local UI=EchoesUI
if not UI or not UI.ScreenManager or not UI.InputManager or not UI.ProgressionRow then return end
local Theme,Animation=UI.Theme,UI.AnimationController
local Screen={id="talents",active=false,selected=0,previewCache={},previewPending=false,purchasePending=false,openToken=0}
local VIOLET={0.58,0.31,0.84,1}; local VIOLET_PALE={0.84,0.70,0.98,1}
local MAT={
    iron={0.052,0.050,0.052,1}, ironLift={0.105,0.096,0.092,1},
    ironEdge={0.175,0.145,0.105,1}, recess={0.016,0.015,0.019,0.98},
    recessLift={0.037,0.030,0.043,1}, bronzeSeat={0.205,0.130,0.048,1},
    bronzeEdge={0.43,0.285,0.095,1}, violetDark={0.135,0.060,0.190,1},
}
local META={
    [0]={abbr="STR",name="STRENGTH",icon="Interface\\Icons\\Ability_Warrior_StrengthOfArms"},
    [1]={abbr="AGI",name="AGILITY",icon="Interface\\Icons\\Ability_Rogue_Sprint"},
    [2]={abbr="STA",name="STAMINA",icon="Interface\\Icons\\Spell_Holy_WordFortitude"},
    [3]={abbr="INT",name="INTELLECT",icon="Interface\\Icons\\Spell_Holy_MagicalSentry"},
    [4]={abbr="SPI",name="SPIRIT",icon="Interface\\Icons\\Spell_Holy_DivineSpirit"},
}

local function Solid(parent,layer,color) local t=parent:CreateTexture(nil,layer); Theme:SetTextureColor(t,color); return t end
local function Label(parent,text,font,size,color,point,relative,relativePoint,x,y,width,justify)
    local v=parent:CreateFontString(nil,"OVERLAY"); v:SetFont(font,size,font==Theme.fonts.monument and "OUTLINE" or nil); v:SetText(text); v:SetTextColor(unpack(color)); v:SetPoint(point,relative,relativePoint,x,y)
    if width then v:SetWidth(width); v:SetJustifyH(justify or "LEFT") end; return v
end
local function FormatInt(value)
    local s=tostring(math.floor(tonumber(value) or 0)); while true do local n,c=s:gsub("^(%d+)(%d%d%d)","%1,%2"); s=n; if c==0 then break end end; return s
end
local function ParseMap(raw,numeric)
    local r={}; if raw then for entry in tostring(raw):gmatch("[^,]+") do local k,v=entry:match("^([^:]+):(.+)$"); if k then r[tonumber(k) or k]=numeric and tonumber(v) or v end end end; return r
end
local function Pct(value) return string.format("%.1f%%",tonumber(value) or 0) end
local function StatName(index) local meta=META[tonumber(index)]; return meta and meta.name or "NONE" end

function Screen:IsAvailable()
    local e=APB and APB.echoes
    return UI.flags.nativeTalents~=false and e and e.welcomed==true and e.compatible~=0
        and e.caps and e.caps.talents_state_v1 and e.caps.action_talent_preview
        and e.caps.action_talent_purchase
end

local frame=CreateFrame("Frame","EchoesUITalentsScreen",UIParent); frame:SetSize(1672,941); frame:SetPoint("CENTER",UIParent,"CENTER",0,0); frame:SetFrameStrata("DIALOG"); frame:EnableMouse(true); frame:Hide(); Screen.frame=frame
for row=0,1 do for col=0,3 do
    local tile=frame:CreateTexture(nil,"BACKGROUND"); tile:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\C43_"..col..row)
    local w=col==3 and 136 or 512; local h=row==1 and 429 or 512; tile:SetSize(w,h); tile:SetPoint("TOPLEFT",frame,"TOPLEFT",col*512,-row*512); tile:SetTexCoord(0,w/512,0,h/512); tile:SetVertexColor(0.25,0.21,0.30,0.24)
end end
local veil=Solid(frame,"BACKGROUND",{0.005,0.006,0.010,0.80}); veil:SetAllPoints(frame)

-- Candidate 43's upper-left brace unfolded into two unequal support limbs. The
-- heavy members terminate at each anchor but never form dependency paths.
local shellTop=Solid(frame,"ARTWORK",MAT.iron); shellTop:SetSize(1492,10); shellTop:SetPoint("TOP",frame,"TOP",0,-94)
local shellSeam=Solid(frame,"OVERLAY",MAT.bronzeEdge); shellSeam:SetSize(706,2); shellSeam:SetPoint("CENTER",shellTop,"CENTER",-188,0); shellSeam:SetAlpha(0.58)
local shellL=Solid(frame,"ARTWORK",MAT.ironLift); shellL:SetSize(18,720); shellL:SetPoint("TOPLEFT",frame,"TOPLEFT",47,-122)
local shellLEdge=Solid(frame,"OVERLAY",MAT.bronzeEdge); shellLEdge:SetSize(3,612); shellLEdge:SetPoint("CENTER",shellL,"CENTER",3,-12); shellLEdge:SetAlpha(0.35)
local shellR=Solid(frame,"ARTWORK",MAT.iron); shellR:SetSize(14,614); shellR:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-48,-122)
local shellREdge=Solid(frame,"OVERLAY",MAT.bronzeSeat); shellREdge:SetSize(3,492); shellREdge:SetPoint("CENTER",shellR,"CENTER",-3,-8); shellREdge:SetAlpha(0.42)
-- Full Visual Fabrication: tal-shell-top/side-left/side-right (all confirmed static).
local shellTopArt=frame:CreateTexture(nil,"ARTWORK"); shellTopArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\TAL_SHELL_TOP"); shellTopArt:SetSize(1492,10); shellTopArt:SetPoint("TOP",frame,"TOP",0,-94); shellTopArt:SetTexCoord(0,1492/2048,0,10/16)
local shellSideLeftArt=frame:CreateTexture(nil,"ARTWORK"); shellSideLeftArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\TAL_SHELL_SIDE_LEFT"); shellSideLeftArt:SetSize(18,720); shellSideLeftArt:SetPoint("TOPLEFT",frame,"TOPLEFT",47,-122); shellSideLeftArt:SetTexCoord(0,18/32,0,720/1024)
local shellSideRightArt=frame:CreateTexture(nil,"ARTWORK"); shellSideRightArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\TAL_SHELL_SIDE_RIGHT"); shellSideRightArt:SetSize(14,614); shellSideRightArt:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-48,-122); shellSideRightArt:SetTexCoord(14/16,0,0,614/1024)
shellTop:Hide(); shellSeam:Hide(); shellL:Hide(); shellLEdge:Hide(); shellR:Hide(); shellREdge:Hide()
-- Full Visual Fabrication: tal-outer-member (4 instances, sparse outer support
-- segments) and tal-brace-* (5, one per anchor -- confirmed static, no Refresh
-- reference anywhere, safe to fully neutralize).
for _,d in ipairs({{69,124,302,9},{69,844,398,10},{1204,124,400,9},{1110,844,494,10}}) do
    local p=Solid(frame,"ARTWORK",MAT.ironLift); p:SetSize(d[3],d[4]); p:SetPoint("TOPLEFT",frame,"TOPLEFT",d[1],-d[2]); p:SetAlpha(0.88)
    local seam=Solid(frame,"OVERLAY",MAT.bronzeEdge); seam:SetSize(math.max(24,d[3]-42),2); seam:SetPoint("CENTER",p,"CENTER",0,0); seam:SetAlpha(0.62)
    local member=frame:CreateTexture(nil,"ARTWORK"); member:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\TAL_OUTER_MEMBER"); member:SetSize(d[3],16); member:SetPoint("TOPLEFT",frame,"TOPLEFT",d[1],-(d[2]+d[4]/2-8)); member:SetTexCoord(0,1.0,0,1.0)
    p:Hide(); seam:Hide()
end
-- {name, x, y, w, h, POT_w, POT_h}
local BRACES={
    {"TAL_BRACE_STRENGTH",300,238,218,13,256,16},{"TAL_BRACE_AGILITY",365,399,172,15,256,16},
    {"TAL_BRACE_STAMINA",292,627,236,13,256,16},{"TAL_BRACE_INTELLECT",1142,298,194,13,256,16},
    {"TAL_BRACE_SPIRIT",1062,609,236,14,256,16},
}
for _,d in ipairs(BRACES) do
    local name,x,y,w,h,pw,ph=d[1],d[2],d[3],d[4],d[5],d[6],d[7]
    local p=Solid(frame,"ARTWORK",MAT.ironLift); p:SetSize(w,h); p:SetPoint("TOPLEFT",frame,"TOPLEFT",x,-y); p:SetAlpha(0.88)
    local seam=Solid(frame,"OVERLAY",MAT.bronzeEdge); seam:SetSize(math.max(24,w-42),2); seam:SetPoint("CENTER",p,"CENTER",0,0); seam:SetAlpha(0.62)
    local brace=frame:CreateTexture(nil,"ARTWORK"); brace:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\"..name); brace:SetAllPoints(p); brace:SetTexCoord(0,w/pw,0,h/ph)
    p:Hide(); seam:Hide()
