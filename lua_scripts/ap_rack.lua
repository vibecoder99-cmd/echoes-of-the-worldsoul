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

local function FindNextExpandTier(current)
    for _, tier in ipairs(AP.Rack.ExpandTiers) do
        if tier[1] > current then return tier end
    end
    return nil
end

-- Session cache: guid -> { [slot_index] -> {item_entry, item_name, item_quality} }
AP.Rack.Cache = AP.Rack.Cache or {}

-- ============================================================
-- CAPACITY
-- ============================================================

function AP.Rack.GetCapacity(guid)
    local q = AP.DB.Query(string.format(
        "SELECT `rack_slots` FROM `ap_mastery` WHERE `guid` = %d",
        guid
    ))
    if q then
        return tonumber(tostring(q:GetUInt32(0))) or 3
    end
    return 3
end

function AP.Rack.PreviewExpand(player)
    if not player then return { ok = false, status = "SERVICE_UNAVAILABLE" } end
    local guid = AP.RT.GetGUID(player)
    local accountId = AP.RT.GetAccountId(player)
    if not guid or not accountId then
        return { ok = false, status = "SERVICE_UNAVAILABLE" }
    end

    local q = AP.DB.Query(string.format(
        "SELECT `rack_slots` FROM `ap_mastery` WHERE `guid` = %d", guid))
    if not q then return { ok = false, status = "SERVICE_UNAVAILABLE" } end
    local current = tonumber(tostring(q:GetUInt32(0)))
    if current == nil then return { ok = false, status = "SERVICE_UNAVAILABLE" } end

    local tier = FindNextExpandTier(current)
    if not tier then
        return { ok = true, status = "AT_MAX", atMaxCapacity = true,
                 currentSlots = current, expectedResidue = nil }
    end

    local expectedResidue = nil
    local expectedEssence = nil
    if tier[2] > 0 then
        local aq = AP.DB.Query(string.format(
            "SELECT `aether` FROM `ap_mastery` WHERE `guid` = %d", guid))
        if not aq then return { ok = false, status = "SERVICE_UNAVAILABLE" } end
        expectedEssence = tonumber(tostring(aq:GetUInt32(0)))
        if expectedEssence == nil then return { ok = false, status = "SERVICE_UNAVAILABLE" } end
    end
    if tier[3] > 0 then
        local residueOk
        residueOk, expectedResidue = AP.Forge.GetVerifiedResidue(accountId)
        if not residueOk then return { ok = false, status = "SERVICE_UNAVAILABLE" } end
    end

    return {
        ok = true,
        status = "READY",
        atMaxCapacity = false,
        currentSlots = current,
        nextSlots = tier[1],
        essenceCost = tier[2],
        residueCost = tier[3],
        expectedEssence = expectedEssence,
        expectedResidue = expectedResidue,
    }
end

