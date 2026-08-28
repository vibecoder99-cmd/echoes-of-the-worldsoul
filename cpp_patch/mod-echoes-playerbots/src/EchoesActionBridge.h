#ifndef MODULE_ECHOES_PLAYERBOTS_ACTION_BRIDGE_H
#define MODULE_ECHOES_PLAYERBOTS_ACTION_BRIDGE_H

#include "EchoesPlayerbotsCommon.h"
#include "EchoesBotActionTypes.h"
#include <optional>
#include <string>

class Player;

// E2i6 prototype: the single generic C++ client of Echoes' Lua-owned
// AP.API.GetCapabilities/ValidateBotAction/ExecuteBotAction/QueryBotActionResult
// service. No feature adapter may call into Lua directly - every adapter goes
// through this class, which is the only place in this module that touches
// ALE/Lua at all.
//
// Implemented using ALE's already-public interface (ALE::GALE, ALE::L,
// ALE::ExecuteCall) - zero modification to mod-ale. The whitelist enforced
// here (only "AP.API.<Name>" may be resolved and called) is what keeps this a
// narrow, bounded bridge rather than an arbitrary "execute Lua string"
// facility - there is no code path anywhere in this class that can reach any
// Lua global outside that one namespace.
class EchoesActionBridge
{
public:
    static EchoesActionBridge* instance()
    {
        static EchoesActionBridge inst;
        return &inst;
    }

    // Cheap, cacheable capability query. Caller (EchoesAdapterFactory) is
    // responsible for its own caching/rate-limiting - this call itself always
    // reaches Lua fresh (mirrors the presence handshake's own "call it, don't
    // guess" philosophy), but is never called per-tick by any adapter.
    struct Capabilities
    {
        bool bridgeReachable = false; // false if Lua itself was unreachable (fail-dormant)
        bool echoesReady = false;
        bool canRackStore = false;
        bool canRackRetrieve = false;

        // E2i8 naming correction: "Legacy Forge" IS Echoes' Dissolution system
        // (see env/backups/e2i8/.../source-audit/) - these are the corrected,
        // unambiguous field names.
        bool canDissolutionDryRun = false;
        bool canDissolutionExecute = false;
        bool legacyForgeAlias = false;   // true when LEGACY_FORGE resolves to canDissolution*
        bool canForgeUpgrade = false;    // permanently false - there is no separate upgrade/crafting
                                          // Forge; kept named so "false" cannot be misread as
                                          // "Dissolution is absent"

        // Deprecated E2i6/E2i7 field names, kept as aliases of the corrected
        // fields above so no existing caller silently breaks.
        bool canDissolveDryRun = false;
        bool canDissolveExecute = false;
        bool canForge = false;
    };
    Capabilities GetCapabilities();

    // Read-only, never mutates regardless of request.dryRun.
    bool ValidateBotAction(Player* player, EchoesBotAction::Request const& request, EchoesBotAction::Result& outResult);

    // May mutate only if request.dryRun is false AND the action type supports
    // execution: RACK_STORE/RACK_RETRIEVE (E2i7), and now DISSOLVE/DISSOLUTION
    // (E2i8) - but only when EchoesPlayerbots.Bridge.Dissolution.Execute.Enable
    // is explicitly true, which is enforced entirely on this (C++) side before
    // this method is ever called with dryRun=false (see
    // EchoesDissolutionAdapter::Execute's gate check). The Lua side's own
    // safety contribution is independent of that flag: AP.Forge.Dissolve()
    // performs its own complete guard-clause re-verification (pending state,
    // already-dissolved, attunement, possession, equipped) immediately before
    // ever mutating, so a stale or manipulated C++-side decision still cannot
    // produce an unsafe dissolution. FORGE always returns a non-mutating
    // CAPABILITY_UNAVAILABLE - there is no separate upgrade/crafting mutation
    // to call.
    bool ExecuteBotAction(Player* player, EchoesBotAction::Request const& request, EchoesBotAction::Result& outResult);

    bool QueryBotActionResult(std::string const& token, EchoesBotAction::Result& outResult);

    // E2i8-R1: narrow, read-only delegation to Echoes' own AP.GetScaledCap
    // (ap_core.lua) - the real level-scaled quadratic attunement cap
    // formula. Returns std::nullopt if Lua/Echoes is unreachable or the
    // result is malformed - callers (EchoesBotCache) must treat nullopt as
    // "cap unavailable" and fail closed exactly like any other DB/bridge
    // failure, never substitute a guessed constant.
    std::optional<uint32> GetAttunementCap(uint32 itemEntry);

