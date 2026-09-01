-- Standalone regression for the public 2.1.0 Essence Rack false-success bug.
AP = { DB = {}, RT = {}, Rack = {}, Forge = {}, Tutorial = {} }
function AP.RT.RegisterEvent() end
local state = { slots = 3, essence = 0, residue = 0 }
local writeMode, messages = "success", {}
function AP.RT.GetGUID() return 77 end
function AP.RT.GetAccountId() return 88 end
function AP.RT.SendMessage(_, message) messages[#messages + 1] = message end
function AP.Forge.GetVerifiedResidue() return true, state.residue end
function AP.Forge.SyncResidueAccountRepresentations() return true, "test" end
function AP.Tutorial.Trigger() end
local function result(values) return { GetUInt32 = function(_, index) return values[index + 1] end } end
function AP.DB.Query(sql)
    if sql:find("m%.`rack_slots`, r%.`amount`") then return result({state.slots, state.residue})
    elseif sql:find("`rack_slots`, `aether`") then return result({state.slots, state.essence})
    elseif sql:find("`rack_slots`") then return result({state.slots})
    elseif sql:find("`aether`") then return result({state.essence}) end
end
function AP.DB.ExecuteCritical(sql)
    if writeMode == "failure" then return false end
    if writeMode == "zero" then return true end
    if sql:find("UPDATE `ap_mastery` SET `aether`") then
        local cost, nextSlots = sql:match("`aether` = `aether` %- (%d+), `rack_slots` = (%d+)")
        if writeMode == "mismatch" then state.slots = tonumber(nextSlots)
        else state.essence, state.slots = state.essence - tonumber(cost), tonumber(nextSlots) end
    elseif sql:find("UPDATE `ap_mastery` AS m JOIN `ap_residue`") then
        local nextSlots, cost = sql:match("SET m%.`rack_slots` = (%d+), r%.`amount` = r%.`amount` %- (%d+)")
        if writeMode == "mismatch" then state.slots = tonumber(nextSlots)
        else state.residue, state.slots = state.residue - tonumber(cost), tonumber(nextSlots) end
    end
    return true
end
function AP.DB.Execute() return true end
dofile((arg[0]:match("^(.*)[/\\]") or ".") .. "/../ap_rack.lua")
local function reset(slots, essence, residue, mode)
    state.slots, state.essence, state.residue = slots, essence or 0, residue or 0
    writeMode, messages = mode or "success", {}
end
local function essenceTier(oldSlots, newSlots, cost)
    reset(oldSlots, cost, 0)
    local exact = AP.Rack.PurchaseEssenceExpand({}, oldSlots, newSlots, cost)
    assert(exact.ok and exact.status == "SUCCESS")
    assert(state.slots == newSlots and state.essence == 0)
end
local function residueTier(oldSlots, newSlots, cost)
    reset(oldSlots, 0, cost)
    local exact = AP.Rack.PurchaseExpand({}, oldSlots, newSlots, cost)
    assert(exact.ok and exact.status == "SUCCESS")
    assert(state.slots == newSlots and state.residue == 0)
end
essenceTier(3, 5, 500); essenceTier(5, 7, 2000); essenceTier(7, 10, 5000)
residueTier(10, 13, 15); residueTier(13, 16, 40); residueTier(16, 20, 100)
reset(3, 499, 0); assert(AP.Rack.PurchaseEssenceExpand({}, 3, 5, 499).status == "INSUFFICIENT_ESSENCE")
reset(10, 0, 14); assert(AP.Rack.PurchaseExpand({}, 10, 13, 14).status == "INSUFFICIENT_RESIDUE")
reset(3, 600, 0); assert(AP.Rack.PurchaseEssenceExpand({}, 3, 5, 500).status == "STALE_PREVIEW")
reset(5, 500, 0); assert(AP.Rack.PurchaseEssenceExpand({}, 3, 5, 500).status == "STALE_PREVIEW")
reset(3, 500, 0); assert(AP.Rack.PurchaseEssenceExpand({}, 3, 5, 500).status == "SUCCESS")
assert(AP.Rack.PurchaseEssenceExpand({}, 3, 5, 500).status == "STALE_PREVIEW")
reset(10, 0, 15); assert(AP.Rack.PurchaseExpand({}, 10, 13, 15).status == "SUCCESS")
assert(AP.Rack.PurchaseExpand({}, 10, 13, 15).status == "STALE_PREVIEW")
reset(20, 0, 0); local maxed = AP.Rack.PreviewExpand({}); assert(maxed.ok and maxed.status == "AT_MAX")
for _, mode in ipairs({"zero", "mismatch"}) do
    reset(3, 500, 0, mode); assert(AP.Rack.PurchaseEssenceExpand({}, 3, 5, 500).status == "STALE_PREVIEW")
end
reset(3, 500, 0, "failure"); assert(AP.Rack.PurchaseEssenceExpand({}, 3, 5, 500).status == "DATABASE_FAILURE")
reset(3, 500, 0, "failure"); assert(AP.Rack.Expand({}) == false)
assert(state.slots == 3 and state.essence == 500 and not messages[#messages]:find("Rack expands", 1, true))
reset(3, 500, 0); assert(AP.Rack.Expand({}) == true)
assert(state.slots == 5 and state.essence == 0 and messages[#messages]:find("Rack expands", 1, true))
print("rack_spending_regression: PASS (6 tiers + required failures + legacy truth)")