end
-- Full Visual Fabrication: tal-joint-* (5, anchor retaining pivots). joint/seat
-- confirmed static (no Refresh reference); pin is the native selected-joint
-- indicator ("native selected-joint pin where state-bearing" per provenance) --
-- kept fully native, layered above via unchanged OVERLAY creation order.
local JOINTS={
    {"TAL_JOINT_STRENGTH",468,232,70,42,128,64},{"TAL_JOINT_AGILITY",492,387,74,48,128,64},
    {"TAL_JOINT_STAMINA",464,611,82,40,128,64},{"TAL_JOINT_INTELLECT",1104,286,74,44,128,64},
    {"TAL_JOINT_SPIRIT",1032,594,78,42,128,64},
}
for _,d in ipairs(JOINTS) do
    local name,x,y,w,h,pw,ph=d[1],d[2],d[3],d[4],d[5],d[6],d[7]
    local joint=Solid(frame,"ARTWORK",MAT.ironLift); joint:SetSize(w,h); joint:SetPoint("TOPLEFT",frame,"TOPLEFT",x,-y)
    local seat=Solid(frame,"ARTWORK",MAT.bronzeSeat); seat:SetSize(w-24,h-16); seat:SetPoint("CENTER",joint,"CENTER",0,0); seat:SetAlpha(0.84)
    local jointArt=frame:CreateTexture(nil,"ARTWORK"); jointArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\"..name); jointArt:SetAllPoints(joint); jointArt:SetTexCoord(0,w/pw,0,h/ph)
    joint:Hide(); seat:Hide()
    local pin=frame:CreateTexture(nil,"OVERLAY"); pin:SetTexture("Interface\\Buttons\\UI-Quickslot2"); pin:SetSize(22,22); pin:SetPoint("CENTER",joint,"CENTER",0,0); pin:SetVertexColor(.52,.38,.19,.82)
end

local crown=Solid(frame,"ARTWORK",MAT.iron); crown:SetSize(570,66); crown:SetPoint("TOP",frame,"TOP",0,-17)
local crownL=Solid(frame,"ARTWORK",MAT.ironLift); crownL:SetSize(98,29); crownL:SetPoint("RIGHT",crown,"LEFT",18,-2)
local crownR=Solid(frame,"ARTWORK",MAT.ironLift); crownR:SetSize(72,22); crownR:SetPoint("LEFT",crown,"RIGHT",-14,4)
-- Full Visual Fabrication: tal-title-crown replaces crown/crownL/crownR.
local titleCrownArt=frame:CreateTexture(nil,"ARTWORK"); titleCrownArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\TAL_TITLE_CROWN"); titleCrownArt:SetAllPoints(crown); titleCrownArt:SetTexCoord(0,570/1024,0,66/128)
crown:Hide(); crownL:Hide(); crownR:Hide()
local crownSeam=Solid(frame,"OVERLAY",VIOLET); crownSeam:SetSize(392,2); crownSeam:SetPoint("TOP",crown,"BOTTOM",0,0); crownSeam:SetAlpha(0.56)
Label(frame,"WORLDSOUL TALENTS",Theme.fonts.monument,27,Theme.colors.text,"CENTER",crown,"CENTER",0,7)
Label(frame,"FIVE INDEPENDENT STAT ANCHORS  /  PERMANENT DIRECTION",Theme.fonts.readable,10,Theme.colors.textMuted,"CENTER",crown,"CENTER",0,-17)

local function Place(control,x,y) control.root:SetPoint("TOPLEFT",frame,"TOPLEFT",x,-y); return control end
Screen.back=Place(UI.ProgressionRow:Create(frame,{id="back",width=130,height=38,icon=false,compact=true,label="‹  BACK",onActivate=function() Screen:Leave("back") end}),28,24)
Screen.home=Place(UI.ProgressionRow:Create(frame,{id="home",width=130,height=38,icon=false,compact=true,label="CORE / HOME",onActivate=function() Screen:Leave("home") end}),1368,24)
Screen.close=Place(UI.ProgressionRow:Create(frame,{id="close",width=130,height=38,icon=false,compact=true,label="CLOSE  ×",onActivate=function() Screen:CloseCompanion() end}),1514,24)

