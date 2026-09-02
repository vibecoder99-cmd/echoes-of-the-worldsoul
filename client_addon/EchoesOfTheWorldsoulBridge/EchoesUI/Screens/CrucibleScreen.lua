local UI=EchoesUI
if not UI or not UI.ScreenManager or not UI.InputManager or not UI.ProgressionRow then return end
local Theme,Animation=UI.Theme,UI.AnimationController
local Screen={id="crucible",active=false,selected="life_leech",amount=1000,previewCache={},previewPending=false,investPending=false,openToken=0}
-- Crucible-local materials. Keep neutral UI gray out of the finished machine without
-- changing the shared Dashboard, Progression, or World Threat material language.
local MAT={
    iron={0.030,0.028,0.026,1}, ironLift={0.067,0.058,0.047,1}, stone={0.026,0.029,0.032,1},
    bronzeRecess={0.120,0.082,0.038,1}, bronzeEdge={0.285,0.190,0.075,1}, well={0.010,0.009,0.009,0.98},
}

local function Solid(parent,layer,color) local t=parent:CreateTexture(nil,layer); Theme:SetTextureColor(t,color); return t end
local function Label(parent,text,font,size,color,point,relative,relativePoint,x,y,width,justify)
    local v=parent:CreateFontString(nil,"OVERLAY"); v:SetFont(font,size,font==Theme.fonts.monument and "OUTLINE" or nil); v:SetText(text); v:SetTextColor(unpack(color)); v:SetPoint(point,relative,relativePoint,x,y)
    if width then v:SetWidth(width); v:SetJustifyH(justify or "LEFT") end; return v
end
local function FormatInt(value)
    local s=tostring(math.floor(tonumber(value) or 0)); local sign=""; if s:sub(1,1)=="-" then sign="-"; s=s:sub(2) end
    while true do local n,c=s:gsub("^(%d+)(%d%d%d)","%1,%2"); s=n; if c==0 then break end end; return sign..s
end
local function ParseMap(raw) local r={}; if raw then for e in tostring(raw):gmatch("[^,]+") do local k,v=e:match("^([^:]+):(.+)$"); if k then r[k]=v end end end; return r end
local function Pct(value) return string.format("%.2f%%",tonumber(value) or 0) end

local GROUPS={
    {id="foundation",label="FOUNDATION",side="left",x=70,y=154,categories={"life_leech","fortitude","melee_power","spell_power"}},
    {id="damage",label="DAMAGE",side="right",x=1164,y=154,categories={"crit_rating","haste_rating","armor_pen","execute_power"}},
    {id="survival",label="SURVIVAL",side="left",x=70,y=493,categories={"spell_mitigation","dodge_rating","parry_rating","reflect_chance"}},
    {id="utility",label="UTILITY",side="right",x=1164,y=454,categories={"cooldown_reduction","movement_speed","res_resilience","aether_surge","attunement_echo"}},
}
local META={
 life_leech={label="Life Leech",desc="Restores HP based on damage dealt to enemies."},fortitude={label="Fortitude",desc="Multiplies bonus HP from STA absorption."},
 melee_power={label="Melee Power",desc="Increases your absorbed weapon DPS contribution."},spell_power={label="Spell Power",desc="Increases INT absorption contribution to spell damage."},
 crit_rating={label="Crit Rating",desc="Adds flat critical strike chance to melee, ranged, and spells."},haste_rating={label="Haste Rating",desc="Reduces GCD and increases attack and cast speed."},
 armor_pen={label="Armor Penetration",desc="Boosts all outgoing damage, scaling with how armored your target is."},execute_power={label="Execute Power",desc="Bonus damage dealt when target is below 20% HP."},
 spell_mitigation={label="Spell Mitigation",desc="Reduces incoming magic damage."},dodge_rating={label="Dodge Rating",desc="Adds flat dodge percentage via combat rating."},
 parry_rating={label="Parry Rating",desc="Adds flat parry percentage via combat rating."},reflect_chance={label="Reflect Chance",desc="Chance to reflect incoming spells back at the attacker."},
 cooldown_reduction={label="Cooldown Reduction",desc="Chance to reset a spell cooldown after casting."},movement_speed={label="Movement Speed",desc="Increases run speed. Does not affect mounts."},
 res_resilience={label="Res Resilience",desc="Reduces durability loss on death."},aether_surge={label="Aether Surge",desc="Bonus Essence from kills and quests."},attunement_echo={label="Attunement Echo",desc="Bonus attunement XP rate from kills."},
}

local frame=CreateFrame("Frame","EchoesUICrucibleScreen",UIParent); frame:SetSize(1672,941); frame:SetPoint("CENTER",UIParent,"CENTER",0,0); frame:SetFrameStrata("DIALOG"); frame:EnableMouse(true); frame:Hide(); Screen.frame=frame
for row=0,1 do for col=0,3 do
    local tile=frame:CreateTexture(nil,"BACKGROUND"); tile:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\C43_"..col..row)
    local w=col==3 and 136 or 512; local h=row==1 and 429 or 512; tile:SetSize(w,h); tile:SetPoint("TOPLEFT",frame,"TOPLEFT",col*512,-row*512); tile:SetTexCoord(0,w/512,0,h/512); tile:SetVertexColor(0.24,0.22,0.20,0.22)
end end
local veil=Solid(frame,"BACKGROUND",{0.004,0.006,0.009,0.82}); veil:SetAllPoints(frame)

