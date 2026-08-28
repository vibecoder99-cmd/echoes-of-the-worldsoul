local UI = EchoesUI
if not UI or not UI.ProgressionRow or not UI.ScreenManager then return end

local Theme = UI.Theme
local Animation = UI.AnimationController
local Screen = {id="threat",active=false,openToken=0,actionPending=false,level=0,maximum=10}

local function Solid(parent,layer,color)
    local texture=parent:CreateTexture(nil,layer)
    Theme:SetTextureColor(texture,color)
    return texture
end

local function Label(parent,text,font,size,color,point,relative,relativePoint,x,y,width,justify)
    local value=parent:CreateFontString(nil,"OVERLAY")
    value:SetFont(font,size, font==Theme.fonts.monument and "OUTLINE" or nil)
    value:SetText(text); value:SetTextColor(unpack(color)); value:SetPoint(point,relative,relativePoint,x,y)
    if width then value:SetWidth(width); value:SetJustifyH(justify or "LEFT") end
    return value
end

local frame=CreateFrame("Frame","EchoesUIWorldThreatScreen",UIParent)
frame:SetSize(1672,941); frame:SetPoint("CENTER",UIParent,"CENTER",0,0); frame:SetFrameStrata("DIALOG")
frame:EnableMouse(true); frame:Hide(); Screen.frame=frame

for row=0,1 do for column=0,3 do
    local tile=frame:CreateTexture(nil,"BACKGROUND")
    tile:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\C43_"..column..row)
    local width=column==3 and 136 or 512; local height=row==1 and 429 or 512
    tile:SetSize(width,height); tile:SetPoint("TOPLEFT",frame,"TOPLEFT",column*512,-(row*512))
    tile:SetTexCoord(0,width/512,0,height/512); tile:SetVertexColor(0.25,0.34,0.42,0.28)
end end
local veil=Solid(frame,"BACKGROUND",{0.006,0.010,0.015,0.74}); veil:SetAllPoints(frame)

