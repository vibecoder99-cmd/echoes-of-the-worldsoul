#include "EchoesDissolutionAdapter.h"
#include "EchoesActionBridge.h"
#include "EchoesConfig.h"
#include "EchoesProtection.h"
#include "Item.h"
#include "ItemTemplate.h"
#include "Player.h"

// Note: the real ap_rack membership check (read-only, single indexed lookup,
// same pattern EchoesBotCache already uses) lives in EchoesHooks.cpp, where
// EchoesAdapterContext is populated from live game state before being
// passed to this adapter - this class only ever consumes ctx.rackProtected,
// it never queries the database itself, keeping this file's own
// responsibility limited to policy evaluation and bridge calls.

bool EchoesDissolutionAdapter::IsEnabled() const
{
    return EchoesConfig::instance()->bridgeEnabled
        && EchoesConfig::instance()->dissolveEnabled
        && EchoesConfig::instance()->dissolutionDryRunEnabled;
}

bool EchoesDissolutionAdapter::IsDryRunOnly() const
{
    return !EchoesConfig::instance()->dissolutionExecuteEnabled;
}

bool EchoesDissolutionAdapter::IsEligible(EchoesAdapterContext const& ctx) const
{
    if (!IsEnabled())
        return false;
    if (!ctx.item || !ctx.player)
        return false;

    ItemTemplate const* proto = ctx.item->GetTemplate();
    if (!proto)
        return false;

    // Cheap local pre-check only (per the factory interface contract) -
    // weapon/armor with a valid equip slot, same guard Rack and Echoes'
    // own Dissolve() eligibility both already use.
    if (!((proto->Class == ITEM_CLASS_WEAPON || proto->Class == ITEM_CLASS_ARMOR) && proto->InventoryType > 0))
        return false;

    return EvaluateLocalPolicy(ctx) == DissolutionPolicyDecision::ELIGIBLE_FOR_PREVIEW;
}

DissolutionPolicyDecision EchoesDissolutionAdapter::EvaluateLocalPolicy(EchoesAdapterContext const& ctx) const
{
    DissolutionEligibilityContext pctx;
    pctx.adapterEnabled = IsEnabled();
    pctx.isHumanPlayer = false; // caller (EchoesHooks.cpp) never invokes this adapter for a human -
                                // GET_PLAYERBOT_AI is checked before any adapter is ever reached,
                                // identical to every other hook in this module
    pctx.requestingBotOwnsItem = ctx.requestingBotOwnsItem;
    pctx.isEquipped = ctx.isEquipped;
    pctx.isSelectedForEquip = ctx.isSelectedForEquip;
    // E2i8 correction (bot policy alignment audit): these two config flags
    // were loaded by EchoesConfig but never actually consulted anywhere,
    // making them dead/decorative - an operator toggling either during
    // testing would see no behavior change. Wired here so they are real:
    // when RequireFullAttunement is false, the fully-attuned gate is
    // bypassed (pctx.fullyAttuned forced true); when RejectRackProtected is
    // false, the Rack-protection gate is bypassed (pctx.rackProtected forced
    // false). Both default to true, which reproduces the exact prior
    // hardcoded behavior - this is purely making an existing config surface
    // functional, not changing any default outcome.
    pctx.fullyAttuned = EchoesConfig::instance()->dissolutionRequiresFullAttunement ? ctx.fullyAttuned : true;
    pctx.layer1Protected = ctx.layer1Protected; // always false for unequipped bag items in practice -
                                                 // Layer 1 has no persisted state outside the equip hook
    pctx.keepInBagProtected = ctx.keepInBagProtected;
    pctx.rackProtected = EchoesConfig::instance()->dissolutionRejectsRackProtected ? ctx.rackProtected : false;
    pctx.isQuestItem = ctx.isQuestItem;
    pctx.isUniqueItem = ctx.isUniqueItem;
    pctx.isConjuredOrTemporary = ctx.isConjuredOrTemporary;
    pctx.isLockedOrInUse = ctx.isLockedOrInUse;
    pctx.hasStableItemGuid = ctx.hasStableItemGuid;
    pctx.stateIsFresh = ctx.stateIsFresh;
    pctx.hasPendingActionConflict = ctx.hasPendingActionConflict;
    pctx.saferAlternativeExists = ctx.saferAlternativeExists;
    pctx.replacementProvenSuperior = ctx.replacementProvenSuperior;

    return EvaluateDissolutionEligibility(pctx);
}

