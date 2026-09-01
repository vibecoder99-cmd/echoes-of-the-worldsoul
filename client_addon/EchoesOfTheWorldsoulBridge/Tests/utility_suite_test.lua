-- Phase C utility suite behavioral test (WoW 3.3.5 mock host).
local ADDON_DIR=arg[1]; assert(ADDON_DIR,"addon path required"); dofile(arg[2])
local function fail(m) print("FAIL: "..m); os.exit(1) end
local function pass(m) print("PASS: "..m) end
local callbacks={}; local requests={}
_G.APB={echoes={welcomed=true,compatible=0,caps={},codexTopics={}},
    SubscribeCodex=function(self,fn) callbacks[#callbacks+1]=fn end,
    RequestCodexManifest=function() requests[#requests+1]="manifest"; return true end,
    RequestCodexPage=function(_,t,p) requests[#requests+1]="page:"..t..":"..p; return true end,
    SearchCodex=function(_,q) requests[#requests+1]="search:"..q; return true end,
}
AttunementPlusBridgeDB={cache={},c43={reducedMotion=false}}
local function load(rel) local f,e=loadfile(ADDON_DIR.."/"..rel); if not f then fail(e) end; local ok,x=pcall(f); if not ok then fail(rel..": "..x) end end
for _,rel in ipairs({
    "EchoesUI/Bootstrap.lua","EchoesUI/Theme.lua","EchoesUI/StateStore.lua","EchoesUI/AnimationController.lua","EchoesUI/Chaos.lua",
    "EchoesUI/ScreenManager.lua","EchoesUI/InputManager.lua","EchoesUI/Layout.lua",
    "EchoesUI/Components/IconButton.lua","EchoesUI/Components/Landmark.lua","EchoesUI/Components/CoreWidget.lua",
    "EchoesUI/Components/ResourceDisplay.lua","EchoesUI/Components/ProgressionZone.lua","EchoesUI/Components/ProgressionRow.lua",
    "EchoesUI/Components/UtilityShell.lua","C43Dashboard.lua","EchoesUI/DashboardGateB.lua",
    "EchoesUI/Screens/SettingsScreen.lua","EchoesUI/Screens/AccessibilityScreen.lua",
    "EchoesUI/Screens/CodexScreen.lua","EchoesUI/Screens/SearchScreen.lua",
}) do load(rel) end
local C43=APB.C43; local Gate=EchoesUI.DashboardGateB

C43:Show(); C43.buttons.settings:FireEvent("OnClick")
if not EchoesUI.SettingsScreen.active or EchoesUI.ScreenManager.current~="settings" then fail("Candidate route missed Settings") end
EchoesUI.SettingsScreen.accessibility:Activate("keyboard")
if not EchoesUI.AccessibilityScreen.active then fail("Settings cross-link missed Accessibility") end
EchoesUI.AccessibilityScreen.toggle:Activate("keyboard")
if not AttunementPlusBridgeDB.c43.reducedMotion or EchoesUI.AccessibilityScreen.toggle.value:GetText()~="ON" then fail("Reduced Motion was not immediate/account-wide") end
if EchoesUI.AccessibilityScreen.frame:GetScript("OnUpdate") then fail("Reduced Motion installed a shell transition") end
pass("native Settings ledger and single real Accessibility preference")

EchoesUI.AccessibilityScreen:Leave("accessibility"); ClearMockChatMessages()
C43.buttons.codex:FireEvent("OnClick")
local sent=GetMockChatMessages(); if #sent==0 or sent[#sent][1]~="ap" then fail("cold Codex missed gossip fallback") end
local sameDashboard=C43.frame
APB.echoes.compatible=1; APB.echoes.caps.codex_state_v1=true; APB.echoes.caps.codex_search_v1=true
C43.buttons.codex:FireEvent("OnClick")
if C43.frame~=sameDashboard or not EchoesUI.CodexScreen.active or requests[#requests]~="manifest" then fail("same-instance cold-load Codex activation failed") end
for i=1,11 do for _,fn in ipairs(callbacks) do fn("CODEX_TOPIC",{topic=tostring(i),title="Topic "..i,icon="0",pages=i==11 and "6" or "5"}) end end
for _,fn in ipairs(callbacks) do fn("CODEX_DONE",{kind="manifest",count="11"}) end
if requests[#requests]~="page:1:1" then fail("Codex manifest did not lazy-request first page") end
for _,fn in ipairs(callbacks) do fn("CODEX_PAGE",{topic="1",page="1",count="5",title="Getting Started",body="Canonical body"}) end
if EchoesUI.CodexScreen.body:GetText()~="Canonical body" or #EchoesUI.CodexScreen.topics~=11 then fail("Codex did not render server-owned corpus") end
pass("Codex fallback, cold-load capability re-evaluation, manifest, and lazy page")

-- Rapid-navigation regression: an ERROR belonging to a page the player has
-- since navigated away from (superseded by a newer request) must not
-- overwrite the body with the fallback failure copy. Only an ERROR that
-- still matches the currently outstanding AND currently desired page may
-- do that.
EchoesUI.CodexScreen:SelectTopic(1,2)
APB.echoes.codexPage={sentTopic=1,sentPage=1,desiredTopic=1,desiredPage=2} -- error belongs to the superseded page:1:1 request
for _,fn in ipairs(callbacks) do fn("ERROR",{code="RATE_LIMITED",message="codex_page"}) end
if EchoesUI.CodexScreen.body:GetText()=="The Codex request could not be completed. The gossip Codex remains available." then
    fail("a stale/superseded Codex error incorrectly surfaced as a user-visible failure")
end
APB.echoes.codexPage={sentTopic=1,sentPage=2,desiredTopic=1,desiredPage=2} -- error belongs to the current, still-desired request
for _,fn in ipairs(callbacks) do fn("ERROR",{code="RATE_LIMITED",message="codex_page"}) end
if EchoesUI.CodexScreen.body:GetText()~="The Codex request could not be completed. The gossip Codex remains available." then
    fail("a genuine current-request Codex error was incorrectly suppressed")
end
pass("stale Codex errors from superseded rapid-navigation requests are dropped; genuine current errors still surface")

EchoesUI.CodexScreen:Leave("codex"); C43.buttons.search:FireEvent("OnClick")
local Search=EchoesUI.SearchScreen; if not Search.active then fail("Candidate route missed capable Search") end
Search.field:SetText("rack slots"); Search:PerformSearch()
if requests[#requests]~="search:rack slots" then fail("Search did not submit only the Codex query") end
for _,fn in ipairs(callbacks) do fn("CODEX_RESULT",{topic="8",page="3",title="Attunement Rack",excerpt="Expand slot capacity."}) end
for _,fn in ipairs(callbacks) do fn("CODEX_DONE",{kind="search",count="1",total="1"}) end
if #Search.results~=1 or Search.input.focusId~="result1" then fail("Search result selection/focus failed") end
Search.resultRows[1]:Activate("keyboard")
if not EchoesUI.CodexScreen.active or requests[#requests]~="page:8:3" then fail("Search result did not open exact Codex page") end
pass("bounded Codex-only Search and exact result routing")

-- Battle-hardening regression: the server never correlates a search result
-- back to a specific query, so a second search issued while one is still
-- pending must be refused outright -- otherwise a stale result for an
-- abandoned query could overwrite a newer query's results.
EchoesUI.SearchScreen:Leave("search"); C43.buttons.search:FireEvent("OnClick")
Search.field:SetText("first query"); Search:PerformSearch()
local requestsBeforeOverlap=#requests
if Search:PerformSearch()~=false or #requests~=requestsBeforeOverlap then
    fail("Search allowed a second query to be issued while one was still pending")
end
-- Closing mid-search must not leave `searching` stuck true forever.
EchoesUI.SearchScreen:Leave("search"); C43.buttons.search:FireEvent("OnClick")
Search.field:SetText("second query")
if not Search:PerformSearch() then fail("Search stayed refused after being closed and reopened mid-request") end
if requests[#requests]~="search:second query" then fail("reopened Search did not submit the fresh query") end
-- A response that never arrives must recover, not stay stuck forever.
RunAllTimers()
if Search.searching then fail("an unanswered search left the screen stuck pending forever") end
if Search.status:GetText()~="Search could not be completed. Try again shortly." then
    fail("an unanswered search did not show a recoverable status")
end
pass("Search cannot interleave overlapping queries and recovers from an unanswered request")

-- Battle-hardening regression: an unanswered Codex page/manifest request
-- must not leave the screen frozen on "Retrieving..." forever.
EchoesUI.SearchScreen:Leave("search"); C43.buttons.codex:FireEvent("OnClick")
EchoesUI.CodexScreen:SelectTopic(1,1)
RunAllTimers()
if EchoesUI.CodexScreen.loading then fail("an unanswered Codex page request left the screen stuck loading forever") end
if EchoesUI.CodexScreen.body:GetText()~="The Codex request could not be completed. The gossip Codex remains available." then
    fail("an unanswered Codex page request did not show a recoverable status")
end
pass("Codex recovers from an unanswered page request instead of staying stuck loading")

-- Route-table parity: both Dashboard routing mechanisms must open every
-- native utility destination too, not just the seven gameplay ones -- the
-- Utility Suite sprint correctly extended both, and this test makes sure
-- no future patch silently drops one branch again (see the gameplay-side
-- version of this same test in smoke_test.lua).
EchoesUI.SearchScreen:Leave("search")
Gate:SetEnabled(true)
for _, id in ipairs({"settings", "accessibility", "codex", "search"}) do
    C43:Show(); ClearMockChatMessages()
    C43.buttons[id]:FireEvent("OnClick")
    if EchoesUI.ScreenManager.current ~= id then
        fail(id .. ": legacy Activate() route did not open the native screen (route-table parity)")
    end
    EchoesUI.ScreenManager:Close(id)

    C43:Show(); ClearMockChatMessages()
    Gate.controls[id]:SetEnabled(true) -- routing correctness, not staggered-reveal timing, is under test here
    Gate.controls[id]:Activate("keyboard")
    if EchoesUI.ScreenManager.current ~= id then
        fail(id .. ": DashboardGateB RouteThroughCandidate did not open the native screen (route-table parity)")
    end
    EchoesUI.ScreenManager:Close(id)
end
pass("both Dashboard routing mechanisms open every native utility destination (route-table parity)")

Gate:SetEnabled(true); Gate.input:SetFocusById("core"); local before=Gate.input.focusId
SetMockChatActive(true); Gate.input:HandleKey("TAB"); SetMockChatActive(false)
if Gate.input.focusId~=before then fail("utility sprint regressed chat-focus guard") end
pass("keyboard guard retained")
print("ALL UTILITY SUITE TESTS PASSED")
