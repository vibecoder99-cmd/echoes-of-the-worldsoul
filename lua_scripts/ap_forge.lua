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
-- (Gossip UI state only. Not to be confused with ap_dissolution_pending,
-- the durable DB-backed transaction-safety record below.)
AP.Forge.Pending = {}

-- ============================================================
-- DISSOLUTION PENDING-RECORD STATE MACHINE (E2j5h Stage 4)
--
-- Implements the design chosen by the E2j5h Stage 3 report
-- (e2j5h-DISSOLUTION-TRANSACTION-DESIGN.md, "Option C"): a durable,
-- two-phase pending record written to `ap_dissolution_pending` BEFORE
-- the item is touched, advanced through PENDING_REMOVAL -> REMOVED ->
-- COMPLETE as the mutation proceeds, and reconciled by a
-- login-time recovery pass (AP.Forge.ReconcilePendingDissolutions below)
-- if a crash leaves it non-COMPLETE.
--
-- Item removal still crosses the Lua/core persistence boundary and is
-- recoverable rather than globally atomic. Once the row is REMOVED, however,
-- the Essence, Residue, persisted gold, and COMPLETE transition are one
-- synchronous multi-table database mutation guarded by the row status. This
-- closes the former asynchronous reward-before-COMPLETE crash window.
-- RECORDED remains accepted by recovery for rows created by older builds.
-- ============================================================

-- Reserve a pending record before the item is touched. Returns true on
-- success, or (nil, reasonCode) if a non-COMPLETE row already exists for
-- this (guid, item_entry) -- i.e. a dissolution of this exact item entry
-- is already in flight. This is the idempotency guard against rapid
-- duplicate requests (two near-simultaneous confirmations for the same
-- item): the second one is rejected here, before any mutation, rather
-- than racing the first.
function AP.Forge.CreatePendingRecord(guid, accountId, itemEntry, itemInstanceGuid, quality, rewards)
    local existing = AP.DB.Query(string.format(
        "SELECT `status` FROM `ap_dissolution_pending` "..
        "WHERE `guid` = %d AND `item_entry` = %d",
        guid, itemEntry
    ))
    if existing then
        local status = existing:GetString(0)
        if status ~= "COMPLETE" then
            return nil, "already_pending"
        end
        -- A COMPLETE row already exists for this exact item_entry. In
        -- practice ap_dissolved_items (checked earlier in both Dissolve()
        -- and DissolveDirect()) already permanently blocks a second
        -- dissolution of the same item_entry, so this branch should be
        -- unreachable in normal operation -- defensive only.
    end

    local ok = AP.DB.ExecuteCritical(string.format(
        "INSERT INTO `ap_dissolution_pending` "..
        "(`guid`,`account_id`,`item_entry`,`item_instance_guid`,`quality`,"..
        "`essence_reward`,`gold_reward`,`residue_reward`,`status`) "..
        "VALUES (%d,%d,%d,%d,%d,%d,%d,%d,'PENDING_REMOVAL') "..
        "ON DUPLICATE KEY UPDATE "..
        "`item_instance_guid`=VALUES(`item_instance_guid`),"..
        "`quality`=VALUES(`quality`),"..
        "`essence_reward`=VALUES(`essence_reward`),"..
        "`gold_reward`=VALUES(`gold_reward`),"..
        "`residue_reward`=VALUES(`residue_reward`),"..
        "`status`='PENDING_REMOVAL'",
        guid, accountId, itemEntry, itemInstanceGuid or 0, quality,
        rewards.essence, rewards.gold, rewards.residue
    ), "AP.Forge.CreatePendingRecord")

    if not ok then return nil, "db_error" end
    return true
end

function AP.Forge.MarkPendingStatus(guid, itemEntry, status)
    return AP.DB.ExecuteCritical(string.format(
        "UPDATE `ap_dissolution_pending` SET `status` = '%s' "..
        "WHERE `guid` = %d AND `item_entry` = %d",
        status, guid, itemEntry
    ), "AP.Forge.MarkPendingStatus")
end

function AP.Forge.DeletePendingRecord(guid, itemEntry)
    return AP.DB.ExecuteCritical(string.format(
        "DELETE FROM `ap_dissolution_pending` WHERE `guid` = %d AND `item_entry` = %d",
        guid, itemEntry
    ), "AP.Forge.DeletePendingRecord")
end

local function GetPendingStatus(guid, itemEntry)
    local q = AP.DB.Query(string.format(
        "SELECT `status` FROM `ap_dissolution_pending` "..
        "WHERE `guid` = %d AND `item_entry` = %d LIMIT 1",
        guid, itemEntry))
    if not q then return nil end
    local ok, status = pcall(function() return q:GetString(0) end)
    return (ok and status) or nil
end

