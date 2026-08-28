local UI = EchoesUI
if not UI then return end

local Theme = UI.Theme
local Zone = {}
Zone.__index = Zone

local function Solid(parent, layer, color)
    local texture = parent:CreateTexture(nil, layer)
    Theme:SetTextureColor(texture, color)
    return texture
end

function Zone:Create(parent, options)
    local object = setmetatable({}, self)
    object.id = assert(options.id, "ProgressionZone requires an id")
    object.enabled = options.enabled ~= false
    object.focused = false
    object.hovered = false
    object.pressed = false
    object.onActivate = options.onActivate
    object.tooltip = options.tooltip
    object.onStateChange = options.onStateChange

    local root = CreateFrame("Button", options.name, parent)
    root:SetSize(options.width, options.height)
    root:RegisterForClicks("LeftButtonUp")
    object.root = root

    object.shadow = Solid(root, "BACKGROUND", {0.005, 0.007, 0.010, 0.88})
    object.shadow:SetPoint("TOPLEFT", root, "TOPLEFT", 8, -5)
    object.shadow:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -7, 7)
    object.surface = Solid(root, "ARTWORK", options.surfaceColor or Theme.colors.stone)
    object.surface:SetPoint("TOPLEFT", root, "TOPLEFT", 3, -3)
    object.surface:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -3, 3)

    object.topSeam = Solid(root, "OVERLAY", options.accentColor or Theme.colors.bronze)
    object.topSeam:SetHeight(2)
    object.topSeam:SetPoint("TOPLEFT", root, "TOPLEFT", 32, -10)
    object.topSeam:SetPoint("TOPRIGHT", root, "TOPRIGHT", -92, -10)
    object.topSeam:SetAlpha(0.48)

    object.focusPlate = Solid(root, "OVERLAY", options.focusColor or options.accentColor or Theme.colors.bronzeBright)
    object.focusPlate:SetPoint("TOPLEFT", root, "TOPLEFT", 3, -3)
    object.focusPlate:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -3, 3)
    object.focusPlate:SetAlpha(0)

    object.shoulder = Solid(root, "ARTWORK", options.plateColor or Theme.colors.stoneLift)
    object.shoulder:SetSize(82, 11)
    object.shoulder:SetPoint("TOPRIGHT", root, "TOPRIGHT", -12, -4)
    object.foot = Solid(root, "ARTWORK", options.plateColor or Theme.colors.stoneLift)
    object.foot:SetSize(108, 9)
    object.foot:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 14, 4)
    object.leftRetainer = Solid(root, "OVERLAY", options.accentColor or Theme.colors.bronze)
    object.leftRetainer:SetSize(3, 24)
    object.leftRetainer:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -10)
    object.rightRetainer = Solid(root, "OVERLAY", options.accentColor or Theme.colors.bronze)
    object.rightRetainer:SetSize(3, 18)
    object.rightRetainer:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 10)

    object.title = root:CreateFontString(nil, "OVERLAY")
    object.title:SetFont(Theme.fonts.monument, options.titleSize or 20, "OUTLINE")
    object.title:SetText(options.title or "")
    object.title:SetTextColor(unpack(options.titleColor or Theme.colors.text))
    object.title:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -18)
    object.title:SetWidth(options.width - 40)
    object.title:SetHeight(28)
    object.title:SetJustifyH("LEFT")

    object.subtitle = root:CreateFontString(nil, "OVERLAY")
    object.subtitle:SetFont(Theme.fonts.readable, options.subtitleSize or 12)
    object.subtitle:SetText(options.subtitle or "")
    object.subtitle:SetTextColor(unpack(Theme.colors.textMuted))
    object.subtitle:SetPoint("TOPLEFT", root, "TOPLEFT", 21, -47)
    object.subtitle:SetWidth(options.width - 42)
    object.subtitle:SetHeight(22)
    object.subtitle:SetJustifyH("LEFT")

    object.content = CreateFrame("Frame", nil, root)
    object.content:SetPoint("TOPLEFT", root, "TOPLEFT", 18, -72)
    object.content:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -18, 16)

    root:SetScript("OnEnter", function()
        object.hovered = true
        object:Render()
        if object.tooltip then
            GameTooltip:SetOwner(root, "ANCHOR_LEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(object.tooltip, 0.88, 0.82, 0.68)
            GameTooltip:Show()
        end
    end)
    root:SetScript("OnLeave", function()
        object.hovered = false
        object.pressed = false
        object:Render()
        GameTooltip:Hide()
    end)
    root:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and object.enabled then object.pressed = true; object:Render() end
    end)
    root:SetScript("OnMouseUp", function() object.pressed = false; object:Render() end)
    root:SetScript("OnClick", function() object:Activate("mouse") end)
    object:Render()
    return object
end

function Zone:Render()
    local alpha = 0
    if self.enabled then
        if self.pressed then alpha = 0.25
        elseif self.focused and self.hovered then alpha = 0.19
        elseif self.focused then alpha = 0.14
        elseif self.hovered then alpha = 0.07 end
    end
    self.focusPlate:SetAlpha(alpha * 0.55)
    self.topSeam:SetAlpha(self.focused and 0.95 or (self.hovered and 0.70 or 0.48))
    self.leftRetainer:SetAlpha(self.focused and 1 or (self.hovered and 0.72 or 0.48))
    self.rightRetainer:SetAlpha(self.focused and 0.90 or (self.hovered and 0.62 or 0.34))
    self.title:SetTextColor(unpack(self.enabled and (self.focused and Theme.colors.worldsoulPale or Theme.colors.text) or Theme.colors.disabled))
    if self.onStateChange then self.onStateChange(self, self.focused, self.hovered, self.pressed) end
end

function Zone:SetFocused(value) self.focused = value == true; self:Render() end
function Zone:SetEnabled(value) self.enabled = value == true; self.root:EnableMouse(self.enabled); self:Render() end
function Zone:Activate(source)
    if not self.enabled or not self.onActivate then return false end
    UI:SafeCall("Progression zone " .. self.id, self.onActivate, self, source)
    return true
end

UI.ProgressionZone = Zone
UI.modules.ProgressionZone = true
