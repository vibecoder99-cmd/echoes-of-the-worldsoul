local UI = EchoesUI
if not UI or not UI.IconButton or not UI.Landmark or not UI.CoreWidget
    or not UI.ResourceDisplay or not APB or not APB.C43 then return end

local ADDON_NAME = "EchoesOfTheWorldsoulBridge"
local Theme = UI.Theme
local Animation = UI.AnimationController
local C43 = APB.C43
local dashboard = C43.frame

local orderedIds = {
    "codex", "search", "talents", "rack", "visage", "core",
    "progression", "threat", "crucible", "forge",
    "accessibility", "settings", "close",
}

local navigation = {
    core={UP="progression",DOWN="visage",LEFT="rack",RIGHT="crucible"},
    progression={UP="codex",DOWN="core",LEFT="talents",RIGHT="threat"},
    talents={UP="codex",DOWN="rack",LEFT="search",RIGHT="progression"},
    threat={UP="settings",DOWN="crucible",LEFT="progression",RIGHT="accessibility"},
    crucible={UP="threat",DOWN="forge",LEFT="core",RIGHT="close"},
    rack={UP="talents",DOWN="visage",LEFT="search",RIGHT="core"},
    visage={UP="core",DOWN="forge",LEFT="rack",RIGHT="forge"},
    forge={UP="crucible",DOWN="close",LEFT="visage",RIGHT="close"},
    codex={UP="close",DOWN="search",LEFT="search",RIGHT="progression"},
    search={UP="codex",DOWN="rack",LEFT="codex",RIGHT="talents"},
    accessibility={UP="settings",DOWN="threat",LEFT="threat",RIGHT="settings"},
    settings={UP="close",DOWN="accessibility",LEFT="accessibility",RIGHT="close"},
    close={UP="settings",DOWN="accessibility",LEFT="settings",RIGHT="codex"},
}

local gameplayIds = {
    "progression", "talents", "threat", "crucible", "rack", "visage", "forge",
}
local utilityIds = { "codex", "search", "accessibility", "settings", "close" }

local Gate = {
    id = "dashboardGateB",
    componentIds = orderedIds,
    active = false,
    controls = {},
    legacyAdapters = {},
    revealToken = 0,
}

local root = CreateFrame("Frame", "EchoesUIGateBOverlay", dashboard)
root:SetAllPoints(dashboard)
root:Hide()
Gate.frame = root

local function RouteThroughCandidate(id)
    local native = UI.ScreenManager and UI.ScreenManager.registry[id]
    local available = native and (not native.IsAvailable or native:IsAvailable())
    if (id == "progression" or id == "talents" or id == "threat" or id == "crucible"
        or id == "rack" or id == "forge" or id == "visage" or id == "settings"
        or id == "accessibility" or id == "codex" or id == "search") and available then
        return UI.ScreenManager:Show(id)
    end
    local button = C43.buttons and C43.buttons[id]
    local click = button and button:GetScript("OnClick")
    if not click then
        UI:ReportError("native Dashboard route", "Candidate 43 route unavailable for " .. tostring(id))
        return false
    end
    click(button)
    return true
end

local function Place(control, x, y)
    control.root:SetPoint("TOPLEFT", dashboard, "TOPLEFT", x, -y)
    Gate.controls[control.id] = control
    return control
end

local settings = UI.IconButton:Create(root, {
    id = "settings", name = "EchoesUINativeSettingsButton", tooltip = "Settings",
    seatTexture = "Interface\\AddOns\\" .. ADDON_NAME .. "\\EchoesUI\\Assets\\SettingsGear.tga",
    seatSize = 30, seatRestAlpha = 0, hitWidth = 68, hitHeight = 64,
    hideShadow = true, hideIcon = true, shapedResponse = true,
    responseColor = Theme.colors.bronzeBright,
    glowAlphas = { hover=0.18, focus=0.24, hoverFocus=0.32, selected=0.38 },
    focusDisplayAlpha = 0, focusCues = {},
    hoverResponseScale=1.025, focusResponseScale=1.08,
    hoverFocusResponseScale=1.10, pressedResponseScale=0.96,
    onActivate = function(_, source)
        UI:Debug("settings activated by " .. tostring(source))
        RouteThroughCandidate("settings")
    end,
})
Place(settings, 1493, 64)

