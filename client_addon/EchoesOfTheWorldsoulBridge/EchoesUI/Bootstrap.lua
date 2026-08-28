-- EchoesUI native frontend bootstrap (WoW 3.3.5a / Interface 30300).
-- The legacy Candidate 43 Dashboard remains the default production surface.

EchoesUI = EchoesUI or {}

local UI = EchoesUI
UI.version = "1.5.2"
UI.modules = UI.modules or {}

AttunementPlusBridgeDB = AttunementPlusBridgeDB or { cache = {} }
AttunementPlusBridgeDB.echoesUI = AttunementPlusBridgeDB.echoesUI or {}

local DB = AttunementPlusBridgeDB.echoesUI
DB.flags = DB.flags or {}

if DB.flags.settingsProofEnabled == nil then
    DB.flags.settingsProofEnabled = false
end
if DB.flags.nativeDashboardGateB == nil then
    DB.flags.nativeDashboardGateB = false
end
if DB.flags.nativeProgression == nil then
    DB.flags.nativeProgression = true
end
if DB.flags.nativeWorldThreat == nil then
    DB.flags.nativeWorldThreat = true
end
if DB.flags.nativeCrucible == nil then
    DB.flags.nativeCrucible = true
end
if DB.flags.nativeTalents == nil then
    DB.flags.nativeTalents = true
end
if DB.flags.nativeRack == nil then
    DB.flags.nativeRack = true
end
if DB.flags.nativeForge == nil then
    DB.flags.nativeForge = true
end
if DB.flags.nativeVisage == nil then
    DB.flags.nativeVisage = true
end
if DB.flags.nativeSettings == nil then DB.flags.nativeSettings = true end
if DB.flags.nativeAccessibility == nil then DB.flags.nativeAccessibility = true end
if DB.flags.nativeCodex == nil then DB.flags.nativeCodex = true end
if DB.flags.nativeSearch == nil then DB.flags.nativeSearch = true end
if DB.debug == nil then
    DB.debug = false
end

UI.DB = DB
UI.flags = DB.flags

function UI:IsReducedMotion()
    local c43 = AttunementPlusBridgeDB and AttunementPlusBridgeDB.c43
    return c43 and c43.reducedMotion == true or false
end

function UI:Debug(message)
    if not self.DB.debug then return end
    print("|cff66ccff[EchoesUI]|r " .. tostring(message))
end

function UI:ReportError(scope, message)
    print("|cffff5555[EchoesUI]|r " .. tostring(scope) .. " failed: " .. tostring(message))
end

function UI:SafeCall(scope, callback, ...)
    local ok, result = pcall(callback, ...)
    if not ok then
        self:ReportError(scope, result)
        return false, result
    end
    return true, result
end

UI.modules.Bootstrap = true
