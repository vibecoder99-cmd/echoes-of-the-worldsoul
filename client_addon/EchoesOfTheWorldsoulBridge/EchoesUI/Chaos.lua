local UI = EchoesUI
if not UI then return end

local Chaos = {
    suffixes = {"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"},
    listeners = {},
    state = {
        enabled = false,
        power = {mantissa=0, order=0},
        powerRaw = "0",
        magnitude = 0,
        scale = 1000,
        ready = false,
    },
}

local function RoundFormat(value, significant)
    significant = significant or 3
    local absolute = math.abs(value)
    local digits = absolute >= 100 and 3 or (absolute >= 10 and 2 or 1)
    local decimals = math.max(0, math.min(2, significant - digits))
    return string.format("%." .. decimals .. "f", value)
end

function Chaos:FormatParts(mantissa, order, significant)
    mantissa = tonumber(mantissa) or 0
    order = math.max(0, math.floor(tonumber(order) or 0))
    if order < #self.suffixes then
        return RoundFormat(mantissa, significant) .. self.suffixes[order + 1]
    end
    return RoundFormat(mantissa, significant) .. " x 10^" .. tostring(order * 3)
end

function Chaos:Format(value, significant)
    value = tonumber(value) or 0
    local absolute = math.abs(value)
    if absolute < 1000 then return tostring(math.floor(value + (value >= 0 and 0.000001 or -0.000001))) end
    local order = 0
    while absolute >= 1000 and order < 128 do
        value = value / 1000
        absolute = absolute / 1000
        order = order + 1
    end
    return self:FormatParts(value, order, significant)
end

function Chaos:Roman(value)
    local numerals = {"0", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"}
    value = math.floor(tonumber(value) or 0)
    return numerals[value + 1] or tostring(value)
end

function Chaos:GetPowerText()
    if self.state.powerRaw == "0" then return "0" end
    return self:FormatParts(self.state.power.mantissa, self.state.power.order, 4)
end

local function ParsePower(raw)
    raw = tostring(raw or "0"):match("^(%d+)$") or "0"
    raw = raw:gsub("^0+", "")
    if raw == "" then return {mantissa=0,order=0}, "0" end
    local order = math.floor((#raw - 1) / 3)
    local leading = #raw - order * 3
    local take = math.min(#raw, leading + 3)
    local digits = tonumber(raw:sub(1,take)) or 0
    return {mantissa=digits / (10 ^ (take - leading)),order=order}, raw
end

function Chaos:GetMagnitudeText()
    return "MAGNITUDE " .. self:Roman(self.state.magnitude)
end

function Chaos:GetMagnitudeName(value)
    value = math.floor(tonumber(value) or self.state.magnitude or 0)
    if value <= 0 then return "QUIET" end
    local names = {"STIRRING", "RESONANT", "ELEVATED", "ASCENDANT", "TRANSCENDENT"}
    return names[value] or "UNBOUNDED"
end

function Chaos:GetMagnitudeDisplayText()
    return self:GetMagnitudeText() .. "  |  " .. self:GetMagnitudeName()
end

function Chaos:GetScale(unit)
    unit = unit or "target"
    local level = type(UnitLevel) == "function" and tonumber(UnitLevel(unit)) or 1
    if level == -1 then level = 80 end
    level = math.max(1, math.min(80, level or 1))
    -- Native Wrath health already rises sharply with level. Tapering the
    -- presentation multiplier lets that real hierarchy drive the journey
    -- instead of compounding it into endgame notation during early leveling.
    local anchors = {
        {1, 1000}, {10, 600}, {30, 300}, {50, 180},
        {60, 140}, {70, 120}, {80, 100},
    }
    local scale = anchors[#anchors][2]
    for index = 2, #anchors do
        local low, high = anchors[index - 1], anchors[index]
        if level <= high[1] then
            local progress = (level - low[1]) / (high[1] - low[1])
            scale = low[2] + (high[2] - low[2]) * progress
            break
        end
    end

    return math.floor(scale * ((tonumber(self.state.scale) or 1000) / 1000) + 0.5)
end

function Chaos:GetEffectiveHealth(value, unit)
    return (tonumber(value) or 0) * self:GetScale(unit)
end

-- Stable target-independent reference for static equipment and paper-doll
-- output. Actual combat presentation continues to use destination scale.
function Chaos:GetPersonalScale()
    return self:GetScale("player")
end

function Chaos:Subscribe(callback)
    self.listeners[#self.listeners + 1] = callback
    callback(self.state, "initial")
    return callback
end

function Chaos:Notify(reason)
    for _, callback in ipairs(self.listeners) do
        UI:SafeCall("Chaos state listener", callback, self.state, reason)
    end
end

function Chaos:SetEnabled(enabled)
    enabled = enabled == true
    if not (APB and APB.RequestEchoesAction) then return false end
    return APB:RequestEchoesAction("chaos_toggle", enabled and 1 or 0)
end

function Chaos:Toggle()
    self:SetEnabled(not self.state.enabled)
end

function Chaos:ApplyState(values, reason)
    values = values or {}
    if values.enabled ~= nil then self.state.enabled = values.enabled == true end
    if values.power then self.state.power, self.state.powerRaw = ParsePower(values.power) end
    if values.magnitude then self.state.magnitude = tonumber(values.magnitude) or self.state.magnitude end
    if values.scale then self.state.scale = tonumber(values.scale) or self.state.scale end
    if values.ready ~= nil then self.state.ready = values.ready == true end
    self:Notify(reason or "state")
end

-- Authoritative presentation-application seam. StateStore may already be
-- hydrated before this module loads (notably after login/relog), so both the
-- live subscriber and the initial snapshot must converge here. Presentation
-- modules subscribe to Chaos and therefore receive the same idempotent state
-- regardless of whether it came from a toggle response or initial hydration.
function Chaos:ApplyAuthoritativeState(values, reason)
    if type(values) ~= "table" or values.chaos_power == nil then return false end
    self:ApplyState({
        enabled = tonumber(values.chaos_enabled) == 1,
        power = values.chaos_power,
        magnitude = values.chaos_magnitude,
        scale = values.chaos_scale,
        ready = true,
    }, reason or "server_state")
    return true
end

if UI.StateStore then
    UI.StateStore:Subscribe(function(values)
        Chaos:ApplyAuthoritativeState(values, "server_state")
    end)
    -- Subscribe is intentionally edge-triggered. Explicitly replay the
    -- current snapshot so a STATE packet ingested before Chaos.lua loaded is
    -- not mistaken for an OFF/default presentation state.
    Chaos:ApplyAuthoritativeState(UI.StateStore.values, "initial_hydration")
end
if APB and APB.SubscribeEchoesActions then
    APB:SubscribeEchoesActions(function(verb,fields)
        if verb=="ACTION_OK" and fields.action=="chaos_toggle" and APB.RequestEchoesState then APB:RequestEchoesState() end
    end)
end
UI.Chaos = Chaos
UI.modules.Chaos = true
