-- ============================================================
-- ap_visage.lua -- Echoes of the Worldsoul: Cosmetic Ascension
-- Handles primary/secondary auras, Visage gossip menu,
-- attunement milestone flash triggers, theme and tier management.
-- ============================================================

AP = AP or {}
AP.Visage = AP.Visage or {}

-- ============================================================
-- AURA SPELL ID TABLE
-- Each theme has 5 tiers (T1=subtle, T5=dramatic)
-- All IDs verified safe, persistent, player-following via Aura Lab.
-- ============================================================
AP.Visage.ThemeSpells = {
    worldsoul = { 34403, 49411, 22576, 46933, 42051 },
    ethereal  = { 47840, 44816, 30987, 22581, 42047 },
    verdant   = { 18951, 44808, 40071, 33339, 42050 },
    void      = { 34399, 33569, 30166, 49646, 22578 },
    infernal  = { 34398, 33827, 62300, 42075, 42048 },
}

AP.Visage.ThemeUnlocks = {
    worldsoul = 0,
    ethereal  = 25,
    verdant   = 50,
    void      = 100,
    infernal  = 250,
}

AP.Visage.ThemeNames = {
    worldsoul = "Worldsoul",
    void      = "Void",
    infernal  = "Infernal",
    ethereal  = "Ethereal",
    verdant   = "Verdant",
}

AP.Visage.ThemeColors = {
    worldsoul = "88bbff",
    void      = "9944cc",
    infernal  = "ff4400",
    ethereal  = "ddddff",
    verdant   = "44cc44",
}

AP.Visage.PrimaryTiers = { 10, 25, 50, 100, 250 }
AP.Visage.SecondaryTiers = { 100000, 250000, 500000, 1000000, 2000000 }
AP.Visage.ThemeOrder = { "worldsoul", "ethereal", "verdant", "void", "infernal" }

local TIER_NAMES = { "T1 Subtle", "T2 Low", "T3 Medium", "T4 Strong", "T5 Dramatic" }

-- ============================================================
-- DB MIGRATION
-- ============================================================
local function MigrateVisageDb()
    pcall(function()
        CharDBQuery("ALTER TABLE `ap_visage` ADD COLUMN `primary_tier_selected` TINYINT UNSIGNED NOT NULL DEFAULT 0")
    end)
    pcall(function()
        CharDBQuery("ALTER TABLE `ap_visage` ADD COLUMN `secondary_tier_selected` TINYINT UNSIGNED NOT NULL DEFAULT 0")
    end)
end
MigrateVisageDb()

-- ============================================================
-- SESSION CACHE
-- ============================================================
AP.Visage.Cache = AP.Visage.Cache or {}

function AP.Visage.LoadForChar(guid)
    local defaults = {
        primary_theme          = "worldsoul",
        primary_enabled        = 1,
        primary_tier_selected  = 0,
        secondary_theme        = "worldsoul",
        secondary_enabled      = 1,
        secondary_tier_selected = 0,
        flash_enabled          = 1,
        chat_flavor_enabled    = 1,
    }
    local ok, _ = pcall(function()
        local q = CharDBQuery(string.format(
            "SELECT `primary_theme`,`primary_enabled`,`secondary_theme`,"..
            "`secondary_enabled`,`flash_enabled`,`chat_flavor_enabled`,"..
            "`primary_tier_selected`,`secondary_tier_selected` "..
            "FROM `ap_visage` WHERE `guid` = %d",
            guid
        ))
        if q then
            defaults.primary_theme          = q:GetString(0)
            defaults.primary_enabled        = tonumber(tostring(q:GetUInt32(1))) or 1
            defaults.secondary_theme        = q:GetString(2)
            defaults.secondary_enabled      = tonumber(tostring(q:GetUInt32(3))) or 1
            defaults.flash_enabled          = tonumber(tostring(q:GetUInt32(4))) or 1
            defaults.chat_flavor_enabled    = tonumber(tostring(q:GetUInt32(5))) or 1
            defaults.primary_tier_selected  = tonumber(tostring(q:GetUInt32(6))) or 0
            defaults.secondary_tier_selected = tonumber(tostring(q:GetUInt32(7))) or 0
        end
    end)
    if not ok then
        pcall(function()
            local q = CharDBQuery(string.format(
                "SELECT `primary_theme`,`primary_enabled`,`secondary_theme`,"..
                "`secondary_enabled`,`flash_enabled`,`chat_flavor_enabled` "..
                "FROM `ap_visage` WHERE `guid` = %d",
                guid
            ))
            if q then
                defaults.primary_theme       = q:GetString(0)
                defaults.primary_enabled     = tonumber(tostring(q:GetUInt32(1))) or 1
                defaults.secondary_theme     = q:GetString(2)
                defaults.secondary_enabled   = tonumber(tostring(q:GetUInt32(3))) or 1
                defaults.flash_enabled       = tonumber(tostring(q:GetUInt32(4))) or 1
                defaults.chat_flavor_enabled = tonumber(tostring(q:GetUInt32(5))) or 1
            end
        end)
    end
    AP.Visage.Cache[guid] = defaults