    // E2j1: bounded progression-economy read/spend surface. Every call is a narrow, read-only
    // or gated-mutation delegation to Echoes' own already-existing Lua functions - identical
    // whitelist/fail-closed contract as GetAttunementCap above. Never a new formula.
    struct ProgressionSnapshot
    {
        bool ok = false;
        uint32 essence = 0;
        uint32 rackSlots = 0;
        uint32 residue = 0;
    };
    ProgressionSnapshot GetProgressionSnapshot(Player* player);

    struct SinkInvestPreview
    {
        bool ok = false;
        uint32 cost = 0;
        double projectedEffectAtAmount = 0.0;
        double ceiling = 0.0;
    };
    SinkInvestPreview PreviewSinkInvest(std::string const& category, uint32 amount);

    // Mutates only when called - identical safety posture to ExecuteBotAction: the caller
    // (EchoesProgressionSinkAdapter) is solely responsible for gating this behind
    // EchoesConfig::progressionSpendingEnabled and a fresh EvaluateProgressionSpend result
    // before ever reaching this method.
    bool ExecuteSinkInvest(Player* player, std::string const& category, uint32 amount);

    struct RackExpandPreview
    {
        bool ok = false;
        bool atMaxCapacity = false;
        uint32 currentSlots = 0;
        uint32 nextSlots = 0;
        uint32 essenceCost = 0;
        uint32 residueCost = 0;
        uint32 expectedResidue = 0;
    };
    RackExpandPreview PreviewRackExpand(Player* player);

    bool ExecuteRackExpand(Player* player);

    struct ResiduePurchaseResult
    {
        bool ok = false;
        bool physicalSynced = false;
        std::string status;
        uint32 cost = 0;
        uint32 oldBalance = 0;
        uint32 newBalance = 0;
        uint64 oldState = 0;
        uint64 newState = 0;
    };

    ResiduePurchaseResult ExecuteResidueRackExpand(Player* player, RackExpandPreview const& preview);

    struct CatalystPreview
    {
        bool ok = false;
        std::string status;
        uint32 cost = 0;
        uint32 reward = 0;
        uint32 expectedResidue = 0;
        uint64 expectedEssence = 0;
    };
    CatalystPreview PreviewCatalyst(Player* player);
    ResiduePurchaseResult ExecuteCatalyst(Player* player, CatalystPreview const& preview);

    // E2j5: Mastery bridging - delegates to AP.API.PreviewMasteryPurchase /
    // AP.API.ExecuteMasteryPurchase (ap_botapi.lua), which themselves delegate to the shared
    // AP.Mastery.Purchase service (ap_core.lua) - the same one the human gossip menu now
    // calls. Never a duplicate cost/formula/ceiling. status mirrors the Lua-side structured
    // return: "SUCCESS" | "INSUFFICIENT_ESSENCE" | "INVALID_PLAYER" | "DATABASE_FAILURE" |
    // "SERVICE_UNAVAILABLE".
    struct MasteryPurchasePreview
    {
        bool ok = false;
        uint32 currentRank = 0;
        uint32 currentBalance = 0;
        uint32 cost = 0;
    };
    MasteryPurchasePreview PreviewMasteryPurchase(Player* player);

    struct MasteryPurchaseResult
    {
        bool ok = false;
        std::string status;
        uint32 oldRank = 0;
        uint32 newRank = 0;
        uint32 cost = 0;
        uint32 oldBalance = 0;
        uint32 newBalance = 0;
    };
    MasteryPurchaseResult ExecuteMasteryPurchase(Player* player);

    // Aggregate instrumentation (E2i6 Stage 7 requirement) - no per-item spam.
    uint32 GetRequestCount() const { return requestCount; }
    uint32 GetBridgeUnavailableCount() const { return bridgeUnavailableCount; }
    uint32 GetLuaErrorCount() const { return luaErrorCount; }

private:
    EchoesActionBridge() = default;

    // The one function that ever touches raw Lua stack state. dottedName
    // must begin with "AP.API." or this returns false immediately without
    // any Lua interaction at all - the whitelist check happens before any
    // lua_getglobal call.
    bool CallNamedFunction(char const* dottedName, Player* player, EchoesBotAction::Request const& request, EchoesBotAction::Result& outResult);

    uint32 requestCount = 0;
    uint32 bridgeUnavailableCount = 0;
    uint32 luaErrorCount = 0;
};

#endif
