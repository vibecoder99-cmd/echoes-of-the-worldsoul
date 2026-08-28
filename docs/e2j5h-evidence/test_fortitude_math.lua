-- Real execution against the actual ap_sinks.lua source (not a reimplementation).
-- Covers only what is pure-Lua and engine-independent: the diminishing-returns
-- formula and the cached-investment lookup that feed the Fortitude bonus.
-- Everything downstream (ApplyStatBuffMod, UpdateAllStats, current/max health
-- scaling) lives in mod_attunement_plus.patch (C++) and cannot be executed
-- here -- no compiler/build/server exists in this environment. Those items
-- are covered by static trace in the audit report, not by this test run.

local failures = 0
local function check(name, cond, detail)
    if cond then
        print("PASS  " .. name)
    else
        failures = failures + 1
        print("FAIL  " .. name .. (detail and ("  -- " .. detail) or ""))
    end
end

-- Stub the Eluna/AzerothCore globals ap_sinks.lua references so the file
-- loads without a live DB connection. Not called by any test below.
CharDBQuery = function() return nil end
CharDBExecute = function() end
RegisterPlayerEvent = function() end

local SCRIPT_DIR = (arg and arg[0] and arg[0]:match("(.*[/\\])")) or "./"
local ok, err = pcall(dofile, SCRIPT_DIR .. "../../lua_scripts/ap_sinks.lua")
check("ap_sinks.lua loads standalone under real Lua 5.4", ok, err)
if not ok then os.exit(1) end

-- ---- AP.Sinks.GetEffect: the DR formula backing every category, incl. fortitude ----

check("fortitude def exists with documented ceiling/k",
    AP.SinkDefs.fortitude ~= nil
    and AP.SinkDefs.fortitude.ceiling == 0.50
    and AP.SinkDefs.fortitude.k == 0.000003)

check("zero investment -> zero effect",
    AP.Sinks.GetEffect("fortitude", 0) == 0)

check("negative investment -> zero effect (defensive)",
    AP.Sinks.GetEffect("fortitude", -50) == 0)

local e1 = AP.Sinks.GetEffect("fortitude", 10000)
local e2 = AP.Sinks.GetEffect("fortitude", 100000)
local e3 = AP.Sinks.GetEffect("fortitude", 10000000)
check("effect strictly increases with investment (10k < 100k)", e1 < e2,
    string.format("e1=%.6f e2=%.6f", e1, e2))
check("effect strictly increases with investment (100k < 10M)", e2 < e3,
    string.format("e2=%.6f e3=%.6f", e2, e3))

check("effect never reaches or exceeds ceiling (asymptotic, not a hard cap bug)",
    e3 < 0.50 and e3 > 0.49, string.format("e3=%.6f", e3))

-- At extreme investment, math.exp(-k*invested) underflows to 0.0 in double
-- precision, so effect saturates to exactly the ceiling (0.50) rather than
-- approaching it asymptotically forever. That's expected float behavior, not
-- a cap-exceeding bug -- the real safety property is <=, not <.
check("effect never exceeds ceiling even at extreme investment (saturates, doesn't overflow)",
    AP.Sinks.GetEffect("fortitude", 1e12) <= 0.50,
    string.format("value=%.10f", AP.Sinks.GetEffect("fortitude", 1e12)))

-- ---- Monotonic idempotence: same investment always yields the same effect ----
-- This is the Lua-side half of the "no compounding on repeated refresh" contract.
-- The C++ side re-derives newStats from this same invested total on every 10s
-- tick (see CalculateAbsorption), so as long as this function is a pure
-- function of `invested` (no hidden mutable state), repeated refreshes at a
-- constant investment level cannot drift upward.
local a = AP.Sinks.GetEffect("fortitude", 54321)
local b = AP.Sinks.GetEffect("fortitude", 54321)
local c = AP.Sinks.GetEffect("fortitude", 54321)
check("GetEffect is a pure function of invested (no drift across repeated calls)",
    a == b and b == c, string.format("a=%.10f b=%.10f c=%.10f", a, b, c))

-- ---- GetInvested: cache lookup used by GetFortitudeForPlayer ----
AP.SinkCache[777] = { fortitude = 42000 }
check("GetInvested returns cached value for known account/category",
    AP.Sinks.GetInvested(777, "fortitude") == 42000)
check("GetInvested defaults to 0 for unknown account",
    AP.Sinks.GetInvested(999999, "fortitude") == 0)
check("GetInvested defaults to 0 for unknown category on known account",
    AP.Sinks.GetInvested(777, "nonexistent_category") == 0)

-- ---- Rank decrease: GetEffect must respond correctly if invested is ever lowered ----
-- (No refund path exists in AP.Sinks -- investment is permanent, per InvestCost's
-- own comment "no additional fee" and no Refund function defined. This test
-- documents that GetEffect itself has no floor/ratchet bug if invested did
-- drop, since the audit must check "rank decrease" behavior generically.)
local higher = AP.Sinks.GetEffect("fortitude", 80000)
local lower  = AP.Sinks.GetEffect("fortitude", 20000)
check("GetEffect responds downward if invested amount is ever lower (no ratchet-up bug)",
    lower < higher)

print("")
if failures == 0 then
    print("ALL " .. "PASS")
    os.exit(0)
else
    print(failures .. " FAILURE(S)")
    os.exit(1)
end
