#include "EchoesActionBridge.h"
#include "Player.h"
#include "Log.h"
#include <cstring>

// mod-ale's own headers are reachable here without any ALE source
// modification: AzerothCore's module CMake (modules/CMakeLists.txt,
// CollectIncludeDirectories) already adds every static module's src/
// directory to one shared include path for the combined `modules` static
// library target - mod-ale and mod-echoes-playerbots compile into the same
// binary. ALE::GALE, ALE::L and ALE::ExecuteCall are already public members
// (see LuaEngine.h) - this file is the only place in this module that
// includes LuaEngine.h or touches raw Lua stack state.
#include "LuaEngine.h"
#include "ALEIncludes.h"
#include "ALETemplate.h"

namespace
{
    // Whitelist enforcement: the ONLY thing that makes this a bounded bridge
    // rather than an arbitrary "call any Lua global" facility. Checked before
    // any lua_getglobal call is made.
    bool IsWhitelistedName(char const* dottedName)
    {
        static char const* kPrefix = "AP.API.";
        return dottedName && std::strncmp(dottedName, kPrefix, std::strlen(kPrefix)) == 0;
    }

    // Resolves a dotted "AP.API.Foo" path via lua_getglobal + lua_getfield
    // chain. Leaves the resolved value (or nil) on top of the stack. Returns
    // true only if the resolved value is actually a function.
    bool ResolveDottedFunction(lua_State* L, char const* dottedName)
    {
        std::string name(dottedName);
        size_t start = 0;
        size_t dot = name.find('.');
        // First segment via lua_getglobal, remaining segments via lua_getfield.
        std::string first = name.substr(0, dot);
        lua_getglobal(L, first.c_str());
        start = dot + 1;

        while (dot != std::string::npos)
        {
            size_t next = name.find('.', start);
            std::string segment = (next == std::string::npos) ? name.substr(start) : name.substr(start, next - start);
            if (!lua_istable(L, -1) && !lua_isfunction(L, -1))
            {
                // Cannot descend further - Echoes not loaded or path invalid.
                return false;
            }
            lua_getfield(L, -1, segment.c_str());
            lua_remove(L, -2); // drop the parent, keep only the resolved child
            dot = next;
            start = next + 1;
        }

        return lua_isfunction(L, -1);
    }

    std::string GetStringField(lua_State* L, int tableIdx, char const* field, std::string const& def)
    {
        lua_getfield(L, tableIdx, field);
        std::string result = def;
        if (lua_isstring(L, -1))
            result = lua_tostring(L, -1);
        lua_pop(L, 1);
        return result;
    }

    bool GetBoolField(lua_State* L, int tableIdx, char const* field, bool def)
    {
        lua_getfield(L, tableIdx, field);
        bool result = def;
        if (lua_isboolean(L, -1))
            result = lua_toboolean(L, -1) != 0;
        lua_pop(L, 1);
        return result;
    }

    std::int64_t GetIntField(lua_State* L, int tableIdx, char const* field, std::int64_t def)
    {
        lua_getfield(L, tableIdx, field);
        std::int64_t result = def;
        if (lua_isnumber(L, -1))
            result = static_cast<std::int64_t>(lua_tonumber(L, -1));
        lua_pop(L, 1);
        return result;
    }
}

