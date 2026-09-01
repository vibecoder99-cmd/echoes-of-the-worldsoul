local UI = EchoesUI
if not UI or not UI.ProgressionZone or not UI.ProgressionRow or not UI.ScreenManager then return end

local Theme = UI.Theme
local Animation = UI.AnimationController
local Screen = {
    id = "progression",
    equipped = {},
    equippedByEntry = {},
    equippedOffset = 0,
    slotOffset = 0,
    openToken = 0,
    active = false,
    actionPending = false,
}
local ASSET = "Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\"

local SLOT_DEFS = {
    {0,1,"Head"},{1,2,"Neck"},{2,3,"Shoulders"},{4,5,"Chest"},
    {5,6,"Waist"},{6,7,"Legs"},{7,8,"Feet"},{8,9,"Wrists"},{9,10,"Hands"},
    {10,11,"Finger I"},{11,12,"Finger II"},{12,13,"Trinket I"},{13,14,"Trinket II"},
    {14,15,"Back"},{15,16,"Main Hand"},{16,17,"Off Hand"},{17,18,"Ranged"},
}
local ATTUNEMENT_SLOTS = {
    {0,1,"Head"},{4,5,"Chest"},{5,6,"Waist"},{6,7,"Legs"},{7,8,"Feet"},
    {8,9,"Wrists"},{9,10,"Hands"},{14,15,"Back"},{15,16,"Main Hand"},{16,17,"Off Hand"},
}

local function Solid(parent, layer, color)
    local texture = parent:CreateTexture(nil, layer)
    Theme:SetTextureColor(texture, color)
    return texture
end
local function Art(parent, layer, name, uMax, vMax)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(ASSET .. name)
    t:SetTexCoord(0, uMax, 0, vMax)
    return t
end

-- RUNTIME REGRESSION FIX: this block (CURRENT_STATE/SLOT_STATE/UpdateRowState)
-- previously lived much later in the file, after the row-creation loops that
-- reference it inside `row.onStateChange` closures. Lua resolves a `local`'s
-- visibility by textual/lexical position, not execution order -- a local
-- declared later in the chunk is not an upvalue for a closure written earlier,
-- even though that closure only runs much later at runtime. The old ordering
-- made every reference to UpdateRowState/CURRENT_STATE/SLOT_STATE inside those
-- closures resolve as globals (all nil), causing "attempt to call global
-- 'UpdateRowState' (a nil value)" the first time a row's onStateChange fired.
-- Moved here, before every row-creation site, so all three are genuine local
-- upvalues by the time those closures are compiled.
-- Dynamic State Supplement: sparse hardware overlays replacing the native
-- full-rectangle hover/selected/complete/developed fill. The native `channel`/
-- `selection` textures (ProgressionRow, BACKGROUND layer) are neutralized to
-- alpha 0 via focusColor at Create() time (see row-creation sites below) --
-- their state LOGIC (row.hovered/row.focused/row.pressed) is untouched and
-- drives this overlay instead. `row.state` renders at ARTWORK layer, above
-- `row.bed` (BACKGROUND) and below all native text/icon/progress (OVERLAY).
-- Priority (per PROGRESSION-STATE-HIERARCHY.md): resting < hover/focus <
-- selected < active/complete/developed. Only the highest-priority applicable
-- overlay is ever shown -- never stacked.
local CURRENT_STATE = {
    hover={"ProgressionRowStateHover",0.42}, selected={"ProgressionRowStateSelected",0.64},
    complete={"ProgressionRowStateComplete",0.66},
}
local SLOT_STATE = {
    hover={"ProgressionSlotStateHover",0.38}, selected={"ProgressionSlotStateSelected",0.68},
    developed={"ProgressionSlotStateDeveloped",0.58},
}
local function UpdateRowState(row, table_, uMax, vMax)
    local key = row.contentState
    if not key then
        if row.pressed then key = "selected"
        elseif row.hovered or row.focused then key = "hover" end
    end
    if key then
        local entry = table_[key]
        row.state:SetTexture(ASSET .. entry[1])
        row.state:SetTexCoord(0, uMax, 0, vMax)
        row.state:SetAlpha(entry[2])
        row.state:Show()
    else
        row.state:Hide()
    end
end

local frame = CreateFrame("Frame", "EchoesUIProgressionScreen", UIParent)
frame:SetSize(1672, 941)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
frame:SetFrameStrata("DIALOG")
frame:EnableMouse(true)
frame:Hide()
Screen.frame = frame

-- Gate 1 (Progression): ProgressionReadingFieldTile replaces the shared C43_*
-- Dashboard-tile wash + full veil at the identical 4x2 grid/crop geometry (native
-- per-cell edge-crop math preserved, same technique used on every other fabricated
-- screen this engagement -- the art terminates exactly at the audited 1672x941
-- canvas edge rather than overflowing it).
for row = 0, 1 do
    for column = 0, 3 do
        local tile = frame:CreateTexture(nil, "BACKGROUND")
        tile:SetTexture("Interface\\AddOns\\EchoesOfTheWorldsoulBridge\\Assets\\C43_" .. column .. row)
        local width = column == 3 and 136 or 512
        local height = row == 1 and 429 or 512
        tile:SetSize(width, height)
        tile:SetPoint("TOPLEFT", frame, "TOPLEFT", column * 512, -(row * 512))
        tile:SetTexCoord(0, width / 512, 0, height / 512)
        tile:SetVertexColor(0.30, 0.34, 0.40, 0.32)
        tile:Hide()
    end
end
for row = 0, 1 do
    for column = 0, 3 do
        local width = column == 3 and 136 or 512
        local height = row == 1 and 429 or 512
        local tile = Art(frame, "BACKGROUND", "ProgressionReadingFieldTile", width / 512, height / 512)
        tile:SetSize(width, height)
        tile:SetPoint("TOPLEFT", frame, "TOPLEFT", column * 512, -(row * 512))
        tile:SetAlpha(0.40)
    end
end
-- Global-veil recovery test: restored at its exact original native color/alpha
-- (0.72), unhidden. Isolated single-variable change -- no other asset touched.
-- Purpose (inferred from source): full-screen environmental neutralization scrim
-- behind all Progression content, distinct from ProgressionReadingFieldTile
-- (a local atmospheric material layered on top, not a substitute for this).
local veil = Solid(frame, "BACKGROUND", {0.008, 0.011, 0.016, 0.72})
veil:SetAllPoints(frame)

-- A single broken machine shell sits beneath the four working surfaces. The
-- dark gaps are intentional cavities, while the braces make the regions read
-- as parts of one unfolded Progression landmark rather than separate cards.
local function Plate(width, height, x, y, color, alpha)
    local plate = Solid(frame, "BACKGROUND", color or Theme.colors.stoneLift)
    plate:SetSize(width, height)
    plate:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
    plate:SetAlpha(alpha or 1)
    return plate
end
local shellTopPlate = Plate(1544, 16, 64, 88, Theme.colors.stoneLift, 0.78); shellTopPlate:Hide()
local shellLeftPlate = Plate(22, 760, 38, 118, Theme.colors.stoneLift, 0.72); shellLeftPlate:Hide()
local shellRightPlate = Plate(20, 760, 1613, 118, Theme.colors.stoneLift, 0.72); shellRightPlate:Hide()
-- CONFIRMED LEFTOVER (visibility recovery pass): Plate(690,12,66,562) spans
-- x66-756, y562-574 -- directly overlapping the top edge of Current Attunement
-- (zone starts x55-985, y588), sitting only 14-26px above it. This is the
-- "broad horizontal dark strip above Current Attunement" reported from the
-- real-client screenshot: a native bronze-dark bar (690x12, alpha .72) never
-- named by any of the 29 production assets or R2's four. Not functionally
-- required (no hitbox, no interactive role). Neutralized. Plate(560,12,1053,438)
-- is the same leftover pattern (unmapped native connector between Retained
-- Record and Slot Specialization) -- neutralized for the same reason.
local orphanConnectorLeft = Plate(690, 12, 66, 562, Theme.colors.bronzeDark, 0.72); orphanConnectorLeft:Hide()
local orphanConnectorRight = Plate(560, 12, 1053, 438, Theme.colors.bronzeDark, 0.72); orphanConnectorRight:Hide()
local bridgeA = Plate(322, 20, 715, 184, Theme.colors.stoneLift, 0.58); bridgeA:Hide()
local bridgeB = Plate(290, 12, 736, 202, Theme.colors.bronzeDark, 0.54); bridgeB:Hide()
local bridgeC = Plate(22, 350, 815, 214, Theme.colors.stoneLift, 0.56); bridgeC:Hide()
local bridgeD = Plate(12, 338, 837, 224, Theme.colors.bronzeDark, 0.62); bridgeD:Hide()
local bridgeE = Plate(286, 18, 744, 548, Theme.colors.stoneLift, 0.62); bridgeE:Hide()
local bridgeF = Plate(72, 32, 792, 552, Theme.colors.stoneLift, 0.78); bridgeF:Hide()
local shellLowerLeftPlate = Plate(950, 13, 66, 914, Theme.colors.stoneLift, 0.72); shellLowerLeftPlate:Hide()
local shellLowerRightPlate = Plate(548, 13, 1063, 914, Theme.colors.stoneLift, 0.72); shellLowerRightPlate:Hide()

