#include "EchoesDissolutionPolicy.h"

char const* DissolutionPolicyDecisionToString(DissolutionPolicyDecision d)
{
    switch (d)
    {
        case DissolutionPolicyDecision::ELIGIBLE_FOR_PREVIEW: return "ELIGIBLE_FOR_PREVIEW";
        case DissolutionPolicyDecision::REJECT_HUMAN_OWNER: return "REJECT_HUMAN_OWNER";
        case DissolutionPolicyDecision::REJECT_WRONG_BOT_OWNER: return "REJECT_WRONG_BOT_OWNER";
        case DissolutionPolicyDecision::REJECT_EQUIPPED: return "REJECT_EQUIPPED";
        case DissolutionPolicyDecision::REJECT_SELECTED_FOR_EQUIP: return "REJECT_SELECTED_FOR_EQUIP";
        case DissolutionPolicyDecision::REJECT_NOT_FULLY_ATTUNED: return "REJECT_NOT_FULLY_ATTUNED";
        case DissolutionPolicyDecision::REJECT_LAYER1_PROTECTED: return "REJECT_LAYER1_PROTECTED";
        case DissolutionPolicyDecision::REJECT_KEEP_IN_BAG_PROTECTED: return "REJECT_KEEP_IN_BAG_PROTECTED";
        case DissolutionPolicyDecision::REJECT_RACK_PROTECTED: return "REJECT_RACK_PROTECTED";
        case DissolutionPolicyDecision::REJECT_QUEST_ITEM: return "REJECT_QUEST_ITEM";
        case DissolutionPolicyDecision::REJECT_UNIQUE_ITEM: return "REJECT_UNIQUE_ITEM";
        case DissolutionPolicyDecision::REJECT_CONJURED_OR_TEMPORARY: return "REJECT_CONJURED_OR_TEMPORARY";
        case DissolutionPolicyDecision::REJECT_LOCKED_OR_IN_USE: return "REJECT_LOCKED_OR_IN_USE";
        case DissolutionPolicyDecision::REJECT_MISSING_ITEM_GUID: return "REJECT_MISSING_ITEM_GUID";
        case DissolutionPolicyDecision::REJECT_STALE_STATE: return "REJECT_STALE_STATE";
        case DissolutionPolicyDecision::REJECT_SAFER_ALTERNATIVE_EXISTS: return "REJECT_SAFER_ALTERNATIVE_EXISTS";
        case DissolutionPolicyDecision::REJECT_PENDING_ACTION_CONFLICT: return "REJECT_PENDING_ACTION_CONFLICT";
        case DissolutionPolicyDecision::REJECT_ADAPTER_DISABLED: return "REJECT_ADAPTER_DISABLED";
        case DissolutionPolicyDecision::REJECT_ECHOES_VALIDATOR_REJECTED: return "REJECT_ECHOES_VALIDATOR_REJECTED";
        case DissolutionPolicyDecision::REJECT_NOT_PROVEN_OBSOLETE: return "REJECT_NOT_PROVEN_OBSOLETE";
    }
    return "UNKNOWN";
}

DissolutionPolicyDecision EvaluateDissolutionEligibility(DissolutionEligibilityContext const& ctx)
{
    // Ordered from cheapest/most-fundamental to most-specific, matching the
    // spirit of Echoes' own Dissolve() defensive ordering (Stage 2 audit) -
    // human isolation and ownership are checked before anything else, exactly
    // like every other hook in this module.
    if (!ctx.adapterEnabled)
        return DissolutionPolicyDecision::REJECT_ADAPTER_DISABLED;

    if (ctx.isHumanPlayer)
        return DissolutionPolicyDecision::REJECT_HUMAN_OWNER;

    if (!ctx.requestingBotOwnsItem)
        return DissolutionPolicyDecision::REJECT_WRONG_BOT_OWNER;

    if (!ctx.hasStableItemGuid)
        return DissolutionPolicyDecision::REJECT_MISSING_ITEM_GUID;

    if (!ctx.stateIsFresh)
        return DissolutionPolicyDecision::REJECT_STALE_STATE;

    if (ctx.hasPendingActionConflict)
        return DissolutionPolicyDecision::REJECT_PENDING_ACTION_CONFLICT;

    if (ctx.isEquipped)
        return DissolutionPolicyDecision::REJECT_EQUIPPED;

    if (ctx.isSelectedForEquip)
        return DissolutionPolicyDecision::REJECT_SELECTED_FOR_EQUIP;

    if (ctx.isQuestItem)
        return DissolutionPolicyDecision::REJECT_QUEST_ITEM;

    if (ctx.isUniqueItem)
        return DissolutionPolicyDecision::REJECT_UNIQUE_ITEM;

    if (ctx.isConjuredOrTemporary)
        return DissolutionPolicyDecision::REJECT_CONJURED_OR_TEMPORARY;

    if (ctx.isLockedOrInUse)
        return DissolutionPolicyDecision::REJECT_LOCKED_OR_IN_USE;

    // Layer 1 / Layer 2 / Rack protection - each an independent, earlier
    // decision this module already made about the same item. Dissolution
    // must never contradict them.
    if (ctx.layer1Protected)
        return DissolutionPolicyDecision::REJECT_LAYER1_PROTECTED;

    if (ctx.keepInBagProtected)
        return DissolutionPolicyDecision::REJECT_KEEP_IN_BAG_PROTECTED;

    if (ctx.rackProtected)
        return DissolutionPolicyDecision::REJECT_RACK_PROTECTED;

    // Authoritative Echoes threshold (Stage 2 source audit): only a FULLY
    // attuned item is ever eligible - never a "meaningfully attuned" one.
    if (!ctx.fullyAttuned)
        return DissolutionPolicyDecision::REJECT_NOT_FULLY_ATTUNED;

    // E2i8-R1: full attunement is a PREREQUISITE for consideration, never an
    // instruction to dissolve. Positive obsolescence proof is required next -
    // absence of a protection flag is not proof of uselessness. This must be
    // an authoritative, already-computed fact (Playerbots' own gear scoring),
    // never assumed true by default (the struct default is false).
    if (!ctx.replacementProvenSuperior)
        return DissolutionPolicyDecision::REJECT_NOT_PROVEN_OBSOLETE;

    if (ctx.saferAlternativeExists)
        return DissolutionPolicyDecision::REJECT_SAFER_ALTERNATIVE_EXISTS;

    return DissolutionPolicyDecision::ELIGIBLE_FOR_PREVIEW;
}

DissolutionExecutionGateResult EvaluateDissolutionExecutionGate(DissolutionExecutionGateContext const& ctx)
{
    if (!ctx.moduleActive)
        return DissolutionExecutionGateResult::BLOCKED_MODULE_INACTIVE;
    if (!ctx.bridgeEnabled)
        return DissolutionExecutionGateResult::BLOCKED_BRIDGE_DISABLED;
    if (!ctx.dissolutionAdapterEnabled)
        return DissolutionExecutionGateResult::BLOCKED_ADAPTER_DISABLED;
    if (!ctx.executionExplicitlyEnabled)
        return DissolutionExecutionGateResult::BLOCKED_EXECUTION_DISABLED;
    if (!ctx.freshRevalidationPassed)
        return DissolutionExecutionGateResult::BLOCKED_REVALIDATION_FAILED;
    if (!ctx.idempotencyTokenPresent)
        return DissolutionExecutionGateResult::BLOCKED_MISSING_TOKEN;
    if (!ctx.requestNotStale)
        return DissolutionExecutionGateResult::BLOCKED_STALE_REQUEST;
    return DissolutionExecutionGateResult::ALLOWED;
}
