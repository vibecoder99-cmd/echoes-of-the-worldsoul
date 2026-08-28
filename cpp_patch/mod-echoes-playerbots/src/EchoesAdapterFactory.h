#ifndef MODULE_ECHOES_PLAYERBOTS_ADAPTER_FACTORY_H
#define MODULE_ECHOES_PLAYERBOTS_ADAPTER_FACTORY_H

#include "EchoesPlayerbotsCommon.h"
#include "EchoesBotActionTypes.h"
#include "ObjectGuid.h"
#include <string>
#include <vector>
#include <memory>
#include <unordered_map>
#include <mutex>

class Player;
class Item;

// E2i6 Stage 8: common feature-adapter interface. Every adapter (Rack,
// Dissolve, Forge, and any future one) implements exactly this shape and is
// registered through the one factory below - no adapter is permitted to call
// EchoesActionBridge directly outside this interface, and no adapter may
// bypass the shared bridge to touch Lua/DB itself.
struct EchoesAdapterContext
{
    Player* player = nullptr;
    Item* item = nullptr;
    uint32 attunementPct = 0;
    bool fullyAttuned = false;

    // E2i8: additional context fields for the Dissolution adapter's richer
    // policy. Default to the safest ("protected"/"unknown") value so any
    // caller that does not populate them (e.g. existing Rack call sites)
    // never accidentally grants eligibility by omission.
    bool isEquipped = false;
    bool isSelectedForEquip = false;
    bool layer1Protected = false;
    bool keepInBagProtected = false;
    bool rackProtected = false;
    bool isQuestItem = false;
    bool isUniqueItem = false;
    bool isConjuredOrTemporary = false;
    bool isLockedOrInUse = false;
    bool hasStableItemGuid = true;
    bool stateIsFresh = true;
    bool hasPendingActionConflict = false;
    bool saferAlternativeExists = false;
    bool requestingBotOwnsItem = true; // set false only if ownership check explicitly fails

    // E2i8-R1: positive obsolescence proof - see EchoesDissolutionPolicy.h's
    // struct comment. Defaults to false (conservative); only the Dissolution
    // trigger site (MaybeOfferToDissolution in EchoesHooks.cpp) ever sets
    // this true, and only from a real StatsWeightCalculator comparison.
    bool replacementProvenSuperior = false;
};

class IEchoesActionAdapter
{
public:
    virtual ~IEchoesActionAdapter() = default;

    virtual char const* CapabilityName() const = 0;
    virtual char const* TelemetryCategory() const = 0;

    // Cheap, local-only eligibility pre-check (no Lua call) - e.g. item
    // class/quest-item exclusion, config enable flag. Must return false fast
    // for the overwhelming majority of items so Evaluate() (which may call
    // the bridge) is only reached for genuinely plausible candidates.
    virtual bool IsEligible(EchoesAdapterContext const& ctx) const = 0;

    // May call EchoesActionBridge::ValidateBotAction (dry-run, never mutates).
    virtual EchoesBotAction::Result Evaluate(EchoesAdapterContext const& ctx) = 0;

    // Interprets a Result into an adapter-specific outcome the caller can log
    // via TelemetryCategory-scoped counters. Pure, no side effects.
    virtual void InterpretResult(EchoesBotAction::Result const& result) = 0;

    // Only called after a confirmed SUCCESS result from an execution call -
    // updates this module's own local bot-state (e.g. releasing a Layer 2
    // protection entry once an item is confirmed Racked).
    virtual void UpdateBotState(EchoesAdapterContext const& ctx, EchoesBotAction::Result const& result) = 0;

    // Called whenever this adapter declines or fails - must never leave the
    // bot's normal Playerbots behavior worse off than doing nothing.
    virtual void Fallback(EchoesAdapterContext const& ctx) = 0;

    virtual bool IsEnabled() const = 0;
    virtual bool IsDryRunOnly() const = 0;
};

// One factory/registry, per Stage 8's explicit requirement that adapters
// register through a single mechanism rather than each wiring itself in
// separately.
class EchoesAdapterFactory
{
public:
    static EchoesAdapterFactory* instance()
    {
        static EchoesAdapterFactory inst;
        return &inst;
    }

    void Register(std::unique_ptr<IEchoesActionAdapter> adapter);
    IEchoesActionAdapter* Get(std::string const& capabilityName) const;
    std::vector<IEchoesActionAdapter*> GetAll() const;

    // E2i6 Stage 12: one per-item action lease/cooldown, shared by every
    // adapter, so no two adapters (or two evaluations of the same adapter)
    // can act on the same item instance concurrently. Bounded, process-local,
    // cleared on logout/shutdown exactly like EchoesProtectionTracker.
    bool TryAcquireLease(ObjectGuid itemGuid, uint32 nowSeconds, uint32 cooldownSeconds);
    void ReleaseLease(ObjectGuid itemGuid);
    void ClearLeases();

private:
    EchoesAdapterFactory() = default;
    std::vector<std::unique_ptr<IEchoesActionAdapter>> adapters_;

    mutable std::mutex leaseMutex_;
    std::unordered_map<ObjectGuid, uint32> leaseExpiryByItem_;
};

#endif