local progression = UI.Landmark:Create(root, {
    id="progression", name="EchoesUINativeProgression", label="PROGRESSION",
    hitWidth=260, hitHeight=180, embedded=true,
    environmentCrops={{sourceX=805,sourceY=55,x=70,y=-29,w=110,h=100}},
    labelX=55, labelY=84, labelWidth=150,
    labelFocusY=1, focusCues={}, focusDisplayAlpha=0,
    materialPieces={
        {sourceX=825,sourceY=60,x=90,y=-24,w=70,h=70,color={1.00,0.72,0.30,1},hoverAlpha=0.08,focusAlpha=0.34,hoverFocusAlpha=0.41,pressedAlpha=0.47,focusY=4,pressY=-2},
        {sourceX=790,sourceY=160,x=55,y=76,w=150,h=45,color={1.00,0.78,0.38,1},hoverAlpha=0.05,focusAlpha=0.28,hoverFocusAlpha=0.34,pressedAlpha=0.40,focusY=2,pressY=-2},
        {sourceX=845,sourceY=110,x=110,y=26,w=35,h=35,color={1.00,0.82,0.42,1},hoverAlpha=0.08,focusAlpha=0.40,hoverFocusAlpha=0.48,pressedAlpha=0.55,focusY=3,focusScale=1.06,pressY=-2},
    },
    responseColor={1.00,0.72,0.30,1},
    responseAlphas={hover=0.18,focus=0.07,hoverFocus=0.22,pressed=0.24,selected=0.26},
    onActivate=function(_,source) UI:Debug("progression activated by "..tostring(source)); RouteThroughCandidate("progression") end,
})
Place(progression,735,84)

local talents = UI.Landmark:Create(root, {
    id="talents", name="EchoesUINativeTalents", label="TALENTS",
    hitWidth=330, hitHeight=310, embedded=true,
    environmentCrops={{sourceX=350,sourceY=170,x=160,y=0,w=135,h=145},{sourceX=350,sourceY=352,x=160,y=182,w=135,h=118}},
    labelX=28, labelY=152, labelWidth=130,
    labelFocusY=1, focusCues={}, focusDisplayAlpha=0,
    materialPieces={
        {sourceX=350,sourceY=170,x=160,y=0,w=70,h=70,color={0.76,0.48,1.00,1},hoverAlpha=0.07,focusAlpha=0.28,hoverFocusAlpha=0.35,pressedAlpha=0.41,focusX=2,focusY=2,pressY=-2},
        {sourceX=350,sourceY=352,x=160,y=182,w=70,h=80,color={1.00,0.72,0.34,1},hoverAlpha=0.05,focusAlpha=0.25,hoverFocusAlpha=0.31,pressedAlpha=0.37,focusX=-2,focusY=-1,pressY=-1},
        {sourceX=420,sourceY=235,x=230,y=65,w=55,h=55,color={0.74,0.42,1.00,1},hoverAlpha=0.06,focusAlpha=0.31,hoverFocusAlpha=0.38,pressedAlpha=0.44,focusX=3,focusScale=1.05,pressX=1,pressY=-1},
    },
    responseColor={0.72,0.38,1.00,1},
    responseAlphas={hover=0.14,focus=0.06,hoverFocus=0.18,pressed=0.21,selected=0.23},
    hoverLabelColor={0.84,0.68,1.00,1},
    onActivate=function(_,source) UI:Debug("talents activated by "..tostring(source)); RouteThroughCandidate("talents") end,
})
Place(talents,190,170)

