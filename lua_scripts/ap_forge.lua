-- Copyright (C) 2025-2026 vibecoder99
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version. See LICENSE for the full text.
-- ============================================================
-- ap_forge.lua -- Echoes of the Worldsoul: Legacy Forge
-- Deliberate dissolution of fully-attuned items into
-- Essence, gold, and Worldsoul Residue.
-- Player-initiated only. Confirmation required.
-- ============================================================

AP = AP or {}
AP.Forge = AP.Forge or {}

local RESIDUE_ITEM_ENTRY = 900011

-- Dissolution rewards by quality
AP.Forge.Rewards = {
    [0] = { essence = 50,    gold = 500,    residue = 0  },  -- Poor
    [1] = { essence = 150,   gold = 5000,   residue = 1  },  -- Common
    [2] = { essence = 400,   gold = 20000,  residue = 3  },  -- Uncommon
    [3] = { essence = 1000,  gold = 80000,  residue = 8  },  -- Rare
    [4] = { essence = 2500,  gold = 200000, residue = 20 },  -- Epic
    [5] = { essence = 6000,  gold = 500000, residue = 50 },  -- Legendary
}

-- Residue spending costs
AP.Forge.ResidueCosts = {
    slot_empower      = 50,
    echo_crystal      = 30,
    crucible_catalyst = 10,  -- 10 Residue -> 5000 Essence
}

-- Pending dissolution confirmation: guid -> {itemEntry, quality, name}
AP.Forge.Pending = {}

-- ============================================================
-- RESIDUE BALANCE
-- ============================================================

function AP.Forge.GetResidue(accountId)
    local q = CharDBQuery(string.format(
        "SELECT `amount` FROM `ap_residue` WHERE `account_id` = %d",
        accountId
    ))
    if q then return tonumber(tostring(q:GetUInt32(0))) or 0 end
    return 0
end

function AP.Forge.AddResidue(player, amount)
    local accountId = player:GetAccountId()
    CharDBExecute(string.format(
        "INSERT INTO `ap_residue` (`account_id`, `amount`) VALUES (%d, %d) "..
        "ON DUPLICATE KEY UPDATE `amount` = `amount` + %d",
        accountId, amount, amount
    ))
    pcall(function() player:AddItem(RESIDUE_ITEM_ENTRY, amount) end)
    CharDBExecute("COMMIT")
    -- Force a character DB save so the physical item survives a client crash
    -- before AzerothCore's autosave tick (typically 15 min).
    pcall(function() player:SaveToDB(false, false) end)
end

function AP.Forge.SpendResidue(accountId, amount)
    local current = AP.Forge.GetResidue(accountId)
    if current < amount then return false end
    CharDBExecute(string.format(
        "UPDATE `ap_residue` SET `amount` = `amount` - %d "..
        "WHERE `account_id` = %d",
        amount, accountId
    ))
    CharDBExecute("COMMIT")
    return true
end

-- ============================================================
-- GOSSIP UI
-- Sender range: 250-255
-- ============================================================

