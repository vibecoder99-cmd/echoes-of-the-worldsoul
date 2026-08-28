local UI = EchoesUI
if not UI then return end

local Theme = UI.Theme
local Row = {}
Row.__index = Row

local function Solid(parent, layer, color)
    local texture = parent:CreateTexture(nil, layer)
    Theme:SetTextureColor(texture, color)
    return texture
end

function Row:Create(parent, options)
    local object = setmetatable({}, self)
    object.id = assert(options.id, "ProgressionRow requires an id")
    object.enabled = options.enabled ~= false
    object.focused = false
    object.hovered = false
    object.pressed = false
    object.pending = false
    object.onActivate = options.onActivate
    object.tooltip = options.tooltip
    object.width = options.width
    object.compact = options.compact == true
    object.valueWidth = options.valueWidth or 72
    object.progressInset = options.progressInset or 0
    object.onStateChange = options.onStateChange

    local root = CreateFrame("Button", options.name, parent)
    root:SetSize(options.width, options.height or 46)
    root:RegisterForClicks("LeftButtonUp")
    object.root = root

    object.channel = Solid(root, "BACKGROUND", options.channelColor or {0.018, 0.024, 0.030, 0.88})
    object.channel:SetPoint("TOPLEFT", root, "TOPLEFT", 4, -2)
    object.channel:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -4, 2)
    object.selection = Solid(root, "BACKGROUND", options.focusColor or Theme.colors.worldsoul)
    object.selection:SetAllPoints(root)
    object.selection:SetAlpha(0)
    object.edge = Solid(root, "OVERLAY", options.accentColor or Theme.colors.worldsoul)
    object.edge:SetWidth(3)
    object.edge:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    object.edge:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
    object.edge:SetAlpha(0.35)

    if options.icon ~= false then
        object.icon = root:CreateTexture(nil, "ARTWORK")
        object.icon:SetSize(options.iconSize or 34, options.iconSize or 34)
        object.icon:SetPoint("LEFT", root, "LEFT", 9, 0)
        object.icon:SetTexture(options.iconTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
    end

    local textLeft = options.icon == false and 12 or 52
    object.label = root:CreateFontString(nil, "OVERLAY")
    object.label:SetFont(Theme.fonts.readable, options.fontSize or 13)
    object.label:SetText(options.label or "")
    object.label:SetTextColor(unpack(Theme.colors.text))
    object.label:SetPoint(object.compact and "LEFT" or "TOPLEFT", root,
        object.compact and "LEFT" or "TOPLEFT", textLeft, object.compact and 0 or -7)
    object.label:SetWidth(object.compact and (options.width - textLeft - 12)
        or (options.width - textLeft - object.valueWidth - 18))
    object.label:SetHeight(object.compact and (options.height or 38) or 18)
    object.label:SetJustifyH(options.justifyH or "LEFT")

    object.meta = root:CreateFontString(nil, "OVERLAY")
    object.meta:SetFont(Theme.fonts.readable, options.metaSize or 11)
    object.meta:SetText(options.meta or "")
    object.meta:SetTextColor(unpack(Theme.colors.textMuted))
    object.meta:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", textLeft, 6)
    object.meta:SetWidth(options.width - textLeft - object.valueWidth - 18)
    object.meta:SetHeight(14)
    object.meta:SetJustifyH("LEFT")

    object.value = root:CreateFontString(nil, "OVERLAY")
    object.value:SetFont(Theme.fonts.monument, options.valueSize or 13, "OUTLINE")
    object.value:SetText(options.value or "")
    object.value:SetTextColor(unpack(options.valueColor or Theme.colors.worldsoulPale))
    object.value:SetPoint("RIGHT", root, "RIGHT", -10, 2)
    object.value:SetWidth(object.valueWidth)
    object.value:SetHeight(22)
    object.value:SetJustifyH("RIGHT")

    object.progressBack = Solid(root, "ARTWORK", {0.02, 0.03, 0.04, 0.90})
    object.progressWidth = options.width - textLeft - object.valueWidth - 22 - object.progressInset
    object.progressBack:SetSize(math.max(1, object.progressWidth), options.progressHeight or 3)
    object.progressBack:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", textLeft + object.progressInset, 2)
    object.progress = Solid(root, "OVERLAY", options.progressColor or Theme.colors.worldsoul)
    object.progress:SetSize(1, options.progressHeight or 3)
    object.progress:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", textLeft + object.progressInset, 2)

    object.completeMark = Solid(root, "OVERLAY", options.completeColor or Theme.colors.bronzeBright)
    object.completeMark:SetSize(6, 6)
    object.completeMark:SetPoint("RIGHT", root, "RIGHT", -8, -12)
    object.completeMark:Hide()

    if object.compact then
        object.meta:Hide()
        object.value:Hide()
        object.progressBack:Hide()
        object.progress:Hide()
    end

    root:SetScript("OnEnter", function() object.hovered = true; object:Render(); object:ShowTooltip() end)
    root:SetScript("OnLeave", function() object.hovered = false; object.pressed = false; object:Render(); GameTooltip:Hide() end)
    root:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" and object.enabled then object.pressed = true; object:Render() end end)
    root:SetScript("OnMouseUp", function() object.pressed = false; object:Render() end)
    root:SetScript("OnClick", function() object:Activate("mouse") end)
    object:SetProgress(options.progress or 0)
    object:Render()
    return object
end

function Row:SetProgress(value)
    self.progressValue = math.max(0, math.min(1, tonumber(value) or 0))
    self.progress:SetWidth(math.max(1, self.progressWidth * self.progressValue))
end

function Row:SetData(data)
    self.data = data
    self.label:SetText(data.label or "")
    self.meta:SetText(data.meta or "")
    self.value:SetText(data.value or "")
    if self.icon and data.icon then self.icon:SetTexture(data.icon) end
    self.tooltip = data.tooltip
    self.tooltipLink = data.tooltipLink
    self.complete = data.complete == true
    self.strength = math.max(0, math.min(1, tonumber(data.strength) or 0))
    if self.complete then self.completeMark:Show() else self.completeMark:Hide() end
    self:SetProgress(data.progress or 0)
    self:Render()
end

function Row:ShowTooltip()
    if not self.tooltip and not self.tooltipLink then return end
    GameTooltip:SetOwner(self.root, "ANCHOR_LEFT")
    GameTooltip:ClearLines()
    if self.tooltipLink and GameTooltip.SetHyperlink then
        GameTooltip:SetHyperlink(self.tooltipLink)
    else
        GameTooltip:AddLine(self.tooltip, 0.88, 0.82, 0.68)
    end
    GameTooltip:Show()
end

function Row:Render()
    local alpha = self.pressed and 0.24 or (self.focused and 0.16 or (self.hovered and 0.08 or 0))
    self.selection:SetAlpha(self.pending and 0.10 or (self.enabled and alpha or 0))
    self.edge:SetAlpha(self.pending and 0.74
        or (self.enabled and (self.focused and 0.95 or (self.hovered and 0.62 or 0.35)) or 0.16))
    self.channel:SetAlpha(self.pending and 0.78
        or (self.enabled and (0.74 + ((self.strength or 0) * 0.18)) or 0.42))
    self.label:SetTextColor(unpack(self.pending and Theme.colors.worldsoulPale
        or (self.enabled and Theme.colors.text or Theme.colors.disabled)))
    if self.onStateChange then self.onStateChange(self, self.focused, self.hovered, self.pressed) end
end

function Row:SetFocused(value) self.focused = value == true; self:Render() end
function Row:SetEnabled(value)
    self.enabled = value == true
    self.root:EnableMouse(self.enabled and not self.pending)
    self:Render()
end
function Row:SetPending(value)
    self.pending = value == true
    self.root:EnableMouse(self.enabled and not self.pending)
    self:Render()
end
function Row:Activate(source)
    if not self.enabled or self.pending then return false end
    if self.onActivate then UI:SafeCall("Progression row " .. self.id, self.onActivate, self, source) end
    return true
end

UI.ProgressionRow = Row
UI.modules.ProgressionRow = true