local threat = UI.Landmark:Create(root, {
    id="threat", name="EchoesUINativeWorldThreat", label="WORLD THREAT",
    hitWidth=410, hitHeight=300, embedded=true,
    environmentCrops={{sourceX=1085,sourceY=145,x=0,y=103,w=85,h=140},{sourceX=1185,sourceY=68,x=100,y=26,w=150,h=35},{sourceX=1375,sourceY=120,x=290,y=78,w=80,h=150}},
    labelX=98, labelY=176, labelWidth=185,
    labelFocusY=1, focusCues={}, focusDisplayAlpha=0,
    materialPieces={
        {sourceX=1085,sourceY=145,x=0,y=103,w=85,h=140,color={0.48,0.80,1.00,1},hoverAlpha=0.06,focusAlpha=0.32,hoverFocusAlpha=0.39,pressedAlpha=0.46,focusX=5,pressX=1,pressY=-1},
        {sourceX=1375,sourceY=120,x=290,y=78,w=80,h=150,color={0.48,0.80,1.00,1},hoverAlpha=0.06,focusAlpha=0.32,hoverFocusAlpha=0.39,pressedAlpha=0.46,focusX=-5,pressX=-1,pressY=-1},
        {sourceX=1185,sourceY=68,x=100,y=26,w=150,h=35,color={0.58,0.88,1.00,1},hoverAlpha=0.05,focusAlpha=0.30,hoverFocusAlpha=0.37,pressedAlpha=0.43,focusY=-3,focusScale=1.03,pressY=-1},
    },
    responseColor={0.48,0.80,1.00,1},
    responseAlphas={hover=0.16,focus=0.07,hoverFocus=0.20,pressed=0.23,selected=0.25},
    hoverLabelColor={0.68,0.88,1.00,1},
    onActivate=function(_,source) UI:Debug("threat activated by "..tostring(source)); RouteThroughCandidate("threat") end,
})
Place(threat,1085,42)

local crucible = UI.Landmark:Create(root, {
    id="crucible", name="EchoesUINativeCrucible", label="THE CRUCIBLE",
    hitWidth=355, hitHeight=365, embedded=true,
    environmentCrops={{sourceX=1370,sourceY=330,x=125,y=26,w=180,h=160},{sourceX=1452,sourceY=452,x=207,y=148,w=78,h=58}},
    labelX=125, labelY=201, labelWidth=180,
    labelFocusY=1, focusCues={}, focusDisplayAlpha=0,
    materialPieces={
        {sourceX=1370,sourceY=330,x=125,y=26,w=80,h=160,color={1.00,0.34,0.12,1},hoverAlpha=0.07,focusAlpha=0.28,hoverFocusAlpha=0.35,pressedAlpha=0.41,focusX=3,pressX=1,pressY=-1},
        {sourceX=1450,sourceY=330,x=205,y=26,w=100,h=160,color={1.00,0.40,0.14,1},hoverAlpha=0.07,focusAlpha=0.28,hoverFocusAlpha=0.35,pressedAlpha=0.41,focusX=-3,pressX=-1,pressY=-1},
        {sourceX=1490,sourceY=360,x=245,y=56,w=35,h=80,color={1.00,0.40,0.10,1},hoverAlpha=0.09,focusAlpha=0.36,hoverFocusAlpha=0.44,pressedAlpha=0.51,focusY=-2,focusScale=1.04,pressY=-1},
    },
    responseColor={1.00,0.34,0.12,1},
    responseAlphas={hover=0.18,focus=0.07,hoverFocus=0.22,pressed=0.24,selected=0.26},
    hoverLabelColor={1.00,0.68,0.38,1},
    onActivate=function(_,source) UI:Debug("crucible activated by "..tostring(source)); RouteThroughCandidate("crucible") end,
})
Place(crucible,1245,304)