end

function AP.Visage.SaveForChar(guid)
    local c = AP.Visage.Cache[guid]
    if not c then return end
    CharDBExecute(string.format(
        "INSERT INTO `ap_visage` (`guid`,`primary_theme`,`primary_enabled`,"..
        "`secondary_theme`,`secondary_enabled`,`flash_enabled`,`chat_flavor_enabled`,"..
        "`primary_tier_selected`,`secondary_tier_selected`) "..
        "VALUES (%d,'%s',%d,'%s',%d,%d,%d,%d,%d) "..
        "ON DUPLICATE KEY UPDATE "..
        "`primary_theme`='%s', `primary_enabled`=%d, "..
        "`secondary_theme`='%s', `secondary_enabled`=%d, "..
        "`flash_enabled`=%d, `chat_flavor_enabled`=%d, "..
        "`primary_tier_selected`=%d, `secondary_tier_selected`=%d",
        guid,
        c.primary_theme, c.primary_enabled,
        c.secondary_theme, c.secondary_enabled,
        c.flash_enabled, c.chat_flavor_enabled,
        c.primary_tier_selected or 0, c.secondary_tier_selected or 0,
        c.primary_theme, c.primary_enabled,
        c.secondary_theme, c.secondary_enabled,
        c.flash_enabled, c.chat_flavor_enabled,
        c.primary_tier_selected or 0, c.secondary_tier_selected or 0
    ))
    CharDBExecute("COMMIT")
end

-- ============================================================
-- TIER CALCULATION
-- ============================================================

function AP.Visage.GetPrimaryTier(attunedCount)
    local tier = 0
    for i, threshold in ipairs(AP.Visage.PrimaryTiers) do
        if attunedCount >= threshold then tier = i end
    end
    return tier
end

function AP.Visage.GetSecondaryTier(totalInvested)
    local tier = 0
    for i, threshold in ipairs(AP.Visage.SecondaryTiers) do
        if totalInvested >= threshold then tier = i end
    end
    return tier
end

function AP.Visage.GetAttunedCount(guid)
    local q = CharDBQuery(string.format(
        "SELECT COUNT(*) FROM `ap_item_attune` WHERE `guid` = %d AND `attuned` = 1",
        guid
    ))
    if q then return tonumber(tostring(q:GetUInt32(0))) or 0 end
    return 0
end

function AP.Visage.GetTotalCrucibleInvested(accountId)
    local q = CharDBQuery(string.format(
        "SELECT SUM(`invested`) FROM `ap_aether_sinks` WHERE `account_id` = %d",
        accountId
    ))
    if q then return tonumber(tostring(q:GetUInt32(0))) or 0 end
    return 0
end

function AP.Visage.IsThemeUnlocked(theme, attunedCount)
    local req = AP.Visage.ThemeUnlocks[theme] or 999
    return attunedCount >= req
end

-- Resolve effective tier: clamp selected to unlocked max, 0 = auto (highest)
function AP.Visage.GetEffectiveTier(selectedTier, unlockedTier)
    if selectedTier == 0 or selectedTier == nil then
        return unlockedTier
    end
    if selectedTier > unlockedTier then
        return unlockedTier
    end
    return selectedTier
end

-- ============================================================
-- AURA APPLICATION (single path for all callers)
-- ============================================================

AP.Visage.AllSpellIds = {}
for _, spells in pairs(AP.Visage.ThemeSpells) do
    for _, id in ipairs(spells) do
        AP.Visage.AllSpellIds[id] = true
    end
end