-- Complete the durable economy mutation and the pending-state transition in
-- one synchronous multi-table UPDATE. The WHERE status guard is the durable
-- idempotency key: the first successful call credits Essence, Residue, and
-- persisted gold while changing the row to COMPLETE atomically; later calls
-- cannot match and therefore cannot credit a second time.
--
-- Zero-valued reward rows and the permanent dissolved-item ledger are created
-- first with idempotent critical writes. They carry no reward and are safe to
-- repeat after a crash. Physical Residue and the online coinage cache are
-- representation synchronization performed only after durable completion.
function AP.Forge.GrantDissolutionRewards(player, guid, accountId, itemEntry, rewards)
    local status = GetPendingStatus(guid, itemEntry)
    if status == "COMPLETE" then return true, "already_complete" end
    if status ~= "REMOVED" and status ~= "RECORDED" then
        return false, "not_recoverable"
    end

    local masteryReady = AP.DB.ExecuteCritical(string.format(
        "INSERT IGNORE INTO `ap_mastery` (`guid`,`aether`,`mastery`) VALUES (%d,0,0)",
        guid), "AP.Forge.EnsureMasteryRewardRow")
    if not masteryReady then return false, "mastery_row_failed" end

    local residueReady = AP.DB.ExecuteCritical(string.format(
        "INSERT IGNORE INTO `ap_residue` (`account_id`,`amount`) VALUES (%d,0)",
        accountId), "AP.Forge.EnsureResidueRewardRow")
    if not residueReady then return false, "residue_row_failed" end

    local ledgerReady = AP.DB.ExecuteCritical(string.format(
        "INSERT IGNORE INTO `ap_dissolved_items` (`account_id`,`item_entry`) VALUES (%d,%d)",
        accountId, itemEntry), "AP.Forge.EnsureDissolvedLedger")
    if not ledgerReady then return false, "ledger_write_failed" end

    local currentGold = AP.RT.GetCoinage(player)
    local rewardWrite = AP.DB.ExecuteCritical(string.format(
        "UPDATE `ap_dissolution_pending` AS p "..
        "JOIN `ap_mastery` AS m ON m.`guid` = p.`guid` "..
        "JOIN `ap_residue` AS r ON r.`account_id` = p.`account_id` "..
        "LEFT JOIN `characters` AS c ON c.`guid` = p.`guid` "..
        "SET m.`aether` = m.`aether` + p.`essence_reward`, "..
        "r.`amount` = r.`amount` + p.`residue_reward`, "..
        "c.`money` = c.`money` + p.`gold_reward`, "..
        "p.`status` = 'COMPLETE' "..
        "WHERE p.`guid` = %d AND p.`account_id` = %d AND p.`item_entry` = %d "..
        "AND p.`status` IN ('REMOVED','RECORDED')",
        guid, accountId, itemEntry), "AP.Forge.CommitDissolutionRewards")
    if not rewardWrite then return false, "reward_write_failed" end

    if GetPendingStatus(guid, itemEntry) ~= "COMPLETE" then
        return false, "reward_write_unconfirmed"
    end

    -- The database credit is authoritative. Cache/item synchronization is
    -- deliberately non-crediting: failure leaves the durable reward intact
    -- and must never make recovery apply the ledger credit again.
    local goldSynced = AP.RT.SetCoinage(player, currentGold + rewards.gold)
    local residueSynced = true
    if rewards.residue > 0 then
        residueSynced = AP.RT.AddItem(player, RESIDUE_ITEM_ENTRY, rewards.residue)
    end
    local playerSaved = AP.RT.SavePlayerToDB(player, false, false)

    if not goldSynced or not residueSynced or not playerSaved then
        AP.Log(string.format(
            "Dissolution durable reward committed; representation sync deferred "..
            "guid=%d item=%d gold=%s residue=%s save=%s",
            guid, itemEntry, tostring(goldSynced), tostring(residueSynced), tostring(playerSaved)))
    end

    return true, "complete", {
        goldSynced = goldSynced,
        residueSynced = residueSynced,
        playerSaved = playerSaved,
    }
end

-- ============================================================
-- RESIDUE BALANCE
-- ============================================================

function AP.Forge.GetResidue(accountId)
    local q = AP.DB.Query(string.format(
        "SELECT `amount` FROM `ap_residue` WHERE `account_id` = %d",
        accountId
    ))
    if q then return tonumber(tostring(q:GetUInt32(0))) or 0 end
    return 0
end

-- Correctness-critical reads must distinguish a verified zero/missing row from
-- a failed query. The scalar subquery always returns one row when the query is
-- available, even when the account has no ap_residue row.
function AP.Forge.GetVerifiedResidue(accountId)
    if type(accountId) ~= "number" or accountId <= 0 then return false, nil end
    local q = AP.DB.Query(string.format(
        "SELECT COALESCE((SELECT `amount` FROM `ap_residue` "..
        "WHERE `account_id` = %d), 0)", accountId))
    if not q then return false, nil end
    local ok, value = pcall(function() return q:GetUInt32(0) end)
    if not ok or value == nil then return false, nil end
    return true, tonumber(tostring(value)) or 0
end

