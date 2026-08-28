local UI = EchoesUI
if not UI or not UI.UtilityShell or not UI.ScreenManager then return end
local Theme=UI.Theme
local ASSET = "Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\"
local function Art(parent, layer, name, uMax, vMax)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(ASSET .. name)
    t:SetTexCoord(0, uMax, 0, vMax)
    return t
end
local function ArtMirrored(parent, layer, name, uMax, vMax)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(ASSET .. name)
    t:SetTexCoord(uMax, 0, 0, vMax)
    return t
end
local function NeutralizeRow(row)
    Theme:SetTextureColor(row.channel, {0, 0, 0, 0})
    Theme:SetTextureColor(row.selection, {0, 0, 0, 0})
    Theme:SetTextureColor(row.edge, {0, 0, 0, 0})
end
-- Native focused/hovered/pressed booleans remain the sole authority for which
-- art variant shows; the underlying native channel/selection/edge fills are
-- neutralized to zero alpha above so they never paint a rectangle beneath.
-- "selected/active" for a result row maps to native keyboard focus (self.focused):
-- the row Enter would currently activate -- there is no other persistent
-- "selected result" concept in native SearchScreen.lua (OpenResult hides the
-- screen immediately), so this is the one real state that matches "active/
-- open target" without inventing anything new.
local function WireRowArt(row, resting, focus, selected, isSelected)
    NeutralizeRow(row)
    row.onStateChange = function(self)
        if isSelected and isSelected(self) then
            resting:Hide(); if focus then focus:Hide() end; selected:Show()
        elseif self.focused or self.hovered then
            resting:Hide(); if selected then selected:Hide() end; focus:Show()
        else
            focus:Hide(); if selected then selected:Hide() end; resting:Show()
        end
    end
    row.onStateChange(row)
end

local Screen=UI.UtilityShell:Create({id="search",name="EchoesUISearchScreen",title="CODEX SEARCH",subtitle="SEARCH THE AUTHORITATIVE WORLDSOUL CODEX",accentColor=Theme.colors.worldsoul})
Screen.results={}; Screen.searching=false

-- Search-local shared-shell material pass. Each UtilityShell:Create() call
-- builds its own independent frame/texture set, so this only affects this
-- Search instance -- Settings/Accessibility keep their own native shell.
Theme:SetTextureColor(Screen.veil, {0.006, 0.009, 0.014, 0.78})
Screen.rimPanel:SetAlpha(0)
Screen.corePanel:SetAlpha(0)
Screen.headerPlate:SetAlpha(0)
Screen.headerLine:SetAlpha(0)

local headerCrown = Art(Screen.frame, "ARTWORK", "CodexHeaderCrown", 0.63476562, 0.546875)
headerCrown:SetSize(650, 70); headerCrown:SetPoint("TOP", Screen.frame, "TOP", 0, -22); headerCrown:SetAlpha(0.78)

local shellTopRail = Art(Screen.frame, "ARTWORK", "CodexShellTopRail", 0.609375, 0.5625)
shellTopRail:SetSize(1248, 18); shellTopRail:SetPoint("TOP", Screen.frame, "TOP", 0, -20); shellTopRail:SetAlpha(0.62)

local shellSideSpineL = Art(Screen.frame, "ARTWORK", "CodexShellSideSpine", 0.875, 0.625)
shellSideSpineL:SetSize(28, 640); shellSideSpineL:SetPoint("TOPLEFT", Screen.frame, "TOPLEFT", 16, -92); shellSideSpineL:SetAlpha(0.54)
local shellSideSpineR = ArtMirrored(Screen.frame, "ARTWORK", "CodexShellSideSpine", 0.875, 0.625)
shellSideSpineR:SetSize(28, 640); shellSideSpineR:SetPoint("TOPRIGHT", Screen.frame, "TOPRIGHT", -16, -92); shellSideSpineR:SetAlpha(0.54)

local shellLowerL = Art(Screen.frame, "ARTWORK", "CodexShellLowerTerminus", 0.9375, 1.0)
shellLowerL:SetSize(480, 16); shellLowerL:SetPoint("BOTTOMLEFT", Screen.frame, "BOTTOMLEFT", 30, 16); shellLowerL:SetAlpha(0.58)
local shellLowerR = ArtMirrored(Screen.frame, "ARTWORK", "CodexShellLowerTerminus", 0.9375, 1.0)
shellLowerR:SetSize(480, 16); shellLowerR:SetPoint("BOTTOMRIGHT", Screen.frame, "BOTTOMRIGHT", -30, 16); shellLowerR:SetAlpha(0.58)