-- Atomic Essence-tier expansion. This is deliberately separate from the
-- Residue service above: both paths use an exact-balance compare-and-swap and
-- read-after-write verification, and neither can report success merely because
-- a SQL call was submitted.
function AP.Rack.PurchaseEssenceExpand(player, expectedCurrent, expectedNext, expectedEssence)
    local result = { ok = false, status = "SERVICE_UNAVAILABLE" }
    if not player or type(expectedCurrent) ~= "number" or type(expectedNext) ~= "number" or
            type(expectedEssence) ~= "number" then
        return result
    end
    expectedCurrent = math.floor(expectedCurrent)
    expectedNext = math.floor(expectedNext)
    expectedEssence = math.floor(expectedEssence)
    local tier = FindNextExpandTier(expectedCurrent)
    if not tier or tier[1] ~= expectedNext or tier[2] <= 0 or tier[3] ~= 0 then
        result.status = "INELIGIBLE"
        return result
    end
    local guid = AP.RT.GetGUID(player)
    local cost = tier[2]
    result.cost, result.oldSlots, result.newSlots = cost, expectedCurrent, expectedNext
    result.oldBalance = expectedEssence
    if not guid then return result end
    if expectedEssence < cost then
        result.status = "INSUFFICIENT_ESSENCE"
        return result
    end
    local before = AP.DB.Query(string.format(
        "SELECT `rack_slots`, `aether` FROM `ap_mastery` WHERE `guid` = %d", guid))
    local slotsBefore = before and tonumber(tostring(before:GetUInt32(0)))
    local essenceBefore = before and tonumber(tostring(before:GetUInt32(1)))
    if not before then result.status = "SERVICE_UNAVAILABLE"; return result end
    if slotsBefore ~= expectedCurrent or essenceBefore ~= expectedEssence then
        result.status = "STALE_PREVIEW"
        result.newBalance = essenceBefore
        return result
    end
    local wrote = AP.DB.ExecuteCritical(string.format(
        "UPDATE `ap_mastery` SET `aether` = `aether` - %d, `rack_slots` = %d "..
        "WHERE `guid` = %d AND `rack_slots` = %d AND `aether` = %d AND `aether` >= %d",
        cost, expectedNext, guid, expectedCurrent, expectedEssence, cost),
        "AP.Rack.PurchaseEssenceExpand")
    if not wrote then result.status = "DATABASE_FAILURE"; return result end
    local after = AP.DB.Query(string.format(
        "SELECT `rack_slots`, `aether` FROM `ap_mastery` WHERE `guid` = %d", guid))
    if not after then result.status = "POST_VERIFY_FAILURE"; return result end
    local slotsAfter = tonumber(tostring(after:GetUInt32(0)))
    local essenceAfter = tonumber(tostring(after:GetUInt32(1)))
    if slotsAfter ~= expectedNext or essenceAfter ~= expectedEssence - cost then
        result.status = "STALE_PREVIEW"
        result.newBalance = essenceAfter
        return result
    end
    result.ok, result.status, result.newBalance = true, "SUCCESS", essenceAfter
    return result
end

function AP.Rack.PurchaseExpand(player, expectedCurrent, expectedNext, expectedResidue)
    local result = { ok = false, status = "SERVICE_UNAVAILABLE", physicalSynced = false }
    if not player or type(expectedCurrent) ~= "number" or type(expectedNext) ~= "number" or
            type(expectedResidue) ~= "number" then
        return result
    end

    expectedCurrent = math.floor(expectedCurrent)
    expectedNext = math.floor(expectedNext)
    expectedResidue = math.floor(expectedResidue)
    local tier = FindNextExpandTier(expectedCurrent)
    if not tier or tier[1] ~= expectedNext or tier[2] ~= 0 or tier[3] <= 0 then
        result.status = "INELIGIBLE"
        return result
    end

    local guid = AP.RT.GetGUID(player)
    local accountId = AP.RT.GetAccountId(player)
    local cost = tier[3]
    result.cost = cost
    result.oldSlots = expectedCurrent
    result.newSlots = expectedNext
    result.oldBalance = expectedResidue
    if not guid or not accountId then return result end
    if expectedResidue < cost then
        result.status = "INSUFFICIENT_RESIDUE"
        return result
    end

    local before = AP.DB.Query(string.format(
        "SELECT m.`rack_slots`, r.`amount` FROM `ap_mastery` AS m "..
        "JOIN `ap_residue` AS r ON r.`account_id` = %d WHERE m.`guid` = %d",
        accountId, guid))
    local slotsBefore = before and tonumber(tostring(before:GetUInt32(0)))
    local residueBefore = before and tonumber(tostring(before:GetUInt32(1)))
    if not before then result.status = "SERVICE_UNAVAILABLE"; return result end
    if slotsBefore ~= expectedCurrent or residueBefore ~= expectedResidue then
        result.status = "STALE_PREVIEW"
        result.newBalance = residueBefore
        return result
    end

    local wrote = AP.DB.ExecuteCritical(string.format(
        "UPDATE `ap_mastery` AS m JOIN `ap_residue` AS r ON r.`account_id` = %d "..
        "SET m.`rack_slots` = %d, r.`amount` = r.`amount` - %d "..
        "WHERE m.`guid` = %d AND m.`rack_slots` = %d "..
        "AND r.`amount` = %d AND r.`amount` >= %d",
        accountId, expectedNext, cost, guid, expectedCurrent, expectedResidue, cost),
        "AP.Rack.PurchaseExpand")
    if not wrote then result.status = "DATABASE_FAILURE"; return result end

    local after = AP.DB.Query(string.format(
        "SELECT m.`rack_slots`, r.`amount` FROM `ap_mastery` AS m "..
        "JOIN `ap_residue` AS r ON r.`account_id` = %d WHERE m.`guid` = %d",
        accountId, guid))
    if not after then result.status = "POST_VERIFY_FAILURE"; return result end
    local slotsAfter = tonumber(tostring(after:GetUInt32(0)))
    local residueAfter = tonumber(tostring(after:GetUInt32(1)))
    local targetResidue = expectedResidue - cost
    if slotsAfter ~= expectedNext or residueAfter ~= targetResidue then
        result.status = "STALE_PREVIEW"
        result.newBalance = residueAfter
        result.physicalSynced, result.physicalReason =
            AP.Forge.SyncResidueAccountRepresentations(player, accountId, residueAfter)
        return result
    end

    result.ok = true
    result.status = "SUCCESS"
    result.newBalance = residueAfter
    result.physicalSynced, result.physicalReason =
        AP.Forge.SyncResidueAccountRepresentations(player, accountId, residueAfter)
    return result