function AP.Visage.ApplyAuras(player)
    local ok, err = pcall(function()
        local guid      = player:GetGUIDLow()
        local accountId = player:GetAccountId()

        if not AP.Visage.Cache[guid] then
            AP.Visage.LoadForChar(guid)
        end
        local c = AP.Visage.Cache[guid]

        local attunedCount   = AP.Visage.GetAttunedCount(guid)
        local totalInvested  = AP.Visage.GetTotalCrucibleInvested(accountId)
        local primaryMax     = AP.Visage.GetPrimaryTier(attunedCount)
        local secondaryMax   = AP.Visage.GetSecondaryTier(totalInvested)

        local targetPrimary   = nil
        local targetSecondary = nil

        if c.primary_enabled == 1 and primaryMax > 0 then
            local effectiveTier = AP.Visage.GetEffectiveTier(c.primary_tier_selected, primaryMax)
            local spells = AP.Visage.ThemeSpells[c.primary_theme]
            if spells and effectiveTier > 0 then
                targetPrimary = spells[effectiveTier]
            end
        end

        if c.secondary_enabled == 1 and secondaryMax > 0 then
            local effectiveTier = AP.Visage.GetEffectiveTier(c.secondary_tier_selected, secondaryMax)
            local spells = AP.Visage.ThemeSpells[c.secondary_theme]
            if spells and effectiveTier > 0 then
                targetSecondary = spells[effectiveTier]
            end
        end

        for spellId, _ in pairs(AP.Visage.AllSpellIds) do
            if spellId ~= targetPrimary and spellId ~= targetSecondary then
                pcall(function() player:RemoveAura(spellId) end)
            end
        end

        if targetPrimary then
            pcall(function() player:AddAura(targetPrimary, player) end)
        end

        if targetSecondary and targetSecondary ~= targetPrimary then
            pcall(function() player:AddAura(targetSecondary, player) end)
        end
    end)
    if not ok then
        print("[EotW Visage] ERROR in ApplyAuras: " .. tostring(err))
    end
end

-- ============================================================
-- FLASH TRIGGER
-- ============================================================

function AP.Visage.SendFlash(player, title, subtitle)
    local c = AP.Visage.Cache[player:GetGUIDLow()]
    if c and c.flash_enabled == 0 then return end
    local payload
    if subtitle and subtitle ~= "" then
        payload = "[EOTW_FLASH]" .. title .. "|" .. subtitle
    else
        payload = "[EOTW_FLASH]" .. title
    end
    player:SendBroadcastMessage(payload)
end

-- ============================================================
-- ATTUNEMENT MILESTONE CHECK
-- ============================================================

AP.Visage.LastKnownPrimaryTier = AP.Visage.LastKnownPrimaryTier or {}
AP.Visage.LastKnownThemeUnlocks = AP.Visage.LastKnownThemeUnlocks or {}

function AP.Visage.CheckAttunementMilestone(player, newAttunedCount)
    local guid = player:GetGUIDLow()
    local newTier = AP.Visage.GetPrimaryTier(newAttunedCount)
    local oldTier = AP.Visage.LastKnownPrimaryTier[guid] or 0

    if newTier > oldTier then
        AP.Visage.LastKnownPrimaryTier[guid] = newTier
        if newTier == 1 and AP.Tutorial and AP.Tutorial.Trigger then
            AP.Tutorial.Trigger(player, "first_visage")
        end
        local flash = AP.AttunementFlashes and AP.AttunementFlashes[AP.Visage.PrimaryTiers[newTier]]
        if flash then
            AP.Visage.SendFlash(player, flash[1], flash[2])
        end
        AP.Visage.ApplyAuras(player)
    end

    for _, theme in ipairs(AP.Visage.ThemeOrder) do
        local req = AP.Visage.ThemeUnlocks[theme]
        if req > 0 then
            local key = guid .. "_" .. theme
            if not AP.Visage.LastKnownThemeUnlocks[key] and newAttunedCount >= req then
                AP.Visage.LastKnownThemeUnlocks[key] = true
                player:SendBroadcastMessage(string.format(
                    "|cff9966ff[Worldsoul]|r The |cff%s%s|r Visage has been unlocked. "..
                    "Find it in your Visage menu.",
                    AP.Visage.ThemeColors[theme] or "ffffff",
                    AP.Visage.ThemeNames[theme]
                ))
            end
        end
    end
end

-- ============================================================
-- CRUCIBLE MILESTONE CHECK
-- ============================================================