local rack = UI.Landmark:Create(root, {
    id="rack", name="EchoesUINativeAttunementRack", label="ATTUNEMENT RACK",
    hitWidth=490, hitHeight=370, embedded=true,
    environmentCrops={{sourceX=125,sourceY=500,x=70,y=30,w=340,h=175},{sourceX=90,sourceY=635,x=35,y=165,w=160,h=80}},
    labelX=180, labelY=222, labelWidth=220,
    labelFocusY=1, focusCues={}, focusDisplayAlpha=0,
    materialPieces={
        {sourceX=210,sourceY=635,x=155,y=165,w=60,h=80,color={0.42,0.82,1.00,1},hoverAlpha=0.05,focusAlpha=0.28,hoverFocusAlpha=0.35,pressedAlpha=0.41,focusX=-3,pressX=-1,pressY=-1},
        {sourceX=350,sourceY=500,x=295,y=30,w=80,h=120,color={0.42,0.82,1.00,1},hoverAlpha=0.05,focusAlpha=0.28,hoverFocusAlpha=0.35,pressedAlpha=0.41,focusX=3,pressX=1,pressY=-1},
        {sourceX=260,sourceY=635,x=205,y=165,w=70,h=45,color={0.48,0.86,1.00,1},hoverAlpha=0.05,focusAlpha=0.32,hoverFocusAlpha=0.40,pressedAlpha=0.47,focusY=2,focusScale=1.04,pressY=-1},
    },
    responseColor={0.42,0.74,1.00,1},
    responseAlphas={hover=0.11,focus=0.055,hoverFocus=0.15,pressed=0.18,selected=0.20},
    hoverLabelColor={0.66,0.88,1.00,1},
    onActivate=function(_,source) UI:Debug("rack activated by "..tostring(source)); RouteThroughCandidate("rack") end,
})
Place(rack,55,470)

local visage = UI.Landmark:Create(root, {
    id="visage", name="EchoesUINativeVisage", label="VISAGE",
    hitWidth=335, hitHeight=225, embedded=true,
    environmentCrops={{sourceX=630,sourceY=705,x=55,y=15,w=130,h=125},{sourceX=690,sourceY=730,x=115,y=40,w=68,h=92}},
    labelX=115, labelY=150, labelWidth=120,
    labelFocusY=1, focusCues={}, focusDisplayAlpha=0,
    materialPieces={
        {sourceX=630,sourceY=705,x=55,y=15,w=60,h=125,color={0.50,0.72,1.00,1},hoverAlpha=0.06,focusAlpha=0.30,hoverFocusAlpha=0.37,pressedAlpha=0.44,focusX=-3,pressX=-1,pressY=-1},
        {sourceX=690,sourceY=730,x=115,y=40,w=68,h=92,color={0.72,0.48,1.00,1},hoverAlpha=0.07,focusAlpha=0.33,hoverFocusAlpha=0.41,pressedAlpha=0.48,focusX=3,focusY=2,pressX=1,pressY=-1},
        {sourceX=670,sourceY=735,x=95,y=45,w=36,h=60,color={0.66,0.84,1.00,1},hoverAlpha=0.07,focusAlpha=0.38,hoverFocusAlpha=0.46,pressedAlpha=0.53,focusY=2,focusScale=1.055,pressY=-1},
    },
    responseColor={0.58,0.48,1.00,1},
    responseAlphas={hover=0.15,focus=0.07,hoverFocus=0.20,pressed=0.23,selected=0.25},
    hoverLabelColor={0.80,0.72,1.00,1},
    onActivate=function(_,source) UI:Debug("visage activated by "..tostring(source)); RouteThroughCandidate("visage") end,
})
Place(visage,575,690)