-- Real-client contrast recovery pass: shell alphas raised (package values were
-- visually correct against the review composites but collapsed into the live
-- world background). Interpretive bridge deliberately left at package alpha --
-- it must remain the faintest element per the recovery brief.
local shellTop = Art(frame, "BACKGROUND", "ProgressionShellTop", 0.75390625, 1.0); shellTop:SetSize(1544, 16); shellTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 64, -88); shellTop:SetAlpha(0.58)
local shellLeft = Art(frame, "BACKGROUND", "ProgressionShellLeft", 0.6875, 0.7421875); shellLeft:SetSize(22, 760); shellLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 38, -118); shellLeft:SetAlpha(0.62)
local shellRight = Art(frame, "BACKGROUND", "ProgressionShellRight", 0.625, 0.7421875); shellRight:SetSize(20, 760); shellRight:SetPoint("TOPLEFT", frame, "TOPLEFT", 1613, -118); shellRight:SetAlpha(0.62)
-- ProgressionShellInterpretiveBridge stays at package alpha (.34) -- unchanged,
-- intentionally the faintest element in this recovery pass, not brightened.
local shellBridge = Art(frame, "BACKGROUND", "ProgressionShellInterpretiveBridge", 0.62890625, 0.74609375); shellBridge:SetSize(322, 382); shellBridge:SetPoint("TOPLEFT", frame, "TOPLEFT", 715, -184); shellBridge:SetAlpha(0.40)
local shellLowerLeft = Art(frame, "BACKGROUND", "ProgressionShellLowerLeft", 0.92773438, 0.8125); shellLowerLeft:SetSize(950, 13); shellLowerLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 66, -914); shellLowerLeft:SetAlpha(0.56)
local shellLowerRight = Art(frame, "BACKGROUND", "ProgressionShellLowerRight", 0.53515625, 0.8125); shellLowerRight:SetSize(548, 13); shellLowerRight:SetPoint("TOPLEFT", frame, "TOPLEFT", 1063, -914); shellLowerRight:SetAlpha(0.54)

-- HEADER DEFECT WATCH: crown/crownLeft/crownRight/crownSeam/crownRoot are all
-- Progression-owned scaffold (confirmed by source, this is not shared nav/HUD) --
-- crownLeft/crownRight are exactly the two flat gray rectangles flanking the
-- crown. All five are neutralized here and replaced by ProgressionKeystoneCrown.
local crown = Solid(frame, "ARTWORK", {0.055, 0.060, 0.070, 0.96})
crown:SetSize(570, 66)
crown:SetPoint("TOP", frame, "TOP", 0, -17)
crown:Hide()
local crownLeft = Solid(frame, "ARTWORK", Theme.colors.stoneLift)
crownLeft:SetSize(92, 38); crownLeft:SetPoint("RIGHT", crown, "LEFT", 22, 0)
crownLeft:Hide()
local crownRight = Solid(frame, "ARTWORK", Theme.colors.stoneLift)
crownRight:SetSize(92, 38); crownRight:SetPoint("LEFT", crown, "RIGHT", -22, 0)
crownRight:Hide()
local crownSeam = Solid(frame, "OVERLAY", Theme.colors.bronze)
crownSeam:SetSize(392, 2)
crownSeam:SetPoint("TOP", crown, "BOTTOM", 0, 0)
crownSeam:Hide()
local crownRoot = Solid(frame, "OVERLAY", Theme.colors.bronzeBright)
crownRoot:SetSize(4, 22); crownRoot:SetPoint("TOP", crown, "BOTTOM", 0, 0); crownRoot:SetAlpha(0.64)
crownRoot:Hide()
local crownArt = Art(frame, "ARTWORK", "ProgressionKeystoneCrown", 0.69335938, 0.515625); crownArt:SetSize(710, 66); crownArt:SetPoint("TOP", frame, "TOP", 0, -17); crownArt:SetAlpha(0.80)
local title = frame:CreateFontString(nil, "OVERLAY")
title:SetFont(Theme.fonts.monument, 27, "OUTLINE")
title:SetText("PROGRESSION")
title:SetTextColor(unpack(Theme.colors.text))
title:SetPoint("CENTER", crown, "CENTER", 0, 7)
local titleSub = frame:CreateFontString(nil, "OVERLAY")
titleSub:SetFont(Theme.fonts.readable, 11)
titleSub:SetText("MASTERY  ·  ATTUNEMENT  ·  RETAINED STATE")
titleSub:SetTextColor(unpack(Theme.colors.textMuted))
titleSub:SetPoint("CENTER", crown, "CENTER", 0, -17)

local function Place(control, x, y)
    control.root:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
    return control
end

local back = Place(UI.ProgressionRow:Create(frame, {
    id="back", name="EchoesUIProgressionBack", width=130, height=38, icon=false,
    compact=true, label="‹  BACK", value="", progress=0,
    onActivate=function() Screen:Leave("back") end,
}), 28, 24)
local home = Place(UI.ProgressionRow:Create(frame, {
    id="home", name="EchoesUIProgressionHome", width=130, height=38, icon=false,
    compact=true, label="CORE / HOME", value="", progress=0,
    onActivate=function() Screen:Leave("home") end,
}), 1368, 24)
local close = Place(UI.ProgressionRow:Create(frame, {
    id="close", name="EchoesUIProgressionClose", width=130, height=38, icon=false,
    compact=true, label="CLOSE  ×", value="", progress=0,
    onActivate=function() Screen:CloseCompanion() end,
}), 1514, 24)
Screen.back = back
Screen.home = home
Screen.close = close

local mastery = Place(UI.ProgressionZone:Create(frame, {
    id="mastery", name="EchoesUIProgressionMastery", width=650, height=455,
    title="MASTERY", subtitle="The Worldsoul interprets what you have permanently retained.",
    accentColor=Theme.colors.bronzeBright,
    tooltip="Mastery determines the share of attuned power retained as permanent growth.",
}), 55, 104)
Screen.mastery = mastery
-- Gate 1 (Progression): ProgressionMasteryZoneSupport/RetainedZoneSupport/
-- CurrentZoneSupport/SlotsZoneSupport replace each ProgressionZone's own native
-- shadow/surface/shoulder/foot at the SAME bounds as the zone's own root button,
-- parented directly to `frame` -- the zone's own child-Button frame level renders
-- its focusPlate/topSeam/retainers/title/subtitle (all OVERLAY) above this
-- automatically, so native focus/hover/selection is never buried.
mastery.shadow:Hide(); mastery.surface:Hide(); mastery.shoulder:Hide(); mastery.foot:Hide()
-- Real-client contrast recovery: Mastery is the strongest structural concentration
-- per the recovery brief -- pushed to the top of the suggested band.
local masterySupport = Art(frame, "ARTWORK", "ProgressionMasteryZoneSupport", 0.63476562, 0.88867188); masterySupport:SetSize(650, 455); masterySupport:SetPoint("TOPLEFT", frame, "TOPLEFT", 55, -104); masterySupport:SetAlpha(0.78)

-- Gate 1 (Progression): ProgressionMasteryApparatus replaces apparatusShadow/Seat/
-- Basin/cradle*/absorbGauge[*]/interpretationLine. Created before coreGlow (both
-- ARTWORK layer on mastery.content) so the native glow -- explicitly retained,
-- not neutralized -- keeps rendering on top of this backdrop by creation order.
-- Real-client contrast recovery: raised significantly -- this is the apparatus
-- directly surrounding the crystal, diagnosed as reading as an isolated icon
-- because the surrounding machinery had collapsed into the world.
local masteryApparatusArt = Art(mastery.content, "ARTWORK", "ProgressionMasteryApparatus", 0.59960938, 0.71679688); masteryApparatusArt:SetSize(614, 367); masteryApparatusArt:SetPoint("TOPLEFT", mastery.content, "TOPLEFT", 0, 0); masteryApparatusArt:SetAlpha(0.88)

