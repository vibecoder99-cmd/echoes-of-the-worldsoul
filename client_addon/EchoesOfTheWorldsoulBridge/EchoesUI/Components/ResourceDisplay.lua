local UI = EchoesUI
if not UI or not UI.StateStore then return end

local Theme = UI.Theme
local Animation = UI.AnimationController
local ResourceDisplay = {}
ResourceDisplay.__index = ResourceDisplay

local function FormatInteger(value)
    value = tonumber(value)
    if not value then return "--" end
    return tostring(math.floor(value)):reverse():gsub("(%d%d%d)", "%1,")
        :reverse():gsub("^,", "")
end

function ResourceDisplay:Create(parent, options)
    options = options or {}
    local object = setmetatable({
        id = options.id or "essence",
        field = options.field or "essence",
        baseFontSize = options.fontSize or 15,
        labelFontSize = options.labelFontSize or 9,
        emphasisToken = 0,
    }, self)

    local root = CreateFrame("Frame", options.name, parent)
    root:SetSize(options.width or 142, options.height or 34)
    object.root = root

    local seatFrame = CreateFrame("Frame", nil, root)
    seatFrame:SetAllPoints(root)
    seatFrame:SetAlpha(0.34)
    object.seatFrame = seatFrame

    local seatRune = seatFrame:CreateTexture(nil, "ARTWORK")
    Theme:SetTextureColor(seatRune, Theme.colors.bronzeBright)
    seatRune:SetSize(2, 10)
    seatRune:SetPoint("LEFT", root, "LEFT", 18, 0)
    local seatLine = seatFrame:CreateTexture(nil, "ARTWORK")
    Theme:SetTextureColor(seatLine, Theme.colors.bronze)
    seatLine:SetSize(106, 1)
    seatLine:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -7, 5)

    local responseFrame = CreateFrame("Frame", nil, root)
    responseFrame:SetAllPoints(root)
    responseFrame:SetAlpha(0)
    object.responseFrame = responseFrame

    local glyphFrame = CreateFrame("Frame", nil, responseFrame)
    glyphFrame:SetSize(18, 18)
    glyphFrame.__echoesMaterialPoint = "LEFT"
    glyphFrame.__echoesMaterialRelative = root
    glyphFrame.__echoesMaterialRelativePoint = "LEFT"
    glyphFrame.__echoesMaterialBaseX = 8
    glyphFrame.__echoesMaterialBaseY = 0
    glyphFrame.__echoesMaterialX = 0
    glyphFrame.__echoesMaterialY = 0
    glyphFrame:SetPoint("LEFT", root, "LEFT", 8, 0)
    object.glyphFrame = glyphFrame

    local glyphWake = glyphFrame:CreateTexture(nil, "OVERLAY")
    Theme:SetTextureColor(glyphWake, Theme.colors.worldsoul)
    glyphWake:SetSize(8, 8)
    glyphWake:SetPoint("CENTER", glyphFrame, "CENTER", 0, 0)
    local glyphCore = glyphFrame:CreateTexture(nil, "OVERLAY")
    Theme:SetTextureColor(glyphCore, Theme.colors.worldsoulPale)
    glyphCore:SetSize(3, 3)
    glyphCore:SetPoint("CENTER", glyphFrame, "CENTER", 0, 0)
    local valueWake = responseFrame:CreateTexture(nil, "OVERLAY")
    Theme:SetTextureColor(valueWake, Theme.colors.worldsoulPale)
    valueWake:SetSize(48, 2)
    valueWake:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -7, 5)

    local label = root:CreateFontString(nil, "OVERLAY")
    label:SetFont(Theme.fonts.readable, object.labelFontSize, "OUTLINE")
    label:SetText(options.label or "ESSENCE")
    label:SetTextColor(unpack(Theme.colors.text))
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
    label:SetPoint("TOPLEFT", root, "TOPLEFT", 25, -2)
    label:SetWidth(108)
    label:SetJustifyH("LEFT")
    object.label = label

    local value = root:CreateFontString(nil, "OVERLAY")
    value:SetFont(Theme.fonts.readable, object.baseFontSize, "OUTLINE")
    value:SetTextColor(0.92, 0.88, 0.76, 1)
    value:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -8, 1)
    value:SetWidth(109)
    value:SetJustifyH("RIGHT")
    value:SetText("--")
    object.value = value

    function object:SetValue(nextValue, acknowledge)
        self.value:SetText(FormatInteger(nextValue))
        if not acknowledge then return end

        self.emphasisToken = self.emphasisToken + 1
        local token = self.emphasisToken
        self.value:SetTextColor(unpack(Theme.colors.worldsoulPale))
        if not UI:IsReducedMotion() then
            self.responseFrame:SetAlpha(0.34)
            Animation:Alpha(self.responseFrame, 0, 0.26)
            Animation:Material(self.glyphFrame, 1, 0, 0, 1.08, 0.10, function()
                Animation:Material(self.glyphFrame, 1, 0, 0, 1, 0.14)
            end)
        else
            self.responseFrame:SetAlpha(0)
            Animation:Material(self.glyphFrame, 1, 0, 0, 1, 0)
        end
        C_Timer.After(0.18, function()
            if self.emphasisToken ~= token then return end
            self.value:SetTextColor(0.92, 0.88, 0.76, 1)
        end)
    end

    object.unsubscribe = UI.StateStore:Subscribe(function(values, changed)
        if changed[object.field] ~= nil then
            object:SetValue(values[object.field], true)
        end
    end)
    object:SetValue(UI.StateStore:Get(object.field), false)

    return object
end

function ResourceDisplay:SetScaleCompensation(scale, minimumPhysicalSize)
    scale = tonumber(scale) or 1
    if scale <= 0 then scale = 1 end
    local size = self.baseFontSize
    local minimum = minimumPhysicalSize or 12
    if size * scale < minimum then size = minimum / scale end
    local labelSize = self.labelFontSize
    if labelSize * scale < 8 then labelSize = 8 / scale end
    self.label:SetFont(Theme.fonts.readable, labelSize, "OUTLINE")
    self.value:SetFont(Theme.fonts.readable, size, "OUTLINE")
end

function ResourceDisplay:Destroy()
    if self.unsubscribe then self.unsubscribe(); self.unsubscribe = nil end
    Animation:Stop(self.responseFrame)
    Animation:Stop(self.glyphFrame)
    self.root:Hide()
end

UI.ResourceDisplay = ResourceDisplay
UI.modules.ResourceDisplay = true
