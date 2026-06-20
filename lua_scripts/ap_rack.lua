-- Copyright (C) 2025-2026 vibecoder99
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version. See LICENSE for the full text.
-- ============================================================
-- ap_rack.lua -- Echoes of the Worldsoul: Attunement Rack
-- Virtual storage for items accruing attunement at 20% rate.
-- Items stay physically in bags/bank. Only entry tracked here.
-- ============================================================

AP = AP or {}
AP.Rack = AP.Rack or {}

AP.Rack.MAX_SLOTS = 20   -- absolute maximum
AP.Rack.XP_RATE   = 0.20 -- 20% of normal kill XP

-- Expansion tiers: {slots_after_upgrade, essence_cost, residue_cost}
AP.Rack.ExpandTiers = {
    { 5,  500,   0   },  -- Tier 1: 500 Essence
    { 7,  2000,  0   },  -- Tier 2: 2,000 Essence
    { 10, 5000,  0   },  -- Tier 3: 5,000 Essence
    { 13, 0,     15  },  -- Tier 4: 15 Residue
    { 16, 0,     40  },  -- Tier 5: 40 Residue
    { 20, 0,     100 },  -- Tier 6: 100 Residue (max)
}

-- Session cache: guid -> { [slot_index] -> {item_entry, item_name, item_quality} }
AP.Rack.Cache = AP.Rack.Cache or {}

-- ============================================================
-- CAPACITY
-- ============================================================

function AP.Rack.GetCapacity(guid)
    local q = CharDBQuery(string.format(
        "SELECT `rack_slots` FROM `ap_mastery` WHERE `guid` = %d",
        guid
    ))
    if q then
        return tonumber(tostring(q:GetUInt32(0))) or 3
    end
    return 3
end

-- ============================================================
-- LOAD / QUERY
-- ============================================================

function AP.Rack.Load(guid)
    AP.Rack.Cache[guid] = {}
    local q = CharDBQuery(string.format(
        "SELECT `slot_index`,`item_entry`,`item_name`,`item_quality` "..
        "FROM `ap_rack` WHERE `guid` = %d ORDER BY `slot_index`",
        guid
    ))
    if q then
        repeat
            local slot    = tonumber(tostring(q:GetUInt32(0))) or 0
            local entry   = tonumber(tostring(q:GetUInt32(1))) or 0
            local name    = q:GetString(2)
            local quality = tonumber(tostring(q:GetUInt32(3))) or 1
            if slot > 0 and entry > 0 then
                AP.Rack.Cache[guid][slot] = {
                    item_entry   = entry,
                    item_name    = name,
                    item_quality = quality,
                }
            end
        until not q:NextRow()
    end
end

function AP.Rack.CountSlots(guid)
    local count = 0
    local cache = AP.Rack.Cache[guid]
    if not cache then return 0 end
    for _, slot in pairs(cache) do
        if slot and slot.item_entry > 0 then count = count + 1 end
    end
    return count
end

