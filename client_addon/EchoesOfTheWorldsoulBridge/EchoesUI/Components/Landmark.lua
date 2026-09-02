local UI = EchoesUI
if not UI then return end

local Theme = UI.Theme
local Animation = UI.AnimationController
local ADDON_NAME = "EchoesOfTheWorldsoulBridge"
local Landmark = {}
Landmark.__index = Landmark

local function Solid(parent, layer, color, width, height, point, relative, relativePoint, x, y)
    local texture = parent:CreateTexture(nil, layer)
    Theme:SetTextureColor(texture, color)
    texture:SetSize(width, height)
    texture:SetPoint(point, relative or parent, relativePoint or point, x or 0, y or 0)
    return texture
end

local function AddFocusCorners(frame, width, height, inset)
    local c = Theme.colors.bronzeBright
    local arm = 14
    local thick = 3
    local pieces = {}
    pieces[#pieces + 1] = Solid(frame, "OVERLAY", c, arm, thick, "TOPLEFT", frame, "CENTER", -width / 2 + inset, height / 2 - inset)
    pieces[#pieces + 1] = Solid(frame, "OVERLAY", c, thick, arm, "TOPLEFT", frame, "CENTER", -width / 2 + inset, height / 2 - inset)
    pieces[#pieces + 1] = Solid(frame, "OVERLAY", c, arm, thick, "TOPRIGHT", frame, "CENTER", width / 2 - inset, height / 2 - inset)
    pieces[#pieces + 1] = Solid(frame, "OVERLAY", c, thick, arm, "TOPRIGHT", frame, "CENTER", width / 2 - inset, height / 2 - inset)
    pieces[#pieces + 1] = Solid(frame, "OVERLAY", c, arm, thick, "BOTTOMLEFT", frame, "CENTER", -width / 2 + inset, -height / 2 + inset)
    pieces[#pieces + 1] = Solid(frame, "OVERLAY", c, thick, arm, "BOTTOMLEFT", frame, "CENTER", -width / 2 + inset, -height / 2 + inset)
    pieces[#pieces + 1] = Solid(frame, "OVERLAY", c, arm, thick, "BOTTOMRIGHT", frame, "CENTER", width / 2 - inset, -height / 2 + inset)
    pieces[#pieces + 1] = Solid(frame, "OVERLAY", c, thick, arm, "BOTTOMRIGHT", frame, "CENTER", width / 2 - inset, -height / 2 + inset)
    return pieces
end

local function AddFocusCues(frame, cues)
    local pieces = {}
    for _, cue in ipairs(cues or {}) do
        local texture = frame:CreateTexture(nil, "OVERLAY")
        Theme:SetTextureColor(texture, cue.color or Theme.colors.bronzeBright)
        texture:SetSize(cue.w or 12, cue.h or 3)
        texture:SetPoint("TOPLEFT", frame, "TOPLEFT", cue.x or 0, -(cue.y or 0))
        pieces[#pieces + 1] = texture

        if cue.cap ~= false then
            local cap = frame:CreateTexture(nil, "OVERLAY")
            Theme:SetTextureColor(cap, cue.color or Theme.colors.bronzeBright)
            if (cue.w or 12) >= (cue.h or 3) then
                cap:SetSize(cue.h or 3, (cue.h or 3) + 5)
                cap:SetPoint("TOPLEFT", frame, "TOPLEFT", cue.x or 0, -((cue.y or 0) - 2))
            else
                cap:SetSize((cue.w or 3) + 5, cue.w or 3)
                cap:SetPoint("TOPLEFT", frame, "TOPLEFT", (cue.x or 0) - 2, -(cue.y or 0))
            end
            pieces[#pieces + 1] = cap
        end
    end
    return pieces
end

local function AddResponseCues(frame, cues)
    local pieces = {}
    for _, cue in ipairs(cues or {}) do
        local texture = frame:CreateTexture(nil, "OVERLAY")
        Theme:SetTextureColor(texture, cue.color or Theme.colors.worldsoul)
        texture:SetSize(cue.w or 3, cue.h or 10)
        texture:SetPoint("TOPLEFT", frame, "TOPLEFT", cue.x or 0, -(cue.y or 0))
        pieces[#pieces + 1] = texture
    end
    return pieces
end

local function AddEnvironmentCrops(frame, root, crops, color)
    local pieces = {}
    for _, crop in ipairs(crops or {}) do
        local sourceX = crop.sourceX
        local sourceY = crop.sourceY
        local sourceRight = sourceX + crop.w
        local sourceBottom = sourceY + crop.h
        local pieceY = sourceY

        while pieceY < sourceBottom do
            local tileRow = math.floor(pieceY / 512)
            local tileTop = tileRow * 512
            local pieceBottom = math.min(sourceBottom, tileTop + 512)
            local pieceX = sourceX

            while pieceX < sourceRight do
                local tileColumn = math.floor(pieceX / 512)
                local tileLeft = tileColumn * 512
                local pieceRight = math.min(sourceRight, tileLeft + 512)
                local pieceWidth = pieceRight - pieceX
                local pieceHeight = pieceBottom - pieceY
                local texture = frame:CreateTexture(nil, "OVERLAY")

                texture:SetTexture("Interface\\AddOns\\" .. ADDON_NAME ..
                    "\\Assets\\C43_" .. tileColumn .. tileRow)
                texture:SetSize(pieceWidth, pieceHeight)
                texture:SetPoint("TOPLEFT", root, "TOPLEFT",
                    (crop.x or 0) + (pieceX - sourceX),
                    -((crop.y or 0) + (pieceY - sourceY)))
                texture:SetTexCoord(
                    (pieceX - tileLeft) / 512,
                    (pieceRight - tileLeft) / 512,
                    (pieceY - tileTop) / 512,
                    (pieceBottom - tileTop) / 512
                )
                texture:SetBlendMode("ADD")
                texture:SetVertexColor(unpack(crop.color or color or Theme.colors.bronzeBright))
                pieces[#pieces + 1] = texture
                pieceX = pieceRight
            end
            pieceY = pieceBottom
        end
    end
    return pieces
end

local function AddMaterialCrop(frame, spec)
    local sourceX = spec.sourceX
    local sourceY = spec.sourceY
    local sourceRight = sourceX + spec.w
    local sourceBottom = sourceY + spec.h
    local pieceY = sourceY

    while pieceY < sourceBottom do
        local tileRow = math.floor(pieceY / 512)
        local tileTop = tileRow * 512
        local pieceBottom = math.min(sourceBottom, tileTop + 512)
        local pieceX = sourceX

        while pieceX < sourceRight do
            local tileColumn = math.floor(pieceX / 512)
            local tileLeft = tileColumn * 512
            local pieceRight = math.min(sourceRight, tileLeft + 512)
            local texture = frame:CreateTexture(nil, "OVERLAY")
            texture:SetTexture("Interface\\AddOns\\" .. ADDON_NAME ..
                "\\Assets\\C43_" .. tileColumn .. tileRow)
            texture:SetSize(pieceRight - pieceX, pieceBottom - pieceY)
            texture:SetPoint("TOPLEFT", frame, "TOPLEFT",
                pieceX - sourceX, -(pieceY - sourceY))
            texture:SetTexCoord(
                (pieceX - tileLeft) / 512,
                (pieceRight - tileLeft) / 512,
                (pieceY - tileTop) / 512,
                (pieceBottom - tileTop) / 512)
            texture:SetBlendMode(spec.blendMode or "ADD")
            texture:SetVertexColor(unpack(spec.color or Theme.colors.bronzeBright))
            pieceX = pieceRight
        end
        pieceY = pieceBottom
    end
end

local function CreateMaterialPiece(root, spec)
    local frame = CreateFrame("Frame", nil, root)
    frame:SetSize(spec.w, spec.h)
    frame.__echoesMaterialPoint = "TOPLEFT"
    frame.__echoesMaterialRelative = root
    frame.__echoesMaterialRelativePoint = "TOPLEFT"
    frame.__echoesMaterialBaseX = spec.x or 0
    frame.__echoesMaterialBaseY = spec.y or 0
    frame.__echoesMaterialX = 0
    frame.__echoesMaterialY = 0
    frame:SetPoint("TOPLEFT", root, "TOPLEFT", spec.x or 0, -(spec.y or 0))
    frame:SetAlpha(spec.restAlpha or 0)

    if spec.solid then
        Solid(frame, "OVERLAY", spec.color or Theme.colors.bronzeBright,
            spec.w, spec.h, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    else
        AddMaterialCrop(frame, spec)
    end
    return { frame=frame, spec=spec }
end

function Landmark:Create(parent, options)
    options = options or {}
    local object = setmetatable({}, self)
    object.id = assert(options.id, "Landmark requires an id")
    object.enabled = options.enabled ~= false
    object.hovered = false
    object.focused = false
    object.pressed = false
    object.selected = false
    object.onActivate = options.onActivate
    object.tooltip = options.tooltip or options.label
    object.artWidth = options.artWidth or options.hitWidth
    object.artHeight = options.artHeight or options.hitHeight
    object.artX = options.artX or 0
    object.artY = options.artY or 0
    object.baseFontSize = options.fontSize or 18
    object.embedded = options.embedded == true
    object.labelX = options.labelX or 0
    object.labelY = options.labelY or 0
    object.responseAlphas = options.responseAlphas or {}
    object.focusDisplayAlpha = options.focusDisplayAlpha or 0.92
    object.hoverLabelColor = options.hoverLabelColor or { 1.00, 0.86, 0.52, 1 }
    object.focusLabelColor = options.focusLabelColor or { 1.00, 0.88, 0.48, 1 }
    object.activeLabelColor = options.activeLabelColor or Theme.colors.worldsoulPale
    object.labelFocusX = options.labelFocusX or 0
    object.labelFocusY = options.labelFocusY or 0

    local root = CreateFrame("Button", options.name, parent)
    root:SetSize(options.hitWidth, options.hitHeight)
    root:RegisterForClicks("LeftButtonUp")
    object.root = root

    if options.artTexture then
        object.art = root:CreateTexture(nil, "ARTWORK")
        object.art:SetTexture(options.artTexture)
        object.art:SetSize(object.artWidth, object.artHeight)
        object.art:SetPoint("CENTER", root, "CENTER", object.artX, object.artY)
    end

    object.responseFrame = CreateFrame("Frame", nil, root)
    object.responseFrame:SetAllPoints(root)
    object.responseFrame:SetAlpha(0)
    object.responseTextures = {}
    if options.environmentCrops then
        object.responseTextures = AddEnvironmentCrops(object.responseFrame, root,
            options.environmentCrops, options.responseColor)
    elseif options.responseTexture or options.artTexture then
        object.response = object.responseFrame:CreateTexture(nil, "OVERLAY")
        object.response:SetTexture(options.responseTexture or options.artTexture)
        object.response:SetSize(object.artWidth, object.artHeight)
        object.response:SetPoint("CENTER", root, "CENTER", object.artX, object.artY)
        object.response:SetBlendMode("ADD")
        object.response:SetVertexColor(unpack(options.responseColor or Theme.colors.bronzeBright))
        object.responseTextures[1] = object.response
    end
    if options.responseCues then
        local responseCues = AddResponseCues(object.responseFrame, options.responseCues)
        for _, texture in ipairs(responseCues) do
            object.responseTextures[#object.responseTextures + 1] = texture
        end
    end

    object.materialPieces = {}
    for _, spec in ipairs(options.materialPieces or {}) do
        object.materialPieces[#object.materialPieces + 1] = CreateMaterialPiece(root, spec)
    end

    local labelFrame = CreateFrame("Frame", nil, root)
    labelFrame:SetSize(options.labelWidth or options.hitWidth, options.labelHeight or 28)
    labelFrame.__echoesMaterialPoint = "TOPLEFT"
    labelFrame.__echoesMaterialRelative = root
    labelFrame.__echoesMaterialRelativePoint = "TOPLEFT"
    labelFrame.__echoesMaterialBaseX = object.labelX
    labelFrame.__echoesMaterialBaseY = object.labelY
    labelFrame.__echoesMaterialX = 0
    labelFrame.__echoesMaterialY = 0
    labelFrame:SetPoint("TOPLEFT", root, "TOPLEFT", object.labelX, -object.labelY)
    object.labelFrame = labelFrame

    local label = labelFrame:CreateFontString(nil, "OVERLAY")
    label:SetFont(Theme.fonts.monument, object.baseFontSize, "OUTLINE")
    label:SetText(options.label or "")
    label:SetTextColor(unpack(Theme.colors.text))
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
    label:SetWidth(options.labelWidth or options.hitWidth)
    label:SetHeight(options.labelHeight or 28)
    label:SetJustifyH("CENTER")
    label:SetJustifyV("MIDDLE")
    label:SetPoint("TOPLEFT", labelFrame, "TOPLEFT", 0, 0)
    object.label = label

    object.focusFrame = CreateFrame("Frame", nil, root)
    object.focusFrame:SetAllPoints(root)
    object.focusFrame:SetAlpha(0)
    if options.focusCues then
        object.focusPieces = AddFocusCues(object.focusFrame, options.focusCues)
    else
        object.focusPieces = AddFocusCorners(object.focusFrame,
            options.focusWidth or math.min(options.hitWidth, object.artWidth),
            options.focusHeight or math.min(options.hitHeight, object.artHeight),
            options.focusInset or 7)
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

function Landmark:ShowTooltip()
    if not self.tooltip then return end
    GameTooltip:SetOwner(self.root, "ANCHOR_LEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(self.tooltip, 0.88, 0.82, 0.68)
    GameTooltip:Show()
end

function Landmark:SetFocused(focused)
    self.focused = focused == true
    self:Render()
end

function Landmark:SetEnabled(enabled)
    self.enabled = enabled == true
    self.root:EnableMouse(self.enabled)
    if not self.enabled then
        self.hovered = false
        self.pressed = false
    end
    self:Render(true)
end

function Landmark:SetScaleCompensation(scale, minimumPhysicalSize)
    scale = tonumber(scale) or 1
    if scale <= 0 then scale = 1 end
    local fontSize = self.baseFontSize
    local minimum = minimumPhysicalSize or 12
    if fontSize * scale < minimum then fontSize = minimum / scale end
    self.label:SetFont(Theme.fonts.monument, fontSize, "OUTLINE")
end

function Landmark:Activate(source)
    if not self.enabled then UI:Trace("control." .. self.id, source, "disabled"); return false end
    self.selected = true
    self.pressed = false
    self:Render()
    local ok = true
    if self.onActivate then ok = UI:SafeCall(self.id .. " activation", self.onActivate, self, source) end
    UI:Trace("control." .. self.id, source, ok and "activated" or "error")
    C_Timer.After(Theme.timing.click, function()
        self.selected = false
        self:Render()
    end)
    return ok
end

function Landmark:Render(immediate)
    local responseAlpha = 0
    if self.enabled then
        if self.selected then responseAlpha = self.responseAlphas.selected or 0.30
        elseif self.pressed then responseAlpha = self.responseAlphas.pressed or 0.27
        elseif self.hovered and self.focused then responseAlpha = self.responseAlphas.hoverFocus or 0.28
        elseif self.hovered then responseAlpha = self.responseAlphas.hover or 0.22
        elseif self.focused then responseAlpha = self.responseAlphas.focus or 0.08
        end
    end

    local current = self.responseFrame:GetAlpha()
    local duration = immediate and 0 or (responseAlpha > current
        and Theme.timing.hoverEnter or Theme.timing.hoverRelease)
    Animation:Alpha(self.responseFrame, responseAlpha, duration)
    Animation:Alpha(self.focusFrame, self.enabled and self.focused and self.focusDisplayAlpha or 0,
        immediate and 0 or Theme.timing.hoverEnter)

    local materialDuration = immediate and 0 or Theme.timing.hoverEnter
    if self.pressed or self.selected then
        materialDuration = immediate and 0 or Theme.timing.click
    elseif not self.hovered and not self.focused then
        materialDuration = immediate and 0 or Theme.timing.hoverRelease
    end

    for _, piece in ipairs(self.materialPieces) do
        local spec = piece.spec
        local alpha = spec.restAlpha or 0
        local offsetX, offsetY = 0, 0
        local scale = spec.restScale or 1
        if self.enabled then
            if self.focused then
                alpha = spec.focusAlpha or alpha
                offsetX = spec.focusX or 0
                offsetY = spec.focusY or 0
                scale = spec.focusScale or scale
            elseif self.hovered then
                alpha = spec.hoverAlpha or alpha
                offsetX = spec.hoverX or 0
                offsetY = spec.hoverY or 0
                scale = spec.hoverScale or scale
            end
            if self.hovered and self.focused then
                alpha = spec.hoverFocusAlpha or spec.focusAlpha or alpha
                offsetX = spec.hoverFocusX or spec.focusX or offsetX
                offsetY = spec.hoverFocusY or spec.focusY or offsetY
                scale = spec.hoverFocusScale or spec.focusScale or scale
            end
            if self.pressed or self.selected then
                alpha = spec.pressedAlpha or spec.focusAlpha or alpha
                offsetX = offsetX + (spec.pressX or 0)
                offsetY = offsetY + (spec.pressY or -1)
                scale = spec.pressedScale or scale
            end
        end
        Animation:Material(piece.frame, alpha, offsetX, offsetY, scale, materialDuration)
    end

    local labelX = self.focused and self.labelFocusX or 0
    local labelY = self.focused and self.labelFocusY or 0
    if self.pressed or self.selected then
        labelX = labelX + 1
        labelY = labelY - 1
    end
    Animation:Material(self.labelFrame, 1, labelX, labelY, 1, materialDuration)

    local pressX = self.pressed and 1 or 0
    local pressY = self.pressed and -1 or 0
    if self.art and not self.embedded then
        local x = self.artX + pressX
        local y = self.artY + pressY
        self.art:ClearAllPoints()
        self.art:SetPoint("CENTER", self.root, "CENTER", x, y)
        if self.response then
            self.response:ClearAllPoints()
            self.response:SetPoint("CENTER", self.root, "CENTER", x, y)
        end
    end

    if not self.enabled then
        self.label:SetTextColor(unpack(Theme.colors.disabled))
        if self.art then self.art:SetVertexColor(0.52, 0.52, 0.52) end
    elseif self.pressed or self.selected then
        self.label:SetTextColor(unpack(self.activeLabelColor))
        if self.art then self.art:SetVertexColor(0.92, 0.88, 0.78) end
    elseif self.hovered then
        self.label:SetTextColor(unpack(self.hoverLabelColor))
        if self.art then self.art:SetVertexColor(1.00, 0.96, 0.88) end
    elseif self.focused then
        self.label:SetTextColor(unpack(self.focusLabelColor))
        if self.art then self.art:SetVertexColor(0.94, 0.92, 0.86) end
    else
        self.label:SetTextColor(unpack(Theme.colors.text))
        if self.art then self.art:SetVertexColor(1, 1, 1) end
    end
end

UI.Landmark = Landmark
UI.modules.Landmark = true
