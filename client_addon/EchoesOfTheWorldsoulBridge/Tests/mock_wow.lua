-- Minimal WoW 3.3.5a API mock sufficient to load and exercise the EchoesUI
-- module chain outside the game client. Not exhaustive - just what the
-- EchoesUI files under test actually call.

local function noop() end

local FontString = {}
FontString.__index = FontString
function FontString:SetFont() end
function FontString:SetTextColor() end
function FontString:SetText(t) self._text = t end
function FontString:GetText() return self._text end
function FontString:SetPoint() end
function FontString:ClearAllPoints() end
function FontString:SetWidth(v) self._width = v end
function FontString:SetHeight(v) self._height = v end
function FontString:SetJustifyH() end
function FontString:SetJustifyV() end
function FontString:SetShadowColor() end
function FontString:SetShadowOffset() end
function FontString:Show() self._shown = true end
function FontString:Hide() self._shown = false end
function FontString:IsShown() return self._shown end
function FontString:SetAlpha(a) self._alpha = a end
function FontString:GetAlpha() return self._alpha or 1 end

local Texture = {}
Texture.__index = Texture
function Texture:SetTexture() end
function Texture:SetSize(w,h) self._width=w; self._height=h end
function Texture:SetWidth(w) self._width=w end
function Texture:GetWidth() return self._width or 0 end
function Texture:SetHeight() end
function Texture:SetPoint() end
function Texture:ClearAllPoints() end
function Texture:SetTexCoord() end
function Texture:SetVertexColor() end
function Texture:SetBlendMode() end
function Texture:SetRotation() end
function Texture:SetAllPoints() end
function Texture:Show() self._shown = true end
function Texture:Hide() self._shown = false end
function Texture:IsShown() return self._shown end
function Texture:SetAlpha(a) self._alpha = a end
function Texture:GetAlpha() return self._alpha or 1 end

local Frame = {}
Frame.__index = Frame
local frameRegistry = {}

local function newFrame(kind, name, parent)
    local f = setmetatable({
        _kind = kind, _name = name, _parent = parent,
        _shown = false, _alpha = 1, _scripts = {}, _mouseEnabled = false,
        _keyboardEnabled = false, _events = {},
    }, Frame)
    if name then frameRegistry[name] = f; _G[name] = f end
    return f
end

function Frame:SetSize() end
function Frame:SetWidth() end
function Frame:SetHeight() end
function Frame:SetPoint() end
function Frame:ClearAllPoints() end
function Frame:SetAllPoints() end
function Frame:SetFrameStrata() end
function Frame:SetFrameLevel() end
function Frame:SetClampedToScreen() end
function Frame:EnableMouse(v) self._mouseEnabled = v end
function Frame:EnableKeyboard(v) self._keyboardEnabled = v end
function Frame:EnableMouseWheel(v) self._mouseWheelEnabled = v end
function Frame:Show()
    if self._shown then return end
    self._shown = true
    local fn = self._scripts.OnShow
    if fn then fn(self) end
end
function Frame:Hide()
    if not self._shown then return end
    self._shown = false
    local fn = self._scripts.OnHide
    if fn then fn(self) end
end
function Frame:IsShown() return self._shown end
function Frame:SetAlpha(a) self._alpha = a end
function Frame:GetAlpha() return self._alpha end
function Frame:SetScale(s) self._scale = s end
function Frame:GetScale() return self._scale or 1 end
function Frame:GetRight() return nil end
function Frame:GetWidth() return 1024 end
function Frame:GetHeight() return 768 end
function Frame:RegisterForClicks() end
function Frame:SetAutoFocus() end
function Frame:SetTextInsets() end
function Frame:SetMaxLetters(v) self._maxLetters=v end
function Frame:SetText(t) self._text=t or "" end
function Frame:GetText() return self._text or "" end
function Frame:SetFocus() self._hasFocus=true end
function Frame:ClearFocus() self._hasFocus=false end
function Frame:HasFocus() return self._hasFocus == true end
function Frame:SetFontObject() end
function Frame:SetTextColor() end
function Frame:RegisterEvent(e) self._events[e] = true end
function Frame:UnregisterEvent(e) self._events[e] = nil end
function Frame:SetHighlightTexture() end
function Frame:HookScript(event, fn)
    local prev = self._scripts[event]
    self._scripts[event] = function(...)
        if prev then prev(...) end
        fn(...)
    end