function AP.Forge.ShowPage(player, npc)
    local guid      = player:GetGUIDLow()
    local accountId = player:GetAccountId()
    local residue   = AP.Forge.GetResidue(accountId)

    player:GossipClearMenu()

    player:GossipMenuAddItem(0, string.format(
        "Legacy Forge -- Return attuned items to the Worldsoul.\n"..
        "Receive Essence, gold, and Worldsoul Residue in return.\n"..
        "Your Residue: |cffffff00%d|r\n"..
        "Each item entry can only be dissolved once per account.\n"..
        "Only fully-attuned, undissolved items appear here.",
        residue
    ), 250, 0)

    -- Build a set of currently equipped item entries so we can exclude them.
    -- Equipped items cannot be dissolved (would require unequipping first).
    local equippedEntries = {}
    pcall(function()
        for slot = 0, 18 do
            local eq = player:GetEquippedItemBySlot(slot)
            if eq then
                equippedEntries[eq:GetEntry()] = true
            end
        end
    end)

    -- Exclude entries already dissolved on this account via LEFT JOIN.
    local q = CharDBQuery(string.format(
        "SELECT a.item_entry, s.quality "..
        "FROM ap_item_attune a "..
        "JOIN ap_item_snapshot s ON s.guid = %d "..
        "  AND s.item_entry = a.item_entry "..
        "LEFT JOIN ap_dissolved_items d "..
        "  ON d.account_id = %d AND d.item_entry = a.item_entry "..
        "WHERE a.guid = %d AND a.attuned = 1 AND d.account_id IS NULL "..
        "ORDER BY s.quality DESC, a.item_entry ASC",
        accountId, accountId, guid
    ))

    local count = 0
    if q then
        repeat
            local entry   = tonumber(tostring(q:GetUInt32(0))) or 0
            local quality = tonumber(tostring(q:GetUInt32(1))) or 1
            if entry > 0 and not equippedEntries[entry] then
                -- Verify the item is physically in bags/bank right now.
                -- A player may have an attuned record for an item they
                -- already vendored or disenchanted through normal means.
                local itemObj = nil
                pcall(function() itemObj = player:GetItemByEntry(entry) end)
                if itemObj then
                    local itemName = "Unknown Item"
                    local wq = WorldDBQuery(string.format(
                        "SELECT `name`, `class`, `InventoryType` FROM `item_template` WHERE `entry` = %d",
                        entry
                    ))
                    if wq then
                        itemName = wq:GetString(0)
                        local iClass  = tonumber(tostring(wq:GetUInt8(1)))  or 0
                        local invType = tonumber(tostring(wq:GetUInt32(2))) or 0
                        if (iClass == 2 or iClass == 4) and invType > 0 then
                            local rewards = AP.Forge.Rewards[quality] or AP.Forge.Rewards[1]
                            local goldG   = math.floor(rewards.gold / 10000)
                            local goldS   = math.floor((rewards.gold % 10000) / 100)

                            local label = string.format(
                                "%s |cff666666(#%d)|r\n+%d Essence, +%dg %ds, +%d Residue",
                                itemName, entry,
                                rewards.essence,
                                goldG, goldS,
                                rewards.residue
                            )
                            player:GossipMenuAddItem(0, label, 251, entry)
                            count = count + 1
                        end
                    end
                end
            end
        until not q:NextRow() or count >= 8
    end

    if count == 0 then
        player:GossipMenuAddItem(0,
            "Nothing ready to dissolve.\n"..
            "Fully attune items through combat or the Rack, then return.",
            250, 0)
    end

    -- Crucible Catalyst spend option
    if residue >= AP.Forge.ResidueCosts.crucible_catalyst then
        player:GossipMenuAddItem(0, string.format(
            "Spend %d Residue\n+5,000 Essence (Crucible Catalyst)",
            AP.Forge.ResidueCosts.crucible_catalyst
        ), 253, 1)
    end

    player:GossipMenuAddItem(0, "<< Back to Main Menu", 254, 0)
    player:GossipSendMenu(1, npc, 250)
end

-- Confirmation page before dissolution
function AP.Forge.ShowConfirm(player, npc, itemEntry)
    local quality  = 1
    local itemName = "Unknown Item"

    local wq = WorldDBQuery(string.format(
        "SELECT `name`, `Quality` FROM `item_template` WHERE `entry` = %d",
        itemEntry
    ))
    if wq then
        itemName = wq:GetString(0)
        quality  = tonumber(tostring(wq:GetUInt32(1))) or 1
    end

    local rewards = AP.Forge.Rewards[quality] or AP.Forge.Rewards[1]
    local goldG   = math.floor(rewards.gold / 10000)
    local goldS   = math.floor((rewards.gold % 10000) / 100)

    local guid = player:GetGUIDLow()
    AP.Forge.Pending[guid] = {
        itemEntry = itemEntry,
        quality   = quality,
        name      = itemName,
    }

    player:GossipClearMenu()
    player:GossipMenuAddItem(0, string.format(
        "Dissolve: %s\n\n"..
        "This item's echo has been claimed.\n"..
        "Returning its husk to the Worldsoul is permanent.\n\n"..
        "You will receive:\n"..
        "  +%d Essence\n"..
        "  +%dg %ds\n"..
        "  +%d Worldsoul Residue\n\n"..
        "This cannot be undone.",
        itemName,
        rewards.essence,
        goldG, goldS,
        rewards.residue
    ), 250, 0)

    player:GossipMenuAddItem(0, "Dissolve into the Worldsoul", 252, itemEntry)
    player:GossipMenuAddItem(0, "Keep this item",              255, 0)

    player:GossipSendMenu(1, npc, 250)
