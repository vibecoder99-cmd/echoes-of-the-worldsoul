-- ============================================================
-- ap_gm_aether.lua - GM Aether Grant Tool
-- Standalone: drop into lua_scripts, no other changes needed.
-- Commands:
--
--   #ap gmaether <amount>
--       Grants <amount> Aether to yourself.
--
--   #ap gmaether <amount> <playerName>
--       Grants <amount> Aether to another online player.
--
-- Examples:
--   #ap gmaether 50000
--   #ap gmaether 100000 Pramm
-- ============================================================

AP = AP or {}
AP.GM = AP.GM or {}

local function GrantAether(player, targetGuid, targetName, amount)
    -- Read current value BEFORE the write (CharDBQuery is sync, CharDBExecute is async)
    local oldTotal = 0
    local q = CharDBQuery(string.format(
        "SELECT `aether` FROM `ap_mastery` WHERE `guid` = %d", targetGuid
    ))
    if q then
        oldTotal = tonumber(tostring(q:GetUInt64(0))) or 0
    end

    -- Upsert: create mastery row if needed, otherwise add to existing
    CharDBExecute(string.format(
        "INSERT INTO `ap_mastery` (`guid`, `aether`, `mastery`) VALUES (%d, %d, 0) "..
        "ON DUPLICATE KEY UPDATE `aether` = `aether` + %d",
        targetGuid, amount, amount
    ))
    CharDBExecute("COMMIT")

    -- Calculate new total arithmetically rather than reading back
    -- (CharDBExecute is async so a post-write SELECT would race)
    local newTotal = oldTotal + amount

    player:SendBroadcastMessage(string.format(
        "|cff00ccff[Worldsoul GM]|r Granted |cffffff00%d|r Aether to %s. New total: |cffffff00%d|r",
        amount, targetName, newTotal
    ))

    if targetGuid ~= player:GetGUIDLow() then
        local target = GetPlayerByName(targetName)
        if target then
            target:SendBroadcastMessage(string.format(
                "|cff9966ff[Worldsoul]|r A GM granted you |cffffff00%d|r Essence. Total: |cffffff00%d|r",
                amount, newTotal
            ))
        end
    end
end

local function OnChat(event, player, msg, msgType, lang)
    local lower = string.lower(msg)
    if not lower:find("^#ap gmaether") then
        return
    end

    if not AP.IsGM(player) then
        player:SendBroadcastMessage("|cffff4444[Worldsoul]|r GM access required.")
        return false
    end

    -- Parse: #ap gmaether <amount> [playerName]
    local rest = msg:match("^[#][aA][pP]%s+[gG][mM][aA][eE][tT][hH][eE][rR]%s+(.+)") or ""
    rest = rest:match("^%s*(.-)%s*$")

    local tokens = {}
    for t in rest:gmatch("%S+") do
        tokens[#tokens + 1] = t
    end

    local amount = tonumber(tokens[1])
    if not amount or amount < 1 then
        player:SendBroadcastMessage("|cffff4444[Worldsoul GM] Usage: #ap gmaether <amount> [playerName]|r")
        return false
    end
    amount = math.floor(amount)

    local targetGuid
    local targetName

    if tokens[2] then
        local target = GetPlayerByName(tokens[2])
        if not target then
            player:SendBroadcastMessage("|cffff4444[Worldsoul GM] Player not found online: " .. tokens[2] .. "|r")
            return false
        end
        targetGuid = target:GetGUIDLow()
        targetName = target:GetName()
    else
        targetGuid = player:GetGUIDLow()
        targetName = player:GetName()
    end

    GrantAether(player, targetGuid, targetName, amount)
    return false  -- swallow the chat message
end

RegisterPlayerEvent(18, OnChat)  -- PLAYER_EVENT_ON_CHAT

print("[Worldsoul GM] Aether grant tool loaded. Command: #ap gmaether <amount> [player]")