Screen.anchors={}
local ANCHOR_SHAPES={
    [0]={plate=214,arm=72,armY=-4}, [1]={plate=228,arm=58,armY=3}, [2]={plate=206,arm=82,armY=-2},
    [3]={plate=218,arm=68,armY=4}, [4]={plate=232,arm=55,armY=-3},
}
local ANCHOR_ASSET={[0]="TAL_ANCHOR_STRENGTH",[1]="TAL_ANCHOR_AGILITY",[2]="TAL_ANCHOR_STAMINA",[3]="TAL_ANCHOR_INTELLECT",[4]="TAL_ANCHOR_SPIRIT"}
local function CreateAnchor(index,side)
    local meta=META[index]; local shape=ANCHOR_SHAPES[index]; local a={id="talent"..index,index=index,side=side,enabled=true,focused=false,hovered=false,selected=false,primary=false,rank=0,maxRank=3,role="UNSET"}
    local root=CreateFrame("Button","EchoesUITalentAnchor"..index,frame); root:SetSize(326,118); root:RegisterForClicks("LeftButtonUp"); root:EnableMouse(true); a.root=root
    -- Full Visual Fabrication: TAL_ANCHOR_* housing. MAJOR DEVIATION FROM PACKAGE: the
    -- package's neutralize list names backing/mass/shoulder/arm/elbow as static
    -- scaffold, but a:Refresh() (below) drives ALL of their alpha dynamically for
    -- selected/hover/primary state -- they are the anchor's core native feedback, not
    -- scaffold. Kept fully native. Housing is installed as the true base layer
    -- (created first, BACKGROUND) beneath them; only the confirmed-static accent
    -- pieces (shadow, topRib, lowerRib, breakTop, breakBottom, socketSeat, armInset,
    -- couplingRib -- none referenced by Refresh) are hidden below. Reported in full
    -- in the integration report, not silently absorbed.
    a.housing=root:CreateTexture(nil,"BACKGROUND"); a.housing:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\"..ANCHOR_ASSET[index]); a.housing:SetAllPoints(root); a.housing:SetTexCoord(0,326/512,0,118/128)
    a.shadow=Solid(root,"BACKGROUND",{0.002,0.003,0.005,0.82}); a.shadow:SetSize(shape.plate+48,82); a.shadow:SetPoint("CENTER",root,"CENTER",side=="left" and -2 or 2,-1)
    a.shadow:Hide()
    a.backing=Solid(root,"BACKGROUND",MAT.recessLift); a.backing:SetSize(shape.plate+22,68); a.backing:SetPoint("CENTER",root,"CENTER",side=="left" and -5 or 5,0); a.backing:SetAlpha(.92)
    a.mass=Solid(root,"ARTWORK",MAT.ironLift); a.mass:SetSize(shape.plate,58); a.mass:SetPoint("CENTER",root,"CENTER",side=="left" and -3 or 3,0)
    a.massInset=Solid(root,"ARTWORK",MAT.recessLift); a.massInset:SetSize(shape.plate-38,42); a.massInset:SetPoint("CENTER",a.mass,"CENTER",side=="left" and 10 or -10,0)
    a.topRib=Solid(root,"ARTWORK",MAT.ironEdge); a.topRib:SetSize(shape.plate-48,7); a.topRib:SetPoint(side=="left" and "TOPLEFT" or "TOPRIGHT",a.mass,side=="left" and "TOPLEFT" or "TOPRIGHT",side=="left" and 30 or -30,6)
    a.lowerRib=Solid(root,"ARTWORK",MAT.iron); a.lowerRib:SetSize(shape.plate-72,8); a.lowerRib:SetPoint(side=="left" and "BOTTOMRIGHT" or "BOTTOMLEFT",a.mass,side=="left" and "BOTTOMRIGHT" or "BOTTOMLEFT",side=="left" and 8 or -8,-5)
    a.breakTop=Solid(root,"ARTWORK",MAT.ironEdge); a.breakTop:SetSize(34,11); a.breakTop:SetPoint(side=="left" and "TOPRIGHT" or "TOPLEFT",a.mass,side=="left" and "TOPRIGHT" or "TOPLEFT",side=="left" and 12 or -12,2)
    a.breakBottom=Solid(root,"ARTWORK",MAT.bronzeSeat); a.breakBottom:SetSize(52,8); a.breakBottom:SetPoint(side=="left" and "BOTTOMLEFT" or "BOTTOMRIGHT",a.mass,side=="left" and "BOTTOMLEFT" or "BOTTOMRIGHT",side=="left" and 18 or -18,-2); a.breakBottom:SetAlpha(.76)
    a.shoulder=Solid(root,"ARTWORK",MAT.iron); a.shoulder:SetSize(76,78); a.shoulder:SetPoint(side=="left" and "LEFT" or "RIGHT",a.mass,side=="left" and "LEFT" or "RIGHT",side=="left" and -20 or 20,0)
    a.socketSeat=Solid(root,"ARTWORK",MAT.bronzeSeat); a.socketSeat:SetSize(58,58); a.socketSeat:SetPoint("CENTER",a.shoulder,"CENTER",0,0); a.socketSeat:SetAlpha(.68)
    a.socketFrame=root:CreateTexture(nil,"ARTWORK"); a.socketFrame:SetTexture("Interface\\Buttons\\UI-Quickslot2"); a.socketFrame:SetSize(60,60); a.socketFrame:SetPoint("CENTER",a.socketSeat,"CENTER",0,0); a.socketFrame:SetVertexColor(.44,.34,.20,.96)
    a.rune=root:CreateTexture(nil,"ARTWORK"); a.rune:SetTexture(meta.icon); a.rune:SetTexCoord(.10,.90,.10,.90); a.rune:SetSize(40,40); a.rune:SetPoint("CENTER",a.socketSeat,"CENTER",0,0); a.rune:SetVertexColor(.64,.58,.70,.78)
    a.wake=Solid(root,"OVERLAY",VIOLET); a.wake:SetSize(43,43); a.wake:SetPoint("CENTER",a.rune,"CENTER",0,0); a.wake:SetAlpha(0.02)
    a.arm=Solid(root,"ARTWORK",MAT.ironLift); a.arm:SetSize(shape.arm,22); a.arm:SetPoint(side=="left" and "LEFT" or "RIGHT",a.mass,side=="left" and "RIGHT" or "LEFT",side=="left" and -8 or 8,shape.armY)
    a.armInset=Solid(root,"ARTWORK",MAT.bronzeSeat); a.armInset:SetSize(shape.arm-18,8); a.armInset:SetPoint("CENTER",a.arm,"CENTER",0,0); a.armInset:SetAlpha(.82)
    a.elbow=Solid(root,"ARTWORK",MAT.ironEdge); a.elbow:SetSize(28,34); a.elbow:SetPoint(side=="left" and "RIGHT" or "LEFT",a.arm,side=="left" and "RIGHT" or "LEFT",side=="left" and 5 or -5,0)
    a.pin=root:CreateTexture(nil,"OVERLAY"); a.pin:SetTexture("Interface\\Buttons\\UI-Quickslot2"); a.pin:SetSize(24,24); a.pin:SetPoint("CENTER",a.elbow,"CENTER",0,0); a.pin:SetVertexColor(.46,.35,.19,.92)
    a.engageBed=Solid(root,"OVERLAY",MAT.violetDark); a.engageBed:SetSize(shape.arm-10,10); a.engageBed:SetPoint("CENTER",a.arm,"CENTER",0,0); a.engageBed:SetAlpha(.12)
    a.engage=Solid(root,"OVERLAY",VIOLET); a.engage:SetSize(shape.arm-20,3); a.engage:SetPoint("CENTER",a.arm,"CENTER",0,0); a.engage:SetAlpha(0)
    a.couplingRib=Solid(root,"OVERLAY",MAT.bronzeEdge); a.couplingRib:SetSize(18,3); a.couplingRib:SetPoint("CENTER",a.elbow,"CENTER",0,0); a.couplingRib:SetAlpha(.72)
    a.topRib:Hide(); a.lowerRib:Hide(); a.breakTop:Hide(); a.breakBottom:Hide(); a.socketSeat:Hide(); a.armInset:Hide(); a.couplingRib:Hide()
    a.primaryJaw=Solid(root,"OVERLAY",Theme.colors.bronzeBright); a.primaryJaw:SetSize(7,54); a.primaryJaw:SetPoint(side=="left" and "LEFT" or "RIGHT",a.shoulder,side=="left" and "LEFT" or "RIGHT",side=="left" and -2 or 2,0); a.primaryJaw:SetAlpha(0)
    a.primaryCap=Solid(root,"OVERLAY",MAT.bronzeEdge); a.primaryCap:SetSize(44,5); a.primaryCap:SetPoint("TOP",a.shoulder,"TOP",0,3); a.primaryCap:SetAlpha(0)
    a.focusA=Solid(root,"OVERLAY",Theme.colors.text); a.focusA:SetSize(20,3); a.focusA:SetPoint("TOPLEFT",a.mass,"TOPLEFT",8,-5); a.focusA:SetAlpha(0)
    a.focusB=Solid(root,"OVERLAY",Theme.colors.text); a.focusB:SetSize(20,3); a.focusB:SetPoint("BOTTOMRIGHT",a.mass,"BOTTOMRIGHT",-8,5); a.focusB:SetAlpha(0)
    local textPoint=side=="left" and "LEFT" or "RIGHT"; local textX=side=="left" and 64 or -64; local justify=side=="left" and "LEFT" or "RIGHT"
    a.name=Label(root,meta.name,Theme.fonts.monument,18,Theme.colors.text,textPoint,a.mass,textPoint,textX,15,142,justify)
    a.rankText=Label(root,"RANK 0 / 3",Theme.fonts.readable,10,Theme.colors.textMuted,textPoint,a.mass,textPoint,textX,-7,142,justify)
    a.roleText=Label(root,"UNSET  /  +0.0%",Theme.fonts.readable,9,Theme.colors.textMuted,textPoint,a.mass,textPoint,textX,-25,142,justify)
    a.rankTabs={}
    for rank=1,3 do
        local tab=Solid(root,"OVERLAY",MAT.bronzeSeat); tab:SetSize(18,4)
        tab:SetPoint(side=="left" and "BOTTOMLEFT" or "BOTTOMRIGHT",a.mass,side=="left" and "BOTTOMLEFT" or "BOTTOMRIGHT",side=="left" and (63+((rank-1)*23)) or -(63+((rank-1)*23)),2)
        tab:SetAlpha(.14); a.rankTabs[rank]=tab
    end
    function a:Refresh()
        local awake=self.focused or self.hovered; self.backing:SetAlpha(self.selected and 1 or (awake and .98 or .88)); self.mass:SetAlpha(self.selected and 1 or (awake and .96 or .88)); self.massInset:SetAlpha(self.selected and .98 or (awake and .90 or .80)); self.shoulder:SetAlpha(self.primary and 1 or (awake and .96 or .86)); self.arm:SetAlpha(self.selected and 1 or (awake and .96 or .84)); self.elbow:SetAlpha(self.selected and 1 or (awake and .96 or .88))
        self.wake:SetAlpha(self.selected and .26 or (awake and .15 or (self.rank>0 and .08 or .03))); self.engageBed:SetAlpha(self.selected and .92 or (awake and .38 or .20)); self.engage:SetAlpha(self.selected and 1 or (awake and .38 or 0)); self.primaryJaw:SetAlpha(self.primary and .94 or 0); self.primaryCap:SetAlpha(self.primary and .88 or 0)
        self.focusA:SetAlpha(self.focused and .94 or 0); self.focusB:SetAlpha(self.focused and .94 or 0); self.rune:SetVertexColor(self.selected and .88 or (awake and .76 or .62),self.selected and .67 or .58,self.selected and .96 or .72,1); self.socketFrame:SetVertexColor(self.primary and .72 or .44,self.primary and .51 or .34,self.primary and .22 or .20,1)
        self.name:SetTextColor(unpack(self.selected and VIOLET_PALE or Theme.colors.text))
        for rank,tab in ipairs(self.rankTabs) do
            if rank>self.maxRank then tab:SetAlpha(0)
            elseif rank<=self.rank then Theme:SetTextureColor(tab,self.primary and Theme.colors.bronzeBright or VIOLET_PALE); tab:SetAlpha(.88)
            else Theme:SetTextureColor(tab,MAT.bronzeSeat); tab:SetAlpha(.32) end
        end
    end
    function a:SetFocused(v) self.focused=v==true; self:Refresh() end
    function a:SetEnabled(v) self.enabled=v~=false; root:EnableMouse(self.enabled); self:Refresh() end
    function a:SetSelected(v) self.selected=v==true; self:Refresh() end
    function a:SetData(data)
        data=data or {}; self.rank=tonumber(data.rank) or 0; self.maxRank=tonumber(data.maxRank) or 0; self.role=data.role or "UNSET"; self.primary=self.role=="PRIMARY"
        self.rankText:SetText(self.maxRank>0 and ("RANK "..self.rank.." / "..self.maxRank) or "RANK -"); self.roleText:SetText(self.role.."  /  +"..Pct(data.bonus)); self.roleText:SetTextColor(unpack(self.primary and Theme.colors.bronzeBright or (self.rank>0 and VIOLET_PALE or Theme.colors.textMuted))); self:Refresh()
    end
    function a:ShowTooltip()
        GameTooltip:SetOwner(self.root,side=="left" and "ANCHOR_RIGHT" or "ANCHOR_LEFT"); GameTooltip:ClearLines(); GameTooltip:AddLine(meta.name.." TALENT ANCHOR",.88,.82,.68)
        if self.role=="PRIMARY" then GameTooltip:AddLine("Primary: the dominant invested stat. Its brace supports the Primary rank capacity.",.82,.62,.27,true)
        elseif self.role=="SECONDARY" then GameTooltip:AddLine("Secondary: independently investable and supported by the shared specialization brace.",.80,.66,.96,true)
        else GameTooltip:AddLine("Dormant and available. Your first investment establishes a Primary anchor.",.72,.72,.72,true) end
        GameTooltip:AddLine("Rank capacity and projected amplification are read from the Worldsoul before investment.",.58,.58,.58,true); GameTooltip:AddLine("Investment is permanent.",.70,.82,.94,true); GameTooltip:Show()
    end
    function a:Activate(source) if not self.enabled then return false end; Screen:SelectAnchor(self.index,source); return true end
    root:SetScript("OnEnter",function() a.hovered=true; a:Refresh(); a:ShowTooltip() end); root:SetScript("OnLeave",function() a.hovered=false; a:Refresh(); GameTooltip:Hide() end)
    root:SetScript("OnMouseDown",function(_,button) if button=="LeftButton" then a.mass:ClearAllPoints(); a.mass:SetPoint("CENTER",root,"CENTER",side=="left" and -3 or 3,-2) end end)
    root:SetScript("OnMouseUp",function(_,button) a.mass:ClearAllPoints(); a.mass:SetPoint("CENTER",root,"CENTER",side=="left" and -3 or 3,0); if button=="LeftButton" then a:Activate("mouse") end end); a:Refresh(); return a