local forge = UI.Landmark:Create(root, {
    id="forge", name="EchoesUINativeLegacyForge", label="LEGACY FORGE",
    hitWidth=405, hitHeight=255, embedded=true,
    environmentCrops={{sourceX=1100,sourceY=710,x=95,y=60,w=230,h=70},{sourceX=1100,sourceY=830,x=95,y=180,w=230,h=70}},
    labelX=95, labelY=142, labelWidth=185,
    labelFocusY=1, focusCues={}, focusDisplayAlpha=0,
    materialPieces={
        {sourceX=1090,sourceY=784,x=85,y=134,w=200,h=48,color={1.00,0.70,0.30,1},hoverAlpha=0.05,focusAlpha=0.16,hoverFocusAlpha=0.20,pressedAlpha=0.23,focusY=1,pressY=-2},
        {sourceX=1100,sourceY=830,x=95,y=180,w=230,h=70,color={0.86,0.48,0.16,1},hoverAlpha=0.06,focusAlpha=0.17,hoverFocusAlpha=0.21,pressedAlpha=0.25,focusY=-2,pressY=-1},
        {sourceX=1190,sourceY=845,x=185,y=195,w=90,h=45,color={0.94,0.52,0.16,1},hoverAlpha=0.07,focusAlpha=0.21,hoverFocusAlpha=0.26,pressedAlpha=0.31,focusX=1,focusY=-2,focusScale=1.025,pressY=-1},
    },
    responseColor={0.86,0.48,0.16,1},
    responseAlphas={hover=0.15,focus=0.065,hoverFocus=0.19,pressed=0.22,selected=0.24},
    hoverLabelColor={1.00,0.76,0.40,1}, activeLabelColor={1.00,0.82,0.52,1},
    onActivate=function(_,source) UI:Debug("forge activated by "..tostring(source)); RouteThroughCandidate("forge") end,
})
Place(forge,1005,650)

local core = UI.CoreWidget:Create(root, {
    id="core", name="EchoesUINativeCoreHome", label="WORLDSOUL CORE",
    tooltip="Worldsoul Core — Home", hitWidth=555, hitHeight=430,
    embedded=true, fontSize=16, labelHeight=46,
    environmentCrops={{sourceX=760,sourceY=300,x=185,y=45,w=190,h=190},{sourceX=680,sourceY=450,x=105,y=195,w=135,h=105},{sourceX=925,sourceY=405,x=350,y=150,w=95,h=120}},
    labelX=212, labelY=316, labelWidth=220,
    labelFocusY=1, focusCues={}, focusDisplayAlpha=0,
    materialPieces={
        {sourceX=820,sourceY=330,x=245,y=75,w=150,h=180,color={0.46,0.82,1.00,1},hoverAlpha=0.08,focusAlpha=0.38,hoverFocusAlpha=0.47,pressedAlpha=0.55,focusY=3,focusScale=1.035,pressedScale=1.015},
        {sourceX=790,sourceY=545,x=215,y=290,w=215,h=85,color={1.00,0.72,0.30,1},hoverAlpha=0.05,focusAlpha=0.34,hoverFocusAlpha=0.42,pressedAlpha=0.50,focusY=3,pressY=-2},
        {sourceX=865,sourceY=535,x=290,y=280,w=60,h=38,color={1.00,0.78,0.38,1},hoverAlpha=0.07,focusAlpha=0.48,hoverFocusAlpha=0.58,pressedAlpha=0.66,focusY=4,focusScale=1.055,pressY=-2},
    },
    responseColor={0.42,0.78,1.00,1},
    responseAlphas={hover=0.08,focus=0.09,hoverFocus=0.15,pressed=0.18,selected=0.20},
    hoverLabelColor={0.72,0.92,1.00,1},
    onActivate=function(_,source) UI:Debug("core/home activated by "..tostring(source)); RouteThroughCandidate("core") end,
})
Place(core,575,255)

local codex = UI.Landmark:Create(root, {
    id="codex", name="EchoesUINativeCodex", label="CODEX", tooltip="Worldsoul Codex",
    hitWidth=145, hitHeight=52, embedded=true, fontSize=16,
    environmentCrops={{sourceX=54,sourceY=45,x=0,y=0,w=44,h=42}},
    labelX=37, labelY=9, labelWidth=95,
    labelFocusY=1, focusCues={}, focusDisplayAlpha=0,
    materialPieces={
        {sourceX=54,sourceY=45,x=0,y=0,w=44,h=42,color={1.00,0.76,0.34,1},hoverAlpha=0.10,focusAlpha=0.24,hoverFocusAlpha=0.30,pressedAlpha=0.34,focusX=1,pressY=-1},
        {sourceX=95,sourceY=45,x=41,y=0,w=70,h=42,color={1.00,0.76,0.34,1},hoverAlpha=0.06,focusAlpha=0.18,hoverFocusAlpha=0.23,pressedAlpha=0.27,focusY=1,pressY=-2},
    },
    responseColor={1.00,0.76,0.34,1},
    responseAlphas={hover=0.22,focus=0.08,hoverFocus=0.27,pressed=0.30,selected=0.32},
    onActivate=function(_,source) UI:Debug("codex activated by "..tostring(source)); RouteThroughCandidate("codex") end,
})
Place(codex,54,45)