-- Shared navigation keys (Back / Core-Home / Close) live on UtilityShell.lua's
-- shell.back/home/close fields, but each instance belongs to this Search
-- frame alone -- art and neutralization are attached here, never in the
-- shared file.
for _, id in ipairs({"back", "home", "close"}) do
    local row = Screen[id]
    local resting = Art(row.root, "ARTWORK", "CodexNavKeyResting", 0.5390625, 0.59375)
    resting:SetSize(138, 38); resting:SetPoint("TOPLEFT", row.root, "TOPLEFT", 0, 0); resting:SetAlpha(0.58)
    local focus = Art(row.root, "ARTWORK", "CodexNavKeyFocus", 0.5390625, 0.59375)
    focus:SetSize(138, 38); focus:SetPoint("TOPLEFT", row.root, "TOPLEFT", 0, 0); focus:SetAlpha(0.68)
    WireRowArt(row, resting, focus, nil, nil)
end

local fieldSeat=Screen.content:CreateTexture(nil,"BACKGROUND"); Theme:SetTextureColor(fieldSeat,Theme.colors.stoneLift); fieldSeat:SetSize(920,54); fieldSeat:SetPoint("TOPLEFT",Screen.content,"TOPLEFT",30,-10)
fieldSeat:SetAlpha(0)
local queryChannel = Art(Screen.content, "ARTWORK", "CodexQueryChannel", 0.8984375, 0.84375)
queryChannel:SetSize(920, 54); queryChannel:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 30, -10); queryChannel:SetAlpha(0.76)
local queryFocused = Art(Screen.content, "ARTWORK", "CodexQueryFocused", 0.8984375, 0.84375)
queryFocused:SetSize(920, 54); queryFocused:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 30, -10); queryFocused:SetAlpha(0.68); queryFocused:Hide()
local field=CreateFrame("EditBox","EchoesUICodexSearchField",Screen.content)
field:SetSize(870,44); field:SetPoint("CENTER",fieldSeat,"CENTER",0,0); field:SetAutoFocus(false); field:SetMaxLetters(80); field:SetFontObject(GameFontHighlight); field:SetTextInsets(12,12,0,0); field:SetTextColor(unpack(Theme.colors.text))
field:SetScript("OnEditFocusGained",function() queryFocused:Show() end)
field:SetScript("OnEditFocusLost",function() queryFocused:Hide() end)
Screen.field=field
local search=UI.ProgressionRow:Create(Screen.content,{id="searchNow",name="EchoesUICodexSearchNow",width=160,height=54,icon=false,compact=true,label="SEARCH",value="",progress=0,onActivate=function() Screen:PerformSearch() end})
search.root:SetPoint("TOPLEFT",Screen.content,"TOPLEFT",950,-10); Screen.search=search; Screen:AddControl(search,"searchNow")
do
    local resting = Art(search.root, "ARTWORK", "CodexSearchActuatorResting", 0.625, 0.84375)
    resting:SetSize(160, 54); resting:SetPoint("TOPLEFT", search.root, "TOPLEFT", 0, 0); resting:SetAlpha(0.62)
    local focus = Art(search.root, "ARTWORK", "CodexSearchActuatorFocus", 0.625, 0.84375)
    focus:SetSize(160, 54); focus:SetPoint("TOPLEFT", search.root, "TOPLEFT", 0, 0); focus:SetAlpha(0.70)
    WireRowArt(search, resting, focus, nil, nil)
end
local status=Screen.content:CreateFontString(nil,"OVERLAY"); status:SetFont(Theme.fonts.readable,11); status:SetText("Enter at least two characters."); status:SetTextColor(unpack(Theme.colors.textMuted)); status:SetPoint("TOPLEFT",Screen.content,"TOPLEFT",32,-73); status:SetWidth(1060); status:SetHeight(18); status:SetJustifyH("LEFT"); Screen.status=status
local resultsSpine = Art(Screen.content, "ARTWORK", "CodexSearchResultsSpine", 0.52734375, 0.86328125)
resultsSpine:SetSize(1080, 442); resultsSpine:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 30, -105); resultsSpine:SetAlpha(0.58)
Screen.resultRows={}
for i=1,7 do
    local row=UI.ProgressionRow:Create(Screen.content,{id="result"..i,name="EchoesUICodexSearchResult"..i,width=1080,height=58,icon=false,label="",meta="",value="",progress=0,onActivate=function() Screen:OpenResult(i) end})
    row.root:SetPoint("TOPLEFT",Screen.content,"TOPLEFT",30,-(105+(i-1)*64)); row:SetEnabled(false); Screen.resultRows[i]=row; Screen:AddControl(row,"result"..i)
    local resting = Art(row.root, "ARTWORK", "CodexResultMemoryResting", 0.52734375, 0.90625)
    resting:SetSize(1080, 58); resting:SetPoint("TOPLEFT", row.root, "TOPLEFT", 0, 0); resting:SetAlpha(0.60)
    local focus = Art(row.root, "ARTWORK", "CodexResultMemoryFocus", 0.52734375, 0.90625)
    focus:SetSize(1080, 58); focus:SetPoint("TOPLEFT", row.root, "TOPLEFT", 0, 0); focus:SetAlpha(0.48)
    local selected = Art(row.root, "ARTWORK", "CodexResultMemorySelected", 0.52734375, 0.90625)
    selected:SetSize(1080, 58); selected:SetPoint("TOPLEFT", row.root, "TOPLEFT", 0, 0); selected:SetAlpha(0.74)
    WireRowArt(row, resting, focus, selected, function(self) return self.focused end)
