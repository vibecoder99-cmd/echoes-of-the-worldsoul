local UI = EchoesUI
if not UI or not UI.UtilityShell or not UI.ScreenManager then return end
local Theme = UI.Theme
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
-- Native focused/hovered/pressed booleans (and, for topics, isSelected) remain
-- the sole authority for which art variant shows; the underlying native
-- channel/selection/edge fills are neutralized to zero alpha above so they
-- never paint a rectangle beneath or beside the art.
local function WireRowArt(row, resting, focus, selected, isSelected)
    NeutralizeRow(row)
    row.onStateChange = function(self)
        if isSelected and isSelected() then
            resting:Hide(); if focus then focus:Hide() end; selected:Show()
        elseif self.focused or self.hovered then
            resting:Hide(); if selected then selected:Hide() end; focus:Show()
        else
            focus:Hide(); if selected then selected:Hide() end; resting:Show()
        end
    end
    row.onStateChange(row)
end

local Screen = UI.UtilityShell:Create({id="codex",name="EchoesUICodexScreen",title="WORLDSOUL CODEX",subtitle="SERVER-OWNED KNOWLEDGE OF THE ECHOES"})
Screen.topics={}; Screen.selectedTopic=1; Screen.selectedPage=1; Screen.loading=false

-- Codex-local shared-shell material pass. UtilityShell:Create() builds a new,
-- independent frame/texture set per call, so this only affects this Codex
-- instance -- Settings/Accessibility keep their own native shell untouched.
Theme:SetTextureColor(Screen.veil, {0.006, 0.009, 0.014, 0.72})
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
-- shell.back/home/close fields, but each instance belongs to this Codex frame
-- alone -- art and neutralization are attached here, never in the shared file.
for _, id in ipairs({"back", "home", "close"}) do
    local row = Screen[id]
    local resting = Art(row.root, "ARTWORK", "CodexNavKeyResting", 0.5390625, 0.59375)
    resting:SetSize(138, 38); resting:SetPoint("TOPLEFT", row.root, "TOPLEFT", 0, 0); resting:SetAlpha(0.58)
    local focus = Art(row.root, "ARTWORK", "CodexNavKeyFocus", 0.5390625, 0.59375)
    focus:SetSize(138, 38); focus:SetPoint("TOPLEFT", row.root, "TOPLEFT", 0, 0); focus:SetAlpha(0.68)
    WireRowArt(row, resting, focus, nil, nil)
end

local rail=Screen.content:CreateTexture(nil,"BACKGROUND"); Theme:SetTextureColor(rail,Theme.colors.stone)
rail:SetSize(350,540); rail:SetPoint("TOPLEFT",Screen.content,"TOPLEFT",0,0)
rail:SetAlpha(0)
local archiveSpine = Art(Screen.content, "ARTWORK", "CodexArchiveSpine", 0.68359375, 0.52734375)
archiveSpine:SetSize(350, 540); archiveSpine:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 0, 0); archiveSpine:SetAlpha(0.72)

Screen.topicRows={}
for i=1,11 do
    local row=UI.ProgressionRow:Create(Screen.content,{
        id="topic"..i,name="EchoesUICodexTopic"..i,width=330,height=42,icon=false,compact=true,
        label="TOPIC "..i,meta="",value="",progress=0,
        onActivate=function() Screen:SelectTopic(i,1) end,
    })
    row.root:SetPoint("TOPLEFT",Screen.content,"TOPLEFT",10,-(10+(i-1)*47))
    Screen.topicRows[i]=row; Screen:AddControl(row,"topic"..i)
    local resting = Art(row.root, "ARTWORK", "CodexTopicMemoryResting", 0.64453125, 0.65625)
    resting:SetSize(330, 42); resting:SetPoint("TOPLEFT", row.root, "TOPLEFT", 0, 0); resting:SetAlpha(0.62)
    local focus = Art(row.root, "ARTWORK", "CodexTopicMemoryFocus", 0.64453125, 0.65625)
    focus:SetSize(330, 42); focus:SetPoint("TOPLEFT", row.root, "TOPLEFT", 0, 0); focus:SetAlpha(0.48)
    local selected = Art(row.root, "ARTWORK", "CodexTopicMemorySelected", 0.64453125, 0.65625)
    selected:SetSize(330, 42); selected:SetPoint("TOPLEFT", row.root, "TOPLEFT", 0, 0); selected:SetAlpha(0.74)
    local index = i
    WireRowArt(row, resting, focus, selected, function() return index == Screen.selectedTopic end)