end

local positions={{0,"left",142,156},{1,"left",232,332},{2,"left",138,532},{3,"right",1206,208},{4,"right",1118,500}}
for _,p in ipairs(positions) do local a=CreateAnchor(p[1],p[2]); a.root:SetPoint("TOPLEFT",frame,"TOPLEFT",p[3],-p[4]); Screen.anchors[p[1]]=a end

-- The shared specialization joint is a stack of independently retained bays,
-- not one modal rectangle. Unequal clamps make the center read as the point at
-- which all five articulated supports are seated.
local chamber=CreateFrame("Frame",nil,frame); chamber:SetSize(564,698); chamber:SetPoint("TOP",frame,"TOP",2,-122); Screen.chamber=chamber
local bodyShadow=Solid(chamber,"BACKGROUND",{0.002,0.003,0.005,.62}); bodyShadow:SetSize(520,624); bodyShadow:SetPoint("TOP",chamber,"TOP",0,-22)
-- CONTROLLED TEST CANDIDATE (single variable): bodyShadow was never neutralized or
-- given a fabricated replacement, unlike identity/preview/truth in this same chamber
-- (all three hidden and replaced by TAL_* art). It shows through in four gaps between
-- the fabricated slabs stacked above it (34px/26px/18px/75px bands, none containing
-- text), reading as one continuous generic dark rectangle down the center column.
-- Hidden here as the sole change under test; nothing else in this file touched.
bodyShadow:Hide()
-- Full Visual Fabrication: tal-center-retainer-left/right (confirmed static).
local retainerLeftArt=chamber:CreateTexture(nil,"ARTWORK"); retainerLeftArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\TAL_CENTER_RETAINER_LEFT"); retainerLeftArt:SetSize(20,548); retainerLeftArt:SetPoint("LEFT",chamber,"LEFT",2,-2); retainerLeftArt:SetTexCoord(0,20/32,0,548/1024)
local retainerRightArt=chamber:CreateTexture(nil,"ARTWORK"); retainerRightArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\TAL_CENTER_RETAINER_RIGHT"); retainerRightArt:SetSize(15,472); retainerRightArt:SetPoint("RIGHT",chamber,"RIGHT",-2,-12); retainerRightArt:SetTexCoord(15/16,0,0,472/512)
local retainL=Solid(chamber,"ARTWORK",MAT.ironLift); retainL:SetSize(20,548); retainL:SetPoint("LEFT",chamber,"LEFT",2,-2)
local retainLSeat=Solid(chamber,"ARTWORK",MAT.bronzeSeat); retainLSeat:SetSize(6,462); retainLSeat:SetPoint("CENTER",retainL,"CENTER",3,-5); retainLSeat:SetAlpha(.82)
local retainR=Solid(chamber,"ARTWORK",MAT.iron); retainR:SetSize(15,472); retainR:SetPoint("RIGHT",chamber,"RIGHT",-2,-12)
local retainRSeat=Solid(chamber,"ARTWORK",MAT.bronzeSeat); retainRSeat:SetSize(4,382); retainRSeat:SetPoint("CENTER",retainR,"CENTER",-3,0); retainRSeat:SetAlpha(.72)
retainL:Hide(); retainLSeat:Hide(); retainR:Hide(); retainRSeat:Hide()
local contourLT=Solid(chamber,"ARTWORK",MAT.ironLift); contourLT:SetSize(74,18); contourLT:SetPoint("TOPLEFT",chamber,"TOPLEFT",4,-42)
local contourLTSeat=Solid(chamber,"OVERLAY",MAT.bronzeEdge); contourLTSeat:SetSize(44,3); contourLTSeat:SetPoint("CENTER",contourLT,"CENTER",8,0); contourLTSeat:SetAlpha(.70)
local contourLB=Solid(chamber,"ARTWORK",MAT.ironEdge); contourLB:SetSize(96,17); contourLB:SetPoint("BOTTOMLEFT",chamber,"BOTTOMLEFT",5,78)
local contourRT=Solid(chamber,"ARTWORK",MAT.ironEdge); contourRT:SetSize(62,21); contourRT:SetPoint("TOPRIGHT",chamber,"TOPRIGHT",-4,-65)
local contourRB=Solid(chamber,"ARTWORK",MAT.ironLift); contourRB:SetSize(112,16); contourRB:SetPoint("BOTTOMRIGHT",chamber,"BOTTOMRIGHT",-3,104)
contourLT:Hide(); contourLTSeat:Hide(); contourLB:Hide(); contourRT:Hide(); contourRB:Hide()
local topMass=Solid(chamber,"ARTWORK",MAT.iron); topMass:SetSize(372,12); topMass:SetPoint("TOP",chamber,"TOP",-25,0)
local topMassSeam=Solid(chamber,"OVERLAY",MAT.bronzeEdge); topMassSeam:SetSize(292,2); topMassSeam:SetPoint("CENTER",topMass,"CENTER",-8,0); topMassSeam:SetAlpha(.80)
local topLock=Solid(chamber,"ARTWORK",MAT.ironLift); topLock:SetSize(94,32); topLock:SetPoint("TOPLEFT",chamber,"TOPLEFT",20,-18); topLock:Hide()
local topLockCap=chamber:CreateTexture(nil,"ARTWORK"); topLockCap:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\TalentsTopLockCap"); topLockCap:SetSize(94,32); topLockCap:SetPoint("TOPLEFT",chamber,"TOPLEFT",20,-18); topLockCap:SetTexCoord(0,0.734375,0,1.0); topLockCap:SetAlpha(1.0)
local topLockSeat=Solid(chamber,"ARTWORK",MAT.bronzeSeat); topLockSeat:SetSize(58,9); topLockSeat:SetPoint("BOTTOM",topLock,"BOTTOM",8,0); topLockSeat:SetAlpha(.66)
local topRight=Solid(chamber,"ARTWORK",MAT.ironEdge); topRight:SetSize(78,24); topRight:SetPoint("TOPRIGHT",chamber,"TOPRIGHT",-17,-30); topRight:Hide()
local topRightCap=chamber:CreateTexture(nil,"ARTWORK"); topRightCap:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\TalentsTopRightCap"); topRightCap:SetSize(78,24); topRightCap:SetPoint("TOPRIGHT",chamber,"TOPRIGHT",-17,-30); topRightCap:SetTexCoord(0,0.609375,0,0.75); topRightCap:SetAlpha(1.0)
local bottomMass=Solid(chamber,"ARTWORK",MAT.ironLift); bottomMass:SetSize(398,11); bottomMass:SetPoint("BOTTOM",chamber,"BOTTOM",18,0)
local bottomLock=Solid(chamber,"ARTWORK",MAT.iron); bottomLock:SetSize(102,23); bottomLock:SetPoint("BOTTOMRIGHT",chamber,"BOTTOMRIGHT",-16,7)
local selectedJointBed=Solid(chamber,"OVERLAY",MAT.violetDark); selectedJointBed:SetSize(21,100); selectedJointBed:SetPoint("LEFT",chamber,"LEFT",15,174); selectedJointBed:SetAlpha(.94); Screen.selectedJointBed=selectedJointBed
local selectedJoint=Solid(chamber,"OVERLAY",VIOLET); selectedJoint:SetSize(5,76); selectedJoint:SetPoint("CENTER",selectedJointBed,"CENTER",0,0); selectedJoint:SetAlpha(1); Screen.selectedJoint=selectedJoint
local selectedPin=chamber:CreateTexture(nil,"OVERLAY"); selectedPin:SetTexture("Interface\\Buttons\\UI-Quickslot2"); selectedPin:SetSize(26,26); selectedPin:SetPoint("CENTER",selectedJointBed,"CENTER",0,0); selectedPin:SetVertexColor(.58,.34,.80,.92); Screen.selectedPin=selectedPin