local search = UI.Landmark:Create(root, {
    id="search", name="EchoesUINativeSearch", label="SEARCH", tooltip="Search",
    hitWidth=145, hitHeight=52, embedded=true, fontSize=16,
    environmentCrops={{sourceX=57,sourceY=96,x=3,y=1,w=34,h=40}},
    labelX=37, labelY=10, labelWidth=95,
    labelFocusY=1, focusCues={}, focusDisplayAlpha=0,
    materialPieces={
        {sourceX=57,sourceY=96,x=3,y=1,w=34,h=40,color={1.00,0.74,0.34,1},hoverAlpha=0.10,focusAlpha=0.24,hoverFocusAlpha=0.30,pressedAlpha=0.34,focusX=1,pressY=-1},
        {sourceX=95,sourceY=96,x=41,y=1,w=70,h=40,color={1.00,0.74,0.34,1},hoverAlpha=0.06,focusAlpha=0.18,hoverFocusAlpha=0.23,pressedAlpha=0.27,focusY=1,pressY=-2},
    },
    responseColor={1.00,0.74,0.34,1},
    responseAlphas={hover=0.20,focus=0.08,hoverFocus=0.25,pressed=0.28,selected=0.30},
    onActivate=function(_,source) UI:Debug("search activated by "..tostring(source)); RouteThroughCandidate("search") end,
})
Place(search,54,95)

local accessibility = UI.Landmark:Create(root, {
    id="accessibility", name="EchoesUINativeAccessibility", label="ACCESSIBILITY",
    tooltip="Toggle reduced motion", hitWidth=205, hitHeight=55,
    embedded=true, fontSize=16,
    environmentCrops={{sourceX=1425,sourceY=131,x=10,y=1,w=30,h=45}},
    labelX=35, labelY=15, labelWidth=165,
    labelFocusY=1, focusCues={}, focusDisplayAlpha=0,
    materialPieces={
        {sourceX=1425,sourceY=131,x=10,y=1,w=30,h=45,color={1.00,0.76,0.34,1},hoverAlpha=0.10,focusAlpha=0.26,hoverFocusAlpha=0.32,pressedAlpha=0.36,focusX=1,pressY=-1},
        {sourceX=1458,sourceY=131,x=43,y=1,w=120,h=45,color={1.00,0.78,0.38,1},hoverAlpha=0.06,focusAlpha=0.20,hoverFocusAlpha=0.25,pressedAlpha=0.29,focusY=1,pressY=-2},
    },
    responseColor={1.00,0.76,0.34,1},
    responseAlphas={hover=0.20,focus=0.08,hoverFocus=0.25,pressed=0.28,selected=0.30},
    onActivate=function(_,source) UI:Debug("accessibility activated by "..tostring(source)); RouteThroughCandidate("accessibility") end,
})
Place(accessibility,1415,130)