bool EchoesActionBridge::CallNamedFunction(char const* dottedName, Player* player, EchoesBotAction::Request const& request, EchoesBotAction::Result& outResult)
{
    if (!IsWhitelistedName(dottedName))
    {
        // Structurally unreachable in this module's own code (all call sites
        // below pass literal "AP.API.*" strings), but kept as a hard gate so
        // this invariant can never silently regress.
        ++luaErrorCount;
        return false;
    }

    if (!ALE::GALE)
    {
        ++bridgeUnavailableCount;
        return false;
    }

    LOCK_ALE;
    lua_State* L = ALE::GALE->L;
    if (!L)
    {
        ++bridgeUnavailableCount;
        return false;
    }

    int stackTop = lua_gettop(L);

    if (!ResolveDottedFunction(L, dottedName))
    {
        lua_settop(L, stackTop); // clean up whatever partial resolution left behind
        ++bridgeUnavailableCount;
        return false;
    }

    // Build the single request-table argument.
    lua_newtable(L);
    lua_pushstring(L, EchoesBotAction::ActionTypeToString(request.actionType));
    lua_setfield(L, -2, "actionType");
    lua_pushinteger(L, request.protocolVersion);
    lua_setfield(L, -2, "protocolVersion");
    lua_pushinteger(L, request.itemEntry);
    lua_setfield(L, -2, "itemEntry");
    // E2i8: stable per-item GUID, required by AP.Forge.Dissolve's own
    // ownership/state re-check (see ap_forge.lua's Dissolve() signature) -
    // itemEntry alone is not sufficient to identify a specific item instance.
    lua_pushinteger(L, static_cast<lua_Integer>(request.itemGuidRaw));
    lua_setfield(L, -2, "itemGuidRaw");
    lua_pushstring(L, request.idempotencyToken.c_str());
    lua_setfield(L, -2, "idempotencyToken");
    lua_pushboolean(L, request.dryRun);
    lua_setfield(L, -2, "dryRun");
    if (player)
    {
        ALE::Push(L, player);
        lua_setfield(L, -2, "_playerObj");
    }

    ++requestCount;

    // Stack: function, request_table -> ExecuteCall(1 param, 1 result)
    if (!ALE::GALE->ExecuteCall(1, 1))
    {
        // ExecuteCall already logged the Lua error and pushed a nil result.
        lua_settop(L, stackTop);
        ++luaErrorCount;
        return false;
    }

    if (!lua_istable(L, -1))
    {
        lua_settop(L, stackTop);
        ++luaErrorCount;
        return false;
    }

    outResult.resultCode = EchoesBotAction::ResultCodeFromString(GetStringField(L, -1, "resultCode", "INTERNAL_ERROR"));
    outResult.authoritativeCost = GetIntField(L, -1, "authoritativeCost", 0);
    outResult.authoritativeReward = GetIntField(L, -1, "authoritativeReward", 0);
    outResult.destinationRef = GetStringField(L, -1, "destinationRef", "");
    outResult.stateVersionAfter = GetStringField(L, -1, "stateVersionAfter", "");
    outResult.reasonCode = GetStringField(L, -1, "reasonCode", "");

    lua_settop(L, stackTop); // restore stack to exactly where we found it
    return true;
}

EchoesActionBridge::Capabilities EchoesActionBridge::GetCapabilities()
{
    Capabilities caps;

    if (!ALE::GALE)
        return caps; // bridgeReachable stays false - fail dormant

    LOCK_ALE;
    lua_State* L = ALE::GALE->L;
    if (!L)
        return caps;

    int stackTop = lua_gettop(L);
    if (!ResolveDottedFunction(L, "AP.API.GetCapabilities"))
    {
        lua_settop(L, stackTop);
        return caps;
    }

    if (!ALE::GALE->ExecuteCall(0, 1))
    {
        lua_settop(L, stackTop);
        return caps;
    }

    if (!lua_istable(L, -1))
    {
        lua_settop(L, stackTop);
        return caps;
    }

    caps.bridgeReachable = true;
    caps.echoesReady = GetBoolField(L, -1, "ready", false);
    caps.canRackStore = GetBoolField(L, -1, "canRackStore", false);
    caps.canRackRetrieve = GetBoolField(L, -1, "canRackRetrieve", false);

    // E2i8: read the corrected field names from ap_botapi.lua's response.
    // "Legacy Forge" IS Dissolution - there is no separate field to read for
    // a fictional upgrade/crafting Forge, so canForgeUpgrade is never read
    // from Lua and stays permanently false.
    caps.canDissolutionDryRun = GetBoolField(L, -1, "canDissolutionDryRun", false);
    caps.canDissolutionExecute = GetBoolField(L, -1, "canDissolutionExecute", false);
    caps.legacyForgeAlias = GetBoolField(L, -1, "legacyForgeAlias", false);
    caps.canForgeUpgrade = false;

    // Deprecated E2i6/E2i7 fields kept synchronized to the corrected ones so
    // no existing caller (or its own passing tests) silently breaks.
    caps.canDissolveDryRun = caps.canDissolutionDryRun;
    caps.canDissolveExecute = caps.canDissolutionExecute;
    caps.canForge = caps.canForgeUpgrade;

    lua_settop(L, stackTop);
    return caps;
}

bool EchoesActionBridge::ValidateBotAction(Player* player, EchoesBotAction::Request const& request, EchoesBotAction::Result& outResult)
{
    return CallNamedFunction("AP.API.ValidateBotAction", player, request, outResult);
}