-- Full Visual Fabrication: tal-selected-analysis-recess replaces identity and all
-- its static caps/locks/edges.
local analysisRecess=chamber:CreateTexture(nil,"ARTWORK"); analysisRecess:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\TAL_SELECTED_ANALYSIS_RECESS"); analysisRecess:SetPoint("TOP",chamber,"TOP",0,-56); analysisRecess:SetSize(468,138); analysisRecess:SetTexCoord(0,468/512,0,138/256)
local identity=Solid(chamber,"ARTWORK",MAT.recess); identity:SetSize(468,138); identity:SetPoint("TOP",chamber,"TOP",0,-56)
local identityCapL=Solid(chamber,"ARTWORK",MAT.ironLift); identityCapL:SetSize(118,14); identityCapL:SetPoint("TOPLEFT",identity,"TOPLEFT",-15,8)
local identityCapR=Solid(chamber,"ARTWORK",MAT.ironEdge); identityCapR:SetSize(76,10); identityCapR:SetPoint("TOPRIGHT",identity,"TOPRIGHT",12,2)
local identityFoot=Solid(chamber,"ARTWORK",MAT.iron); identityFoot:SetSize(326,10); identityFoot:SetPoint("BOTTOMRIGHT",identity,"BOTTOMRIGHT",13,-5)
local identityEdgeBed=Solid(chamber,"OVERLAY",MAT.bronzeSeat); identityEdgeBed:SetSize(408,6); identityEdgeBed:SetPoint("TOP",identity,"TOP",-7,1); identityEdgeBed:SetAlpha(.70)
local identityEdge=Solid(chamber,"OVERLAY",MAT.violetDark); identityEdge:SetSize(390,2); identityEdge:SetPoint("CENTER",identityEdgeBed,"CENTER",0,0); identityEdge:SetAlpha(.94)
local identityLockL=Solid(chamber,"ARTWORK",MAT.ironEdge); identityLockL:SetSize(22,54); identityLockL:SetPoint("BOTTOMLEFT",identity,"BOTTOMLEFT",-8,6)
local identityLockR=Solid(chamber,"ARTWORK",MAT.ironLift); identityLockR:SetSize(30,38); identityLockR:SetPoint("TOPRIGHT",identity,"TOPRIGHT",10,-18)
identity:Hide(); identityCapL:Hide(); identityCapR:Hide(); identityFoot:Hide(); identityEdgeBed:Hide(); identityEdge:Hide(); identityLockL:Hide(); identityLockR:Hide()
Screen.detailRole=Label(chamber,"UNSET ANCHOR",Theme.fonts.readable,9,Theme.colors.textMuted,"TOPLEFT",identity,"TOPLEFT",25,-20)
Screen.detailName=Label(chamber,"STRENGTH",Theme.fonts.monument,29,Theme.colors.text,"TOPLEFT",identity,"TOPLEFT",24,-42,440)
Screen.detailRank=Label(chamber,"RANK 0 / 3",Theme.fonts.readable,11,Theme.colors.textMuted,"TOPLEFT",identity,"TOPLEFT",26,-83,220)
Screen.detailBonus=Label(chamber,"CURRENT AMPLIFIER  +0.0%",Theme.fonts.readable,11,VIOLET_PALE,"TOPRIGHT",identity,"TOPRIGHT",-26,-83,230,"RIGHT")
Label(chamber,"Each anchor amplifies one retained main stat. Investment is permanent.",Theme.fonts.readable,9,Theme.colors.textMuted,"BOTTOM",identity,"BOTTOM",0,20,420,"CENTER")

local previewBraceL=Solid(chamber,"ARTWORK",MAT.ironLift); previewBraceL:SetSize(52,26); previewBraceL:SetPoint("TOPLEFT",identity,"BOTTOMLEFT",-11,-16)
local previewBraceR=Solid(chamber,"ARTWORK",MAT.iron); previewBraceR:SetSize(76,20); previewBraceR:SetPoint("TOPRIGHT",identity,"BOTTOMRIGHT",13,-22)
-- Full Visual Fabrication: tal-next-rank-mechanism replaces preview and its static
-- caps/locks/transfer-bed/efficiency-bed. NOTE (residual-scaffold watch item):
-- previewBraceL/R (small struts bridging identity->preview) are not named in the
-- package's neutralize list and are confirmed static but left native per the
-- additive/preserve-unless-named principle -- they sit in the 26px gap between
-- analysisRecess and this mechanism and may or may not be visually covered by the
-- new art; flagged for the live walk.
local nextRankMechanism=chamber:CreateTexture(nil,"ARTWORK"); nextRankMechanism:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\TAL_NEXT_RANK_MECHANISM"); nextRankMechanism:SetPoint("TOP",identity,"BOTTOM",0,-26); nextRankMechanism:SetSize(488,208); nextRankMechanism:SetTexCoord(0,488/512,0,208/256)
local preview=Solid(chamber,"ARTWORK",MAT.recessLift); preview:SetSize(488,208); preview:SetPoint("TOP",identity,"BOTTOM",0,-26); Screen.previewWell=preview
local previewTop=Solid(chamber,"ARTWORK",MAT.iron); previewTop:SetSize(344,9); previewTop:SetPoint("TOPLEFT",preview,"TOPLEFT",-9,4)
local previewBottom=Solid(chamber,"ARTWORK",MAT.ironEdge); previewBottom:SetSize(372,9); previewBottom:SetPoint("BOTTOMRIGHT",preview,"BOTTOMRIGHT",10,-4)
local previewTopSeat=Solid(chamber,"OVERLAY",MAT.bronzeEdge); previewTopSeat:SetSize(246,2); previewTopSeat:SetPoint("CENTER",previewTop,"CENTER",18,0); previewTopSeat:SetAlpha(.76)
local previewLockTR=Solid(chamber,"ARTWORK",MAT.ironLift); previewLockTR:SetSize(54,22); previewLockTR:SetPoint("TOPRIGHT",preview,"TOPRIGHT",12,8)
local previewLockBL=Solid(chamber,"ARTWORK",MAT.ironEdge); previewLockBL:SetSize(46,27); previewLockBL:SetPoint("BOTTOMLEFT",preview,"BOTTOMLEFT",-9,-8)
local previewEdgeBed=Solid(chamber,"OVERLAY",MAT.violetDark); previewEdgeBed:SetSize(13,168); previewEdgeBed:SetPoint("LEFT",preview,"LEFT",0,0); previewEdgeBed:SetAlpha(.78)
preview:Hide(); previewTop:Hide(); previewBottom:Hide(); previewTopSeat:Hide(); previewLockTR:Hide(); previewLockBL:Hide(); previewEdgeBed:Hide()
local previewEdge=Solid(chamber,"OVERLAY",VIOLET); previewEdge:SetSize(3,136); previewEdge:SetPoint("CENTER",previewEdgeBed,"CENTER",0,0); previewEdge:SetAlpha(.62)
Screen.previewEdge=previewEdge
Screen.previewTitle=Label(chamber,"NEXT RANK PREVIEW",Theme.fonts.readable,9,Theme.colors.textMuted,"TOPLEFT",preview,"TOPLEFT",24,-19)
Label(chamber,"CURRENT",Theme.fonts.readable,8,Theme.colors.disabled,"TOPLEFT",preview,"TOPLEFT",25,-52)
Label(chamber,"AFTER INVESTMENT",Theme.fonts.readable,8,Theme.colors.disabled,"TOPRIGHT",preview,"TOPRIGHT",-25,-52)
Screen.currentValue=Label(chamber,"+0.0%",Theme.fonts.monument,24,Theme.colors.textMuted,"TOPLEFT",preview,"TOPLEFT",24,-72,150)
Screen.projectedValue=Label(chamber,"READING",Theme.fonts.monument,24,VIOLET_PALE,"TOPRIGHT",preview,"TOPRIGHT",-24,-72,190,"RIGHT")
local transferBed=Solid(chamber,"ARTWORK",MAT.ironLift); transferBed:SetSize(150,15); transferBed:SetPoint("CENTER",preview,"CENTER",0,22)
local transferSeat=Solid(chamber,"OVERLAY",MAT.bronzeSeat); transferSeat:SetSize(118,7); transferSeat:SetPoint("CENTER",transferBed,"CENTER",0,0); transferSeat:SetAlpha(.82)
transferBed:Hide(); transferSeat:Hide()
local transferLine=Solid(chamber,"OVERLAY",VIOLET); transferLine:SetSize(92,3); transferLine:SetPoint("CENTER",transferBed,"CENTER",0,0); transferLine:SetAlpha(.64); Screen.transferLine=transferLine
Screen.transferLabel=Label(chamber,"NEXT",Theme.fonts.readable,8,VIOLET_PALE,"CENTER",transferBed,"CENTER",0,14,72,"CENTER")
Screen.roleTransition=Label(chamber,"Select an anchor to read its next retained state.",Theme.fonts.readable,10,Theme.colors.textMuted,"TOP",preview,"TOP",0,-116,458,"CENTER")
Screen.efficiency=Label(chamber,"CONCENTRATION EFFICIENCY  100.0%",Theme.fonts.readable,10,Theme.colors.text,"TOPLEFT",preview,"TOPLEFT",24,-151,466)
Screen.distinct=Label(chamber,"0 DISTINCT ANCHORS",Theme.fonts.readable,8,Theme.colors.textMuted,"BOTTOMLEFT",preview,"BOTTOMLEFT",24,17,220)
Screen.cost=Label(chamber,"COST  -",Theme.fonts.monument,13,Theme.colors.bronzeBright,"BOTTOMRIGHT",preview,"BOTTOMRIGHT",-24,14,190,"RIGHT")
local efficiencySeat=Solid(chamber,"ARTWORK",MAT.bronzeSeat); efficiencySeat:SetSize(292,3); efficiencySeat:SetPoint("TOPLEFT",preview,"TOPLEFT",24,-170); efficiencySeat:SetAlpha(.48)
efficiencySeat:Hide()
local efficiencyTension=Solid(chamber,"OVERLAY",VIOLET); efficiencyTension:SetSize(116,3); efficiencyTension:SetPoint("LEFT",efficiencySeat,"LEFT",0,0); efficiencyTension:SetAlpha(.34); Screen.efficiencyTension=efficiencyTension