local close = UI.Landmark:Create(root, {
    id="close", name="EchoesUINativeClose", label="", tooltip="Close",
    hitWidth=75, hitHeight=72, embedded=true, fontSize=16,
    environmentCrops={{sourceX=1590,sourceY=28,x=20,y=10,w=42,h=42}},
    labelX=21, labelY=12, labelWidth=40,
    focusCues={}, focusDisplayAlpha=0,
    materialPieces={
        {sourceX=1590,sourceY=28,x=20,y=10,w=42,h=42,color={1.00,0.72,0.38,1},hoverAlpha=0.12,focusAlpha=0.28,hoverFocusAlpha=0.35,pressedAlpha=0.40,focusScale=1.05,hoverFocusScale=1.07,pressedScale=0.94},
    },
    responseColor={1.00,0.72,0.38,1},
    responseAlphas={hover=0.26,focus=0.10,hoverFocus=0.31,pressed=0.34,selected=0.36},
    onActivate=function(_,source) UI:Debug("close activated by "..tostring(source)); Gate:BeginClose() end,
})
Place(close,1570,18)

local essence = UI.ResourceDisplay:Create(root, {
    id="essence", name="EchoesUINativeEssence", field="essence",
    label="ESSENCE", width=142, height=34, fontSize=15,
})
essence.root:SetPoint("TOPLEFT",dashboard,"TOPLEFT",489,-669)
Gate.resource = essence

local input = UI.InputManager:New(dashboard,{installHandler=false})
input:SetNavigation(orderedIds,navigation)
input.defaultFocusId = "core"
Gate.input = input
for _,id in ipairs(orderedIds) do input:Add(Gate.controls[id],id) end

local function SuppressLegacy(id,suppress)
    local button = C43.buttons and C43.buttons[id]
    if not button then return end
    button.nativeSuppressed = suppress == true
    button.hovered = false
    button:EnableMouse(not suppress)
    if suppress then
        button.label:Hide()
        button.focusMark:Hide()
        button.hoverVisualAlpha=0; button.hoverVisualTarget=0; button.hoverVisualRenderedAlpha=0
        if button.hoverVisualTextures then
            for _,texture in ipairs(button.hoverVisualTextures) do texture:SetAlpha(0) end
        end
    else
        button.label:Show()
    end
end

function Gate:SetInteractionEnabled(enabled)
    for _,id in ipairs(self.componentIds) do self.controls[id]:SetEnabled(enabled) end
end

local function RevealControls(ids,token,delay,duration)
    C_Timer.After(delay,function()
        if not Gate.active or Gate.revealToken~=token or not dashboard:IsShown() then return end
        for _,id in ipairs(ids) do
            local control=Gate.controls[id]
            control:SetEnabled(true)
            Animation:Alpha(control.root,1,duration)
        end
    end)
end

function Gate:BeginReveal()
    if not self.active then return end
    self.revealToken=self.revealToken+1
    local token=self.revealToken
    for _,id in ipairs(self.componentIds) do
        local control=self.controls[id]
        Animation:Stop(control.root)
        control.root:SetAlpha(0)
        control:SetEnabled(false)
    end
    Animation:Stop(self.resource.root)
    self.resource.root:SetAlpha(0)
    self.resource.root:Show()
    if UI:IsReducedMotion() then
        for _,id in ipairs(self.componentIds) do
            self.controls[id]:SetEnabled(true)
            self.controls[id].root:SetAlpha(1)
        end
        self.resource.root:SetAlpha(1)
        return
    end
    RevealControls({"core"},token,0.02,0.11)
    RevealControls(gameplayIds,token,0.05,0.14)
    RevealControls(utilityIds,token,0.09,0.12)
    C_Timer.After(0.10,function()
        if not self.active or self.revealToken~=token or not dashboard:IsShown() then return end
        Animation:Alpha(self.resource.root,1,0.12)
    end)
end

function Gate:BeginClose()
    if not self.active then if C43 and C43.Hide then C43:Hide() end; return end
    self.revealToken=self.revealToken+1
    input:ClearFocus()
    self:SetInteractionEnabled(false)
    if not RouteThroughCandidate("close") then self:SetInteractionEnabled(true) end
end

input.onEscape=function() Gate:BeginClose() end

Gate.unsubscribeMotion = C43:SubscribeMotion(function(state)
    if not Gate.active then return end
    if state == "OPENING" and not Gate.explicitShow then
        Gate:BeginReveal()
    elseif state == "CLOSING" or state == "CLOSED" then
        Gate.revealToken = Gate.revealToken + 1
        input:ClearFocus()
        Gate:SetInteractionEnabled(false)
    end
end)