end

-- Execute dissolution
-- Ordering is load-bearing for exploit safety:
--   1. Verify pending state
--   2. Check ap_dissolved_items â€" abort cleanly (player keeps item) if already dissolved
--   3. Verify physical item in inventory â€" abort if missing
--   4. Remove physical item
--   5. Record in ap_dissolved_items BEFORE any reward grants
--   6. Grant rewards
function AP.Forge.Dissolve(player, npc, itemEntry)
    local guid      = player:GetGUIDLow()
    local accountId = player:GetAccountId()
    local pending   = AP.Forge.Pending[guid]

    if not pending or pending.itemEntry ~= itemEntry then
        player:SendBroadcastMessage(
            "|cffff4444[Worldsoul]|r The dissolution did not complete. Please try again."
        )
        AP.Forge.ShowPage(player, npc)
        return
    end

    -- Step 1: Guard against already-dissolved entries.
    -- ShowPage filters these out, so this path is purely defensive
    -- (stale gossip state, race conditions, direct exploit attempts).
    -- Player keeps the item â€" no reward, no removal.
    local alreadyDissolved = CharDBQuery(string.format(
        "SELECT 1 FROM `ap_dissolved_items` "..
        "WHERE `account_id` = %d AND `item_entry` = %d",
        accountId, itemEntry
    ))
    if alreadyDissolved then
        AP.Voice.Speak(player, "already_dissolved")
        AP.Forge.Pending[guid] = nil
        AP.Forge.ShowPage(player, npc)
        return
    end

    -- Re-verify the item is actually attuned on this character. ShowPage only
    -- lists attuned items, but a stale confirm page combined with an item
    -- swap (attune a second copy via other means, then dissolve the un-attuned
    -- copy) could reach here without a genuine echo having been earned.
    local attuneRow = CharDBQuery(string.format(
        "SELECT 1 FROM `ap_item_attune` WHERE `guid` = %d "..
        "AND `item_entry` = %d AND `attuned` = 1",
        guid, itemEntry
    ))
    if not attuneRow then
        AP.Voice.Speak(player, "dissolve_not_attuned")
        AP.Forge.Pending[guid] = nil
        AP.Forge.ShowPage(player, npc)
        return
    end

    -- Step 2: Find and verify the physical item (bags, bank, or equipped).
    -- GetItemByEntry searches the full inventory including equipped slots.
    -- ShowPage already filtered out equipped items, but we defensively
    -- check that here too â€" unequipping mid-flow or stale gossip state
    -- could leave an equipped item reaching this code path.
    local itemObj = nil
    pcall(function() itemObj = player:GetItemByEntry(itemEntry) end)
    if not itemObj then
        player:SendBroadcastMessage(
            "|cffff4444[Worldsoul]|r That item is not in your possession. "..
            "It may have left your bags."
        )
        AP.Forge.Pending[guid] = nil
        AP.Forge.ShowPage(player, npc)
        return
    end

    -- Equipped items should not reach here (ShowPage excludes them),
    -- but if they do, reject with a clear message rather than silently
    -- destroying a worn item.
    local isEquipped = false
    pcall(function()
        for slot = 0, 18 do
            local eq = player:GetEquippedItemBySlot(slot)
            if eq and eq:GetEntry() == itemEntry then
                isEquipped = true
                break
            end
        end
    end)
    if isEquipped then
        AP.Voice.Speak(player, "dissolve_equipped")
        AP.Forge.Pending[guid] = nil
        AP.Forge.ShowPage(player, npc)
        return
    end

    -- Step 3: Remove the physical item using the item object reference.
    -- Mirrors the Echo Fragment removal pattern (ap_events.lua).
    local removed = false
    pcall(function() player:RemoveItem(itemObj, 1); removed = true end)
    if not removed then
        player:SendBroadcastMessage(
            "|cffff4444[Worldsoul]|r The item could not be removed. Please try again."
        )
        AP.Forge.Pending[guid] = nil
        AP.Forge.ShowPage(player, npc)
        return
    end

    -- Persist item removal before recording the dissolution or granting
    -- rewards. Without this, a crash between here and the ap_dissolved_items
    -- INSERT could leave character_inventory with the item restored (the
    -- in-memory removal rolled back), while the dissolution record is
    -- already committed â€" locking the player out with no reward and no item.
    pcall(function() player:SaveToDB(false, false) end)

    local quality = pending.quality
    local rewards = AP.Forge.Rewards[quality] or AP.Forge.Rewards[1]

    -- Step 4: Record dissolution before granting rewards so partial
    -- failures can never leave the ledger open for retry exploitation.
    -- ap_item_attune is intentionally NOT deleted â€" attuned=1 is permanent.
    -- The snapshot (absorbed stats) is also unchanged.
    CharDBExecute(string.format(
        "INSERT IGNORE INTO `ap_dissolved_items` (`account_id`, `item_entry`) "..
        "VALUES (%d, %d)",
        accountId, itemEntry
    ))
    CharDBExecute("COMMIT")

    -- Step 5: Grant rewards.
    CharDBExecute(string.format(
        "INSERT INTO `ap_mastery` (`guid`,`aether`,`mastery`) VALUES (%d,%d,0) "..
        "ON DUPLICATE KEY UPDATE `aether`=`aether`+%d",
        guid, rewards.essence, rewards.essence
    ))

    local currentGold = 0
    pcall(function() currentGold = player:GetCoinage() end)
    pcall(function() player:SetCoinage(currentGold + rewards.gold) end)

    if rewards.residue > 0 then
        AP.Forge.AddResidue(player, rewards.residue)
    end

    CharDBExecute("COMMIT")

    -- Unconditional save after all reward grants. AddResidue() already calls
    -- SaveToDB internally when residue > 0, but Poor-quality items (residue=0)
    -- skip that path, leaving the gold grant (SetCoinage) volatile. This
    -- covers that case. Safe to call multiple times â€" SaveToDB is idempotent.
    pcall(function() player:SaveToDB(false, false) end)

    -- Remove from Rack if present
    if AP.Rack then
        local rCache = AP.Rack.Cache[guid]
        if rCache then
            for i, slot in pairs(rCache) do
                if slot.item_entry == itemEntry then
                    AP.Rack.RemoveItem(player, i)
                    break
                end
            end
        end
    end

    AP.Forge.Pending[guid] = nil

    local goldG = math.floor(rewards.gold / 10000)
    local goldS = math.floor((rewards.gold % 10000) / 100)
    player:SendBroadcastMessage(string.format(
        "|cff9966ff[Worldsoul]|r %s dissolved. "..
        "|cffffff00+%d Essence|r, |cffffff00+%dg %ds|r, "..
        "|cffffff00+%d Residue|r. Its echo endures.",
        pending.name, rewards.essence, goldG, goldS, rewards.residue
    ))

    if AP.Tutorial and AP.Tutorial.Trigger then
        AP.Tutorial.Trigger(player, "first_dissolution")
    end
    if AP.API and AP.API.DispatchHook then
        AP.API.DispatchHook("OnForgeDissolve", {
            guid=guid, itemEntry=pending.entry,
            essenceReward=rewards.essence, residueReward=rewards.residue })
    end

    AP.Forge.ShowPage(player, npc)