bool EchoesActionBridge::ExecuteBotAction(Player* player, EchoesBotAction::Request const& request, EchoesBotAction::Result& outResult)
{
    return CallNamedFunction("AP.API.ExecuteBotAction", player, request, outResult);
}

bool EchoesActionBridge::QueryBotActionResult(std::string const& token, EchoesBotAction::Result& outResult)
{
    EchoesBotAction::Request dummyReq;
    dummyReq.idempotencyToken = token;
    if (!ALE::GALE)
        return false;

    LOCK_ALE;
    lua_State* L = ALE::GALE->L;
    if (!L)
        return false;

    int stackTop = lua_gettop(L);
    if (!ResolveDottedFunction(L, "AP.API.QueryBotActionResult"))
    {
        lua_settop(L, stackTop);
        return false;
    }

    lua_pushstring(L, token.c_str());
    if (!ALE::GALE->ExecuteCall(1, 1))
    {
        lua_settop(L, stackTop);
        return false;
    }

    if (!lua_istable(L, -1))
    {
        lua_settop(L, stackTop);
        return false;
    }

    outResult.resultCode = EchoesBotAction::ResultCodeFromString(GetStringField(L, -1, "resultCode", "INTERNAL_ERROR"));
    outResult.authoritativeCost = GetIntField(L, -1, "authoritativeCost", 0);
    outResult.authoritativeReward = GetIntField(L, -1, "authoritativeReward", 0);
    outResult.destinationRef = GetStringField(L, -1, "destinationRef", "");
    outResult.stateVersionAfter = GetStringField(L, -1, "stateVersionAfter", "");
    outResult.reasonCode = GetStringField(L, -1, "reasonCode", "");

    lua_settop(L, stackTop);
    return true;
}

std::optional<uint32> EchoesActionBridge::GetAttunementCap(uint32 itemEntry)
{

    if (!ALE::GALE)
    {
        return std::nullopt;
    }

    LOCK_ALE;
    lua_State* L = ALE::GALE->L;
    if (!L)
    {
        return std::nullopt;
    }

    int stackTop = lua_gettop(L);
    if (!ResolveDottedFunction(L, "AP.API.GetAttunementCap"))
    {
        lua_settop(L, stackTop);
        return std::nullopt;
    }

    lua_pushinteger(L, static_cast<lua_Integer>(itemEntry));
    if (!ALE::GALE->ExecuteCall(1, 1))
    {
        lua_settop(L, stackTop);
        return std::nullopt;
    }

    if (!lua_istable(L, -1))
    {
        lua_settop(L, stackTop);
        return std::nullopt;
    }

    bool ok = GetBoolField(L, -1, "ok", false);
    std::int64_t cap = GetIntField(L, -1, "cap", 0);

    lua_settop(L, stackTop);

    if (!ok || cap <= 0)
    {
        return std::nullopt;
    }

    return static_cast<uint32>(cap);
}

EchoesActionBridge::ProgressionSnapshot EchoesActionBridge::GetProgressionSnapshot(Player* player)
{
    ProgressionSnapshot snap;
    if (!player || !ALE::GALE)
        return snap;

    LOCK_ALE;
    lua_State* L = ALE::GALE->L;
    if (!L)
        return snap;

    int stackTop = lua_gettop(L);
    if (!ResolveDottedFunction(L, "AP.API.GetProgressionSnapshot"))
    {
        lua_settop(L, stackTop);
        return snap;
    }

    ALE::Push(L, player);
    if (!ALE::GALE->ExecuteCall(1, 1))
    {
        lua_settop(L, stackTop);
        return snap;
    }

    if (!lua_istable(L, -1))
    {
        lua_settop(L, stackTop);
        return snap;
    }

    snap.ok = GetBoolField(L, -1, "ok", false);
    snap.essence = static_cast<uint32>(GetIntField(L, -1, "essence", 0));
    snap.rackSlots = static_cast<uint32>(GetIntField(L, -1, "rackSlots", 0));
    snap.residue = static_cast<uint32>(GetIntField(L, -1, "residue", 0));

    lua_settop(L, stackTop);
    if (!snap.ok)
        return ProgressionSnapshot{};
    return snap;
}

