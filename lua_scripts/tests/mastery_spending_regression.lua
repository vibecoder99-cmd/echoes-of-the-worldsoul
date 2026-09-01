-- Standalone regression for guarded, verified Mastery purchase.
AP = { RT={}, DB={}, Cap={ GetEquippedItemBySlot=false } }
function AP.RT.RegisterEvent() return true end
function AP.RT.RegisterStartup() return true end
function AP.RT.GetGUID() return 77 end
function AP.DB.Execute() return true end
function AP.DB.WorldQuery() return nil end
local state = { essence=5000, mastery=0 }
local mode = "success"
local function row(values) return { GetUInt32=function(_, i) return values[i+1] end, GetUInt64=function(_, i) return values[i+1] end } end
function AP.DB.GetUInt64(q, i) return tonumber(tostring(q:GetUInt64(i))) or 0 end
function AP.DB.Query(sql)
    if sql:find("SELECT `aether`, `mastery`") then
        if mode == "verify_missing" then return nil end
        return row({state.essence, state.mastery})
    end
end
function AP.DB.ExecuteCritical(sql)
    if mode == "write_failure" and sql:find("UPDATE `ap_mastery`") then return false end
    if sql:find("UPDATE `ap_mastery`") then
        if mode == "zero_match" then return true end
        local cost, rank = sql:match("`aether` = `aether` %- (%d+), `mastery` = (%d+)")
        state.essence, state.mastery = state.essence-tonumber(cost), tonumber(rank)
    end
    return true
end

dofile((arg[0]:match("^(.*)[/\\]") or ".") .. "/../ap_core.lua")
AP.LoadMastery = function() return {aether=state.essence, mastery=state.mastery} end
AP.MasteryCost = function() return 5000 end
local function reset(nextMode) state.essence, state.mastery, mode = 5000, 0, nextMode end

reset("success")
local success = AP.Mastery.Purchase({})
assert(success.status == "SUCCESS" and state.essence == 0 and state.mastery == 1)

for _, failureMode in ipairs({"write_failure", "zero_match"}) do
    reset(failureMode)
    local result = AP.Mastery.Purchase({})
    assert(result.status ~= "SUCCESS")
    assert(state.essence == 5000 and state.mastery == 0)
end

reset("verify_missing")
assert(AP.Mastery.Purchase({}).status == "POST_VERIFY_FAILURE")
assert(state.essence == 0 and state.mastery == 1)

print("mastery_spending_regression: PASS (guarded transition + post-verify)")