end

-- ============================================================
-- GOSSIP DISPATCH
-- ============================================================

function AP.Forge.OnSelect(player, npc, sender, code)
    if sender == 250 then
        AP.Forge.ShowPage(player, npc)
    elseif sender == 251 then
        AP.Forge.ShowConfirm(player, npc, code)
    elseif sender == 252 then
        AP.Forge.Dissolve(player, npc, code)
    elseif sender == 253 then
        -- Crucible Catalyst: spend 10 Residue -> 5000 Essence
        local accountId = player:GetAccountId()
        local guid      = player:GetGUIDLow()
        local cost      = AP.Forge.ResidueCosts.crucible_catalyst
        if AP.Forge.SpendResidue(accountId, cost) then
            local essence = 5000
            CharDBExecute(string.format(
                "INSERT INTO `ap_mastery` (`guid`,`aether`,`mastery`) "..
                "VALUES (%d,%d,0) ON DUPLICATE KEY UPDATE `aether`=`aether`+%d",
                guid, essence, essence
            ))
            CharDBExecute("COMMIT")
            pcall(function() player:RemoveItem(RESIDUE_ITEM_ENTRY, cost) end)
            player:SendBroadcastMessage(string.format(
                "|cff9966ff[Worldsoul]|r The Catalyst takes %d Residue. "..
                "|cffffff00+%d Essence|r flows in return.",
                cost, essence
            ))
        else
            player:SendBroadcastMessage(
                "|cffff4444[Worldsoul]|r Not enough Residue for the Catalyst."
            )
        end
        AP.Forge.ShowPage(player, npc)
    elseif sender == 254 then
        if AP.OpenUI then AP.OpenUI(player) end
    elseif sender == 255 then
        AP.Forge.Pending[player:GetGUIDLow()] = nil
        AP.Forge.ShowPage(player, npc)
    end
