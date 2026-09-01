local UI = EchoesUI
if not UI then return end

local Store = {
    values = {},
    stamp = nil,
    subscribers = {},
    nextSubscriberId = 0,
}

local supportedFields = {
    "essence", "mastery_rank", "absorb_pct", "attuned", "snapshots",
    "residue", "rack_used", "rack_cap", "talents", "talent_primary_stat",
    "talent_role", "talent_bonus_pct", "talent_next_rank_cost",
    "talent_next_bonus_pct", "talent_max_rank", "talent_distinct_stats",
    "talent_distinct_penalty_pct", "crucible",
    "crucible_status", "crucible_effect_pct", "crucible_ceiling_pct",
    "crucible_total_invested",
    "mastery_next_cost", "slots", "absorbed_stats",
    "threat_level", "threat_name", "threat_max", "threat_ceiling_pct",
    "threat_momentum_pct", "threat_effective_pct", "threat_safety_pct",
    "threat_debt_kills", "threat_debt_mult_pct", "threat_attune_loss_pct",
    "threat_essence_loss_pct", "threat_essence_cap", "threat_penalty_debt_kills",
    "threat_penalty_debt_mult_pct", "threat_cap_normal_pct", "threat_cap_elite_pct",
    "threat_cap_boss_pct", "threat_cap_raid_pct",
    "rack_entries", "rack_candidates", "rack_next_slots",
    "rack_next_essence_cost", "rack_next_residue_cost", "rack_at_max",
    "forge_eligible", "forge_catalyst_status", "forge_catalyst_cost",
    "forge_catalyst_reward", "forge_catalyst_expected_residue",
    "forge_catalyst_expected_essence",
    "visage_primary_theme", "visage_primary_enabled",
    "visage_primary_tier_selected", "visage_primary_tier_effective",
    "visage_primary_tier_max", "visage_secondary_theme",
    "visage_secondary_enabled", "visage_secondary_tier_selected",
    "visage_secondary_tier_effective", "visage_secondary_tier_max",
    "visage_themes_unlocked", "visage_flash_enabled",
    "visage_chat_flavor_enabled", "visage_attuned_count",
    "visage_crucible_invested", "visage_preview_active",
    "chaos_enabled", "chaos_power", "chaos_magnitude", "chaos_scale",
    "chaos_ruleset", "chaos_base", "chaos_attunement_basis",
    "chaos_attunement_contribution", "chaos_mastery_rank", "chaos_mastery_basis",
    "chaos_mastery_contribution", "chaos_crucible_basis", "chaos_crucible_contribution",
}

local numericFields = {
    essence = true,
    mastery_rank = true,
    absorb_pct = true,
    attuned = true,
    snapshots = true,
    residue = true,
    rack_used = true,
    rack_cap = true,
    talent_distinct_stats = true,
    talent_distinct_penalty_pct = true,
    mastery_next_cost = true,
    crucible_total_invested = true,
    threat_level=true, threat_max=true, threat_ceiling_pct=true,
    threat_momentum_pct=true, threat_effective_pct=true, threat_safety_pct=true,
    threat_debt_kills=true, threat_debt_mult_pct=true, threat_attune_loss_pct=true,
    threat_essence_loss_pct=true, threat_essence_cap=true, threat_penalty_debt_kills=true,
    threat_penalty_debt_mult_pct=true, threat_cap_normal_pct=true,
    threat_cap_elite_pct=true, threat_cap_boss_pct=true, threat_cap_raid_pct=true,
    rack_next_slots=true, rack_next_essence_cost=true,
    rack_next_residue_cost=true, rack_at_max=true,
    forge_catalyst_cost=true, forge_catalyst_reward=true,
    forge_catalyst_expected_residue=true, forge_catalyst_expected_essence=true,
    visage_primary_enabled=true, visage_primary_tier_selected=true,
    visage_primary_tier_effective=true, visage_primary_tier_max=true,
    visage_secondary_enabled=true, visage_secondary_tier_selected=true,
    visage_secondary_tier_effective=true, visage_secondary_tier_max=true,
    visage_flash_enabled=true, visage_chat_flavor_enabled=true,
    visage_attuned_count=true, visage_crucible_invested=true,
    visage_preview_active=true,
    chaos_enabled=true, chaos_magnitude=true, chaos_scale=true, chaos_ruleset=true,
    chaos_base=true, chaos_attunement_basis=true, chaos_attunement_contribution=true,
    chaos_mastery_rank=true, chaos_mastery_basis=true, chaos_mastery_contribution=true,
    chaos_crucible_basis=true, chaos_crucible_contribution=true,
}

local function Normalize(key, value)
    if value == nil then return nil end
    if numericFields[key] then
        return tonumber(value)
    end
    return value
end

function Store:Ingest(fields, stamp, forceNotify)
    if type(fields) ~= "table" then return false end

    local changed = {}
    local changedCount = 0
    for _, key in ipairs(supportedFields) do
        local nextValue = Normalize(key, fields[key])
        if self.values[key] ~= nextValue then
            self.values[key] = nextValue
            changed[key] = nextValue
            changedCount = changedCount + 1
        end
    end

    self.stamp = stamp or GetTime()
    if changedCount == 0 and not forceNotify then return false end

    for _, callback in pairs(self.subscribers) do
        UI:SafeCall("StateStore subscriber", callback, self.values, changed, self.stamp)
    end
    return changedCount > 0
end

function Store:Get(key)
    return self.values[key]
end

function Store:GetSnapshot()
    local snapshot = {}
    for _, key in ipairs(supportedFields) do
        snapshot[key] = self.values[key]
    end
    return snapshot, self.stamp
end

function Store:Subscribe(callback)
    if type(callback) ~= "function" then return nil end
    self.nextSubscriberId = self.nextSubscriberId + 1
    local id = self.nextSubscriberId
    self.subscribers[id] = callback
    return function()
        self.subscribers[id] = nil
    end
end

UI.StateStore = Store
UI.modules.StateStore = true

-- Covers reloads where protocol state already exists before this module loads.
if APB and APB.echoes and APB.echoes.lastState then
    Store:Ingest(APB.echoes.lastState, APB.echoes.lastStateTime, true)
end
