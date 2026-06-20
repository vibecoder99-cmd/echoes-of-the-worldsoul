-- ============================================================
-- ap_pvp.lua
-- Echoes of the Worldsoul — PvP Integration (Layer 1-2)
-- Layer 1: Honor kill Essence
-- Layer 2: Battleground win/loss Essence
-- Layer 3 (arena end event, rating milestones, BG objectives):
--   DEFERRED — no Eluna hooks available in this AzerothCore build
-- ============================================================

AP     = AP     or {}
AP.PvP = AP.PvP or {}

-- ---- Config ----
AP.PvP.Config = {
    enabled          = true,
    honorKillEnabled = true,
    bgEssenceEnabled = true,
}

AP.PvP.Values = {
    honorKillBase = 15,
    bgWinBase     = 200,
    bgLossBase    = 75,
}

-- ---- Helper ----
local function GrantEssence(guid, amount)
    CharDBExecute(string.format([[
        INSERT INTO `ap_mastery` (`guid`, `aether`)
        VALUES (%d, %d)
        ON DUPLICATE KEY UPDATE `aether` = `aether` + %d;
    ]], guid, amount, amount))
    CharDBExecute("COMMIT")
end

-- ============================================================
-- LAYER 1: Honor kill Essence
-- PLAYER_EVENT_ON_KILL_PLAYER = 6  →  (event, killer, killed)
-- ============================================================
local function OnHonorableKill(event, killer, killed)
    if not AP.PvP.Config.enabled or not AP.PvP.Config.honorKillEnabled then return end
    if not killer or not killed then return end
    pcall(function()
        local guid   = killer:GetGUIDLow()
        local amount = AP.PvP.Values.honorKillBase
        GrantEssence(guid, amount)
        killer:SendBroadcastMessage(string.format(
            "|cff9966ff[Worldsoul]|r A foe falls. +%d Essence.", amount))
        if AP.Tutorial and AP.Tutorial.Trigger then
            AP.Tutorial.Trigger(killer, "first_pvp_essence")
        end
    end)
end

RegisterPlayerEvent(6, OnHonorableKill)

-- ============================================================
-- LAYER 2: Battleground win/loss Essence
-- BG_EVENT_ON_END = 2  →  (event, bg, bgId, instanceId, winner)
-- winner = TeamId of winning faction (1=Horde, 2=Alliance, 0=none)
--
-- bg:GetPlayers() does NOT exist in this Eluna build.
-- We iterate GetPlayersInWorld() and filter by InBattleground()
-- + GetBattlegroundId() == instanceId.
-- ============================================================
local BG_EVENT_ON_END = 2

local function OnBGEnd(event, bg, bgId, instanceId, winner)
    if not AP.PvP.Config.enabled or not AP.PvP.Config.bgEssenceEnabled then return end
    if winner == 0 then return end  -- draw / no winner
    pcall(function()
        local allPlayers = GetPlayersInWorld()
        if not allPlayers then return end
        for _, player in ipairs(allPlayers) do
            pcall(function()
                if not player:InBattleground() then return end
                if player:GetBattlegroundId() ~= instanceId then return end
                local guid     = player:GetGUIDLow()
                local isWinner = (player:GetTeam() == winner)
                local amount   = isWinner and AP.PvP.Values.bgWinBase or AP.PvP.Values.bgLossBase
                GrantEssence(guid, amount)
                local msg = isWinner
                    and string.format("|cff9966ff[Worldsoul]|r Victory. +%d Essence.", amount)
                    or  string.format("|cff9966ff[Worldsoul]|r A hard-fought defeat. +%d Essence.", amount)
                player:SendBroadcastMessage(msg)
                if AP.Tutorial and AP.Tutorial.Trigger then
                    AP.Tutorial.Trigger(player, "first_pvp_essence")
                end
            end)
        end
    end)
end

RegisterBGEvent(BG_EVENT_ON_END, OnBGEnd)

print("[EotW] PvP Integration loaded (honor kills + BG end rewards).")
