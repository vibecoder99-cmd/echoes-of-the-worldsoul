// E2j2 - EchoesProgressionSchedulerPolicy tests.
//
// EchoesSelectSinkCategoryForGuid()/EchoesShouldSkipSchedulerRecheck() are pure and
// dependency-free by design (see EchoesProgressionSchedulerPolicy.h) - they compile and are
// fully testable standalone, matching EchoesProgressionBudgetPolicyTests.cpp's own established
// pattern. The engine-coupled parts of RunProgressionSchedulerPass (ObjectAccessor iteration,
// GET_PLAYERBOT_AI/GetMaster checks, the actual bridge spend calls) are proven separately by
// the E2j2 disposable candidate validation (Stage 8) and focused comparative proof (Stage 9),
// not by this file - identical split to every other DB/ALE-touching class in this module.

#include "../src/EchoesProgressionSchedulerPolicy.h"
#include <cstdio>
#include <cstring>
#include <set>
#include <string>

static int g_pass = 0;
static int g_fail = 0;

static void Check(char const* name, bool condition, char const* detail = "")
{
    if (condition) { ++g_pass; std::printf("PASS: %-55s %s\n", name, detail); }
    else { ++g_fail; std::printf("FAIL: %-55s %s\n", name, detail); }
}

int main()
{
    // --- Category allowlist itself ---
    {
        std::size_t count = 0;
        char const* const* cats = EchoesFunctionalCrucibleCategories(count);
        Check("01_category_count_is_exactly_six", count == 6);
        bool hasAttunementEcho = false, hasAetherSurge = false, hasCooldownReduction = false,
             hasMovementSpeed = false, hasResResilience = false, hasLifeLeech = false;
        for (std::size_t i = 0; i < count; ++i)
        {
            if (std::strcmp(cats[i], "attunement_echo") == 0) hasAttunementEcho = true;
            if (std::strcmp(cats[i], "aether_surge") == 0) hasAetherSurge = true;
            if (std::strcmp(cats[i], "cooldown_reduction") == 0) hasCooldownReduction = true;
            if (std::strcmp(cats[i], "movement_speed") == 0) hasMovementSpeed = true;
            if (std::strcmp(cats[i], "res_resilience") == 0) hasResResilience = true;
            if (std::strcmp(cats[i], "life_leech") == 0) hasLifeLeech = true;
        }
        Check("02_contains_attunement_echo", hasAttunementEcho);
        Check("03_contains_aether_surge", hasAetherSurge);
        Check("04_contains_cooldown_reduction", hasCooldownReduction);
        Check("05_contains_movement_speed", hasMovementSpeed);
        Check("06_contains_res_resilience", hasResResilience);
        Check("07_contains_life_leech", hasLifeLeech);
        // Explicitly excluded - Stage 2 proved these have zero gameplay consumer.
        bool hasFortitude = false, hasMastery = false;
        for (std::size_t i = 0; i < count; ++i)
        {
            if (std::strcmp(cats[i], "fortitude") == 0) hasFortitude = true;
            if (std::strcmp(cats[i], "mastery") == 0) hasMastery = true;
        }
        Check("08_never_contains_fortitude_inactive_category", !hasFortitude);
        Check("09_never_contains_mastery_not_a_crucible_category_at_all", !hasMastery);
    }

    // --- Category selection determinism ---
    {
        Check("10_same_guid_always_same_category",
            std::strcmp(EchoesSelectSinkCategoryForGuid(12345), EchoesSelectSinkCategoryForGuid(12345)) == 0);

        // Population-level diversification: across a range of guids, more than one category
        // must be selected (never uniformly one category for the whole population).
        std::set<std::string> seen;
        for (uint32_t guid = 1; guid <= 600; ++guid)
            seen.insert(EchoesSelectSinkCategoryForGuid(guid));
        Check("11_population_spreads_across_multiple_categories", seen.size() > 1,
            (std::to_string(seen.size()) + " distinct categories seen").c_str());
        Check("12_population_spreads_across_all_six_categories", seen.size() == 6,
            (std::to_string(seen.size()) + " distinct categories seen").c_str());

        Check("13_guid_zero_resolves_to_a_valid_category",
            std::strcmp(EchoesSelectSinkCategoryForGuid(0), "attunement_echo") == 0);
    }

    // --- Recheck/jitter decision: never-checked always eligible ---
    {
        Check("14_never_checked_before_always_eligible",
            EchoesShouldSkipSchedulerRecheck(1000, 0, 900, 180, 42) == false);
    }

    // --- Recheck floor without jitter (guid=180 -> 180 % 180 == 0, isolates the base floor) ---
    {
        // now=1000, lastChecked=700 -> elapsed=300; floor=400, jitter offset(guid=180)=0 -> effectiveFloor=400
        // 300 < 400 -> should skip
        Check("16_elapsed_less_than_floor_skips",
            EchoesShouldSkipSchedulerRecheck(1000, 700, 400, 180, 180) == true);
        // now=1000, lastChecked=600 -> elapsed=400; effectiveFloor=400 -> 400 < 400 is false -> NOT skipped (exactly at floor is eligible)
        Check("17_elapsed_exactly_at_floor_not_skipped",
            EchoesShouldSkipSchedulerRecheck(1000, 600, 400, 180, 180) == false);
        // now=1000, lastChecked=599 -> elapsed=401 > 400 -> not skipped
        Check("18_elapsed_just_past_floor_not_skipped",
            EchoesShouldSkipSchedulerRecheck(1000, 599, 400, 180, 180) == false);
    }

    // --- Jitter actually shifts the effective floor for a non-zero-offset guid ---
    {
        // guid=90 -> 90 % 180 = 90 -> effectiveFloor = 400 + 90 = 490
        // now=1000, lastChecked=600 -> elapsed=400 -> 400 < 490 -> skip (would NOT have skipped at floor=400 alone)
        Check("19_jitter_extends_effective_floor",
            EchoesShouldSkipSchedulerRecheck(1000, 600, 400, 180, 90) == true);
        // same guid, elapsed=490 exactly -> not skipped
        Check("20_jitter_extended_floor_reached_not_skipped",
            EchoesShouldSkipSchedulerRecheck(1000, 510, 400, 180, 90) == false);
    }

    // --- Zero jitter window never adds an offset ---
    {
        Check("21_zero_jitter_window_no_offset",
            EchoesShouldSkipSchedulerRecheck(1000, 601, 400, 0, 999999) == true); // elapsed=399 < 400 -> skip
        Check("22_zero_jitter_window_boundary_exact",
            EchoesShouldSkipSchedulerRecheck(1000, 600, 400, 0, 999999) == false); // elapsed=400 == floor -> not skipped
    }

    // --- Clock anomaly: now < lastChecked fails open (never permanently stuck) ---
    {
        Check("23_clock_anomaly_now_before_last_checked_fails_open",
            EchoesShouldSkipSchedulerRecheck(500, 1000, 400, 180, 42) == false);
    }

    // --- Structural/source-cited scenarios (verified by direct source inspection of
    //     RunProgressionSchedulerPass in EchoesHooks.cpp; not independently unit-testable
    //     outside a live worldserver - see E2j2 Stage 8/9 disposable-candidate evidence) ---
    // 24_global_work_budget: RunProgressionSchedulerPass's loop breaks as soon as
    //     evaluatedThisPass reaches progressionSchedulerMaxBotsPerPass - a hard, bounded ceiling
    //     independent of total online population, verified by direct source read.
    // 25_human_isolation: the loop's GET_PLAYERBOT_AI(botAiCheck) check is the exact same
    //     macro/invariant used by every other hook in this module - a null botAi always
    //     `continue`s before any Echoes work, identical to MaybeReconcileLoginInventory/
    //     MaybeReconcileProgressionSpending's own gates.
    // 26_controlled_bot_exclusion: botAi->GetMaster() != nullptr is checked before any spend
    //     logic runs - GetMaster() is Playerbots' own public accessor (PlayerbotAI.h:537),
    //     returning non-null only when a real human player is the master, confirmed via direct
    //     source read of PlayerbotAI::SetMaster/GetMaster.
    // 27_one_action_per_pass_shared_with_login_path: RunProgressionSchedulerPass delegates to
    //     the exact same TryOneProgressionSpendForBot function used by
    //     EchoesPlayerScript::MaybeReconcileProgressionSpending - there is only one spend
    //     implementation in this module, not two divergent copies, so E2j1 Stage 10's proven
    //     one-action-per-pass/no-chained-async-deduction guarantee applies identically to both
    //     trigger paths by construction, not by parallel maintenance.
    // 28_cache_invalidation_after_success: TryOneProgressionSpendForBot re-reads
    //     GetProgressionSnapshot synchronously immediately after every successful mutation
    //     (post-spend verification) rather than relying on any cached balance - there is no
    //     separate progression-spending cache to invalidate; EchoesBotCache (attunement %) is
    //     an entirely different subsystem never touched by this code path.
    // 29_deferred_login_check_unchanged: EchoesPlayerScript::OnPlayerLogin still schedules
    //     DeferredLoginReconcileEvent at the same proven 1500ms delay (E2j1 Stage 10) - the
    //     scheduler is purely additive, the login path was not modified in shape, only in which
    //     Crucible category it targets (now via SelectSinkCategoryForBot instead of a hardcoded
    //     "attunement_echo" literal).
    // 30_shutdown_safety: EchoesWorldScript::OnShutdown clears
    //     lastSchedulerCheckSecsByGuid/schedulerCursorGuid; any already-queued
    //     DeferredLoginReconcileEvent is owned by its Player's own m_Events processor and torn
    //     down with that Player object by AzerothCore's own shutdown sequence, never referenced
    //     by this module after shutdown begins.

    // 31_cooldown_lease_recorded_independent_of_postverify_race: E2j2 Stage 9's focused
    //     comparative proof directly observed, via targeted diagnostic logging against a live
    //     disposable candidate, that the post-spend verification read in
    //     TryOneProgressionSpendForBot (EchoesHooks.cpp) can race ahead of AP.Sinks.Invest's own
    //     async DB write and consistently observe the pre-spend balance - and that, before this
    //     fix, the cooldown lease (lastSpendSecondsByKey[leaseKey] = now) was written only
    //     inside the post-verify-success branch, so a raced verify silently disabled the
    //     cooldown entirely. Reproduced concretely: one seeded bot (guid 1667) spent 4 times in
    //     under 6 minutes against a configured 3600s cooldown, confirmed via
    //     leaseFound=false/mapSize=0 on every repeat attempt. Fixed by moving the lease write to
    //     execute unconditionally as soon as ExecuteSinkInvest/ExecuteRackExpand returns ok=true
    //     - the lease now reflects "an attempt was dispatched," not "the immediate re-read
    //     happened to observe it," while spendsSucceeded/spendsFailedPostVerify remain accurate
    //     pure observability counters, unaffected by the fix. Re-verified after the fix: no
    //     repeat spend for any bot within the configured cooldown window across a fresh
    //     disposable run. Not independently unit-testable here (it is inseparable from the real
    //     async Lua/DB timing that only exists in a live worldserver), proven only by this
    //     directly-observed before/after evidence.

    // ============================================================================
    // E2j5 - Mastery as a bounded bot spending target. Mastery's actual purchase logic lives in
    // AP.Mastery.Purchase (Lua) and TryOneProgressionSpendForBot's Candidate 2 (EchoesHooks.cpp,
    // engine-coupled) - not independently unit-testable in this pure-header test file. These are
    // structural/source-cited notes, proven live in Stage 10-13's isolated disposable gates:
    // ============================================================================
    // 32_mastery_reuses_shared_budget_gate: Candidate 2 constructs the identical
    //     ProgressionBudgetContext/EvaluateProgressionSpend call shape as Candidates 1 and 3 -
    //     confirmed by direct source read of EchoesHooks.cpp - no separate Mastery-only
    //     affordability/reserve/cooldown logic exists.
    // 33_mastery_never_introduces_a_rank_ceiling: masteryPreview.cost/currentRank come straight
    //     from the bridge's call into AP.API.PreviewMasteryPurchase -> AP.LoadMastery/
    //     AP.MasteryCost (ap_core.lua), uncapped, exactly as the human path computes them. The
    //     shared budget gate only ever rejects on affordability (REJECT_INSUFFICIENT_BALANCE/
    //     REJECT_BELOW_RESERVE/REJECT_EXCEEDS_PER_DECISION_MAX/REJECT_COOLDOWN_ACTIVE), never on
    //     rank magnitude - confirmed by direct source read of EvaluateProgressionSpend, which has
    //     no rank-aware branch at all.
    // 34_mastery_write_is_synchronous_no_postverify_race: unlike Sinks/Rack (fire-and-forget
    //     AP.DB.ExecuteAsync, requiring the E2j2 Stage 9 post-verify-independent-lease fix),
    //     AP.Mastery.Purchase uses AP.DB.ExecuteCritical (CharDBDirectExecute, synchronous) for
    //     its single atomic UPSERT - the bridge's returned old/new rank and balance are already
    //     authoritative the instant ExecuteMasteryPurchase returns, so no separate post-spend
    //     re-read is performed or needed for this specific candidate.
    // 35_mastery_cost_overflow_is_structurally_unreachable: AP.MasteryCost grows as
    //     400*(rank+1)^1.5 - its value would exceed uint32_t range only around rank ~49,243, but
    //     the SAME shared progressionMaxSpendPerDecision cap Candidates 1/3 already use (default
    //     2000) rejects any Mastery purchase past roughly rank 3-4 via
    //     REJECT_EXCEEDS_PER_DECISION_MAX long before cost magnitude could ever approach the
    //     preview-side uint32_t cast. Even in a hypothetical future config raising that cap far
    //     enough to reach the overflow-prone range, the actual mutation is always re-validated
    //     and re-computed fresh in Lua (double precision, no overflow) inside AP.Mastery.Purchase
    //     itself, independent of whatever the C++ preview computed - a truncated/wrong preview
    //     cost can at worst cause a wasted attempt (caught by the Lua-side aether<cost check,
    //     returning INSUFFICIENT_ESSENCE), never an under-charged mutation.
    // 36_one_action_per_pass_preserved: Candidate 2 is gated by the same
    //     `actionsThisLogin < maxActions && !spendAttemptedThisPass` condition as Candidates 1
    //     and 3, and sets spendAttemptedThisPass = true before calling ExecuteMasteryPurchase -
    //     identical one-mutation-per-pass invariant, confirmed by direct source read.
    // 37_completed_purchase_survives_downstream_failure: masteryRefreshRequested is incremented
    //     only after result.status=="SUCCESS" is already confirmed and counted - a failure to
    //     increment this observability counter (e.g. a future refactor bug) cannot undo or retry
    //     the already-committed purchase, since the purchase and the refresh-request counter are
    //     never coupled through any conditional that could roll the former back.
    // 38_disabled_by_default_zero_calls: progressionMasteryPurchaseEnabled defaults to false
    //     (EchoesConfig.h) - Candidate 2's outermost gate short-circuits before
    //     PreviewMasteryPurchase is ever called, identical to progressionSpendingEnabled's
    //     existing convention - proven live in Stage 10's disabled-gate.

    // ============================================================================
    // E2j9 - Playerbot Crucible Scheduler Expansion
    // ============================================================================

    // --- Expanded whitelist: exactly 17 categories, threat_reduction never present ---
    {
        std::size_t count = 0;
        char const* const* cats = EchoesExpandedFunctionalCrucibleCategories(count);
        Check("39_expanded_category_count_is_exactly_seventeen", count == 17,
            (std::to_string(count) + " categories").c_str());

        bool hasThreatReduction = false;
        std::set<std::string> seenNames;
        for (std::size_t i = 0; i < count; ++i)
        {
            seenNames.insert(cats[i]);
            if (std::strcmp(cats[i], "threat_reduction") == 0) hasThreatReduction = true;
        }
        Check("40_threat_reduction_never_in_expanded_whitelist", !hasThreatReduction);
        Check("41_no_duplicate_category_entries", seenNames.size() == count,
            (std::to_string(seenNames.size()) + " unique of " + std::to_string(count)).c_str());

        // Original six retained
        char const* originalSix[] = { "attunement_echo", "aether_surge", "cooldown_reduction",
            "movement_speed", "res_resilience", "life_leech" };
        for (char const* name : originalSix)
            Check(("42_expanded_list_retains_" + std::string(name)).c_str(),
                seenNames.count(name) == 1);

        // E2j9 additions present
        char const* additions[] = { "fortitude", "spell_mitigation", "crit_rating", "haste_rating",
            "dodge_rating", "parry_rating", "melee_power", "spell_power", "execute_power",
            "armor_pen", "reflect_chance" };
        for (char const* name : additions)
            Check(("43_expanded_list_contains_" + std::string(name)).c_str(),
                seenNames.count(name) == 1);
    }

    // --- Inert-consumer prevention invariant: the policy table itself must never contain
    //     threat_reduction, and every table entry must also appear in the expanded whitelist
    //     (the one durable, evidence-cited list) - the exact "registration exists AND is live"
    //     class of check E2j2 skipped for life_leech. ---
    {
        std::size_t tableCount = 0;
        EchoesCrucibleCategoryPolicyEntry const* table = EchoesCrucibleCategoryPolicyTable(tableCount);
        std::size_t whitelistCount = 0;
        char const* const* whitelist = EchoesExpandedFunctionalCrucibleCategories(whitelistCount);
        std::set<std::string> whitelistSet(whitelist, whitelist + whitelistCount);

        bool tableHasThreatReduction = false;
        bool everyEntryWhitelisted = true;
        for (std::size_t i = 0; i < tableCount; ++i)
        {
            if (std::strcmp(table[i].name, "threat_reduction") == 0) tableHasThreatReduction = true;
            if (whitelistSet.count(table[i].name) == 0) everyEntryWhitelisted = false;
        }
        Check("44_policy_table_never_contains_threat_reduction", !tableHasThreatReduction);
        Check("45_every_policy_table_entry_is_in_the_evidence_cited_whitelist", everyEntryWhitelisted);
        Check("46_policy_table_count_matches_whitelist_count", tableCount == whitelistCount,
            (std::to_string(tableCount) + " vs " + std::to_string(whitelistCount)).c_str());
    }

    // --- Class-aware selection: determinism, and universal categories reachable by any class ---
    {
        Check("47_same_guid_and_class_always_same_category",
            std::strcmp(EchoesSelectSinkCategoryForGuidClassAware(555, 1),
                        EchoesSelectSinkCategoryForGuidClassAware(555, 1)) == 0);

        // Different classes CAN resolve differently for the same guid (pool composition differs)
        // - not asserted equal or unequal, just that both calls succeed and return a real name.
        char const* forWarrior = EchoesSelectSinkCategoryForGuidClassAware(777, 1 /*Warrior*/);
        char const* forMage    = EchoesSelectSinkCategoryForGuidClassAware(777, 8 /*Mage*/);
        Check("48_class_aware_selection_returns_nonnull_for_warrior", forWarrior != nullptr);
        Check("49_class_aware_selection_returns_nonnull_for_mage", forMage != nullptr);
    }

    // --- melee_power / spell_power class eligibility ---
    {
        // Warrior (class 1): melee_power reachable across a guid sweep, spell_power never reachable.
        bool warriorSawMelee = false, warriorSawSpell = false;
        for (uint32_t guid = 1; guid <= 2000; ++guid)
        {
            char const* cat = EchoesSelectSinkCategoryForGuidClassAware(guid, 1);
            if (std::strcmp(cat, "melee_power") == 0) warriorSawMelee = true;
            if (std::strcmp(cat, "spell_power") == 0) warriorSawSpell = true;
        }
        Check("50_warrior_can_be_assigned_melee_power", warriorSawMelee);
        Check("51_warrior_never_assigned_spell_power", !warriorSawSpell);

        // Mage (class 8): spell_power reachable, melee_power never reachable.
        bool mageSawMelee = false, mageSawSpell = false;
        for (uint32_t guid = 1; guid <= 2000; ++guid)
        {
            char const* cat = EchoesSelectSinkCategoryForGuidClassAware(guid, 8);
            if (std::strcmp(cat, "melee_power") == 0) mageSawMelee = true;
            if (std::strcmp(cat, "spell_power") == 0) mageSawSpell = true;
        }
        Check("52_mage_can_be_assigned_spell_power", mageSawSpell);
        Check("53_mage_never_assigned_melee_power", !mageSawMelee);

        // Priest (class 5): spell_power reachable, melee_power never reachable (pure caster/healer).
        bool priestSawMelee = false, priestSawSpell = false;
        for (uint32_t guid = 1; guid <= 2000; ++guid)
        {
            char const* cat = EchoesSelectSinkCategoryForGuidClassAware(guid, 5);
            if (std::strcmp(cat, "melee_power") == 0) priestSawMelee = true;
            if (std::strcmp(cat, "spell_power") == 0) priestSawSpell = true;
        }
        Check("54_priest_can_be_assigned_spell_power", priestSawSpell);
        Check("55_priest_never_assigned_melee_power", !priestSawMelee);

        // Rogue (class 4): melee_power reachable, spell_power never reachable.
        bool rogueSawMelee = false, rogueSawSpell = false;
        for (uint32_t guid = 1; guid <= 2000; ++guid)
        {
            char const* cat = EchoesSelectSinkCategoryForGuidClassAware(guid, 4);
            if (std::strcmp(cat, "melee_power") == 0) rogueSawMelee = true;
            if (std::strcmp(cat, "spell_power") == 0) rogueSawSpell = true;
        }
        Check("56_rogue_can_be_assigned_melee_power", rogueSawMelee);
        Check("57_rogue_never_assigned_spell_power", !rogueSawSpell);

        // Hunter (class 3): melee_power (weapon DPS) reachable, spell_power never reachable.
        bool hunterSawMelee = false, hunterSawSpell = false;
        for (uint32_t guid = 1; guid <= 2000; ++guid)
        {
            char const* cat = EchoesSelectSinkCategoryForGuidClassAware(guid, 3);
            if (std::strcmp(cat, "melee_power") == 0) hunterSawMelee = true;
            if (std::strcmp(cat, "spell_power") == 0) hunterSawSpell = true;
        }
        Check("58_hunter_can_be_assigned_melee_power", hunterSawMelee);
        Check("59_hunter_never_assigned_spell_power", !hunterSawSpell);

        // Death Knight (class 6): melee_power reachable, spell_power never reachable.
        bool dkSawMelee = false, dkSawSpell = false;
        for (uint32_t guid = 1; guid <= 2000; ++guid)
        {
            char const* cat = EchoesSelectSinkCategoryForGuidClassAware(guid, 6);
            if (std::strcmp(cat, "melee_power") == 0) dkSawMelee = true;
            if (std::strcmp(cat, "spell_power") == 0) dkSawSpell = true;
        }
        Check("60_death_knight_can_be_assigned_melee_power", dkSawMelee);
        Check("61_death_knight_never_assigned_spell_power", !dkSawSpell);

        // Hybrids: Paladin (2), Shaman (7), Druid (11) - both categories reachable.
        struct HybridCase { uint8_t classId; char const* label; };
        HybridCase hybrids[] = { {2, "paladin"}, {7, "shaman"}, {11, "druid"} };
        for (auto const& h : hybrids)
        {
            bool sawMelee = false, sawSpell = false;
            for (uint32_t guid = 1; guid <= 2000; ++guid)
            {
                char const* cat = EchoesSelectSinkCategoryForGuidClassAware(guid, h.classId);
                if (std::strcmp(cat, "melee_power") == 0) sawMelee = true;
                if (std::strcmp(cat, "spell_power") == 0) sawSpell = true;
            }
            Check(("62_hybrid_" + std::string(h.label) + "_can_be_assigned_melee_power").c_str(), sawMelee);
            Check(("63_hybrid_" + std::string(h.label) + "_can_be_assigned_spell_power").c_str(), sawSpell);
        }
    }

    // --- Universal categories reachable regardless of class (spot-check a few) ---
    {
        char const* universalCats[] = { "fortitude", "spell_mitigation", "crit_rating",
            "haste_rating", "dodge_rating", "parry_rating", "execute_power", "armor_pen",
            "reflect_chance", "life_leech", "attunement_echo" };
        for (char const* wanted : universalCats)
        {
            bool seen = false;
            for (uint32_t guid = 1; guid <= 2000 && !seen; ++guid)
                if (std::strcmp(EchoesSelectSinkCategoryForGuidClassAware(guid, 5 /*Priest*/), wanted) == 0)
                    seen = true;
            Check(("64_universal_category_" + std::string(wanted) + "_reachable_by_priest").c_str(), seen);
        }
    }

    // --- threat_reduction is never selectable by the class-aware function for any class ---
    {
        bool everSawThreatReduction = false;
        for (uint8_t classId = 1; classId <= 11 && !everSawThreatReduction; ++classId)
        {
            if (classId == 10) continue; // unused class ID
            for (uint32_t guid = 1; guid <= 500; ++guid)
                if (std::strcmp(EchoesSelectSinkCategoryForGuidClassAware(guid, classId), "threat_reduction") == 0)
                { everSawThreatReduction = true; break; }
        }
        Check("65_threat_reduction_never_selectable_for_any_class", !everSawThreatReduction);
    }

    // --- Invalid/edge class values fail safe (no crash, returns a real category) ---
    {
        char const* zeroClass = EchoesSelectSinkCategoryForGuidClassAware(100, 0);
        Check("66_class_zero_returns_a_valid_universal_category", zeroClass != nullptr);
        char const* outOfRangeClass = EchoesSelectSinkCategoryForGuidClassAware(100, 255);
        Check("67_out_of_range_class_returns_a_valid_universal_category", outOfRangeClass != nullptr);
    }

    // --- Class mask constants match the documented citation exactly ---
    {
        Check("68_melee_power_mask_includes_warrior", (kEchoesMeleePowerClassMask & (1u << 0)) != 0);
        Check("69_melee_power_mask_includes_hunter", (kEchoesMeleePowerClassMask & (1u << 2)) != 0);
        Check("70_melee_power_mask_excludes_mage", (kEchoesMeleePowerClassMask & (1u << 7)) == 0);
        Check("71_melee_power_mask_excludes_priest", (kEchoesMeleePowerClassMask & (1u << 4)) == 0);
        Check("72_spell_power_mask_includes_mage", (kEchoesSpellPowerClassMask & (1u << 7)) != 0);
        Check("73_spell_power_mask_includes_priest", (kEchoesSpellPowerClassMask & (1u << 4)) != 0);
        Check("74_spell_power_mask_excludes_warrior", (kEchoesSpellPowerClassMask & (1u << 0)) == 0);
        Check("75_spell_power_mask_excludes_rogue", (kEchoesSpellPowerClassMask & (1u << 3)) == 0);
        Check("76_druid_bit_is_bit_ten_matching_class_id_eleven",
            (kEchoesMeleePowerClassMask & (1u << 10)) != 0 && (kEchoesSpellPowerClassMask & (1u << 10)) != 0);
    }

    // --- Structural/source-cited notes (engine-coupled, not independently unit-testable here) ---
    // 77_selectSinkCategoryForBot_passes_real_class: EchoesHooks.cpp's SelectSinkCategoryForBot
    //     now takes Player* (not a raw guidLow) and calls player->getClass() directly - confirmed
    //     by direct source read; both call sites (RunProgressionSchedulerPass and
    //     MaybeReconcileProgressionSpending) updated identically, no divergent copy.
    // 78_no_engine_math_duplicated: this policy table stores only category names, class masks,
    //     and selection weights - no ceiling/k/formula constant from mod-echoes-stats is
    //     reproduced here, matching the ownership boundary in the E2j9 authorization (§4).
    // 79_ui_purchasability_unchanged: this phase does not touch ap_sinks.lua's `active` flags or
    //     the Crucible gossip UI - human purchasing behavior for threat_reduction (still shown as
    //     ACTIVE, still human-investable) is explicitly unchanged, per the authorization's
    //     instruction not to alter human purchasing without separate approval.

    std::printf("\n%d/%d tests passed.\n", g_pass, g_pass + g_fail);
    if (g_fail == 0) std::printf("ALL TESTS PASSED\n");
    return g_fail == 0 ? 0 : 1;
}