local function GetVerifiedEssence(guid)
    if type(guid) ~= "number" or guid <= 0 then return false, nil end
    local q = AP.DB.Query(string.format(
        "SELECT `aether` FROM `ap_mastery` WHERE `guid` = %d", guid))
    if not q then return false, nil end
    local value = AP.DB.GetUInt64(q, 0)
    if type(value) ~= "number" or value < 0 then return false, nil end
    return true, value
end

-- Synchronize item 900011 to an already-authoritative ledger balance. This
-- function never changes the ledger. Excess physical representation is removed
-- rather than converted into currency; shortfall is restored. A failure leaves
-- the durable balance untouched and is safe to retry on login.
function AP.Forge.SyncResiduePhysicalToLedger(player, ledger)
    if not player or type(ledger) ~= "number" or ledger < 0 or ledger ~= math.floor(ledger) then
        return false, "invalid_target"
    end
    if not AP.RT or type(AP.RT.TryGetItemCount) ~= "function" then
        return false, "inventory_unavailable"
    end

    local countOk, physical = AP.RT.TryGetItemCount(player, RESIDUE_ITEM_ENTRY, true)
    if not countOk or type(physical) ~= "number" or physical < 0 then
        return false, "inventory_unavailable"
    end
    physical = math.floor(physical)
    if physical == ledger then return true, "already_exact" end

    local changed
    if physical > ledger then
        changed = AP.RT.RemoveItem(player, RESIDUE_ITEM_ENTRY, physical - ledger)
    else
        changed = AP.RT.AddItem(player, RESIDUE_ITEM_ENTRY, ledger - physical)
    end
    if not changed then return false, "item_mutation_failed" end

    local saved = AP.RT.SavePlayerToDB(player, false, false)
    local afterOk, after = AP.RT.TryGetItemCount(player, RESIDUE_ITEM_ENTRY, true)
    if not afterOk or type(after) ~= "number" or math.floor(after) ~= ledger then
        return false, "post_verify_failed"
    end
    if not saved then return false, "save_failed" end
    return true, "synchronized"
end

-- Residue is account-scoped, while item 900011 is represented in each online
-- character inventory. After an account balance changes, converge every
-- currently-online character on that account in the same bounded pass. This
-- prevents a second simultaneously logged-in character from retaining a stale
-- physical representation after another character wins an atomic spend race.
function AP.Forge.SyncResidueAccountRepresentations(player, accountId, ledger)
    if not player or type(accountId) ~= "number" then
        return false, "invalid_account"
    end

    local allOk = true
    local firstReason = "already_exact"
    local primaryGuid = AP.RT.GetGUID(player)
    local function sync(candidate)
        local ok, reason = AP.Forge.SyncResiduePhysicalToLedger(candidate, ledger)
        if not ok then
            allOk = false
            if firstReason == "already_exact" then firstReason = reason end
        end
    end

    sync(player)
    local players = AP.RT.GetPlayersInWorld and AP.RT.GetPlayersInWorld() or {}
    if type(players) == "table" then
        for _, candidate in pairs(players) do
            local candidateGuid = AP.RT.GetGUID(candidate)
            if candidate and candidateGuid ~= primaryGuid and
                    AP.RT.GetAccountId(candidate) == accountId then
                sync(candidate)
            end
        end
    end
    return allOk, allOk and "account_synchronized" or firstReason
end

function AP.Forge.PreviewCatalyst(player)
    if not player then return { ok = false, status = "SERVICE_UNAVAILABLE" } end
    local accountId = AP.RT.GetAccountId(player)
    local guid = AP.RT.GetGUID(player)
    if not accountId or not guid then
        return { ok = false, status = "SERVICE_UNAVAILABLE" }
    end

    local residueOk, residue = AP.Forge.GetVerifiedResidue(accountId)
    local essenceOk, essence = GetVerifiedEssence(guid)
    if not residueOk or not essenceOk then
        return { ok = false, status = "SERVICE_UNAVAILABLE" }
    end

    local cost = AP.Forge.ResidueCosts.crucible_catalyst
    local reward = 5000
    return {
        ok = true,
        status = residue >= cost and "READY" or "INSUFFICIENT_RESIDUE",
        cost = cost,
        reward = reward,
        expectedResidue = residue,
        expectedEssence = essence,
    }
end