end
local detail=Screen.content:CreateTexture(nil,"BACKGROUND"); Theme:SetTextureColor(detail,Theme.colors.void)
detail:SetSize(744,420); detail:SetPoint("TOPLEFT",Screen.content,"TOPLEFT",378,-10)
detail:SetAlpha(0)
local readingPlane = Art(Screen.content, "ARTWORK", "CodexReadingPlane", 0.7265625, 0.8203125)
readingPlane:SetSize(744, 420); readingPlane:SetPoint("TOPLEFT", Screen.content, "TOPLEFT", 378, -10); readingPlane:SetAlpha(0.62)
local detailTitle = Screen.content:CreateFontString(nil,"OVERLAY")
detailTitle:SetFont(Theme.fonts.monument,26,"OUTLINE"); detailTitle:SetText("CONNECTING…"); detailTitle:SetTextColor(unpack(Theme.colors.text)); detailTitle:SetPoint("TOPLEFT",detail,"TOPLEFT",34,-34); detailTitle:SetWidth(680); detailTitle:SetHeight(38); detailTitle:SetJustifyH("LEFT")
local pageMark = Screen.content:CreateFontString(nil,"OVERLAY")
pageMark:SetFont(Theme.fonts.readable,11); pageMark:SetText(""); pageMark:SetTextColor(unpack(Theme.colors.worldsoulPale)); pageMark:SetPoint("TOPLEFT",detail,"TOPLEFT",35,-82)
local body = Screen.content:CreateFontString(nil,"OVERLAY")
body:SetFont(Theme.fonts.readable,17); body:SetText("Waiting for the Worldsoul Codex."); body:SetTextColor(unpack(Theme.colors.text)); body:SetPoint("TOPLEFT",detail,"TOPLEFT",35,-120); body:SetWidth(670); body:SetHeight(245); body:SetJustifyH("LEFT"); body:SetJustifyV("TOP")
Screen.detailTitle,Screen.pageMark,Screen.body=detailTitle,pageMark,body
local function pageButton(id,label,x,delta)
    local row=UI.ProgressionRow:Create(Screen.content,{id=id,name="EchoesUICodex"..id,width=220,height=54,icon=false,compact=true,label=label,value="",progress=0,onActivate=function() Screen:TurnPage(delta) end})
    row.root:SetPoint("TOPLEFT",Screen.content,"TOPLEFT",x,-458); Screen:AddControl(row,id)
    local resting = Art(row.root, "ARTWORK", "CodexPageActuatorResting", 0.859375, 0.84375)
    resting:SetSize(220, 54); resting:SetPoint("TOPLEFT", row.root, "TOPLEFT", 0, 0); resting:SetAlpha(0.62)
    local focus = Art(row.root, "ARTWORK", "CodexPageActuatorFocus", 0.859375, 0.84375)
    focus:SetSize(220, 54); focus:SetPoint("TOPLEFT", row.root, "TOPLEFT", 0, 0); focus:SetAlpha(0.66)
    WireRowArt(row, resting, focus, nil, nil)
    return row
end
Screen.previous=pageButton("previous","‹  PREVIOUS",464,-1); Screen.next=pageButton("next","NEXT  ›",880,1)

function Screen:IsAvailable()
    return UI.flags.nativeCodex~=false and APB and APB.echoes and APB.echoes.compatible==1 and APB.echoes.caps.codex_state_v1==true
end
function Screen:RefreshTopics()
    for i,row in ipairs(self.topicRows) do
        local topic=self.topics[i]; row.label:SetText(topic and topic.title or ("TOPIC "..i)); row:SetEnabled(topic~=nil)
        row.onStateChange(row)
    end
end
function Screen:SelectTopic(topic,page)
    local meta=self.topics[topic]; if not meta then return false end
    self.selectedTopic=topic; self.selectedPage=math.max(1,math.min(page or 1,tonumber(meta.pages) or 1)); self.loading=true
    for _,row in ipairs(self.topicRows) do row.onStateChange(row) end
    self.detailTitle:SetText(meta.title); self.pageMark:SetText("PAGE "..self.selectedPage.." / "..tostring(meta.pages)); self.body:SetText("Retrieving this page…")
    APB:RequestCodexPage(self.selectedTopic,self.selectedPage)
    -- No response (lost message, capability revoked mid-session) must not
    -- leave the page silently frozen on "Retrieving this page..." forever --
    -- matching the timeout-recovery pattern every other native screen uses.
    -- The token+topic/page match makes this a no-op if the player has since
    -- navigated away or the real response already arrived.
    local topic,page=self.selectedTopic,self.selectedPage
    self.pageTimeoutToken=(self.pageTimeoutToken or 0)+1; local token=self.pageTimeoutToken
    C_Timer.After(6,function()
        if Screen.active and Screen.pageTimeoutToken==token and Screen.selectedTopic==topic and Screen.selectedPage==page and Screen.loading then
            Screen.loading=false; Screen.body:SetText("The Codex request could not be completed. The gossip Codex remains available.")
        end
    end)
    return true
