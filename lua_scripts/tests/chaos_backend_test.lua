AP = { DB={ValidateSchema=function() return true end}, RT={RegisterStartup=function() end} }
assert(pcall(dofile, "lua_scripts/ap_core.lua"))

local function expect(profile, power, magnitude, scale)
    local reading=AP.Chaos.BuildReading(profile.enabled,profile.attuned,profile.mastery,profile.crucible)
    assert(reading.power==power, "power: "..reading.power.." ~= "..power)
    assert(reading.magnitude==magnitude, "magnitude mismatch")
    assert(reading.scale==scale, "scale mismatch")
    assert(reading.enabled==profile.enabled, "enabled mismatch")
    assert(tonumber(reading.power)==reading.base+reading.attunementContribution+reading.masteryContribution+reading.crucibleContribution,
        "contribution breakdown does not reconcile")
end

expect({enabled=false,attuned=0,mastery=0,crucible=0},"1000",1,1025)
expect({enabled=true,attuned=14,mastery=4,crucible=0},"241225",1,1025)
expect({enabled=true,attuned=50,mastery=20,crucible=100000},"8858800",2,1050)
expect({enabled=true,attuned=200,mastery=100,crucible=5000000},"456012050",2,1050)

assert(AP.Chaos.MasteryBasis(4)==6809,"rank-derived Mastery backfill changed")
print("ALL CHAOS BACKEND TESTS PASSED")