AP.Visage.LastKnownCrucibleTier = AP.Visage.LastKnownCrucibleTier or {}

function AP.Visage.CheckCrucibleMilestone(player, totalInvested)
    local guid = player:GetGUIDLow()
    local newTier = AP.Visage.GetSecondaryTier(totalInvested)
    local oldTier = AP.Visage.LastKnownCrucibleTier[guid] or 0

    if newTier > oldTier then
        AP.Visage.LastKnownCrucibleTier[guid] = newTier
        local threshold = AP.Visage.SecondaryTiers[newTier]
        local flash = AP.CrucibleFlashes and AP.CrucibleFlashes[threshold]
        if flash then
            AP.Visage.SendFlash(player, flash[1], flash[2])
        end
        AP.Visage.ApplyAuras(player)
    end
end

-- ============================================================
-- VISAGE GOSSIP MENU
-- 200 = display only
-- 201 = open Visage main page
-- 202 = toggle primary aura
-- 203 = toggle secondary aura
-- 204 = toggle flash
-- 205 = toggle chat flavor
-- 206 = select primary theme (code = ThemeOrder index)
-- 207 = select secondary theme (code = ThemeOrder index)
-- 208 = back to main menu
-- 209 = select primary tier (code = tier 1-5, or 0 = auto)
-- 217 = select secondary tier (code = tier 1-5, or 0 = auto)
-- ============================================================