function AP.Forge.PurchaseCatalyst(player, expectedResidue, expectedEssence)
    local result = {
        ok = false,
        status = "SERVICE_UNAVAILABLE",
        cost = AP.Forge.ResidueCosts.crucible_catalyst,
        reward = 5000,
        physicalSynced = false,
    }
    if not player or type(expectedResidue) ~= "number" or type(expectedEssence) ~= "number" then
        return result
    end

    expectedResidue = math.floor(expectedResidue)
    expectedEssence = math.floor(expectedEssence)
    local accountId = AP.RT.GetAccountId(player)
    local guid = AP.RT.GetGUID(player)
    if not accountId or not guid or expectedResidue < result.cost or expectedEssence < 0 then
        result.status = expectedResidue < result.cost and "INSUFFICIENT_RESIDUE" or "SERVICE_UNAVAILABLE"
        return result
    end

    local wrote = AP.DB.ExecuteCritical(string.format(
        "UPDATE `ap_residue` AS r JOIN `ap_mastery` AS m ON m.`guid` = %d "..
        "SET r.`amount` = r.`amount` - %d, m.`aether` = m.`aether` + %d "..
        "WHERE r.`account_id` = %d AND r.`amount` = %d AND r.`amount` >= %d "..
        "AND m.`aether` = %.0f",
        guid, result.cost, result.reward, accountId, expectedResidue, result.cost, expectedEssence),
        "AP.Forge.PurchaseCatalyst")
    if not wrote then result.status = "DATABASE_FAILURE"; return result end

    local residueOk, residueAfter = AP.Forge.GetVerifiedResidue(accountId)
    local essenceOk, essenceAfter = GetVerifiedEssence(guid)
    if not residueOk or not essenceOk then
        result.status = "POST_VERIFY_FAILURE"
        return result
    end

    local targetResidue = expectedResidue - result.cost
    local targetEssence = expectedEssence + result.reward
    if residueAfter ~= targetResidue or essenceAfter ~= targetEssence then
        result.status = "STALE_PREVIEW"
        result.oldBalance = expectedResidue
        result.newBalance = residueAfter
        result.physicalSynced, result.physicalReason =
            AP.Forge.SyncResidueAccountRepresentations(player, accountId, residueAfter)
        return result
    end

    result.ok = true
    result.status = "SUCCESS"
    result.oldBalance = expectedResidue
    result.newBalance = residueAfter
    result.oldEssence = expectedEssence
    result.newEssence = essenceAfter
    result.physicalSynced, result.physicalReason =
        AP.Forge.SyncResidueAccountRepresentations(player, accountId, residueAfter)
    return result
end

function AP.Forge.AddResidue(player, amount)
    local accountId = AP.RT.GetAccountId(player)
    AP.DB.ExecuteAsync(string.format(
        "INSERT INTO `ap_residue` (`account_id`, `amount`) VALUES (%d, %d) "..
        "ON DUPLICATE KEY UPDATE `amount` = `amount` + %d",
        accountId, amount, amount
    ))
    pcall(function() AP.RT.AddItem(player,RESIDUE_ITEM_ENTRY, amount) end)
    AP.DB.ExecuteAsync("COMMIT")
    -- Force a character DB save so the physical item survives a client crash
    -- before AzerothCore's autosave tick (typically 15 min).
    pcall(function() AP.RT.SavePlayerToDB(player,false, false) end)
end

function AP.Forge.SpendResidue(accountId, amount)
    local current = AP.Forge.GetResidue(accountId)
    if current < amount then return false end
    AP.DB.ExecuteAsync(string.format(
        "UPDATE `ap_residue` SET `amount` = `amount` - %d "..
        "WHERE `account_id` = %d",
        amount, accountId
    ))
    AP.DB.ExecuteAsync("COMMIT")
    return true
end

-- ============================================================
-- GOSSIP UI
-- Sender range: 250-255
-- ============================================================

