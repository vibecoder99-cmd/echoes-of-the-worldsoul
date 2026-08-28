// E2i8 Stage 7 - standalone deterministic tests for the dependency-free
// Dissolution ("Legacy Forge") decision policy (EchoesDissolutionPolicy.h/.cpp).
// Zero AzerothCore/Lua dependency, mirrors EchoesAwarenessTests.cpp/
// EchoesDispositionTests.cpp/EchoesBotActionTypesTests.cpp's own pattern.
//
// The adapter/bridge/hook wiring that consumes this policy (EchoesDissolutionAdapter,
// EchoesActionBridge, the MaybeOfferToDissolution wiring in EchoesHooks.cpp) cannot
// be compiled standalone - verified structurally and at runtime instead, exactly
// the same split already established for every other layer in this module.

#include "EchoesDissolutionPolicy.h"
#include <cstdio>
#include <cstring>

static int g_pass = 0;
static int g_fail = 0;

static void CheckDecision(char const* name, DissolutionPolicyDecision actual, DissolutionPolicyDecision expected)
{
    bool ok = actual == expected;
    if (ok) ++g_pass; else ++g_fail;
    std::printf("%s: %-55s -> %s\n", ok ? "PASS" : "FAIL", name, DissolutionPolicyDecisionToString(actual));
}

static void CheckGate(char const* name, DissolutionExecutionGateResult actual, DissolutionExecutionGateResult expected)
{
    bool ok = actual == expected;
    if (ok) ++g_pass; else ++g_fail;
    std::printf("%s: %-55s -> %d\n", ok ? "PASS" : "FAIL", name, static_cast<int>(actual));
}

static void CheckStr(char const* name, char const* actual, char const* expected)
{
    bool ok = std::strcmp(actual, expected) == 0;
    if (ok) ++g_pass; else ++g_fail;
    std::printf("%s: %-55s -> %s\n", ok ? "PASS" : "FAIL", name, actual);
}

// A fully eligible bot bag item - the ONLY context every rejection test below
// starts from, flipping exactly one field per case, mirroring the "one
// controlled variable per test" pattern EchoesDispositionTests.cpp already uses.
static DissolutionEligibilityContext BaselineEligible()
{
    DissolutionEligibilityContext ctx;
    ctx.adapterEnabled = true;
    ctx.isHumanPlayer = false;
    ctx.requestingBotOwnsItem = true;
    ctx.isEquipped = false;
    ctx.isSelectedForEquip = false;
    ctx.fullyAttuned = true;
    ctx.layer1Protected = false;
    ctx.keepInBagProtected = false;
    ctx.rackProtected = false;
    ctx.isQuestItem = false;
    ctx.isUniqueItem = false;
    ctx.isConjuredOrTemporary = false;
    ctx.isLockedOrInUse = false;
    ctx.hasStableItemGuid = true;
    ctx.stateIsFresh = true;
    ctx.hasPendingActionConflict = false;
    ctx.saferAlternativeExists = false;
    ctx.replacementProvenSuperior = true; // E2i8-R1: baseline assumes proof was already established
    return ctx;
}

