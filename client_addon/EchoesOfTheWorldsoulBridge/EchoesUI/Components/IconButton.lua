local UI = EchoesUI
if not UI then return end

local ADDON_NAME = "EchoesOfTheWorldsoulBridge"
local Theme = UI.Theme
local Animation = UI.AnimationController
local IconButton = {}
IconButton.__index = IconButton

local function Solid(parent, layer, color, width, height, point, relative, relativePoint, x, y)
    local texture = parent:CreateTexture(nil, layer)
    Theme:SetTextureColor(texture, color)
    texture:SetSize(width, height)
    texture:SetPoint(point, relative or parent, relativePoint or point, x or 0, y or 0)
    return texture
end

local function AddCornerBrackets(frame)
    local c = Theme.colors.bronzeBright
    local pieces = {}
    pieces[#pieces + 1] = Solid(frame, "OVERLAY", c, 13, 2, "TOPLEFT", frame, "TOPLEFT", 3, -3)
    pieces[#pieces + 1] = Solid(frame, "OVERLAY", c, 2, 13, "TOPLEFT", frame, "TOPLEFT", 3, -3)
    pieces[#pieces + 1] = Solid(frame, "OVERLAY", c, 13, 2, "TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    pieces[#pieces + 1] = Solid(frame, "OVERLAY", c, 2, 13, "TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    pieces[#pieces + 1] = Solid(frame, "OVERLAY", c, 13, 2, "BOTTOMLEFT", frame, "BOTTOMLEFT", 3, 3)
    pieces[#pieces + 1] = Solid(frame, "OVERLAY", c, 2, 13, "BOTTOMLEFT", frame, "BOTTOMLEFT", 3, 3)
    pieces[#pieces + 1] = Solid(frame, "OVERLAY", c, 13, 2, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    pieces[#pieces + 1] = Solid(frame, "OVERLAY", c, 2, 13, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    return pieces
end

local function AddFocusCues(frame, cues)
    local pieces = {}
    for _, cue in ipairs(cues or {}) do
        local color = cue.color or Theme.colors.bronzeBright
        local main = Solid(frame, "OVERLAY", color, cue.w or 10, cue.h or 2,
            "TOPLEFT", frame, "TOPLEFT", cue.x or 0, -(cue.y or 0))
        pieces[#pieces + 1] = main

        if cue.cap ~= false then
            local cap
            if (cue.w or 10) >= (cue.h or 2) then
                cap = Solid(frame, "OVERLAY", color, cue.h or 2, (cue.h or 2) + 4,
                    "TOPLEFT", frame, "TOPLEFT", cue.x or 0, -((cue.y or 0) - 2))
            else
                cap = Solid(frame, "OVERLAY", color, (cue.w or 2) + 4, cue.w or 2,
                    "TOPLEFT", frame, "TOPLEFT", (cue.x or 0) - 2, -(cue.y or 0))
            end
            pieces[#pieces + 1] = cap
        end
    end
    return pieces
end

function IconButton:Create(parent, options)
    options = options or {}
    local object = setmetatable({}, self)
    object.id = options.id or "iconButton"
    object.enabled = options.enabled ~= false
    object.hovered = false
    object.focused = false
    object.pressed = false
    object.selected = false
    object.onActivate = options.onActivate
    object.tooltip = options.tooltip
    object.tooltipDetail = options.tooltipDetail
    object.shapedResponse = options.shapedResponse == true
    object.seatSize = options.seatSize or 64
    object.seatRestAlpha = options.seatRestAlpha == nil and 1 or options.seatRestAlpha
    object.glowAlphas = options.glowAlphas or {}
    object.focusDisplayAlpha = options.focusDisplayAlpha or 0.88
    object.hoverResponseScale = options.hoverResponseScale or 1
    object.focusResponseScale = options.focusResponseScale or 1
    object.hoverFocusResponseScale = options.hoverFocusResponseScale or object.focusResponseScale
    object.pressedResponseScale = options.pressedResponseScale or 0.97
    object.seatTexture = options.seatTexture or
        ("Interface\\AddOns\\" .. ADDON_NAME .. "\\EchoesUI\\Assets\\SettingsSeat.tga")

    local root = CreateFrame("Button", options.name, parent)
    root:SetSize(options.hitWidth or 74, options.hitHeight or 74)
    root:RegisterForClicks("LeftButtonUp")
    object.root = root

    -- Soft drop shadow behind the seat gives the disc a touch of depth
    -- against whatever host frame it's placed on.
    object.shadow = Solid(root, "BACKGROUND", Theme.colors.void,
        options.shadowSize or 66, options.shadowSize or 66, "CENTER")
    if options.hideShadow then object.shadow:Hide() end

    -- The seat is a single owned ornamental asset (a round, beveled
    -- Titan-stone disc with a blackened-bronze retaining rim) rather than
    -- stacked flat rectangles - this is the "component asset", not the
    -- whole menu. Component-specific variants may override the path.
    object.seat = root:CreateTexture(nil, "ARTWORK")
    object.seat:SetTexture(object.seatTexture)
    object.seat:SetSize(object.seatSize, object.seatSize)
    object.seat:SetPoint("CENTER", root, "CENTER", 0, 0)
    object.seat:SetAlpha(object.seatRestAlpha)

    object.glowFrame = CreateFrame("Frame", nil, root)
    object.glowFrame:SetSize(options.hitWidth or 74, options.hitHeight or 74)
    object.glowFrame.__echoesMaterialPoint = "CENTER"
    object.glowFrame.__echoesMaterialRelative = root
    object.glowFrame.__echoesMaterialRelativePoint = "CENTER"
    object.glowFrame.__echoesMaterialBaseX = 0
    object.glowFrame.__echoesMaterialBaseY = 0
    object.glowFrame.__echoesMaterialX = 0
    object.glowFrame.__echoesMaterialY = 0
    object.glowFrame:SetPoint("CENTER", root, "CENTER", 0, 0)
    object.glowFrame:SetAlpha(0)
    if object.shapedResponse then
        object.glow = object.glowFrame:CreateTexture(nil, "OVERLAY")
        object.glow:SetTexture(object.seatTexture)
        object.glow:SetSize(object.seatSize, object.seatSize)
        object.glow:SetPoint("CENTER", root, "CENTER", 0, 0)
        object.glow:SetBlendMode("ADD")
        object.glow:SetVertexColor(unpack(options.responseColor or Theme.colors.bronzeBright))
    else
        local glow = Solid(object.glowFrame, "OVERLAY", Theme.colors.worldsoul, 56, 2, "TOP", root, "TOP", 0, -8)
        Solid(object.glowFrame, "OVERLAY", Theme.colors.worldsoul, 56, 2, "BOTTOM", root, "BOTTOM", 0, 8)
        Solid(object.glowFrame, "OVERLAY", Theme.colors.worldsoul, 2, 56, "LEFT", root, "LEFT", 8, 0)
        Solid(object.glowFrame, "OVERLAY", Theme.colors.worldsoul, 2, 56, "RIGHT", root, "RIGHT", -8, 0)
        object.glow = glow
    end

    object.focusFrame = CreateFrame("Frame", nil, root)
    object.focusFrame:SetAllPoints(root)
    object.focusFrame:SetAlpha(0)
    if options.focusCues then
        object.focusPieces = AddFocusCues(object.focusFrame, options.focusCues)
    else
        object.focusPieces = AddCornerBrackets(object.focusFrame)
    end

    object.pressOverlay = Solid(root, "OVERLAY", Theme.colors.worldsoulPale, 48, 48, "CENTER")
    object.pressOverlay:SetAlpha(0)
    if object.shapedResponse then object.pressOverlay:Hide() end

    local icon = root:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(options.icon or "Interface\\Buttons\\UI-OptionsButton")
    icon:SetSize(options.iconSize or 32, options.iconSize or 32)
    icon:SetPoint("CENTER", root, "CENTER", 0, 0)
    if options.texCoord then
        icon:SetTexCoord(unpack(options.texCoord))
    end
    object.icon = icon
    if options.hideIcon then
        icon:SetAlpha(0)
        object.hideIcon = true
    end

    root:SetScript("OnEnter", function()
        object.hovered = true
        object:Render()
        object:ShowTooltip()
    end)
    root:SetScript("OnLeave", function()
        object.hovered = false
        object.pressed = false
        object:Render()
        GameTooltip:Hide()
    end)
    root:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "LeftButton" and object.enabled then
            object.pressed = true
            object:Render()
        end
    end)
    root:SetScript("OnMouseUp", function()
        object.pressed = false
        object:Render()
    end)
    root:SetScript("OnClick", function()
        object:Activate("mouse")
    end)

    object:Render(true)
    return object
end

function IconButton:ShowTooltip()
    if not self.tooltip then return end
    GameTooltip:SetOwner(self.root, "ANCHOR_LEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(self.tooltip, 0.88, 0.82, 0.68)
    if self.tooltipDetail then
        GameTooltip:AddLine(self.tooltipDetail, 0.55, 0.58, 0.62)
    end
    GameTooltip:Show()
end

function IconButton:SetFocused(focused)
    self.focused = focused == true
    self:Render()
end

function IconButton:SetEnabled(enabled)
    self.enabled = enabled == true
    self.root:EnableMouse(self.enabled)
    if not self.enabled then
        self.hovered = false
        self.pressed = false
    end
    self:Render()
end

function IconButton:Activate(source)
    if not self.enabled then return false end
    self.selected = true
    self.pressed = false
    self:Render(true)

    if self.onActivate then
        UI:SafeCall(self.id .. " activation", self.onActivate, self, source)
    end

    C_Timer.After(Theme.timing.click, function()
        self.selected = false
        self:Render()
    end)
    return true
end

function IconButton:Render(immediate)
    local glowAlpha = 0
    if self.enabled then
        if self.selected then glowAlpha = self.glowAlphas.selected or 0.48
        elseif self.hovered and self.focused then glowAlpha = self.glowAlphas.hoverFocus or 0.34
        elseif self.hovered then glowAlpha = self.glowAlphas.hover or 0.25
        elseif self.focused then glowAlpha = self.glowAlphas.focus or 0.11
        end
    end

    local duration = immediate and 0 or (glowAlpha > self.glowFrame:GetAlpha()
        and Theme.timing.hoverEnter or Theme.timing.hoverRelease)
    local responseScale = 1
    if self.focused and self.hovered then responseScale = self.hoverFocusResponseScale
    elseif self.focused then responseScale = self.focusResponseScale
    elseif self.hovered then responseScale = self.hoverResponseScale end
    if self.pressed or self.selected then responseScale = self.pressedResponseScale end
    Animation:Material(self.glowFrame, glowAlpha, 0, 0, responseScale, duration)
    Animation:Alpha(self.focusFrame, self.enabled and self.focused and self.focusDisplayAlpha or 0,
        immediate and 0 or Theme.timing.hoverEnter)

    self.pressOverlay:SetAlpha((not self.shapedResponse) and self.enabled and self.pressed and 0.16 or 0)
    self.seat:ClearAllPoints()
    self.seat:SetPoint("CENTER", self.root, "CENTER", self.pressed and 1 or 0, self.pressed and -1 or 0)
    self.seat:SetAlpha(self.seatRestAlpha)
    if self.shapedResponse then
        self.glow:ClearAllPoints()
        self.glow:SetPoint("CENTER", self.root, "CENTER", self.pressed and 1 or 0, self.pressed and -1 or 0)
    end
    self.icon:ClearAllPoints()
    self.icon:SetPoint("CENTER", self.root, "CENTER", self.pressed and 1 or 0, self.pressed and -1 or 0)

    if self.hideIcon then
        self.icon:SetAlpha(0)
    elseif not self.enabled then
        self.icon:SetVertexColor(Theme.colors.disabled[1], Theme.colors.disabled[2], Theme.colors.disabled[3])
    elseif self.pressed or self.selected then
        self.icon:SetVertexColor(Theme.colors.worldsoulPale[1], Theme.colors.worldsoulPale[2], Theme.colors.worldsoulPale[3])
    elseif self.hovered then
        self.icon:SetVertexColor(1.00, 0.88, 0.58)
    else
        self.icon:SetVertexColor(0.82, 0.72, 0.52)
    end
end

UI.IconButton = IconButton
UI.modules.IconButton = true
