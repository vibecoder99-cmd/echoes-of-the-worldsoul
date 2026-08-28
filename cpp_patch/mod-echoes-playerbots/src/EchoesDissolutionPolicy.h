#ifndef MODULE_ECHOES_PLAYERBOTS_DISSOLUTION_POLICY_H
#define MODULE_ECHOES_PLAYERBOTS_DISSOLUTION_POLICY_H

#include <cstdint>

// E2i8: pure, dependency-free Dissolution ("Legacy Forge") decision policy.
// Mirrors EchoesAwareness.h/EchoesDisposition.h's own pattern - zero
// AzerothCore/Playerbots/Lua dependency, standalone-testable.
//
// The default is always KEEP (do not dissolve), per Stage 4's explicit
// instruction. Every reject reason is reported distinctly so tests and
// telemetry can distinguish exactly why an item was declined.
//
// This function only ever decides local eligibility for a PREVIEW/dry-run
// request. It never itself grants execution - EvaluateExecutionGate (below)
// is a second, separate check applied only when a caller already holds an
// ELIGIBLE_FOR_PREVIEW-or-better result and wants to proceed to the real
// mutation.
enum class DissolutionPolicyDecision : std::uint8_t
{
    ELIGIBLE_FOR_PREVIEW = 0,
    REJECT_HUMAN_OWNER = 1,
    REJECT_WRONG_BOT_OWNER = 2,
    REJECT_EQUIPPED = 3,
    REJECT_SELECTED_FOR_EQUIP = 4,
    REJECT_NOT_FULLY_ATTUNED = 5,       // Echoes' own real threshold - see Stage 2 source audit
    REJECT_LAYER1_PROTECTED = 6,
    REJECT_KEEP_IN_BAG_PROTECTED = 7,
    REJECT_RACK_PROTECTED = 8,          // bot-specific safety margin, stricter than human path
    REJECT_QUEST_ITEM = 9,
    REJECT_UNIQUE_ITEM = 10,
    REJECT_CONJURED_OR_TEMPORARY = 11,
    REJECT_LOCKED_OR_IN_USE = 12,
    REJECT_MISSING_ITEM_GUID = 13,
    REJECT_STALE_STATE = 14,
    REJECT_SAFER_ALTERNATIVE_EXISTS = 15, // e.g. ordinary vendor-junk under bag pressure
    REJECT_PENDING_ACTION_CONFLICT = 16,  // another adapter/lease already holds this item
    REJECT_ADAPTER_DISABLED = 17,
    REJECT_ECHOES_VALIDATOR_REJECTED = 18, // real Lua-side ap_item_attune/ap_dissolved_items re-check failed

    // E2i8-R1: positive obsolescence proof, distinct from every check above.
    // Full attunement is a PREREQUISITE for consideration, never an
    // instruction to dissolve - a fully attuned item can still be equipped
    // (checked separately above), Rack-worthy (checked separately above), or
    // simply still useful, which none of the checks above can detect on
    // their own. This is the one new required predicate: the bot's own
    // authoritative gear evaluation (Playerbots' StatsWeightCalculator, the
    // same scorer Layer 1 already uses) must have proven a specific
    // replacement is a clear upgrade for this exact item's slot, in the same
    // decision event, before this item may even be considered obsolete.
    REJECT_NOT_PROVEN_OBSOLETE = 19,
};

char const* DissolutionPolicyDecisionToString(DissolutionPolicyDecision d);

struct DissolutionEligibilityContext
{
    bool adapterEnabled = false;
    bool isHumanPlayer = false;
    bool requestingBotOwnsItem = false;
    bool isEquipped = false;
    bool isSelectedForEquip = false;    // mid-flight in an equip decision this same tick
    bool fullyAttuned = false;          // authoritative: ap_item_attune.attuned = 1
    bool layer1Protected = false;       // Layer 1 would currently veto replacing this item
    bool keepInBagProtected = false;    // Layer 2 EchoesProtectionTracker has this item
    bool rackProtected = false;         // tracked in AP.Rack.Cache for this bot
    bool isQuestItem = false;
    bool isUniqueItem = false;
    bool isConjuredOrTemporary = false;
    bool isLockedOrInUse = false;
    bool hasStableItemGuid = false;
    bool stateIsFresh = true;           // false if inventory was re-read and item moved/changed
    bool hasPendingActionConflict = false;
    bool saferAlternativeExists = false; // only meaningful under bag-pressure evaluation

    // E2i8-R1: positive obsolescence proof. Defaults to false (conservative -
    // "unknown role/value -> KEEP", per Stage 4's explicit fallback rule).
    // Populated by the caller ONLY from a real, already-computed Playerbots
    // StatsWeightCalculator comparison (see EchoesHooks.cpp's
    // MaybeOfferToDissolution) - never hardcoded true, never inferred from
    // the mere absence of a protection flag. This module does not attempt to
    // detect alternate specs/roles, weapon pairing, or unique on-use effects
    // beyond what StatsWeightCalculator itself accounts for - those remain
    // documented limitations (see the E2i8-R1 reconciliation report), not
    // silently-assumed-safe gaps.
    bool replacementProvenSuperior = false;
};

DissolutionPolicyDecision EvaluateDissolutionEligibility(DissolutionEligibilityContext const& ctx);

// Second gate, applied only immediately before the real mutation call (Stage 6).
// Distinct from eligibility because a caller may legitimately want to preview
// (get ELIGIBLE_FOR_PREVIEW) while execution itself stays globally disabled.
struct DissolutionExecutionGateContext
{
    bool moduleActive = false;          // EchoesPresence::IsActiveOrDegraded()
    bool bridgeEnabled = false;
    bool dissolutionAdapterEnabled = false;
    bool executionExplicitlyEnabled = false; // EchoesConfig::dissolutionExecuteEnabled
    bool freshRevalidationPassed = false;    // eligibility re-checked immediately before mutation
    bool idempotencyTokenPresent = false;
    bool requestNotStale = false;
};

enum class DissolutionExecutionGateResult : std::uint8_t
{
    ALLOWED = 0,
    BLOCKED_MODULE_INACTIVE = 1,
    BLOCKED_BRIDGE_DISABLED = 2,
    BLOCKED_ADAPTER_DISABLED = 3,
    BLOCKED_EXECUTION_DISABLED = 4,
    BLOCKED_REVALIDATION_FAILED = 5,
    BLOCKED_MISSING_TOKEN = 6,
    BLOCKED_STALE_REQUEST = 7,
};

DissolutionExecutionGateResult EvaluateDissolutionExecutionGate(DissolutionExecutionGateContext const& ctx);

#endif