end
function Screen:TurnPage(delta) return self:SelectTopic(self.selectedTopic,self.selectedPage+delta) end
function Screen:OnCodex(verb,fields)
    if verb=="CODEX_TOPIC" then
        local i=tonumber(fields.topic); if i then self.topics[i]={title=fields.title,icon=tonumber(fields.icon),pages=tonumber(fields.pages)} end
        self:RefreshTopics()
    elseif verb=="CODEX_DONE" and fields.kind=="manifest" then
        self.loading=false; self:RefreshTopics(); if self.active then self:SelectTopic(self.selectedTopic,self.selectedPage) end
    elseif verb=="CODEX_PAGE" and tonumber(fields.topic)==self.selectedTopic and tonumber(fields.page)==self.selectedPage then
        self.loading=false; self.detailTitle:SetText(fields.title or "CODEX"); self.pageMark:SetText("PAGE "..fields.page.." / "..fields.count); self.body:SetText(fields.body or "")
        local count=tonumber(fields.count) or 1; self.previous:SetEnabled(self.selectedPage>1); self.next:SetEnabled(self.selectedPage<count)
    elseif verb=="ERROR" and self.active then
        -- A rate-limited or otherwise-failed response can arrive for a page
        -- request the player has since navigated away from (rapid NEXT, a
        -- topic switch, or a Search result opening a different page while a
        -- prior request was still in flight). Only surface the failure if it
        -- still corresponds to what is currently outstanding AND currently
        -- desired -- i.e. nothing newer has superseded it. A stale error is
        -- silently dropped; the newer request's own response governs.
        local pageState=APB.echoes.codexPage
        local stale=pageState and pageState.sentTopic~=nil and not (
            pageState.sentTopic==self.selectedTopic and pageState.sentPage==self.selectedPage
            and pageState.sentTopic==pageState.desiredTopic and pageState.sentPage==pageState.desiredPage)
        if not stale then
            self.loading=false; self.body:SetText("The Codex request could not be completed. The gossip Codex remains available.")
        end
    end
end
function Screen:ShowAt(topic,page)
    if not self:IsAvailable() then return false end
    UI.UtilityShell.Show(self,"topic"..tostring(topic or 1)); self.selectedTopic=topic or 1; self.selectedPage=page or 1
    if next(self.topics) then self:SelectTopic(self.selectedTopic,self.selectedPage) else
        self.loading=true; self.body:SetText("Retrieving the Codex index…"); APB:RequestCodexManifest()
        self.manifestTimeoutToken=(self.manifestTimeoutToken or 0)+1; local token=self.manifestTimeoutToken
        C_Timer.After(6,function()
            if Screen.active and Screen.manifestTimeoutToken==token and Screen.loading and not next(Screen.topics) then
                Screen.loading=false; Screen.body:SetText("The Codex request could not be completed. The gossip Codex remains available.")
            end
        end)
    end
    return true
end
function Screen:Show() return self:ShowAt(self.selectedTopic,self.selectedPage) end
function Screen:Hide()
    -- Invalidate any in-flight timeout closures and stop treating this
    -- screen as loading, so reopening never inherits a stale pending state
    -- from a request abandoned by closing the screen.
    self.pageTimeoutToken=(self.pageTimeoutToken or 0)+1
    self.manifestTimeoutToken=(self.manifestTimeoutToken or 0)+1
    self.loading=false
    UI.UtilityShell.Hide(self)
end
local order={}; for i=1,11 do order[#order+1]="topic"..i end; order[#order+1]="previous"; order[#order+1]="next"; order[#order+1]="back"; order[#order+1]="home"; order[#order+1]="close"
Screen.input:SetNavigation(order,nil); Screen.defaultFocus="topic1"
if APB and APB.SubscribeCodex then APB:SubscribeCodex(function(v,f) Screen:OnCodex(v,f) end) end
UI.CodexScreen=Screen; UI.ScreenManager:Register("codex",Screen,false); UI.modules.CodexScreen=true
