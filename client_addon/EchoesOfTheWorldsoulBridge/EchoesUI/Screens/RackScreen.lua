local UI=EchoesUI
if not UI or not UI.ProgressionRow or not UI.ScreenManager then return end
local Theme=UI.Theme
local Animation=UI.AnimationController
local Screen={id="rack",active=false,pending=false,rows={},candidates={}}
local ASSET="Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\"

local function Solid(parent,layer,color)
    local t=parent:CreateTexture(nil,layer); Theme:SetTextureColor(t,color); return t
end
local function Art(parent,layer,name,uMax,vMax,mirror)
    local t=parent:CreateTexture(nil,layer); t:SetTexture(ASSET..name)
    if mirror then t:SetTexCoord(uMax,0,0,vMax) else t:SetTexCoord(0,uMax,0,vMax) end
    return t
end
local function Label(parent,text,font,size,color,point,relative,relativePoint,x,y,width,justify)
    local f=parent:CreateFontString(nil,"OVERLAY"); f:SetFont(font,size,font==Theme.fonts.monument and "OUTLINE" or nil)
    f:SetText(text); f:SetTextColor(unpack(color)); f:SetPoint(point,relative,relativePoint,x,y)
    if width then f:SetWidth(width); f:SetJustifyH(justify or "LEFT") end; return f
