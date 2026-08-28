/*
 * Standalone, deterministic unit tests for the Layer 1 decision policy
 * (EvaluateAwareness). Intentionally NOT under src/, so the module build
 * system's auto-discovery (CollectSourceFiles over src/ only) never links
 * this test binary into the worldserver.
 *
 * EchoesAwareness.h/.cpp have zero AzerothCore dependency by design, so
 * this file compiles completely standalone:
 *
 *   g++ -std=c++17 -I../src ../src/EchoesAwareness.cpp EchoesAwarenessTests.cpp -o echoes_awareness_tests
 *   ./echoes_awareness_tests
 *
 * Exit code 0 and "ALL TESTS PASSED" means every case below passed.
 */

#include "EchoesAwareness.h"
#include <cstdio>
#include <cstdlib>

static int g_failures = 0;
static int g_total = 0;

static void Check(char const* name, EchoesAwarenessDecision actual, EchoesAwarenessDecision expected)
{
    ++g_total;
    if (actual != expected)
    {
        ++g_failures;
        std::printf("FAIL: %-70s expected=%-28s actual=%s\n",
                     name,
                     EchoesAwarenessDecisionToString(expected),
                     EchoesAwarenessDecisionToString(actual));
    }
    else
    {
        std::printf("PASS: %-70s -> %s\n", name, EchoesAwarenessDecisionToString(actual));
    }
}

int main()
{
    // Common thresholds used across most cases (defaults from
    // mod_echoes_playerbots.conf.dist).
    const std::uint32_t MEANINGFUL = 25;
    const std::uint32_t CLEAR = 15;

    // 1. 0% attuned item + marginal upgrade (5%) -> Echoes has no opinion,
    //    defer entirely (nothing worth protecting, and not a clear upgrade).
    Check("0pct_attuned_marginal_upgrade",
          EvaluateAwareness(true, 100.0f, 105.0f, 0, false, MEANINGFUL, CLEAR),
          EchoesAwarenessDecision::DEFAULT_PLAYERBOTS_DECISION);

    // 2. Partially attuned (10%, below meaningful threshold) + marginal
    //    upgrade -> still defer, 10% is not "meaningful" yet.
    Check("partial_10pct_attuned_marginal_upgrade",
          EvaluateAwareness(true, 100.0f, 105.0f, 10, false, MEANINGFUL, CLEAR),
          EchoesAwarenessDecision::DEFAULT_PLAYERBOTS_DECISION);

    // 3. Highly attuned (60%, above meaningful threshold) + marginal
    //    upgrade -> veto, keep the attuned item.
    Check("highly_60pct_attuned_marginal_upgrade",
          EvaluateAwareness(true, 100.0f, 105.0f, 60, false, MEANINGFUL, CLEAR),
          EchoesAwarenessDecision::KEEP_ATTUNED_ITEM);

    // 4. Fully attuned + marginal upgrade -> veto, keep the attuned item.
    Check("fully_attuned_marginal_upgrade",
          EvaluateAwareness(true, 100.0f, 105.0f, 100, true, MEANINGFUL, CLEAR),
          EchoesAwarenessDecision::KEEP_ATTUNED_ITEM);

    // 5. Partially attuned (40%, above meaningful) + a CLEAR upgrade (30%
    //    margin) -> always accept a clear upgrade regardless of attunement.
    Check("partial_attuned_clear_upgrade",
          EvaluateAwareness(true, 100.0f, 130.0f, 40, false, MEANINGFUL, CLEAR),
          EchoesAwarenessDecision::ACCEPT_CLEAR_UPGRADE);

    // 6. Fully attuned + a clear, role-critical upgrade (50% margin) ->
    //    still always accept - E2i1/E2i2 explicitly forbid absolute
    //    protection against a clearly superior upgrade.
    Check("fully_attuned_clear_role_critical_upgrade",
          EvaluateAwareness(true, 100.0f, 150.0f, 100, true, MEANINGFUL, CLEAR),
          EchoesAwarenessDecision::ACCEPT_CLEAR_UPGRADE);

    // 7. Cache/state unavailable -> always fall back, regardless of any
    //    other input (even a huge attunement value).
    Check("cache_unavailable_forces_fallback",
          EvaluateAwareness(false, 100.0f, 500.0f, 100, true, MEANINGFUL, CLEAR),
          EchoesAwarenessDecision::FALLBACK_STATE_UNAVAILABLE);

    // 8. Database-read-failure equivalent: same as (7), modeled the same
    //    way at this layer (the hook code maps a failed cache read to
    //    stateAvailable=false before ever calling this function).
    Check("db_read_failure_equivalent",
          EvaluateAwareness(false, 50.0f, 60.0f, 0, false, MEANINGFUL, CLEAR),
          EchoesAwarenessDecision::FALLBACK_STATE_UNAVAILABLE);

    // 9. Empty slot (no currently equipped item, score 0) -> nothing to
    //    protect, defer entirely even with high attunement values (which
    //    would be meaningless/impossible for an empty slot anyway).
    Check("empty_slot_no_current_item",
          EvaluateAwareness(true, 0.0f, 80.0f, 0, false, MEANINGFUL, CLEAR),
          EchoesAwarenessDecision::DEFAULT_PLAYERBOTS_DECISION);

    // 10. Exactly at the meaningful-attunement boundary (25%) + marginal
    //     upgrade -> boundary is inclusive, so this vetoes.
    Check("exactly_at_meaningful_boundary",
          EvaluateAwareness(true, 100.0f, 105.0f, 25, false, MEANINGFUL, CLEAR),
          EchoesAwarenessDecision::KEEP_ATTUNED_ITEM);

    // 11. Exactly at the clear-upgrade boundary (15% margin) on a fully
    //     attuned item -> boundary is inclusive toward accepting the
    //     upgrade (never worse than "block a clear upgrade").
    Check("exactly_at_clear_upgrade_boundary",
          EvaluateAwareness(true, 100.0f, 115.0f, 100, true, MEANINGFUL, CLEAR),
          EchoesAwarenessDecision::ACCEPT_CLEAR_UPGRADE);

    // 12. Downgrade candidate (negative margin) on a non-attuned item ->
    //     defer; Layer 1 never actively recommends anything, it only ever
    //     vetoes marginal-over-attuned replacements. A downgrade candidate
    //     reaching this function at all would already be unusual for
    //     Playerbots' own logic, but the policy must still behave sanely.
    Check("downgrade_candidate_non_attuned",
          EvaluateAwareness(true, 100.0f, 80.0f, 0, false, MEANINGFUL, CLEAR),
          EchoesAwarenessDecision::DEFAULT_PLAYERBOTS_DECISION);

    // 13. Downgrade candidate on a fully attuned item -> also defer at
    //     this layer (KEEP_ATTUNED_ITEM's veto only prevents *marginal
    //     upgrades*; a downgrade is not something Layer 1 forces a veto
    //     for, since Playerbots itself would not normally offer one).
    //     Documented as a known, deliberately narrow v1 scope boundary.
    Check("downgrade_candidate_fully_attuned",
          EvaluateAwareness(true, 100.0f, 80.0f, 100, true, MEANINGFUL, CLEAR),
          EchoesAwarenessDecision::KEEP_ATTUNED_ITEM);

    std::printf("\n%d/%d tests passed.\n", g_total - g_failures, g_total);
    if (g_failures > 0)
    {
        std::printf("SOME TESTS FAILED\n");
        return 1;
    }
    std::printf("ALL TESTS PASSED\n");
    return 0;
}
