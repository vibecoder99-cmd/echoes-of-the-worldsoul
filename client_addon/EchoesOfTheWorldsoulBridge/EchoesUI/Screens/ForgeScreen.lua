local UI=EchoesUI
if not UI or not UI.ProgressionRow or not UI.ScreenManager then return end
local Theme,Animation=UI.Theme,UI.AnimationController
local Screen={id="forge",active=false,pending=false,selected=nil,items={},rows={},armedEntry=nil,armToken=0}
local ASSET="Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\"
local function Solid(p,l,c) local t=p:CreateTexture(nil,l); Theme:SetTextureColor(t,c); return t end
local function Art(parent,layer,name,uMax,vMax) local t=parent:CreateTexture(nil,layer); t:SetTexture(ASSET..name); t:SetTexCoord(0,uMax,0,vMax); return t end
local function Label(p,text,font,size,color,point,rel,relPoint,x,y,width,justify) local f=p:CreateFontString(nil,"OVERLAY"); f:SetFont(font,size,font==Theme.fonts.monument and "OUTLINE" or nil); f:SetText(text); f:SetTextColor(unpack(color)); f:SetPoint(point,rel,relPoint,x,y); if width then f:SetWidth(width); f:SetJustifyH(justify or "LEFT") end; return f end
local function FormatInt(v) local s=tostring(math.floor(tonumber(v) or 0)); while true do local n; s,n=s:gsub("^(-?%d+)(%d%d%d)","%1,%2"); if n==0 then break end end; return s end
local function Item(entry) local name,link,_,_,_,_,_,_,_,icon=GetItemInfo(entry); return name or ("ITEM "..entry),link,icon or "Interface\\Icons\\INV_Misc_QuestionMark" end
local function Parse(value) local out={}; for token in tostring(value or ""):gmatch("[^,]+") do local a,b,c,d,e=token:match("^(%d+):(%d+):(%d+):(%d+):(%d+)$"); if a then out[#out+1]={entry=tonumber(a),quality=tonumber(b),essence=tonumber(c),gold=tonumber(d),residue=tonumber(e)} end end; return out end
-- Presentation-only formatting for raw server enum values. The internal
-- comparison (values.forge_catalyst_status=="READY") always reads the raw
-- value directly and is untouched by this table -- only the player-facing
-- text is reformatted.
local CATALYST_STATUS_DISPLAY={INSUFFICIENT_RESIDUE="INSUFFICIENT RESIDUE"}
local function FormatCatalystStatus(status) return status and (CATALYST_STATUS_DISPLAY[status] or status) or nil end
local frame=CreateFrame("Frame","EchoesUIForgeScreen",UIParent); frame:SetSize(1672,941); frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG"); frame:EnableMouse(true); frame:Hide(); Screen.frame=frame
for r=0,1 do for c=0,3 do local t=frame:CreateTexture(nil,"BACKGROUND"); t:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\C43_"..c..r); local w=c==3 and 136 or 512; local h=r==1 and 429 or 512; t:SetSize(w,h); t:SetPoint("TOPLEFT",frame,"TOPLEFT",c*512,-r*512); t:SetTexCoord(0,w/512,0,h/512); t:SetVertexColor(.20,.28,.34,.23) end end
local veil=Solid(frame,"BACKGROUND",{.004,.007,.010,.79}); veil:SetAllPoints(frame)
local crown=Solid(frame,"ARTWORK",Theme.colors.stone); crown:SetSize(610,68); crown:SetPoint("TOP",frame,"TOP",0,-18); crown:Hide(); local crownArt=Art(frame,"ARTWORK","ForgeHeaderCrown",0.595703125,0.53125); crownArt:SetSize(610,68); crownArt:SetPoint("TOP",frame,"TOP",0,-18); crownArt:SetAlpha(1.0); local crownEdge=Solid(frame,"OVERLAY",Theme.colors.bronzeBright); crownEdge:SetSize(410,2); crownEdge:SetPoint("TOP",crown,"BOTTOM",0,0); crownEdge:SetAlpha(.42); crownEdge:Hide()
Label(frame,"LEGACY FORGE",Theme.fonts.monument,28,Theme.colors.text,"CENTER",crown,"CENTER",0,7); Label(frame,"DISSOLUTION  ·  PERMANENT ECHO RETENTION",Theme.fonts.readable,10,Theme.colors.textMuted,"CENTER",crown,"CENTER",0,-18)
local function Place(c,x,y) c.root:SetPoint("TOPLEFT",frame,"TOPLEFT",x,-y); return c end
Screen.back=Place(UI.ProgressionRow:Create(frame,{id="back",width=130,height=38,icon=false,compact=true,label="‹  BACK",onActivate=function() Screen:Leave("back") end}),28,24); Screen.home=Place(UI.ProgressionRow:Create(frame,{id="home",width=130,height=38,icon=false,compact=true,label="CORE / HOME",onActivate=function() Screen:Leave("home") end}),1368,24); Screen.close=Place(UI.ProgressionRow:Create(frame,{id="close",width=130,height=38,icon=false,compact=true,label="CLOSE  ×",onActivate=function() Screen:CloseCompanion() end}),1514,24)

local channel=CreateFrame("Frame",nil,frame); channel:SetSize(760,720); channel:SetPoint("TOPLEFT",frame,"TOPLEFT",100,-126)
-- Gate 1 (Forge): FORGE_RELEASE_QUEUE_SPINE/FORGE_QUEUE_THROAT/FORGE_QUEUE_TERMINUS
-- replace the flat descent/throat/terminus bars at identical anchors.
local descent=Solid(channel,"ARTWORK",Theme.colors.stoneLift); descent:SetSize(25,630); descent:SetPoint("TOPLEFT",channel,"TOPLEFT",0,-30); descent:Hide()
local queueSpine=Art(channel,"ARTWORK","FORGE_RELEASE_QUEUE_SPINE",0.78125000,0.61523438); queueSpine:SetSize(25,630); queueSpine:SetPoint("TOPLEFT",channel,"TOPLEFT",0,-30)
local throat=Solid(channel,"ARTWORK",Theme.colors.stone); throat:SetSize(680,15); throat:SetPoint("TOPLEFT",channel,"TOPLEFT",26,-3); throat:Hide()
local queueThroat=Art(channel,"ARTWORK","FORGE_QUEUE_THROAT",0.66406250,0.93750000); queueThroat:SetSize(680,15); queueThroat:SetPoint("TOPLEFT",channel,"TOPLEFT",26,-3)
local terminus=Solid(channel,"ARTWORK",Theme.colors.stoneLift); terminus:SetSize(620,30); terminus:SetPoint("BOTTOMLEFT",channel,"BOTTOMLEFT",24,0); terminus:Hide()
local queueTerminus=Art(channel,"ARTWORK","FORGE_QUEUE_TERMINUS",0.60546875,0.93750000); queueTerminus:SetSize(620,30); queueTerminus:SetPoint("BOTTOMLEFT",channel,"BOTTOMLEFT",24,0)
-- queue/chamber transition joint: reusable connector where the descent spine meets the terminus mass.
local queueJoint=Art(channel,"ARTWORK","FORGE_TERMINAL_JOINT",0.65625000,0.53125000); queueJoint:SetSize(42,34); queueJoint:SetPoint("BOTTOMLEFT",channel,"BOTTOMLEFT",2,26)
Label(channel,"ATTUNED RELICS READY FOR RELEASE",Theme.fonts.monument,17,Theme.colors.text,"TOPLEFT",channel,"TOPLEFT",48,-28)
Label(channel,"The physical item is destroyed. Its absorbed stats remain forever.",Theme.fonts.readable,10,Theme.colors.textMuted,"TOPLEFT",channel,"TOPLEFT",48,-55,650)
for i=1,8 do
    local row=UI.ProgressionRow:Create(channel,{id="forgeItem"..i,width=650,height=64,label="EMPTY TERMINUS",meta="",value="",icon=true,accentColor=Theme.colors.worldsoul,onActivate=function() Screen:Select(i) end}); row.root:SetPoint("TOPLEFT",channel,"TOPLEFT",48,-88-(i-1)*68); Screen.rows[i]=row
    -- Gate 1 (Forge): FORGE_RELEASE_SEAT_A/B alternate per candidate row (cosmetic only).
    local seat=row.root:CreateTexture(nil,"BACKGROUND"); seat:SetAllPoints(row.root); seat:SetTexture(ASSET..(i%2==0 and "FORGE_RELEASE_SEAT_B" or "FORGE_RELEASE_SEAT_A")); seat:SetTexCoord(0,0.63476562,0,1.00000000); row.seat=seat
end

local chamber=CreateFrame("Frame",nil,frame); chamber:SetSize(650,720); chamber:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-104,-126)
-- Gate 1 (Forge): FORGE_CHAMBER_MASS/FORGE_CHAMBER_TOP replace the flat mass/top rails.
local mass=Solid(chamber,"ARTWORK",Theme.colors.stoneLift); mass:SetSize(26,650); mass:SetPoint("RIGHT",chamber,"RIGHT",0,0); mass:Hide()
local chamberMass=Art(chamber,"ARTWORK","FORGE_CHAMBER_MASS",0.81250000,0.63476562); chamberMass:SetSize(26,650); chamberMass:SetPoint("RIGHT",chamber,"RIGHT",0,0)
local top=Solid(chamber,"ARTWORK",Theme.colors.stone); top:SetSize(586,15); top:SetPoint("TOPRIGHT",chamber,"TOPRIGHT",-26,-3); top:Hide()
local chamberTop=Art(chamber,"ARTWORK","FORGE_CHAMBER_TOP",0.57226562,0.93750000); chamberTop:SetSize(586,15); chamberTop:SetPoint("TOPRIGHT",chamber,"TOPRIGHT",-26,-3)
Label(chamber,"RECLAMATION TERMINUS",Theme.fonts.monument,17,Theme.colors.text,"TOPLEFT",chamber,"TOPLEFT",12,-28)
-- Gate 1 (Forge): FORGE_RECLAMATION_CAVITY replaces the old low-alpha ForgeTerminus
-- rail wash as an illustrated reclamation shell.
-- Alpha restoration (drift ledger Forge row 2): native rail alpha was .46 -- the
-- screen's single largest asset (186,050px) was left at CreateTexture's default 1.0
-- during integration, which is the "display case frame" failure the Crucible
-- precedent warned against. Restored to the exact native value; no placement-map
-- document specifies a different target for this object.
local rail=chamber:CreateTexture(nil,"ARTWORK"); rail:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\EchoesUI\\Assets\\ForgeTerminus"); rail:SetSize(610,305); rail:SetPoint("TOPLEFT",chamber,"TOPLEFT",-8,-54); rail:Hide()
local reclamationCavity=Art(chamber,"ARTWORK","FORGE_RECLAMATION_CAVITY",0.59570312,0.59570312); reclamationCavity:SetSize(610,305); reclamationCavity:SetPoint("TOPLEFT",chamber,"TOPLEFT",-8,-54); reclamationCavity:SetAlpha(.46)
local well=CreateFrame("Frame",nil,chamber); well:SetSize(570,315); well:SetPoint("TOPLEFT",chamber,"TOPLEFT",12,-82)
-- Gate 1 (Forge): FORGE_INSPECTION_WELL replaces wellBack/wellEdge at the same bounds,
-- deliberately darker/lower-contrast than the outer reclamation cavity above.
-- Alpha restoration (drift ledger Forge row 3): native wellBack alpha was .74;
-- restored to the exact native value.
local wellBack=Solid(well,"ARTWORK",{.006,.012,.017,.74}); wellBack:SetAllPoints(well); wellBack:Hide()
local wellEdge=Solid(well,"OVERLAY",Theme.colors.worldsoul); wellEdge:SetSize(5,285); wellEdge:SetPoint("LEFT",well,"LEFT",0,0); wellEdge:SetAlpha(.62); wellEdge:Hide()
local inspectionWell=Art(well,"ARTWORK","FORGE_INSPECTION_WELL",0.55664062,0.61523438); inspectionWell:SetAllPoints(well); inspectionWell:SetAlpha(.74)
-- Gate 1 (Forge): SHARED_RELIC_ICON_SOCKET replaces the Blizzard UI-Quickslot2 placeholder.
Screen.selectedSocket=well:CreateTexture(nil,"OVERLAY"); Screen.selectedSocket:SetTexture(ASSET.."SHARED_RELIC_ICON_SOCKET"); Screen.selectedSocket:SetTexCoord(0,0.90625000,0,0.90625000); Screen.selectedSocket:SetSize(58,58); Screen.selectedSocket:SetPoint("TOPLEFT",well,"TOPLEFT",24,-22)
Screen.selectedIcon=well:CreateTexture(nil,"OVERLAY"); Screen.selectedIcon:SetSize(42,42); Screen.selectedIcon:SetPoint("CENTER",Screen.selectedSocket,"CENTER",0,0); Screen.selectedIcon:SetAlpha(0)
Screen.itemName=Label(well,"SELECT A RELIC",Theme.fonts.monument,24,Theme.colors.text,"TOPLEFT",well,"TOPLEFT",96,-30,440)
Screen.itemMeta=Label(well,"Up to eight authoritative candidates are shown.",Theme.fonts.readable,10,Theme.colors.textMuted,"TOPLEFT",well,"TOPLEFT",96,-72,440)
Label(well,"DISSOLUTION RETURN",Theme.fonts.readable,10,Theme.colors.textMuted,"TOPLEFT",well,"TOPLEFT",28,-126)
-- Gate 1 (Forge): FORGE_RETURN_MANIFOLD replaces the three individual reward-field
-- backdrops with one mechanism spanning all three; per-field labels/values stay native.
local returnManifold=Art(well,"ARTWORK","FORGE_RETURN_MANIFOLD",0.50976562,0.51562500); returnManifold:SetSize(522,66); returnManifold:SetPoint("TOPLEFT",well,"TOPLEFT",28,-148)
local rewardColors={Theme.colors.worldsoulPale,Theme.colors.bronzeBright,{.73,.52,.92,1}}; local rewardNames={"ESSENCE","GOLD","RESIDUE"}; Screen.rewardFields={}
for i=1,3 do local x=28+(i-1)*174; local field=CreateFrame("Frame",nil,well); field:SetSize(158,66); field:SetPoint("TOPLEFT",well,"TOPLEFT",x,-148); Label(field,rewardNames[i],Theme.fonts.readable,8,Theme.colors.textMuted,"TOPLEFT",field,"TOPLEFT",14,-10); Screen.rewardFields[i]=Label(field,"—",Theme.fonts.monument,17,rewardColors[i],"BOTTOMLEFT",field,"BOTTOMLEFT",14,10,132) end
Screen.reward=Screen.rewardFields[1]
Screen.warning=Label(well,"Your permanent Attunement is retained. Only the physical item is consumed.",Theme.fonts.readable,11,Theme.colors.text,"BOTTOMLEFT",well,"BOTTOMLEFT",28,30,510)
Screen.release=UI.ProgressionRow:Create(chamber,{id="forgeRelease",width=570,height=78,label="RELEASE PHYSICAL ITEM",meta="SELECT A RELIC TO ARM DISSOLUTION",value="CONFIRM",icon=false,accentColor=Theme.colors.worldsoul,onActivate=function() Screen:Dissolve() end}); Screen.release.root:SetPoint("TOPLEFT",chamber,"TOPLEFT",12,-420)
-- Gate 1 (Forge): FORGE_RELEASE_ACTUATOR backs the release row; it never encodes
-- armed state -- the existing arm/confirm/timeout/disarm text stays fully native.
local releaseActuator=Screen.release.root:CreateTexture(nil,"BACKGROUND"); releaseActuator:SetTexture(ASSET.."FORGE_RELEASE_ACTUATOR"); releaseActuator:SetTexCoord(0,0.55664062,0,0.60937500); releaseActuator:SetAllPoints(Screen.release.root)
local releaseSeam=Art(chamber,"OVERLAY","FORGE_DISSOLUTION_SEAM",1.00000000,0.60937500); releaseSeam:SetSize(8,78); releaseSeam:SetPoint("TOPLEFT",chamber,"TOPLEFT",582,-420); releaseSeam:SetAlpha(.7)
local catalystWell=CreateFrame("Frame",nil,chamber); catalystWell:SetSize(570,118); catalystWell:SetPoint("BOTTOMLEFT",chamber,"BOTTOMLEFT",12,14)
-- Gate 1 (Forge): FORGE_CATALYST_APPARATUS replaces the flat cb backdrop, kept
-- deliberately subordinate in contrast/mass to the release actuator above.
-- Alpha restoration (drift ledger Forge row 4): native cb alpha was .68, and
-- INTEGRATION-GUIDANCE.md explicitly requires this asset "remains subordinate in
-- contrast and mass" to the release actuator above (which is correctly opaque at
-- 1.0 -- that was never the problem). Restored to the exact native value so Catalyst
-- reads as materially lower-weight than Release, not equal.
local cb=Solid(catalystWell,"ARTWORK",{.012,.018,.023,.68}); cb:SetAllPoints(catalystWell); cb:Hide()
local catalystApparatus=Art(catalystWell,"ARTWORK","FORGE_CATALYST_APPARATUS",0.55664062,0.92187500); catalystApparatus:SetAllPoints(catalystWell); catalystApparatus:SetAlpha(.68)
-- Fit fix: forge_catalyst_status passes the server's raw status string straight
-- through (ap_forge.lua AP.Forge.PreviewCatalyst) -- "INSUFFICIENT_RESIDUE" (21
-- chars) and "SERVICE_UNAVAILABLE"/"UNAVAILABLE" fallbacks do not fit the default
-- 72px valueWidth at this font; only "READY" did. Widened to 170; meta ("500
-- RESIDUE -> +50 ESSENCE"-style text) has ample spare width to absorb the change.
Screen.catalyst=UI.ProgressionRow:Create(catalystWell,{id="forgeCatalyst",width=540,height=72,label="CRUCIBLE CATALYST",meta="RESIDUE → ESSENCE",value="—",icon=false,valueWidth=170,accentColor=Theme.colors.bronzeBright,onActivate=function() Screen:Catalyst() end}); Screen.catalyst.root:SetPoint("CENTER",catalystWell,"CENTER",0,0)
Screen.balance=Label(chamber,"RESIDUE —",Theme.fonts.readable,10,Theme.colors.textMuted,"BOTTOMLEFT",chamber,"BOTTOMLEFT",20,0,250)
Screen.status=Label(frame,"",Theme.fonts.readable,10,Theme.colors.textMuted,"BOTTOM",frame,"BOTTOM",0,26,1100,"CENTER")

local input=UI.InputManager:New(frame); Screen.input=input; for _,c in ipairs({Screen.back,Screen.home,Screen.close}) do input:Add(c,c.id) end; for i=1,8 do input:Add(Screen.rows[i],Screen.rows[i].id) end; input:Add(Screen.release,Screen.release.id); input:Add(Screen.catalyst,Screen.catalyst.id)
local order={"back","home","close","forgeItem1","forgeItem2","forgeItem3","forgeItem4","forgeItem5","forgeItem6","forgeItem7","forgeItem8","forgeRelease","forgeCatalyst"}; local nav={back={RIGHT="forgeItem1",DOWN="forgeItem1"},home={LEFT="back",RIGHT="close",DOWN="forgeRelease"},close={LEFT="home",DOWN="forgeRelease"},forgeRelease={LEFT="forgeItem4",UP="home",DOWN="forgeCatalyst"},forgeCatalyst={LEFT="forgeItem8",UP="forgeRelease"}}
for i=1,8 do nav["forgeItem"..i]={UP=i==1 and "back" or "forgeItem"..(i-1),DOWN=i==8 and "forgeCatalyst" or "forgeItem"..(i+1),RIGHT="forgeRelease"} end; input:SetNavigation(order,nav); input.defaultFocusId="forgeItem1"; input.onEscape=function() Screen:Leave("back") end

function Screen:Disarm()
    self.armedEntry=nil; self.armToken=(self.armToken or 0)+1
    if self.release then
        self.release.label:SetText("RELEASE PHYSICAL ITEM")
        self.release.meta:SetText(self.selected and "FIRST PRESS ARMS  ·  SECOND PRESS CONFIRMS" or "SELECT A RELIC TO ARM DISSOLUTION")
        self.release.value:SetText("ARM")
    end
end
function Screen:Select(index) local item=self.items[index]; if not item then return end; if self.selected~=item.entry then self:Disarm() end; self.selected=item.entry; for i,row in ipairs(self.rows) do row.selection:SetAlpha(i==index and .12 or 0) end; local name,_,icon=Item(item.entry); self.selectedIcon:SetTexture(icon); self.selectedIcon:SetAlpha(1); self.itemName:SetText(string.upper(name)); self.itemMeta:SetText("QUALITY "..item.quality.."  ·  ITEM "..item.entry); self.rewardFields[1]:SetText("+"..FormatInt(item.essence)); self.rewardFields[2]:SetText("+"..string.format("%.2f",item.gold/10000)); self.rewardFields[3]:SetText("+"..FormatInt(item.residue)); self.release.meta:SetText("FIRST PRESS ARMS  ·  SECOND PRESS CONFIRMS"); self.release.value:SetText("ARM"); self.release:SetEnabled(not self.pending) end
function Screen:Refresh(values) values=values or UI.StateStore.values or {}; self.items=Parse(values.forge_eligible); local selectedExists=false
    for i,row in ipairs(self.rows) do local item=self.items[i]; if item then local name,link,icon=Item(item.entry); row.root:Show(); row:SetData({label=name,meta="FULLY ATTUNED  ·  PHYSICAL ITEM PRESENT",value="+"..FormatInt(item.residue).." R",icon=icon,tooltipLink=link or ("item:"..item.entry),strength=.3}); if row.icon then row.icon:SetAlpha(1) end; row:SetEnabled(not self.pending); if item.entry==self.selected then selectedExists=true end else row:SetData({label=i==1 and "NO RELICS READY" or "",meta=i==1 and "No fully attuned physical item is available" or "",value=""}); if row.icon then row.icon:SetAlpha(0) end; row:SetEnabled(false); if i==1 then row.root:Show() else row.root:Hide() end end end
    if not selectedExists then self.selected=nil; self:Disarm(); self.selectedIcon:SetAlpha(0); self.itemName:SetText("SELECT A RELIC"); self.itemMeta:SetText("Up to eight authoritative candidates are shown."); for _,field in ipairs(self.rewardFields) do field:SetText("—") end; self.release:SetEnabled(false) end
    local residue=tonumber(values.residue) or 0; local cost=tonumber(values.forge_catalyst_cost) or 0; local reward=tonumber(values.forge_catalyst_reward) or 0; self.balance:SetText("RESIDUE  "..FormatInt(residue)); self.catalyst:SetData({label="CRUCIBLE CATALYST",meta=FormatInt(cost).." RESIDUE  →  +"..FormatInt(reward).." ESSENCE",value=FormatCatalystStatus(values.forge_catalyst_status) or "—"}); self.catalyst:SetEnabled(not self.pending and values.forge_catalyst_status=="READY")
    local count=math.max(1,#self.items); local ordered={"back","home","close"}; local nav={back={DOWN="forgeItem1"},home={LEFT="back",RIGHT="close",DOWN="forgeRelease"},close={LEFT="home",DOWN="forgeRelease"},forgeRelease={LEFT="forgeItem"..math.min(4,count),UP="home",DOWN="forgeCatalyst"},forgeCatalyst={LEFT="forgeItem"..count,UP="forgeRelease"}}
    for i=1,count do local id="forgeItem"..i; ordered[#ordered+1]=id; nav[id]={UP=i==1 and "back" or "forgeItem"..(i-1),DOWN=i==count and "forgeCatalyst" or "forgeItem"..(i+1),RIGHT="forgeRelease"} end; ordered[#ordered+1]="forgeRelease"; ordered[#ordered+1]="forgeCatalyst"; self.input:SetNavigation(ordered,nav)
end
function Screen:Begin(action,entry) if self.pending then self.status:SetText("The Forge is already answering the current request."); return false end; self.pending=true; self.pendingAction=action; self.status:SetText(action=="forge_dissolve" and "Dissolution reserved. Do not retry while the terminus settles." or "Catalyst is settling…"); self:Refresh(UI.StateStore.values); if not (APB and APB.RequestEchoesAction and APB:RequestEchoesAction(action,entry)) then self.pending=false; self.pendingAction=nil; self.status:SetText("Forge request could not be dispatched. Check the Worldsoul connection."); self:Refresh(UI.StateStore.values); UI:Trace("request."..action,"ui","dispatch-failed"); return false end; UI:Trace("request."..action,"ui","dispatched"); self.token=(self.token or 0)+1; local token=self.token; C_Timer.After(7,function() if Screen.active and Screen.pending and Screen.token==token then Screen.pending=false; Screen.status:SetText("No response received. Verify state before trying again."); Screen:Refresh(UI.StateStore.values); APB:RequestEchoesState() end end); return true end
function Screen:Dissolve()
    if not self.selected or self.pending then return false end
    if self.armedEntry~=self.selected then
        self.armedEntry=self.selected; self.armToken=(self.armToken or 0)+1; local token=self.armToken
        self.release.label:SetText("CONFIRM ITEM DESTRUCTION")
        self.release.meta:SetText("PHYSICAL ITEM DESTROYED  ·  PERMANENT ATTUNEMENT REMAINS")
        self.release.value:SetText("CONFIRM")
        self.status:SetText("The Forge recognizes the offering. Confirm within 6 seconds to dissolve it.")
        C_Timer.After(6,function() if Screen.active and not Screen.pending and Screen.armToken==token then Screen:Disarm(); Screen.status:SetText("Dissolution disarmed; no item was changed.") end end)
        return true
    end
    local entry=self.selected; self:Disarm(); return self:Begin("forge_dissolve",entry)
end
function Screen:Catalyst() return self:Begin("forge_purchase_catalyst") end
function Screen:OnAction(verb,fields) if not self.active or not self.pending then return end; self:Disarm(); if verb=="ACTION_OK" and fields.action==self.pendingAction then self.pending=false; self.token=(self.token or 0)+1; if fields.status=="SUCCESS" then self.status:SetText(fields.action=="forge_dissolve" and ("The Forge remembers what was given. +"..FormatInt(fields.essence_reward).." Essence, +"..FormatInt(fields.residue_reward).." Residue; permanent Attunement remains.") or "The catalyst exchange is sealed."); self.selected=nil else self.status:SetText(fields.recoverable=="1" and "The item was removed; durable recovery will complete the reward on relog." or (fields.reason~="" and fields.reason or fields.status)) end; self:Refresh(UI.StateStore.values); APB:RequestEchoesState() elseif verb=="ERROR" then self.pending=false; self.token=(self.token or 0)+1; self.status:SetText("Forge request unavailable: "..tostring(fields.code)); self:Refresh(UI.StateStore.values) end end
function Screen:UpdateScale() self.frame:SetScale(math.min((UIParent:GetWidth() or 1672)/1672,(UIParent:GetHeight() or 941)/941)) end
function Screen:Show() if not self:IsAvailable() then return false end; self.active=true; self:UpdateScale(); if APB.C43 and APB.C43.frame then APB.C43.frame:Hide() end; self.frame:SetAlpha(UI:IsReducedMotion() and 1 or 0); self.frame:Show(); Animation:Alpha(self.frame,1,.22); self:Refresh(UI.StateStore.values); self.input:SetFocusById("forgeItem1"); APB:RequestEchoesState(); return true end
function Screen:Hide() self:Disarm(); self.active=false; self.pending=false; self.token=(self.token or 0)+1; self.input:ClearFocus(); Animation:Stop(self.frame); self.frame:Hide() end
function Screen:Leave(destination) self:Hide(); local focus=destination=="home" and "core" or "forge"; if UI.DashboardGateB and UI.ScreenManager:Show("dashboardGateB",false,focus) then return end; UI.ScreenManager.current=nil; if APB.C43 then APB.C43:Show() end end
function Screen:CloseCompanion() self:Hide(); UI.ScreenManager.current=nil; UI.ScreenManager.history={}; if APB.C43 and APB.C43.Hide then APB.C43:Hide() end end
function Screen:IsAvailable() local e=APB and APB.echoes; return UI.flags.nativeForge~=false and e and e.welcomed==true and e.compatible~=0 and e.caps and e.caps.forge_state_v1 and e.caps.action_forge_dissolve and e.caps.action_forge_purchase_catalyst end
UI.StateStore:Subscribe(function(values) if Screen.active then Screen:Refresh(values) end end); if APB and APB.SubscribeEchoesActions then APB:SubscribeEchoesActions(function(v,f) Screen:OnAction(v,f) end) end; UI.ForgeScreen=Screen; UI.ScreenManager:Register("forge",Screen,false); UI.modules.ForgeScreen=true