EchoesActionBridge::SinkInvestPreview EchoesActionBridge::PreviewSinkInvest(std::string const& category, uint32 amount)
{
    SinkInvestPreview preview;
    if (!ALE::GALE)
        return preview;

    LOCK_ALE;
    lua_State* L = ALE::GALE->L;
    if (!L)
        return preview;

    int stackTop = lua_gettop(L);
    if (!ResolveDottedFunction(L, "AP.API.PreviewSinkInvest"))
    {
        lua_settop(L, stackTop);
        return preview;
    }

    lua_pushstring(L, category.c_str());
    lua_pushinteger(L, static_cast<lua_Integer>(amount));
    if (!ALE::GALE->ExecuteCall(2, 1))
    {
        lua_settop(L, stackTop);
        return preview;
    }

    if (!lua_istable(L, -1))
    {
        lua_settop(L, stackTop);
        return preview;
    }

    bool ok = GetBoolField(L, -1, "ok", false);
    std::int64_t cost = GetIntField(L, -1, "cost", 0);
    lua_getfield(L, -1, "projectedEffectAtAmount");
    double projected = lua_isnumber(L, -1) ? lua_tonumber(L, -1) : 0.0;
    lua_pop(L, 1);
    lua_getfield(L, -1, "ceiling");
    double ceiling = lua_isnumber(L, -1) ? lua_tonumber(L, -1) : 0.0;
    lua_pop(L, 1);

    lua_settop(L, stackTop);

    if (!ok || cost <= 0)
        return SinkInvestPreview{};

    preview.ok = true;
    preview.cost = static_cast<uint32>(cost);
    preview.projectedEffectAtAmount = projected;
    preview.ceiling = ceiling;
    return preview;
}

bool EchoesActionBridge::ExecuteSinkInvest(Player* player, std::string const& category, uint32 amount)
{
    if (!player || !ALE::GALE)
        return false;

    LOCK_ALE;
    lua_State* L = ALE::GALE->L;
    if (!L)
        return false;

    int stackTop = lua_gettop(L);
    if (!ResolveDottedFunction(L, "AP.API.ExecuteSinkInvest"))
    {
        lua_settop(L, stackTop);
        return false;
    }

    ALE::Push(L, player);
    lua_pushstring(L, category.c_str());
    lua_pushinteger(L, static_cast<lua_Integer>(amount));
    if (!ALE::GALE->ExecuteCall(3, 1))
    {
        lua_settop(L, stackTop);
        return false;
    }

    bool ok = lua_istable(L, -1) && GetBoolField(L, -1, "ok", false);
    lua_settop(L, stackTop);
    return ok;
}

EchoesActionBridge::MasteryPurchasePreview EchoesActionBridge::PreviewMasteryPurchase(Player* player)
{
    MasteryPurchasePreview preview;
    if (!player || !ALE::GALE)
        return preview;

    LOCK_ALE;
    lua_State* L = ALE::GALE->L;
    if (!L)
        return preview;

    int stackTop = lua_gettop(L);
    if (!ResolveDottedFunction(L, "AP.API.PreviewMasteryPurchase"))
    {
        lua_settop(L, stackTop);
        return preview;
    }

    ALE::Push(L, player);
    if (!ALE::GALE->ExecuteCall(1, 1))
    {
        lua_settop(L, stackTop);
        return preview;
    }

    if (!lua_istable(L, -1) || !GetBoolField(L, -1, "ok", false))
    {
        lua_settop(L, stackTop);
        return MasteryPurchasePreview{};
    }

    preview.ok = true;
    preview.currentRank = static_cast<uint32>(GetIntField(L, -1, "currentRank", 0));
    preview.currentBalance = static_cast<uint32>(GetIntField(L, -1, "currentBalance", 0));
    preview.cost = static_cast<uint32>(GetIntField(L, -1, "cost", 0));

    lua_settop(L, stackTop);
    return preview;
}