EchoesBotAction::Result EchoesDissolutionAdapter::Evaluate(EchoesAdapterContext const& ctx)
{
    ++evaluations;

    EchoesBotAction::Request req;
    req.actionType = EchoesBotAction::ActionType::DISSOLVE;
    req.itemEntry = ctx.item->GetTemplate()->ItemId;
    req.itemGuidRaw = ctx.item->GetGUID().GetRawValue();
    req.dryRun = true; // Evaluate() is always a preview - see Execute() for the real path

    EchoesBotAction::Result result;
    if (!EchoesActionBridge::instance()->ValidateBotAction(ctx.player, req, result))
    {
        result.resultCode = EchoesBotAction::ResultCode::BRIDGE_UNAVAILABLE;
    }
    return result;
}

void EchoesDissolutionAdapter::InterpretResult(EchoesBotAction::Result const& result)
{
    if (result.resultCode == EchoesBotAction::ResultCode::SUCCESS)
        ++eligibleDryRuns;
    else
        ++rejections;
}

void EchoesDissolutionAdapter::UpdateBotState(EchoesAdapterContext const& /*ctx*/, EchoesBotAction::Result const& result)
{
    // Only ever meaningful after a confirmed SUCCESS execution result (never
    // after a dry-run) - this module keeps no local shadow state of
    // ap_dissolved_items/ap_mastery/ap_residue, so there is nothing to
    // update locally even on success; Echoes' own tables remain the single
    // source of truth, exactly as required.
    (void)result;
}

void EchoesDissolutionAdapter::Fallback(EchoesAdapterContext const& /*ctx*/)
{
    // Declining/deferring Dissolution leaves the item exactly where Layer
    // 1/2/Rack already left it - never worse than doing nothing.
}

EchoesBotAction::Result EchoesDissolutionAdapter::Execute(EchoesAdapterContext const& ctx, std::string const& idempotencyToken)
{
    EchoesBotAction::Result result;

    // Fresh revalidation immediately before mutation (Stage 6 explicit
    // requirement) - never trust a policy decision made even one event ago.
    DissolutionPolicyDecision freshDecision = EvaluateLocalPolicy(ctx);

    DissolutionExecutionGateContext gate;
    gate.moduleActive = true; // caller (EchoesHooks.cpp) already checked EchoesPresence before
                               // ever reaching this method - identical invariant to every other hook
    gate.bridgeEnabled = EchoesConfig::instance()->bridgeEnabled;
    gate.dissolutionAdapterEnabled = IsEnabled();
    gate.executionExplicitlyEnabled = EchoesConfig::instance()->dissolutionExecuteEnabled;
    gate.freshRevalidationPassed = (freshDecision == DissolutionPolicyDecision::ELIGIBLE_FOR_PREVIEW);
    gate.idempotencyTokenPresent = !idempotencyToken.empty(); // caller guarantees uniqueness; bridge/Lua
                                                               // side is the authority on actual reuse
    gate.requestNotStale = ctx.stateIsFresh;

    DissolutionExecutionGateResult gateResult = EvaluateDissolutionExecutionGate(gate);
    if (gateResult != DissolutionExecutionGateResult::ALLOWED)
    {
        ++executionsBlockedByGate;
        result.resultCode = EchoesBotAction::ResultCode::REJECTED;
        result.reasonCode = "execution_gate_blocked";
        return result;
    }

    EchoesBotAction::Request req;
    req.actionType = EchoesBotAction::ActionType::DISSOLVE;
    req.itemEntry = ctx.item->GetTemplate()->ItemId;
    req.itemGuidRaw = ctx.item->GetGUID().GetRawValue();
    req.idempotencyToken = idempotencyToken;
    req.dryRun = false; // the only place in this class that ever sets dryRun=false

    if (!EchoesActionBridge::instance()->ExecuteBotAction(ctx.player, req, result))
    {
        result.resultCode = EchoesBotAction::ResultCode::BRIDGE_UNAVAILABLE;
        ++executionsRejected;
        return result;
    }

    if (result.resultCode == EchoesBotAction::ResultCode::SUCCESS)
        ++executionsSucceeded;
    else
        ++executionsRejected;

    return result;
}