local legacyKeyHandler=dashboard:GetScript("OnKeyDown")
dashboard:SetScript("OnKeyDown",function(frame,key)
    if Gate.active then input:HandleKey(key)
    elseif legacyKeyHandler then legacyKeyHandler(frame,key) end
end)

function Gate:SetEnabled(enabled,focusId)
    self.active=enabled==true
    UI.flags.nativeDashboardGateB=self.active
    self.revealToken=self.revealToken+1
    input:ClearFocus()
    C43.keyboardFocusActive=false
    for _,button in pairs(C43.buttons or {}) do if button.focusMark then button.focusMark:Hide() end end
    for _,id in ipairs(self.componentIds) do SuppressLegacy(id,self.active) end
    if self.active then
        if C43.essenceSeat then C43.essenceSeat:Hide() end
        root:Show(); self.resource.root:Show(); self:SetInteractionEnabled(false)
        if focusId then input:SetFocusById(focusId) end
    else
        self:SetInteractionEnabled(false); root:Hide(); self.resource.root:Hide()
        if C43.essenceSeat then C43.essenceSeat:Show() end
    end
end

function Gate:UpdateScale()
    local scale=C43.scale or 1
    for _,control in pairs(self.controls) do
        if control.SetScaleCompensation then control:SetScaleCompensation(scale,12) end
    end
    self.resource:SetScaleCompensation(scale,12)
end

function Gate:Show(focusId)
    self.explicitShow=true
    self:SetEnabled(true,focusId)
    if C43 and C43.Show then C43:Show() end
    self.explicitShow=false
    self:UpdateScale(); self:BeginReveal()
    if focusId then input:SetFocusById(focusId) end
end

function Gate:Hide() self:SetEnabled(false) end

dashboard:HookScript("OnShow",function()
    if UI.flags.nativeDashboardGateB and not Gate.explicitShow then
        Gate:SetEnabled(true); Gate:UpdateScale(); Gate:BeginReveal()
    end
end)

dashboard:HookScript("OnHide",function()
    Gate.revealToken=Gate.revealToken+1
    input:ClearFocus()
    if Gate.active then Gate:SetInteractionEnabled(false) end
end)

local resize=CreateFrame("Frame")
resize:RegisterEvent("DISPLAY_SIZE_CHANGED")
resize:RegisterEvent("UI_SCALE_CHANGED")
resize:SetScript("OnEvent",function() C_Timer.After(0,function() Gate:UpdateScale() end) end)

UI.DashboardGateB=Gate
UI.ScreenManager:Register("dashboardGateB",Gate,true)

SLASH_ECHOESUI1="/echoesui"
SlashCmdList["ECHOESUI"]=function(inputText)
    local cmd=(inputText or ""):lower():match("^%s*(%S*)")
    if cmd=="" or cmd=="dashboard" then Gate:Show()
    elseif cmd=="settings" then Gate:Show("settings")
    elseif cmd=="fallback" or cmd=="off" then Gate:Hide(); print("|cff66ccff[EchoesUI]|r Candidate 43 fallback restored.")
    elseif cmd=="debug" then UI.DB.debug=not UI.DB.debug; print("|cff66ccff[EchoesUI]|r Development diagnostics "..(UI.DB.debug and "enabled." or "disabled."))
    elseif cmd=="status" then
        print("|cff66ccff[EchoesUI]|r version="..UI.version.." gate=NativeDashboardCompletion"..
            " native="..tostring(Gate.active).." focus="..tostring(input.focusId)..
            " reducedMotion="..tostring(UI:IsReducedMotion()))
    else print("|cff66ccff[EchoesUI]|r Commands: /echoesui dashboard | settings | fallback | status | debug") end
end

Gate:SetEnabled(UI.flags.nativeDashboardGateB)
UI.modules.DashboardGateB=true