EchoesActionBridge::MasteryPurchaseResult EchoesActionBridge::ExecuteMasteryPurchase(Player* player)
{
    MasteryPurchaseResult result;
    if (!player || !ALE::GALE)
    {
        result.status = "SERVICE_UNAVAILABLE";
        return result;
    }

    LOCK_ALE;
    lua_State* L = ALE::GALE->L;
    if (!L)
    {
        result.status = "SERVICE_UNAVAILABLE";
        return result;
    }

    int stackTop = lua_gettop(L);
    if (!ResolveDottedFunction(L, "AP.API.ExecuteMasteryPurchase"))
    {
        lua_settop(L, stackTop);
        result.status = "SERVICE_UNAVAILABLE";
        return result;
    }

    ALE::Push(L, player);
    if (!ALE::GALE->ExecuteCall(1, 1))
    {
        lua_settop(L, stackTop);
        result.status = "SERVICE_UNAVAILABLE";
        return result;
    }

    if (!lua_istable(L, -1))
    {
        lua_settop(L, stackTop);
        result.status = "SERVICE_UNAVAILABLE";
        return result;
    }

    result.ok = GetBoolField(L, -1, "ok", false);
    result.status = GetStringField(L, -1, "status", "SERVICE_UNAVAILABLE");
    result.oldRank = static_cast<uint32>(GetIntField(L, -1, "oldRank", 0));
    result.newRank = static_cast<uint32>(GetIntField(L, -1, "newRank", 0));
    result.cost = static_cast<uint32>(GetIntField(L, -1, "cost", 0));
    result.oldBalance = static_cast<uint32>(GetIntField(L, -1, "oldBalance", 0));
    result.newBalance = static_cast<uint32>(GetIntField(L, -1, "newBalance", 0));

    lua_settop(L, stackTop);
    return result;
}

EchoesActionBridge::RackExpandPreview EchoesActionBridge::PreviewRackExpand(Player* player)
{
    RackExpandPreview preview;
    if (!player || !ALE::GALE)
        return preview;

    LOCK_ALE;
    lua_State* L = ALE::GALE->L;
    if (!L)
        return preview;

    int stackTop = lua_gettop(L);
    if (!ResolveDottedFunction(L, "AP.API.PreviewRackExpand"))
    {
        lua_settop(L, stackTop);
        return preview;
    }

    ALE::Push(L, player);
    if (!ALE::GALE->ExecuteCall(1, 1))
    {
        lua_settop(L, stackTop);
        return preview;
    }

    if (!lua_istable(L, -1))
    {
        lua_settop(L, stackTop);
        return preview;
    }

    bool ok = GetBoolField(L, -1, "ok", false);
    if (!ok)
    {
        lua_settop(L, stackTop);
        return RackExpandPreview{};
    }

    preview.ok = true;
    preview.atMaxCapacity = GetBoolField(L, -1, "atMaxCapacity", false);
    preview.currentSlots = static_cast<uint32>(GetIntField(L, -1, "currentSlots", 0));
    preview.nextSlots = static_cast<uint32>(GetIntField(L, -1, "nextSlots", 0));
    preview.essenceCost = static_cast<uint32>(GetIntField(L, -1, "essenceCost", 0));
    preview.residueCost = static_cast<uint32>(GetIntField(L, -1, "residueCost", 0));
    preview.expectedResidue = static_cast<uint32>(GetIntField(L, -1, "expectedResidue", 0));

    lua_settop(L, stackTop);
    return preview;
}

bool EchoesActionBridge::ExecuteRackExpand(Player* player)
{
    if (!player || !ALE::GALE)
        return false;

    LOCK_ALE;
    lua_State* L = ALE::GALE->L;
    if (!L)
        return false;

    int stackTop = lua_gettop(L);
    if (!ResolveDottedFunction(L, "AP.API.ExecuteRackExpand"))
    {
        lua_settop(L, stackTop);
        return false;
    }

    ALE::Push(L, player);
    if (!ALE::GALE->ExecuteCall(1, 1))
    {
        lua_settop(L, stackTop);
        return false;
    }

    bool ok = lua_istable(L, -1) && GetBoolField(L, -1, "ok", false);
    lua_settop(L, stackTop);
    return ok;
}

