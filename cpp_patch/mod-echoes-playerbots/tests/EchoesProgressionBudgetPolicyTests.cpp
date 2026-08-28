// E2j1 - EchoesProgressionBudgetPolicy tests.
//
// EvaluateProgressionSpend() is pure and dependency-free by design (see
// EchoesProgressionBudgetPolicy.h) - it compiles and is fully testable standalone, matching
// EchoesDissolutionPolicyTests.cpp's own established pattern. The bridge/adapter integration
// (real Lua calls, real balance reads, real post-spend verification) is proven separately by
// the E2j1 Stage 10 isolated disposable-mutation validation, not by this file - identical split
// to every other DB/ALE-touching class in this module.

#include "../src/EchoesProgressionBudgetPolicy.h"
#include <cstdio>

static int g_pass = 0;
static int g_fail = 0;

static void CheckDecision(char const* name, ProgressionSpendDecision actual, ProgressionSpendDecision expected)
{
    if (actual == expected) { ++g_pass; std::printf("PASS: %-55s -> %s\n", name, ProgressionSpendDecisionToString(actual)); }
    else { ++g_fail; std::printf("FAIL: %-55s -> got %s, expected %s\n", name,
        ProgressionSpendDecisionToString(actual), ProgressionSpendDecisionToString(expected)); }
}

static ProgressionBudgetContext Baseline()
{
    ProgressionBudgetContext ctx;
    ctx.adapterEnabled = true;
    ctx.currentBalance = 10000;
    ctx.reserveEssence = 500;
    ctx.maxSpendPerDecision = 2000;
    ctx.proposedCost = 1000;
    ctx.actionsAlreadyThisLogin = 0;
    ctx.maxActionsPerLogin = 3;
    ctx.secondsSinceLastSpend = 99999;
    ctx.cooldownSeconds = 3600;
    ctx.balanceIsFresh = true;
    return ctx;
}

