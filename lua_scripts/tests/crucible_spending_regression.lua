-- Standalone regression for atomic Crucible debit + sink credit.
AP = { DB={}, RT={}, Tutorial={}, Visage=nil }
local state = { essence=100, invested=10 }
local mode = "success"
function AP.RT.GetGUID() return 77 end
function AP.RT.GetAccountId() return 88 end
function AP.RT.SendMessage() end
function AP.RT.RegisterEvent() return true end
function AP.Tutorial.Trigger() end
local function row(values) return { GetUInt32=function(_, i) return values[i+1] end } end
function AP.DB.Query(sql)
    if sql:find("SELECT `aether`") then return row({state.essence}) end
    if sql:find("SELECT `invested`") then return row({state.invested}) end
    if sql:find("SELECT m%.`aether`,s%.`invested`") then
        if mode == "verify_missing" then return nil end
        return row({state.essence, state.invested})
    end
end
function AP.DB.ExecuteCritical(sql)
    if mode == "ensure_failure" and sql:find("INSERT IGNORE") then return false end
    if mode == "write_failure" and sql:find("UPDATE `ap_mastery` AS m") then return false end
    if sql:find("UPDATE `ap_mastery` AS m") then
        if mode == "zero_match" then return true end
        local debit, credit = sql:match("m%.`aether`=m%.`aether`%-(%d+), s%.`invested`=s%.`invested`%+(%d+)")
        state.essence = state.essence - tonumber(debit)
        state.invested = state.invested + tonumber(credit)
    end
    return true
end

dofile((arg[0]:match("^(.*)[/\\]") or ".") .. "/../ap_sinks.lua")
local function reset(nextMode) state.essence, state.invested, mode = 100, 10, nextMode end

reset("success")
assert(AP.Sinks.Invest({}, "melee_power", 25) == true)
assert(state.essence == 75 and state.invested == 35)

for _, failureMode in ipairs({"ensure_failure", "write_failure", "zero_match"}) do
    reset(failureMode)
    assert(AP.Sinks.Invest({}, "melee_power", 25) == false)
    assert(state.essence == 100 and state.invested == 10)
end

reset("verify_missing")
assert(AP.Sinks.Invest({}, "melee_power", 25) == false)
assert(state.essence == 75 and state.invested == 35) -- both committed or neither

print("crucible_spending_regression: PASS (atomic dual-table transition + failures)")