EchoesActionBridge::ResiduePurchaseResult EchoesActionBridge::ExecuteResidueRackExpand(
    Player* player, RackExpandPreview const& preview)
{
    ResiduePurchaseResult result;
    if (!player || !ALE::GALE || !preview.ok || preview.residueCost == 0)
        return result;

    LOCK_ALE;
    lua_State* L = ALE::GALE->L;
    if (!L)
        return result;

    int stackTop = lua_gettop(L);
    if (!ResolveDottedFunction(L, "AP.API.ExecuteRackExpand"))
    {
        lua_settop(L, stackTop);
        return result;
    }

    ALE::Push(L, player);
    lua_pushinteger(L, static_cast<lua_Integer>(preview.currentSlots));
    lua_pushinteger(L, static_cast<lua_Integer>(preview.nextSlots));
    lua_pushinteger(L, static_cast<lua_Integer>(preview.expectedResidue));
    if (!ALE::GALE->ExecuteCall(4, 1) || !lua_istable(L, -1))
    {
        lua_settop(L, stackTop);
        return result;
    }

    result.ok = GetBoolField(L, -1, "ok", false);
    result.physicalSynced = GetBoolField(L, -1, "physicalSynced", false);
    result.status = GetStringField(L, -1, "status", "SERVICE_UNAVAILABLE");
    result.cost = static_cast<uint32>(GetIntField(L, -1, "cost", 0));
    result.oldBalance = static_cast<uint32>(GetIntField(L, -1, "oldBalance", 0));
    result.newBalance = static_cast<uint32>(GetIntField(L, -1, "newBalance", 0));
    result.oldState = static_cast<uint64>(GetIntField(L, -1, "oldSlots", 0));
    result.newState = static_cast<uint64>(GetIntField(L, -1, "newSlots", 0));
    lua_settop(L, stackTop);
    return result;
}

EchoesActionBridge::CatalystPreview EchoesActionBridge::PreviewCatalyst(Player* player)
{
    CatalystPreview preview;
    if (!player || !ALE::GALE)
        return preview;

    LOCK_ALE;
    lua_State* L = ALE::GALE->L;
    if (!L)
        return preview;

    int stackTop = lua_gettop(L);
    if (!ResolveDottedFunction(L, "AP.API.PreviewCatalyst"))
    {
        lua_settop(L, stackTop);
        return preview;
    }

    ALE::Push(L, player);
    if (!ALE::GALE->ExecuteCall(1, 1) || !lua_istable(L, -1))
    {
        lua_settop(L, stackTop);
        return preview;
    }

    preview.ok = GetBoolField(L, -1, "ok", false);
    preview.status = GetStringField(L, -1, "status", "SERVICE_UNAVAILABLE");
    preview.cost = static_cast<uint32>(GetIntField(L, -1, "cost", 0));
    preview.reward = static_cast<uint32>(GetIntField(L, -1, "reward", 0));
    preview.expectedResidue = static_cast<uint32>(GetIntField(L, -1, "expectedResidue", 0));
    preview.expectedEssence = static_cast<uint64>(GetIntField(L, -1, "expectedEssence", 0));
    lua_settop(L, stackTop);
    return preview;
}

EchoesActionBridge::ResiduePurchaseResult EchoesActionBridge::ExecuteCatalyst(
    Player* player, CatalystPreview const& preview)
{
    ResiduePurchaseResult result;
    if (!player || !ALE::GALE || !preview.ok || preview.cost == 0)
        return result;

    LOCK_ALE;
    lua_State* L = ALE::GALE->L;
    if (!L)
        return result;

    int stackTop = lua_gettop(L);
    if (!ResolveDottedFunction(L, "AP.API.ExecuteCatalyst"))
    {
        lua_settop(L, stackTop);
        return result;
    }

    ALE::Push(L, player);
    lua_pushinteger(L, static_cast<lua_Integer>(preview.expectedResidue));
    lua_pushinteger(L, static_cast<lua_Integer>(preview.expectedEssence));
    if (!ALE::GALE->ExecuteCall(3, 1) || !lua_istable(L, -1))
    {
        lua_settop(L, stackTop);
        return result;
    }

    result.ok = GetBoolField(L, -1, "ok", false);
    result.physicalSynced = GetBoolField(L, -1, "physicalSynced", false);
    result.status = GetStringField(L, -1, "status", "SERVICE_UNAVAILABLE");
    result.cost = static_cast<uint32>(GetIntField(L, -1, "cost", 0));
    result.oldBalance = static_cast<uint32>(GetIntField(L, -1, "oldBalance", 0));
    result.newBalance = static_cast<uint32>(GetIntField(L, -1, "newBalance", 0));
    result.oldState = static_cast<uint64>(GetIntField(L, -1, "oldEssence", 0));
    result.newState = static_cast<uint64>(GetIntField(L, -1, "newEssence", 0));
    lua_settop(L, stackTop);
    return result;
}
