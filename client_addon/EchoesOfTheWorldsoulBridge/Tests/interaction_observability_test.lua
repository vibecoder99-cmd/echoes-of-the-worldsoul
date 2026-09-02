-- Live-like interaction acknowledgement/trace harness for the WoW mock host.
local ADDON_DIR=arg[1]; assert(ADDON_DIR,"addon path required"); dofile(arg[2])

local output={}
local realPrint=print
print=function(message) output[#output+1]=tostring(message) end
local function check(value,message) if not value then error(message,2) end end
local function contains(needle)
    for _,line in ipairs(output) do if line:find(needle,1,true) then return true end end
    return false
end

dofile(ADDON_DIR.."/EchoesUI/Bootstrap.lua")
dofile(ADDON_DIR.."/EchoesUI/Theme.lua")
dofile(ADDON_DIR.."/EchoesUI/AnimationController.lua")
dofile(ADDON_DIR.."/EchoesUI/Components/ProgressionRow.lua")
dofile(ADDON_DIR.."/EchoesUI/InputManager.lua")

local UI=EchoesUI
local host=CreateFrame("Frame","EchoesInteractionObservabilityHost",UIParent)
local callbacks=0
local row=UI.ProgressionRow:Create(host,{id="proof",width=240,height=46,icon=false,
    label="PROOF",onActivate=function(_,source) callbacks=callbacks+1; return source end})

UI.DB.debug=false
UI:Trace("proof.disabled-trace","test","hidden")
check(#output==0,"debug trace emitted while disabled")

UI.DB.debug=true
check(row:Activate("keyboard"),"keyboard activation failed")
check(callbacks==1,"activation callback was not invoked")
check(row.acknowledged==true,"keyboard activation lacked immediate static acknowledgement")
check((row.selection:GetAlpha() or 0)>0,"acknowledgement was not visually represented")
check(contains("action=control.proof source=keyboard result=activated"),"activation trace missing identity/source/result")
RunAllTimers()
check(row.acknowledged==false,"transient acknowledgement did not settle")

row:SetEnabled(false)
check(row:Activate("keyboard")==false,"disabled control activated")
check(contains("result=disabled"),"disabled rejection was not traced")

local ok=UI:SafeCall("proof callback",function() error("expected failure") end)
check(ok==false,"callback exception was misreported as success")
check(contains("proof callback failed"),"callback exception was not player/operator visible")
check(contains("result=error"),"callback exception was not traced")

AttunementPlusBridgeDB.c43={reducedMotion=true}
row:SetEnabled(true)
check(row:Activate("keyboard"),"reduced-motion activation failed")
check(row.acknowledged and (row.selection:GetAlpha() or 0)>0,
    "reduced motion removed the non-motion acknowledgement")

local accepted,failed=0,0
local request=UI.ProgressionRow:Create(host,{id="request",width=240,height=46,icon=false,
    label="REQUEST",onActivate=function() accepted=accepted+1; return true end})
check(request:Activate("mouse"),"request dispatch success callback failed")
request.onActivate=function() failed=failed+1; error("dispatch rejected") end
check(request:Activate("mouse")==false,"request callback failure was misrepresented")
check(accepted==1 and failed==1,"success/failure callback paths were not both exercised")

print=realPrint
print("ALL INTERACTION OBSERVABILITY TESTS PASSED")