-- Preserve the polished Work shell. World Threat identity is concentrated in
-- the opening and its instruments rather than imposed by giant outer rails.
local topRail=Solid(frame,"ARTWORK",Theme.colors.stoneLift); topRail:SetSize(1510,16); topRail:SetPoint("TOP",frame,"TOP",0,-87)
local leftRail=Solid(frame,"ARTWORK",Theme.colors.stoneLift); leftRail:SetSize(28,744); leftRail:SetPoint("TOPLEFT",frame,"TOPLEFT",42,-112)
local rightRail=Solid(frame,"ARTWORK",Theme.colors.stoneLift); rightRail:SetSize(28,744); rightRail:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-42,-112)
local outerPlates={}
for _,data in ipairs({{70,112,265,12},{70,844,510,14},{1092,844,510,14},{128,602,270,12},{1274,602,270,12}}) do
    local plate=Solid(frame,"ARTWORK",Theme.colors.bronzeDark); plate:SetSize(data[3],data[4]); plate:SetPoint("TOPLEFT",frame,"TOPLEFT",data[1],-data[2]); plate:SetAlpha(0.74)
    outerPlates[#outerPlates+1]=plate
end
-- Scaffold Eradication Sprint: cru-outer-top/side-rail replace topRail/leftRail/
-- rightRail/plates. NOTE: these were named for removal back in the True-Final
-- Material Resolve prune list but were never actually hidden (crownL/crownR were
-- correctly hidden at the time; these were missed) -- fixed here alongside the
-- new art rather than left as a further-compounding gap.
local outerTopRail=frame:CreateTexture(nil,"ARTWORK"); outerTopRail:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_OUTER_TOP_RAIL"); outerTopRail:SetSize(1510,16); outerTopRail:SetPoint("TOPLEFT",frame,"TOPLEFT",81,-87); outerTopRail:SetTexCoord(0,1510/2048,0,1.0)
local outerSideRailL=frame:CreateTexture(nil,"ARTWORK"); outerSideRailL:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_OUTER_SIDE_RAIL"); outerSideRailL:SetSize(28,744); outerSideRailL:SetPoint("TOPLEFT",frame,"TOPLEFT",42,-112); outerSideRailL:SetTexCoord(0,28/32,0,744/1024)
local outerSideRailR=frame:CreateTexture(nil,"ARTWORK"); outerSideRailR:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_OUTER_SIDE_RAIL"); outerSideRailR:SetSize(28,744); outerSideRailR:SetPoint("TOPLEFT",frame,"TOPLEFT",1602,-112); outerSideRailR:SetTexCoord(28/32,0,0,744/1024)
topRail:Hide(); leftRail:Hide(); rightRail:Hide(); for _,p in ipairs(outerPlates) do p:Hide() end

local crown=Solid(frame,"ARTWORK",Theme.colors.stone); crown:SetSize(570,66); crown:SetPoint("TOP",frame,"TOP",0,-17)
-- Scaffold Eradication Sprint: wt-title-crown replaces the flat crown fill.
-- crownL/crownR already hidden (True-Final Material Resolve pass).
local titleCrownArt=frame:CreateTexture(nil,"ARTWORK"); titleCrownArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_TITLE_CROWN"); titleCrownArt:SetAllPoints(crown); titleCrownArt:SetTexCoord(0,570/1024,0,66/128)
crown:Hide()
-- True-final material resolve: removed as redundant (Manifest/PRUNE-LISTS.md).
local crownL=Solid(frame,"ARTWORK",Theme.colors.stoneLift); crownL:SetSize(92,38); crownL:SetPoint("RIGHT",crown,"LEFT",22,0); crownL:Hide()
local crownR=Solid(frame,"ARTWORK",Theme.colors.stoneLift); crownR:SetSize(92,38); crownR:SetPoint("LEFT",crown,"RIGHT",-22,0); crownR:Hide()
local crownSeam=Solid(frame,"OVERLAY",Theme.colors.worldsoul); crownSeam:SetSize(392,2); crownSeam:SetPoint("TOP",crown,"BOTTOM",0,0); crownSeam:SetAlpha(0.56)
Label(frame,"WORLD THREAT",Theme.fonts.monument,27,Theme.colors.text,"CENTER",crown,"CENTER",0,7)
Label(frame,"WORLD-PRESSURE  ·  RESPONSE CONTROL",Theme.fonts.readable,11,Theme.colors.textMuted,"CENTER",crown,"CENTER",0,-17)

local function Place(control,x,y) control.root:SetPoint("TOPLEFT",frame,"TOPLEFT",x,-y); return control end
local back=Place(UI.ProgressionRow:Create(frame,{id="back",width=130,height=38,icon=false,compact=true,label="‹  BACK",onActivate=function() Screen:Leave("back") end}),28,24)
local home=Place(UI.ProgressionRow:Create(frame,{id="home",width=130,height=38,icon=false,compact=true,label="CORE / HOME",onActivate=function() Screen:Leave("home") end}),1368,24)
local close=Place(UI.ProgressionRow:Create(frame,{id="close",width=130,height=38,icon=false,compact=true,label="CLOSE  ×",onActivate=function() Screen:CloseCompanion() end}),1514,24)
Screen.back=back; Screen.home=home; Screen.close=close

local aperture=CreateFrame("Frame",nil,frame); aperture:SetSize(920,410); aperture:SetPoint("TOP",frame,"TOP",0,-126)
-- Scaffold Eradication Sprint: wt-aperture-cavity replaces apertureShadow/field.
-- Alpha is mechanically clipped by the asset itself to the protected central
-- cavity per its own provenance -- no extra Lua clip logic needed. Created before
-- apertureShadow so it sits at the very back; gate masses, throat/crown/ledge art,
-- and all native text/state (all created later / on separate child frames) render
-- above it unchanged.
local apertureCavity=aperture:CreateTexture(nil,"BACKGROUND"); apertureCavity:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_APERTURE_CAVITY"); apertureCavity:SetAllPoints(aperture); apertureCavity:SetTexCoord(0,920/1024,0,410/512)
local apertureShadow=Solid(aperture,"BACKGROUND",{0.002,0.006,0.010,0.90}); apertureShadow:SetAllPoints(aperture)
local field=Solid(aperture,"ARTWORK",{0.005,0.020,0.032,0.96}); field:SetSize(650,300); field:SetPoint("CENTER",aperture,"CENTER",8,10)
apertureShadow:Hide(); field:Hide()
local pressure=Solid(aperture,"ARTWORK",Theme.colors.worldsoul); pressure:SetSize(480,236); pressure:SetPoint("CENTER",field,"CENTER",0,0); pressure:SetAlpha(0.07); Screen.pressure=pressure

-- The Candidate 43 opening is a world-facing void held by unlike masses: a
-- broken left throat, a denser right retainer, and a low seal ledge.
local throatTop=Solid(aperture,"ARTWORK",Theme.colors.stoneLift); throatTop:SetSize(332,13); throatTop:SetPoint("TOPLEFT",aperture,"TOPLEFT",26,-38)
local throatStep=Solid(aperture,"ARTWORK",Theme.colors.stone); throatStep:SetSize(108,28); throatStep:SetPoint("TOPLEFT",aperture,"TOPLEFT",58,-67)
-- Gate 1: wt-gate-throat-left replaces the throatTop/throatStep group above (static,
-- non-dynamic scaffold -- exact bounds match throatTop's own anchor).
-- Gate 1 texture-compatibility repair: padded to 512x64 POT canvas (original
-- art 332x57, unscaled); SetTexCoord crops back to the exact visible region.
local throatLeftHousing=aperture:CreateTexture(nil,"BACKGROUND"); throatLeftHousing:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_GATE_THROAT_LEFT"); throatLeftHousing:SetSize(332,57); throatLeftHousing:SetPoint("TOPLEFT",aperture,"TOPLEFT",26,-38); throatLeftHousing:SetTexCoord(0,332/512,0,57/64)
throatTop:Hide(); throatStep:Hide()
local rightCrown=Solid(aperture,"ARTWORK",Theme.colors.stoneLift); rightCrown:SetSize(216,17); rightCrown:SetPoint("TOPRIGHT",aperture,"TOPRIGHT",-22,-52)
local rightShoulder=Solid(aperture,"ARTWORK",Theme.colors.stone); rightShoulder:SetSize(94,38); rightShoulder:SetPoint("TOPRIGHT",aperture,"TOPRIGHT",-46,-79)
-- Gate 2: wt-gate-crown-right replaces rightCrown/rightShoulder (union bounding box).
-- POT 256x128, visible 216x65.
local crownRightArt=aperture:CreateTexture(nil,"BACKGROUND"); crownRightArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_GATE_CROWN_RIGHT"); crownRightArt:SetSize(216,65); crownRightArt:SetPoint("TOPRIGHT",aperture,"TOPRIGHT",-22,-52); crownRightArt:SetTexCoord(0,216/256,0,65/128)
-- True-final material resolve: wt-gate-joint closes the right upper-gate
-- discontinuity. Static placement is safe here -- the 90px-wide joint spans the
-- sealRight dynamic frame's full possible left-edge travel range (1050 at ratio 0
-- to 1105 at ratio 1), so it never visually detaches regardless of Threat level.
local gateJointArt=aperture:CreateTexture(nil,"BACKGROUND"); gateJointArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_GATE_JOINT"); gateJointArt:SetSize(90,32); gateJointArt:SetPoint("TOPLEFT",frame,"TOPLEFT",1040,-198); gateJointArt:SetTexCoord(0,90/128,0,1.0)
rightCrown:Hide(); rightShoulder:Hide()
local sealLedge=Solid(aperture,"ARTWORK",Theme.colors.bronzeDark); sealLedge:SetSize(530,13); sealLedge:SetPoint("BOTTOM",aperture,"BOTTOM",18,22); sealLedge:SetAlpha(0.76)
local sealLedgeLock=Solid(aperture,"OVERLAY",Theme.colors.stoneLift); sealLedgeLock:SetSize(176,8); sealLedgeLock:SetPoint("BOTTOMRIGHT",aperture,"BOTTOMRIGHT",-76,17)
-- Gate 2: wt-seal-ledge replaces sealLedge/sealLedgeLock (union bounding box).
-- POT 1024x32, visible 631x18.
-- NOTE: anchored TOPLEFT with an absolute offset (213,-375), not BOTTOM like the
-- scaffold it replaces -- sealLedge's BOTTOM anchor is a center-based point, and
-- this asset's width (631) differs from sealLedge's (530), so reusing BOTTOM at the
-- same offset would recenter rather than reproduce the documented (589,501) corner.
local sealLedgeArt=aperture:CreateTexture(nil,"BACKGROUND"); sealLedgeArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_SEAL_LEDGE"); sealLedgeArt:SetSize(631,18); sealLedgeArt:SetPoint("TOPLEFT",aperture,"TOPLEFT",213,-375); sealLedgeArt:SetTexCoord(0,631/1024,0,18/32)
sealLedge:Hide(); sealLedgeLock:Hide()
-- Gate 2: removed as redundant (LEVEL-1-PRUNE-LIST.md) -- thin buttress trim adjacent
-- to the accepted Gate 1 gate masses, which already supply the material there.
local leftButtress=Solid(aperture,"OVERLAY",Theme.colors.bronze); leftButtress:SetSize(96,11); leftButtress:SetPoint("LEFT",aperture,"LEFT",18,31); leftButtress:SetAlpha(0.52)
local rightButtress=Solid(aperture,"OVERLAY",Theme.colors.bronze); rightButtress:SetSize(146,9); rightButtress:SetPoint("RIGHT",aperture,"RIGHT",-14,-35); rightButtress:SetAlpha(0.46)
leftButtress:Hide(); rightButtress:Hide()

-- Unequal gate masses carry Candidate 43's asymmetry while protecting a
-- minimum 414px reading aperture. Structure intensifies before effects.
local sealLeft=CreateFrame("Frame",nil,aperture); sealLeft:SetSize(190,294)
local sealRight=CreateFrame("Frame",nil,aperture); sealRight:SetSize(145,254)
Screen.sealLeftWidth=190; Screen.sealRightWidth=145
Screen.protectedReadoutLeft=200; Screen.protectedReadoutRight=214
local function BuildGateMass(seal,isLeft)
    -- Gate 1: wt-gate-mass-left/right replace core/crownPlate/shoulder/foot below.
    -- Parented directly to `seal` (SetAllPoints) so the art tracks Screen:SetSeal's
    -- live leftGap/rightGap repositioning automatically -- never a baked coordinate.
    -- Gate 1 texture-compatibility repair: padded to POT canvases (left
    -- 190x294->256x512, right 145x254->256x256; art unscaled). SetTexCoord
    -- crops back to the exact visible region.
    local massHousing=seal:CreateTexture(nil,"BACKGROUND")
    -- Level 2: swapped to independently-authored stressed variants (same visible/POT/
    -- UV spec as the Gate 1 originals) per World-Threat/WORLD-THREAT-LEVEL2-
    -- PROVENANCE.md -- left gets diagonal-load wear, right gets compression wear;
    -- never mirrored from each other, preserving the authored asymmetry.
    massHousing:SetTexture(isLeft and "Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_GATE_MASS_LEFT_STRESSED" or "Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_GATE_MASS_RIGHT_STRESSED")
    massHousing:SetAllPoints(seal)
    massHousing:SetTexCoord(0,isLeft and 190/256 or 145/256,0,isLeft and 294/512 or 254/256)
    local core=Solid(seal,"ARTWORK",Theme.colors.stoneLift); core:SetSize(isLeft and 126 or 92,isLeft and 220 or 188)
    core:SetPoint(isLeft and "RIGHT" or "LEFT",seal,isLeft and "RIGHT" or "LEFT",0,isLeft and 1 or -3)
    local crownPlate=Solid(seal,"ARTWORK",Theme.colors.stone); crownPlate:SetSize(isLeft and 174 or 128,isLeft and 46 or 38)
    crownPlate:SetPoint(isLeft and "TOPRIGHT" or "TOPLEFT",seal,isLeft and "TOPRIGHT" or "TOPLEFT",0,isLeft and -8 or -18)
    local shoulder=Solid(seal,"ARTWORK",Theme.colors.stoneLift); shoulder:SetSize(isLeft and 82 or 62,isLeft and 118 or 94)
    shoulder:SetPoint(isLeft and "LEFT" or "RIGHT",seal,isLeft and "LEFT" or "RIGHT",0,isLeft and 21 or -17)
    local foot=Solid(seal,"ARTWORK",Theme.colors.stone); foot:SetSize(isLeft and 150 or 112,isLeft and 44 or 36)
    foot:SetPoint(isLeft and "BOTTOMRIGHT" or "BOTTOMLEFT",seal,isLeft and "BOTTOMRIGHT" or "BOTTOMLEFT",0,isLeft and 6 or 12)
    local inner=Solid(seal,"OVERLAY",Theme.colors.bronze); inner:SetSize(isLeft and 7 or 5,isLeft and 236 or 196)
    inner:SetPoint(isLeft and "RIGHT" or "LEFT",seal,isLeft and "RIGHT" or "LEFT",0,0)
    local channel=Solid(seal,"OVERLAY",Theme.colors.worldsoul); channel:SetSize(3,isLeft and 172 or 146)
    channel:SetPoint(isLeft and "RIGHT" or "LEFT",seal,isLeft and "RIGHT" or "LEFT",isLeft and -15 or 14,0); channel:SetAlpha(0.34)
    core:Hide(); crownPlate:Hide(); shoulder:Hide(); foot:Hide()
end
BuildGateMass(sealLeft,true); BuildGateMass(sealRight,false)
Screen.sealLeft=sealLeft; Screen.sealRight=sealRight

Screen.loadSegments={}
for index,data in ipairs({
    {"TOPLEFT",aperture,"TOPLEFT",142,-55,74,5},
    {"TOPLEFT",aperture,"TOPLEFT",98,-91,118,6},
    {"BOTTOMLEFT",aperture,"BOTTOMLEFT",76,64,156,6},
    {"TOPRIGHT",aperture,"TOPRIGHT",-66,-76,92,5},
    {"BOTTOMRIGHT",aperture,"BOTTOMRIGHT",-34,86,126,6},
}) do
    local segment=Solid(aperture,"OVERLAY",Theme.colors.worldsoul)
    segment:SetSize(data[6],data[7]); segment:SetPoint(data[1],data[2],data[3],data[4],data[5]); segment:SetAlpha(0.06)
    Screen.loadSegments[index]=segment
end

local stanceLabel=Label(aperture,"CURRENT WORLD STANCE",Theme.fonts.readable,11,Theme.colors.textMuted,"CENTER",aperture,"CENTER",8,105)
local stanceName=Label(aperture,"READING",Theme.fonts.monument,31,Theme.colors.text,"CENTER",aperture,"CENTER",8,58,400,"CENTER")
stanceName:SetHeight(42); Screen.stanceName=stanceName
local levelValue=Label(aperture,"—",Theme.fonts.monument,76,Theme.colors.worldsoulPale,"CENTER",aperture,"CENTER",8,-18); Screen.levelValue=levelValue
local levelLabel=Label(aperture,"THREAT LEVEL",Theme.fonts.readable,11,Theme.colors.textMuted,"CENTER",aperture,"CENTER",8,-67)
local pressureCaption=Label(aperture,"CALM BASELINE",Theme.fonts.readable,11,Theme.colors.text,"CENTER",aperture,"CENTER",8,-104,420,"CENTER"); Screen.pressureCaption=pressureCaption

Screen.stages={}
local pressureBed=CreateFrame("Frame",nil,frame); pressureBed:SetSize(1194,68); pressureBed:SetPoint("TOPLEFT",frame,"TOPLEFT",238,-548)
local pressureBack=Solid(pressureBed,"ARTWORK",{0.010,0.015,0.019,0.82}); pressureBack:SetSize(1180,48); pressureBack:SetPoint("CENTER",pressureBed,"CENTER",0,1)
local pressureSpine=Solid(pressureBed,"ARTWORK",Theme.colors.stone); pressureSpine:SetSize(1068,11); pressureSpine:SetPoint("CENTER",pressureBed,"CENTER",0,3)
local pressureChannel=Solid(pressureBed,"OVERLAY",Theme.colors.bronzeDark); pressureChannel:SetSize(1104,5); pressureChannel:SetPoint("CENTER",pressureSpine,"CENTER",0,0); pressureChannel:SetAlpha(0.66)
local pressureAnchor=Solid(pressureBed,"OVERLAY",Theme.colors.stoneLift); pressureAnchor:SetSize(142,17); pressureAnchor:SetPoint("LEFT",pressureBed,"LEFT",-8,1)
local pressureOuter=Solid(pressureBed,"OVERLAY",Theme.colors.stoneLift); pressureOuter:SetSize(206,13); pressureOuter:SetPoint("RIGHT",pressureBed,"RIGHT",18,-5)
-- Gate 2: wt-pressure-bed replaces the five-piece pressure backing (pressureBack/
-- Spine/Channel/Anchor/Outer). Anchored to `frame` at the exact canvas coordinate
-- (245,557), not pressureBed's own CENTER-anchored children, to avoid the same
-- center-vs-corner drift risk noted for the seal ledge above. POT 2048x64, visible
-- 1180x48.
-- Scaffold Eradication Sprint: wt-pressure-housing. REDUNDANCY: the accepted Gate 2
-- WT_PRESSURE_BED (1180x48 @ 245,557) is fully contained within this new asset's
-- 1194x68 @ 238,548 bounds (verified: 245>=238, 1425<=1432, 557>=548, 605<=616) --
-- an exact identical-role subset, so it's hidden below rather than double-rendered.
-- WT_PRESSURE_ENDCAP_L/R are NOT contained (each extends 25px beyond the housing's
-- own edge) and are explicitly preserved per the additive-stack requirement.
-- Parented to `frame` (not `pressureBed`) at the same absolute coordinate, matching
-- pressureEndcapL/R and pressureBedArt below -- keeps all three on the same frame
-- level so creation order alone determines stacking (avoids cross-frame-level
-- surprises between a `pressureBed`-child texture and `frame`-child endcaps).
local pressureHousing=frame:CreateTexture(nil,"BACKGROUND"); pressureHousing:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_PRESSURE_HOUSING"); pressureHousing:SetSize(1194,68); pressureHousing:SetPoint("TOPLEFT",frame,"TOPLEFT",238,-548); pressureHousing:SetTexCoord(0,1194/2048,0,68/128)
local pressureBedArt=frame:CreateTexture(nil,"BACKGROUND"); pressureBedArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_PRESSURE_BED"); pressureBedArt:SetSize(1180,48); pressureBedArt:SetPoint("TOPLEFT",frame,"TOPLEFT",245,-557); pressureBedArt:SetTexCoord(0,1180/2048,0,48/64)
pressureBedArt:Hide()
pressureBack:Hide(); pressureSpine:Hide(); pressureChannel:Hide(); pressureAnchor:Hide(); pressureOuter:Hide()
-- True-final material resolve: wt-pressure-endcap-l/r close the accepted Gate 2
-- pressure bed's ends. Both overlap the bed by 32px and extend 32px beyond it.
local pressureEndcapL=frame:CreateTexture(nil,"BACKGROUND"); pressureEndcapL:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_PRESSURE_ENDCAP_L"); pressureEndcapL:SetSize(64,48); pressureEndcapL:SetPoint("TOPLEFT",frame,"TOPLEFT",213,-557); pressureEndcapL:SetTexCoord(0,1.0,0,48/64)
local pressureEndcapR=frame:CreateTexture(nil,"BACKGROUND"); pressureEndcapR:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_PRESSURE_ENDCAP_R"); pressureEndcapR:SetSize(64,48); pressureEndcapR:SetPoint("TOPLEFT",frame,"TOPLEFT",1393,-557); pressureEndcapR:SetTexCoord(0,1.0,0,48/64)
for level=0,10 do
    local stage=CreateFrame("Frame",nil,frame); stage:SetSize(94,54); stage:SetPoint("TOPLEFT",frame,"TOPLEFT",258+(level*105),-555)
    local seat=Solid(stage,"ARTWORK",{0.020,0.026,0.032,0.96}); seat:SetSize(66,32); seat:SetPoint("CENTER",stage,"CENTER",0,3)
    local shoulderL=Solid(stage,"ARTWORK",Theme.colors.stoneLift); shoulderL:SetSize(8,22); shoulderL:SetPoint("RIGHT",seat,"LEFT",0,0); shoulderL:SetAlpha(0.46)
    local shoulderR=Solid(stage,"ARTWORK",Theme.colors.stoneLift); shoulderR:SetSize(8,16); shoulderR:SetPoint("LEFT",seat,"RIGHT",0,-3); shoulderR:SetAlpha(0.34)
    local edge=Solid(stage,"OVERLAY",Theme.colors.worldsoul); edge:SetSize(3,24); edge:SetPoint("LEFT",seat,"LEFT",0,0); edge:SetAlpha(0.12)
    local engaged=Solid(stage,"OVERLAY",Theme.colors.stoneLift); engaged:SetSize(24,9); engaged:SetPoint("TOP",seat,"TOP",0,4); engaged:SetAlpha(0.10)
    local lock=Solid(stage,"OVERLAY",Theme.colors.worldsoul); lock:SetSize(42,4); lock:SetPoint("BOTTOM",seat,"BOTTOM",0,-2); lock:SetAlpha(0)
    local number=Label(stage,tostring(level),Theme.fonts.monument,18,Theme.colors.textMuted,"CENTER",seat,"CENTER",0,3)
    local mark=Label(stage,level==0 and "PEACEFUL" or "",Theme.fonts.readable,8,Theme.colors.disabled,"TOP",seat,"BOTTOM",0,-5)
    Screen.stages[level]={root=stage,seat=seat,edge=edge,engaged=engaged,lock=lock,number=number,mark=mark,shoulderL=shoulderL,shoulderR=shoulderR}
end
-- Level 2: wt-current-marker-recess mechanically seats the native current-stage
-- marker. Genuinely dynamic per World-Threat/WORLD-THREAT-LEVEL2-PROVENANCE.md
-- ("reparented or repositioned to the current stage") -- created once here, then
-- reparented to whichever stage is selected inside Screen:SetSeal below, exactly
-- the same technique already proven for the World Threat gate masses. Native
-- numeric stage, engaged edge, lock, and the marker itself stay above (BACKGROUND
-- layer, and stage.seat/number/etc. are created after this on their own frame).
local markerRecess=frame:CreateTexture(nil,"BACKGROUND"); markerRecess:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_CURRENT_MARKER_RECESS"); markerRecess:SetSize(40,18); markerRecess:SetTexCoord(0,40/64,0,18/32)
Screen.markerRecess=markerRecess

local lowerBrace=Solid(frame,"ARTWORK",Theme.colors.stoneLift); lowerBrace:SetSize(304,9); lowerBrace:SetPoint("TOPLEFT",frame,"TOPLEFT",212,-657)
local raiseBrace=Solid(frame,"ARTWORK",Theme.colors.stoneLift); raiseBrace:SetSize(318,9); raiseBrace:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-212,-654)
local resetSeat=Solid(frame,"ARTWORK",Theme.colors.bronzeDark); resetSeat:SetSize(278,8); resetSeat:SetPoint("TOP",frame,"TOP",0,-677); resetSeat:SetAlpha(0.62)
-- True-final material resolve: wt-action-seat-lower/reset/raise give the three
-- native action controls (built by UI.ProgressionRow:Create) intentional mechanical
-- seating. Parented to `frame` at each control's own exact bounds -- the controls
-- themselves are separate, deeper-nested frames, so they render above these
-- BACKGROUND-layer textures automatically regardless of creation order.
local actionSeatLower=frame:CreateTexture(nil,"BACKGROUND"); actionSeatLower:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_ACTION_SEAT_LOWER"); actionSeatLower:SetSize(250,58); actionSeatLower:SetPoint("TOPLEFT",frame,"TOPLEFT",246,-622); actionSeatLower:SetTexCoord(0,250/256,0,58/64)
local actionSeatReset=frame:CreateTexture(nil,"BACKGROUND"); actionSeatReset:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_ACTION_SEAT_RESET"); actionSeatReset:SetSize(220,48); actionSeatReset:SetPoint("TOPLEFT",frame,"TOPLEFT",726,-632); actionSeatReset:SetTexCoord(0,220/256,0,48/64)
local actionSeatRaise=frame:CreateTexture(nil,"BACKGROUND"); actionSeatRaise:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_ACTION_SEAT_RAISE"); actionSeatRaise:SetSize(250,58); actionSeatRaise:SetPoint("TOPLEFT",frame,"TOPLEFT",1176,-622); actionSeatRaise:SetTexCoord(0,250/256,0,58/64)
local lower=Place(UI.ProgressionRow:Create(frame,{id="decrease",width=250,height=58,icon=false,label="LOWER PRESSURE",meta="Clears Momentum",value="−1",accentColor=Theme.colors.worldsoul,onActivate=function() Screen:RequestAction("threat_decrease") end}),246,622)
local reset=Place(UI.ProgressionRow:Create(frame,{id="reset",width=220,height=48,icon=false,fontSize=11,valueWidth=34,label="SEAL TO PEACEFUL",meta="Clears Momentum",value="0",accentColor=Theme.colors.bronze,onActivate=function() Screen:RequestAction("threat_reset") end}),726,632)
local raise=Place(UI.ProgressionRow:Create(frame,{id="increase",width=250,height=58,icon=false,label="RAISE PRESSURE",meta="Retains Momentum",value="+1",accentColor=Theme.colors.worldsoul,onActivate=function() Screen:RequestAction("threat_increase") end}),1176,622)
Screen.lower=lower; Screen.reset=reset; Screen.raise=raise
Screen.actionControls={threat_decrease=lower,threat_reset=reset,threat_increase=raise}
Screen.actionMeta={
    threat_decrease="Clears Momentum",
    threat_reset="Clears Momentum",
    threat_increase="Retains Momentum",
}