-- Returns list of item entries currently on the Rack for a character
function AP.Rack.GetEntries(guid)
    local entries = {}
    local cache = AP.Rack.Cache[guid]
    if not cache then return entries end
    for _, slot in pairs(cache) do
        if slot.item_entry > 0 then
            entries[#entries + 1] = slot.item_entry
        end
    end
    return entries
end

-- ============================================================
-- ADD / REMOVE
-- ============================================================

function AP.Rack.AddItem(player, itemEntry)
    local guid = player:GetGUIDLow()
    if not AP.Rack.Cache[guid] then AP.Rack.Load(guid) end
    local cache = AP.Rack.Cache[guid]

    -- Validate item entry exists in item_template (hard requirement).
    -- Doubles as the name/quality lookup, replacing the later WorldDBQuery.
    local itemName    = "Unknown Item"
    local itemQuality = 1
    local wq = WorldDBQuery(string.format(
        "SELECT `name`, `Quality`, `class`, `InventoryType` FROM `item_template` WHERE `entry` = %d",
        itemEntry
    ))
    if not wq then
        AP.Voice.Speak(player, "rack_unknown_entry")
        player:SendBroadcastMessage(
            "|cff888888Tip: check the ID with #apfind <name>.|r"
        )
        return false
    end
    itemName    = wq:GetString(0)
    itemQuality = tonumber(tostring(wq:GetUInt32(1))) or 1

    -- EXPLOIT GUARD: only weapons (class=2) and armor (class=4) with a valid equip slot.
    -- Consumables, quest items, reagents, etc. must not enter the Rack — they would
    -- receive 20% kill XP and become attuned, then dissolve-able for infinite Residue.
    local iClass  = tonumber(tostring(wq:GetUInt8(2))) or 0
    local invType = tonumber(tostring(wq:GetUInt32(3))) or 0
    if not ((iClass == 2 or iClass == 4) and invType > 0) then
        player:SendBroadcastMessage(
            "|cffff4444[Worldsoul]|r Only weapons and armor can be placed on the Rack."
        )
        return false
    end

    -- Require physical possession — the Rack tracks items the player carries.
    local hasItem = false
    local possOk = pcall(function()
        hasItem = player:GetItemCount(itemEntry, true) > 0
    end)
    if not possOk or not hasItem then
        AP.Voice.Speak(player, "rack_not_possessed")
        return false
    end

    -- Check if already on Rack
    for _, slot in pairs(cache) do
        if slot.item_entry == itemEntry then
            player:SendBroadcastMessage(
                "|cffffd700[Worldsoul]|r That item is already on the Rack."
            )
            return false
        end
    end

    -- Find empty slot within current capacity
    local capacity  = AP.Rack.GetCapacity(guid)
    local emptySlot = nil
    for i = 1, capacity do
        if not cache[i] or cache[i].item_entry == 0 then
            emptySlot = i
            break
        end
    end

    if not emptySlot then
        player:SendBroadcastMessage(string.format(
            "|cffffd700[Worldsoul]|r The Attunement Rack is full "..
            "(%d/%d slots used). "..
            "Open |cffffff00#ap|r then Attunement Rack to expand it.",
            capacity, capacity
        ))
        return false
    end

    -- Escape apostrophes for SQL only; cache keeps the original display name.
    local itemNameSQL = itemName:gsub("'", "''")
    CharDBExecute(string.format(
        "INSERT INTO `ap_rack` (`guid`,`slot_index`,`item_entry`,"..
        "`item_name`,`item_quality`) VALUES (%d,%d,%d,'%s',%d) "..
        "ON DUPLICATE KEY UPDATE `item_entry`=%d, `item_name`='%s', "..
        "`item_quality`=%d",
        guid, emptySlot, itemEntry, itemNameSQL, itemQuality,
        itemEntry, itemNameSQL, itemQuality
    ))
    CharDBExecute("COMMIT")

    cache[emptySlot] = {
        item_entry   = itemEntry,
        item_name    = itemName,      -- original name, not SQL-escaped
        item_quality = itemQuality,
    }

    player:SendBroadcastMessage(string.format(
        "|cffffd700[Worldsoul]|r %s |cff666666(#%d)|r placed in the Rack "..
        "(slot %d). Its echo begins to form.",
        itemName, itemEntry, emptySlot
    ))
    return true
end

function AP.Rack.RemoveItem(player, slotIndex)
    local guid  = player:GetGUIDLow()
    local cache = AP.Rack.Cache[guid]
    if not cache or not cache[slotIndex] then
        player:SendBroadcastMessage(
            "|cffff4444[Worldsoul]|r No item in that Rack slot."
        )
        return false
    end

    local itemName = cache[slotIndex].item_name

    CharDBExecute(string.format(
        "UPDATE `ap_rack` SET `item_entry`=0, `item_name`='', `item_quality`=1 "..
        "WHERE `guid`=%d AND `slot_index`=%d",
        guid, slotIndex
    ))
    CharDBExecute("COMMIT")
    cache[slotIndex] = nil

    player:SendBroadcastMessage(string.format(
        "|cffffd700[Worldsoul]|r %s removed from the Rack.", itemName
    ))
    return true
end

-- ============================================================
-- XP INTEGRATION (called from ap_events.lua kill loop)
-- ============================================================

function AP.Rack.GetXPRecipients(guid)
    return AP.Rack.GetEntries(guid)
end

-- Check if a Rack item newly reached full attunement; notify player
function AP.Rack.CheckAttuned(player, itemEntry)
    local guid = player:GetGUIDLow()
    local cap = AP.GetScaledCap(itemEntry)
    local q = CharDBQuery(string.format(
        "SELECT `progress`, `attuned` FROM `ap_item_attune` "..
        "WHERE `guid` = %d AND `item_entry` = %d",
        guid, itemEntry
    ))
    if not q then return end

    local progress = tonumber(tostring(q:GetUInt32(0))) or 0
    local attuned  = tonumber(tostring(q:GetUInt32(1))) or 0

    if progress >= cap and attuned == 0 then
        CharDBQuery(string.format(
            "UPDATE `ap_item_attune` SET `attuned`=1 "..
            "WHERE `guid`=%d AND `item_entry`=%d",
            guid, itemEntry
        ))
        CharDBQuery("COMMIT;")

        -- Capture snapshot so the Legacy Forge can list this item.
        -- Normal equip-path attunement creates the snapshot in ap_events.lua;
        -- Rack attunement bypasses that path, so we create it here.
        AP.Try(function()
            local accountId = player:GetAccountId()
            local iq = WorldDBQuery(string.format(
                "SELECT `stat_type1`,`stat_value1`,"..
                "`stat_type2`,`stat_value2`,"..
                "`stat_type3`,`stat_value3`,"..
                "`stat_type4`,`stat_value4`,"..
                "`stat_type5`,`stat_value5`,"..
                "`stat_type6`,`stat_value6`,"..
                "`stat_type7`,`stat_value7`,"..
                "`stat_type8`,`stat_value8`,"..
                "`stat_type9`,`stat_value9`,"..
                "`stat_type10`,`stat_value10`,"..
                "`Quality` "..
                "FROM `item_template` WHERE `entry`=%d LIMIT 1;",
                itemEntry
            ))
            if iq then
                local stats = { str=0, agi=0, sta=0, ["int"]=0, spi=0 }
                for i = 0, 9 do
                    local t = tonumber(iq:GetUInt32(i * 2))     or 0
                    local v = tonumber(iq:GetUInt32(i * 2 + 1)) or 0
                    if     t == 4 then stats.str      = stats.str      + v
                    elseif t == 3 then stats.agi      = stats.agi      + v
                    elseif t == 7 then stats.sta      = stats.sta      + v
                    elseif t == 5 then stats["int"]   = stats["int"]   + v
                    elseif t == 6 then stats.spi      = stats.spi      + v
                    end
                end
                local quality = tonumber(iq:GetUInt8(20)) or 1
                AP.SaveSnapshotAccountWide(guid, itemEntry, quality, stats)
            end
        end, "Rack.CheckAttuned snapshot")

        local itemName = "An item"
        local cache = AP.Rack.Cache[guid]
        if cache then
            for _, slot in pairs(cache) do
                if slot.item_entry == itemEntry then
                    itemName = slot.item_name
                    break
                end
            end
        end

        player:SendBroadcastMessage(string.format(
            "|cff9966ff[Worldsoul]|r %s has fully attuned in the Rack. "..
            "Its echo is ready to be claimed.",
            itemName
        ))

        if AP.Visage and AP.Visage.SendFlash then
            AP.Visage.SendFlash(player,
                "AN ECHO MATURES",
                itemName .. " - attuned through patience."
            )
        end

        if AP.Tutorial and AP.Tutorial.Trigger then
            AP.Tutorial.Trigger(player, "first_rack_attune")
        end
    end
end

-- ============================================================
-- EXPANSION
-- ============================================================

function AP.Rack.Expand(player)
    local guid      = player:GetGUIDLow()
    local accountId = player:GetAccountId()
    local current   = AP.Rack.GetCapacity(guid)

    local nextTier = nil
    for _, tier in ipairs(AP.Rack.ExpandTiers) do
        if tier[1] > current then
            nextTier = tier
            break
        end
    end

    if not nextTier then
        player:SendBroadcastMessage(
            "|cffffd700[Worldsoul]|r The Attunement Rack is at maximum capacity (20 slots)."
        )
        return false
    end

    local newSlots    = nextTier[1]
    local essenceCost = nextTier[2]
    local residueCost = nextTier[3]

    if essenceCost > 0 then
        local aether = 0
        local aq = CharDBQuery(string.format(
            "SELECT `aether` FROM `ap_mastery` WHERE `guid` = %d", guid
        ))
        if aq then aether = tonumber(tostring(aq:GetUInt32(0))) or 0 end

        if aether < essenceCost then
            player:SendBroadcastMessage(string.format(
                "|cffff4444[Worldsoul]|r Not enough Essence. Need %d, have %d.",
                essenceCost, aether
            ))
            return false
        end

        CharDBQuery(string.format(
            "UPDATE `ap_mastery` SET `aether` = `aether` - %d, "..
            "`rack_slots` = %d WHERE `guid` = %d",
            essenceCost, newSlots, guid
        ))
    end

    if residueCost > 0 then
        local residue = AP.Forge and AP.Forge.GetResidue(accountId) or 0

        if residue < residueCost then
            player:SendBroadcastMessage(string.format(
                "|cffff4444[Worldsoul]|r Not enough Worldsoul Residue. "..
                "Need %d, have %d. Visit the Legacy Forge to earn more.",
                residueCost, residue
            ))
            return false
        end

        if AP.Forge then
            AP.Forge.SpendResidue(accountId, residueCost)
            pcall(function() player:RemoveItem(900011, residueCost) end)
        end

        CharDBQuery(string.format(
            "UPDATE `ap_mastery` SET `rack_slots` = %d WHERE `guid` = %d",
            newSlots, guid
        ))
    end

    CharDBQuery("COMMIT;")

    player:SendBroadcastMessage(string.format(
        "|cff9966ff[Worldsoul]|r The Attunement Rack expands. "..
        "|cffffff00%d slots|r now available.",
        newSlots
    ))

    if newSlots >= 13 and AP.Visage and AP.Visage.SendFlash then
        AP.Visage.SendFlash(player,
            "THE RACK GROWS",
            "Your dedication shapes the Worldsoul's gift."
        )
    end

    if AP.Tutorial and AP.Tutorial.Trigger then
        AP.Tutorial.Trigger(player, "first_rack_expand")
    end

    return true
end

-- ============================================================
-- GOSSIP UI
-- Sender range: 240-247
--   240 = Rack main page / non-action items
--   241 = Slot items (code = slot_index → remove)
--   242 = Back to main menu
--   243 = Expand rack
--   244 = Bag picker entry / picker page non-action items
--   245 = Picker list items (code = item_entry → add)
-- ============================================================

local PICKER_QUALITY_COLORS = {
    [0] = "|cff9d9d9d",  -- Gray
    [1] = "|cffffffff",  -- White
    [2] = "|cff1eff00",  -- Green
    [3] = "|cff0070dd",  -- Blue
    [4] = "|cffa335ee",  -- Purple
    [5] = "|cffff8000",  -- Orange/Legendary
    [6] = "|cffe6cc80",  -- Artifact
}

function AP.Rack.ShowPage(player, npc)
    local guid = player:GetGUIDLow()
    if not AP.Rack.Cache[guid] then AP.Rack.Load(guid) end
    local cache    = AP.Rack.Cache[guid]
    local capacity = AP.Rack.GetCapacity(guid)

    player:GossipClearMenu()

    local header = string.format(
        "Attunement Rack -- Items here attune at 20%%%% of normal rate\n"..
        "while you are online and fighting. Items stay in your bags.\n"..
        "Slots used: |cffffff00%d|r / |cffffff00%d|r\n"..
        "Add via |cffffff00\"Add an item from your bags\"|r below, "..
        "or |cffffff00#ap rack <itemEntry>|r for a specific ID.",
        AP.Rack.CountSlots(guid), capacity
    )
    player:GossipMenuAddItem(0, header, 240, 0)

    for i = 1, capacity do
        local slot = cache[i]
        if slot and slot.item_entry > 0 then
            local progress = 0
            local attuned  = false
            local pq = CharDBQuery(string.format(
                "SELECT `progress`,`attuned` FROM `ap_item_attune` "..
                "WHERE `guid`=%d AND `item_entry`=%d",
                guid, slot.item_entry
            ))
            if pq then
                progress = tonumber(tostring(pq:GetUInt32(0))) or 0
                attuned  = (tonumber(tostring(pq:GetUInt32(1))) or 0) == 1
            end

            local cap    = AP.GetScaledCap(slot.item_entry)
            local pct    = math.floor(progress / cap * 100)
            local status = attuned and "|cff00ff00ATTUNED|r" or
                           string.format("|cffffff00%d%%|r", pct)
            local label  = string.format(
                "[%d] %s |cff666666(#%d)|r -- %s  [Remove]",
                i, slot.item_name, slot.item_entry, status
            )
            player:GossipMenuAddItem(0, label, 241, i)
        else
            player:GossipMenuAddItem(0,
                string.format("[%d] Empty slot", i),
                240, 0)
        end
    end

    -- Bag picker entry point
    player:GossipMenuAddItem(0, "Add an item from your bags", 244, 0)

    -- Next expansion tier
    local nextTier = nil
    for _, tier in ipairs(AP.Rack.ExpandTiers) do
        if tier[1] > capacity then
            nextTier = tier
            break
        end
    end

    if nextTier then
        local costStr
        if nextTier[2] > 0 then
            costStr = string.format("%d Essence", nextTier[2])
        else
            costStr = string.format("%d Worldsoul Residue", nextTier[3])
        end
        player:GossipMenuAddItem(0, string.format(
            "Expand Rack to %d slots (%s)",
            nextTier[1], costStr
        ), 243, 0)
    else
        player:GossipMenuAddItem(0,
            "|cff888888Rack at maximum capacity (20 slots)|r",
            240, 0)
    end

    player:GossipMenuAddItem(0, "<< Back to Main Menu", 242, 0)
    player:GossipSendMenu(1, npc, 240)
end

function AP.Rack.ShowPickerPage(player, npc)
    local guid = player:GetGUIDLow()
    if not AP.Rack.Cache[guid] then AP.Rack.Load(guid) end
    local cache    = AP.Rack.Cache[guid]
    local capacity = AP.Rack.GetCapacity(guid)

    player:GossipClearMenu()

    -- Rack full: no point scanning bags.
    local used = AP.Rack.CountSlots(guid)
    if used >= capacity then
        player:GossipMenuAddItem(0, string.format(
            "The Rack is full (%d/%d slots). "..
            "Expand it or remove an item before adding another.",
            used, capacity), 244, 0)
        player:GossipMenuAddItem(0, "<< Back to Rack", 240, 0)
        player:GossipSendMenu(1, npc, 244)
        return
    end

    -- Items already on the Rack (memory lookup, no DB hit).
    local onRack = {}
    for _, slot in pairs(cache) do
        if slot and slot.item_entry > 0 then
            onRack[slot.item_entry] = true
        end
    end

    -- Fully-attuned entries for this character (one batch query).
    local attuned = {}
    local aq = CharDBQuery(string.format(
        "SELECT `item_entry` FROM `ap_item_attune` "..
        "WHERE `guid` = %d AND `attuned` = 1", guid))
    if aq then
        repeat
            local e = tonumber(tostring(aq:GetUInt32(0))) or 0
            if e > 0 then attuned[e] = true end
        until not aq:NextRow()
    end

    -- GetBagSize does not exist in this Eluna build.
    -- Use GetItemByPos with C++ slot constants directly:
    --   bag=255 (NULL_BAG), slots 23-38: the 16 backpack item slots
    --   bag=19-22: equipped bag containers, slots 0-35 per bag
    -- Empty and out-of-range slots return nil and are skipped safely.
    local candidates  = {}
    local seenEntries = {}

    local function scanSlot(bag, slot)
        local item = nil
        pcall(function() item = player:GetItemByPos(bag, slot) end)
        if not item then return end
        local entry = 0
        pcall(function() entry = item:GetEntry() end)
        if entry > 0 and not seenEntries[entry]
                and not onRack[entry] and not attuned[entry] then
            seenEntries[entry] = true
            local wq = WorldDBQuery(string.format(
                "SELECT `name`, `Quality`, `class`, `InventoryType` "..
                "FROM `item_template` WHERE `entry` = %d LIMIT 1", entry))
            if wq then
                local iClass  = tonumber(tostring(wq:GetUInt8(2)))  or 0
                local invType = tonumber(tostring(wq:GetUInt32(3))) or 0
                if (iClass == 2 or iClass == 4) and invType > 0 then
                    candidates[#candidates + 1] = {
                        entry   = entry,
                        name    = wq:GetString(0) or ("Item " .. entry),
                        quality = tonumber(tostring(wq:GetUInt8(1))) or 1,
                    }
                end
            end
        end
    end

    for slot = 23, 38 do          -- backpack: 16 slots
        scanSlot(255, slot)
    end
    for bagSlot = 19, 22 do       -- equipped bag containers: up to 36 slots each
        for slot = 0, 35 do
            scanSlot(bagSlot, slot)
        end
    end

    if #candidates == 0 then
        player:GossipMenuAddItem(0,
            "Nothing in your bags is eligible for the Rack right now.",
            244, 0)
        player:GossipMenuAddItem(0, "<< Back to Rack", 240, 0)
        player:GossipSendMenu(1, npc, 244)
        return
    end

    -- Sort by quality descending, then alphabetically.
    table.sort(candidates, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.name < b.name
    end)

    local shown = math.min(#candidates, 10)
    for i = 1, shown do
        local c     = candidates[i]
        local color = PICKER_QUALITY_COLORS[c.quality] or PICKER_QUALITY_COLORS[1]
        player:GossipMenuAddItem(0,
            string.format("%s%s|r", color, c.name),
            245, c.entry)
    end

    if #candidates > 10 then
        player:GossipMenuAddItem(0, string.format(
            "...and %d more. Narrow down by removing gear first, "..
            "or use |cffffff00#ap rack <item ID>|r directly.",
            #candidates - 10), 244, 0)
    end

    player:GossipMenuAddItem(0, "<< Back to Rack", 240, 0)
    player:GossipSendMenu(1, npc, 244)
end

function AP.Rack.OnSelect(player, npc, sender, code)
    if sender == 240 then
        AP.Rack.ShowPage(player, npc)
    elseif sender == 241 then
        AP.Rack.RemoveItem(player, code)
        AP.Rack.ShowPage(player, npc)
    elseif sender == 242 then
        if AP.OpenUI then AP.OpenUI(player) end
    elseif sender == 243 then
        AP.Rack.Expand(player)
        AP.Rack.ShowPage(player, npc)
    elseif sender == 244 then
        AP.Rack.ShowPickerPage(player, npc)
    elseif sender == 245 then
        AP.Rack.AddItem(player, code)
        AP.Rack.ShowPage(player, npc)
    end
end

-- ============================================================
-- LOGIN HOOK
-- ============================================================

local function OnLogin_Rack(event, player)
    local ok, err = pcall(function()
        AP.Rack.Load(player:GetGUIDLow())
    end)
    if not ok then
        print("[EotW Rack] ERROR in OnLogin_Rack: " .. tostring(err))
    end
end

RegisterPlayerEvent(3, OnLogin_Rack)

print("[EotW] Attunement Rack loaded. Max slots: " .. AP.Rack.MAX_SLOTS)