end

-- ============================================================
-- LOAD / QUERY
-- ============================================================

function AP.Rack.Load(guid)
    AP.Rack.Cache[guid] = {}
    local q = AP.DB.Query(string.format(
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
    local guid = AP.RT.GetGUID(player)
    if not AP.Rack.Cache[guid] then AP.Rack.Load(guid) end
    local cache = AP.Rack.Cache[guid]

    -- Validate item entry exists in item_template (hard requirement).
    -- Doubles as the name/quality lookup, replacing the later WorldDBQuery.
    local itemName    = "Unknown Item"
    local itemQuality = 1
    local wq = AP.DB.WorldQuery(string.format(
        "SELECT `name`, `Quality`, `class`, `InventoryType` FROM `item_template` WHERE `entry` = %d",
        itemEntry
    ))
    if not wq then
        AP.Voice.Speak(player, "rack_unknown_entry")
        AP.RT.SendMessage(player,
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
        AP.RT.SendMessage(player,
            "|cffff4444[Worldsoul]|r Only weapons and armor can be placed on the Rack."
        )
        return false
    end

    -- Require physical possession — the Rack tracks items the player carries.
    local hasItem = false
    local possOk = pcall(function()
        hasItem = AP.RT.GetItemCount(player,itemEntry, true) > 0
    end)
    if not possOk or not hasItem then
        AP.Voice.Speak(player, "rack_not_possessed")
        return false
    end

    -- Check if already on Rack
    for _, slot in pairs(cache) do
        if slot.item_entry == itemEntry then
            AP.RT.SendMessage(player,
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
        AP.RT.SendMessage(player,string.format(
            "|cffffd700[Worldsoul]|r The Attunement Rack is full "..
            "(%d/%d slots used). "..
            "Open |cffffff00#ap|r then Attunement Rack to expand it.",
            capacity, capacity
        ))
        return false
    end

    -- Escape apostrophes for SQL only; cache keeps the original display name.
    local itemNameSQL = itemName:gsub("'", "''")
    AP.DB.ExecuteAsync(string.format(
        "INSERT INTO `ap_rack` (`guid`,`slot_index`,`item_entry`,"..
        "`item_name`,`item_quality`) VALUES (%d,%d,%d,'%s',%d) "..
        "ON DUPLICATE KEY UPDATE `item_entry`=%d, `item_name`='%s', "..
        "`item_quality`=%d",
        guid, emptySlot, itemEntry, itemNameSQL, itemQuality,
        itemEntry, itemNameSQL, itemQuality
    ))
    AP.DB.ExecuteAsync("COMMIT")

    cache[emptySlot] = {
        item_entry   = itemEntry,
        item_name    = itemName,      -- original name, not SQL-escaped
        item_quality = itemQuality,
    }

    AP.RT.SendMessage(player,string.format(
        "|cffffd700[Worldsoul]|r %s |cff666666(#%d)|r placed in the Rack "..
        "(slot %d). Its echo begins to form.",
        itemName, itemEntry, emptySlot
    ))
    return true
end

function AP.Rack.RemoveItem(player, slotIndex)
    local guid  = AP.RT.GetGUID(player)
    local cache = AP.Rack.Cache[guid]
    if not cache or not cache[slotIndex] then
        AP.RT.SendMessage(player,
            "|cffff4444[Worldsoul]|r No item in that Rack slot."
        )
        return false
    end

    local itemName = cache[slotIndex].item_name

    AP.DB.ExecuteAsync(string.format(
        "UPDATE `ap_rack` SET `item_entry`=0, `item_name`='', `item_quality`=1 "..
        "WHERE `guid`=%d AND `slot_index`=%d",
        guid, slotIndex
    ))
    AP.DB.ExecuteAsync("COMMIT")
    cache[slotIndex] = nil

    AP.RT.SendMessage(player,string.format(
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
    local guid = AP.RT.GetGUID(player)
    local cap = AP.GetScaledCap(itemEntry)
    local q = AP.DB.Query(string.format(
        "SELECT `progress`, `attuned` FROM `ap_item_attune` "..
        "WHERE `guid` = %d AND `item_entry` = %d",
        guid, itemEntry
    ))
    if not q then return end

    local progress = tonumber(tostring(q:GetUInt32(0))) or 0
    local attuned  = tonumber(tostring(q:GetUInt32(1))) or 0

    if progress >= cap and attuned == 0 then
        AP.DB.ExecuteCritical(string.format(
            "UPDATE `ap_item_attune` SET `attuned`=1 "..
            "WHERE `guid`=%d AND `item_entry`=%d",
            guid, itemEntry
        ))
        AP.DB.Execute("COMMIT;")

        -- Capture snapshot so the Legacy Forge can list this item.
        -- Normal equip-path attunement creates the snapshot in ap_events.lua;
        -- Rack attunement bypasses that path, so we create it here.
        AP.Try(function()
            local accountId = AP.RT.GetAccountId(player)
            local iq = AP.DB.WorldQuery(string.format(
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

        AP.RT.SendMessage(player,string.format(
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
    local guid = AP.RT.GetGUID(player)
    local preview = AP.Rack.PreviewExpand(player)
    if not preview.ok then
        AP.RT.SendMessage(player,
            "|cffff4444[Worldsoul]|r Rack expansion state is unavailable. Nothing was spent.")
        return false
    end
    if preview.atMaxCapacity then
        AP.RT.SendMessage(player,
            "|cffffd700[Worldsoul]|r The Attunement Rack is at maximum capacity (20 slots)."
        )
        return false
    end

    local newSlots    = preview.nextSlots
    local essenceCost = preview.essenceCost
    local residueCost = preview.residueCost

    if essenceCost > 0 then
        local aether = 0
        local aq = AP.DB.Query(string.format(
            "SELECT `aether` FROM `ap_mastery` WHERE `guid` = %d", guid
        ))
        if aq then aether = tonumber(tostring(aq:GetUInt32(0))) or 0 end

        if aether < essenceCost then
            AP.RT.SendMessage(player,string.format(
                "|cffff4444[Worldsoul]|r Not enough Essence. Need %d, have %d.",
                essenceCost, aether
            ))
            return false
        end

        local purchase = AP.Rack.PurchaseEssenceExpand(
            player, preview.currentSlots, preview.nextSlots, preview.expectedEssence)
        if not purchase.ok then
            AP.RT.SendMessage(player,
                "|cffff4444[Worldsoul]|r Rack expansion could not be committed. Nothing was spent.")
            return false
        end
    end

    if residueCost > 0 then
        if preview.expectedResidue < residueCost then
            AP.RT.SendMessage(player,string.format(
                "|cffff4444[Worldsoul]|r Not enough Worldsoul Residue. "..
                "Need %d, have %d. Visit the Legacy Forge to earn more.",
                residueCost, preview.expectedResidue
            ))
            return false
        end

        local purchase = AP.Rack.PurchaseExpand(
            player, preview.currentSlots, preview.nextSlots, preview.expectedResidue)
        if not purchase.ok then
            AP.RT.SendMessage(player,
                "|cffff4444[Worldsoul]|r Rack expansion could not be committed. Nothing was spent.")
            return false
        end
    end

    AP.RT.SendMessage(player,string.format(
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
    local guid = AP.RT.GetGUID(player)
    if not AP.Rack.Cache[guid] then AP.Rack.Load(guid) end
    local cache    = AP.Rack.Cache[guid]
    local capacity = AP.Rack.GetCapacity(guid)

    AP.UI.ClearMenu(player)

    local header = string.format(
        "Attunement Rack -- Items here attune at 20%%%% of normal rate\n"..
        "while you are online and fighting. Items stay in your bags.\n"..
        "Slots used: |cffffff00%d|r / |cffffff00%d|r\n"..
        "Add via |cffffff00\"Add an item from your bags\"|r below, "..
        "or |cffffff00#ap rack <itemEntry>|r for a specific ID.",
        AP.Rack.CountSlots(guid), capacity
    )
    AP.UI.AddItem(player,0, header, 240, 0)

    for i = 1, capacity do
        local slot = cache[i]
        if slot and slot.item_entry > 0 then
            local progress = 0
            local attuned  = false
            local pq = AP.DB.Query(string.format(
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
            AP.UI.AddItem(player,0, label, 241, i)
        else
            AP.UI.AddItem(player,0,
                string.format("[%d] Empty slot", i),
                240, 0)
        end
    end

    -- Bag picker entry point
    AP.UI.AddItem(player,0, "Add an item from your bags", 244, 0)

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
        AP.UI.AddItem(player,0, string.format(
            "Expand Rack to %d slots (%s)",
            nextTier[1], costStr
        ), 243, 0)
    else
        AP.UI.AddItem(player,0,
            "|cff888888Rack at maximum capacity (20 slots)|r",
            240, 0)
    end

    AP.UI.AddItem(player,0, "<< Back to Main Menu", 242, 0)
    AP.UI.SendMenu(player,1, npc, 240)
end

function AP.Rack.ShowPickerPage(player, npc)
    local guid = AP.RT.GetGUID(player)
    if not AP.Rack.Cache[guid] then AP.Rack.Load(guid) end
    local cache    = AP.Rack.Cache[guid]
    local capacity = AP.Rack.GetCapacity(guid)

    AP.UI.ClearMenu(player)

    -- Rack full: no point scanning bags.
    local used = AP.Rack.CountSlots(guid)
    if used >= capacity then
        AP.UI.AddItem(player,0, string.format(
            "The Rack is full (%d/%d slots). "..
            "Expand it or remove an item before adding another.",
            used, capacity), 244, 0)
        AP.UI.AddItem(player,0, "<< Back to Rack", 240, 0)
        AP.UI.SendMenu(player,1, npc, 244)
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
    local aq = AP.DB.Query(string.format(
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
        pcall(function() item = AP.RT.GetItemByPos(player,bag, slot) end)
        if not item then return end
        local entry = 0
        pcall(function() entry = AP.RT.GetItemEntry(item) end)
        if entry > 0 and not seenEntries[entry]
                and not onRack[entry] and not attuned[entry] then
            seenEntries[entry] = true
            local wq = AP.DB.WorldQuery(string.format(
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
        AP.UI.AddItem(player,0,
            "Nothing in your bags is eligible for the Rack right now.",
            244, 0)
        AP.UI.AddItem(player,0, "<< Back to Rack", 240, 0)
        AP.UI.SendMenu(player,1, npc, 244)
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
        AP.UI.AddItem(player,0,
            string.format("%s%s|r", color, c.name),
            245, c.entry)
    end

    if #candidates > 10 then
        AP.UI.AddItem(player,0, string.format(
            "...and %d more. Narrow down by removing gear first, "..
            "or use |cffffff00#ap rack <item ID>|r directly.",
            #candidates - 10), 244, 0)
    end

    AP.UI.AddItem(player,0, "<< Back to Rack", 240, 0)
    AP.UI.SendMenu(player,1, npc, 244)
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
        AP.Rack.Load(AP.RT.GetGUID(player))
    end)
    if not ok then
        print("[EotW Rack] ERROR in OnLogin_Rack: " .. tostring(err))
    end
end

AP.RT.RegisterEvent("player", 3, OnLogin_Rack)

print("[EotW] Attunement Rack loaded. Max slots: " .. AP.Rack.MAX_SLOTS)