function AP.Forge.ShowPage(player, npc)
    local guid      = AP.RT.GetGUID(player)
    local accountId = AP.RT.GetAccountId(player)
    local residue   = AP.Forge.GetResidue(accountId)

    AP.UI.ClearMenu(player)

    AP.UI.AddItem(player,0, string.format(
        "Legacy Forge -- Return attuned items to the Worldsoul.\n"..
        "Receive Essence, gold, and Worldsoul Residue in return.\n"..
        "Dissolution consumes the physical item, but its permanent Attunement remains -- "..
        "you keep the absorbed stats forever, whether or not you keep the item.\n"..
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
            local eq = AP.RT.GetEquippedItem(player,slot)
            if eq then
                equippedEntries[AP.RT.GetItemEntry(eq)] = true
            end
        end
    end)

    -- Exclude entries already dissolved on this account via LEFT JOIN.
    local q = AP.DB.Query(string.format(
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
                pcall(function() itemObj = AP.RT.GetItemByEntry(player,entry) end)
                if itemObj then
                    local itemName = "Unknown Item"
                    local wq = AP.DB.WorldQuery(string.format(
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
                            AP.UI.AddItem(player,0, label, 251, entry)
                            count = count + 1
                        end
                    end
                end
            end
        until not q:NextRow() or count >= 8
    end

    if count == 0 then
        AP.UI.AddItem(player,0,
            "Nothing ready to dissolve.\n"..
            "Fully attune items through combat or the Rack, then return.",
            250, 0)
    end

    -- Crucible Catalyst spend option
    if residue >= AP.Forge.ResidueCosts.crucible_catalyst then
        AP.UI.AddItem(player,0, string.format(
            "Spend %d Residue\n+5,000 Essence (Crucible Catalyst)",
            AP.Forge.ResidueCosts.crucible_catalyst
        ), 253, 1)
    end

    AP.UI.AddItem(player,0, "<< Back to Main Menu", 254, 0)
    AP.UI.SendMenu(player,1, npc, 250)
end

-- Confirmation page before dissolution
function AP.Forge.ShowConfirm(player, npc, itemEntry)
    local quality  = 1
    local itemName = "Unknown Item"

    local wq = AP.DB.WorldQuery(string.format(
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

    local guid = AP.RT.GetGUID(player)
    AP.Forge.Pending[guid] = {
        itemEntry = itemEntry,
        quality   = quality,
        name      = itemName,
    }

    AP.UI.ClearMenu(player)
    AP.UI.AddItem(player,0, string.format(
        "Dissolve: %s\n\n"..
        "This item's echo has been claimed.\n"..
        "Returning its husk to the Worldsoul is permanent -- the physical item will be gone for good.\n"..
        "Your Attunement is NOT affected: the permanent stat benefit you already earned from this "..
        "item stays yours forever, whether or not you keep the item itself.\n\n"..
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

    AP.UI.AddItem(player,0, "Dissolve into the Worldsoul", 252, itemEntry)
    AP.UI.AddItem(player,0, "Keep this item",              255, 0)

    AP.UI.SendMenu(player,1, npc, 250)
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
    local guid      = AP.RT.GetGUID(player)
    local accountId = AP.RT.GetAccountId(player)
    local pending   = AP.Forge.Pending[guid]

    if not pending or pending.itemEntry ~= itemEntry then
        AP.RT.SendMessage(player,
            "|cffff4444[Worldsoul]|r The dissolution did not complete. Please try again."
        )
        AP.Forge.ShowPage(player, npc)
        return
    end

    -- Step 1: Guard against already-dissolved entries.
    -- ShowPage filters these out, so this path is purely defensive
    -- (stale gossip state, race conditions, direct exploit attempts).
    -- Player keeps the item â€" no reward, no removal.
    local alreadyDissolved = AP.DB.Query(string.format(
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
    local attuneRow = AP.DB.Query(string.format(
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
    pcall(function() itemObj = AP.RT.GetItemByEntry(player,itemEntry) end)
    if not itemObj then
        AP.RT.SendMessage(player,
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
            local eq = AP.RT.GetEquippedItem(player,slot)
            if eq and AP.RT.GetItemEntry(eq) == itemEntry then
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

    local quality = pending.quality
    local rewards = AP.Forge.Rewards[quality] or AP.Forge.Rewards[1]

    local itemInstanceGuid = 0
    pcall(function() itemInstanceGuid = AP.RT.GetItemGUIDLow(itemObj) end)

    -- Step 2b (E2j5h Stage 4): reserve a durable pending record BEFORE the
    -- item is touched. See "DISSOLUTION PENDING-RECORD STATE MACHINE" above
    -- for the full rationale. Rewards are snapshotted into the row now so a
    -- later change to AP.Forge.Rewards cannot alter an in-flight payout.
    local pendingOk, pendingReason = AP.Forge.CreatePendingRecord(
        guid, accountId, itemEntry, itemInstanceGuid, quality, rewards)
    if not pendingOk then
        AP.RT.SendMessage(player,
            "|cffff4444[Worldsoul]|r A dissolution for this item is already being processed. "..
            "Please wait a moment and try again."
        )
        AP.Forge.Pending[guid] = nil
        AP.Forge.ShowPage(player, npc)
        return
    end

    -- Step 3: Remove the physical item using the item object reference.
    -- Mirrors the Echo Fragment removal pattern (ap_events.lua).
    local removed = false
    removed = AP.RT.RemoveItem(player, itemObj, 1)
    if not removed then
        -- Nothing was touched -- discard the reservation so it cannot wedge
        -- a future dissolution attempt on this item_entry.
        AP.Forge.DeletePendingRecord(guid, itemEntry)
        AP.RT.SendMessage(player,
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
    -- The ap_dissolution_pending row (now REMOVED) is what makes this
    -- recoverable rather than silent: see AP.Forge.ReconcilePendingDissolutions.
    pcall(function() AP.RT.SavePlayerToDB(player,false, false) end)
    AP.Forge.MarkPendingStatus(guid, itemEntry, "REMOVED")

    -- Steps 4-5: atomically credit durable rewards and COMPLETE the guarded
    -- pending row; the permanent ledger is prepared idempotently first.
    -- ap_item_attune is intentionally NOT deleted â€" attuned=1 is permanent.
    -- The snapshot (absorbed stats) is also unchanged.
    local rewardOk, rewardReason = AP.Forge.GrantDissolutionRewards(
        player, guid, accountId, itemEntry, rewards)
    if not rewardOk then
        AP.RT.SendMessage(player,
            "|cffff4444[Worldsoul]|r The item was removed, but its reward is pending durable recovery. "..
            "Please relog; do not attempt another dissolution of this item.")
        AP.Log(string.format(
            "Dissolution reward deferred: guid=%d item=%d reason=%s status=REMOVED",
            guid, itemEntry, tostring(rewardReason)))
        AP.Forge.Pending[guid] = nil
        AP.Forge.ShowPage(player, npc)
        return
    end

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
    AP.RT.SendMessage(player,string.format(
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
            guid=guid, itemEntry=itemEntry,
            essenceReward=rewards.essence, residueReward=rewards.residue })
    end

    AP.Forge.ShowPage(player, npc)
end

-- ============================================================
-- E2i8: non-UI, non-gossip service entry point for the bot action bridge
-- (ap_botapi.lua). Added after an independent architecture audit found that
-- priming AP.Forge.Pending directly from outside this file reached into an
-- undocumented, file-private implementation detail rather than a real
-- interface, even though it worked correctly. This function performs the
-- IDENTICAL guard-clause sequence and mutation ordering as AP.Forge.Dissolve
-- above (already-dissolved / attunement / possession / equipped checks, then
-- removal -> ap_dissolved_items ledger write -> reward grant -> Rack cleanup,
-- in that exploit-safe order) but:
--   - never reads or writes AP.Forge.Pending (no gossip-confirmation coupling)
--   - never calls AP.UI.* / AP.RT.SendMessage / AP.Forge.ShowPage (no UI)
--   - returns a real, structured result table instead of relying on a
--     follow-up gossip page refresh to communicate outcome
-- The human gossip flow (ShowConfirm/Dissolve/OnSelect) is completely
-- unchanged by this addition - this is a new, additive entry point only.
-- ============================================================

function AP.Forge.DissolveDirect(player, itemEntry)
    local guid      = AP.RT.GetGUID(player)
    local accountId = AP.RT.GetAccountId(player)

    -- Guard 1: already dissolved (same table/condition as Dissolve()'s own check)
    local alreadyDissolved = AP.DB.Query(string.format(
        "SELECT 1 FROM `ap_dissolved_items` WHERE `account_id` = %d AND `item_entry` = %d",
        accountId, itemEntry
    ))
    if alreadyDissolved then
        return { success = false, reasonCode = "already_dissolved" }
    end

    -- Guard 2: fully attuned (the same authoritative attuned=1 threshold)
    local attuneRow = AP.DB.Query(string.format(
        "SELECT 1 FROM `ap_item_attune` WHERE `guid` = %d AND `item_entry` = %d AND `attuned` = 1",
        guid, itemEntry
    ))
    if not attuneRow then
        return { success = false, reasonCode = "not_attuned" }
    end

    -- Guard 3: physically possessed right now
    local itemObj = nil
    pcall(function() itemObj = AP.RT.GetItemByEntry(player, itemEntry) end)
    if not itemObj then
        return { success = false, reasonCode = "item_not_possessed" }
    end

    -- Guard 4: not equipped
    local isEquipped = false
    pcall(function()
        for slot = 0, 18 do
            local eq = AP.RT.GetEquippedItem(player, slot)
            if eq and AP.RT.GetItemEntry(eq) == itemEntry then
                isEquipped = true
                break
            end
        end
    end)
    if isEquipped then
        return { success = false, reasonCode = "item_equipped" }
    end

    local quality = 1
    local wq = AP.DB.WorldQuery(string.format(
        "SELECT `Quality` FROM `item_template` WHERE `entry` = %d", itemEntry))
    if wq then quality = tonumber(tostring(wq:GetUInt32(0))) or 1 end
    local rewards = AP.Forge.Rewards[quality] or AP.Forge.Rewards[1]

    local itemInstanceGuid = 0
    pcall(function() itemInstanceGuid = AP.RT.GetItemGUIDLow(itemObj) end)

    -- Reserve a durable pending record BEFORE the item is touched - identical
    -- state machine and rationale as Dissolve() (see the "DISSOLUTION
    -- PENDING-RECORD STATE MACHINE" block near the top of this file).
    local pendingOk = AP.Forge.CreatePendingRecord(
        guid, accountId, itemEntry, itemInstanceGuid, quality, rewards)
    if not pendingOk then
        return { success = false, reasonCode = "already_pending" }
    end

    -- Step 1: remove the physical item.
    local removed = AP.RT.RemoveItem(player, itemObj, 1)
    if not removed then
        AP.Forge.DeletePendingRecord(guid, itemEntry)
        return { success = false, reasonCode = "removal_failed" }
    end

    -- Persist item removal before recording the dissolution or granting
    -- rewards - identical ordering rationale as Dissolve() (see its own
    -- comment above): without this, a crash between here and the ledger
    -- INSERT could leave the item restored while the dissolution record is
    -- already committed.
    pcall(function() AP.RT.SavePlayerToDB(player, false, false) end)
    AP.Forge.MarkPendingStatus(guid, itemEntry, "REMOVED")

    -- Steps 2-3: use the same atomic durable reward/completion path as the
    -- human gossip flow.
    local rewardOk, rewardReason = AP.Forge.GrantDissolutionRewards(
        player, guid, accountId, itemEntry, rewards)
    if not rewardOk then
        return {
            success = false,
            reasonCode = "reward_pending",
            recoveryReason = rewardReason,
            recoverable = true,
        }
    end

    -- Remove from Rack if present - identical to Dissolve() (Rack membership
    -- never blocks dissolution; it is auto-cleared as a side effect).
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

    if AP.API and AP.API.DispatchHook then
        AP.API.DispatchHook("OnForgeDissolve", {
            guid = guid, itemEntry = itemEntry,
            essenceReward = rewards.essence, residueReward = rewards.residue })
    end

    return {
        success = true,
        reasonCode = "dissolved",
        essence = rewards.essence,
        gold = rewards.gold,
        residue = rewards.residue,
        quality = quality,
    }
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
        local preview = AP.Forge.PreviewCatalyst(player)
        local purchase = preview.ok and preview.status == "READY" and
            AP.Forge.PurchaseCatalyst(player, preview.expectedResidue, preview.expectedEssence) or nil
        if purchase and purchase.ok then
            AP.RT.SendMessage(player,string.format(
                "|cff9966ff[Worldsoul]|r The Catalyst takes %d Residue. "..
                "|cffffff00+%d Essence|r flows in return.",
                purchase.cost, purchase.reward
            ))
        else
            AP.RT.SendMessage(player,
                "|cffff4444[Worldsoul]|r Not enough Residue for the Catalyst."
            )
        end
        AP.Forge.ShowPage(player, npc)
    elseif sender == 254 then
        if AP.OpenUI then AP.OpenUI(player) end
    elseif sender == 255 then
        AP.Forge.Pending[AP.RT.GetGUID(player)] = nil
        AP.Forge.ShowPage(player, npc)
    end
end

-- ============================================================
-- DISSOLUTION PENDING-RECORD RECOVERY (E2j5h Stage 4)
--
-- Runs on every login. Scans `ap_dissolution_pending` for rows left
-- non-COMPLETE by this character's last session and resolves each one:
--
--   PENDING_REMOVAL -> the mutation never got past reserving the row (crash
--                       before RemoveItem, or before the SaveToDB that
--                       persists it). The item was never actually touched --
--                       delete the stale reservation. Nothing to reconcile.
--
--   REMOVED / RECORDED -> the item removal was already committed to
--                       character_inventory (SaveToDB ran) before the crash.
--                       The item is genuinely gone. Ensure the permanent
--                       ap_dissolved_items ledger row exists (idempotent --
--                       covers REMOVED, where the crash landed before that
--                       INSERT), then atomically credit the snapshotted
--                       durable rewards and change status to COMPLETE. The
--                       status predicate makes repeated recovery a no-op.
-- ============================================================
function AP.Forge.ReconcilePendingDissolutions(player)
    local guid      = AP.RT.GetGUID(player)
    local accountId = AP.RT.GetAccountId(player)

    local rows = AP.DB.FetchAll(string.format(
        "SELECT `item_entry`,`status`,`essence_reward`,`gold_reward`,`residue_reward` "..
        "FROM `ap_dissolution_pending` WHERE `guid` = %d AND `status` != 'COMPLETE'",
        guid),
        {
            { col = 0, name = "itemEntry", type = "uint32" },
            { col = 1, name = "status",    type = "string" },
            { col = 2, name = "essence",   type = "uint32" },
            { col = 3, name = "gold",      type = "uint32" },
            { col = 4, name = "residue",   type = "uint32" },
        })

    for _, row in ipairs(rows) do
        if row.status == "PENDING_REMOVAL" then
            AP.Forge.DeletePendingRecord(guid, row.itemEntry)
            AP.Log(string.format(
                "Dissolution recovery: guid=%d item=%d status=PENDING_REMOVAL -> discarded (item untouched)",
                guid, row.itemEntry))
        elseif row.status == "REMOVED" or row.status == "RECORDED" then
            local rewards = { essence = row.essence, gold = row.gold, residue = row.residue }
            local recovered, recoveryReason = AP.Forge.GrantDissolutionRewards(
                player, guid, accountId, row.itemEntry, rewards)
            if recovered then
                local goldG = math.floor(rewards.gold / 10000)
                local goldS = math.floor((rewards.gold % 10000) / 100)
                AP.RT.SendMessage(player, string.format(
                    "|cff9966ff[Worldsoul]|r A dissolution interrupted by a prior disconnect has been "..
                    "completed. |cffffff00+%d Essence|r, |cffffff00+%dg %ds|r, |cffffff00+%d Residue|r.",
                    rewards.essence, goldG, goldS, rewards.residue
                ))
                AP.Log(string.format(
                    "Dissolution recovery: guid=%d item=%d status=%s -> atomic reward committed "..
                    "(essence=%d gold=%d residue=%d)",
                    guid, row.itemEntry, row.status, rewards.essence, rewards.gold, rewards.residue))
            else
                AP.Log(string.format(
                    "Dissolution recovery deferred: guid=%d item=%d status=%s reason=%s",
                    guid, row.itemEntry, row.status, tostring(recoveryReason)))
            end
        end
        -- status == "COMPLETE" rows are already excluded by the WHERE clause.
    end
end

-- ============================================================
-- LOGIN RECONCILIATION -- E2j11b fail-safe state machine
--
-- `ap_residue` is the durable account-level source of truth. Item 900011 is
-- only a synchronized client-visible representation of that ledger. This
-- reconciliation therefore NEVER reduces the ledger to match a lower
-- physical count, under any circumstance (clean exit included). Ledger
-- reduction happens only through an authorized spend transaction.
--
-- States handled, in order:
--   1. Ledger or item-template state unverified -> preserve and defer.
--   2. Inventory unavailable or invalid -> preserve and defer.
--   3. ledger == physical -> no mutation.
--   4. ledger > physical -> top up bags where possible; preserve ledger.
--   5. physical > ledger -> remove stale representation; preserve ledger.
-- ============================================================
local AP_E2j11b_ReconcileDiagCount = 0

local function E2j11bWarnReconcile(message)
    AP_E2j11b_ReconcileDiagCount = AP_E2j11b_ReconcileDiagCount + 1
    if AP_E2j11b_ReconcileDiagCount <= 50 then
        AP.Warn(message)
    end
end

-- A normal GetResidue() miss and a failed query both return zero. Reconciliation
-- must distinguish those states because an unverified zero may never authorize
-- a ledger increase. This scalar query returns one row even when the account has
-- no ap_residue row; nil therefore means the query itself was unavailable.
-- A missing item_template row makes GetItemCount's safe zero fallback
-- indistinguishable from a real empty inventory. Prove the definition exists
-- before any physical reconciliation. A failed world query also returns nil.
local function E2j11bResidueTemplateAvailable()
    local q = AP.DB.WorldQuery(string.format(
        "SELECT COUNT(*) FROM `item_template` WHERE `entry` = %d",
        RESIDUE_ITEM_ENTRY))
    if not q then return false end

    local ok, value = pcall(function() return q:GetUInt32(0) end)
    return ok and value ~= nil and (tonumber(tostring(value)) or 0) == 1
end

AP.RT.RegisterEvent("player", 3, function(event, player)
    pcall(function() AP.Forge.ReconcilePendingDissolutions(player) end)

    pcall(function()
        local accountId = AP.RT.GetAccountId(player)
        local guid      = AP.RT.GetGUID(player)

        -- clean_exit bookkeeping is retained for other consumers, but never
        -- authorizes a destructive ledger decision here.
        pcall(function()
            AP.DB.ExecuteCritical(string.format(
                "INSERT INTO `ap_session_state` (`guid`,`clean_exit`) VALUES (%d, 0) "..
                "ON DUPLICATE KEY UPDATE `clean_exit` = 0",
                guid))
            AP.DB.Execute("COMMIT;")
        end)

        local ledgerOk, ledger = AP.Forge.GetVerifiedResidue(accountId)
        if not ledgerOk then
            E2j11bWarnReconcile(string.format(
                "[E2j11b] Residue reconciliation deferred for account=%d guid=%d: "..
                "ledger balance could not be verified. No mutation attempted.",
                accountId, guid))
            return
        end

        if not E2j11bResidueTemplateAvailable() then
            E2j11bWarnReconcile(string.format(
                "[E2j11b] CRITICAL: Residue reconciliation deferred for account=%d guid=%d: "..
                "item_template entry %d is missing or could not be verified. Ledger preserved at %d.",
                accountId, guid, RESIDUE_ITEM_ENTRY, ledger))
            return
        end

        local countOk, physical = AP.RT.TryGetItemCount(player, RESIDUE_ITEM_ENTRY, true)
        if not countOk or physical == nil or physical < 0 then
            E2j11bWarnReconcile(string.format(
                "[E2j11b] Residue reconciliation deferred for account=%d guid=%d: "..
                "inventory count unavailable or invalid. Ledger preserved at %d.",
                accountId, guid, ledger))
            return
        end

        if physical == ledger then return end

        local synced, syncReason = AP.Forge.SyncResiduePhysicalToLedger(player, ledger)
        if not synced then
            E2j11bWarnReconcile(string.format(
                "[E2j10] Residue representation reconciliation deferred for account=%d guid=%d "..
                "physical=%d ledger=%d reason=%s. Ledger preserved.",
                accountId, guid, physical, ledger, tostring(syncReason)))
            return
        end

        local delta = math.abs(ledger - physical)
        if physical < ledger then
            AP.RT.SendMessage(player,string.format(
                "|cff9966ff[Worldsoul]|r %d Worldsoul Residue returned to your bags. Nothing was lost.",
                delta))
        end
        AP.Log(string.format(
            "Residue reconcile: account=%d ledger=%d physical_before=%d synchronized=%d",
            accountId, ledger, physical, delta))
    end)
end)
print("[EotW] Legacy Forge loaded.")
