local UI = EchoesUI
if not UI or not UI.Chaos then return end

local Chaos = UI.Chaos
local Tooltip = { hooked = {}, states = setmetatable({}, { __mode = "k" }) }
local ACCENT = "|cff66ccff"
local MUTED = "|cffaaa49a"
local CLOSE = "|r"

local function Plain(text)
    return tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function Number(text)
    return tonumber((tostring(text or ""):gsub(",", "")))
end

local function TooltipLines(tooltip)
    local name = tooltip and type(tooltip.GetName) == "function" and tooltip:GetName() or nil
    if not name or type(tooltip.NumLines) ~= "function" then return nil end
    local lines = {}
    for index = 1, tooltip:NumLines() do
        local region = _G[name .. "TextLeft" .. index]
        lines[#lines + 1] = Plain(region and region:GetText() or "")
    end
    return lines
end

local function Range(line, phrase)
    local low, high = line:match(phrase .. "%s+([%d,]+%.?%d*)%s+to%s+([%d,]+%.?%d*)")
    if not low then low, high = line:match(phrase .. "%s+([%d,]+%.?%d*)%s*%-%s*([%d,]+%.?%d*)") end
    if low then return Number(low), Number(high) end
    local value = line:match(phrase .. "%s+([%d,]+%.?%d*)")
    value = Number(value)
    return value, value
end

function Tooltip:ClassifyLine(text)
    local line = Plain(text)
    local lower = line:lower()
    if lower:find("%%") then return nil end

    local low, high
    if lower:find("damage") and (lower:find("every %d") or lower:find("over [%d,]+%.?%d* sec")) then
        low, high = Range(lower, "deals")
        if not low then low, high = Range(lower, "causes") end
        if not low then low, high = Range(lower, "causing") end
        if not low then low, high = Range(lower, "for") end
        if low then return { kind="periodic_damage", low=low, high=high } end
    end
    if (lower:find("heal") or lower:find("restores? [%d,]+%.?%d* health")) and
        (lower:find("every %d") or lower:find("over [%d,]+%.?%d* sec")) then
        low, high = Range(lower, "heals?[^%d]*for")
        if not low then low, high = Range(lower, "restores?") end
        if low then return { kind="periodic_heal", low=low, high=high } end
    end
    if lower:find("absorbs? [%d,]+%.?%d* damage") then
        low, high = Range(lower, "absorbs?")
        if low then return { kind="absorb", low=low, high=high } end
    end
    if lower:find("damage") then
        low, high = Range(lower, "deals")
        if not low then low, high = Range(lower, "causes") end
        if not low then low, high = Range(lower, "causing") end
        if low then return { kind="damage", low=low, high=high } end
    end
    if lower:find("heal") or lower:find("restores? [%d,]+%.?%d* health") then
        low, high = Range(lower, "heals?[^%d]*for")
        if not low then low, high = Range(lower, "restores?") end
        if low then return { kind="heal", low=low, high=high } end
    end
    return nil
end

local COPY = {
    damage = { "Chaos Ability Reference", "effective fixed base damage", "target" },
    periodic_damage = { "Chaos Periodic Reference", "effective fixed base damage over duration", "target" },
    heal = { "Chaos Healing Reference", "effective fixed base healing", "recipient" },
    periodic_heal = { "Chaos Periodic Reference", "effective fixed base healing over duration", "recipient" },
    absorb = { "Chaos Absorb Reference", "effective fixed absorb", "recipient" },
}

function Tooltip:FindReference(lines, procOnly)
    for _, line in ipairs(lines or {}) do
        local plain = Plain(line)
        if plain:find("Chaos ", 1, true) and plain:find(" Reference", 1, true) then return nil, "present" end
        local eligible = not procOnly or plain:match("^%s*[Cc]hance on hit:") or plain:match("^%s*[Ee]quip:") or plain:match("^%s*[Uu]se:")
        if eligible then
            local result = self:ClassifyLine(plain)
            if result then return result end
        end
    end
    return nil
end

function Tooltip:AddReference(tooltip, procOnly)
    if not Chaos.state.enabled or not tooltip or type(tooltip.AddLine) ~= "function" then return false end
    local prior = self.states[tooltip]
    if prior and type(tooltip.NumLines) == "function" and tooltip:NumLines() >= prior then return true end
    local lines = TooltipLines(tooltip)
    if not lines then return false end
    local result, reason = self:FindReference(lines, procOnly)
    if not result then return reason == "present" end
    local copy = COPY[result.kind]
    if not copy then return false end
    local scale = Chaos:GetPersonalScale()
    local low, high = result.low * scale, result.high * scale
    local amount = Chaos:Format(low, 4)
    if high ~= low then amount = amount .. " - " .. Chaos:Format(high, 4) end
    tooltip:AddLine(" ")
    tooltip:AddLine(ACCENT .. copy[1] .. CLOSE, 0.40, 0.82, 1)
    tooltip:AddLine("~" .. amount .. " " .. copy[2], 0.78, 0.90, 1)
    tooltip:AddLine(MUTED .. "Personal reference; final result varies by " .. copy[3] .. "." .. CLOSE, 0.67, 0.64, 0.60, true)
    if type(tooltip.NumLines) == "function" then self.states[tooltip] = tooltip:NumLines() end
    return true
end

function Tooltip:AddSpellReference(tooltip)
    return self:AddReference(tooltip, false)
end

function Tooltip:AddProcReference(tooltip)
    return self:AddReference(tooltip, true)
end

function Tooltip:HookSpellTooltip(tooltip)
    if not tooltip or self.hooked[tooltip] or type(tooltip.HookScript) ~= "function" then return false end
    tooltip:HookScript("OnTooltipSetSpell", function(self) Tooltip:AddSpellReference(self) end)
    tooltip:HookScript("OnTooltipCleared", function(self) Tooltip.states[self] = nil end)
    tooltip:HookScript("OnHide", function(self) Tooltip.states[self] = nil end)
    self.hooked[tooltip] = true
    return true
end

-- GameTooltip covers spellbook, action/macro, pet, vehicle, talent and aura
-- SetSpell/SetAction/SetUnitAura paths. ItemRefTooltip covers spell links.
-- The post-native script fires synchronously; no ClearLines, replay or OnUpdate
-- writer is introduced.
Tooltip:HookSpellTooltip(GameTooltip)
Tooltip:HookSpellTooltip(ItemRefTooltip)

if APB and type(APB.RegisterItemTooltipAugmenter) == "function" then
    APB:RegisterItemTooltipAugmenter(function(tooltip) Tooltip:AddProcReference(tooltip) end)
end

UI.ChaosTooltip = Tooltip
UI.modules.ChaosTooltip = true