int main()
{
    int n = 0;

    // ---- 1. Golden path: every field safe -> ELIGIBLE_FOR_PREVIEW ----
    {
        auto ctx = BaselineEligible();
        CheckDecision("01_baseline_fully_eligible", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::ELIGIBLE_FOR_PREVIEW);
    }

    // ---- 2. One rejection category per case, in the exact order the
    // implementation checks them, so ordering precedence is also implicitly
    // verified (each test only flips the ctx field(s) needed to reach that
    // specific branch without an earlier branch firing first). ----
    {
        auto ctx = BaselineEligible(); ctx.adapterEnabled = false;
        CheckDecision("02_reject_adapter_disabled", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_ADAPTER_DISABLED);
    }
    {
        auto ctx = BaselineEligible(); ctx.isHumanPlayer = true;
        CheckDecision("03_reject_human_owner", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_HUMAN_OWNER);
    }
    {
        // Human check must win over ownership when both are true - human
        // isolation is the single most important invariant in this module.
        auto ctx = BaselineEligible(); ctx.isHumanPlayer = true; ctx.requestingBotOwnsItem = false;
        CheckDecision("04_human_precedes_wrong_owner", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_HUMAN_OWNER);
    }
    {
        auto ctx = BaselineEligible(); ctx.requestingBotOwnsItem = false;
        CheckDecision("05_reject_wrong_bot_owner", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_WRONG_BOT_OWNER);
    }
    {
        auto ctx = BaselineEligible(); ctx.hasStableItemGuid = false;
        CheckDecision("06_reject_missing_item_guid", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_MISSING_ITEM_GUID);
    }
    {
        auto ctx = BaselineEligible(); ctx.stateIsFresh = false;
        CheckDecision("07_reject_stale_state", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_STALE_STATE);
    }
    {
        auto ctx = BaselineEligible(); ctx.hasPendingActionConflict = true;
        CheckDecision("08_reject_pending_action_conflict", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_PENDING_ACTION_CONFLICT);
    }
    {
        auto ctx = BaselineEligible(); ctx.isEquipped = true;
        CheckDecision("09_reject_equipped", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_EQUIPPED);
    }
    {
        auto ctx = BaselineEligible(); ctx.isSelectedForEquip = true;
        CheckDecision("10_reject_selected_for_equip", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_SELECTED_FOR_EQUIP);
    }
    {
        auto ctx = BaselineEligible(); ctx.isQuestItem = true;
        CheckDecision("11_reject_quest_item", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_QUEST_ITEM);
    }
    {
        auto ctx = BaselineEligible(); ctx.isUniqueItem = true;
        CheckDecision("12_reject_unique_item", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_UNIQUE_ITEM);
    }
    {
        auto ctx = BaselineEligible(); ctx.isConjuredOrTemporary = true;
        CheckDecision("13_reject_conjured_or_temporary", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_CONJURED_OR_TEMPORARY);
    }
    {
        auto ctx = BaselineEligible(); ctx.isLockedOrInUse = true;
        CheckDecision("14_reject_locked_or_in_use", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_LOCKED_OR_IN_USE);
    }
    {
        auto ctx = BaselineEligible(); ctx.layer1Protected = true;
        CheckDecision("15_reject_layer1_protected", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_LAYER1_PROTECTED);
    }
    {
        auto ctx = BaselineEligible(); ctx.keepInBagProtected = true;
        CheckDecision("16_reject_keep_in_bag_protected", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_KEEP_IN_BAG_PROTECTED);
    }
    {
        // Rack precedence over Dissolution (Stage 4 explicit requirement) -
        // an item tracked on the Rack is never eligible for Dissolution.
        auto ctx = BaselineEligible(); ctx.rackProtected = true;
        CheckDecision("17_reject_rack_protected_precedence", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_RACK_PROTECTED);
    }
    {
        // The authoritative Echoes threshold (Stage 2 source audit): only
        // FULLY attuned, never "meaningfully attuned".
        auto ctx = BaselineEligible(); ctx.fullyAttuned = false;
        CheckDecision("18_reject_not_fully_attuned", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_NOT_FULLY_ATTUNED);
    }
    {
        auto ctx = BaselineEligible(); ctx.saferAlternativeExists = true;
        CheckDecision("19_reject_safer_alternative_exists", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_SAFER_ALTERNATIVE_EXISTS);
    }

    // ---- 3. Multi-flag combinations - confirms the ordering is total and
    // deterministic (not just individually correct), same defense-in-depth
    // spirit as Echoes' own Dissolve() ordering (Stage 2 audit). ----
    {
        auto ctx = BaselineEligible(); ctx.isEquipped = true; ctx.fullyAttuned = false; ctx.rackProtected = true;
        CheckDecision("20_equipped_wins_over_attune_and_rack", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_EQUIPPED);
    }
    {
        auto ctx = BaselineEligible(); ctx.rackProtected = true; ctx.fullyAttuned = false;
        CheckDecision("21_rack_protected_wins_over_not_attuned", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_RACK_PROTECTED);
    }
    {
        auto ctx = BaselineEligible(); ctx.isQuestItem = true; ctx.isUniqueItem = true; ctx.isLockedOrInUse = true;
        CheckDecision("22_quest_wins_over_unique_and_locked", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_QUEST_ITEM);
    }
    {
        // Every protection layer simultaneously plus adapter disabled - the
        // single cheapest/most-fundamental check must still win.
        auto ctx = BaselineEligible();
        ctx.adapterEnabled = false; ctx.isHumanPlayer = true; ctx.isEquipped = true;
        ctx.fullyAttuned = false; ctx.rackProtected = true; ctx.isQuestItem = true;
        CheckDecision("23_adapter_disabled_wins_over_everything", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_ADAPTER_DISABLED);
    }

    // ---- 4. DissolutionPolicyDecisionToString round-trips for a
    // representative sample (not exhaustive - the enum-to-string switch
    // itself is trivial and each branch is already exercised above via the
    // CheckDecision printf; these confirm the string form specifically,
    // which is what any future telemetry/report tooling will consume). ----
    CheckStr("24_tostring_eligible", DissolutionPolicyDecisionToString(DissolutionPolicyDecision::ELIGIBLE_FOR_PREVIEW), "ELIGIBLE_FOR_PREVIEW");
    CheckStr("25_tostring_not_fully_attuned", DissolutionPolicyDecisionToString(DissolutionPolicyDecision::REJECT_NOT_FULLY_ATTUNED), "REJECT_NOT_FULLY_ATTUNED");
    CheckStr("26_tostring_rack_protected", DissolutionPolicyDecisionToString(DissolutionPolicyDecision::REJECT_RACK_PROTECTED), "REJECT_RACK_PROTECTED");
    CheckStr("27_tostring_echoes_validator_rejected", DissolutionPolicyDecisionToString(DissolutionPolicyDecision::REJECT_ECHOES_VALIDATOR_REJECTED), "REJECT_ECHOES_VALIDATOR_REJECTED");

    // ---- 5. Execution gate - one blocked reason per case plus the single
    // ALLOWED path, in check order (Stage 6's "explicit enable gate
    // independent of Layer 1, KEEP_IN_BAG, Bridge, and Rack"). ----
    auto BaselineGateAllowed = []() {
        DissolutionExecutionGateContext g;
        g.moduleActive = true;
        g.bridgeEnabled = true;
        g.dissolutionAdapterEnabled = true;
        g.executionExplicitlyEnabled = true;
        g.freshRevalidationPassed = true;
        g.idempotencyTokenPresent = true;
        g.requestNotStale = true;
        return g;
    };
    {
        auto g = BaselineGateAllowed();
        CheckGate("28_gate_allowed", EvaluateDissolutionExecutionGate(g), DissolutionExecutionGateResult::ALLOWED);
    }
    {
        auto g = BaselineGateAllowed(); g.moduleActive = false;
        CheckGate("29_gate_blocked_module_inactive", EvaluateDissolutionExecutionGate(g), DissolutionExecutionGateResult::BLOCKED_MODULE_INACTIVE);
    }
    {
        auto g = BaselineGateAllowed(); g.bridgeEnabled = false;
        CheckGate("30_gate_blocked_bridge_disabled", EvaluateDissolutionExecutionGate(g), DissolutionExecutionGateResult::BLOCKED_BRIDGE_DISABLED);
    }
    {
        auto g = BaselineGateAllowed(); g.dissolutionAdapterEnabled = false;
        CheckGate("31_gate_blocked_adapter_disabled", EvaluateDissolutionExecutionGate(g), DissolutionExecutionGateResult::BLOCKED_ADAPTER_DISABLED);
    }
    {
        // The critical default-safe case: dry-run/preview stays available
        // while execution itself is off (E2i8's production-default posture).
        auto g = BaselineGateAllowed(); g.executionExplicitlyEnabled = false;
        CheckGate("32_gate_blocked_execution_disabled_by_default", EvaluateDissolutionExecutionGate(g), DissolutionExecutionGateResult::BLOCKED_EXECUTION_DISABLED);
    }
    {
        auto g = BaselineGateAllowed(); g.freshRevalidationPassed = false;
        CheckGate("33_gate_blocked_revalidation_failed", EvaluateDissolutionExecutionGate(g), DissolutionExecutionGateResult::BLOCKED_REVALIDATION_FAILED);
    }
    {
        auto g = BaselineGateAllowed(); g.idempotencyTokenPresent = false;
        CheckGate("34_gate_blocked_missing_token", EvaluateDissolutionExecutionGate(g), DissolutionExecutionGateResult::BLOCKED_MISSING_TOKEN);
    }
    {
        auto g = BaselineGateAllowed(); g.requestNotStale = false;
        CheckGate("35_gate_blocked_stale_request", EvaluateDissolutionExecutionGate(g), DissolutionExecutionGateResult::BLOCKED_STALE_REQUEST);
    }
    {
        // Execution-disabled must win even if every other gate condition is
        // also false - never let a downstream check accidentally mask the
        // single most important safety switch.
        auto g = BaselineGateAllowed();
        g.executionExplicitlyEnabled = false; g.freshRevalidationPassed = false;
        g.idempotencyTokenPresent = false; g.requestNotStale = false;
        CheckGate("36_gate_execution_disabled_wins_over_other_failures", EvaluateDissolutionExecutionGate(g), DissolutionExecutionGateResult::BLOCKED_EXECUTION_DISABLED);
    }

    // ---- 6. E2i8-R1: positive obsolescence proof. Full attunement is a
    // PREREQUISITE for consideration, never an instruction to dissolve - a
    // fully attuned but still-useful item must be rejected even when every
    // earlier check passes. ----
    {
        // The core new requirement: even a fully-attuned, otherwise fully
        // eligible item is rejected if no replacement was proven superior.
        auto ctx = BaselineEligible(); ctx.replacementProvenSuperior = false;
        CheckDecision("37_reject_not_proven_obsolete_fully_attuned_but_useful", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_NOT_PROVEN_OBSOLETE);
    }
    {
        // Obsolescence proof is checked strictly AFTER full-attunement -
        // a partially-attuned item must be rejected for that reason first,
        // never reach (or be masked by) the obsolescence check.
        auto ctx = BaselineEligible(); ctx.fullyAttuned = false; ctx.replacementProvenSuperior = false;
        CheckDecision("38_not_fully_attuned_precedes_obsolescence_check", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_NOT_FULLY_ATTUNED);
    }
    {
        // Rack protection must still win over a missing obsolescence proof -
        // upstream protections are never weakened by this new check.
        auto ctx = BaselineEligible(); ctx.rackProtected = true; ctx.replacementProvenSuperior = false;
        CheckDecision("39_rack_protected_wins_over_missing_obsolescence_proof", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_RACK_PROTECTED);
    }
    {
        // Fully attuned AND conclusively obsolete (proof present, nothing else
        // blocks it) - this is the one path that reaches ELIGIBLE_FOR_PREVIEW.
        auto ctx = BaselineEligible();
        CheckDecision("40_fully_attuned_and_conclusively_obsolete_eligible", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::ELIGIBLE_FOR_PREVIEW);
    }
    {
        // Obsolescence proof present but a safer alternative still exists
        // (e.g. bag-pressure vendor-junk case) - safer-alternative check
        // still runs after obsolescence proof and can still reject.
        auto ctx = BaselineEligible(); ctx.saferAlternativeExists = true;
        CheckDecision("41_obsolescence_proven_but_safer_alternative_still_rejects", EvaluateDissolutionEligibility(ctx),
                       DissolutionPolicyDecision::REJECT_SAFER_ALTERNATIVE_EXISTS);
    }
    CheckStr("42_tostring_not_proven_obsolete", DissolutionPolicyDecisionToString(DissolutionPolicyDecision::REJECT_NOT_PROVEN_OBSOLETE), "REJECT_NOT_PROVEN_OBSOLETE");

    // --- Structural/source-cited notes (engine-coupled, proven by direct source read of
    //     EchoesHooks.cpp and disposable/production runtime evidence, not independently
    //     unit-testable in this pure-header test file - matching this project's established
    //     convention for wiring changes, e.g. E2j7c's 280-287 notes) ---
    // 43_e2j11_execute_call_site_is_the_only_one: EchoesDissolutionAdapter::Execute() (dryRun=
    //     false) is called from exactly one place in the entire module -
    //     MaybeOfferToDissolution, immediately after a SUCCESS dry-run result, gated behind
    //     EchoesConfig::dissolutionExecuteEnabled - confirmed by direct source read (zero other
    //     call sites to ->Execute(ctx exist anywhere in mod-echoes-playerbots).
    // 44_e2j11_execution_reuses_the_gate_unchanged: MaybeOfferToDissolution never re-implements
    //     or bypasses EvaluateDissolutionExecutionGate/EvaluateDissolutionEligibility - Execute()
    //     itself performs the fresh revalidation and gate check (tests 28-36 above already prove
    //     that logic exhaustively); the E2j11 wiring change is additive-only, calling an
    //     already-fully-tested method, not modifying its internals.
    // 45_e2j11_default_off_preserves_prior_behavior_exactly: with
    //     dissolutionExecuteEnabled=false (the unchanged production default), the new
    //     `if (EchoesConfig::instance()->dissolutionExecuteEnabled)` block in
    //     MaybeOfferToDissolution is never entered - the dry-run-only code path above and below
    //     it is byte-for-byte unchanged from pre-E2j11, confirmed by direct source read.
    // 46_e2j11_idempotency_token_uniqueness: the token is built from (bot guid, item guid,
    //     decision-tick timestamp) - the same granularity every other lease/cooldown key in this
    //     module already uses (e.g. TryOneProgressionSpendForBot's leaseKey) - a genuine repeat
    //     attempt on the same item within the same second is prevented upstream by the
    //     TryAcquireLease(itemGuid, now, 60) call already made before Evaluate()/Execute() are
    //     ever reached, not by the token's own uniqueness alone.
    // 47_e2j11_lease_held_through_execution: EchoesAdapterFactory::ReleaseLease(itemGuid) is
    //     called once, after the entire dry-run-then-maybe-execute sequence completes - the lease
    //     acquired before Evaluate() is held through Execute() too, so no concurrent decision pass
    //     can touch the same item guid mid-execution.

    (void)n;
    std::printf("\n%d/%d tests passed.\n", g_pass, g_pass + g_fail);
    if (g_fail == 0)
        std::printf("ALL TESTS PASSED\n");
    return g_fail == 0 ? 0 : 1;
}