local efficiencyHit=CreateFrame("Frame",nil,chamber); efficiencyHit:SetSize(458,27); efficiencyHit:SetPoint("TOPLEFT",preview,"TOPLEFT",18,-140); efficiencyHit:EnableMouse(true)
efficiencyHit:SetScript("OnEnter",function()
    GameTooltip:SetOwner(efficiencyHit,"ANCHOR_RIGHT"); GameTooltip:ClearLines(); GameTooltip:AddLine("CONCENTRATION EFFICIENCY",.88,.82,.68); GameTooltip:AddLine("Investing across additional stat anchors spreads the specialization brace's amplification. The displayed efficiency is the current Worldsoul result.",.72,.72,.72,true); GameTooltip:Show()
end)
efficiencyHit:SetScript("OnLeave",function() GameTooltip:Hide() end); Screen.efficiencyHit=efficiencyHit

-- Full Visual Fabrication: tal-essence-reservoir replaces truth/truthBridge/
-- truthJaw/supplyLineBed. The cyan lines (truthBridgeSeat/truthJawSeat/supplyLine)
-- are explicitly named "native live feed trace" by the package and kept native.
local essenceReservoirArt=chamber:CreateTexture(nil,"ARTWORK"); essenceReservoirArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\TAL_ESSENCE_RESERVOIR"); essenceReservoirArt:SetPoint("TOP",preview,"BOTTOM",0,-18); essenceReservoirArt:SetSize(456,76); essenceReservoirArt:SetTexCoord(0,456/512,0,76/128)
local truth=Solid(chamber,"ARTWORK",MAT.recess); truth:SetSize(456,76); truth:SetPoint("TOP",preview,"BOTTOM",0,-18)
local truthBridge=Solid(chamber,"ARTWORK",MAT.ironLift); truthBridge:SetSize(118,12); truthBridge:SetPoint("TOPLEFT",truth,"TOPLEFT",36,6); Screen.truthBridge=truthBridge
local truthBridgeSeat=Solid(chamber,"OVERLAY",Theme.colors.worldsoul); truthBridgeSeat:SetSize(74,2); truthBridgeSeat:SetPoint("CENTER",truthBridge,"CENTER",8,0); truthBridgeSeat:SetAlpha(.62)
local truthJaw=Solid(chamber,"ARTWORK",MAT.ironLift); truthJaw:SetSize(28,76); truthJaw:SetPoint("LEFT",truth,"LEFT",0,0)
local truthJawSeat=Solid(chamber,"OVERLAY",Theme.colors.worldsoul); truthJawSeat:SetSize(5,50); truthJawSeat:SetPoint("CENTER",truthJaw,"CENTER",3,0); truthJawSeat:SetAlpha(.58)
local essenceSocket=chamber:CreateTexture(nil,"ARTWORK"); essenceSocket:SetTexture("Interface\\Buttons\\UI-Quickslot2"); essenceSocket:SetSize(40,40); essenceSocket:SetPoint("LEFT",truth,"LEFT",17,0); essenceSocket:SetVertexColor(.34,.65,.82,.92)
local essenceRune=chamber:CreateTexture(nil,"OVERLAY"); essenceRune:SetTexture("Interface\\Icons\\INV_Misc_Gem_Sapphire_02"); essenceRune:SetTexCoord(.12,.88,.12,.88); essenceRune:SetSize(25,25); essenceRune:SetPoint("CENTER",essenceSocket,"CENTER",0,0); essenceRune:SetVertexColor(.60,.88,1,1)
Screen.essenceLabel=Label(chamber,"AVAILABLE ESSENCE",Theme.fonts.readable,8,Theme.colors.textMuted,"TOPLEFT",truth,"TOPLEFT",66,-17)
Screen.essenceValue=Label(chamber,"-",Theme.fonts.monument,19,Theme.colors.worldsoulPale,"BOTTOMLEFT",truth,"BOTTOMLEFT",65,15)
local supplyLineBed=Solid(chamber,"ARTWORK",MAT.ironLift); supplyLineBed:SetSize(104,11); supplyLineBed:SetPoint("RIGHT",truth,"RIGHT",-18,0)
truth:Hide(); truthBridge:Hide(); truthJaw:Hide(); supplyLineBed:Hide()
local supplyLine=Solid(chamber,"OVERLAY",Theme.colors.worldsoul); supplyLine:SetSize(72,3); supplyLine:SetPoint("CENTER",supplyLineBed,"CENTER",0,0); supplyLine:SetAlpha(.52)
Label(chamber,"Available resonance held by the shared brace.",Theme.fonts.readable,8,Theme.colors.textMuted,"RIGHT",truth,"RIGHT",-20,12,235,"RIGHT")
Label(chamber,"Additional anchors reduce concentration efficiency.",Theme.fonts.readable,8,Theme.colors.textMuted,"RIGHT",truth,"RIGHT",-20,-10,260,"RIGHT")