function AP.Visage.ShowPage(player, npc)
    local guid      = player:GetGUIDLow()
    local accountId = player:GetAccountId()

    if not AP.Visage.Cache[guid] then
        AP.Visage.LoadForChar(guid)
    end
    local c = AP.Visage.Cache[guid]

    if AP.Tutorial and AP.Tutorial.Trigger then
        AP.Tutorial.Trigger(player, "first_visage_open")
    end

    local attunedCount  = AP.Visage.GetAttunedCount(guid)
    local totalInvested = AP.Visage.GetTotalCrucibleInvested(accountId)
    local primaryMax    = AP.Visage.GetPrimaryTier(attunedCount)
    local secondaryMax  = AP.Visage.GetSecondaryTier(totalInvested)
    local priEffective  = AP.Visage.GetEffectiveTier(c.primary_tier_selected, primaryMax)
    local secEffective  = AP.Visage.GetEffectiveTier(c.secondary_tier_selected, secondaryMax)

    local priTierLabel = (c.primary_tier_selected == 0) and "Auto" or (TIER_NAMES[priEffective] or "?")
    local secTierLabel = (c.secondary_tier_selected == 0) and "Auto" or (TIER_NAMES[secEffective] or "?")

    player:GossipClearMenu()

    local primaryStatus = c.primary_enabled == 1 and "|cff00ff00ON|r" or "|cffff4444OFF|r"
    local secondaryStatus = c.secondary_enabled == 1 and "|cff00ff00ON|r" or "|cffff4444OFF|r"
    local flashStatus = c.flash_enabled == 1 and "|cff00ff00ON|r" or "|cffff4444OFF|r"
    local flavorStatus = c.chat_flavor_enabled == 1 and "|cff00ff00ON|r" or "|cffff4444OFF|r"

    local header = string.format(
        "Visage -- Shape your legend.\n"..
        "Echoes: |cffffff00%d|r  Crucible: |cffffff00%d|r\n"..
        "Primary: %s %s [%s] (%d/%d unlocked)\n"..
        "Secondary: %s %s [%s] (%d/%d unlocked)\n"..
        "Flash: %s  Lore: %s",
        attunedCount, totalInvested,
        primaryStatus, AP.Visage.ThemeNames[c.primary_theme] or "?", priTierLabel, priEffective, primaryMax,
        secondaryStatus, AP.Visage.ThemeNames[c.secondary_theme] or "?", secTierLabel, secEffective, secondaryMax,
        flashStatus, flavorStatus
    )
    player:GossipMenuAddItem(0, header, 200, 0, false, "", 0)

    -- Toggles
    player:GossipMenuAddItem(0,
        c.primary_enabled == 1 and "Primary Aura: Turn OFF" or "Primary Aura: Turn ON",
        202, 0, false, "", 0)
    player:GossipMenuAddItem(0,
        c.secondary_enabled == 1 and "Secondary Aura: Turn OFF" or "Secondary Aura: Turn ON",
        203, 0, false, "", 0)
    player:GossipMenuAddItem(0,
        c.flash_enabled == 1 and "Victory Flash: Turn OFF" or "Victory Flash: Turn ON",
        204, 0, false, "", 0)
    player:GossipMenuAddItem(0,
        c.chat_flavor_enabled == 1 and "Lore Notifications: Turn OFF" or "Lore Notifications: Turn ON",
        205, 0, false, "", 0)

    -- Primary theme
    player:GossipMenuAddItem(0, "-- Primary Theme --", 200, 0, false, "", 0)
    for i, theme in ipairs(AP.Visage.ThemeOrder) do
        local unlocked = AP.Visage.IsThemeUnlocked(theme, attunedCount)
        local current  = c.primary_theme == theme and " [CURRENT]" or ""
        if unlocked then
            player:GossipMenuAddItem(0, AP.Visage.ThemeNames[theme] .. current, 206, i, false, "", 0)
        else
            player:GossipMenuAddItem(0, string.format("|cff888888%s (%d echoes)|r",
                AP.Visage.ThemeNames[theme], AP.Visage.ThemeUnlocks[theme]), 200, 0, false, "", 0)
        end
    end

    -- Primary tier
    player:GossipMenuAddItem(0, "-- Primary Intensity --", 200, 0, false, "", 0)
    local priAutoLabel = "Auto (highest)" .. ((c.primary_tier_selected == 0) and " [CURRENT]" or "")
    player:GossipMenuAddItem(0, priAutoLabel, 209, 0, false, "", 0)
    for t = 1, 5 do
        local current = (c.primary_tier_selected == t) and " [CURRENT]" or ""
        if t <= primaryMax then
            player:GossipMenuAddItem(0, TIER_NAMES[t] .. current, 209, t, false, "", 0)
        else
            local req = AP.Visage.PrimaryTiers[t] or 0
            player:GossipMenuAddItem(0, string.format("|cff888888%s (%d echoes)|r", TIER_NAMES[t], req), 200, 0, false, "", 0)
        end
    end

    -- Secondary theme
    player:GossipMenuAddItem(0, "-- Secondary Theme --", 200, 0, false, "", 0)
    for i, theme in ipairs(AP.Visage.ThemeOrder) do
        local unlocked = AP.Visage.IsThemeUnlocked(theme, attunedCount)
        local current  = c.secondary_theme == theme and " [CURRENT]" or ""
        if unlocked then
            player:GossipMenuAddItem(0, AP.Visage.ThemeNames[theme] .. current, 207, i, false, "", 0)
        else
            player:GossipMenuAddItem(0, string.format("|cff888888%s (%d echoes)|r",
                AP.Visage.ThemeNames[theme], AP.Visage.ThemeUnlocks[theme]), 200, 0, false, "", 0)
        end
    end

    -- Secondary tier
    player:GossipMenuAddItem(0, "-- Secondary Intensity --", 200, 0, false, "", 0)
    local secAutoLabel = "Auto (highest)" .. ((c.secondary_tier_selected == 0) and " [CURRENT]" or "")
    player:GossipMenuAddItem(0, secAutoLabel, 217, 0, false, "", 0)
    for t = 1, 5 do
        local current = (c.secondary_tier_selected == t) and " [CURRENT]" or ""
        if t <= secondaryMax then
            player:GossipMenuAddItem(0, TIER_NAMES[t] .. current, 217, t, false, "", 0)
        else
            local req = AP.Visage.SecondaryTiers[t] or 0
            local reqLabel = req >= 1000000 and string.format("%dM", req / 1000000) or string.format("%dk", req / 1000)
            player:GossipMenuAddItem(0, string.format("|cff888888%s (%s invested)|r", TIER_NAMES[t], reqLabel), 200, 0, false, "", 0)
        end
    end

    player:GossipMenuAddItem(0, "<< Back to Main Menu", 208, 0, false, "", 0)
    player:GossipSendMenu(1, npc, 201)
end

