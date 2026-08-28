local UI = EchoesUI
if not UI or not UI.ProgressionRow or not UI.InputManager then return end

local Theme = UI.Theme
local Animation = UI.AnimationController
local UtilityShell = {}
UtilityShell.__index = UtilityShell

local function Solid(parent, layer, color)
    local texture = parent:CreateTexture(nil, layer)
    Theme:SetTextureColor(texture, color)
    return texture
end

function UtilityShell:Create(options)
    options = options or {}
    local shell = setmetatable({ id=options.id, title=options.title or "UTILITY", active=false }, self)
    local frame = CreateFrame("Frame", options.name, UIParent)
    frame:SetSize(1280, 760); frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG"); frame:EnableMouse(true); frame:Hide()
    shell.frame = frame

    local veil = Solid(frame, "BACKGROUND", {0.006,0.009,0.014,0.96}); veil:SetAllPoints(frame)
    local rim = Solid(frame, "BACKGROUND", Theme.colors.stoneLift)
    rim:SetSize(1248, 720); rim:SetPoint("CENTER", frame, "CENTER", 0, 0)
    local body = Solid(frame, "BACKGROUND", Theme.colors.void)
    body:SetSize(1236, 708); body:SetPoint("CENTER", rim, "CENTER", 0, 0)
    local top = Solid(frame, "ARTWORK", {0.045,0.050,0.060,1})
    top:SetSize(650, 70); top:SetPoint("TOP", frame, "TOP", 0, -22)
    local line = Solid(frame, "OVERLAY", options.accentColor or Theme.colors.bronzeBright)
    line:SetSize(450, 2); line:SetPoint("BOTTOM", top, "BOTTOM", 0, 0)
    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont(Theme.fonts.monument, 28, "OUTLINE"); title:SetText(shell.title)
    title:SetTextColor(unpack(Theme.colors.text)); title:SetPoint("CENTER", top, "CENTER", 0, 9)
    local subtitle = frame:CreateFontString(nil, "OVERLAY")
    subtitle:SetFont(Theme.fonts.readable, 10); subtitle:SetText(options.subtitle or "WORLDSOUL UTILITY")
    subtitle:SetTextColor(unpack(Theme.colors.textMuted)); subtitle:SetPoint("CENTER", top, "CENTER", 0, -17)
    shell.titleText, shell.subtitleText = title, subtitle
    -- Exposed so a screen can apply its own local material pass to its own
    -- Create() instance (e.g. Codex/Search reducing veil alpha or replacing
    -- rim/body/top/line with art) without editing this shared component and
    -- without affecting any other screen's independently-created instance.
    shell.veil, shell.rimPanel, shell.corePanel, shell.headerPlate, shell.headerLine = veil, rim, body, top, line

    local content = CreateFrame("Frame", nil, frame)
    content:SetSize(1130, 574); content:SetPoint("TOPLEFT", frame, "TOPLEFT", 75, -115)
    shell.content = content

    local function nav(id, label, x, callback)
        local row = UI.ProgressionRow:Create(frame, {
            id=id, name=options.name .. id, width=138, height=38, icon=false,
            compact=true, label=label, value="", progress=0, onActivate=callback,
        })
        row.root:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -30)
        return row
    end
    shell.back = nav("back", "‹  BACK", 24, function() shell:Leave(shell.id) end)
    shell.home = nav("home", "CORE / HOME", 976, function() shell:Leave("core") end)
    shell.close = nav("close", "CLOSE  ×", 1120, function() shell:CloseCompanion() end)
    shell.input = UI.InputManager:New(frame, {isInputCaptured=function()
        return shell.isInputCaptured and shell:isInputCaptured() or false
    end})
    shell.input:Add(shell.back, "back"); shell.input:Add(shell.home, "home"); shell.input:Add(shell.close, "close")
    shell.input.onEscape = function() shell:Leave(shell.id) end
    return shell
end

function UtilityShell:AddControl(control, id)
    self.input:Add(control, id)
end

function UtilityShell:UpdateScale()
    self.frame:SetScale(math.min((UIParent:GetWidth() or 1280)/1280, (UIParent:GetHeight() or 760)/760))
end

function UtilityShell:Show(defaultFocus)
    self.active = true; self:UpdateScale()
    if APB and APB.C43 and APB.C43.frame then APB.C43.frame:Hide() end
    self.frame:SetAlpha(UI:IsReducedMotion() and 1 or 0); self.frame:Show()
    Animation:Alpha(self.frame, 1, 0.22)
    self.input:SetFocusById(defaultFocus or self.defaultFocus or "back")
end

function UtilityShell:Hide()
    self.active = false; self.input:ClearFocus(); Animation:Stop(self.frame); self.frame:Hide()
end

function UtilityShell:Leave(focusId)
    self:Hide()
    if UI.DashboardGateB and UI.ScreenManager:Show("dashboardGateB", false, focusId or self.id) then return end
    UI.ScreenManager.current = nil
    if APB and APB.C43 then APB.C43:Show() end
end

function UtilityShell:CloseCompanion()
    self:Hide(); UI.ScreenManager.current=nil; UI.ScreenManager.history={}
    if APB and APB.C43 and APB.C43.Hide then APB.C43:Hide() end
end

UI.UtilityShell = UtilityShell
UI.modules.UtilityShell = true