-- Full Visual Fabrication: tal-invest-actuator replaces actuatorBed/rail/spine/
-- feed/clamps. Screen.actuatorSpine is stored but never referenced again anywhere
-- in this file (confirmed by full-file read) -- effectively static despite the
-- Screen-level storage.
local investActuatorArt=chamber:CreateTexture(nil,"ARTWORK"); investActuatorArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\TAL_INVEST_ACTUATOR"); investActuatorArt:SetPoint("TOPLEFT",chamber,"TOPLEFT",55,-597); investActuatorArt:SetSize(454,106); investActuatorArt:SetTexCoord(0,454/512,0,106/128)
local actuatorBed=Solid(chamber,"ARTWORK",MAT.iron); actuatorBed:SetSize(454,18); actuatorBed:SetPoint("BOTTOM",chamber,"BOTTOM",0,80)
local actuatorRail=Solid(chamber,"OVERLAY",MAT.bronzeSeat); actuatorRail:SetSize(346,4); actuatorRail:SetPoint("CENTER",actuatorBed,"CENTER",0,0); actuatorRail:SetAlpha(.74)
local actuatorSpine=Solid(chamber,"ARTWORK",MAT.ironLift); actuatorSpine:SetSize(18,86); actuatorSpine:SetPoint("TOP",actuatorBed,"BOTTOM",-136,2); Screen.actuatorSpine=actuatorSpine
local actuatorSpineSeat=Solid(chamber,"OVERLAY",VIOLET); actuatorSpineSeat:SetSize(4,62); actuatorSpineSeat:SetPoint("CENTER",actuatorSpine,"CENTER",0,0); actuatorSpineSeat:SetAlpha(.50)
local actuatorFeed=Solid(chamber,"ARTWORK",MAT.ironEdge); actuatorFeed:SetSize(112,12); actuatorFeed:SetPoint("TOPRIGHT",actuatorBed,"BOTTOMRIGHT",-32,-22)
local actuatorFeedSeat=Solid(chamber,"OVERLAY",MAT.bronzeEdge); actuatorFeedSeat:SetSize(72,3); actuatorFeedSeat:SetPoint("CENTER",actuatorFeed,"CENTER",0,0); actuatorFeedSeat:SetAlpha(.72)
local actuatorClampL=Solid(chamber,"ARTWORK",MAT.ironLift); actuatorClampL:SetSize(58,54); actuatorClampL:SetPoint("BOTTOMLEFT",chamber,"BOTTOMLEFT",31,41)
local actuatorClampR=Solid(chamber,"ARTWORK",MAT.ironEdge); actuatorClampR:SetSize(74,46); actuatorClampR:SetPoint("BOTTOMRIGHT",chamber,"BOTTOMRIGHT",-24,45)
actuatorBed:Hide(); actuatorRail:Hide(); actuatorSpine:Hide(); actuatorSpineSeat:Hide(); actuatorFeed:Hide(); actuatorFeedSeat:Hide(); actuatorClampL:Hide(); actuatorClampR:Hide()
Screen.invest=UI.ProgressionRow:Create(chamber,{id="invest",width=380,height=62,icon=false,label="INVEST NEXT RANK",meta="Preview required",value="-",valueWidth=100,channelColor=MAT.recessLift,focusColor=VIOLET,accentColor=VIOLET,tooltip="Invest one permanent rank in the selected anchor after reviewing its projected amplification, role, cost, and concentration efficiency.",onActivate=function() Screen:Purchase() end})
Screen.invest.root:SetPoint("BOTTOM",chamber,"BOTTOM",0,39)
Screen.status=Label(chamber,"",Theme.fonts.readable,9,Theme.colors.textMuted,"BOTTOM",chamber,"BOTTOM",0,17,500,"CENTER")
Screen.footer=Label(frame,"FIVE INDEPENDENT ANCHORS  /  INVESTMENT IS PERMANENT",Theme.fonts.readable,8,Theme.colors.textMuted,"BOTTOM",frame,"BOTTOM",0,24,700,"CENTER")

local input=UI.InputManager:New(frame); Screen.input=input
for _,c in ipairs({Screen.back,Screen.home,Screen.close}) do input:Add(c,c.id) end
for index=0,4 do input:Add(Screen.anchors[index],"talent"..index) end; input:Add(Screen.invest,"invest")
input:SetNavigation({"back","home","close","talent0","talent1","talent2","talent3","talent4","invest"},{
    back={RIGHT="talent0",DOWN="talent0"},home={LEFT="talent3",RIGHT="close",DOWN="talent3"},close={LEFT="home",DOWN="talent3"},
    talent0={UP="back",DOWN="talent1",RIGHT="invest"},talent1={UP="talent0",DOWN="talent2",RIGHT="invest"},talent2={UP="talent1",RIGHT="invest"},
    talent3={UP="home",DOWN="talent4",LEFT="invest"},talent4={UP="talent3",LEFT="invest"},invest={LEFT="talent1",RIGHT="talent4",UP="talent3",DOWN="talent2"},
}); input.defaultFocusId="talent0"; input.onEscape=function() Screen:Leave("back") end

function Screen:ReadState(values)
    local ranks=ParseMap(values.talents,true); local roles=ParseMap(values.talent_role,false); local bonuses=ParseMap(values.talent_bonus_pct,true)
    local costs=ParseMap(values.talent_next_rank_cost,true); local nextBonuses=ParseMap(values.talent_next_bonus_pct,true); local maxima=ParseMap(values.talent_max_rank,true)
    self.hasTruth=values.talent_max_rank~=nil and values.talent_role~=nil; self.essence=tonumber(values.essence) or 0; self.primary=tonumber(values.talent_primary_stat); self.penalty=tonumber(values.talent_distinct_penalty_pct) or 100; self.distinctCount=tonumber(values.talent_distinct_stats) or 0; self.stats={}
    for index=0,4 do self.stats[index]={rank=ranks[index] or 0,role=roles[index] or "UNSET",bonus=bonuses[index] or 0,cost=costs[index] or 0,nextBonus=nextBonuses[index] or 0,maxRank=maxima[index] or 0} end
end

function Screen:PreviewForSelected() return self.previewCache[self.selected] end
function Screen:RefreshDetail()
    local data=self.stats and self.stats[self.selected] or {rank=0,role="UNSET",bonus=0,cost=0,nextBonus=0,maxRank=0}; local meta=META[self.selected]; local p=self:PreviewForSelected()
    self.detailRole:SetText((data.role=="PRIMARY" and "PRIMARY ANCHOR" or (data.role=="SECONDARY" and "SECONDARY ANCHOR" or "UNSET ANCHOR"))); self.detailRole:SetTextColor(unpack(data.role=="PRIMARY" and Theme.colors.bronzeBright or Theme.colors.textMuted)); self.detailName:SetText(meta.name); self.detailRank:SetText(data.maxRank>0 and ("RANK "..data.rank.." / "..data.maxRank) or "RANK -"); self.detailBonus:SetText("CURRENT AMPLIFIER  +"..Pct(data.bonus)); self.currentValue:SetText("+"..Pct(data.bonus)); self.essenceValue:SetText(FormatInt(self.essence)); self.distinct:SetText(self.distinctCount.." DISTINCT ANCHOR"..(self.distinctCount==1 and "" or "S"))
    if p then
        self.projectedValue:SetText("+"..Pct(p.projected_bonus_pct)); local oldPrimary=StatName(p.current_primary_stat); local newPrimary=StatName(p.projected_primary_stat); local oldRole=p.current_role or data.role; local newRole=p.projected_role or oldRole
        if oldPrimary~=newPrimary then self.roleTransition:SetText("PRIMARY SHIFTS  /  "..oldPrimary.."  TO  "..newPrimary)
        elseif oldRole~=newRole then self.roleTransition:SetText(oldRole.."  TO  "..newRole)
        else self.roleTransition:SetText(newRole.." RETAINED  /  RANK "..tostring(p.projected_rank or data.rank)) end
        self.efficiency:SetText("CONCENTRATION EFFICIENCY  "..Pct(p.current_penalty_pct).."  TO  "..Pct(p.projected_penalty_pct)); self.cost:SetText("COST  "..FormatInt(p.cost or data.cost)); self.transferLine:SetAlpha(1); self.previewEdge:SetAlpha(.84); self.efficiencyTension:SetWidth(math.max(34,116*((tonumber(p.projected_penalty_pct) or 100)/100))); self.efficiencyTension:SetAlpha(.62)
    else
        local maxed=data.maxRank>0 and data.rank>=data.maxRank; self.projectedValue:SetText(self.previewPending and "READING" or (maxed and "MAXIMUM" or (self.hasTruth and ("+"..Pct(data.nextBonus)) or "READING"))); self.roleTransition:SetText(self.previewPending and "The selected joint is reading the next rank..." or (maxed and "THIS ANCHOR IS FULLY SET" or "Select an anchor to read its next projected state.")); self.efficiency:SetText("CONCENTRATION EFFICIENCY  "..Pct(self.penalty)); self.cost:SetText(maxed and "FULLY SET" or (self.hasTruth and ("COST  "..FormatInt(data.cost)) or "COST  -")); self.transferLine:SetAlpha(self.previewPending and .48 or .30); self.previewEdge:SetAlpha(self.previewPending and .62 or .48); self.efficiencyTension:SetWidth(math.max(34,116*((tonumber(self.penalty) or 100)/100))); self.efficiencyTension:SetAlpha(.46)
    end
    self:RefreshInvest()
end

