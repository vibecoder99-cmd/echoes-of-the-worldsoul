-- ALE startup lifecycle regression: event 33 initializes once per Lua state,
-- independent of database-write capability or deployment identity.
local root = (arg[0]:match("^(.*)[/\\]") or ".") .. "/.."

local function newState(directAvailable)
    AP = nil
    local registered = {}
    function RegisterServerEvent(id, fn)
        registered[id] = registered[id] or {}
        registered[id][#registered[id] + 1] = fn
        return true
    end
    function RegisterPlayerEvent() return true end
    CharDBQuery = function() end
    CharDBExecute = function() end
    CharDBDirectExecute = directAvailable and function() end or nil
    dofile(root .. "/ap00_compat.lua")
    dofile(root .. "/ap01_runtime.lua")
    dofile(root .. "/ap02_runtime_eluna.lua")
    AP.Cap = AP.Cap or {}
    AP.Cap.Check = function(name)
        return name == "CharDBDirectExecute" and directAvailable
    end
    return registered
end

local function registerAndDeliver(directAvailable, deliveries)
    local registered = newState(directAvailable)
    local initialized = 0
    assert(AP.RT.RegisterStartup(function() initialized = initialized + 1 end))
    assert(registered[33] and #registered[33] == 1)
    assert(not registered[3] and not registered[13])
    assert(AP.Profile.name == "ale" and AP.Profile.ale == true)
    assert(AP.Profile.startupEventId == 33)
    assert(AP.Cap.Check("CharDBDirectExecute") == directAvailable)
    for _ = 1, deliveries do registered[33][1](33) end
    assert(initialized == 1)
    return initialized
end

assert(registerAndDeliver(true, 1) == 1)   -- fresh boot
assert(registerAndDeliver(true, 3) == 1)   -- repeated delivery
assert(registerAndDeliver(false, 2) == 1)  -- unsupported DB API remains independent
assert(registerAndDeliver(true, 2) == 1)   -- reload.ale: new state, once again

print("runtime_compat_regression: PASS (event 33 fresh/reload + once + capability independence)")