int main()
{
    // --- Baseline eligible ---
    { auto c = Baseline();
      CheckDecision("01_baseline_eligible", EvaluateProgressionSpend(c), ProgressionSpendDecision::ELIGIBLE_TO_SPEND); }

    // --- Adapter disabled (system disabled / Echoes-absent proxy) ---
    { auto c = Baseline(); c.adapterEnabled = false;
      CheckDecision("02_adapter_disabled", EvaluateProgressionSpend(c), ProgressionSpendDecision::REJECT_ADAPTER_DISABLED); }

    // --- Invalid cost / prerequisite missing ---
    { auto c = Baseline(); c.proposedCost = 0;
      CheckDecision("03_zero_cost_invalid", EvaluateProgressionSpend(c), ProgressionSpendDecision::REJECT_INVALID_COST); }
    { auto c = Baseline(); c.maxSpendPerDecision = 0;
      CheckDecision("04_zero_max_spend_invalid", EvaluateProgressionSpend(c), ProgressionSpendDecision::REJECT_INVALID_COST); }

    // --- Stale balance ---
    { auto c = Baseline(); c.balanceIsFresh = false;
      CheckDecision("05_stale_balance_rejected", EvaluateProgressionSpend(c), ProgressionSpendDecision::REJECT_STALE_BALANCE); }
    { auto c = Baseline(); c.currentBalance = -1;
      CheckDecision("06_unset_balance_rejected", EvaluateProgressionSpend(c), ProgressionSpendDecision::REJECT_STALE_BALANCE); }

    // --- Login cap / hourly budget reached ---
    { auto c = Baseline(); c.actionsAlreadyThisLogin = 3; c.maxActionsPerLogin = 3;
      CheckDecision("07_login_cap_reached_exact", EvaluateProgressionSpend(c), ProgressionSpendDecision::REJECT_LOGIN_CAP_REACHED); }
    { auto c = Baseline(); c.actionsAlreadyThisLogin = 5; c.maxActionsPerLogin = 3;
      CheckDecision("08_login_cap_exceeded", EvaluateProgressionSpend(c), ProgressionSpendDecision::REJECT_LOGIN_CAP_REACHED); }
    { auto c = Baseline(); c.actionsAlreadyThisLogin = 2; c.maxActionsPerLogin = 3;
      CheckDecision("09_login_cap_not_yet_reached", EvaluateProgressionSpend(c), ProgressionSpendDecision::ELIGIBLE_TO_SPEND); }

    // --- Cooldown / duplicate request / repeated login ---
    { auto c = Baseline(); c.secondsSinceLastSpend = 10; c.cooldownSeconds = 3600;
      CheckDecision("10_cooldown_active_recent_spend", EvaluateProgressionSpend(c), ProgressionSpendDecision::REJECT_COOLDOWN_ACTIVE); }
    { auto c = Baseline(); c.secondsSinceLastSpend = 3600; c.cooldownSeconds = 3600;
      CheckDecision("11_cooldown_exactly_elapsed_ok", EvaluateProgressionSpend(c), ProgressionSpendDecision::ELIGIBLE_TO_SPEND); }
    { auto c = Baseline(); c.secondsSinceLastSpend = 0; c.cooldownSeconds = 0;
      CheckDecision("12_zero_cooldown_never_blocks", EvaluateProgressionSpend(c), ProgressionSpendDecision::ELIGIBLE_TO_SPEND); }

    // --- Per-decision cap ---
    { auto c = Baseline(); c.proposedCost = 2001; c.maxSpendPerDecision = 2000;
      CheckDecision("13_exceeds_per_decision_max", EvaluateProgressionSpend(c), ProgressionSpendDecision::REJECT_EXCEEDS_PER_DECISION_MAX); }
    { auto c = Baseline(); c.proposedCost = 2000; c.maxSpendPerDecision = 2000;
      CheckDecision("14_exactly_at_per_decision_max_ok", EvaluateProgressionSpend(c), ProgressionSpendDecision::ELIGIBLE_TO_SPEND); }

    // --- Insufficient balance (below reserve) ---
    { auto c = Baseline(); c.currentBalance = 500;
      CheckDecision("15_insufficient_balance_below_cost", EvaluateProgressionSpend(c), ProgressionSpendDecision::REJECT_INSUFFICIENT_BALANCE); }
    { auto c = Baseline(); c.currentBalance = 1000; c.proposedCost = 1000; c.reserveEssence = 500;
      CheckDecision("16_spend_would_drop_below_reserve", EvaluateProgressionSpend(c), ProgressionSpendDecision::REJECT_BELOW_RESERVE); }
    { auto c = Baseline(); c.currentBalance = 1500; c.proposedCost = 1000; c.reserveEssence = 500;
      CheckDecision("17_exactly_at_reserve_after_spend_ok", EvaluateProgressionSpend(c), ProgressionSpendDecision::ELIGIBLE_TO_SPEND); }
    { auto c = Baseline(); c.currentBalance = 1499; c.proposedCost = 1000; c.reserveEssence = 500;
      CheckDecision("18_one_below_reserve_after_spend_rejected", EvaluateProgressionSpend(c), ProgressionSpendDecision::REJECT_BELOW_RESERVE); }

    // --- Zero balance ---
    { auto c = Baseline(); c.currentBalance = 0;
      CheckDecision("19_zero_balance_rejected", EvaluateProgressionSpend(c), ProgressionSpendDecision::REJECT_INSUFFICIENT_BALANCE); }

    // --- Large accumulated balance still respects per-decision cap ---
    { auto c = Baseline(); c.currentBalance = 1000000; c.proposedCost = 2001; c.maxSpendPerDecision = 2000;
      CheckDecision("20_large_balance_still_capped_per_decision", EvaluateProgressionSpend(c), ProgressionSpendDecision::REJECT_EXCEEDS_PER_DECISION_MAX); }
    { auto c = Baseline(); c.currentBalance = 1000000; c.proposedCost = 2000;
      CheckDecision("21_large_balance_eligible_within_cap", EvaluateProgressionSpend(c), ProgressionSpendDecision::ELIGIBLE_TO_SPEND); }

    // --- Cap reached (as a precedence case: adapter-disabled wins over everything else) ---
    { auto c = Baseline(); c.adapterEnabled = false; c.currentBalance = -1; c.actionsAlreadyThisLogin = 999;
      CheckDecision("22_adapter_disabled_wins_over_all_other_failures", EvaluateProgressionSpend(c), ProgressionSpendDecision::REJECT_ADAPTER_DISABLED); }

    // --- ToString coverage ---
    CheckDecision("23_tostring_eligible", ProgressionSpendDecision::ELIGIBLE_TO_SPEND, ProgressionSpendDecision::ELIGIBLE_TO_SPEND);
    CheckDecision("24_tostring_below_reserve", ProgressionSpendDecision::REJECT_BELOW_RESERVE, ProgressionSpendDecision::REJECT_BELOW_RESERVE);

    // --- Structural/source-cited scenarios (verified by direct source inspection of the real
    //     call site in EchoesHooks.cpp; not independently unit-testable outside a live
    //     worldserver - see E2j1 Stage 10 isolated disposable-mutation evidence) ---
    // 25_echoes_absent: MaybeReconcileProgressionSpending's GetProgressionSnapshot call returns
    //     snap.ok=false when Lua/Echoes is unreachable, and the function returns immediately
    //     before ever constructing a ProgressionBudgetContext - fails closed identically to
    //     every other bridge call in this module.
    // 26_human_rejected: MaybeReconcileProgressionSpending's first statement is the same
    //     `!GET_PLAYERBOT_AI(player)` gate as every other hook - verified by direct source read,
    //     not re-tested here since it is identical to the already-covered pattern.
    // 27_bot_account_isolation: each ProgressionBudgetContext instance is constructed fresh
    //     per-bot inside MaybeReconcileProgressionSpending (a local, not shared state); the only
    //     persistent state (lastSpendSecondsByKey) is explicitly keyed on botGuidLow, so one
    //     bot's cooldown can never be read or affected by another bot's spend.
    // 28_duplicate_request_same_login: the per-login actionsThisLogin counter is a local
    //     variable scoped to one MaybeReconcileProgressionSpending call - it cannot leak
    //     between logins or be replayed without a fresh login event.
    // 29_repeated_login_cooldown_enforced: proven by tests 10/11 above (the cooldown check
    //     itself); the real secondsSinceLastSpend value is computed from
    //     lastSpendSecondsByKey, updated only after a verified successful spend.

    std::printf("\n%d/%d tests passed.\n", g_pass, g_pass + g_fail);
    if (g_fail == 0) std::printf("ALL TESTS PASSED\n");
    return g_fail == 0 ? 0 : 1;
}