function Screen:RefreshInvest()
    local data=self.stats and self.stats[self.selected]; local p=self:PreviewForSelected(); local maxed=data and data.maxRank>0 and data.rank>=data.maxRank
    self.invest.value:SetText(maxed and "MAX" or FormatInt((p and p.cost) or (data and data.cost) or 0))
    if self.purchasePending then self.invest:SetPending(true); self.invest:SetEnabled(false); self.invest.label:SetText("RETAINING..."); self.invest.meta:SetText("THE BRACE IS COMMITTING")
    elseif maxed or (p and p.status=="MAX_RANK") then self.invest:SetPending(false); self.invest:SetEnabled(false); self.invest.label:SetText("ANCHOR FULLY SET"); self.invest.meta:SetText("NO FURTHER RANK AVAILABLE")
    elseif self.previewPending or not p then self.invest:SetPending(false); self.invest:SetEnabled(false); self.invest.label:SetText("INVEST NEXT RANK"); self.invest.meta:SetText("NEXT RANK PREVIEW REQUIRED")
    elseif tostring(p.affordable)=="0" then self.invest:SetPending(false); self.invest:SetEnabled(false); self.invest.label:SetText("INVEST NEXT RANK"); self.invest.meta:SetText("INSUFFICIENT ESSENCE")
    else self.invest:SetPending(false); self.invest:SetEnabled(true); self.invest.label:SetText("INVEST NEXT RANK"); self.invest.meta:SetText("PERMANENT  /  NO REFUND") end
end

function Screen:RequestPreview()
    if not self.active or self.purchasePending then return end; local index=self.selected; if self.previewCache[index] then self:RefreshDetail(); return end
    self.previewPending=true; self.previewToken=(self.previewToken or 0)+1; local token=self.previewToken; self:RefreshDetail()
    local elapsed=GetTime()-(self.lastPreviewSent or -10); local delay=math.max(0,1.05-elapsed)
    local function send() if not Screen.active or Screen.previewToken~=token then return end; Screen.lastPreviewSent=GetTime(); if not (APB and APB.RequestEchoesAction and APB:RequestEchoesAction("talent_preview",index)) then Screen.previewPending=false; Screen.status:SetText("Native preview unavailable; the gossip Talents route remains available."); Screen:RefreshDetail() end end
    if delay>0 then C_Timer.After(delay,send) else send() end
end

function Screen:SelectAnchor(index)
    if not META[index] then return end; local alreadySelected=self.selected==index; self.selected=index; for value,a in pairs(self.anchors) do a:SetSelected(value==index) end
    self.selectedJointBed:ClearAllPoints(); self.selectedJointBed:SetPoint(index<=2 and "LEFT" or "RIGHT",self.chamber,index<=2 and "LEFT" or "RIGHT",index<=2 and 18 or -18,({[0]=174,[1]=8,[2]=-180,[3]=132,[4]=-160})[index]); local data=self.stats and self.stats[index]; self.selectedPin:SetVertexColor(data and data.role=="PRIMARY" and .82 or .62,data and data.role=="PRIMARY" and .55 or .34,data and data.role=="PRIMARY" and .20 or .88,.98); self.status:SetText(alreadySelected and "This anchor is already selected." or ""); self.previewPending=false; self.previewToken=(self.previewToken or 0)+1; self:RefreshDetail(); self:RequestPreview()
end

function Screen:RefreshState(values)
    self:ReadState(values or {}); for index=0,4 do self.anchors[index]:SetData(self.stats[index]) end
    self.previewCache={}; self.previewPending=false; if self.primary and META[self.primary] and not META[self.selected] then self.selected=self.primary end; self:SelectAnchor(self.selected)
end

function Screen:WakeAnchor(index)
    local a=self.anchors[tonumber(index)]; if not a then return end; a.wake:SetAlpha(.62); a.engage:SetAlpha(1); if UI:IsReducedMotion() then a:Refresh(); a.wake:SetAlpha(.22); return end
    self.wakeToken=(self.wakeToken or 0)+1; local token=self.wakeToken; C_Timer.After(.18,function() if Screen.active and Screen.wakeToken==token then a.wake:SetAlpha(.38) end end); C_Timer.After(.42,function() if Screen.active and Screen.wakeToken==token then a:Refresh() end end)
end

function Screen:Purchase()
    local p=self:PreviewForSelected(); if self.purchasePending or not p or tostring(p.affordable)=="0" then return false end
    self.purchasePending=true; self.purchaseIndex=self.selected; self.status:SetText("The selected anchor is retaining this rank..."); self:WakeAnchor(self.selected); self:RefreshInvest(); if not APB:RequestEchoesAction("talent_purchase",self.selected) then self.purchasePending=false; self.status:SetText("Talent request could not be dispatched. Check the Worldsoul connection."); self:RefreshInvest(); UI:Trace("request.talent_purchase","ui","dispatch-failed"); return false end; UI:Trace("request.talent_purchase","ui","dispatched"); self.purchaseToken=(self.purchaseToken or 0)+1; local token=self.purchaseToken
    C_Timer.After(5,function() if Screen.active and Screen.purchasePending and Screen.purchaseToken==token then Screen.purchasePending=false; Screen.status:SetText("No response received. State is being read again."); Screen:RefreshInvest(); if APB.RequestEchoesState then APB:RequestEchoesState() end end end); return true
end

function Screen:OnAction(verb,fields)
    if not self.active then return end
    if verb=="ACTION_OK" and fields.action=="talent_preview" then self.previewPending=false; local index=tonumber(fields.stat_index); if index~=nil then self.previewCache[index]=fields end; self:RefreshDetail(); if index~=self.selected then self:RequestPreview() end
    elseif verb=="ACTION_OK" and fields.action=="talent_purchase" then self.purchasePending=false; self.purchaseToken=(self.purchaseToken or 0)+1; if fields.status=="SUCCESS" then self.status:SetText("The pattern takes hold. "..StatName(fields.stat_index).." is rank "..tostring(fields.new_rank).."."); self:WakeAnchor(fields.stat_index); self.previewCache={}; if APB.RequestEchoesState then APB:RequestEchoesState() end elseif fields.status=="INSUFFICIENT_ESSENCE" then self.status:SetText("Not enough Essence for this rank.") elseif fields.status=="MAX_RANK" then self.status:SetText("This anchor is already fully set.") else self.status:SetText("The anchor rejected this investment.") end; self:RefreshInvest()
    elseif verb=="ERROR" and (self.previewPending or self.purchasePending) then local wasPreview=self.previewPending; self.previewPending=false; self.purchasePending=false; self.purchaseToken=(self.purchaseToken or 0)+1; self.status:SetText(fields.code=="RATE_LIMITED" and "The brace is still settling; its reading will resume." or "Talents request unavailable."); self:RefreshDetail(); if wasPreview and fields.code=="RATE_LIMITED" then C_Timer.After(1.05,function() if Screen.active then Screen:RequestPreview() end end) end end
end

function Screen:UpdateScale() self.frame:SetScale(math.min((UIParent:GetWidth() or 1672)/1672,(UIParent:GetHeight() or 941)/941)) end
function Screen:Show()
    self.openToken=self.openToken+1; self.active=true; self:UpdateScale(); if APB and APB.C43 and APB.C43.frame then APB.C43.frame:Hide() end; self.frame:SetAlpha(UI:IsReducedMotion() and 1 or 0); self.frame:Show(); Animation:Alpha(self.frame,1,.22); self:RefreshState(UI.StateStore.values); self.input:SetFocusById("talent"..self.selected); if APB and APB.RequestEchoesState then APB:RequestEchoesState() end
end
function Screen:Hide() self.openToken=self.openToken+1; self.active=false; self.previewPending=false; self.purchasePending=false; self.previewToken=(self.previewToken or 0)+1; self.purchaseToken=(self.purchaseToken or 0)+1; self.wakeToken=(self.wakeToken or 0)+1; self.input:ClearFocus(); Animation:Stop(self.frame); self.frame:Hide() end
function Screen:Leave(destination) self:Hide(); local focusId=destination=="home" and "core" or "talents"; if UI.DashboardGateB and UI.ScreenManager:Show("dashboardGateB",false,focusId) then return end; UI.ScreenManager.current=nil; if APB and APB.C43 then APB.C43:Show() end end
function Screen:CloseCompanion() self:Hide(); UI.ScreenManager.current=nil; UI.ScreenManager.history={}; if APB and APB.C43 and APB.C43.Hide then APB.C43:Hide() end end

UI.StateStore:Subscribe(function(values) if Screen.active then Screen.purchasePending=false; Screen:RefreshState(values) end end)
if APB and APB.SubscribeEchoesActions then APB:SubscribeEchoesActions(function(verb,fields) Screen:OnAction(verb,fields) end) end
UI.TalentsScreen=Screen; UI.ScreenManager:Register("talents",Screen,false); UI.modules.TalentsScreen=true