-- One carved reward relationship replaces three unrelated stat cards:
-- Threat permits the ceiling, Momentum earns into it, Effective is realized.
local reward=CreateFrame("Frame",nil,frame); reward:SetSize(692,100); reward:SetPoint("TOPLEFT",frame,"TOPLEFT",178,-712)
local rewardSeat=Solid(reward,"ARTWORK",{0.014,0.020,0.026,0.94}); rewardSeat:SetSize(678,86); rewardSeat:SetPoint("CENTER",reward,"CENTER",0,0)
local rewardTop=Solid(reward,"ARTWORK",Theme.colors.stoneLift); rewardTop:SetSize(470,9); rewardTop:SetPoint("TOPLEFT",reward,"TOPLEFT",0,-1)
local rewardTopLock=Solid(reward,"ARTWORK",Theme.colors.stone); rewardTopLock:SetSize(126,15); rewardTopLock:SetPoint("TOPRIGHT",reward,"TOPRIGHT",0,-1)
local rewardFoot=Solid(reward,"ARTWORK",Theme.colors.bronzeDark); rewardFoot:SetSize(396,7); rewardFoot:SetPoint("BOTTOMRIGHT",reward,"BOTTOMRIGHT",0,1); rewardFoot:SetAlpha(0.66)
-- Gate 2: wt-reward-seat replaces rewardSeat/Top/TopLock/Foot (union bounding box,
-- anchored at frame's exact canvas coordinate (185,719) to avoid drift). Value
-- dividers (ceilingStop/momentumChannel/effectiveGate) and all text/values stay
-- native above it -- not named in the Gate 2 prune list. POT 1024x128, visible
-- 678x86.
-- Scaffold Eradication Sprint: wt-reward-manifold. REDUNDANCY: identical 678x86
-- footprint at the identical (185,719) position as the accepted Gate 2 WT_REWARD_
-- SEAT, replacing the identical native primitive set -- exact same role, more
-- complete art, so WT_REWARD_SEAT is hidden rather than double-rendered at the
-- same spot. wt-terminal-join (rewardJoin, below) is NOT fully contained in this
-- footprint (it sits 5px above the manifold's top edge) and is preserved.
local rewardManifold=frame:CreateTexture(nil,"BACKGROUND"); rewardManifold:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_REWARD_MANIFOLD"); rewardManifold:SetSize(678,86); rewardManifold:SetPoint("TOPLEFT",frame,"TOPLEFT",185,-719); rewardManifold:SetTexCoord(0,678/1024,0,86/128)
local rewardSeatArt=frame:CreateTexture(nil,"BACKGROUND"); rewardSeatArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_REWARD_SEAT"); rewardSeatArt:SetSize(678,86); rewardSeatArt:SetPoint("TOPLEFT",frame,"TOPLEFT",185,-719); rewardSeatArt:SetTexCoord(0,678/1024,0,86/128)
rewardSeatArt:Hide()
rewardSeat:Hide(); rewardTop:Hide(); rewardTopLock:Hide(); rewardFoot:Hide()
local ceilingStop=Solid(reward,"OVERLAY",Theme.colors.stoneLift); ceilingStop:SetSize(12,58); ceilingStop:SetPoint("LEFT",reward,"LEFT",0,0)
local momentumChannel=Solid(reward,"OVERLAY",Theme.colors.worldsoul); momentumChannel:SetSize(5,54); momentumChannel:SetPoint("LEFT",reward,"LEFT",222,0); momentumChannel:SetAlpha(0.62)
local effectiveGate=Solid(reward,"OVERLAY",Theme.colors.text); effectiveGate:SetSize(9,66); effectiveGate:SetPoint("LEFT",reward,"LEFT",444,0); effectiveGate:SetAlpha(0.64)
Label(reward,"REWARD CEILING",Theme.fonts.readable,10,Theme.colors.textMuted,"TOPLEFT",reward,"TOPLEFT",22,-17)
Label(reward,"MOMENTUM",Theme.fonts.readable,10,Theme.colors.textMuted,"TOPLEFT",reward,"TOPLEFT",244,-17)
Label(reward,"EFFECTIVE REWARD",Theme.fonts.readable,10,Theme.colors.textMuted,"TOPLEFT",reward,"TOPLEFT",466,-17)
Screen.ceilingValue=Label(reward,"—",Theme.fonts.monument,24,Theme.colors.worldsoulPale,"TOPLEFT",reward,"TOPLEFT",21,-44)
Screen.momentumValue=Label(reward,"—",Theme.fonts.monument,25,Theme.colors.worldsoulPale,"TOPLEFT",reward,"TOPLEFT",243,-44)
Screen.effectiveValue=Label(reward,"—",Theme.fonts.monument,29,Theme.colors.text,"TOPLEFT",reward,"TOPLEFT",465,-41)
Label(reward,"×",Theme.fonts.monument,20,Theme.colors.textMuted,"CENTER",reward,"LEFT",214,2)
Label(reward,"=",Theme.fonts.monument,20,Theme.colors.textMuted,"CENTER",reward,"LEFT",436,2)
Label(reward,"PERMITTED",Theme.fonts.readable,8,Theme.colors.disabled,"BOTTOMLEFT",reward,"BOTTOMLEFT",22,13)
Label(reward,"EARNED INTO CEILING",Theme.fonts.readable,8,Theme.colors.disabled,"BOTTOMLEFT",reward,"BOTTOMLEFT",244,13)
Label(reward,"REALIZED NOW",Theme.fonts.readable,8,Theme.colors.disabled,"BOTTOMLEFT",reward,"BOTTOMLEFT",466,13)

local consequence=CreateFrame("Frame",nil,frame); consequence:SetSize(616,100); consequence:SetPoint("TOPLEFT",frame,"TOPLEFT",878,-712)
local consequenceSeat=Solid(consequence,"ARTWORK",{0.012,0.017,0.022,0.96}); consequenceSeat:SetSize(598,86); consequenceSeat:SetPoint("RIGHT",consequence,"RIGHT",0,0)
local consequenceMass=Solid(consequence,"ARTWORK",Theme.colors.stoneLift); consequenceMass:SetSize(15,100); consequenceMass:SetPoint("LEFT",consequence,"LEFT",0,0)
local consequenceEdge=Solid(consequence,"OVERLAY",Theme.colors.bronze); consequenceEdge:SetSize(4,72); consequenceEdge:SetPoint("LEFT",consequence,"LEFT",15,0); consequenceEdge:SetAlpha(0.72)
local consequenceTop=Solid(consequence,"OVERLAY",Theme.colors.stone); consequenceTop:SetSize(248,10); consequenceTop:SetPoint("TOPRIGHT",consequence,"TOPRIGHT",0,-1)
local consequenceFoot=Solid(consequence,"OVERLAY",Theme.colors.bronzeDark); consequenceFoot:SetSize(366,7); consequenceFoot:SetPoint("BOTTOMRIGHT",consequence,"BOTTOMRIGHT",0,1); consequenceFoot:SetAlpha(0.58)
-- Gate 2: wt-consequence-seat replaces consequenceSeat/Mass/Edge/Top/Foot (union
-- bounding box, anchored at frame's exact canvas coordinate (896,719)). Penalty/debt
-- text stays native above it. POT 1024x128, visible 598x86.
-- Scaffold Eradication Sprint: wt-risk-interior. REDUNDANCY: identical 598x86
-- footprint at the identical (896,719) position as the accepted Gate 2 WT_
-- CONSEQUENCE_SEAT -- same reasoning as the reward manifold above.
local riskInterior=frame:CreateTexture(nil,"BACKGROUND"); riskInterior:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_RISK_INTERIOR"); riskInterior:SetSize(598,86); riskInterior:SetPoint("TOPLEFT",frame,"TOPLEFT",896,-719); riskInterior:SetTexCoord(0,598/1024,0,86/128)
local consequenceSeatArt=frame:CreateTexture(nil,"BACKGROUND"); consequenceSeatArt:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_CONSEQUENCE_SEAT"); consequenceSeatArt:SetSize(598,86); consequenceSeatArt:SetPoint("TOPLEFT",frame,"TOPLEFT",896,-719); consequenceSeatArt:SetTexCoord(0,598/1024,0,86/128)
consequenceSeatArt:Hide()
consequenceSeat:Hide(); consequenceMass:Hide(); consequenceEdge:Hide(); consequenceTop:Hide(); consequenceFoot:Hide()
Label(consequence,"RISK AT THIS STANCE",Theme.fonts.readable,10,Theme.colors.textMuted,"TOPLEFT",consequence,"TOPLEFT",34,-17)
Screen.penaltyLine=Label(consequence,"Peaceful stance carries no death penalty.",Theme.fonts.readable,12,Theme.colors.text,"TOPLEFT",consequence,"TOPLEFT",34,-41,566)
Screen.debtLine=Label(consequence,"No Worldsoul Debt active.",Theme.fonts.readable,10,Theme.colors.textMuted,"TOPLEFT",consequence,"TOPLEFT",34,-67,566)
-- Level 2: wt-terminal-join resolves the reward/consequence housing transitions.
-- Consequence instance mirrored (flipped U) to follow its reversed mass direction,
-- per World-Threat/WORLD-THREAT-LEVEL2-PROVENANCE.md.
local rewardJoin=frame:CreateTexture(nil,"BACKGROUND"); rewardJoin:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_TERMINAL_JOIN"); rewardJoin:SetSize(64,18); rewardJoin:SetPoint("TOPLEFT",frame,"TOPLEFT",492,-714); rewardJoin:SetTexCoord(0,1.0,0,18/32)
local consequenceJoin=frame:CreateTexture(nil,"BACKGROUND"); consequenceJoin:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\WT_TERMINAL_JOIN"); consequenceJoin:SetSize(64,18); consequenceJoin:SetPoint("TOPLEFT",frame,"TOPLEFT",1188,-714); consequenceJoin:SetTexCoord(1.0,0,0,18/32)

Screen.capLine=Label(frame,"QUALIFYING CONTENT  ·  NORMAL —  ·  ELITE —  ·  BOSS —  ·  RAID —",Theme.fonts.readable,10,Theme.colors.textMuted,"BOTTOM",frame,"BOTTOM",0,50,1040,"CENTER")
Label(frame,"AFFECTS  ESSENCE  ·  ATTUNEMENT XP  ·  SLOT XP  ·  RACK XP  ·  FRAGMENTS",Theme.fonts.readable,10,Theme.colors.textMuted,"BOTTOM",frame,"BOTTOM",0,29,980,"CENTER")
Screen.status=Label(frame,"",Theme.fonts.readable,10,Theme.colors.textMuted,"BOTTOM",frame,"BOTTOM",0,10,760,"CENTER")

local input=UI.InputManager:New(frame); Screen.input=input
for _,entry in ipairs({back,home,close,lower,reset,raise}) do input:Add(entry,entry.id) end
input:SetNavigation({"back","home","close","decrease","reset","increase"},{
    back={RIGHT="decrease",DOWN="decrease"},home={LEFT="back",RIGHT="close",DOWN="increase"},close={LEFT="home",DOWN="increase"},
    decrease={UP="back",RIGHT="reset"},reset={UP="home",LEFT="decrease",RIGHT="increase"},increase={UP="home",LEFT="reset"},
})
input.defaultFocusId="increase"; input.onEscape=function() Screen:Leave("back") end

local function Pct(value) return string.format("%.1f%%",tonumber(value) or 0) end
local function Int(value) return tostring(math.floor(tonumber(value) or 0)) end

function Screen:SetSeal(level,maximum)
    maximum=math.max(1,maximum or 10); local ratio=math.max(0,math.min(1,level/maximum))
    local leftGap=200+(ratio*45); local rightGap=214+(ratio*55)
    self.currentSealLeftGap=leftGap; self.currentSealRightGap=rightGap
    self.sealLeft:ClearAllPoints(); self.sealLeft:SetPoint("RIGHT",aperture,"CENTER",-leftGap,14)
    self.sealRight:ClearAllPoints(); self.sealRight:SetPoint("LEFT",aperture,"CENTER",rightGap,-4)
    self.pressure:SetAlpha(0.06+(ratio*0.15))
    for index,segment in ipairs(self.loadSegments) do
        local threshold=index*2
        segment:SetAlpha(level>=threshold and (0.30+(ratio*0.28)) or 0.06)
    end
    for value,stage in pairs(self.stages) do
        local selected=value==level; local passed=value<level
        if selected then self.markerRecess:ClearAllPoints(); self.markerRecess:SetPoint("CENTER",stage.seat,"CENTER",0,0) end
        stage.edge:SetAlpha(selected and 1 or (passed and 0.42 or 0.12))
        stage.seat:SetAlpha(selected and 1 or (passed and 0.80 or 0.50))
        stage.engaged:SetAlpha(selected and 0.86 or (passed and 0.38 or 0.10))
        stage.shoulderL:SetAlpha(selected and 0.76 or (passed and 0.54 or 0.24))
        stage.shoulderR:SetAlpha(selected and 0.62 or (passed and 0.42 or 0.18))
        stage.lock:SetAlpha(selected and 1 or 0)
        stage.number:SetTextColor(unpack(selected and Theme.colors.worldsoulPale or (passed and Theme.colors.text or Theme.colors.textMuted)))
        stage.mark:SetText(selected and "CURRENT" or (value==0 and "PEACEFUL" or ""))
    end
end

function Screen:RefreshState(values)
    values=values or UI.StateStore.values or {}
    local level=tonumber(values.threat_level); local maximum=tonumber(values.threat_max) or 10
    self.hasState=level~=nil; self.level=level or 0; self.maximum=maximum
    self.stanceName:SetText(values.threat_name or (self.hasState and "UNKNOWN" or "READING"))
    self.levelValue:SetText(self.hasState and Int(level) or "—")
    self.pressureCaption:SetText(not self.hasState and "READING OUTWARD PRESSURE"
        or (level==0 and "CALM BASELINE" or "OUTWARD PRESSURE ENGAGED"))
    self.ceilingValue:SetText(self.hasState and ("+"..Pct(values.threat_ceiling_pct)) or "—")
    self.momentumValue:SetText(self.hasState and Pct(values.threat_momentum_pct) or "—")
    self.effectiveValue:SetText(self.hasState and ("+"..Pct(values.threat_effective_pct)) or "—")
    if self.hasState and level>0 then
        self.penaltyLine:SetText("On death: Attunement −"..Pct(values.threat_attune_loss_pct).."  ·  Essence −"..Pct(values.threat_essence_loss_pct).." (cap "..Int(values.threat_essence_cap)..")  ·  next "..Int(values.threat_penalty_debt_kills).." kills at "..Pct(values.threat_penalty_debt_mult_pct))
    else self.penaltyLine:SetText("Peaceful stance carries no death penalty.") end
    local debt=tonumber(values.threat_debt_kills) or 0
    self.debtLine:SetText(debt>0 and ("Worldsoul Debt active: "..debt.." kills at "..Pct(values.threat_debt_mult_pct).." gains")
        or (self.hasState and ("Safety threshold: "..Pct(values.threat_safety_pct).."  ·  No Worldsoul Debt active.") or "Awaiting world-response state."))
    self.capLine:SetText("QUALIFYING CONTENT  ·  NORMAL +"..Pct(values.threat_cap_normal_pct).."  ·  ELITE +"..Pct(values.threat_cap_elite_pct).."  ·  BOSS +"..Pct(values.threat_cap_boss_pct).."  ·  RAID +"..Pct(values.threat_cap_raid_pct))
    self:SetSeal(self.level,self.maximum)
    local availability={
        threat_decrease=self.hasState and self.level>0,
        threat_reset=self.hasState and self.level>0,
        threat_increase=self.hasState and self.level<self.maximum,
    }
    self.lower.tooltip=self.hasState and self.level<=0 and "Already at Peaceful." or "Lower World Threat by one level. Momentum will be cleared."
    self.reset.tooltip=self.hasState and self.level<=0 and "Already at Peaceful." or "Seal World Threat to Peaceful. Momentum will be cleared."
    self.raise.tooltip=self.hasState and self.level>=self.maximum and "Maximum world pressure reached." or "Raise World Threat by one level. Current Momentum is retained."
    for action,control in pairs(self.actionControls) do
        local pending=self.actionPending and self.pendingAction==action
        local settling=self.settlingAction==action
        control.meta:SetText(pending and "ADJUSTING…" or (settling and "STABILIZING…" or self.actionMeta[action]))
        control:SetEnabled(availability[action])
        control:SetPending(pending or settling)
    end
end

function Screen:BeginSettling(action)
    if not self.actionControls[action] then return end
    self.settlingAction=action; self.settleToken=(self.settleToken or 0)+1
    local token=self.settleToken
    self:RefreshState(UI.StateStore.values)
    C_Timer.After(2.0,function()
        if Screen.active and Screen.settleToken==token then
            Screen.settlingAction=nil
            Screen:RefreshState(UI.StateStore.values)
        end
    end)
end

function Screen:RequestAction(name)
    if self.actionPending then
        self.status:SetText("The gate is already answering the current adjustment.")
        return false
    end
    if self.settlingAction then
        self.status:SetText("The gate is settling into its last stance.")
        return false
    end
    local control=self.actionControls[name]
    if not control or not control.enabled or not APB or not APB.RequestEchoesAction then return false end
    self.actionPending=true; self.pendingAction=name
    self.actionToken=(self.actionToken or 0)+1; local token=self.actionToken
    self.status:SetText(name=="threat_increase" and "Releasing the outward seal…" or "Bracing the outward seal…")
    self:RefreshState(UI.StateStore.values); APB:RequestEchoesAction(name)
    C_Timer.After(5,function() if Screen.active and Screen.actionToken==token and Screen.actionPending then
        Screen.actionPending=false; Screen.pendingAction=nil
        Screen.status:SetText("The gate did not answer. Its state is being read again.")
        if APB.RequestEchoesState then APB:RequestEchoesState() end; Screen:RefreshState(UI.StateStore.values)
    end end)
    return true
end

function Screen:OnAction(verb,fields)
    fields=fields or {}
    local action=fields.action
    if verb=="ERROR" then
        if not self.actionPending then return end
        local context=action or fields.message
        if context~=self.pendingAction and context~="action" then return end
    elseif not action or not action:find("^threat_") then return end
    local completedAction=action or self.pendingAction
    self.actionPending=false; self.pendingAction=nil
    if verb=="ACTION_OK" and fields.status=="SUCCESS" then self.status:SetText("World pressure confirmed.")
    elseif fields.status=="MAXIMUM" then self.status:SetText("Maximum world pressure reached.")
    elseif fields.status=="MINIMUM" or fields.status=="ALREADY_PEACEFUL" then self.status:SetText("The outward gate is already sealed.")
    elseif fields.status=="INVALID_ACTION" then self.status:SetText("That adjustment is not available.")
    elseif fields.status=="SERVICE_UNAVAILABLE" then self.status:SetText("The gate cannot answer right now.")
    elseif verb=="ERROR" and fields.code=="RATE_LIMITED" then self.status:SetText("The gate is still settling. Try again.")
    elseif verb=="ERROR" then self.status:SetText("The gate could not complete that adjustment.")
    else self.status:SetText("World pressure could not be changed.") end
    self:BeginSettling(completedAction)
    if APB.RequestEchoesState then APB:RequestEchoesState() end
    self:RefreshState(UI.StateStore.values)
end

function Screen:UpdateScale() self.frame:SetScale(math.min((UIParent:GetWidth() or 1672)/1672,(UIParent:GetHeight() or 941)/941)) end
function Screen:Show()
    self.openToken=self.openToken+1; self.active=true; self.actionPending=false; self.pendingAction=nil; self.settlingAction=nil; self:UpdateScale()
    if APB and APB.C43 and APB.C43.frame then APB.C43.frame:Hide() end
    self.frame:SetAlpha(UI:IsReducedMotion() and 1 or 0); self.frame:Show(); Animation:Alpha(self.frame,1,0.22)
    self.input:SetFocusById("increase"); self:RefreshState(UI.StateStore.values)
    if APB and APB.RequestEchoesState then APB:RequestEchoesState() end
end
function Screen:Hide() self.openToken=self.openToken+1; self.active=false; self.actionPending=false; self.pendingAction=nil; self.settlingAction=nil; self.settleToken=(self.settleToken or 0)+1; self.input:ClearFocus(); Animation:Stop(self.frame); self.frame:Hide() end
function Screen:Leave(destination)
    self:Hide(); local focusId=destination=="home" and "core" or "threat"
    if UI.DashboardGateB and UI.ScreenManager:Show("dashboardGateB",false,focusId) then return end
    UI.ScreenManager.current=nil; if APB and APB.C43 then APB.C43:Show() end
end
function Screen:CloseCompanion() self:Hide(); UI.ScreenManager.current=nil; UI.ScreenManager.history={}; if APB and APB.C43 and APB.C43.Hide then APB.C43:Hide() end end

UI.StateStore:Subscribe(function(values) if Screen.active then Screen:RefreshState(values) end end)
if APB and APB.SubscribeEchoesActions then APB:SubscribeEchoesActions(function(verb,fields) Screen:OnAction(verb,fields) end) end

UI.WorldThreatScreen=Screen
UI.ScreenManager:Register("threat",Screen,false)
UI.modules.WorldThreatScreen=true
