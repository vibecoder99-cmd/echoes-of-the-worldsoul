-- ============================================================
-- ap_items.lua — Worldsoul Echo Fragment use handler
-- Loads after ap_events.lua (alphabetically). Reads the
-- EotW_EchoFragmentQuality / EotW_EchoFragmentItemEntry
-- session tables set by the loot handler in ap_events.lua.
-- ============================================================

AP = AP or {}

local ECHO_FRAGMENT_ENTRY = 900010

local function OnEchoFragmentUse(event, player, item, target)
    local ok, err = pcall(function()
        local guid      = AP.RT.GetGUID(player)
        local accountId = AP.RT.GetAccountId(player)

        local quality   = EotW_EchoFragmentQuality   and EotW_EchoFragmentQuality[guid]   or 2
        local itemEntry = EotW_EchoFragmentItemEntry and EotW_EchoFragmentItemEntry[guid] or 0

        -- Gold reward (copper: 1g = 10000)
        local goldReward
        if     quality >= 5 then goldReward = 200000   -- 20g Legendary
        elseif quality >= 4 then goldReward = 80000    -- 8g  Epic
        elseif quality >= 3 then goldReward = 30000    -- 3g  Rare
        elseif quality >= 2 then goldReward = 10000    -- 1g  Uncommon
        else                      goldReward = 2000    -- 20s Common/Poor
        end

        -- Essence reward
        local essenceReward
        if     quality >= 5 then essenceReward = 300
        elseif quality >= 4 then essenceReward = 100
        elseif quality >= 3 then essenceReward = 40
        elseif quality >= 2 then essenceReward = 15
        else                      essenceReward = 5
        end

        -- Legacy Surge: 3x Essence, 1.5x gold on 4th+ duplicate
        local isSurge = false
        if itemEntry > 0 then
            local qd = AP.DB.Query(string.format(
                "SELECT `drop_count` FROM `ap_resonant_drops` "..
                "WHERE `account_id` = %d AND `item_entry` = %d",
                accountId, itemEntry))
            if qd then
                if (tonumber(tostring(qd:GetUInt32(0))) or 0) >= 4 then
                    isSurge       = true
                    essenceReward = essenceReward * 3
                    goldReward    = math.floor(goldReward * 1.5)
                end
            end
        end

        -- attunement_echo sink bonus on Essence
        local echoInv   = AP.Sinks and AP.Sinks.GetInvested(accountId, "attunement_echo") or 0
        local echoMult  = 1.0 + (AP.Sinks and AP.Sinks.GetEffect("attunement_echo", echoInv) or 0)
        essenceReward   = math.floor(essenceReward * echoMult)

        -- Threat momentum bonus on fragment rewards
        local session = AP._session and AP._session[guid]
        if session and session.threat > 0 then
            local fragmentThreatMult = AP.GetThreatMult(session.threat, session.momentum or 0)
            essenceReward = math.floor(essenceReward * fragmentThreatMult)
        end

        -- Remove the fragment FIRST to prevent any duplication
        local removed = false
        removed = AP.RT.RemoveItemObject(item)
        if not removed then
            removed = AP.RT.RemoveItem(player, ECHO_FRAGMENT_ENTRY, 1)
        end
        if not removed then
            print("[EotW] WARN: Could not remove Echo Fragment for " .. AP.RT.GetName(player))
            return
        end

        -- Persist the fragment removal before granting rewards.
        -- Without this, a crash between here and the CharDBExecute below
        -- would leave the fragment intact in the DB while Essence is already
        -- durably written — creating a double-Essence path on retry.
        pcall(function() AP.RT.SavePlayerToDB(player,false, false) end)

        -- Grant gold (try GetCoinage/SetCoinage, fall back to ModifyMoney)
        local goldGranted = false
        local cur = AP.RT.GetCoinage(player)
        goldGranted = AP.RT.SetCoinage(player, cur + goldReward)
        if not goldGranted then
            goldGranted = AP.RT.ModifyMoney(player, goldReward)
        end

        -- Grant Essence
        AP.DB.ExecuteAsync(string.format(
            "INSERT INTO `ap_mastery` (`guid`, `aether`, `mastery`) "..
            "VALUES (%d, %d, 0) ON DUPLICATE KEY UPDATE `aether` = `aether` + %d",
            guid, essenceReward, essenceReward))
        AP.DB.ExecuteAsync("COMMIT")

        local goldG = math.floor(goldReward / 10000)
        local goldS = math.floor((goldReward % 10000) / 100)

        if isSurge then
            AP.RT.SendMessage(player,string.format(
                "|cffffd700[Worldsoul]|r |cffff8800Legacy Surge!|r "..
                "The Worldsoul recognizes your persistence. "..
                "|cffffff00+%d Essence|r and |cffffff00%dg %ds|r claimed.",
                essenceReward, goldG, goldS))
            if AP.Visage and AP.Visage.SendFlash then
                AP.Visage.SendFlash(player, "LEGACY SURGE",
                    "The Worldsoul recognizes your persistence.")
            end
        else
            AP.RT.SendMessage(player,string.format(
                "|cffffd700[Worldsoul]|r Echo absorbed. "..
                "|cffffff00+%d Essence|r and |cffffff00%dg %ds|r claimed.",
                essenceReward, goldG, goldS))
        end

        if AP.Tutorial and AP.Tutorial.Trigger then
            AP.Tutorial.Trigger(player, "first_resonant_drop",
                "|cff9966ff[Worldsoul]|r Duplicate items yield both Essence and gold. "..
                "No vendor trip needed. Enchanters may disenchant the fragment instead.")
        end

        -- Clean up session storage
        if EotW_EchoFragmentQuality   then EotW_EchoFragmentQuality[guid]   = nil end
        if EotW_EchoFragmentItemEntry then EotW_EchoFragmentItemEntry[guid] = nil end
    end)
    if not ok then
        print("[EotW] ERROR in OnEchoFragmentUse: " .. tostring(err))
    end
    return false  -- prevent default item spell-cast behavior
end

AP.RT.RegisterItemEvent(ECHO_FRAGMENT_ENTRY, 2, OnEchoFragmentUse)

print("[EotW] Echo Fragment handler loaded. Entry=" .. ECHO_FRAGMENT_ENTRY)