local apparatusShadow = Solid(mastery.content, "BACKGROUND", {0.004, 0.008, 0.012, 0.94})
apparatusShadow:SetSize(188, 204); apparatusShadow:SetPoint("TOPLEFT", mastery.content, "TOPLEFT", 11, -5)
apparatusShadow:Hide()
local apparatusSeat = Solid(mastery.content, "ARTWORK", Theme.colors.stoneLift)
apparatusSeat:SetSize(170, 186); apparatusSeat:SetPoint("CENTER", apparatusShadow, "CENTER", 0, 0)
apparatusSeat:Hide()
local apparatusBasin = Solid(mastery.content, "ARTWORK", {0.012, 0.028, 0.042, 0.96})
apparatusBasin:SetSize(132, 148); apparatusBasin:SetPoint("CENTER", apparatusSeat, "CENTER", 0, 0)
apparatusBasin:Hide()
local coreGlow = Solid(mastery.content, "ARTWORK", Theme.colors.worldsoul)
coreGlow:SetSize(108, 126); coreGlow:SetPoint("CENTER", apparatusBasin, "CENTER", 0, 0); coreGlow:SetAlpha(0.12)
Screen.masteryCoreGlow = coreGlow
local core = mastery.content:CreateTexture(nil, "OVERLAY")
core:SetTexture("Interface\\Icons\\INV_Misc_Gem_Sapphire_02")
core:SetTexCoord(0.08, 0.92, 0.08, 0.92)
core:SetSize(82, 100); core:SetPoint("CENTER", coreGlow, "CENTER", 0, 0)
core:SetVertexColor(0.48, 0.86, 1.00, 0.88)
local cradleTop = Solid(mastery.content, "OVERLAY", Theme.colors.bronzeBright)
cradleTop:SetSize(120, 3); cradleTop:SetPoint("TOP", apparatusSeat, "TOP", 0, -12)
cradleTop:Hide()
local cradleBottom = Solid(mastery.content, "OVERLAY", Theme.colors.bronze)
cradleBottom:SetSize(120, 3); cradleBottom:SetPoint("BOTTOM", apparatusSeat, "BOTTOM", 0, 12)
cradleBottom:Hide()
local cradleLeft = Solid(mastery.content, "OVERLAY", Theme.colors.bronze)
cradleLeft:SetSize(3, 82); cradleLeft:SetPoint("LEFT", apparatusSeat, "LEFT", 13, 0)
cradleLeft:Hide()
local cradleRight = Solid(mastery.content, "OVERLAY", Theme.colors.bronze)
cradleRight:SetSize(3, 82); cradleRight:SetPoint("RIGHT", apparatusSeat, "RIGHT", -13, 0)
cradleRight:Hide()

Screen.absorbGauge = {}
for index = 1, 8 do
    local tick = Solid(mastery.content, "OVERLAY", Theme.colors.worldsoul)
    tick:SetSize(18 + (index % 2) * 8, 3)
    tick:SetPoint("TOPLEFT", mastery.content, "TOPLEFT", 165, -(22 + ((index - 1) * 18)))
    tick:SetAlpha(0.18)
    Screen.absorbGauge[index] = tick
end

local rankLabel = mastery.content:CreateFontString(nil, "OVERLAY")
rankLabel:SetFont(Theme.fonts.readable, 12)
rankLabel:SetText("MASTERY RANK")
rankLabel:SetTextColor(unpack(Theme.colors.textMuted))
rankLabel:SetPoint("TOPLEFT", mastery.content, "TOPLEFT", 234, -12)
local rankValue = mastery.content:CreateFontString(nil, "OVERLAY")
rankValue:SetFont(Theme.fonts.monument, 58, "OUTLINE")
rankValue:SetText("—")
rankValue:SetTextColor(unpack(Theme.colors.text))
rankValue:SetPoint("TOPLEFT", mastery.content, "TOPLEFT", 230, -35)
rankValue:SetWidth(120); rankValue:SetHeight(65); rankValue:SetJustifyH("LEFT")
Screen.rankValue = rankValue

local absorbLabel = mastery.content:CreateFontString(nil, "OVERLAY")
absorbLabel:SetFont(Theme.fonts.readable, 12)
absorbLabel:SetText("ABSORPTION")
absorbLabel:SetTextColor(unpack(Theme.colors.textMuted))
absorbLabel:SetPoint("TOPLEFT", mastery.content, "TOPLEFT", 396, -12)
local absorbValue = mastery.content:CreateFontString(nil, "OVERLAY")
absorbValue:SetFont(Theme.fonts.monument, 30, "OUTLINE")
absorbValue:SetText("—")
absorbValue:SetTextColor(unpack(Theme.colors.worldsoulPale))
absorbValue:SetPoint("TOPLEFT", mastery.content, "TOPLEFT", 394, -45)
Screen.absorbValue = absorbValue

local essenceLabel = mastery.content:CreateFontString(nil, "OVERLAY")
essenceLabel:SetFont(Theme.fonts.readable, 12)
essenceLabel:SetText("ESSENCE · AVAILABLE")
essenceLabel:SetTextColor(unpack(Theme.colors.textMuted))
essenceLabel:SetPoint("TOPLEFT", mastery.content, "TOPLEFT", 234, -126)
local essenceValue = mastery.content:CreateFontString(nil, "OVERLAY")
essenceValue:SetFont(Theme.fonts.monument, 24, "OUTLINE")
essenceValue:SetText("—")
essenceValue:SetTextColor(unpack(Theme.colors.text))
essenceValue:SetPoint("TOPLEFT", mastery.content, "TOPLEFT", 232, -151)
Screen.essenceValue = essenceValue

local interpretationLine = Solid(mastery.content, "ARTWORK", Theme.colors.bronzeDark)
interpretationLine:SetSize(368, 2); interpretationLine:SetPoint("TOPLEFT", mastery.content, "TOPLEFT", 226, -202)
interpretationLine:Hide()
local interpretationLabel = mastery.content:CreateFontString(nil, "OVERLAY")
interpretationLabel:SetFont(Theme.fonts.readable, 10)
interpretationLabel:SetText("INTERPRETATION CHANNEL")
interpretationLabel:SetTextColor(unpack(Theme.colors.textMuted))
interpretationLabel:SetPoint("TOPLEFT", mastery.content, "TOPLEFT", 234, -216)