end
local function ItemName(entry)
    local name,link,_,_,_,_,_,_,_,icon=GetItemInfo(entry)
    return name or ("ITEM "..tostring(entry)),link,icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function ParseTriples(value)
    local result={}; for token in tostring(value or ""):gmatch("[^,]+") do
        local a,b,c=token:match("^(%d+):(%d+):(%d+)$")
        if a then result[#result+1]={slot=tonumber(a),entry=tonumber(b),quality=tonumber(c)} end
    end; return result
end
local function ParsePairs(value)
    local result={}; for token in tostring(value or ""):gmatch("[^,]+") do
        local a,b=token:match("^(%d+):(%d+)$")
        if a then result[#result+1]={entry=tonumber(a),quality=tonumber(b)} end
    end; return result
end
local function FormatInt(value)
    local s=tostring(math.floor(tonumber(value) or 0)); while true do local n; s,n=s:gsub("^(-?%d+)(%d%d%d)","%1,%2"); if n==0 then break end end; return s
end

local frame=CreateFrame("Frame","EchoesUIRackScreen",UIParent); frame:SetSize(1672,941); frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG"); frame:EnableMouse(true); frame:Hide(); Screen.frame=frame
for row=0,1 do for col=0,3 do local t=frame:CreateTexture(nil,"BACKGROUND"); t:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\C43_"..col..row); local w=col==3 and 136 or 512; local h=row==1 and 429 or 512; t:SetSize(w,h); t:SetPoint("TOPLEFT",frame,"TOPLEFT",col*512,-row*512); t:SetTexCoord(0,w/512,0,h/512); t:SetVertexColor(.20,.30,.38,.25) end end
local veil=Solid(frame,"BACKGROUND",{.004,.009,.014,.82}); veil:SetAllPoints(frame)
local crown=Solid(frame,"ARTWORK",Theme.colors.stone); crown:SetSize(600,68); crown:SetPoint("TOP",frame,"TOP",0,-18); crown:Hide()
local crownArt=Art(frame,"ARTWORK","RackHeaderCrown",0.5859375,0.53125); crownArt:SetSize(600,68); crownArt:SetPoint("TOP",frame,"TOP",0,-18); crownArt:SetAlpha(1.0)
local seam=Solid(frame,"OVERLAY",Theme.colors.worldsoul); seam:SetSize(430,2); seam:SetPoint("TOP",crown,"BOTTOM",0,0); seam:SetAlpha(.55); seam:Hide()
Label(frame,"ATTUNEMENT RACK",Theme.fonts.monument,28,Theme.colors.text,"CENTER",crown,"CENTER",0,7)
Label(frame,"CARRIED RELICS  ·  TWENTY-PERCENT ATTUNEMENT WAKE",Theme.fonts.readable,10,Theme.colors.textMuted,"CENTER",crown,"CENTER",0,-18)

local function Place(c,x,y) c.root:SetPoint("TOPLEFT",frame,"TOPLEFT",x,-y); return c end
Screen.back=Place(UI.ProgressionRow:Create(frame,{id="back",width=130,height=38,icon=false,compact=true,label="‹  BACK",onActivate=function() Screen:Leave("back") end}),28,24)
Screen.home=Place(UI.ProgressionRow:Create(frame,{id="home",width=130,height=38,icon=false,compact=true,label="CORE / HOME",onActivate=function() Screen:Leave("home") end}),1368,24)
Screen.close=Place(UI.ProgressionRow:Create(frame,{id="close",width=130,height=38,icon=false,compact=true,label="CLOSE  ×",onActivate=function() Screen:CloseCompanion() end}),1514,24)

local lattice=CreateFrame("Frame",nil,frame); lattice:SetSize(1040,720); lattice:SetPoint("TOPLEFT",frame,"TOPLEFT",70,-122)

-- Gate 1 (Rack): RACK_LEFT_RETENTION_SPINE/RACK_TOP_RETENTION_RAIL replace the flat
-- leftMass/topMass rails at identical anchors. Old solids hidden, not deleted.
local leftMass=Solid(lattice,"ARTWORK",Theme.colors.stoneLift); leftMass:SetSize(24,680); leftMass:SetPoint("LEFT",lattice,"LEFT",0,0); leftMass:Hide()
local leftSpine=Art(lattice,"ARTWORK","RACK_LEFT_RETENTION_SPINE",0.75000000,0.66406250); leftSpine:SetSize(24,680); leftSpine:SetPoint("LEFT",lattice,"LEFT",0,0)
local topMass=Solid(lattice,"ARTWORK",Theme.colors.stone); topMass:SetSize(920,14); topMass:SetPoint("TOPLEFT",lattice,"TOPLEFT",38,0); topMass:Hide()
local topRail=Art(lattice,"ARTWORK","RACK_TOP_RETENTION_RAIL",0.89843750,0.87500000); topRail:SetSize(920,14); topRail:SetPoint("TOPLEFT",lattice,"TOPLEFT",38,0)
-- cradle/rail joint: reusable connector at the leftSpine/topRail corner.
local leftTopJoint=Art(lattice,"ARTWORK","RACK_CRADLE_JOINT",0.53125000,0.53125000); leftTopJoint:SetSize(34,34); leftTopJoint:SetPoint("TOPLEFT",lattice,"TOPLEFT",13,-1)

-- Gate 1 (Rack): RACK_SEALED_TERMINUS replaces lowerMass and backs the sealed-status
-- label as one fabricated lower terminus band.
local lowerMass=Solid(lattice,"ARTWORK",Theme.colors.bronzeDark); lowerMass:SetSize(760,10); lowerMass:SetPoint("BOTTOMLEFT",lattice,"BOTTOMLEFT",52,0); lowerMass:SetAlpha(.72); lowerMass:Hide()
-- Alpha restoration (frontend drift audit, ECHOES-FRONTEND-DRIFT-LEDGER.md Rack row 3):
-- RACK-ART-PLACEMENT-MAP.md Level 2 explicitly specifies "consider raising to ~.85
-- for contrast" for this object's native predecessor (lowerMass, alpha .72). This is
-- the documented target, not a visually-tuned guess.
local sealedTerminus=Art(lattice,"ARTWORK","RACK_SEALED_TERMINUS",0.74218750,0.65625000); sealedTerminus:SetSize(760,42); sealedTerminus:SetPoint("BOTTOMLEFT",lattice,"BOTTOMLEFT",52,0); sealedTerminus:SetAlpha(.85)

Label(lattice,"TRACKED RELICS",Theme.fonts.monument,18,Theme.colors.text,"TOPLEFT",lattice,"TOPLEFT",50,-31)
Screen.capacity=Label(lattice,"0 / 3 CRADLES",Theme.fonts.readable,10,Theme.colors.worldsoulPale,"TOPRIGHT",lattice,"TOPRIGHT",-36,-38,180,"RIGHT")
Label(lattice,"Items remain in your bags. Removing a relic only ends Rack tracking.",Theme.fonts.readable,10,Theme.colors.textMuted,"TOPLEFT",lattice,"TOPLEFT",50,-58,700)

for slot=1,20 do
    local col=slot<=10 and 0 or 1; local line=((slot-1)%10)
    local row=UI.ProgressionRow:Create(lattice,{id="rackSlot"..slot,width=465,height=54,label="EMPTY CRADLE",meta="Available at this capacity",value=tostring(slot),icon=true,accentColor=Theme.colors.worldsoul,onActivate=function(control) Screen:Remove(control.slot or slot) end})
    row.root:SetPoint("TOPLEFT",lattice,"TOPLEFT",50+col*488,-88-line*57)
    -- Gate 1 (Rack): the old RackCradle placeholder is replaced at :Refresh() time by
    -- RACK_OCCUPIED_CRADLE_A/B (alternating, cosmetic only) or RACK_OPEN_CRADLE,
    -- selected per row state. Layer stays BACKGROUND, below native row content.
    local cradle=row.root:CreateTexture(nil,"BACKGROUND"); cradle:SetAllPoints(row.root); row.cradle=cradle
    Screen.rows[slot]=row
end

local picker=CreateFrame("Frame",nil,frame); picker:SetSize(430,720); picker:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-74,-122)
local pickerMass=Solid(picker,"ARTWORK",Theme.colors.stoneLift); pickerMass:SetSize(20,680); pickerMass:SetPoint("RIGHT",picker,"RIGHT",0,0); pickerMass:Hide()
-- Gate 1 (Rack): RACK_PICKER_SPINE is the mirrored counterpart to leftSpine (source
-- marks it "Mirrored: yes" -- flipped U via Art()'s mirror flag).
local pickerSpine=Art(picker,"ARTWORK","RACK_PICKER_SPINE",0.62500000,0.66406250,true); pickerSpine:SetSize(20,680); pickerSpine:SetPoint("RIGHT",picker,"RIGHT",0,0)
local pickerTop=Solid(picker,"ARTWORK",Theme.colors.stone); pickerTop:SetSize(390,14); pickerTop:SetPoint("TOPRIGHT",picker,"TOPRIGHT",-20,0); pickerTop:Hide()
local pickerTopRail=Art(picker,"ARTWORK","RACK_PICKER_TOP",0.76171875,0.87500000); pickerTopRail:SetSize(390,14); pickerTopRail:SetPoint("TOPRIGHT",picker,"TOPRIGHT",-20,0)
Label(picker,"ELIGIBLE IN BAGS",Theme.fonts.monument,18,Theme.colors.text,"TOPLEFT",picker,"TOPLEFT",0,-31)
Label(picker,"Choose a carried weapon or armor piece to track.",Theme.fonts.readable,10,Theme.colors.textMuted,"TOPLEFT",picker,"TOPLEFT",0,-58,390)

-- Gate 1 (Rack): the persistent empty-intake port sits beneath the candidate list at
-- its first-row position; shown only when no eligible relic occupies row 1.
Screen.emptyIntakePort=Art(picker,"BACKGROUND","RACK_EMPTY_INTAKE_PORT",0.76171875,0.92187500); Screen.emptyIntakePort:SetSize(390,118); Screen.emptyIntakePort:SetPoint("TOPLEFT",picker,"TOPLEFT",0,-88); Screen.emptyIntakePort:Hide()

for index=1,10 do
    local row=UI.ProgressionRow:Create(picker,{id="rackCandidate"..index,width=390,height=48,label="NO ELIGIBLE RELIC",meta="",value="TRACK",icon=true,accentColor=Theme.colors.worldsoul,onActivate=function() Screen:Add(index) end})
    row.root:SetPoint("TOPLEFT",picker,"TOPLEFT",0,-88-(index-1)*51); Screen.candidates[index]=row
    -- Gate 1 (Rack): RACK_INTAKE_SLOT_A/B alternate per candidate row (cosmetic only).
    local intake=row.root:CreateTexture(nil,"BACKGROUND"); intake:SetAllPoints(row.root); row.intake=intake
end

-- Fit fix: default valueWidth (72) clips the worst-case cost string. Real expansion
-- tiers (ap_rack.lua ExpandTiers) include 500/2,000/5,000 Essence -- "5,000 ESSENCE"
-- does not fit 72px at this font. Widened to 115; meta/label reflow automatically
-- since ProgressionRow derives their width from valueWidth. No row size/anchor change.
local expansion=UI.ProgressionRow:Create(picker,{id="rackExpand",width=390,height=70,label="EXPAND RACK",meta="AUTHORITATIVE NEXT CAPACITY",value="—",icon=false,valueWidth=115,accentColor=Theme.colors.bronzeBright,onActivate=function() Screen:Expand() end}); expansion.root:SetPoint("BOTTOMLEFT",picker,"BOTTOMLEFT",0,0); Screen.expand=expansion
-- Gate 1 (Rack): RACK_CAPACITY_ACTUATOR backs the expansion row at its own bounds.
local capacityActuator=expansion.root:CreateTexture(nil,"BACKGROUND"); capacityActuator:SetTexture(ASSET.."RACK_CAPACITY_ACTUATOR"); capacityActuator:SetTexCoord(0,0.76171875,0,0.54687500); capacityActuator:SetAllPoints(expansion.root)

Screen.sealed=Label(lattice,"",Theme.fonts.monument,13,Theme.colors.textMuted,"BOTTOMLEFT",lattice,"BOTTOMLEFT",52,28,900)
Screen.status=Label(frame,"",Theme.fonts.readable,10,Theme.colors.textMuted,"BOTTOM",frame,"BOTTOM",0,34,1100,"CENTER")
Label(frame,"RACK ATTUNEMENT IS PASSIVE  ·  RELICS REMAIN PHYSICAL  ·  REMOVAL IS NON-DESTRUCTIVE",Theme.fonts.readable,9,Theme.colors.disabled,"BOTTOM",frame,"BOTTOM",0,13,1000,"CENTER")

local input=UI.InputManager:New(frame); Screen.input=input
for _,c in ipairs({Screen.back,Screen.home,Screen.close}) do input:Add(c,c.id) end
for i=1,20 do input:Add(Screen.rows[i],Screen.rows[i].id) end
for i=1,10 do input:Add(Screen.candidates[i],Screen.candidates[i].id) end; input:Add(expansion,expansion.id)
local ordered={"back","home","close"}; for i=1,20 do ordered[#ordered+1]="rackSlot"..i end; for i=1,10 do ordered[#ordered+1]="rackCandidate"..i end; ordered[#ordered+1]="rackExpand"
local nav={back={RIGHT="rackSlot1",DOWN="rackSlot1"},home={LEFT="back",RIGHT="close",DOWN="rackCandidate1"},close={LEFT="home",DOWN="rackCandidate1"},rackExpand={UP="rackCandidate10",LEFT="rackSlot20"}}
for i=1,20 do local id="rackSlot"..i; nav[id]={UP=i==1 and "back" or "rackSlot"..(i-1),DOWN=i==20 and "rackExpand" or "rackSlot"..(i+1),RIGHT=i<=10 and "rackSlot"..(i+10) or "rackCandidate"..math.min(10,i-10),LEFT=i>10 and "rackSlot"..(i-10) or nil} end
for i=1,10 do nav["rackCandidate"..i]={UP=i==1 and "home" or "rackCandidate"..(i-1),DOWN=i==10 and "rackExpand" or "rackCandidate"..(i+1),LEFT="rackSlot"..(i+10)} end
input:SetNavigation(ordered,nav); input.defaultFocusId="rackSlot1"; input.onEscape=function() Screen:Leave("back") end

function Screen:Refresh(values)
    values=values or UI.StateStore.values or {}; self.entries=ParseTriples(values.rack_entries); self.eligible=ParsePairs(values.rack_candidates)
    local bySlot={}; for _,entry in ipairs(self.entries) do bySlot[entry.slot]=entry end
    local cap=tonumber(values.rack_cap) or 3; local used=tonumber(values.rack_used) or #self.entries; self.capacity:SetText(used.." / "..cap.." CRADLES")
    local visible={}; for _,entry in ipairs(self.entries) do visible[#visible+1]=entry end
    if used<cap then
        local openSlot; for slot=1,cap do if not bySlot[slot] then openSlot=slot break end end
        if openSlot then visible[#visible+1]={slot=openSlot,empty=true} end
    end
    for index,row in ipairs(self.rows) do local item=visible[index]
        if item then
            local col=index<=10 and 0 or 1; local line=(index-1)%10; row.root:ClearAllPoints(); row.root:SetPoint("TOPLEFT",lattice,"TOPLEFT",50+col*488,-88-line*57); row.root:Show(); row.slot=item.slot
            if item.empty then
                row:SetData({label="OPEN CRADLE",meta="Ready for a carried relic",value=tostring(item.slot),strength=0}); if row.icon then row.icon:SetAlpha(0) end; row:SetEnabled(false)
                -- Alpha restoration (drift ledger Rack row 2): RACK-ART-PLACEMENT-MAP.md
                -- specifies graduated per-state alpha (native .22 empty / .40 tracking),
                -- "raise all three for contrast" -- not flatten to one value. Raised here
                -- proportionally (native tracking/empty ratio .40/.22 ~= 1.82 preserved)
                -- so the AVAILABLE CONNECTION vs TRACKED/ACTIVE distinction stays legible.
                row.cradle:SetTexture(ASSET.."RACK_OPEN_CRADLE"); row.cradle:SetTexCoord(0,0.90820312,0,0.84375000); row.cradle:SetAlpha(.50)
            else
                local name,link,icon=ItemName(item.entry); row:SetData({label=name,meta="TRACKING  ·  20% ATTUNEMENT XP",value="REMOVE",icon=icon,tooltipLink=link or ("item:"..item.entry),strength=.35}); if row.icon then row.icon:SetAlpha(1) end; row:SetEnabled(not self.pending)
                row.cradle:SetTexture(index%2==0 and ASSET.."RACK_OCCUPIED_CRADLE_B" or ASSET.."RACK_OCCUPIED_CRADLE_A"); row.cradle:SetTexCoord(0,0.90820312,0,0.84375000); row.cradle:SetAlpha(.90)
            end
        else row.slot=nil; row.root:Hide(); row:SetEnabled(false) end
    end
    local sealed=math.max(0,20-cap); local open=math.max(0,cap-used)
    self.sealed:SetText((open>0 and (open.." OPEN") or "RACK FULL").."  ·  "..sealed.." SEALED BEYOND CURRENT CAPACITY")
    local anyEligible=false
    for i,row in ipairs(self.candidates) do local item=self.eligible[i]
        if item and used<cap then anyEligible=true; local name,link,icon=ItemName(item.entry); row.root:Show(); row:SetData({label=name,meta="CARRIED  ·  ELIGIBLE",value="TRACK",icon=icon,tooltipLink=link or ("item:"..item.entry),strength=.22}); if row.icon then row.icon:SetAlpha(1) end; row:SetEnabled(not self.pending)
            row.meta:SetWidth(248) -- restore default meta width (undoes the row-1 empty-state widening below, if it was applied)
            row.intake:SetTexture(i%2==0 and ASSET.."RACK_INTAKE_SLOT_B" or ASSET.."RACK_INTAKE_SLOT_A"); row.intake:SetTexCoord(0,0.76171875,0,0.75000000); row.intake:SetAlpha(1)
        else row:SetData({label=i==1 and (used>=cap and "RACK FULL" or "NO ELIGIBLE RELICS") or "",meta=i==1 and "No carried weapon or armor is available to track." or "",value=""}); if row.icon then row.icon:SetAlpha(0) end; row:SetEnabled(false)
            -- Fit fix: row 1's meta at the default 248px width wraps/clips this sentence
            -- (51 chars). Rows 2-10 are hidden in this state and row 1's own value slot
            -- is blank, so this borrows that unused horizontal space -- no row size or
            -- anchor change, and rows 2-10's geometry is untouched.
            if i>1 then row.root:Hide() else row.root:Show(); row.meta:SetWidth(330) end; row.intake:SetAlpha(0) end
    end
    if anyEligible then self.emptyIntakePort:Hide() else self.emptyIntakePort:Show() end
    local atMax=tonumber(values.rack_at_max)==1; local nextSlots=tonumber(values.rack_next_slots) or 0; local e=tonumber(values.rack_next_essence_cost) or 0; local r=tonumber(values.rack_next_residue_cost) or 0
    if atMax then expansion:SetData({label="RACK AT MAXIMUM",meta="TWENTY CRADLES OPEN",value="20"}); expansion:SetEnabled(false)
    elseif nextSlots>0 then local cost=e>0 and (FormatInt(e).." ESSENCE") or (FormatInt(r).." RESIDUE"); expansion:SetData({label="EXPAND TO "..nextSlots.." CRADLES",meta="PERMANENT CAPACITY",value=cost}); expansion:SetEnabled(not self.pending)
    else expansion:SetData({label="EXPANSION UNAVAILABLE",meta="AUTHORITATIVE STATE REQUIRED",value="—"}); expansion:SetEnabled(false) end
    local rowCount=#visible; local candidateCount=used<cap and math.min(#self.eligible,10) or 0; local ordered={"back","home","close"}; local nav={back={DOWN="rackSlot1"},home={LEFT="back",RIGHT="close",DOWN=candidateCount>0 and "rackCandidate1" or "rackExpand"},close={LEFT="home",DOWN=candidateCount>0 and "rackCandidate1" or "rackExpand"},rackExpand={UP=candidateCount>0 and ("rackCandidate"..candidateCount) or ("rackSlot"..rowCount),LEFT="rackSlot"..rowCount}}
    for i=1,rowCount do local id="rackSlot"..i; ordered[#ordered+1]=id; nav[id]={UP=i==1 and "back" or "rackSlot"..(i-1),DOWN=i==rowCount and "rackExpand" or "rackSlot"..(i+1),RIGHT=candidateCount>0 and ("rackCandidate"..math.min(i,candidateCount)) or "rackExpand"} end
    for i=1,candidateCount do local id="rackCandidate"..i; ordered[#ordered+1]=id; nav[id]={UP=i==1 and "home" or "rackCandidate"..(i-1),DOWN=i==candidateCount and "rackExpand" or "rackCandidate"..(i+1),LEFT="rackSlot"..math.min(i,rowCount)} end
    ordered[#ordered+1]="rackExpand"; self.input:SetNavigation(ordered,nav)
end
function Screen:Begin(action,...)
    if self.pending then return false end; self.pending=true; self.pendingAction=action; self.status:SetText("The Rack is settling…"); self:Refresh(UI.StateStore.values); APB:RequestEchoesAction(action,...)
    self.pendingToken=(self.pendingToken or 0)+1; local token=self.pendingToken; C_Timer.After(5,function() if Screen.active and Screen.pending and Screen.pendingToken==token then Screen.pending=false; Screen.status:SetText("No response received. State has been requested again."); Screen:Refresh(UI.StateStore.values); APB:RequestEchoesState() end end); return true
end
function Screen:Add(index) local item=self.eligible and self.eligible[index]; if item then return self:Begin("rack_add",item.entry) end end
function Screen:Remove(slot) local item; for _,entry in ipairs(self.entries or {}) do if entry.slot==slot then item=entry break end end; if item then return self:Begin("rack_remove",slot) end end
function Screen:Expand() return self:Begin("rack_expand") end
function Screen:OnAction(verb,fields)
    if not self.active or not self.pending then return end
    if verb=="ACTION_OK" and fields.action==self.pendingAction then self.pending=false; self.pendingToken=(self.pendingToken or 0)+1; self.status:SetText(fields.status=="SUCCESS" and "Rack state committed." or (fields.status or "Rack request rejected.")); self:Refresh(UI.StateStore.values); APB:RequestEchoesState()
    elseif verb=="ERROR" then self.pending=false; self.pendingToken=(self.pendingToken or 0)+1; self.status:SetText("Rack request unavailable: "..tostring(fields.code or "ERROR")); self:Refresh(UI.StateStore.values) end
end
function Screen:UpdateScale() self.frame:SetScale(math.min((UIParent:GetWidth() or 1672)/1672,(UIParent:GetHeight() or 941)/941)) end
function Screen:Show() if not UI.flags.nativeRack then return false end; self.active=true; self:UpdateScale(); if APB.C43 and APB.C43.frame then APB.C43.frame:Hide() end; self.frame:SetAlpha(UI:IsReducedMotion() and 1 or 0); self.frame:Show(); Animation:Alpha(self.frame,1,.22); self:Refresh(UI.StateStore.values); self.input:SetFocusById("rackSlot1"); APB:RequestEchoesState(); return true end
function Screen:Hide() self.active=false; self.pending=false; self.pendingToken=(self.pendingToken or 0)+1; self.input:ClearFocus(); Animation:Stop(self.frame); self.frame:Hide() end
function Screen:Leave(destination) self:Hide(); local focus=destination=="home" and "core" or "rack"; if UI.DashboardGateB and UI.ScreenManager:Show("dashboardGateB",false,focus) then return end; UI.ScreenManager.current=nil; if APB.C43 then APB.C43:Show() end end
function Screen:CloseCompanion() self:Hide(); UI.ScreenManager.current=nil; UI.ScreenManager.history={}; if APB.C43 and APB.C43.Hide then APB.C43:Hide() end end
function Screen:IsAvailable() local e=APB and APB.echoes; return UI.flags.nativeRack~=false and e and e.welcomed==true and e.compatible~=0 and e.caps and e.caps.rack_state_v1 and e.caps.action_rack_add and e.caps.action_rack_remove and e.caps.action_rack_expand end

UI.StateStore:Subscribe(function(values) if Screen.active then Screen:Refresh(values) end end)
if APB and APB.SubscribeEchoesActions then APB:SubscribeEchoesActions(function(verb,fields) Screen:OnAction(verb,fields) end) end
UI.RackScreen=Screen; UI.ScreenManager:Register("rack",Screen,false); UI.modules.RackScreen=true