end

-- ============================================================
-- LOGIN RECONCILIATION
-- Uses ap_session_state.clean_exit to distinguish a graceful
-- logout (player intentionally removed items) from a crash
-- (items lost to the AddItem→SaveToDB gap).
--
-- clean_exit=1 → graceful logout. Sync ledger DOWN to physical.
-- clean_exit=0 or missing → crash. Restore shortfall to bags.
-- ============================================================
RegisterPlayerEvent(3, function(event, player)
    pcall(function()
        local accountId = player:GetAccountId()
        local guid      = player:GetGUIDLow()

        -- Reset clean_exit to 0 at login start so a mid-session crash
        -- is correctly detected on the NEXT login. The read below uses
        -- the value that was set by the previous logout/startup reset.
        -- pcall guards against ap_session_state not existing yet
        -- (InitDB may not have run before the first login event fires).
        local cleanExit = false
        pcall(function()
            local sq = CharDBQuery(string.format(
                "SELECT `clean_exit` FROM `ap_session_state` WHERE `guid` = %d",
                guid))
            if sq then
                cleanExit = (tonumber(tostring(sq:GetUInt32(0))) or 0) == 1
            end
            CharDBQuery(string.format(
                "INSERT INTO `ap_session_state` (`guid`,`clean_exit`) VALUES (%d, 0) "..
                "ON DUPLICATE KEY UPDATE `clean_exit` = 0",
                guid))
            CharDBQuery("COMMIT;")
        end)

        local ledger    = AP.Forge.GetResidue(accountId)
        if ledger <= 0 then return end

        local physical = 0
        pcall(function()
            physical = player:GetItemCount(RESIDUE_ITEM_ENTRY, true)
        end)

        local shortfall = ledger - physical
        if shortfall <= 0 then return end

        if cleanExit then
            CharDBQuery(string.format(
                "UPDATE `ap_residue` SET `amount` = %d WHERE `account_id` = %d",
                physical, accountId))
            CharDBQuery("COMMIT;")
            AP.Log(string.format(
                "Residue sync-down: account=%d ledger=%d->%d (clean_exit=1)",
                accountId, ledger, physical))
            return
        end

        pcall(function() player:AddItem(RESIDUE_ITEM_ENTRY, shortfall) end)
        pcall(function() player:SaveToDB(false, false) end)
        player:SendBroadcastMessage(string.format(
            "|cff9966ff[Worldsoul]|r %d Worldsoul Residue returned to your bags. "..
            "Nothing was lost.",
            shortfall
        ))
        AP.Log(string.format(
            "Residue reconcile: account=%d ledger=%d physical=%d restored=%d (crash recovery)",
            accountId, ledger, physical, shortfall))
    end)
end)

print("[EotW] Legacy Forge loaded.")