-- Backing-alpha cleanup: same layering as the Current/Slot rows, but kept less
-- reduced (.55 vs .30-.32) since this is an actionable control, not a passive
-- reading row -- per the recovery brief, it may remain somewhat darker.
-- Dynamic State Supplement: native `selection` (hover/focus/pressed fill)
-- neutralized via focusColor alpha 0 -- state logic/hitbox untouched. Mastery's
-- Available/Pending overlay is data-driven (RefreshState/PurchaseMastery/OnAction),
-- not hover-driven, so no onStateChange hook is needed here.
local action = UI.ProgressionRow:Create(mastery.content, {
    id="masteryAction", name="EchoesUIProgressionMasteryAction", width=390, height=58,
    icon=false, label="RETAIN NEXT RANK", meta="Reading next-rank requirement", value="—",
    accentColor=Theme.colors.bronzeBright, focusColor={0, 0, 0, 0},
    progressColor=Theme.colors.bronzeBright,
    channelColor={0.018, 0.024, 0.030, 0.55},
    tooltip="Commit enough Essence to permanently retain the next Mastery rank.",
    onActivate=function() Screen:PurchaseMastery() end,
})
action.root:SetPoint("BOTTOMRIGHT", mastery.content, "BOTTOMRIGHT", -2, 20)
Screen.action = action
-- Gate 1 (Progression): ProgressionMasteryActuator backs the action row. BACKGROUND
-- layer (not the manifest's literal "ARTWORK"): ARTWORK would render above
-- ProgressionRow's native BACKGROUND-layer channel/selection, burying the
-- selection/focus glow -- same conflict class found and resolved during Visage.
do
    local seat = action.root:CreateTexture(nil, "BACKGROUND")
    seat:SetTexture(ASSET .. "ProgressionMasteryActuator")
    seat:SetTexCoord(0, 0.76171875, 0, 0.90625)
    seat:SetAllPoints(action.root)
    seat:SetAlpha(0.78)
end
-- Dynamic State Supplement: Available/Pending overlay, ARTWORK layer (above the
-- BACKGROUND seat, below native OVERLAY text/progress). Driven by Screen:RefreshState
-- (available) and Screen:PurchaseMastery/OnAction (pending) -- see MASTERY_STATE below.
local actionState = action.root:CreateTexture(nil, "ARTWORK")
actionState:SetAllPoints(action.root)
actionState:Hide()
Screen.actionState = actionState
local MASTERY_STATE = {
    available={"ProgressionMasteryStateAvailable",0.70}, pending={"ProgressionMasteryStatePending",0.72},
}
function Screen:UpdateMasteryState(key)
    if key then
        local entry = MASTERY_STATE[key]
        self.actionState:SetTexture(ASSET .. entry[1])
        self.actionState:SetTexCoord(0, 0.76171875, 0, 0.90625)
        self.actionState:SetAlpha(entry[2])
        self.actionState:Show()
    else
        self.actionState:Hide()
    end
end

mastery.onStateChange = function(_, focused, hovered, pressed)
    local awake = focused or hovered
    coreGlow:SetAlpha(pressed and 0.30 or (awake and 0.22 or 0.12))
    core:SetAlpha(pressed and 0.76 or (awake and 1.00 or 0.88))
    cradleTop:SetAlpha(awake and 1.00 or 0.64)
    cradleLeft:SetAlpha(awake and 0.88 or 0.52)
    cradleRight:SetAlpha(awake and 0.88 or 0.52)
end

local actionStatus = mastery.content:CreateFontString(nil, "OVERLAY")
actionStatus:SetFont(Theme.fonts.readable, 11)
actionStatus:SetText("")
actionStatus:SetTextColor(unpack(Theme.colors.textMuted))
actionStatus:SetPoint("BOTTOMRIGHT", mastery.content, "BOTTOMRIGHT", -4, 3)
actionStatus:SetWidth(390); actionStatus:SetHeight(16); actionStatus:SetJustifyH("RIGHT")
Screen.actionStatus = actionStatus

local history = Place(UI.ProgressionZone:Create(frame, {
    id="history", name="EchoesUIProgressionHistory", width=560, height=330,
    title="RETAINED RECORD", subtitle="Permanent measures carried by this character and class.",
    accentColor=Theme.colors.bronze,
    tooltip="This record preserves totals and absorbed attributes; individual items are not listed.",
}), 1055, 104)
Screen.history = history
history.shadow:Hide(); history.surface:Hide(); history.shoulder:Hide(); history.foot:Hide()
-- Real-client contrast recovery: Retained Record stays quieter than Mastery but
-- must not disappear -- "text floats over the world" was the diagnosed failure.
local historySupport = Art(frame, "ARTWORK", "ProgressionRetainedZoneSupport", 0.546875, 0.64453125); historySupport:SetSize(560, 330); historySupport:SetPoint("TOPLEFT", frame, "TOPLEFT", 1055, -104); historySupport:SetAlpha(0.74)

local countSeatA = Solid(history.content, "ARTWORK", {0.020, 0.024, 0.028, 0.92})
countSeatA:SetSize(232, 66); countSeatA:SetPoint("TOPLEFT", history.content, "TOPLEFT", 4, 4)
countSeatA:Hide()
local countSeatS = Solid(history.content, "ARTWORK", {0.020, 0.024, 0.028, 0.92})
countSeatS:SetSize(232, 66); countSeatS:SetPoint("TOPRIGHT", history.content, "TOPRIGHT", -4, 4)
countSeatS:Hide()
local retainedRail = Solid(history.content, "OVERLAY", Theme.colors.bronze)
retainedRail:SetSize(3, 51); retainedRail:SetPoint("LEFT", countSeatA, "LEFT", 0, 0); retainedRail:SetAlpha(0.62)
retainedRail:Hide()
local snapshotRail = Solid(history.content, "OVERLAY", Theme.colors.bronze)
snapshotRail:SetSize(3, 51); snapshotRail:SetPoint("LEFT", countSeatS, "LEFT", 0, 0); snapshotRail:SetAlpha(0.62)
snapshotRail:Hide()
-- Gate 1 (Progression): ProgressionRetainedCounts replaces countSeatA/S + rails.
local retainedCountsArt = Art(history.content, "ARTWORK", "ProgressionRetainedCounts", 0.9921875, 0.515625); retainedCountsArt:SetSize(508, 66); retainedCountsArt:SetPoint("TOPLEFT", history.content, "TOPLEFT", 4, -4); retainedCountsArt:SetAlpha(0.76)
local countA = history.content:CreateFontString(nil, "OVERLAY")
countA:SetFont(Theme.fonts.monument, 28, "OUTLINE"); countA:SetText("—")
countA:SetTextColor(unpack(Theme.colors.text)); countA:SetPoint("TOPLEFT", history.content, "TOPLEFT", 12, -2)
local countALabel = history.content:CreateFontString(nil, "OVERLAY")
countALabel:SetFont(Theme.fonts.readable, 11); countALabel:SetText("ATTUNED · THIS CHARACTER")
countALabel:SetTextColor(unpack(Theme.colors.textMuted)); countALabel:SetPoint("TOPLEFT", history.content, "TOPLEFT", 12, -39)
local countS = history.content:CreateFontString(nil, "OVERLAY")
countS:SetFont(Theme.fonts.monument, 28, "OUTLINE"); countS:SetText("—")
countS:SetTextColor(unpack(Theme.colors.text)); countS:SetPoint("TOPLEFT", history.content, "TOPLEFT", 285, -2)
local countSLabel = history.content:CreateFontString(nil, "OVERLAY")
countSLabel:SetFont(Theme.fonts.readable, 11); countSLabel:SetText("SNAPSHOTS · ACCOUNT / CLASS")
countSLabel:SetTextColor(unpack(Theme.colors.textMuted)); countSLabel:SetPoint("TOPLEFT", history.content, "TOPLEFT", 285, -39)
Screen.attunedValue = countA; Screen.snapshotsValue = countS

local absorbedHeading = history.content:CreateFontString(nil, "OVERLAY")
absorbedHeading:SetFont(Theme.fonts.readable, 11); absorbedHeading:SetText("ABSORBED ATTRIBUTES · RETAINED")
absorbedHeading:SetTextColor(unpack(Theme.colors.textMuted)); absorbedHeading:SetPoint("TOPLEFT", history.content, "TOPLEFT", 12, -88)
-- Gate 1 (Progression): ProgressionRetainedStatRail replaces the five channel/mark
-- pairs as one integrated five-seat rail.
local retainedStatRailArt = Art(history.content, "ARTWORK", "ProgressionRetainedStatRail", 0.9609375, 0.890625); retainedStatRailArt:SetSize(492, 57); retainedStatRailArt:SetPoint("TOPLEFT", history.content, "TOPLEFT", 7, -109); retainedStatRailArt:SetAlpha(0.74)
Screen.statValues = {}
for index, stat in ipairs({"STR","AGI","STA","INT","SPI"}) do
    local x = 12 + (index - 1) * 101
    local channel = Solid(history.content, "ARTWORK", {0.018, 0.021, 0.024, 0.90})
    channel:SetSize(88, 57); channel:SetPoint("TOPLEFT", history.content, "TOPLEFT", x - 5, -109)
    channel:Hide()
    local mark = Solid(history.content, "OVERLAY", Theme.colors.bronze)
    mark:SetSize(2, 42); mark:SetPoint("LEFT", channel, "LEFT", 0, 0); mark:SetAlpha(0.42)
    mark:Hide()
    local label = history.content:CreateFontString(nil, "OVERLAY")
    label:SetFont(Theme.fonts.readable, 10); label:SetText(stat)
    label:SetTextColor(unpack(Theme.colors.textMuted)); label:SetPoint("TOPLEFT", history.content, "TOPLEFT", x, -116)
    local value = history.content:CreateFontString(nil, "OVERLAY")
    value:SetFont(Theme.fonts.monument, 17, "OUTLINE"); value:SetText("+—")
    value:SetTextColor(unpack(Theme.colors.bronzeBright)); value:SetPoint("TOPLEFT", history.content, "TOPLEFT", x, -136)
    Screen.statValues[index] = value
end
local historyTruth = history.content:CreateFontString(nil, "OVERLAY")
historyTruth:SetFont(Theme.fonts.readable, 10)
historyTruth:SetText("Only retained totals are recorded here.")
historyTruth:SetTextColor(unpack(Theme.colors.textMuted))
historyTruth:SetPoint("BOTTOMLEFT", history.content, "BOTTOMLEFT", 12, 3)

local current = Place(UI.ProgressionZone:Create(frame, {
    id="current", name="EchoesUIProgressionCurrent", width=930, height=320,
    title="CURRENT ATTUNEMENT", subtitle="Equipped items currently resonating with the Worldsoul.",
    accentColor=Theme.colors.worldsoul,
}), 55, 588)
Screen.current = current
current.shadow:Hide(); current.surface:Hide(); current.shoulder:Hide(); current.foot:Hide()
-- Real-client contrast recovery: Current Attunement is the broadest evidence
-- region -- raised so the rows read as belonging to one unified reading field.
local currentSupport = Art(frame, "ARTWORK", "ProgressionCurrentZoneSupport", 0.90820312, 0.625); currentSupport:SetSize(930, 320); currentSupport:SetPoint("TOPLEFT", frame, "TOPLEFT", 55, -588); currentSupport:SetAlpha(0.68)
Screen.currentRows = {}
-- Gate 1 (Progression): each row gets a `bed` texture cycling through
-- ProgressionCurrent{Resting,Selected,Complete,Empty,Top,Bottom} in Screen:RefreshEquipped
-- based on real native state (item presence, completion, keyboard focus, row
-- position) -- never a hardcoded composite state. BACKGROUND layer (not the
-- manifest's literal "ARTWORK"): see the MasteryActuator note above for why.
for index = 1, 5 do
    -- Backing-alpha cleanup: native `channel` (created inside ProgressionRow:Create,
    -- BACKGROUND layer, same as our `bed` art but created first) is re-asserted to
    -- .74-.92 alpha every Render() by the shared component. Its own base color alpha
    -- (channelColor, normally defaulting to .88) multiplies with that -- lowering it
    -- here reduces the effective result without touching the shared component, so
    -- Rack/Forge/Visage rows are unaffected. Shows through only in `bed`'s own
    -- transparent art regions, so this is a soft tint behind the machinery, not a
    -- removal of text-contrast support.
    -- Dynamic State Supplement: native `selection` (hover/focus/pressed fill,
    -- BACKGROUND layer) neutralized via focusColor alpha 0 -- state logic and
    -- hitbox untouched; onStateChange drives the new sparse overlay instead.
    -- REGRESSION FIX: onStateChange must NOT be passed inside Create()'s options --
    -- ProgressionRow:Create() calls Render() (which immediately invokes
    -- onStateChange) before returning, i.e. before `row.state` exists below. That
    -- threw a nil-index Lua error at addon-load time, on the FIRST row created,
    -- which aborted the rest of this file's top-level execution -- including the
    -- UI.ScreenManager:Register("progression", ...) call at the very end -- so
    -- Progression was never registered as a navigable screen at all. Assigning
    -- onStateChange as a plain field AFTER row.state is created (below) fixes
    -- this: Create()'s own internal Render() call simply finds onStateChange nil
    -- and skips it, exactly as it does for every other row on every other screen.
    local row = UI.ProgressionRow:Create(current.content, {
        id="attunement" .. index, width=878, height=43, valueWidth=92,
        label="Empty equipment channel", meta="No tracked item", value="—", progress=0,
        accentColor=Theme.colors.worldsoul, progressColor=Theme.colors.worldsoul,
        channelColor={0.018, 0.024, 0.030, 0.30},
        focusColor={0, 0, 0, 0},
    })
    row.root:SetPoint("TOPLEFT", current.content, "TOPLEFT", 0, -((index - 1) * 45))
    local bed = row.root:CreateTexture(nil, "BACKGROUND")
    bed:SetAllPoints(row.root)
    row.bed = bed
    local state = row.root:CreateTexture(nil, "ARTWORK")
    state:SetAllPoints(row.root)
    state:Hide()
    row.state = state
    row.onStateChange = function(r) UpdateRowState(r, CURRENT_STATE, 0.85742188, 0.671875) end
    Screen.currentRows[index] = row
end

local slots = Place(UI.ProgressionZone:Create(frame, {
    id="slots", name="EchoesUIProgressionSlots", width=560, height=448,
    title="SLOT SPECIALIZATION", subtitle="Automatic long-term development by equipment slot.",
    accentColor=Theme.colors.bronzeBright,
    tooltip="Slot specialization grows automatically from repeated use; it is not a spending system.",
}), 1055, 460)
Screen.slots = slots
slots.shadow:Hide(); slots.surface:Hide(); slots.shoulder:Hide(); slots.foot:Hide()
local slotsSupport = Art(frame, "ARTWORK", "ProgressionSlotsZoneSupport", 0.546875, 0.875); slotsSupport:SetSize(560, 448); slotsSupport:SetPoint("TOPLEFT", frame, "TOPLEFT", 1055, -460); slotsSupport:SetAlpha(0.56)
Screen.slotRows = {}
-- Gate 1 (Progression): each row gets a `bed` texture cycling through
-- ProgressionSlot{Resting,Developed,Selected,Resolving,Terminus} in Screen:RefreshSlots.
for index = 1, 7 do
    -- Backing-alpha cleanup: see the identical note on the Current Attunement rows above.
    -- Dynamic State Supplement + REGRESSION FIX: see the identical note on the
    -- Current Attunement rows above -- onStateChange assigned after row.state exists.
    local row = UI.ProgressionRow:Create(slots.content, {
        id="slot" .. index, width=486, height=43, icon=false, valueWidth=76,
        label="Slot", meta="Level 0 · 0 XP", value="+0.0%", progress=0,
        accentColor=Theme.colors.bronzeBright, progressColor=Theme.colors.bronzeBright,
        channelColor={0.018, 0.024, 0.030, 0.32},
        focusColor={0, 0, 0, 0},
    })
    row.root:SetPoint("TOPLEFT", slots.content, "TOPLEFT", 0, -((index - 1) * 45))
    local bed = row.root:CreateTexture(nil, "BACKGROUND")
    bed:SetAllPoints(row.root)
    row.bed = bed
    local state = row.root:CreateTexture(nil, "ARTWORK")
    state:SetAllPoints(row.root)
    state:Hide()
    row.state = state
    row.onStateChange = function(r) UpdateRowState(r, SLOT_STATE, 0.94921875, 0.671875) end
    Screen.slotRows[index] = row
end
local scrollTrack = Solid(slots.content, "ARTWORK", {0.012, 0.016, 0.020, 0.94})
scrollTrack:SetSize(6, 291); scrollTrack:SetPoint("TOPRIGHT", slots.content, "TOPRIGHT", -2, -9)
scrollTrack:Hide()
local scrollTop = Solid(slots.content, "OVERLAY", Theme.colors.bronze)
scrollTop:SetSize(12, 2); scrollTop:SetPoint("TOP", scrollTrack, "TOP", 0, 6); scrollTop:SetAlpha(0.66)
scrollTop:Hide()
local scrollBottom = Solid(slots.content, "OVERLAY", Theme.colors.bronze)
scrollBottom:SetSize(12, 2); scrollBottom:SetPoint("BOTTOM", scrollTrack, "BOTTOM", 0, -6); scrollBottom:SetAlpha(0.66)
scrollBottom:Hide()
local scrollThumb = Solid(slots.content, "OVERLAY", Theme.colors.bronzeBright)
scrollThumb:SetSize(4, 118); scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -1)
scrollThumb:Hide()
-- Gate 1 (Progression): ProgressionScrollSpine replaces track+top+bottom caps as
-- one continuous spine. The hidden scrollTrack is kept as the pure positioning
-- reference (its own anchor never moves) so Screen:RefreshSlots' thumb-position
-- math is untouched.
local scrollSpineArt = Art(slots.content, "ARTWORK", "ProgressionScrollSpine", 0.75, 0.59179688); scrollSpineArt:SetSize(12, 303); scrollSpineArt:SetPoint("TOPRIGHT", slots.content, "TOPRIGHT", -5, -3); scrollSpineArt:SetAlpha(0.68)
-- ProgressionScrollThumb becomes the new Screen.slotScrollThumb so the existing
-- dynamic SetPoint repositioning in RefreshSlots continues to move the fabricated art.
local scrollThumbArt = Art(slots.content, "OVERLAY", "ProgressionScrollThumb", 1.0, 0.921875); scrollThumbArt:SetSize(4, 118); scrollThumbArt:SetPoint("TOP", scrollTrack, "TOP", 0, -1); scrollThumbArt:SetAlpha(0.86)
Screen.slotScrollTrack = scrollTrack
Screen.slotScrollThumb = scrollThumbArt
local scrollPosition = slots.content:CreateFontString(nil, "OVERLAY")
scrollPosition:SetFont(Theme.fonts.readable, 9)
scrollPosition:SetText("1–7 / 17")
scrollPosition:SetTextColor(unpack(Theme.colors.textMuted))
scrollPosition:SetPoint("BOTTOMRIGHT", slots.content, "BOTTOMRIGHT", -1, 2)
Screen.slotScrollPosition = scrollPosition

-- Compact Chaos reading in the documented bridge-foot terminus band. This is
-- informational only and deliberately does not become a fifth Progression zone.
local chaosReadout = CreateFrame("Frame", "EchoesUIProgressionChaosReadout", frame)
chaosReadout:SetSize(322, 28)
chaosReadout:SetPoint("TOPLEFT", frame, "TOPLEFT", 715, -558)
chaosReadout:EnableMouse(true)
local chaosBack = Solid(chaosReadout, "BACKGROUND", {0.008,0.011,0.016,0.78})
chaosBack:SetAllPoints(chaosReadout)
local chaosEdge = Solid(chaosReadout, "ARTWORK", Theme.colors.worldsoul)
chaosEdge:SetSize(3, 22); chaosEdge:SetPoint("LEFT", chaosReadout, "LEFT", 0, 0); chaosEdge:SetAlpha(0.68)
local chaosText = chaosReadout:CreateFontString(nil, "OVERLAY")
chaosText:SetFont(Theme.fonts.readable, 11)
chaosText:SetTextColor(unpack(Theme.colors.text))
chaosText:SetPoint("CENTER", chaosReadout, "CENTER", 0, 0)
chaosText:SetWidth(306); chaosText:SetJustifyH("CENTER")
chaosReadout:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:ClearLines()
    GameTooltip:AddLine("Chaos Power", 0.65, 0.88, 1)
    GameTooltip:AddLine("A reading of your accumulated Echoes progression. It is not a spendable resource and does not replace your actual attributes.", 0.88, 0.82, 0.68, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Magnitude", 0.65, 0.88, 1)
    GameTooltip:AddLine("The number order used to express Chaos values. A new Magnitude changes notation, not combat difficulty.", 0.88, 0.82, 0.68, true)
    GameTooltip:Show()
end)
chaosReadout:SetScript("OnLeave", function() GameTooltip:Hide() end)
Screen.chaosReadout, Screen.chaosText = chaosReadout, chaosText
UI.Chaos:Subscribe(function(state)
    chaosText:SetText("CHAOS POWER  "..UI.Chaos:GetPowerText().."    |    "..UI.Chaos:GetMagnitudeDisplayText())
    if state.enabled then chaosReadout:Show() else chaosReadout:Hide() end
end)

local ordered = {"back","home","close","mastery","masteryAction","history"}
for i=1,5 do ordered[#ordered+1] = "attunement"..i end
for i=1,7 do ordered[#ordered+1] = "slot"..i end
local input = UI.InputManager:New(frame)
Screen.input = input
input:Add(back,"back"); input:Add(home,"home"); input:Add(close,"close"); input:Add(mastery,"mastery"); input:Add(action,"masteryAction"); input:Add(history,"history")
for i,row in ipairs(Screen.currentRows) do input:Add(row,"attunement"..i) end
for i,row in ipairs(Screen.slotRows) do input:Add(row,"slot"..i) end
input:SetNavigation(ordered, {
    back={RIGHT="mastery",DOWN="mastery"}, home={LEFT="history",RIGHT="close",DOWN="history"},
    close={LEFT="home",DOWN="history"},
    mastery={UP="back",RIGHT="history",DOWN="masteryAction"},
    masteryAction={UP="mastery",RIGHT="slot1",DOWN="attunement1"},
    history={UP="home",LEFT="mastery",RIGHT="close",DOWN="slot1"},
    attunement1={UP="masteryAction",RIGHT="slot4",DOWN="attunement2"},
    attunement2={UP="attunement1",RIGHT="slot4",DOWN="attunement3"},
    attunement3={UP="attunement2",RIGHT="slot5",DOWN="attunement4"},
    attunement4={UP="attunement3",RIGHT="slot6",DOWN="attunement5"},
    attunement5={UP="attunement4",RIGHT="slot7",DOWN="back"},
    slot1={UP="history",LEFT="masteryAction",DOWN="slot2"},
    slot2={UP="slot1",LEFT="attunement1",DOWN="slot3"},
    slot3={UP="slot2",LEFT="attunement2",DOWN="slot4"},
    slot4={UP="slot3",LEFT="attunement2",DOWN="slot5"},
    slot5={UP="slot4",LEFT="attunement3",DOWN="slot6"},
    slot6={UP="slot5",LEFT="attunement4",DOWN="slot7"},
    slot7={UP="slot6",LEFT="attunement5",DOWN="home"},
})
input.defaultFocusId = "mastery"
input.onEscape = function() Screen:Leave("back") end
input.onNavigate = function(key, focusId)
    if focusId == "slot7" and key == "DOWN" and Screen:ScrollSlots(1) then return true end
    if focusId == "slot1" and key == "UP" and Screen:ScrollSlots(-1) then return true end
    if focusId == "attunement5" and key == "DOWN" and Screen:ScrollEquipped(1) then return true end
    if focusId == "attunement1" and key == "UP" and Screen:ScrollEquipped(-1) then return true end
    return false
end

local function ParseStats(value)
    local result = {0,0,0,0,0}
    local index = 1
    for part in tostring(value or ""):gmatch("[^/]+") do
        if index > 5 then break end
        result[index] = tonumber(part) or 0
        index = index + 1
    end
    return result
end

local function ParseSlots(value)
    local xp = {}
    for slot, amount in tostring(value or ""):gmatch("(%d+):(%d+)") do xp[tonumber(slot)] = tonumber(amount) or 0 end
    return xp
end

local function FormatInteger(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    local sign, digits = text:match("^([%-]?)(%d+)$")
    if not digits then return text end
    while true do
        local nextDigits, count = digits:gsub("^(%d+)(%d%d%d)", "%1,%2")
        digits = nextDigits
        if count == 0 then break end
    end
    return sign .. digits
end

local function Shorten(value, limit)
    local text = tostring(value or "")
    limit = limit or 38
    if #text <= limit then return text end
    return text:sub(1, limit - 3) .. "..."
end

-- Current/Slot bed variant selection (asset-specs.json TexCoord is identical across
-- every variant within a family, so only SetTexture path + SetAlpha change).
-- Visibility recovery pass: Group C (Current) / Group D (Slot) bed alphas raised.
-- Progress bars/complete marks are OVERLAY-layer native and unaffected by this.
local CURRENT_BED = {
    resting={"ProgressionCurrentResting",0.70}, selected={"ProgressionCurrentSelected",0.82},
    complete={"ProgressionCurrentComplete",0.78}, empty={"ProgressionCurrentEmpty",0.50},
    top={"ProgressionCurrentTop",0.66}, bottom={"ProgressionCurrentBottom",0.66},
}
local SLOT_BED = {
    resting={"ProgressionSlotResting",0.52}, developed={"ProgressionSlotDeveloped",0.64},
    selected={"ProgressionSlotSelected",0.76}, resolving={"ProgressionSlotResolving",0.54},
    terminus={"ProgressionSlotTerminus",0.54},
}
local function SetBed(bed, table_, key, uMax, vMax)
    local entry = table_[key]
    bed:SetTexture(ASSET .. entry[1])
    bed:SetTexCoord(0, uMax, 0, vMax)
    bed:SetAlpha(entry[2])
end

function Screen:WakeMastery(success)
    if not self.masteryCoreGlow then return end
    self.masteryCoreGlow:SetAlpha(success and 0.34 or 0.22)
    if UI:IsReducedMotion() then self.masteryCoreGlow:SetAlpha(0.16); return end
    local token = self.actionToken
    C_Timer.After(success and 0.46 or 0.24, function()
        if Screen.active and Screen.actionToken == token then Screen.masteryCoreGlow:SetAlpha(0.12) end
    end)
end

function Screen:RefreshState(values)
    values = values or UI.StateStore.values or {}
    local essence = tonumber(values.essence) or 0
    local rank = tonumber(values.mastery_rank) or 0
    local cost = tonumber(values.mastery_next_cost)
    self.rankValue:SetText(tostring(rank))
    local absorption = tonumber(values.absorb_pct)
    self.absorbValue:SetText(absorption and string.format("%.1f%%", absorption) or "—")
    local activeTicks = absorption and math.max(0, math.min(8, math.ceil((absorption / 100) * 8))) or 0
    for index,tick in ipairs(self.absorbGauge) do tick:SetAlpha(index <= activeTicks and 0.88 or 0.18) end
    self.essenceValue:SetText(FormatInteger(essence))
    self.attunedValue:SetText(FormatInteger(values.attuned or 0))
    self.snapshotsValue:SetText(FormatInteger(values.snapshots or 0))
    if values.absorbed_stats ~= nil then
        local stats = ParseStats(values.absorbed_stats)
        for index,value in ipairs(stats) do self.statValues[index]:SetText(string.format("+%.1f", value)) end
    else
        for _,value in ipairs(self.statValues) do value:SetText("+—") end
    end

    if cost then
        local affordable = essence >= cost
        self.action:SetData({
            label=affordable and "RETAIN NEXT RANK" or "ESSENCE REQUIRED",
            meta="Rank " .. rank .. " → " .. (rank + 1) .. " · " .. FormatInteger(essence) .. " available",
            value=FormatInteger(cost),
            progress=cost > 0 and math.min(1, essence / cost) or 0,
            strength=affordable and 1 or 0.35,
            tooltip="The next Mastery rank requires " .. FormatInteger(cost) .. " Essence.",
        })
        self.action:SetEnabled(affordable and not self.actionPending)
        -- Dynamic State Supplement: pending (set by PurchaseMastery) outranks available.
        self:UpdateMasteryState(self.actionPending and "pending" or (affordable and "available" or nil))
    else
        self.action:SetData({label="RETAIN NEXT RANK",
            meta="Reading the next-rank requirement", value="—",progress=0,
            tooltip="The Progression machine is still resolving this requirement."})
        self.action:SetEnabled(false)
        self:UpdateMasteryState(nil)
    end

    self.hasSlotState = values.slots ~= nil
    self.slotXP = ParseSlots(values.slots)
    self:RefreshSlots()
end

function Screen:RefreshSlots()
    for rowIndex,row in ipairs(self.slotRows) do
        local def = SLOT_DEFS[self.slotOffset + rowIndex]
        if def then
            if not self.hasSlotState then
                row.contentState = nil
                row:SetData({label=def[3],meta="Reading accumulated development",value="—",progress=0,
                    tooltip="The machine is still resolving this specialization."})
                row.root:Show(); row:SetEnabled(true)
                SetBed(row.bed, SLOT_BED, "resolving", 0.94921875, 0.671875)
            else
                local xp = (self.slotXP and self.slotXP[def[1]]) or 0
                local level = math.floor(math.sqrt(xp / 20))
                local bonus = 1.8 * math.sqrt(level)
                local nextLevelXP = 20 * ((level + 1) ^ 2)
                local levelBaseXP = 20 * (level ^ 2)
                local progress = nextLevelXP > levelBaseXP
                    and (xp - levelBaseXP) / (nextLevelXP - levelBaseXP) or 0
                -- Dynamic State Supplement: contentState set before SetData so the
                -- onStateChange it triggers (via Row:Render()) sees the correct value.
                row.contentState = level > 0 and "developed" or nil
                row:SetData({label=def[3],meta="Level "..level.." · "..FormatInteger(xp).." XP",
                    value=string.format("+%.1f%%", bonus),progress=progress,
                    strength=level > 0 and math.min(1, 0.35 + (level * 0.10)) or 0,
                    tooltip=def[3].." specialization grows automatically through repeated equipment-slot use."})
                row.root:Show(); row:SetEnabled(true)
                -- Variant priority: keyboard focus > real developed progress >
                -- terminus cap (last visible row, undeveloped) > resting default.
                if row.focused then SetBed(row.bed, SLOT_BED, "selected", 0.94921875, 0.671875)
                elseif level > 0 then SetBed(row.bed, SLOT_BED, "developed", 0.94921875, 0.671875)
                elseif rowIndex == #self.slotRows then SetBed(row.bed, SLOT_BED, "terminus", 0.94921875, 0.671875)
                else SetBed(row.bed, SLOT_BED, "resting", 0.94921875, 0.671875) end
            end
        else row.root:Hide(); row:SetEnabled(false) end
    end
    local maximum = math.max(1, #SLOT_DEFS - #self.slotRows)
    local travel = 171
    self.slotScrollThumb:ClearAllPoints()
    self.slotScrollThumb:SetPoint("TOP", self.slotScrollTrack, "TOP", 0, -(1 + ((self.slotOffset / maximum) * travel)))
    self.slotScrollPosition:SetText((self.slotOffset + 1) .. "–" .. math.min(#SLOT_DEFS,
        self.slotOffset + #self.slotRows) .. " / " .. #SLOT_DEFS)
end

function Screen:RefreshEquipped()
    for rowIndex,row in ipairs(self.currentRows) do
        local item = self.equipped[self.equippedOffset + rowIndex]
        if item then
            local data = item.attunement
            local eligible = data and not data.ineligible
            local progress = eligible and data.cap > 0 and math.min(1, data.prog / data.cap) or 0
            local pct = eligible and math.floor(progress * 100) or nil
            local complete = eligible and data.prog >= data.cap
            -- Dynamic State Supplement: contentState set before SetData so the
            -- onStateChange it triggers (via Row:Render()) sees the correct value.
            row.contentState = complete and "complete" or nil
            row:SetData({
                label=Shorten(item.name, 44), icon=item.icon,
                meta=item.slotName .. (eligible and (" · "..FormatInteger(data.prog).." / "..FormatInteger(data.cap)) or (data and " · not attunable" or " · reading resonance")),
                value=eligible and (data.prog >= data.cap and "ATTUNED" or (pct.."%")) or (data and "—" or "READING"),
                progress=progress, complete=complete,
                strength=eligible and math.max(0.20, progress) or 0.10,
                tooltip=item.name, tooltipLink=item.link,
            })
            row.root:Show(); row:SetEnabled(true)
            -- Variant priority: complete > keyboard focus (selected) > top/bottom
            -- termination caps (row position) > resting default.
            if complete then SetBed(row.bed, CURRENT_BED, "complete", 0.85742188, 0.671875)
            elseif row.focused then SetBed(row.bed, CURRENT_BED, "selected", 0.85742188, 0.671875)
            elseif rowIndex == 1 then SetBed(row.bed, CURRENT_BED, "top", 0.85742188, 0.671875)
            elseif rowIndex == #self.currentRows then SetBed(row.bed, CURRENT_BED, "bottom", 0.85742188, 0.671875)
            else SetBed(row.bed, CURRENT_BED, "resting", 0.85742188, 0.671875) end
        else
            local firstEmpty = rowIndex == 1 or self.equippedOffset + rowIndex == #self.equipped + 1
            row.contentState = nil
            row:SetData({
                label=firstEmpty and (#self.equipped == 0 and "NO ATTUNABLE EQUIPMENT DETECTED" or "NO FURTHER ATTUNEMENT") or "UNUSED RESONANCE CHANNEL",
                meta=firstEmpty and (#self.equipped == 0 and "Equip a tracked item to begin resonance" or "All tracked equipment is shown") or "",
                value="—",progress=0,
            })
            row.root:Show(); row:SetEnabled(false)
            SetBed(row.bed, CURRENT_BED, "empty", 0.85742188, 0.671875)
        end
    end
end

function Screen:BuildEquippedQueue()
    self.equipped = {}
    self.equippedByEntry = {}
    self.requestQueue = {}
    for _,def in ipairs(ATTUNEMENT_SLOTS) do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", def[2])
        local entry = link and tonumber(link:match("item:(%d+)"))
        if entry and entry ~= 900010 and entry ~= 900011 then
            local name, icon
            if GetItemInfo then
                name, _, _, _, _, _, _, _, _, icon = GetItemInfo(link)
            end
            if not icon and GetInventoryItemTexture then icon = GetInventoryItemTexture("player", def[2]) end
            local item = {entry=entry,link=link,name=name or "Equipped item",icon=icon,slotName=def[3]}
            self.equipped[#self.equipped+1] = item
            if not self.equippedByEntry[entry] then
                self.equippedByEntry[entry] = {}
                self.requestQueue[#self.requestQueue+1] = item
            end
            self.equippedByEntry[entry][#self.equippedByEntry[entry]+1] = item
        end
    end
    self.equippedOffset = 0
    self.queueIndex = 1
    self:RefreshEquipped()
    self:RequestNextAttunement()
    local token = self.openToken
    for _,delay in ipairs({0.25, 1.0}) do
        C_Timer.After(delay, function()
            if Screen.active and Screen.openToken == token then Screen:RefreshItemMetadata() end
        end)
    end
end

function Screen:RefreshItemMetadata()
    if not GetItemInfo then return end
    local changed = false
    for _,item in ipairs(self.equipped) do
        if item.name == "Equipped item" or not item.icon then
            local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(item.link)
            if name then item.name = name; changed = true end
            if icon then item.icon = icon; changed = true end
        end
    end
    if changed then self:RefreshEquipped() end
end

function Screen:RequestNextAttunement()
    if not self.active then return end
    local item = self.requestQueue[self.queueIndex or 1]
    if not item then return end
    self.queueIndex = (self.queueIndex or 1) + 1
    self.waitingEntry = item.entry
    if APB and APB.RequestAttunement then APB:RequestAttunement(item.entry) end
    local token = self.openToken
    C_Timer.After(4.2, function()
        if Screen.active and Screen.openToken == token and Screen.waitingEntry == item.entry then
            Screen.waitingEntry = nil
            Screen:RequestNextAttunement()
        end
    end)
end

function Screen:OnAttunement(data)
    local items = data and self.equippedByEntry[data.entry]
    if items then
        for _,item in ipairs(items) do item.attunement = data end
        self:RefreshEquipped()
    end
    if data and self.waitingEntry == data.entry then
        self.waitingEntry = nil
        self:RequestNextAttunement()
    end
end

function Screen:PurchaseMastery()
    if self.actionPending or not APB or not APB.RequestEchoesAction then return end
    self.actionPending = true
    self.awaitingPurchaseResult = true
    self.awaitingPurchaseRefresh = false
    self.actionToken = (self.actionToken or 0) + 1
    local token = self.actionToken
    self.action:SetEnabled(false)
    self.action:SetData({label="RETAINING MASTERY", meta="Committing permanent progression",
        value=self.action.value:GetText(), progress=self.action.progressValue or 0, strength=1})
    self:UpdateMasteryState("pending")
    self.actionStatus:SetText("The apparatus is retaining this rank…")
    self:WakeMastery(false)
    APB:RequestEchoesAction("mastery_purchase")
    UI:Debug("purchase activated -> mastery_purchase action sent")
    C_Timer.After(5.0, function()
        if Screen.active and Screen.actionToken == token and Screen.awaitingPurchaseResult then
            Screen.awaitingPurchaseResult = false
            Screen.actionPending = false
            Screen.actionStatus:SetText("The apparatus did not answer. State is being read again.")
            if APB.RequestEchoesState then APB:RequestEchoesState() end
            Screen:RefreshState(UI.StateStore.values)
        end
    end)
end

function Screen:OnAction(verb, fields)
    if fields.action and fields.action ~= "mastery_purchase" then return end
    if verb == "ERROR" and not self.actionPending then return end
    if verb == "ACTION_OK" then
        local messages = {
            SUCCESS="Mastery retained.", INSUFFICIENT_ESSENCE="Not enough Essence.",
            INVALID_PLAYER="Your progression could not be read.", DATABASE_FAILURE="Retention failed; try again.",
        }
        self.actionStatus:SetText(messages[fields.status] or ("Mastery: "..tostring(fields.status)))
    else
        self.actionStatus:SetText("Retention could not be completed. Try again.")
    end
    self.awaitingPurchaseResult = false
    self.awaitingPurchaseRefresh = verb == "ACTION_OK" and fields.status == "SUCCESS"
    self.actionPending = self.awaitingPurchaseRefresh
    UI:Debug("mastery_purchase result=" .. tostring(fields.status or fields.code))
    if APB.RequestEchoesState then APB:RequestEchoesState() end
    if verb == "ACTION_OK" and fields.status == "SUCCESS" then self:WakeMastery(true) end
    self:RefreshState(UI.StateStore.values)
    if self.awaitingPurchaseRefresh then
        local token = self.actionToken
        C_Timer.After(4.0, function()
            if Screen.active and Screen.actionToken == token and Screen.awaitingPurchaseRefresh then
                Screen.awaitingPurchaseRefresh = false
                Screen.actionPending = false
                Screen.actionStatus:SetText("Mastery retained. The new measure is still settling.")
                Screen:RefreshState(UI.StateStore.values)
            end
        end)
    end
end

function Screen:ScrollEquipped(delta)
    local maximum = math.max(0, #self.equipped - #self.currentRows)
    local nextOffset = math.max(0, math.min(maximum, self.equippedOffset + delta))
    if nextOffset == self.equippedOffset then return false end
    self.equippedOffset = nextOffset
    self:RefreshEquipped()
    return true
end

function Screen:ScrollSlots(delta)
    local maximum = math.max(0, #SLOT_DEFS - #self.slotRows)
    local nextOffset = math.max(0, math.min(maximum, self.slotOffset + delta))
    if nextOffset == self.slotOffset then return false end
    self.slotOffset = nextOffset
    self:RefreshSlots()
    return true
end

if current.root.EnableMouseWheel then
    current.root:EnableMouseWheel(true)
    current.root:SetScript("OnMouseWheel", function(_, delta) Screen:ScrollEquipped(delta < 0 and 1 or -1) end)
end
if slots.root.EnableMouseWheel then
    slots.root:EnableMouseWheel(true)
    slots.root:SetScript("OnMouseWheel", function(_, delta) Screen:ScrollSlots(delta < 0 and 1 or -1) end)
end

function Screen:UpdateScale()
    local width = UIParent:GetWidth() or 1672
    local height = UIParent:GetHeight() or 941
    self.frame:SetScale(math.min(width / 1672, height / 941))
end

function Screen:Show()
    self.openToken = self.openToken + 1
    self.active = true
    self.equippedOffset = 0
    self.slotOffset = 0
    self:UpdateScale()
    if APB and APB.C43 and APB.C43.frame then APB.C43.frame:Hide() end
    self.frame:SetAlpha(UI:IsReducedMotion() and 1 or 0)
    self.frame:Show()
    Animation:Alpha(self.frame, 1, 0.24)
    self.input:SetFocusById("mastery")
    self:RefreshState(UI.StateStore.values)
    self:BuildEquippedQueue()
    local _,stamp = UI.StateStore:GetSnapshot()
    local age = stamp and (GetTime() - stamp) or nil
    if APB and APB.RequestEchoesState and (not age or age < 0 or age > 0.75) then APB:RequestEchoesState() end
    UI:Debug("progression screen opened -> live state requested/consumed")
end

function Screen:Hide()
    self.openToken = self.openToken + 1
    self.active = false
    self.waitingEntry = nil
    self.awaitingPurchaseResult = false
    self.awaitingPurchaseRefresh = false
    self.actionPending = false
    self.input:ClearFocus()
    Animation:Stop(self.frame)
    self.frame:Hide()
end

function Screen:Leave(destination)
    self:Hide()
    local focusId = destination == "home" and "core" or "progression"
    if UI.DashboardGateB and UI.ScreenManager:Show("dashboardGateB", false, focusId) then return end
    UI.ScreenManager.current = nil
    if APB and APB.C43 then APB.C43:Show() end
end

function Screen:CloseCompanion()
    self:Hide()
    UI.ScreenManager.current = nil
    UI.ScreenManager.history = {}
    if APB and APB.C43 and APB.C43.Hide then APB.C43:Hide() end
end

UI.StateStore:Subscribe(function(values)
    if not Screen.active then return end
    if Screen.awaitingPurchaseRefresh then
        Screen.awaitingPurchaseRefresh = false
        Screen.actionPending = false
        Screen.actionStatus:SetText("Mastery retained.")
        Screen:WakeMastery(true)
    end
    Screen:RefreshState(values)
    UI:Debug("state received -> progression UI populated")
end)
if APB and APB.SubscribeAttunement then APB:SubscribeAttunement(function(data) Screen:OnAttunement(data) end) end
if APB and APB.SubscribeEchoesActions then APB:SubscribeEchoesActions(function(verb, fields) Screen:OnAction(verb, fields) end) end

UI.ProgressionScreen = Screen
UI.ScreenManager:Register("progression", Screen, false)
UI.modules.ProgressionScreen = true