end
function Frame:SetScript(event, fn) self._scripts[event] = fn end
function Frame:GetScript(event) return self._scripts[event] end
function Frame:FireEvent(event, ...)
    local fn = self._scripts[event]
    if fn then return fn(self, ...) end
end
function Frame:CreateTexture(name, layer)
    return setmetatable({ _layer = layer }, Texture)
end
function Frame:CreateFontString(name, layer)
    return setmetatable({ _layer = layer }, FontString)
end

_G.CreateFrame = function(kind, name, parent)
    return newFrame(kind, name, parent)
end

_G.UIParent = newFrame("Frame", "UIParent")
_G.GameFontHighlight = {}
_G.UISpecialFrames = {}

local ticked = {}
_G.C_Timer = {
    After = function(delay, fn)
        ticked[#ticked + 1] = { delay = delay, fn = fn }
    end,
}
_G.RunAllTimers = function()
    local pending = ticked
    ticked = {}
    for _, t in ipairs(pending) do t.fn() end
end

local clock = 0
_G.GetTime = function() return clock end
_G.AdvanceClock = function(dt) clock = clock + dt end

_G.GameTooltip = newFrame("Frame", "GameTooltip")
function _G.GameTooltip:SetOwner() end
function _G.GameTooltip:ClearLines() self._lines = {} end
function _G.GameTooltip:AddLine(line) self._lines = self._lines or {}; self._lines[#self._lines+1] = line end
function _G.GameTooltip:AddDoubleLine() end
function _G.GameTooltip:IsVisible() return self._shown end
function _G.GameTooltip:GetItem() return self._link and "Mock Item", self._link end
function _G.GameTooltip:SetHyperlink(link)
    self._link = link
    local fn = self._scripts.OnTooltipSetItem
    if fn then fn(self) end
end
_G.ItemRefTooltip = newFrame("Frame", "ItemRefTooltip")
for key, value in pairs({
    ClearLines=_G.GameTooltip.ClearLines, AddLine=_G.GameTooltip.AddLine,
    AddDoubleLine=_G.GameTooltip.AddDoubleLine, IsVisible=_G.GameTooltip.IsVisible,
    GetItem=_G.GameTooltip.GetItem, SetHyperlink=_G.GameTooltip.SetHyperlink,
}) do _G.ItemRefTooltip[key] = value end

_G.IsShiftKeyDown = function() return false end
local mockChatActive = false
_G.ChatEdit_GetActiveWindow = function()
    return mockChatActive and {} or nil
end
_G.SetMockChatActive = function(active)
    mockChatActive = active == true
end
_G.SlashCmdList = {}
local mockChatMessages = {}
_G.SendChatMessage = function(message, channel) mockChatMessages[#mockChatMessages+1] = {message,channel} end
_G.GetMockChatMessages = function() return mockChatMessages end
_G.ClearMockChatMessages = function() mockChatMessages = {} end
_G.UnitName = function() return "TestPlayer" end
_G.GetInventoryItemLink = function(_, slot)
    local entries = { [1]=1001, [5]=1005, [16]=1016 }
    return entries[slot] and ("|cffffffff|Hitem:" .. entries[slot] .. ":0:0:0:0:0:0:0|h[Mock Item " .. entries[slot] .. "]|h|r") or nil
end
_G.GetInventoryItemTexture = function(_, slot) return "Interface\\Icons\\INV_Misc_QuestionMark" end
_G.GetItemInfo = function(link)
    local entry = type(link)=="number" and tostring(link) or (link and link:match("item:(%d+)")) or "0"
    return "Mock Item " .. entry, link, 2, 80, 1, "Armor", "Misc", 1, "", "Interface\\Icons\\INV_Misc_QuestionMark"
end
_G.GetAddOnMetadata = function() return "1.1.0" end

-- CHAT_MSG_SYSTEM/etc filter registry, matching Blizzard's real chained-filter
-- behavior: every registered filter for an event runs in registration order;
-- if any returns true the message is suppressed from chat (we don't render
-- chat, so only the suppression/handling side effects matter here).
local mockChatFilters = {}
_G.ChatFrame_AddMessageEventFilter = function(event, filter)
    mockChatFilters[event] = mockChatFilters[event] or {}
    mockChatFilters[event][#mockChatFilters[event] + 1] = filter
end
_G.SimulateChatMessageEvent = function(event, msg)
    local suppressed = false
    for _, filter in ipairs(mockChatFilters[event] or {}) do
        if filter(nil, event, msg) then suppressed = true end
    end
    return suppressed
end
_G.print = print
_G.unpack = table.unpack or unpack