function AP.Visage.OnSelect(player, npc, sender, code)
    local guid = player:GetGUIDLow()
    if not AP.Visage.Cache[guid] then
        AP.Visage.LoadForChar(guid)
    end
    local c = AP.Visage.Cache[guid]

    if sender == 200 then
        AP.Visage.ShowPage(player, npc)

    elseif sender == 201 then
        AP.Visage.ShowPage(player, npc)

    elseif sender == 202 then
        c.primary_enabled = c.primary_enabled == 1 and 0 or 1
        AP.Visage.SaveForChar(guid)
        AP.Visage.ApplyAuras(player)
        AP.Visage.ShowPage(player, npc)

    elseif sender == 203 then
        c.secondary_enabled = c.secondary_enabled == 1 and 0 or 1
        AP.Visage.SaveForChar(guid)
        AP.Visage.ApplyAuras(player)
        AP.Visage.ShowPage(player, npc)

    elseif sender == 204 then
        c.flash_enabled = c.flash_enabled == 1 and 0 or 1
        AP.Visage.SaveForChar(guid)
        AP.Visage.ShowPage(player, npc)

    elseif sender == 205 then
        c.chat_flavor_enabled = c.chat_flavor_enabled == 1 and 0 or 1
        AP.Visage.SaveForChar(guid)
        AP.Visage.ShowPage(player, npc)

    elseif sender == 206 then
        local theme = AP.Visage.ThemeOrder[code]
        local attunedCount = AP.Visage.GetAttunedCount(guid)
        if theme and AP.Visage.IsThemeUnlocked(theme, attunedCount) then
            local old = c.primary_theme
            c.primary_theme = theme
            AP.Visage.SaveForChar(guid)
            AP.Visage.ApplyAuras(player)
            if AP.API and AP.API.DispatchHook then
                AP.API.DispatchHook("OnVisageChanged", { guid=guid, field="primary_theme", oldValue=old, newValue=theme })
            end
            player:SendBroadcastMessage(string.format(
                "|cff9966ff[Worldsoul]|r Primary Visage set to %s.",
                AP.Visage.ThemeNames[theme]))
        end
        AP.Visage.ShowPage(player, npc)

    elseif sender == 207 then
        local theme = AP.Visage.ThemeOrder[code]
        local attunedCount = AP.Visage.GetAttunedCount(guid)
        if theme and AP.Visage.IsThemeUnlocked(theme, attunedCount) then
            local old = c.secondary_theme
            c.secondary_theme = theme
            AP.Visage.SaveForChar(guid)
            AP.Visage.ApplyAuras(player)
            if AP.API and AP.API.DispatchHook then
                AP.API.DispatchHook("OnVisageChanged", { guid=guid, field="secondary_theme", oldValue=old, newValue=theme })
            end
            player:SendBroadcastMessage(string.format(
                "|cff9966ff[Worldsoul]|r Secondary Visage set to %s.",
                AP.Visage.ThemeNames[theme]))
        end
        AP.Visage.ShowPage(player, npc)

    elseif sender == 208 then
        if AP.OpenUI then
            AP.OpenUI(player)
        end

    elseif sender == 209 then
        c.primary_tier_selected = code
        AP.Visage.SaveForChar(guid)
        AP.Visage.ApplyAuras(player)
        local label = code == 0 and "Auto (highest)" or (TIER_NAMES[code] or "?")
        player:SendBroadcastMessage(string.format(
            "|cff9966ff[Worldsoul]|r Primary intensity set to %s.", label))
        AP.Visage.ShowPage(player, npc)

    elseif sender == 217 then
        c.secondary_tier_selected = code
        AP.Visage.SaveForChar(guid)
        AP.Visage.ApplyAuras(player)
        local label = code == 0 and "Auto (highest)" or (TIER_NAMES[code] or "?")
        player:SendBroadcastMessage(string.format(
            "|cff9966ff[Worldsoul]|r Secondary intensity set to %s.", label))
        AP.Visage.ShowPage(player, npc)
    end
end

-- ============================================================
-- LOGIN HOOK
-- ============================================================

local function OnLogin_Visage(event, player)
    local ok, err = pcall(function()
        local guid = player:GetGUIDLow()
        AP.Visage.LoadForChar(guid)
        local playerGuid = guid
        CreateLuaEvent(function()
            local livePlayer = GetPlayerByGUID(playerGuid)
            if not livePlayer then return end
            AP.Visage.ApplyAuras(livePlayer)
        end, 3000, 1)
    end)
    if not ok then
        print("[EotW Visage] ERROR in OnLogin_Visage: " .. tostring(err))
    end
end

RegisterPlayerEvent(3, OnLogin_Visage)

print("[EotW Visage] Cosmetic Ascension system loaded (v2 - tier selection).")