-- Compressed outer housing. Thin broken ribs retain the silhouette; bronze seams
-- make the remaining dark masses read as artifact material rather than blockout.
local shellTop=Solid(frame,"ARTWORK",MAT.iron); shellTop:SetSize(1490,9); shellTop:SetPoint("TOP",frame,"TOP",0,-94)
local shellInset=Solid(frame,"OVERLAY",MAT.bronzeEdge); shellInset:SetSize(832,2); shellInset:SetPoint("CENTER",shellTop,"CENTER",0,0); shellInset:SetAlpha(0.72)
local shellL=Solid(frame,"ARTWORK",MAT.ironLift); shellL:SetSize(13,718); shellL:SetPoint("TOPLEFT",frame,"TOPLEFT",48,-124)
local shellR=Solid(frame,"ARTWORK",MAT.ironLift); shellR:SetSize(13,718); shellR:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-48,-124)
-- Gate 2: outer shell rails/plates removed as redundant (LEVEL-1-PRUNE-LIST.md)
-- -- the accepted chamber V3 and Gate 2 bank/reservoir/regulator art already
-- supply enough structural read without this separate outer frame.
local outerPlates={}
for _,d in ipairs({{67,121,258,8},{67,840,397,9},{1198,121,407,8},{1351,840,254,9},{486,160,9,595},{1177,160,9,595},{500,801,118,10},{1054,801,118,10}}) do
    local p=Solid(frame,"ARTWORK",d[3]<20 and MAT.bronzeRecess or MAT.iron); p:SetSize(d[3],d[4]); p:SetPoint("TOPLEFT",frame,"TOPLEFT",d[1],-d[2]); p:SetAlpha(0.88)
    outerPlates[#outerPlates+1]=p
end
for _,p in ipairs(outerPlates) do p:Hide() end
shellTop:Hide(); shellInset:Hide(); shellL:Hide(); shellR:Hide()
-- Scaffold Eradication Sprint: cru-outer-top-rail/side-rail fill the space left by
-- the Gate 2 removal above.
local outerTopRail=frame:CreateTexture(nil,"ARTWORK"); outerTopRail:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_OUTER_TOP_RAIL"); outerTopRail:SetSize(1490,16); outerTopRail:SetPoint("TOPLEFT",frame,"TOPLEFT",91,-90); outerTopRail:SetTexCoord(0,1490/2048,0,1.0)
local outerSideRailL=frame:CreateTexture(nil,"ARTWORK"); outerSideRailL:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_OUTER_SIDE_RAIL"); outerSideRailL:SetSize(13,718); outerSideRailL:SetPoint("TOPLEFT",frame,"TOPLEFT",48,-124); outerSideRailL:SetTexCoord(0,13/16,0,718/1024)
local outerSideRailR=frame:CreateTexture(nil,"ARTWORK"); outerSideRailR:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_OUTER_SIDE_RAIL"); outerSideRailR:SetSize(13,718); outerSideRailR:SetPoint("TOPLEFT",frame,"TOPLEFT",1611,-124); outerSideRailR:SetTexCoord(13/16,0,0,718/1024)
local crown=Solid(frame,"ARTWORK",MAT.iron); crown:SetSize(570,66); crown:SetPoint("TOP",frame,"TOP",0,-17)
-- Scaffold Eradication Sprint: cru-title-crown replaces the flat crown fill.
-- crownL/crownR already hidden (True-Final Material Resolve pass).
local titleCrownArt=frame:CreateTexture(nil,"ARTWORK"); titleCrownArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_TITLE_CROWN"); titleCrownArt:SetAllPoints(crown); titleCrownArt:SetTexCoord(0,570/1024,0,66/128)
crown:Hide()
-- True-final material resolve: removed as redundant (Manifest/PRUNE-LISTS.md).
local crownL=Solid(frame,"ARTWORK",MAT.ironLift); crownL:SetSize(64,24); crownL:SetPoint("RIGHT",crown,"LEFT",12,0); crownL:Hide()
local crownR=Solid(frame,"ARTWORK",MAT.ironLift); crownR:SetSize(81,20); crownR:SetPoint("LEFT",crown,"RIGHT",-12,3); crownR:Hide()
local crownSeam=Solid(frame,"OVERLAY",{1.00,0.31,0.10,1}); crownSeam:SetSize(392,2); crownSeam:SetPoint("TOP",crown,"BOTTOM",0,0); crownSeam:SetAlpha(0.52)
Label(frame,"THE CRUCIBLE",Theme.fonts.monument,27,Theme.colors.text,"CENTER",crown,"CENTER",0,7)
Label(frame,"ESSENCE REFINED INTO PERMANENT DEVELOPMENT",Theme.fonts.readable,10,Theme.colors.textMuted,"CENTER",crown,"CENTER",0,-17)
local function Place(c,x,y) c.root:SetPoint("TOPLEFT",frame,"TOPLEFT",x,-y); return c end
Screen.back=Place(UI.ProgressionRow:Create(frame,{id="back",width=130,height=38,icon=false,compact=true,label="‹  BACK",onActivate=function() Screen:Leave("back") end}),28,24)
Screen.home=Place(UI.ProgressionRow:Create(frame,{id="home",width=130,height=38,icon=false,compact=true,label="CORE / HOME",onActivate=function() Screen:Leave("home") end}),1368,24)
Screen.close=Place(UI.ProgressionRow:Create(frame,{id="close",width=130,height=38,icon=false,compact=true,label="CLOSE  ×",onActivate=function() Screen:CloseCompanion() end}),1514,24)

Screen.familyByCategory={}; Screen.channels={}; Screen.channelOrder={}; Screen.bankFrames={}
local function CreateChannel(parent,id,side)
    local c={id=id,side=side,enabled=true,focused=false,hovered=false,selected=false,invested=0}
    local root=CreateFrame("Button","EchoesUICrucible_"..id,parent); root:SetSize(382,43); root:RegisterForClicks("LeftButtonUp"); root:EnableMouse(true); c.root=root
    -- Gate 1: cru-channel-plate replaces only the static jaw scaffold. seat/outer are
    -- left native (see c:Refresh()) because they drive live hover/selected/awake alpha
    -- feedback -- hiding them would silently remove that state cue.
    -- Gate 1 texture-compatibility repair: padded to 512x64 POT canvas (original
    -- art 382x43, unscaled); SetTexCoord crops back to the exact visible region.
    c.plate=root:CreateTexture(nil,"BACKGROUND"); c.plate:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRUCIBLE_CHANNEL_PLATE"); c.plate:SetAllPoints(root); c.plate:SetTexCoord(0,382/512,0,43/64)
    local seat=Solid(root,"ARTWORK",{0.012,0.013,0.014,0.98}); seat:SetSize(330,35); seat:SetPoint(side=="left" and "LEFT" or "RIGHT",root,side=="left" and "LEFT" or "RIGHT",side=="left" and 30 or -30,0); c.seat=seat
    c.outer=Solid(root,"ARTWORK",MAT.ironLift); c.outer:SetSize(14,39); c.outer:SetPoint(side=="left" and "LEFT" or "RIGHT",root,side=="left" and "LEFT" or "RIGHT",side=="left" and 5 or -5,0)
    c.jaw=Solid(root,"ARTWORK",MAT.bronzeRecess); c.jaw:SetSize(46,17); c.jaw:SetPoint(side=="left" and "LEFT" or "RIGHT",seat,side=="left" and "LEFT" or "RIGHT",side=="left" and -5 or 5,0); c.jaw:Hide()
    c.socket=root:CreateTexture(nil,"OVERLAY"); c.socket:SetTexture("Interface\\Buttons\\UI-Quickslot2"); c.socket:SetSize(30,30); c.socket:SetPoint(side=="left" and "LEFT" or "RIGHT",seat,side=="left" and "LEFT" or "RIGHT",side=="left" and 9 or -9,0)
    c.ember=Solid(root,"OVERLAY",{1.00,0.30,0.09,1}); c.ember:SetSize(8,8); c.ember:SetPoint("CENTER",c.socket,"CENTER",0,0); c.ember:SetAlpha(0)
    c.tongue=Solid(root,"OVERLAY",Theme.colors.bronze); c.tongue:SetSize(18,3); c.tongue:SetPoint(side=="left" and "LEFT" or "RIGHT",seat,side=="left" and "LEFT" or "RIGHT",side=="left" and 48 or -48,-11)
    c.engageBed=Solid(root,"ARTWORK",MAT.bronzeRecess); c.engageBed:SetSize(98,6); c.engageBed:SetPoint(side=="left" and "LEFT" or "RIGHT",root,side=="left" and "RIGHT" or "LEFT",side=="left" and -16 or 16,0); c.engageBed:SetAlpha(0)
    c.engage=Solid(root,"OVERLAY",{1.00,0.33,0.11,1}); c.engage:SetSize(92,2); c.engage:SetPoint("CENTER",c.engageBed,"CENTER",0,0); c.engage:SetAlpha(0)
    c.stop=Solid(root,"OVERLAY",Theme.colors.bronzeBright); c.stop:SetSize(6,18); c.stop:SetPoint(side=="left" and "RIGHT" or "LEFT",c.engage,side=="left" and "RIGHT" or "LEFT",0,0); c.stop:SetAlpha(0)
    c.focusA=Solid(root,"OVERLAY",Theme.colors.text); c.focusA:SetSize(15,2); c.focusA:SetPoint(side=="left" and "TOPLEFT" or "TOPRIGHT",seat,side=="left" and "TOPLEFT" or "TOPRIGHT",side=="left" and 4 or -4,-3); c.focusA:SetAlpha(0)
    c.focusB=Solid(root,"OVERLAY",Theme.colors.text); c.focusB:SetSize(15,2); c.focusB:SetPoint(side=="left" and "BOTTOMRIGHT" or "BOTTOMLEFT",seat,side=="left" and "BOTTOMRIGHT" or "BOTTOMLEFT",side=="left" and -4 or 4,3); c.focusB:SetAlpha(0)
    c.label=Label(root,META[id].label,Theme.fonts.readable,11,Theme.colors.textMuted,"LEFT",seat,"LEFT",side=="left" and 53 or 18,3,210)
    c.value=Label(root,"DORMANT",Theme.fonts.readable,9,Theme.colors.textMuted,"RIGHT",seat,"RIGHT",side=="left" and -12 or -52,3,92,"RIGHT")
    function c:Refresh()
        local awake=self.focused or self.hovered; self.seat:SetAlpha(self.selected and 1 or (awake and 0.88 or 0.62)); self.outer:SetAlpha(awake and 0.90 or 0.60)
        self.socket:SetVertexColor(self.selected and 0.92 or (awake and 0.66 or 0.45),self.selected and 0.48 or 0.33,0.18,1)
        self.ember:SetAlpha(self.selected and 0.92 or (self.invested>0 and (awake and 0.50 or 0.25) or 0.04)); self.engageBed:SetAlpha(self.selected and 0.88 or 0); self.engage:SetAlpha(self.selected and 0.76 or 0); self.stop:SetAlpha(self.selected and 0.90 or 0)
        self.focusA:SetAlpha(self.focused and 0.90 or 0); self.focusB:SetAlpha(self.focused and 0.90 or 0); self.label:SetTextColor(unpack(self.selected and Theme.colors.text or (awake and {0.96,0.76,0.50,1} or Theme.colors.textMuted)))
    end
    function c:SetFocused(v) self.focused=v==true; self:Refresh() end
    function c:SetEnabled(v) self.enabled=v~=false; root:EnableMouse(self.enabled); self:Refresh() end
    function c:SetSelected(v) self.selected=v==true; self:Refresh() end
    function c:SetInvestment(v,max)
        self.invested=tonumber(v) or 0; self.value:SetText(self.invested>0 and FormatInt(self.invested) or "DORMANT"); self.value:SetTextColor(unpack(self.invested>0 and Theme.colors.textMuted or Theme.colors.disabled))
        local ratio=0; if self.invested>0 and (max or 0)>0 then ratio=math.log(1+self.invested)/math.log(1+max) end
        self.tongue:SetWidth(18+math.floor(ratio*88)); self.tongue:SetAlpha(self.invested>0 and (0.36+ratio*0.36) or 0.16); self:Refresh()
    end
    function c:Activate(source) if not self.enabled then return false end; Screen:SelectCategory(self.id,source); return true end
    root:SetScript("OnEnter",function() c.hovered=true; c:Refresh() end); root:SetScript("OnLeave",function() c.hovered=false; c:Refresh() end)
    root:SetScript("OnMouseDown",function(_,b) if b=="LeftButton" then seat:ClearAllPoints(); seat:SetPoint(side=="left" and "LEFT" or "RIGHT",root,side=="left" and "LEFT" or "RIGHT",side=="left" and 31 or -31,-1) end end)
    root:SetScript("OnMouseUp",function(_,b) seat:ClearAllPoints(); seat:SetPoint(side=="left" and "LEFT" or "RIGHT",root,side=="left" and "LEFT" or "RIGHT",side=="left" and 30 or -30,0); if b=="LeftButton" then c:Activate("mouse") end end); c:Refresh(); return c
end

for _,g in ipairs(GROUPS) do
    local bank=CreateFrame("Frame",nil,frame); bank:SetSize(438,g.id=="utility" and 288 or 246); bank:SetPoint("TOPLEFT",frame,"TOPLEFT",g.x,-g.y); Screen.bankFrames[g.id]=bank
    local bankShade=Solid(bank,"BACKGROUND",{0.002,0.004,0.006,0.68}); bankShade:SetSize(394,bank:GetHeight()-48); bankShade:SetPoint(g.side=="left" and "BOTTOMLEFT" or "BOTTOMRIGHT",bank,g.side=="left" and "BOTTOMLEFT" or "BOTTOMRIGHT",g.side=="left" and 18 or -18,0); bankShade:SetAlpha(0.42)
    -- Scaffold Eradication Sprint: cru-bank-bed-4/5 replaces bankShade. BED_5 (taller)
    -- for the 5-channel Utility bank; BED_4 for the other three. Mirrored on right
    -- banks via flipped U (same technique used throughout this project).
    local bedAsset=g.id=="utility" and "CRU_BANK_BED_5" or "CRU_BANK_BED_4"
    local bedVisH=g.id=="utility" and 240 or 198
    local bankBed=bank:CreateTexture(nil,"BACKGROUND"); bankBed:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\"..bedAsset); bankBed:SetSize(394,bedVisH)
    bankBed:SetPoint(g.side=="left" and "BOTTOMLEFT" or "BOTTOMRIGHT",bank,g.side=="left" and "BOTTOMLEFT" or "BOTTOMRIGHT",g.side=="left" and 18 or -18,0)
    bankBed:SetTexCoord(g.side=="left" and 0 or 394/512, g.side=="left" and 394/512 or 0, 0, bedVisH/256)
    bankShade:Hide()
    -- Gate 2: cru-bank-support replaces backbone/cap/lock per bank. Reusable family:
    -- mirrored horizontally for right-side banks (Damage/Utility), and stretched to
    -- this bank's own height (246 or 288 for Utility) per the documented reusable-
    -- family contract -- one asset, four placements, not four separate files.
    local bankSupport=bank:CreateTexture(nil,"BACKGROUND")
    bankSupport:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_BANK_SUPPORT_L")
    bankSupport:SetSize(258,bank:GetHeight())
    bankSupport:SetPoint(g.side=="left" and "TOPLEFT" or "TOPRIGHT",bank,g.side=="left" and "TOPLEFT" or "TOPRIGHT",g.side=="left" and 5 or -5,0)
    bankSupport:SetTexCoord(g.side=="left" and 0 or 258/512, g.side=="left" and 258/512 or 0, 0, 288/512)
    local backbone=Solid(bank,"ARTWORK",MAT.ironLift); backbone:SetSize(13,bank:GetHeight()-24); backbone:SetPoint(g.side=="left" and "LEFT" or "RIGHT",bank,g.side=="left" and "LEFT" or "RIGHT",g.side=="left" and 5 or -5,-8)
    local cap=Solid(bank,"ARTWORK",MAT.iron); cap:SetSize(g.side=="left" and 258 or 224,8); cap:SetPoint(g.side=="left" and "TOPLEFT" or "TOPRIGHT",bank,g.side=="left" and "TOPLEFT" or "TOPRIGHT",g.side=="left" and 5 or -5,0)
    local lock=Solid(bank,"ARTWORK",MAT.bronzeRecess); lock:SetSize(68,12); lock:SetPoint(g.side=="left" and "TOPLEFT" or "TOPRIGHT",bank,g.side=="left" and "TOPLEFT" or "TOPRIGHT",g.side=="left" and 18 or -18,-2)
    local rail=Solid(bank,"OVERLAY",MAT.bronzeEdge); rail:SetSize(2,bank:GetHeight()-56); rail:SetPoint(g.side=="left" and "LEFT" or "RIGHT",bank,g.side=="left" and "LEFT" or "RIGHT",g.side=="left" and 26 or -26,-14); rail:SetAlpha(0.74)
    backbone:Hide(); cap:Hide(); lock:Hide(); rail:Hide()
    -- Level 2: cru-bank-header-cap terminates each bank's header rail. Small,
    -- mirrored on right banks via a flipped U range (same technique as the bank
    -- support). Explicit screen coordinates trusted directly per
    -- Crucible/CRUCIBLE-LEVEL2-PROVENANCE.md -- a purely decorative connector with
    -- no dynamic-correctness stakes.
    local headerCapXY={foundation={326,162},survival={326,501},damage={1328,162},utility={1328,462}}
    local hx,hy=headerCapXY[g.id][1],headerCapXY[g.id][2]
    local headerCap=frame:CreateTexture(nil,"BACKGROUND"); headerCap:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_BANK_HEADER_CAP"); headerCap:SetSize(36,14); headerCap:SetPoint("TOPLEFT",frame,"TOPLEFT",hx,-hy)
    headerCap:SetTexCoord(g.side=="left" and 0 or 36/64, g.side=="left" and 36/64 or 0, 0, 14/16)
    Label(bank,g.label,Theme.fonts.monument,14,Theme.colors.text,g.side=="left" and "TOPLEFT" or "TOPRIGHT",bank,g.side=="left" and "TOPLEFT" or "TOPRIGHT",g.side=="left" and 50 or -50,-15,210,g.side=="left" and "LEFT" or "RIGHT")
    Label(bank,"INDEPENDENT CHANNELS",Theme.fonts.readable,8,Theme.colors.disabled,g.side=="left" and "TOPLEFT" or "TOPRIGHT",bank,g.side=="left" and "TOPLEFT" or "TOPRIGHT",g.side=="left" and 50 or -50,-34,210,g.side=="left" and "LEFT" or "RIGHT")
    -- Level 2: deterministic channel-plate wear schedule (Manifest/LEVEL2-ASSET-
    -- MANIFEST.md). Pure material variation, verified against source row math with
    -- zero drift -- must never encode selected/rank/affordability state.
    local PLATE_SCHEDULE={foundation={"A","B","C","A"},survival={"B","C","A","B"},damage={"C","A","B","C"},utility={"A","C","B","A","C"}}
    for i,id in ipairs(g.categories) do
        local c=CreateChannel(bank,id,g.side); c.root:SetPoint("TOPLEFT",bank,"TOPLEFT",g.side=="left" and 30 or 26,-(48+(i-1)*45)); Screen.familyByCategory[id]=g.label; Screen.channels[id]=c; Screen.channelOrder[#Screen.channelOrder+1]=id
        local letter=PLATE_SCHEDULE[g.id][i]
        if letter then c.plate:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_CHANNEL_PLATE_"..letter) end
    end
end

-- Three stepped wells replace the old giant modal rectangle.
local chamber=CreateFrame("Frame",nil,frame); chamber:SetSize(632,704); chamber:SetPoint("TOP",frame,"TOP",0,-118); Screen.chamber=chamber
local shadow=Solid(chamber,"BACKGROUND",{0.002,0.003,0.004,0.94}); shadow:SetSize(598,670); shadow:SetPoint("CENTER",chamber,"CENTER",0,0)
-- Gate 1: cru-chamber-housing replaces the 12-piece structural scaffold below
-- (topMass..footR). BACKGROUND layer guarantees it renders under the ARTWORK-layer
-- native wells (upper/middle/lower) and labels regardless of creation order.
-- Gate 1 texture-compatibility repair: WoW 3.3.5's custom-texture path
-- requires power-of-two file canvases (every other custom TGA in this addon
-- already is; these were the only exception and rendered as black boxes).
-- File is padded to 1024x1024 with the original 632x704 art unscaled;
-- SetTexCoord crops back to the exact original pixel-visible region.
local chamberHousing=chamber:CreateTexture(nil,"BACKGROUND"); chamberHousing:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRUCIBLE_CENTER_CHAMBER_FRAME"); chamberHousing:SetAllPoints(chamber); chamberHousing:SetTexCoord(0,632/1024,0,704/1024)
local topMass=Solid(chamber,"ARTWORK",MAT.iron); topMass:SetSize(424,12); topMass:SetPoint("TOP",chamber,"TOP",-18,-8)
local topMassEdge=Solid(chamber,"OVERLAY",MAT.bronzeEdge); topMassEdge:SetSize(286,2); topMassEdge:SetPoint("CENTER",topMass,"CENTER",-11,0); topMassEdge:SetAlpha(0.66)
local topL=Solid(chamber,"ARTWORK",MAT.ironLift); topL:SetSize(82,34); topL:SetPoint("TOPLEFT",chamber,"TOPLEFT",16,-24)
local topLStep=Solid(chamber,"ARTWORK",MAT.bronzeRecess); topLStep:SetSize(46,13); topLStep:SetPoint("TOPLEFT",topL,"BOTTOMLEFT",19,0)
local topR=Solid(chamber,"ARTWORK",MAT.ironLift); topR:SetSize(104,26); topR:SetPoint("TOPRIGHT",chamber,"TOPRIGHT",-9,-36)
local topRStep=Solid(chamber,"ARTWORK",MAT.bronzeRecess); topRStep:SetSize(55,10); topRStep:SetPoint("TOPRIGHT",topR,"BOTTOMRIGHT",-13,0)
local retainL=Solid(chamber,"ARTWORK",MAT.ironLift); retainL:SetSize(17,492); retainL:SetPoint("LEFT",chamber,"LEFT",12,-7)
local retainLEdge=Solid(chamber,"OVERLAY",MAT.bronzeEdge); retainLEdge:SetSize(2,438); retainLEdge:SetPoint("CENTER",retainL,"CENTER",3,0); retainLEdge:SetAlpha(0.48)
local retainR=Solid(chamber,"ARTWORK",MAT.iron); retainR:SetSize(14,438); retainR:SetPoint("RIGHT",chamber,"RIGHT",-12,-18)
local retainREdge=Solid(chamber,"OVERLAY",MAT.bronzeEdge); retainREdge:SetSize(2,328); retainREdge:SetPoint("CENTER",retainR,"CENTER",-2,-12); retainREdge:SetAlpha(0.38)
-- Scaffold Eradication Sprint: cru-analysis-cavity replaces the flat `upper` fill
-- (plus upperEdge/truth/truthEdge below). Created before `upper` so the accepted
-- Level 2 upperRecess overlay (created after `upper`) stays layered on top unchanged.
local analysisCavity=chamber:CreateTexture(nil,"ARTWORK"); analysisCavity:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_ANALYSIS_CAVITY"); analysisCavity:SetPoint("TOP",chamber,"TOP",0,-70); analysisCavity:SetSize(526,184); analysisCavity:SetTexCoord(0,526/1024,0,184/256)
local upper=Solid(chamber,"ARTWORK",MAT.well); upper:SetSize(526,184); upper:SetPoint("TOP",chamber,"TOP",0,-70); Screen.upperWell=upper
-- True-final material resolve: cru-well-recess adds quiet forged-material detail on
-- top of the flat well fill (not a replacement -- the flat fill stays as a fallback
-- backdrop, matching the package's own prune list which does not name these wells).
-- Created after `upper` so same-layer creation order renders it on top.
local upperRecess=chamber:CreateTexture(nil,"ARTWORK"); upperRecess:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_WELL_RECESS_UPPER"); upperRecess:SetAllPoints(upper); upperRecess:SetTexCoord(0,526/1024,0,184/256)
local upperEdge=Solid(chamber,"OVERLAY",MAT.bronzeRecess); upperEdge:SetSize(474,2); upperEdge:SetPoint("TOP",upper,"TOP",0,0); upperEdge:SetAlpha(0.62)
upper:Hide(); upperEdge:Hide()
-- Scaffold Eradication Sprint: cru-projection-recess replaces `middle`/middleEdge.
local projectionRecess=chamber:CreateTexture(nil,"ARTWORK"); projectionRecess:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_PROJECTION_RECESS"); projectionRecess:SetPoint("TOP",upper,"BOTTOM",0,-12); projectionRecess:SetSize(556,170); projectionRecess:SetTexCoord(0,556/1024,0,170/256)
local middle=Solid(chamber,"ARTWORK",{0.025,0.014,0.010,0.98}); middle:SetSize(556,170); middle:SetPoint("TOP",upper,"BOTTOM",0,-12); Screen.middleWell=middle
local middleRecess=chamber:CreateTexture(nil,"ARTWORK"); middleRecess:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_WELL_RECESS_MIDDLE"); middleRecess:SetAllPoints(middle); middleRecess:SetTexCoord(0,556/1024,0,170/256)
local middleEdge=Solid(chamber,"OVERLAY",MAT.bronzeEdge); middleEdge:SetSize(456,2); middleEdge:SetPoint("TOP",middle,"TOP",11,0); middleEdge:SetAlpha(0.38)
middle:Hide(); middleEdge:Hide()
-- Scaffold Eradication Sprint: cru-actuation-bay replaces `lower`/lowerEdge as a
-- deep base layer. Accepted reservoir/regulator/feed-tick-rail/machine-joint art
-- (Gate 1/2/Level 2) are NOT fully contained within this bay's bounds (feed-
-- regulator and feed-tick-rail both extend ~30px past its right edge) and are
-- explicitly preserved unchanged per the additive-stack addendum.
local actuationBay=chamber:CreateTexture(nil,"ARTWORK"); actuationBay:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_ACTUATION_BAY"); actuationBay:SetPoint("TOP",middle,"BOTTOM",0,-12); actuationBay:SetSize(520,213); actuationBay:SetTexCoord(0,520/1024,0,213/256)
local lower=Solid(chamber,"ARTWORK",{0.013,0.012,0.012,0.98}); lower:SetSize(520,213); lower:SetPoint("TOP",middle,"BOTTOM",0,-12); Screen.lowerWell=lower
local lowerRecess=chamber:CreateTexture(nil,"ARTWORK"); lowerRecess:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_WELL_RECESS_LOWER"); lowerRecess:SetAllPoints(lower); lowerRecess:SetTexCoord(0,520/1024,0,213/256)
local lowerEdge=Solid(chamber,"OVERLAY",MAT.bronzeRecess); lowerEdge:SetSize(392,2); lowerEdge:SetPoint("TOP",lower,"TOP",-18,0); lowerEdge:SetAlpha(0.48)
lower:Hide(); lowerEdge:Hide(); shadow:Hide()
local footL=Solid(chamber,"ARTWORK",MAT.iron); footL:SetSize(116,14); footL:SetPoint("BOTTOMLEFT",chamber,"BOTTOMLEFT",15,3)
local footR=Solid(chamber,"ARTWORK",MAT.ironLift); footR:SetSize(142,11); footR:SetPoint("BOTTOMRIGHT",chamber,"BOTTOMRIGHT",-10,3)
-- Gate 1: exact documented scaffold group replaced by chamberHousing above. Hidden
-- (not deleted) so it can be restored instantly if the asset needs to be pulled.
for _,piece in ipairs({topMass,topMassEdge,topL,topLStep,topR,topRStep,retainL,retainLEdge,retainR,retainREdge,footL,footR}) do piece:Hide() end
-- Level 2: cru-perimeter-retention-seam, 3 instances in low-information perimeter
-- zones per Crucible/CRUCIBLE-LEVEL2-PROVENANCE.md -- one normal, one mirrored
-- (flipped U), one rotated 90 degrees.
local seamA=frame:CreateTexture(nil,"BACKGROUND"); seamA:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_PERIMETER_RETENTION_SEAM"); seamA:SetSize(90,18); seamA:SetPoint("TOPLEFT",frame,"TOPLEFT",650,-786); seamA:SetTexCoord(0,90/128,0,18/32)
local seamB=frame:CreateTexture(nil,"BACKGROUND"); seamB:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_PERIMETER_RETENTION_SEAM"); seamB:SetSize(90,18); seamB:SetPoint("TOPLEFT",frame,"TOPLEFT",932,-786); seamB:SetTexCoord(90/128,0,0,18/32)
local seamC=frame:CreateTexture(nil,"BACKGROUND"); seamC:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_PERIMETER_RETENTION_SEAM"); seamC:SetSize(90,18); seamC:SetPoint("CENTER",frame,"TOPLEFT",531+45,-(488+9)); seamC:SetTexCoord(0,90/128,0,18/32); seamC:SetRotation(math.rad(90))
local ingress=Solid(chamber,"OVERLAY",Theme.colors.worldsoul); ingress:SetSize(5,74); ingress:SetPoint("TOP",chamber,"TOP",-95,-10); ingress:SetAlpha(0.74)
local ingressCap=Solid(chamber,"OVERLAY",Theme.colors.worldsoulPale); ingressCap:SetSize(25,4); ingressCap:SetPoint("TOP",ingress,"TOP",0,0); ingressCap:SetAlpha(0.58)
local heatL=Solid(chamber,"OVERLAY",{1.00,0.25,0.07,1}); heatL:SetSize(5,132); heatL:SetPoint("LEFT",middle,"LEFT",0,0); heatL:SetAlpha(0.34)
local heatR=Solid(chamber,"OVERLAY",{1.00,0.37,0.10,1}); heatR:SetSize(4,94); heatR:SetPoint("RIGHT",middle,"RIGHT",0,-8); heatR:SetAlpha(0.18)
Screen.heat=Solid(chamber,"OVERLAY",{1.00,0.23,0.05,1}); Screen.heat:SetSize(328,38); Screen.heat:SetPoint("BOTTOM",lower,"BOTTOM",0,16); Screen.heat:SetAlpha(0.07)
Screen.selectedJoint=CreateFrame("Frame",nil,chamber); Screen.selectedJoint:SetSize(29,74)
local jointMass=Solid(Screen.selectedJoint,"OVERLAY",MAT.ironLift); jointMass:SetAllPoints(Screen.selectedJoint)
-- True-final material resolve: cru-machine-joint (selected-channel socket variant).
-- DEVIATION FROM PACKAGE: the package specifies a fixed logical placement (554,205),
-- but Screen.selectedJoint is a dynamic frame that Screen:SeatSelectedJoint() moves
-- between the left and right bank sides depending on the selected category -- a
-- fixed coordinate would only be correctly positioned for one specific category and
-- would visually detach for every other selection. Parented directly to
-- Screen.selectedJoint via SetPoint CENTER/CENTER instead, so it tracks automatically
-- (same principle as the Gate 1 World Threat gate-mass fix). Reported in the Gate 3
-- integration notes, not silently absorbed.
-- ALSO: created on the OVERLAY layer, after jointMass but before jointSeat, so it
-- sits above jointMass's flat fallback fill (same-layer creation order) while
-- jointSeat and selectedJointHeat -- both genuinely dynamic (selectedJointHeat's
-- alpha is driven by Screen:WakeCommittedChannel) -- still render above it, exactly
-- as the mission's "dynamic state wins over static provenance" law requires.
-- Level 2: CRU_MACHINE_JOINT updated to 24x54 visible / 32x64 POT (down from the
-- Gate 3 34x74/64x128 spec) per Manifest/LEVEL2-MATERIAL-CHANGE-LEDGER.md.
local jointSocket=Screen.selectedJoint:CreateTexture(nil,"OVERLAY"); jointSocket:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_MACHINE_JOINT"); jointSocket:SetSize(24,54); jointSocket:SetPoint("CENTER",Screen.selectedJoint,"CENTER",0,0); jointSocket:SetTexCoord(0,24/32,0,54/64)
local jointSeat=Solid(Screen.selectedJoint,"OVERLAY",MAT.bronzeRecess); jointSeat:SetSize(13,62); jointSeat:SetPoint("CENTER",Screen.selectedJoint,"CENTER",0,0)
Screen.selectedJointHeat=Solid(Screen.selectedJoint,"OVERLAY",{1.00,0.32,0.08,1}); Screen.selectedJointHeat:SetSize(6,54); Screen.selectedJointHeat:SetPoint("CENTER",Screen.selectedJoint,"CENTER",0,0); Screen.selectedJointHeat:SetAlpha(0.66)

Screen.categoryFamily=Label(chamber,"FOUNDATION CHANNEL",Theme.fonts.readable,9,Theme.colors.textMuted,"TOPLEFT",upper,"TOPLEFT",26,-19)
Screen.categoryName=Label(chamber,"LIFE LEECH",Theme.fonts.monument,29,Theme.colors.text,"TOPLEFT",upper,"TOPLEFT",24,-40,478)
Screen.categoryDesc=Label(chamber,"",Theme.fonts.readable,11,Theme.colors.textMuted,"TOPLEFT",upper,"TOPLEFT",25,-82,476); Screen.categoryDesc:SetHeight(34)
local truth=Solid(chamber,"OVERLAY",MAT.bronzeRecess); truth:SetSize(474,22); truth:SetPoint("TOP",upper,"TOP",0,-126); truth:SetAlpha(0.62)
local truthEdge=Solid(chamber,"OVERLAY",MAT.bronzeEdge); truthEdge:SetSize(418,1); truthEdge:SetPoint("BOTTOM",truth,"BOTTOM",0,0); truthEdge:SetAlpha(0.54)
truth:Hide(); truthEdge:Hide()
Label(chamber,"PERMANENT  ·  ACCOUNT-WIDE  ·  DIMINISHING RETURNS",Theme.fonts.readable,8,Theme.colors.textMuted,"CENTER",truth,"CENTER",0,0)
for _,d in ipairs({{"ESSENCE FED",27},{"CURRENT EFFECT",196},{"CEILING",390}}) do Label(chamber,d[1],Theme.fonts.readable,9,Theme.colors.textMuted,"TOPLEFT",upper,"TOPLEFT",d[2],-151) end
Screen.investedValue=Label(chamber,"—",Theme.fonts.monument,20,Theme.colors.text,"TOPLEFT",upper,"TOPLEFT",26,-169)
Screen.effectValue=Label(chamber,"—",Theme.fonts.monument,20,Theme.colors.text,"TOPLEFT",upper,"TOPLEFT",195,-169)
Screen.ceilingValue=Label(chamber,"—",Theme.fonts.monument,18,Theme.colors.textMuted,"TOPLEFT",upper,"TOPLEFT",389,-171)

Label(chamber,"PROJECTED EFFECT",Theme.fonts.readable,9,Theme.colors.textMuted,"TOPLEFT",middle,"TOPLEFT",27,-17)
-- Scaffold Eradication Sprint: cru-projection-readout-cradle unions currentSeat +
-- projectedSeat + transformBed. Native currentSeat/projectedSeat/transformBed are
-- purely static (no dynamic reference elsewhere) -- safe to hide. Verified against
-- source: cradle bounds (582,414)-(1090,526) fully encompass both seats.
local readoutCradle=chamber:CreateTexture(nil,"ARTWORK"); readoutCradle:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_PROJECTION_READOUT_CRADLE"); readoutCradle:SetPoint("TOPLEFT",chamber,"TOPLEFT",582,-414); readoutCradle:SetSize(508,112); readoutCradle:SetTexCoord(0,508/512,0,112/128)
local currentSeat=Solid(chamber,"OVERLAY",{0.013,0.012,0.012,0.98}); currentSeat:SetSize(172,86); currentSeat:SetPoint("TOPLEFT",middle,"TOPLEFT",24,-43)
local projectedSeat=Solid(chamber,"OVERLAY",{0.060,0.024,0.012,0.98}); projectedSeat:SetSize(210,100); projectedSeat:SetPoint("TOPRIGHT",middle,"TOPRIGHT",-24,-36)
local transformBed=Solid(chamber,"OVERLAY",MAT.bronzeRecess); transformBed:SetSize(116,8); transformBed:SetPoint("LEFT",currentSeat,"RIGHT",8,0); transformBed:SetAlpha(0.88)
currentSeat:Hide(); projectedSeat:Hide(); transformBed:Hide()
local transform=Solid(chamber,"OVERLAY",{1.00,0.31,0.08,1}); transform:SetSize(104,2); transform:SetPoint("CENTER",transformBed,"CENTER",0,0); transform:SetAlpha(0.68)
Screen.previewCurrent=Label(chamber,"—",Theme.fonts.monument,24,Theme.colors.textMuted,"CENTER",currentSeat,"CENTER",0,5); Label(chamber,"CURRENT",Theme.fonts.readable,8,Theme.colors.disabled,"BOTTOM",currentSeat,"BOTTOM",0,11)
Screen.previewArrow=Label(chamber,"›",Theme.fonts.monument,28,{1.00,0.42,0.15,1},"CENTER",transform,"CENTER",0,1)
Screen.previewProjected=Label(chamber,"—",Theme.fonts.monument,31,{1.00,0.67,0.31,1},"CENTER",projectedSeat,"CENTER",0,7); Label(chamber,"AFTER FORGE",Theme.fonts.readable,8,Theme.colors.textMuted,"BOTTOM",projectedSeat,"BOTTOM",0,12)
Screen.previewDelta=Label(chamber,"Choose a calibrated feed amount",Theme.fonts.readable,9,Theme.colors.textMuted,"BOTTOMRIGHT",middle,"BOTTOMRIGHT",-26,14,470,"RIGHT")

Label(chamber,"ESSENCE FEED",Theme.fonts.readable,9,Theme.colors.textMuted,"TOPLEFT",lower,"TOPLEFT",26,-17)
local reservoir=CreateFrame("Frame",nil,chamber); reservoir:SetSize(142,118); reservoir:SetPoint("TOPLEFT",lower,"TOPLEFT",24,-40); Screen.reservoir=reservoir
-- Gate 2: cru-essence-reservoir replaces reservoirMass. POT 256x128, visible 142x118.
local reservoirArt=reservoir:CreateTexture(nil,"BACKGROUND"); reservoirArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_ESSENCE_RESERVOIR"); reservoirArt:SetAllPoints(reservoir); reservoirArt:SetTexCoord(0,142/256,0,118/128)
local reservoirMass=Solid(reservoir,"ARTWORK",MAT.ironLift); reservoirMass:SetAllPoints(reservoir); reservoirMass:Hide()
local reservoirWell=Solid(reservoir,"ARTWORK",{0.008,0.027,0.040,0.98}); reservoirWell:SetSize(108,78); reservoirWell:SetPoint("CENTER",reservoir,"CENTER",0,5)
local reservoirLip=Solid(reservoir,"OVERLAY",MAT.bronzeEdge); reservoirLip:SetSize(84,2); reservoirLip:SetPoint("TOP",reservoirWell,"TOP",6,0); reservoirLip:SetAlpha(0.42)
Screen.reservoirGlow=Solid(reservoir,"OVERLAY",Theme.colors.worldsoul); Screen.reservoirGlow:SetSize(6,58); Screen.reservoirGlow:SetPoint("LEFT",reservoirWell,"LEFT",8,0); Screen.reservoirGlow:SetAlpha(0.70)
Label(reservoir,"AVAILABLE",Theme.fonts.readable,8,Theme.colors.textMuted,"TOPLEFT",reservoirWell,"TOPLEFT",23,-13); Screen.essenceValue=Label(reservoir,"—",Theme.fonts.monument,20,Theme.colors.worldsoulPale,"TOPLEFT",reservoirWell,"TOPLEFT",21,-34,78); Label(reservoir,"ESSENCE",Theme.fonts.readable,8,Theme.colors.disabled,"BOTTOMLEFT",reservoirWell,"BOTTOMLEFT",22,11)
local neck=Solid(chamber,"OVERLAY",Theme.colors.worldsoul); neck:SetSize(44,4); neck:SetPoint("LEFT",reservoir,"RIGHT",0,2); neck:SetAlpha(0.54)
local regulator=CreateFrame("Frame",nil,chamber); regulator:SetSize(340,118); regulator:SetPoint("TOPLEFT",reservoir,"TOPRIGHT",44,0); Screen.regulator=regulator
-- Gate 2: cru-feed-regulator replaces neck + regulatorSpine/regulatorChannel as one
-- continuous 384x118 housing spanning from the reservoir's right edge (covering the
-- 44px neck gap) through to the regulator's own right edge -- POT 512x128.
local regulatorArt=chamber:CreateTexture(nil,"BACKGROUND"); regulatorArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_FEED_REGULATOR"); regulatorArt:SetSize(384,118); regulatorArt:SetPoint("TOPLEFT",reservoir,"TOPRIGHT",0,0); regulatorArt:SetTexCoord(0,384/512,0,118/128)
local regulatorSpine=Solid(regulator,"ARTWORK",MAT.iron); regulatorSpine:SetSize(326,12); regulatorSpine:SetPoint("CENTER",regulator,"CENTER",0,0)
local regulatorChannel=Solid(regulator,"OVERLAY",MAT.bronzeEdge); regulatorChannel:SetSize(286,3); regulatorChannel:SetPoint("CENTER",regulatorSpine,"CENTER",0,0); regulatorChannel:SetAlpha(0.78)
neck:Hide(); regulatorSpine:Hide(); regulatorChannel:Hide()
Screen.amounts={}; local AMOUNTS={1000,5000,10000,50000,100000}
for i,a in ipairs(AMOUNTS) do
    local c={id="amount"..a,amount=a,enabled=true,focused=false,hovered=false,selected=false,affordable=true}; local root=CreateFrame("Button","EchoesUICrucibleAmount"..a,regulator); root:SetSize(60,78); root:SetPoint("LEFT",regulator,"LEFT",5+(i-1)*68,0); root:RegisterForClicks("LeftButtonUp"); root:EnableMouse(true); c.root=root
    c.stem=Solid(root,"ARTWORK",MAT.ironLift); c.stem:SetSize(8,42); c.stem:SetPoint("CENTER",root,"CENTER",0,0)
    c.seat=Solid(root,"ARTWORK",{0.021,0.017,0.014,1}); c.seat:SetSize(52,35); c.seat:SetPoint("CENTER",root,"CENTER",0,0)
    c.notch=Solid(root,"OVERLAY",{1.00,0.32,0.09,1}); c.notch:SetSize(30,5); c.notch:SetPoint("BOTTOM",c.seat,"BOTTOM",0,-1); c.notch:SetAlpha(0)
    c.lock=Solid(root,"OVERLAY",Theme.colors.disabled); c.lock:SetSize(38,3); c.lock:SetPoint("CENTER",c.seat,"CENTER",0,0); c.lock:SetAlpha(0)
    c.focusA=Solid(root,"OVERLAY",Theme.colors.text); c.focusA:SetSize(9,2); c.focusA:SetPoint("TOPLEFT",c.seat,"TOPLEFT",2,-2); c.focusA:SetAlpha(0)
    c.focusB=Solid(root,"OVERLAY",Theme.colors.text); c.focusB:SetSize(9,2); c.focusB:SetPoint("BOTTOMRIGHT",c.seat,"BOTTOMRIGHT",-2,2); c.focusB:SetAlpha(0)
    c.label=Label(root,(a/1000).."K",Theme.fonts.monument,13,Theme.colors.textMuted,"CENTER",c.seat,"CENTER",0,1)
    function c:Refresh() local awake=self.focused or self.hovered; self.notch:SetAlpha(self.selected and 0.94 or (self.focused and 0.45 or (self.hovered and 0.22 or 0))); self.lock:SetAlpha(self.affordable and 0 or 0.72); self.focusA:SetAlpha(self.focused and 0.88 or 0); self.focusB:SetAlpha(self.focused and 0.88 or 0); self.seat:SetAlpha(self.selected and 1 or (self.affordable and (awake and 0.86 or 0.74) or 0.38)); self.stem:SetAlpha(self.selected and 0.92 or (awake and 0.68 or 0.54)); self.label:SetTextColor(unpack(self.selected and {1.00,0.70,0.36,1} or (self.affordable and Theme.colors.text or Theme.colors.disabled))) end
    function c:SetFocused(v) self.focused=v==true; self:Refresh() end; function c:SetEnabled(v) self.enabled=v~=false; root:EnableMouse(self.enabled); self:Refresh() end; function c:SetAffordable(v) self.affordable=v==true; self:Refresh() end
    function c:Activate() if not self.enabled then return false end; Screen:SetAmount(self.amount); return true end
    root:SetScript("OnEnter",function() c.hovered=true; c:Refresh() end); root:SetScript("OnLeave",function() c.hovered=false; c:Refresh() end)
    root:SetScript("OnMouseDown",function(_,b) if b=="LeftButton" then c.seat:ClearAllPoints(); c.seat:SetPoint("CENTER",root,"CENTER",0,-2) end end); root:SetScript("OnMouseUp",function(_,b) c.seat:ClearAllPoints(); c.seat:SetPoint("CENTER",root,"CENTER",0,0); if b=="LeftButton" then c:Activate() end end); c:Refresh(); Screen.amounts[a]=c
end
-- True-final material resolve: cru-feed-tick-rail seats the five native amount
-- controls. `regulator` is a static frame (not dynamic), so an absolute canvas
-- coordinate is safe here, matching the package's own placement exactly.
local feedTickRail=frame:CreateTexture(nil,"BACKGROUND"); feedTickRail:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_FEED_TICK_RAIL"); feedTickRail:SetSize(350,22); feedTickRail:SetPoint("TOPLEFT",frame,"TOPLEFT",780,-668); feedTickRail:SetTexCoord(0,350/512,0,22/32)

-- Terminal actuator: a contained press between two retaining clamps.
local actuator=CreateFrame("Frame",nil,chamber); actuator:SetSize(454,90); actuator:SetPoint("BOTTOM",lower,"BOTTOM",0,9); Screen.actuator=actuator
local actuatorBed=Solid(actuator,"ARTWORK",MAT.iron); actuatorBed:SetSize(384,18); actuatorBed:SetPoint("CENTER",actuator,"CENTER",0,0)
local actuatorBedEdge=Solid(actuator,"OVERLAY",MAT.bronzeEdge); actuatorBedEdge:SetSize(302,2); actuatorBedEdge:SetPoint("CENTER",actuatorBed,"CENTER",0,0); actuatorBedEdge:SetAlpha(0.44)
local actuatorL=Solid(actuator,"ARTWORK",MAT.ironLift); actuatorL:SetSize(66,48); actuatorL:SetPoint("LEFT",actuator,"LEFT",12,0)
local actuatorR=Solid(actuator,"ARTWORK",MAT.ironLift); actuatorR:SetSize(78,42); actuatorR:SetPoint("RIGHT",actuator,"RIGHT",-8,2)
-- Gate 2: removed as redundant (LEVEL-1-PRUNE-LIST.md) -- the accepted chamber V3's
-- lower terminus already visually supplies this housing. The Forge button itself
-- (forge.root and its children, created below) is untouched.
actuatorBed:Hide(); actuatorBedEdge:Hide(); actuatorL:Hide(); actuatorR:Hide()
-- Level 2: cru-forge-heat-wear localizes age at the working terminus. Explicitly
-- never tinted as readiness -- Screen.heat/forge.heat alone carry that state, per
-- Crucible/CRUCIBLE-LEVEL2-PROVENANCE.md's own safe-native-state note.
local forgeHeatWear=frame:CreateTexture(nil,"BACKGROUND"); forgeHeatWear:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_FORGE_HEAT_WEAR"); forgeHeatWear:SetSize(160,24); forgeHeatWear:SetPoint("TOPLEFT",frame,"TOPLEFT",756,-752); forgeHeatWear:SetTexCoord(0,160/256,0,24/32)
-- Level 2: cru-machine-joint reused rotated as two Forge junction clips, per
-- Crucible/CRUCIBLE-LEVEL2-PROVENANCE.md -- updated to the 24x54/32x64 spec,
-- displayed at 46x24 rotated. The right instance is additionally mirrored
-- ("rotated+mirrored") via a flipped U range, matching the physical connection
-- direction on each side of the Forge button. Parented to `frame` (not
-- `actuator`/forge.root) so they render below forge.root's own higher frame level
-- wherever they overlap it. Rotation direction has not been confirmed live.
local forgeJointL=frame:CreateTexture(nil,"BACKGROUND"); forgeJointL:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_MACHINE_JOINT"); forgeJointL:SetSize(24,54); forgeJointL:SetPoint("CENTER",frame,"TOPLEFT",676+23,-(716+12)); forgeJointL:SetTexCoord(0,24/32,0,54/64); forgeJointL:SetRotation(math.rad(90))
local forgeJointR=frame:CreateTexture(nil,"BACKGROUND"); forgeJointR:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_MACHINE_JOINT"); forgeJointR:SetSize(24,54); forgeJointR:SetPoint("CENTER",frame,"TOPLEFT",950+23,-(716+12)); forgeJointR:SetTexCoord(24/32,0,0,54/64); forgeJointR:SetRotation(math.rad(90))
local forge={id="forge",enabled=false,focused=false,hovered=false,pending=false,root=CreateFrame("Button","EchoesUICrucibleForge",actuator)}; Screen.forge=forge
forge.root:SetSize(286,68); forge.root:SetPoint("CENTER",actuator,"CENTER",0,0); forge.root:RegisterForClicks("LeftButtonUp"); forge.root:EnableMouse(false)
-- Scaffold Eradication Sprint: cru-forge-actuator-face. DEVIATION FROM PACKAGE: the
-- package says to zero forge.seat/forge.inner's alpha, but both are genuinely
-- dynamic native state (forge.seat's alpha is driven by forge:Refresh() for pending/
-- enabled/awake; forge.inner's position shifts on click for press feedback) -- not
-- pure scaffold. Kept both fully native and layered the new face BEHIND them
-- (created first, same ARTWORK layer, so same-layer creation order puts it below).
forge.face=Solid(forge.root,"ARTWORK",{1,1,1,1}); forge.face:SetAllPoints(forge.root); forge.face:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\CRU_FORGE_ACTUATOR_FACE"); forge.face:SetTexCoord(0,286/512,0,68/128)
forge.seat=Solid(forge.root,"ARTWORK",{0.050,0.020,0.011,0.99}); forge.seat:SetAllPoints(forge.root); forge.inner=Solid(forge.root,"ARTWORK",{0.015,0.014,0.014,0.98}); forge.inner:SetSize(250,46); forge.inner:SetPoint("CENTER",forge.root,"CENTER",0,0)
forge.heat=Solid(forge.root,"OVERLAY",{1.00,0.28,0.07,1}); forge.heat:SetSize(5,46); forge.heat:SetPoint("LEFT",forge.inner,"LEFT",0,0)
forge.focusA=Solid(forge.root,"OVERLAY",Theme.colors.text); forge.focusA:SetSize(26,3); forge.focusA:SetPoint("TOPLEFT",forge.inner,"TOPLEFT",5,-4); forge.focusA:SetAlpha(0)
forge.focusB=Solid(forge.root,"OVERLAY",Theme.colors.text); forge.focusB:SetSize(26,3); forge.focusB:SetPoint("BOTTOMRIGHT",forge.inner,"BOTTOMRIGHT",-5,4); forge.focusB:SetAlpha(0)
forge.label=Label(forge.root,"FORGE",Theme.fonts.monument,18,Theme.colors.text,"LEFT",forge.inner,"LEFT",19,6); forge.value=Label(forge.root,"1,000",Theme.fonts.monument,15,{1.00,0.66,0.31,1},"RIGHT",forge.inner,"RIGHT",-18,6,88,"RIGHT"); forge.meta=Label(forge.root,"1:1 ESSENCE  ·  PERMANENT  ·  NO REFUND",Theme.fonts.readable,8,Theme.colors.textMuted,"BOTTOM",forge.inner,"BOTTOM",0,8,228,"CENTER")
function forge:Refresh() local awake=self.focused or self.hovered; self.focusA:SetAlpha(self.focused and 0.90 or 0); self.focusB:SetAlpha(self.focused and 0.90 or 0); self.seat:SetAlpha(self.pending and 1 or (self.enabled and (awake and 1 or 0.82) or 0.42)); self.heat:SetAlpha(self.pending and 0.94 or (self.enabled and (awake and 0.70 or 0.40) or 0.12)); self.label:SetTextColor(unpack(self.enabled and Theme.colors.text or Theme.colors.disabled)); self.value:SetTextColor(unpack(self.enabled and {1.00,0.66,0.31,1} or Theme.colors.disabled)) end
function forge:SetFocused(v) self.focused=v==true; self:Refresh() end; function forge:SetEnabled(v) self.enabled=v==true; self.root:EnableMouse(self.enabled and not self.pending); self:Refresh() end; function forge:SetPending(v) self.pending=v==true; self.root:EnableMouse(self.enabled and not self.pending); self:Refresh() end
function forge:Activate(source) if not self.enabled or self.pending then return false end; return Screen:Forge(source) end
forge.root:SetScript("OnEnter",function() forge.hovered=true; forge:Refresh() end); forge.root:SetScript("OnLeave",function() forge.hovered=false; forge:Refresh() end); forge.root:SetScript("OnMouseDown",function(_,b) if b=="LeftButton" then forge.inner:ClearAllPoints(); forge.inner:SetPoint("CENTER",forge.root,"CENTER",0,-2) end end); forge.root:SetScript("OnMouseUp",function(_,b) forge.inner:ClearAllPoints(); forge.inner:SetPoint("CENTER",forge.root,"CENTER",0,0); if b=="LeftButton" then forge:Activate("mouse") end end); forge:Refresh()

Screen.status=Label(chamber,"",Theme.fonts.readable,9,Theme.colors.textMuted,"BOTTOM",chamber,"BOTTOM",0,43,500,"CENTER")
Screen.total=Label(frame,"TOTAL PERMANENT INVESTMENT  —  ·  SECONDARY VISAGE RESPONDS TO THIS TOTAL",Theme.fonts.readable,8,Theme.colors.textMuted,"BOTTOM",frame,"BOTTOM",0,42,760,"CENTER")
Label(frame,"SEVENTEEN INDEPENDENT CHANNELS  ·  ONE PERMANENT CRUCIBLE",Theme.fonts.readable,8,Theme.colors.disabled,"BOTTOM",frame,"BOTTOM",0,22,720,"CENTER")

local input=UI.InputManager:New(frame); Screen.input=input
for _,c in ipairs({Screen.back,Screen.home,Screen.close}) do input:Add(c,c.id) end; for _,id in ipairs(Screen.channelOrder) do input:Add(Screen.channels[id],id) end; for _,a in ipairs(AMOUNTS) do input:Add(Screen.amounts[a],"amount"..a) end; input:Add(forge,"forge")
local ordered={"back","home","close"}; for _,id in ipairs(Screen.channelOrder) do ordered[#ordered+1]=id end; for _,a in ipairs(AMOUNTS) do ordered[#ordered+1]="amount"..a end; ordered[#ordered+1]="forge"
local nav={back={RIGHT="life_leech",DOWN="life_leech"},home={LEFT="back",RIGHT="close",DOWN="crit_rating"},close={LEFT="home",DOWN="crit_rating"},forge={UP="amount10000",LEFT="reflect_chance",RIGHT="attunement_echo"}}
for _,g in ipairs(GROUPS) do for i,id in ipairs(g.categories) do nav[id]={}; nav[id].UP=g.categories[i-1] or (g.id=="foundation" and "back" or (g.id=="damage" and "home" or (g.id=="survival" and "spell_power" or "execute_power"))); nav[id].DOWN=g.categories[i+1] or (g.id=="foundation" and "spell_mitigation" or (g.id=="damage" and "cooldown_reduction" or "forge")); nav[id][g.side=="left" and "RIGHT" or "LEFT"]="amount10000" end end
for i,a in ipairs(AMOUNTS) do local id="amount"..a; nav[id]={LEFT=i>1 and ("amount"..AMOUNTS[i-1]) or "life_leech",RIGHT=i<#AMOUNTS and ("amount"..AMOUNTS[i+1]) or "crit_rating",UP="life_leech",DOWN="forge"} end
input:SetNavigation(ordered,nav); input.defaultFocusId="life_leech"; input.onEscape=function() Screen:Leave("back") end

function Screen:PreviewKey() return self.selected..":"..self.amount end
function Screen:SeatSelectedJoint(id)
    local side="left"; for _,g in ipairs(GROUPS) do for _,cat in ipairs(g.categories) do if cat==id then side=g.side end end end; self.selectedJoint:ClearAllPoints()
    if side=="left" then self.selectedJoint:SetPoint("LEFT",self.upperWell,"LEFT",-18,-18) else self.selectedJoint:SetPoint("RIGHT",self.upperWell,"RIGHT",18,-18) end
end
function Screen:UpdatePreview()
    local p=self.previewCache[self:PreviewKey()]; if not p then self.previewCurrent:SetText(Pct(self.effects and self.effects[self.selected])); self.previewProjected:SetText("READING"); self.previewDelta:SetText(self.previewPending and "The chamber is calculating…" or "Choose a calibrated feed amount"); return end
    self.previewCurrent:SetText(Pct(p.current_effect_pct)); self.previewProjected:SetText(Pct(p.projected_effect_pct)); local delta=(tonumber(p.projected_effect_pct) or 0)-(tonumber(p.current_effect_pct) or 0); self.previewDelta:SetText("+"..string.format("%.4f",delta).."%  ·  "..FormatInt(p.projected_invested).." total fed")
end
function Screen:RequestPreview()
    if not self.active or self.investPending then return end; local key=self:PreviewKey(); self.desiredPreviewKey=key; if self.previewCache[key] then self:UpdatePreview(); self:RefreshForge(); return end; if self.previewPending then return end
    local elapsed=GetTime()-(self.lastPreviewSent or -10); local delay=math.max(0,1.05-elapsed); self.previewPending=true; self.previewToken=(self.previewToken or 0)+1; local token=self.previewToken; self:UpdatePreview(); self:RefreshForge()
    local function send() if not Screen.active or Screen.previewToken~=token then return end; Screen.lastPreviewSent=GetTime(); if not (APB and APB.RequestEchoesAction and APB:RequestEchoesAction("crucible_preview",Screen.selected,Screen.amount)) then Screen.previewPending=false; Screen.status:SetText("Preview unavailable; the gossip Crucible remains available."); Screen:RefreshForge() end end
    if delay>0 then C_Timer.After(delay,send) else send() end
end
function Screen:RefreshForge()
    local essence=tonumber(self.essence) or 0; local status=self.statuses and self.statuses[self.selected] or "UNAVAILABLE"; local p=self.previewCache[self:PreviewKey()]; local enabled=self.active and not self.investPending and status=="AVAILABLE" and essence>=self.amount and p~=nil
    self.forge:SetEnabled(enabled); self.forge.value:SetText(FormatInt(self.amount)); for value,c in pairs(self.amounts) do c:SetAffordable(essence>=value) end
    if self.investPending then self.forge:SetPending(true); self.forge.label:SetText("FORGING…"); self.forge.meta:SetText("THE CHAMBER IS COMMITTING")
    elseif status=="MAXED" then self.forge:SetPending(false); self.forge.label:SetText("AT CEILING"); self.forge.meta:SetText("THIS CHANNEL IS FULLY SETTLED")
    elseif essence<self.amount then self.forge:SetPending(false); self.forge.label:SetText("FORGE"); self.forge.meta:SetText("NEED "..FormatInt(self.amount-essence).." MORE ESSENCE")
    elseif self.previewPending and not p then self.forge:SetPending(false); self.forge.label:SetText("FORGE"); self.forge.meta:SetText("CALCULATING PROJECTED EFFECT")
    elseif not p then self.forge:SetPending(false); self.forge.label:SetText("FORGE"); self.forge.meta:SetText("PREVIEW REQUIRED")
    else self.forge:SetPending(false); self.forge.label:SetText("FORGE"); self.forge.meta:SetText("1:1 ESSENCE  ·  PERMANENT  ·  NO REFUND") end
end
function Screen:SelectCategory(id)
    if not META[id] then return end; local alreadySelected=self.selected==id; self.selected=id; for key,c in pairs(self.channels) do c:SetSelected(key==id) end; self:SeatSelectedJoint(id); self.categoryFamily:SetText((self.familyByCategory[id] or "").." CHANNEL"); self.categoryName:SetText(string.upper(META[id].label)); self.categoryDesc:SetText(META[id].desc)
    self.investedValue:SetText(FormatInt(self.investments and self.investments[id] or 0)); self.effectValue:SetText(Pct(self.effects and self.effects[id])); self.ceilingValue:SetText(Pct(self.ceilings and self.ceilings[id])); self.status:SetText(alreadySelected and "This Crucible channel is already selected." or ""); self.previewPending=false; self.previewToken=(self.previewToken or 0)+1; self:UpdatePreview(); self:RefreshForge(); self:RequestPreview()
end
function Screen:SetAmount(amount) local alreadySelected=self.amount==amount; self.amount=amount; for value,c in pairs(self.amounts) do c.selected=value==amount; c:Refresh() end; self.status:SetText(alreadySelected and "This investment amount is already selected." or ""); self.previewPending=false; self.previewToken=(self.previewToken or 0)+1; self:UpdatePreview(); self:RefreshForge(); self:RequestPreview() end
function Screen:RefreshState(values)
    self.essence=tonumber(values.essence) or 0; self.investments=ParseMap(values.crucible); self.statuses=ParseMap(values.crucible_status); self.effects=ParseMap(values.crucible_effect_pct); self.ceilings=ParseMap(values.crucible_ceiling_pct)
    local maximum=0; for id in pairs(META) do maximum=math.max(maximum,tonumber(self.investments[id]) or 0) end; for id,c in pairs(self.channels) do c:SetInvestment(self.investments[id] or 0,maximum) end
    self.essenceValue:SetText(FormatInt(self.essence)); self.total:SetText("TOTAL PERMANENT INVESTMENT  "..FormatInt(values.crucible_total_invested or 0).."  ·  SECONDARY VISAGE RESPONDS TO THIS TOTAL"); self:SelectCategory(self.selected)
end
function Screen:WakeCommittedChannel(id)
    local c=self.channels[id]; if not c then return end; self.heat:SetAlpha(0.26); self.selectedJointHeat:SetAlpha(1); c.ember:SetAlpha(1); c.engage:SetAlpha(1)
    if UI:IsReducedMotion() then self.heat:SetAlpha(0.10); self.selectedJointHeat:SetAlpha(0.66); c:Refresh(); return end
    local token=(self.commitWakeToken or 0)+1; self.commitWakeToken=token; C_Timer.After(0.16,function() if Screen.active and Screen.commitWakeToken==token then Screen.heat:SetAlpha(0.16); Screen.selectedJointHeat:SetAlpha(0.82) end end); C_Timer.After(0.34,function() if Screen.active and Screen.commitWakeToken==token then Screen.heat:SetAlpha(0.07); Screen.selectedJointHeat:SetAlpha(0.66); c:Refresh() end end)
end
function Screen:Forge()
    if self.investPending or not self.previewCache[self:PreviewKey()] then return false end; if (tonumber(self.essence) or 0)<self.amount then self.status:SetText("Insufficient Essence."); self:RefreshForge(); return false end
    self.investPending=true; self.investKey=self:PreviewKey(); self.status:SetText("The chamber is committing this investment…"); self:WakeCommittedChannel(self.selected); self:RefreshForge(); if not APB:RequestEchoesAction("crucible_invest",self.selected,self.amount) then self.investPending=false; self.status:SetText("Crucible request could not be dispatched. Check the Worldsoul connection."); self:RefreshForge(); UI:Trace("request.crucible_invest","ui","dispatch-failed"); return false end; UI:Trace("request.crucible_invest","ui","dispatched"); self.investToken=(self.investToken or 0)+1; local token=self.investToken
    C_Timer.After(5.0,function() if Screen.active and Screen.investPending and Screen.investToken==token then Screen.investPending=false; Screen.status:SetText("No response received. Verify state before trying again."); Screen:RefreshForge(); if APB.RequestEchoesState then APB:RequestEchoesState() end end end); return true
end
function Screen:OnAction(verb,fields)
    if not self.active then return end
    if verb=="ACTION_OK" and fields.action=="crucible_preview" then self.previewPending=false; local key=tostring(fields.category)..":"..tostring(fields.amount); if fields.status=="READY" then self.previewCache[key]=fields end; self:UpdatePreview(); self:RefreshForge(); if self.desiredPreviewKey~=key then self:RequestPreview() end
    elseif verb=="ACTION_OK" and fields.action=="crucible_invest" then self.investPending=false; self.investToken=(self.investToken or 0)+1; if fields.status=="SUCCESS" then self.previewCache={}; self.status:SetText("The Crucible seals the investment. The chamber is settling…"); self:WakeCommittedChannel(fields.category or self.selected); if APB.RequestEchoesState then APB:RequestEchoesState() end else self.status:SetText(fields.reason~="" and fields.reason or "The Crucible rejected this investment.") end; self:RefreshForge()
    elseif verb=="ERROR" and (self.previewPending or self.investPending) then local wasPreview=self.previewPending; self.previewPending=false; self.investPending=false; self.investToken=(self.investToken or 0)+1; self.status:SetText(fields.code=="RATE_LIMITED" and "The chamber is still settling. Preview will resume." or "Crucible request unavailable."); self:RefreshForge(); if wasPreview and fields.code=="RATE_LIMITED" then C_Timer.After(1.05,function() if Screen.active then Screen:RequestPreview() end end) end end
end

function Screen:UpdateScale() self.frame:SetScale(math.min((UIParent:GetWidth() or 1672)/1672,(UIParent:GetHeight() or 941)/941)) end
function Screen:Show()
    self.openToken=self.openToken+1; self.active=true; self:UpdateScale(); if APB and APB.C43 and APB.C43.frame then APB.C43.frame:Hide() end
    self.frame:SetAlpha(UI:IsReducedMotion() and 1 or 0); self.frame:Show(); Animation:Alpha(self.frame,1,0.22); self.input:SetFocusById(self.selected); self:RefreshState(UI.StateStore.values); if APB and APB.RequestEchoesState then APB:RequestEchoesState() end
end
function Screen:Hide() self.openToken=self.openToken+1; self.active=false; self.previewPending=false; self.investPending=false; self.previewToken=(self.previewToken or 0)+1; self.investToken=(self.investToken or 0)+1; self.commitWakeToken=(self.commitWakeToken or 0)+1; self.input:ClearFocus(); Animation:Stop(self.frame); self.frame:Hide() end
function Screen:Leave(destination) self:Hide(); local focusId=destination=="home" and "core" or "crucible"; if UI.DashboardGateB and UI.ScreenManager:Show("dashboardGateB",false,focusId) then return end; UI.ScreenManager.current=nil; if APB and APB.C43 then APB.C43:Show() end end
function Screen:CloseCompanion() self:Hide(); UI.ScreenManager.current=nil; UI.ScreenManager.history={}; if APB and APB.C43 and APB.C43.Hide then APB.C43:Hide() end end

UI.StateStore:Subscribe(function(values) if Screen.active then Screen:RefreshState(values) end end); if APB and APB.SubscribeEchoesActions then APB:SubscribeEchoesActions(function(verb,fields) Screen:OnAction(verb,fields) end) end
UI.CrucibleScreen=Screen; UI.ScreenManager:Register("crucible",Screen,false); UI.modules.CrucibleScreen=true