end
function Screen:IsAvailable()
    local caps=APB and APB.echoes and APB.echoes.caps or {}
    return UI.flags.nativeSearch~=false and APB and APB.echoes and APB.echoes.compatible==1 and caps.codex_search_v1==true and caps.codex_state_v1==true
end
function Screen:isInputCaptured() return self.field:HasFocus() end
function Screen:PerformSearch()
    -- The server never correlates a CODEX_RESULT/CODEX_DONE back to a
    -- specific query, so a second search issued while one is still in
    -- flight has no reliable way to tell its own results apart from the
    -- abandoned query's -- a stale result could overwrite a newer query's
    -- results. Refusing to start a new search until the current one
    -- resolves (or times out) makes that race structurally impossible.
    if self.searching then return false end
    local query=self.field:GetText() or ""; query=query:gsub("^%s+",""):gsub("%s+$","")
    if #query<2 then self.status:SetText("Enter at least two characters."); return false end
    self.results={}; self.searching=true; self.status:SetText("Searching the server-owned Codex…")
    for _,row in ipairs(self.resultRows) do row.label:SetText(""); row.meta:SetText(""); row:SetEnabled(false) end
    self.field:ClearFocus()
    local sent=APB:SearchCodex(query)
    if not sent then self.searching=false; return false end
    self.searchToken=(self.searchToken or 0)+1; local token=self.searchToken
    C_Timer.After(6,function()
        if Screen.searching and Screen.searchToken==token then
            Screen.searching=false; Screen.status:SetText("Search could not be completed. Try again shortly.")
        end
    end)
    return true
end
function Screen:OnCodex(verb,fields)
    if verb=="CODEX_RESULT" and self.searching then
        local result={topic=tonumber(fields.topic),page=tonumber(fields.page),title=fields.title,excerpt=fields.excerpt}; self.results[#self.results+1]=result
        local row=self.resultRows[#self.results]; if row then row.label:SetText((result.title or "CODEX").."  ·  PAGE "..tostring(result.page)); row.meta:SetText(result.excerpt or ""); row:SetEnabled(true) end
    elseif verb=="CODEX_DONE" and fields.kind=="search" and self.searching then
        self.searching=false; self.searchToken=(self.searchToken or 0)+1
        local total=tonumber(fields.total) or tonumber(fields.count) or #self.results
        self.status:SetText(total==0 and "No Codex pages matched." or (tostring(total).." matching page"..(total==1 and "" or "s")..(total>7 and "; first 7 shown." or ".")))
        if #self.results>0 then self.input:SetFocusById("result1") end
    elseif verb=="ERROR" and self.active and self.searching then
        self.searching=false; self.searchToken=(self.searchToken or 0)+1
        self.status:SetText("Search could not be completed. Try again shortly.")
    end
end
function Screen:OpenResult(index)
    local result=self.results[index]; if not result then return false end
    self:Hide(); return UI.CodexScreen and UI.CodexScreen:ShowAt(result.topic,result.page)
end
field:SetScript("OnEnterPressed",function() Screen:PerformSearch() end)
field:SetScript("OnEscapePressed",function(self) self:ClearFocus(); Screen.input:SetFocusById("searchNow") end)
Screen.input:SetNavigation({"searchNow","result1","result2","result3","result4","result5","result6","result7","back","home","close"},nil)
Screen.defaultFocus="searchNow"
function Screen:Show() UI.UtilityShell.Show(self,"searchNow"); self.field:SetFocus(); self.status:SetText("Enter at least two characters.") end
function Screen:Hide()
    -- Closing Search mid-request must not leave `searching` stuck true --
    -- otherwise reopening the screen and typing a fresh query would be
    -- silently refused by the overlap guard in PerformSearch above.
    self.searching=false; self.searchToken=(self.searchToken or 0)+1
    UI.UtilityShell.Hide(self)
end
if APB and APB.SubscribeCodex then APB:SubscribeCodex(function(v,f) Screen:OnCodex(v,f) end) end
UI.SearchScreen=Screen; UI.ScreenManager:Register("search",Screen,false); UI.modules.SearchScreen=true
