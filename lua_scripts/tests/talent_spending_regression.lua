-- Standalone regression for atomic Talent Essence/rank persistence.
AP = { API = {}, DB = {}, RT = {} }
function AP.Log() end
function AP.RT.GetGUID() return 77 end

local state = { essence = 2000, rank = 0 }
local mode = "success"
local function row(values)
    return { GetUInt32 = function(_, index) return values[index + 1] end }
end

function AP.DB.Query(sql)
    if mode == "verify_missing" and sql:find("SELECT m%.`aether`") then return nil end
    if sql:find("SELECT m%.`aether`") then return row({ state.essence, state.rank }) end
end

function AP.DB.ExecuteCritical(sql)
    if mode == "ensure_failure" and sql:find("INSERT IGNORE INTO `ap_talents`") then return false end
    if mode == "write_failure" and sql:find("UPDATE `ap_mastery` AS m") then return false end
    if sql:find("UPDATE `ap_mastery` AS m") then
        if mode == "zero_match" then return true end
        local cost, rank = sql:match("m%.`aether` = m%.`aether` %- (%d+), t%.`rank` = (%d+)")
        state.essence = state.essence - tonumber(cost)
        state.rank = tonumber(rank)
    end
    return true
end

dofile((arg[0]:match("^(.*)[/\\]") or ".") .. "/../ap_botapi.lua")

local function snapshot()
    local currentStat = { rank = state.rank, bonusPct = 0 }
    local projectedStat = { rank = state.rank + 1, bonusPct = 1 }
    return {
        ok = true, affordable = true, status = "READY", statIndex = 0,
        cost = 2000, essence = state.essence,
        current = { stats = { [0] = currentStat }, primary = nil, penalty = 1 },
        projected = { stats = { [0] = projectedStat }, primary = 0, penalty = 1 },
    }
end
AP.API.PreviewTalentPurchase = function() return snapshot() end

local function reset(nextMode)
    state.essence, state.rank, mode = 2000, 0, nextMode
end

reset("success")
local success = AP.API.ExecuteTalentPurchase({}, 0)
assert(success.ok and success.status == "SUCCESS")
assert(state.essence == 0 and state.rank == 1)

for _, failureMode in ipairs({ "ensure_failure", "write_failure", "zero_match" }) do
    reset(failureMode)
    local result = AP.API.ExecuteTalentPurchase({}, 0)
    assert(not result.ok)
    assert(state.essence == 2000 and state.rank == 0)
end

reset("verify_missing")
local missing = AP.API.ExecuteTalentPurchase({}, 0)
assert(not missing.ok and missing.status == "POST_VERIFY_FAILURE")
assert(state.essence == 0 and state.rank == 1) -- committed together; never split

print("talent_spending_regression: PASS (atomic success + guarded failures + post-verify)")
