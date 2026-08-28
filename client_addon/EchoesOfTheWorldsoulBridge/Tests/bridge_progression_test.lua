dofile(arg[2])

local filters = {}
ChatFrame_AddMessageEventFilter = function(event, callback)
    filters[event] = filters[event] or {}
    filters[event][#filters[event] + 1] = callback
end
AttunementPlusBridgeDB = {cache={}}

local sent = {}
SendChatMessage = function(message, channel) sent[#sent+1] = {message,channel} end

dofile(arg[1])
APB.playerName = "TestPlayer"

local tipSeen
APB:SubscribeAttunement(function(data) tipSeen = data end)
assert(APB:RequestAttunement(4242))
assert(sent[#sent][1] == "#ap tip 4242")
for _, callback in ipairs(filters.CHAT_MSG_SYSTEM) do
    callback(nil, "CHAT_MSG_SYSTEM", "[APTIP] id=4242|prog=40|cap=100|snap=1/2/3/4/5|absorb=0.1/0.2/0.3/0.4/0.5")
end
assert(tipSeen and tipSeen.entry == 4242 and tipSeen.prog == 40)

-- Ineligible responses are explicit, cached, and never render any Echoes
-- line -- not even a transient "fetching..." placeholder while pending.
GameTooltip._lines = {}
GameTooltip:SetHyperlink("|Hitem:4343:0:0:0:0:0:0:0|h[Non-equipment]|h")
GameTooltip:Show()
GameTooltip:FireEvent("OnTooltipSetItem")
assert(#GameTooltip._lines == 0, "ineligible item showed an Echoes line before any server response")
for _, callback in ipairs(filters.CHAT_MSG_SYSTEM) do
    callback(nil, "CHAT_MSG_SYSTEM", "[APTIP] id=4343|ineligible=1")
end
RunAllTimers()
assert(tipSeen and tipSeen.entry == 4343 and tipSeen.ineligible)
for _, line in ipairs(GameTooltip._lines or {}) do
    assert(not line:find("fetching", 1, true) and not line:find("0%%"), "ineligible tooltip retained an Echoes line")
end

local actionVerb, actionFields
APB:SubscribeEchoesActions(function(verb, fields) actionVerb, actionFields = verb, fields end)
APB:RequestEchoesAction("mastery_purchase")
assert(sent[#sent][1] == "#ap action mastery_purchase")
for _, callback in ipairs(filters.CHAT_MSG_SYSTEM) do
    callback(nil, "CHAT_MSG_SYSTEM", "[ECHOES]ACTION_OK|action=mastery_purchase|status=SUCCESS|new_rank=5")
end
assert(actionVerb == "ACTION_OK" and actionFields.status == "SUCCESS")

assert(APB:RequestEchoesAction("crucible_preview", "life_leech", 5000))
assert(sent[#sent][1] == "#ap action crucible_preview life_leech 5000")
assert(not APB:RequestEchoesAction("crucible_preview", "life leech", 5000), "unsafe action token was accepted")

assert(APB:RequestEchoesAction("talent_preview", 4))
assert(sent[#sent][1] == "#ap action talent_preview 4")
assert(APB:RequestEchoesAction("talent_purchase", 0))
assert(sent[#sent][1] == "#ap action talent_purchase 0")
assert(not APB:RequestEchoesAction("talent_preview", "0;drop"), "unsafe Talent argument was accepted")

APB:RequestEchoesState()
assert(sent[#sent][1] == "#ap state")
local beforeThrottle = #sent
APB:RequestEchoesState()
APB:RequestEchoesState()
APB:RequestEchoesState()
assert(#sent == beforeThrottle, "state request throttle sent a duplicate immediately")
RunAllTimers()
assert(#sent == beforeThrottle + 1 and sent[#sent][1] == "#ap state")
assert(not APB.echoes.stateRequestScheduled, "coalesced state request remained scheduled")

local codexVerb,codexFields
APB:SubscribeCodex(function(verb,fields) codexVerb,codexFields=verb,fields end)
assert(APB:RequestCodexManifest() and sent[#sent][1]=="#ap codex manifest")
assert(APB:RequestCodexPage(8,3) and sent[#sent][1]=="#ap codex page 8 3")
assert(APB:SearchCodex("rack slots") and sent[#sent][1]=="#ap codex search rack%20slots")
assert(not APB:SearchCodex("x"),"one-character Codex query was accepted")
local hidden=false
for _,callback in ipairs(filters.CHAT_MSG_SAY or {}) do if callback(nil,"CHAT_MSG_SAY","#ap codex search rack%20slots") then hidden=true end end
assert(hidden,"exact internal Codex request leaked into SAY")
for _,callback in ipairs(filters.CHAT_MSG_SYSTEM) do
    callback(nil,"CHAT_MSG_SYSTEM","[ECHOES]CODEX_PAGE|topic=8|page=3|count=5|title=Attunement%20Rack|body=Expand%20slot%20capacity%2E")
end
assert(codexVerb=="CODEX_PAGE" and codexFields.title=="Attunement Rack" and codexFields.body=="Expand slot capacity.")
print("ALL BRIDGE PROGRESSION TESTS PASSED")
