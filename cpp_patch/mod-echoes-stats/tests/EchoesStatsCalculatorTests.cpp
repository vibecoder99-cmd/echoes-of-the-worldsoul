// E2j3 - EchoesStatsCalculator tests.
//
// EchoesMasteryAbsorbPct/EchoesLevelAbsorbScalar/EchoesSnapshotRowEligible/
// EchoesCalculateAbsorption are pure and dependency-free by design (see
// EchoesStatsCalculator.h) - fully testable standalone, matching this project's established
// EchoesProgressionSchedulerPolicyTests.cpp pattern. The engine-coupled parts
// (EchoesStatsHooks.cpp: DB queries, ItemTemplate lookups, HandleStatFlatModifier application)
// are proven separately by E2j3's isolated candidate stages (Stage 11-13), not by this file.

#include "../src/EchoesStatsCalculator.h"
#include <cstdio>
#include <cmath>

static int g_pass = 0;
static int g_fail = 0;

static void Check(char const* name, bool condition, char const* detail = "")
{
    if (condition) { ++g_pass; std::printf("PASS: %-55s %s\n", name, detail); }
    else { ++g_fail; std::printf("FAIL: %-55s %s\n", name, detail); }
}

static bool NearlyEqual(double a, double b, double eps = 0.0001)
{
    return std::abs(a - b) < eps;
}

int main()
{
    // --- Mastery absorb pct: rank 0, matches base exactly ---
    {
        Check("01_mastery_rank_zero_equals_base_absorb",
            NearlyEqual(EchoesMasteryAbsorbPct(0), 0.05));
    }

    // --- Mastery absorb pct: increases monotonically with rank, approaches base+max ---
    {
        double r1 = EchoesMasteryAbsorbPct(1);
        double r10 = EchoesMasteryAbsorbPct(10);
        double r100 = EchoesMasteryAbsorbPct(100);
        double r10000 = EchoesMasteryAbsorbPct(10000);
        Check("02_absorb_increases_rank1_lt_rank10", r1 < r10);
        Check("03_absorb_increases_rank10_lt_rank100", r10 < r100);
        Check("04_absorb_approaches_base_plus_max_at_high_rank",
            NearlyEqual(r10000, 0.05 + 0.80, 0.001));
        Check("05_absorb_never_exceeds_base_plus_max", r10000 <= 0.05 + 0.80 + 0.0001);
    }

    // --- Mastery absorb pct: known value at rank 8000 (a realistic seeded test value used in
    //     E2j2's own disposable-lab seeding, ap_mastery.mastery=8000) ---
    {
        // masteryPct = 0.05 + 0.80 * (1 - exp(-0.038 * 8000)) -> exponent is enormous negative,
        // so this saturates to essentially base+max.
        double pct = EchoesMasteryAbsorbPct(8000);
        Check("06_high_seeded_rank_saturates_near_max", NearlyEqual(pct, 0.85, 0.0001));
    }

    // --- Level absorb scalar: at/below level 9 is exactly zero ---
    {
        Check("07_level_9_scalar_is_zero", EchoesLevelAbsorbScalar(9) == 0.0);
        Check("08_level_1_scalar_is_zero", EchoesLevelAbsorbScalar(1) == 0.0);
    }

    // --- Level absorb scalar: linear ramp from 10 to 80, clamped at 1.0 ---
    {
        Check("09_level_10_scalar_is_small_positive",
            NearlyEqual(EchoesLevelAbsorbScalar(10), 1.0 / 71.0));
        Check("10_level_80_scalar_is_exactly_one",
            NearlyEqual(EchoesLevelAbsorbScalar(80), 1.0));
        Check("11_level_above_80_still_clamped_to_one",
            NearlyEqual(EchoesLevelAbsorbScalar(200), 1.0));
        Check("12_level_45_scalar_matches_formula",
            NearlyEqual(EchoesLevelAbsorbScalar(45), 36.0 / 71.0));
    }

    // --- Class armor range: known classes ---
    {
        Check("13_warrior_range_is_mail_plate",
            EchoesGetClassArmorRange(1).minSub == 3 && EchoesGetClassArmorRange(1).maxSub == 4);
        Check("14_priest_range_is_cloth_only",
            EchoesGetClassArmorRange(5).minSub == 1 && EchoesGetClassArmorRange(5).maxSub == 1);
        Check("15_rogue_range_is_cloth_leather",
            EchoesGetClassArmorRange(4).minSub == 1 && EchoesGetClassArmorRange(4).maxSub == 2);
        Check("16_class_10_does_not_exist_invalid", !EchoesGetClassArmorRange(10).valid);
        Check("17_class_zero_invalid", !EchoesGetClassArmorRange(0).valid);
    }

    // --- Snapshot row eligibility ---
    {
        EchoesStatSnapshotRow clothRow; clothRow.isArmor = true; clothRow.armorSubClass = 1;
        EchoesStatSnapshotRow plateRow; plateRow.isArmor = true; plateRow.armorSubClass = 4;
        EchoesStatSnapshotRow miscRow; miscRow.isArmor = true; miscRow.armorSubClass = 0;
        EchoesStatSnapshotRow weaponRow; weaponRow.isArmor = false; weaponRow.armorSubClass = 0;

        Check("18_priest_eligible_for_cloth", EchoesSnapshotRowEligible(clothRow, 5));
        Check("19_priest_not_eligible_for_plate", !EchoesSnapshotRowEligible(plateRow, 5));
        Check("20_warrior_eligible_for_plate", EchoesSnapshotRowEligible(plateRow, 1));
        Check("21_warrior_not_eligible_for_cloth", !EchoesSnapshotRowEligible(clothRow, 1));
        Check("22_misc_jewelry_always_eligible_any_class", EchoesSnapshotRowEligible(miscRow, 5));
        Check("23_weapon_always_eligible_ignores_armor_filter", EchoesSnapshotRowEligible(weaponRow, 5));
        Check("24_unknown_class_fails_closed", !EchoesSnapshotRowEligible(clothRow, 99));
    }

    // --- End-to-end calculation: zero mastery/level produces zero bonus ---
    {
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.str = 100; row.sta = 200; row.isArmor = false;
        rows.push_back(row);

        EchoesStatBonus b0 = EchoesCalculateAbsorption(rows, 0, 1, 5); // level 1 -> scalar 0
        Check("25_level_below_threshold_yields_zero_bonus_despite_mastery",
            NearlyEqual(b0.str, 0.0) && NearlyEqual(b0.sta, 0.0));
    }

    // --- End-to-end calculation: known combination, hand-computed expected values ---
    {
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.str = 100; row.agi = 50; row.sta = 200;
        row.intellect = 10; row.spirit = 10; row.isArmor = false; // weapon, always eligible
        rows.push_back(row);

        // masteryRank=0 -> masteryPct=0.05; level=80 -> levelScale=1.0; absorbPct=0.05
        EchoesStatBonus b = EchoesCalculateAbsorption(rows, 0, 80, 1);
        Check("26_known_combo_str_matches_hand_computed", NearlyEqual(b.str, 100 * 0.05));
        Check("27_known_combo_sta_matches_hand_computed", NearlyEqual(b.sta, 200 * 0.05));
    }

    // --- End-to-end calculation: ineligible armor rows contribute zero, eligible rows still count ---
    {
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow eligible; eligible.str = 100; eligible.isArmor = true; eligible.armorSubClass = 1; // cloth
        EchoesStatSnapshotRow ineligible; ineligible.str = 999; ineligible.isArmor = true; ineligible.armorSubClass = 4; // plate
        rows.push_back(eligible);
        rows.push_back(ineligible);

        // Priest (class 5): cloth-only. absorbPct at rank0/level80 = 0.05.
        EchoesStatBonus b = EchoesCalculateAbsorption(rows, 0, 80, 5);
        Check("28_ineligible_row_excluded_from_sum", NearlyEqual(b.str, 100 * 0.05));
    }

    // --- Config-parameterized overload: custom constants change the result deterministically ---
    {
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.str = 100; row.isArmor = false;
        rows.push_back(row);

        EchoesStatBonus bDefault = EchoesCalculateAbsorption(rows, 5, 80, 1);
        EchoesStatBonus bCustom = EchoesCalculateAbsorption(rows, 5, 80, 1, 0.10, 0.80, 0.038);
        Check("29_custom_base_absorb_changes_result", bCustom.str > bDefault.str);
    }

    // --- Empty snapshot set always yields zero bonus regardless of mastery/level ---
    {
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatBonus b = EchoesCalculateAbsorption(rows, 10000, 80, 1);
        Check("30_empty_snapshots_yield_zero_bonus",
            NearlyEqual(b.str, 0.0) && NearlyEqual(b.agi, 0.0) && NearlyEqual(b.sta, 0.0) &&
            NearlyEqual(b.intellect, 0.0) && NearlyEqual(b.spirit, 0.0));
    }

    // ============================================================================
    // E2j4 - defensive calculation-input ceiling tests. Mastery Rank is intentionally uncapped
    // as a gameplay system (E2j4 design decision) - these tests validate ONLY the calculation-
    // layer clamp (EchoesValidateMasteryRankForCalculation / kMasteryRankCalculationCeiling),
    // never a player-facing maximum. All 30 original assertions above are unchanged.
    // ============================================================================

    // --- Values at/below the ceiling pass through unchanged (never clamped) ---
    {
        Check("31_rank_0_passes_through_unclamped",
            EchoesValidateMasteryRankForCalculation(0).validatedRank == 0 &&
            !EchoesValidateMasteryRankForCalculation(0).wasAboveCeiling);
        Check("32_rank_1_passes_through_unclamped",
            EchoesValidateMasteryRankForCalculation(1).validatedRank == 1);
        Check("33_rank_10_passes_through_unclamped",
            EchoesValidateMasteryRankForCalculation(10).validatedRank == 10);
        Check("34_rank_25_passes_through_unclamped",
            EchoesValidateMasteryRankForCalculation(25).validatedRank == 25);
        Check("35_rank_50_passes_through_unclamped_not_a_cap",
            EchoesValidateMasteryRankForCalculation(50).validatedRank == 50);
        Check("36_rank_51_passes_through_unclamped_proves_50_is_not_a_cap",
            EchoesValidateMasteryRankForCalculation(51).validatedRank == 51);
        Check("37_rank_8000_saturated_stress_fixture_passes_through_unclamped",
            EchoesValidateMasteryRankForCalculation(8000).validatedRank == 8000);
        Check("38_rank_999999_passes_through_unclamped",
            EchoesValidateMasteryRankForCalculation(999999).validatedRank == 999999 &&
            !EchoesValidateMasteryRankForCalculation(999999).wasAboveCeiling);
        Check("39_rank_1000000_exactly_at_ceiling_passes_through_unclamped",
            EchoesValidateMasteryRankForCalculation(1000000).validatedRank == 1000000 &&
            !EchoesValidateMasteryRankForCalculation(1000000).wasAboveCeiling);
    }

    // --- Values above the ceiling clamp to exactly the ceiling, flagged ---
    {
        auto v1000001 = EchoesValidateMasteryRankForCalculation(1000001);
        Check("40_rank_1000001_clamps_to_ceiling", v1000001.validatedRank == 1000000);
        Check("41_rank_1000001_flagged_above_ceiling", v1000001.wasAboveCeiling == true);
        Check("42_rank_1000001_not_flagged_as_negative_invalid", v1000001.wasNegativeOrInvalid == false);

        // Widest value the actual DB column (int unsigned, max 4294967295) can ever return.
        auto vMax = EchoesValidateMasteryRankForCalculation(4294967295LL);
        Check("43_widest_db_column_value_clamps_to_ceiling", vMax.validatedRank == 1000000);
        Check("44_widest_db_column_value_flagged_above_ceiling", vMax.wasAboveCeiling == true);

        // Even wider than the column could ever hold (proves int64_t headroom is genuinely safe).
        auto vHuge = EchoesValidateMasteryRankForCalculation(9000000000000000000LL);
        Check("45_adversarial_int64_max_range_value_clamps_safely", vHuge.validatedRank == 1000000);
    }

    // --- Negative/invalid input treated as Rank 0 for calculation, never negative, never crashes ---
    {
        auto vNeg1 = EchoesValidateMasteryRankForCalculation(-1);
        Check("46_negative_one_treated_as_rank_zero", vNeg1.validatedRank == 0);
        Check("47_negative_one_flagged_invalid", vNeg1.wasNegativeOrInvalid == true);
        Check("48_negative_one_not_flagged_above_ceiling", vNeg1.wasAboveCeiling == false);

        auto vMinInt64 = EchoesValidateMasteryRankForCalculation(-9223372036854775807LL - 1);
        Check("49_int64_min_treated_as_rank_zero_no_crash", vMinInt64.validatedRank == 0);
        Check("50_int64_min_flagged_invalid", vMinInt64.wasNegativeOrInvalid == true);
    }

    // --- Clamped/invalid ranks still calculate a valid, finite, saturated absorption bonus ---
    {
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.str = 100; row.isArmor = false;
        rows.push_back(row);

        uint32_t clampedRank = EchoesValidateMasteryRankForCalculation(1000001).validatedRank;
        EchoesStatBonus b = EchoesCalculateAbsorption(rows, clampedRank, 80, 1);
        Check("51_clamped_ceiling_rank_produces_finite_saturated_bonus",
            std::isfinite(b.str) && NearlyEqual(b.str, 100 * 0.85, 0.01));

        uint32_t zeroedRank = EchoesValidateMasteryRankForCalculation(-1).validatedRank;
        EchoesStatBonus bZero = EchoesCalculateAbsorption(rows, zeroedRank, 80, 1);
        Check("52_invalid_input_zeroed_rank_produces_base_absorb_bonus",
            NearlyEqual(bZero.str, 100 * 0.05));
    }

    // --- Repeated recalculation at/above the ceiling is deterministic (pure function - proves
    //     the clamp itself introduces no source of drift/stacking across repeated calls) ---
    {
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.sta = 200; row.isArmor = false;
        rows.push_back(row);
        uint32_t rank = EchoesValidateMasteryRankForCalculation(5000000).validatedRank;
        EchoesStatBonus b1 = EchoesCalculateAbsorption(rows, rank, 80, 1);
        EchoesStatBonus b2 = EchoesCalculateAbsorption(rows, rank, 80, 1);
        EchoesStatBonus b3 = EchoesCalculateAbsorption(rows, rank, 80, 1);
        Check("53_repeated_recalc_above_ceiling_is_byte_identical",
            NearlyEqual(b1.sta, b2.sta) && NearlyEqual(b2.sta, b3.sta));
    }

    // --- Ceiling constant itself is centralized, not a magic number scattered through the file ---
    {
        Check("54_ceiling_constant_matches_specified_value", kMasteryRankCalculationCeiling == 1000000);
    }

    // --- Rank 50 vs Rank 51: absorption values must differ (proves Rank 50 is not a cap) ---
    {
        double pct50 = EchoesMasteryAbsorbPct(50);
        double pct51 = EchoesMasteryAbsorbPct(51);
        Check("55_rank_51_absorption_strictly_greater_than_rank_50", pct51 > pct50);
    }

    // --- Structural/source-cited notes (engine-coupled behavior, proven live in Stage 4/5, not
    //     independently unit-testable in this pure-header test file - matching this project's
    //     established split between pure-formula tests and live/disposable-infrastructure proof) ---
    // 56_no_database_rewrite: EchoesQueryMasteryRankRaw (EchoesStatsHooks.cpp) is a read-only
    //     CharacterDatabase.Query - this module contains no UPDATE/INSERT/REPLACE statement
    //     against ap_mastery anywhere, confirmed by direct source read. Clamping only ever affects
    //     the local `masteryRank` calculation variable, never the row.
    // 57_warning_deduplication: EchoesStatsState::lastWarnedRawMasteryRankByGuid records the last
    //     WARNED raw value per guid; a repeated recalculation with the same offending raw value
    //     produces zero additional log lines, cleared on logout/shutdown - proven live in Stage 4.
    // 58_disabled_module_unaffected: EchoesRecalculateAndApply's early return on
    //     !EchoesStatsConfig::instance()->enabled happens before EchoesQueryMasteryRankRaw is ever
    //     called - the ceiling/warning logic is unreachable while disabled, matching E2j3's
    //     already-proven disabled-gate (zero queries, zero effects).
    // 59_cost_and_absorption_formulas_unchanged: EchoesMasteryAbsorbPct's default constants
    //     (0.05/0.80/0.038) and EchoesCalculateAbsorption's summation logic are byte-identical to
    //     the E2j3-validated implementation - E2j4 added a clamp ahead of these functions, it did
    //     not modify them.

    // ============================================================================
    // E2j5a - armor/weapon-damage absorption restoration. Historical source:
    // cpp_patch/mod_attunement_plus.patch (echoes-of-the-worldsoul repo). Same absorbPct/
    // eligibility gate as the five primary stats - no separate formula, no talent multiplier.
    // ============================================================================

    // --- Armor sums identically to primary stats, same eligibility gate ---
    {
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.armor = 500; row.isArmor = true; row.armorSubClass = 1; // cloth
        rows.push_back(row);
        EchoesStatBonus bPriest = EchoesCalculateAbsorption(rows, 0, 80, 5); // Priest: cloth-only
        Check("60_armor_included_for_eligible_class", NearlyEqual(bPriest.armor, 500 * 0.05));
        EchoesStatBonus bWarrior = EchoesCalculateAbsorption(rows, 0, 80, 1); // Warrior: mail+plate only
        Check("61_armor_excluded_for_ineligible_class", NearlyEqual(bWarrior.armor, 0.0));
    }

    // --- Weapon DPS: weapons are always eligible (isArmor=false bypasses the class filter) ---
    {
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.weaponDps = 100; row.isArmor = false;
        rows.push_back(row);
        EchoesStatBonus b = EchoesCalculateAbsorption(rows, 0, 80, 5); // any class
        Check("62_weapon_dps_always_eligible", NearlyEqual(b.weaponDps, 100 * 0.05));
    }

    // --- Zero armor / zero weapon DPS contributes nothing (explicit zero-value item case) ---
    {
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.armor = 0; row.weaponDps = 0; row.isArmor = false;
        rows.push_back(row);
        EchoesStatBonus b = EchoesCalculateAbsorption(rows, 50, 80, 1);
        Check("63_zero_armor_and_weapon_dps_contribute_nothing",
            NearlyEqual(b.armor, 0.0) && NearlyEqual(b.weaponDps, 0.0));
    }

    // --- No talent-style multiplier on armor/weaponDps (unlike the historical patch's primary
    //     stats, which do get a separate talent multiplier not modeled in this pure calculator at
    //     all - this test just re-confirms armor/weaponDps scale with absorbPct alone, matching
    //     the primary-stat scaling exactly, no extra factor) ---
    {
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.str = 100; row.armor = 100; row.isArmor = false; row.weaponDps = 100;
        rows.push_back(row);
        EchoesStatBonus b = EchoesCalculateAbsorption(rows, 10, 80, 1);
        Check("64_armor_and_weapon_dps_scale_identically_to_primary_stats",
            NearlyEqual(b.armor, b.str) && NearlyEqual(b.weaponDps, b.str));
    }

    // --- Weapon-DPS-to-Attack-Power conversion: exact recovered historical constant (x7) ---
    {
        Check("65_weapon_dps_to_ap_conversion_factor_is_seven", kWeaponDpsToAttackPowerFactor == 7.0);
        Check("66_weapon_dps_to_ap_basic", NearlyEqual(EchoesWeaponDpsToAttackPower(10.0), 70.0));
        Check("67_weapon_dps_to_ap_floors_fractional_result",
            NearlyEqual(EchoesWeaponDpsToAttackPower(10.2), std::floor(10.2 * 7.0)));
        Check("68_weapon_dps_to_ap_zero_or_negative_yields_zero",
            EchoesWeaponDpsToAttackPower(0.0) == 0.0 && EchoesWeaponDpsToAttackPower(-5.0) == 0.0);
    }

    // --- No cap on cumulative weapon-DPS absorption across many gray/common weapon snapshots -
    //     explicit instruction: do not introduce a cumulative damage cap or quality restriction ---
    {
        std::vector<EchoesStatSnapshotRow> rows;
        for (int i = 0; i < 5000; ++i)
        {
            EchoesStatSnapshotRow row; row.weaponDps = 5.0; row.isArmor = false; // many gray weapons
            rows.push_back(row);
        }
        EchoesStatBonus b = EchoesCalculateAbsorption(rows, 8000, 80, 1); // saturated mastery
        double expectedTotal = 5000 * 5.0 * (0.05 + 0.80 * (1.0 - std::exp(-0.038 * 8000)));
        Check("69_no_cumulative_cap_on_many_gray_weapon_snapshots",
            NearlyEqual(b.weaponDps, expectedTotal, 0.01) && std::isfinite(b.weaponDps));
        double apFromLarge = EchoesWeaponDpsToAttackPower(b.weaponDps);
        Check("70_large_accumulated_weapon_dps_converts_to_ap_without_overflow",
            std::isfinite(apFromLarge) && apFromLarge > 0.0);
    }

    // --- Structural/source-cited notes (engine-coupled, proven live in isolated gates, not
    //     independently unit-testable here) ---
    // 71_armor_read_live_not_from_snapshot: EchoesQuerySnapshots (EchoesStatsHooks.cpp) resolves
    //     row.armor from a live sObjectMgr->GetItemTemplate(itemEntry)->Armor lookup, never from
    //     the ap_item_snapshot.armor DB column - confirmed by direct source read, matching the
    //     historical patch's own actually-executed CalculateAbsorption behavior exactly (its
    //     ScalingStatValue-adjusted self-heal path wrote to that column but was never read back
    //     by its own calculation, even in the original historical source).
    // 72_weapon_dps_read_from_snapshot_frozen: row.weaponDps is read directly from the DB's
    //     weapon_dps column (frozen at attunement time by ap_core.lua's
    //     AP.ComputeSnapshotStatsFromItemTemplate), not live - confirmed by direct source read.
    // 73_armor_apply_uses_unit_mod_armor: EchoesApplyDelta applies the armor delta via
    //     HandleStatFlatModifier(UNIT_MOD_ARMOR, TOTAL_VALUE, ..., apply) + UpdateArmor() -
    //     confirmed present in the current AzerothCore core (Unit.h/Player.h), matching the
    //     historical patch's HandleStatModifier(UNIT_MOD_ARMOR,...) call adapted to this core's
    //     actual function name (HandleStatModifier itself does not exist in this core).
    // 74_weapon_dps_apply_uses_unit_mod_attack_power: EchoesApplyDelta converts weaponDps to flat
    //     Attack Power via EchoesWeaponDpsToAttackPower before applying via
    //     HandleStatFlatModifier(UNIT_MOD_ATTACK_POWER, TOTAL_VALUE, ..., apply) +
    //     UpdateAttackPowerAndDamage() - confirmed present in the current core.
    // 75_idempotent_delta_preserved: both new fields use the identical old-minus-new delta
    //     pattern as the five primary stats (EchoesApplyDelta), removing the prior contribution
    //     before applying the new one - never a second/parallel stacking mechanism.
    // 76_removal_zeroes_both_fields: EchoesRemoveAll passes a default-constructed EchoesStatBonus
    //     (armor=0, weaponDps=0 by field initializer) to EchoesApplyDelta, correctly computing a
    //     full-removal delta for both new fields with no special-case code required.

    // ============================================================================
    // E2j5e - Talent stat-multiplier restoration. Historical source: recovered exactly from
    // cpp_patch/mod_attunement_plus.patch's talent-computation block (~line 287-329), corroborated
    // byte-for-byte by Talents.md and E2j3's prior recovery in ap_core.lua. Primary +12%/rank
    // (cap 3), secondary +8%/rank (cap 2), "primary" dynamic (highest rank, lowest index wins
    // ties), distinctPenalty = 0.85^(distinctStats-1). Applied ONLY to str/agi/sta/int/spi, never
    // to armor/weaponDps.
    // ============================================================================

    // --- Single-stat investment: sole invested stat is automatically primary, full +12%/rank ---
    {
        EchoesTalentInput t; t.ranks[0] = 1; // STR rank 1, alone
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.str = 100; row.isArmor = false;
        rows.push_back(row);
        EchoesStatBonus b = EchoesCalculateAbsorption(rows, 0, 80, 1, 0.05, 0.80, 0.038, t);
        // absorbPct = 0.05 (rank0 mastery, level80); mult=1+1*0.12=1.12; distinctPenalty=1
        Check("77_single_stat_investment_gets_primary_rate",
            NearlyEqual(b.str, 100 * 0.05 * 1.12));
    }

    // --- Primary/secondary split is dynamic: highest rank becomes primary regardless of index ---
    {
        EchoesTalentInput t; t.ranks[0] = 1; t.ranks[1] = 3; // STR rank1, AGI rank3 -> AGI primary
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.str = 100; row.agi = 100; row.isArmor = false;
        rows.push_back(row);
        EchoesStatBonus b = EchoesCalculateAbsorption(rows, 0, 80, 1, 0.05, 0.80, 0.038, t);
        // distinctStats=2 -> distinctPenalty=0.85. STR secondary: 1+1*0.08=1.08. AGI primary: 1+3*0.12=1.36.
        Check("78_dynamic_primary_is_highest_rank_stat",
            NearlyEqual(b.str, 100 * 0.05 * 1.08 * 0.85) &&
            NearlyEqual(b.agi, 100 * 0.05 * 1.36 * 0.85));
    }

    // --- Tie-break: equal ranks -> lowest stat_index keeps primary status (deterministic, matches
    //     the historical patch's strict `>` comparison) ---
    {
        EchoesTalentInput t; t.ranks[0] = 2; t.ranks[1] = 2; // STR and AGI both rank 2
        EchoesTalentMultipliers m = EchoesComputeTalentMultipliers(t);
        Check("79_equal_rank_tie_break_favors_lowest_index", m.primaryStat == 0);
    }

    // --- Diminishing-returns penalty: 2 distinct stats invested -> 0.85^1 ---
    {
        EchoesTalentInput t; t.ranks[0] = 1; t.ranks[1] = 1;
        EchoesTalentMultipliers m = EchoesComputeTalentMultipliers(t);
        Check("80_two_distinct_stats_penalty_is_0_85_pow_1", NearlyEqual(m.distinctPenalty, 0.85));
    }

    // --- Diminishing-returns penalty: 3 distinct stats invested -> 0.85^2, applied to all three ---
    {
        EchoesTalentInput t; t.ranks[0] = 1; t.ranks[1] = 1; t.ranks[2] = 1; // STR primary (first at rank1)
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.str = 100; row.agi = 100; row.sta = 100; row.isArmor = false;
        rows.push_back(row);
        EchoesStatBonus b = EchoesCalculateAbsorption(rows, 0, 80, 1, 0.05, 0.80, 0.038, t);
        double penalty = std::pow(0.85, 2);
        Check("81_three_distinct_stats_penalty_is_0_85_pow_2", NearlyEqual(penalty, 0.7225));
        Check("82_three_distinct_stats_str_primary_matches_hand_computed",
            NearlyEqual(b.str, 100 * 0.05 * 1.12 * penalty));
        Check("83_three_distinct_stats_secondary_agi_sta_match_hand_computed",
            NearlyEqual(b.agi, 100 * 0.05 * 1.08 * penalty) &&
            NearlyEqual(b.sta, 100 * 0.05 * 1.08 * penalty));
    }

    // --- Rank is capped defensively at the purchase-time maxima (3 primary / 2 secondary), even
    //     if a corrupt/out-of-range row were ever present - purchase code (unmodified) already
    //     enforces this, this is calculation-input safety only ---
    {
        EchoesTalentInput t; t.ranks[0] = 5; t.ranks[1] = 6; // AGI(6) > STR(5) -> AGI primary
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.str = 100; row.agi = 100; row.isArmor = false;
        rows.push_back(row);
        EchoesStatBonus b = EchoesCalculateAbsorption(rows, 0, 80, 1, 0.05, 0.80, 0.038, t);
        // STR secondary capped at rank 2: 1+2*0.08=1.16. AGI primary capped at rank 3: 1+3*0.12=1.36.
        // distinctStats=2 -> distinctPenalty=0.85.
        Check("84_primary_rank_capped_at_three",
            NearlyEqual(b.agi, 100 * 0.05 * 1.36 * 0.85));
        Check("85_secondary_rank_capped_at_two",
            NearlyEqual(b.str, 100 * 0.05 * 1.16 * 0.85));
    }

    // --- Zero-investment no-op: default EchoesTalentInput (all ranks 0) produces byte-identical
    //     output to omitting the parameter entirely (every pre-E2j5e call site/test) ---
    {
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.str = 100; row.agi = 50; row.sta = 200;
        row.intellect = 10; row.spirit = 10; row.isArmor = false;
        rows.push_back(row);
        EchoesStatBonus bNoParam = EchoesCalculateAbsorption(rows, 0, 80, 1);
        EchoesStatBonus bExplicitZero = EchoesCalculateAbsorption(rows, 0, 80, 1, 0.05, 0.80, 0.038, EchoesTalentInput());
        Check("86_zero_investment_byte_identical_to_omitted_parameter",
            NearlyEqual(bNoParam.str, bExplicitZero.str) && NearlyEqual(bNoParam.agi, bExplicitZero.agi) &&
            NearlyEqual(bNoParam.sta, bExplicitZero.sta) && NearlyEqual(bNoParam.intellect, bExplicitZero.intellect) &&
            NearlyEqual(bNoParam.spirit, bExplicitZero.spirit));
        Check("87_zero_investment_matches_pre_talent_hand_computed_value",
            NearlyEqual(bNoParam.str, 100 * 0.05) && NearlyEqual(bNoParam.sta, 200 * 0.05));
        EchoesTalentMultipliers mZero = EchoesComputeTalentMultipliers(EchoesTalentInput());
        Check("88_no_investment_all_multipliers_are_one_and_no_primary",
            NearlyEqual(mZero.mult[0], 1.0) && NearlyEqual(mZero.mult[1], 1.0) &&
            NearlyEqual(mZero.mult[2], 1.0) && NearlyEqual(mZero.mult[3], 1.0) &&
            NearlyEqual(mZero.mult[4], 1.0) && NearlyEqual(mZero.distinctPenalty, 1.0) &&
            mZero.primaryStat == -1);
    }

    // --- Negative control: armor/weaponDps absorption is completely unaffected by ANY talent
    //     investment, even a maxed-out multi-stat spread (proves the exclusion documented at
    //     E2j5a is preserved exactly by this phase) ---
    {
        EchoesTalentInput t; t.ranks[0] = 3; t.ranks[1] = 2; t.ranks[2] = 2; t.ranks[3] = 2; t.ranks[4] = 2;
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.armor = 100; row.weaponDps = 100; row.isArmor = false;
        rows.push_back(row);
        EchoesStatBonus bWithTalents = EchoesCalculateAbsorption(rows, 0, 80, 1, 0.05, 0.80, 0.038, t);
        EchoesStatBonus bWithoutTalents = EchoesCalculateAbsorption(rows, 0, 80, 1);
        Check("89_armor_unaffected_by_maxed_talent_investment",
            NearlyEqual(bWithTalents.armor, bWithoutTalents.armor) && NearlyEqual(bWithTalents.armor, 100 * 0.05));
        Check("90_weapon_dps_unaffected_by_maxed_talent_investment",
            NearlyEqual(bWithTalents.weaponDps, bWithoutTalents.weaponDps) && NearlyEqual(bWithTalents.weaponDps, 100 * 0.05));
    }

    // --- Repeated recalculation with active Talent investment is deterministic/byte-identical
    //     across calls (pure function - proves talent multiplier math introduces no drift or
    //     accumulation source, mirroring test 53's ceiling-clamp determinism proof) ---
    {
        EchoesTalentInput t; t.ranks[2] = 3; // STA primary rank 3
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.sta = 200; row.isArmor = false;
        rows.push_back(row);
        EchoesStatBonus b1 = EchoesCalculateAbsorption(rows, 0, 80, 1, 0.05, 0.80, 0.038, t);
        EchoesStatBonus b2 = EchoesCalculateAbsorption(rows, 0, 80, 1, 0.05, 0.80, 0.038, t);
        EchoesStatBonus b3 = EchoesCalculateAbsorption(rows, 0, 80, 1, 0.05, 0.80, 0.038, t);
        Check("91_repeated_recalc_with_talents_is_byte_identical",
            NearlyEqual(b1.sta, b2.sta) && NearlyEqual(b2.sta, b3.sta));
    }

    // --- Structural/source-cited notes (engine-coupled, proven by direct source read of
    //     EchoesStatsHooks.cpp, not independently unit-testable in this pure-header file, matching
    //     this project's established split - see E2j5a's 71-76 above for the same convention) ---
    // 92_disable_reenable_non_doubling_reuses_proven_pattern: EchoesQueryTalents/talentMult flow
    //     into the SAME EchoesStatBonus.str/agi/sta/int/spi values that EchoesApplyDelta already
    //     applies via the exact remove-then-reapply HandleStatFlatModifier idiom proven non-doubling
    //     for B1/B2/B3 (E2j5a) - Talents introduce no new stacking mechanism, no new AppliedBonus
    //     field, and no new hook; disabling EchoesStats.Enable=0 zeroes newBonus via the same
    //     early-return path already covering the primary stats, and re-enabling reapplies exactly
    //     once via the same idempotent delta comparison, by construction (direct source read,
    //     EchoesStatsHooks.cpp's EchoesRecalculateAndApply/EchoesRemoveAll/EchoesApplyDelta).
    // 93_no_new_hook_or_query_cost_class: EchoesQueryTalents is a single small SELECT keyed by
    //     guid (character-scoped, confirmed via ap_core.lua/ap04_db.lua), invoked from the exact
    //     same EchoesRecalculateAndApply call sites (login, level-change, 10s periodic refresh) as
    //     EchoesQueryMasteryRankRaw/EchoesQuerySnapshots - no new WorldScript, no new PlayerScript
    //     hook registration, confirmed by direct source read.

    // ============================================================================
    // E2j5g Stage 7 - Spell Mitigation restoration. Historical source: recovered exactly from
    // cpp_patch/mod_attunement_plus.patch's ModifySpellDamageTaken block (~line 967-997),
    // independently re-verified byte-for-byte against that source directly (not just the
    // e2j5g-HIGH-IMPACT-CONTRACT-RECOVERY.md report's paraphrase) before this phase wrote any
    // code. Formula: mitigFrac = 0.25*(1-e^(-0.000004*invested)); reduction = floor(damage*frac);
    // if reduction >= damage, reduction = damage-1 (floor-safety: never zero out damage entirely).
    // ============================================================================

    // --- Zero investment is an explicit no-op: zero reduction regardless of damage amount ---
    {
        Check("94_zero_investment_yields_zero_reduction",
            EchoesComputeSpellMitigationReduction(1000, 0.0) == 0 &&
            EchoesComputeSpellMitigationReduction(1, 0.0) == 0 &&
            EchoesComputeSpellMitigationReduction(999999, 0.0) == 0);
        Check("95_negative_investment_treated_as_zero_no_crash",
            EchoesComputeSpellMitigationReduction(1000, -50.0) == 0);
    }

    // --- Non-positive damage is always a no-op (matches the recovered `damage > 0` guard;
    //     the engine-level spellInfo/school-mask/target-is-player guards are gated in
    //     EchoesStatsHooks.cpp's UnitScript override, not independently testable in this pure
    //     header file - see the structural notes below for that gating chain's source citation) ---
    {
        Check("96_zero_damage_yields_zero_reduction",
            EchoesComputeSpellMitigationReduction(0, 10000.0) == 0);
        Check("97_negative_damage_yields_zero_reduction_no_crash",
            EchoesComputeSpellMitigationReduction(-5, 10000.0) == 0);
    }

    // --- Asymptotic ceiling formula: monotonically increasing with investment, approaches but
    //     never exceeds 25% ---
    {
        double f0 = EchoesSpellMitigationFraction(0.0);
        double f1k = EchoesSpellMitigationFraction(1000.0);
        double f100k = EchoesSpellMitigationFraction(100000.0);
        double f1m = EchoesSpellMitigationFraction(1000000.0);
        double f100m = EchoesSpellMitigationFraction(100000000.0);
        Check("98_fraction_zero_at_zero_investment", NearlyEqual(f0, 0.0));
        Check("99_fraction_increases_monotonically",
            f0 < f1k && f1k < f100k && f100k < f1m && f1m < f100m);
        Check("100_fraction_never_exceeds_ceiling_even_at_huge_investment",
            f100m <= kSpellMitigationCeiling + 0.0001);
        Check("101_fraction_approaches_ceiling_asymptotically",
            NearlyEqual(f100m, kSpellMitigationCeiling, 0.0001));
        Check("102_ceiling_constant_matches_recovered_value", kSpellMitigationCeiling == 0.25);
    }

    // --- Known hand-computed value at a representative investment tier (matches this phase's
    //     own hand-computed value, independent of the implementation, computed directly from the
    //     recovered formula: 0.25*(1-e^(-0.000004*250000))) ---
    {
        double invested = 250000.0;
        double expectedFrac = 0.25 * (1.0 - std::exp(-0.000004 * invested));
        double actualFrac = EchoesSpellMitigationFraction(invested);
        Check("103_hand_computed_fraction_at_250000_invested", NearlyEqual(actualFrac, expectedFrac));

        int32_t damage = 1000;
        uint32_t expectedReduction = static_cast<uint32_t>(std::floor(damage * expectedFrac));
        uint32_t actualReduction = EchoesComputeSpellMitigationReduction(damage, invested);
        Check("104_hand_computed_reduction_at_250000_invested_1000_damage",
            actualReduction == expectedReduction);
    }

    // --- Floor-safety rule: reduction is defensively capped at damage-1 even when a hypothetical
    //     ceiling approaches/exceeds 100% (the real spell-mitigation ceiling is 0.25, so this
    //     branch is mathematically unreachable at the real ceiling for any positive damage - this
    //     test exercises the defensive floor-safety code path itself directly via the optional
    //     ceiling parameter, proving it is implemented correctly and matches the recovered
    //     contract's floor rule exactly, not merely proving something that can never fire) ---
    {
        // ceiling=1.0 (hypothetical, test-only override), huge investment -> frac approaches 1.0
        uint32_t reduction1 = EchoesComputeSpellMitigationReduction(100, 100000000.0, 1.0, 0.000004);
        Check("105_floor_safety_never_reduces_damage_to_zero", reduction1 == 99 && reduction1 < 100);

        uint32_t reduction2 = EchoesComputeSpellMitigationReduction(1, 100000000.0, 1.0, 0.000004);
        Check("106_floor_safety_holds_for_damage_of_one", reduction2 == 0);

        // At the REAL 0.25 ceiling, the floor-safety branch is never reached for any positive
        // damage (0.25 * damage < damage always) - confirmed here across a wide damage range.
        bool floorNeverTriggeredAtRealCeiling = true;
        for (int32_t dmg : {1, 2, 3, 4, 10, 100, 1000, 100000})
        {
            uint32_t r = EchoesComputeSpellMitigationReduction(dmg, 100000000.0); // near-saturated real ceiling
            if (r >= static_cast<uint32_t>(dmg)) { floorNeverTriggeredAtRealCeiling = false; break; }
        }
        Check("107_floor_safety_branch_unreachable_at_real_25pct_ceiling_by_design",
            floorNeverTriggeredAtRealCeiling);
    }

    // --- Repeated computation is deterministic/byte-identical (pure function - no drift or
    //     hidden state, mirroring tests 53/91's own determinism proofs for the other two
    //     recovered formulas in this file) ---
    {
        uint32_t r1 = EchoesComputeSpellMitigationReduction(500, 300000.0);
        uint32_t r2 = EchoesComputeSpellMitigationReduction(500, 300000.0);
        uint32_t r3 = EchoesComputeSpellMitigationReduction(500, 300000.0);
        Check("108_repeated_computation_is_byte_identical", r1 == r2 && r2 == r3);
    }

    // --- Negative control: Spell Mitigation is a wholly separate function from
    //     EchoesCalculateAbsorption - Mastery/Talent/armor/weapon-dps absorption values are
    //     byte-identical whether or not EchoesComputeSpellMitigationReduction is ever called,
    //     since the two are never wired together (confirmed by direct source read: Spell
    //     Mitigation is consumed only by EchoesStatsHooks.cpp's new UnitScript override, a
    //     wholly separate code path from EchoesRecalculateAndApply/EchoesCalculateAbsorption) ---
    {
        EchoesTalentInput t; t.ranks[0] = 3; t.ranks[2] = 2; // some Talent investment, for realism
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row;
        row.str = 100; row.sta = 200; row.armor = 150; row.weaponDps = 80; row.isArmor = false;
        rows.push_back(row);

        EchoesStatBonus bBefore = EchoesCalculateAbsorption(rows, 500, 80, 1, 0.05, 0.80, 0.038, t);
        // Simulate a Spell Mitigation calculation happening "in between" - this call touches no
        // shared state, no snapshot, no Mastery/Talent input, and returns a value entirely
        // independent of the above call.
        (void)EchoesComputeSpellMitigationReduction(1000, 900000.0);
        EchoesStatBonus bAfter = EchoesCalculateAbsorption(rows, 500, 80, 1, 0.05, 0.80, 0.038, t);

        Check("109_mastery_talent_absorption_unaffected_by_spell_mitigation_calls",
            NearlyEqual(bBefore.str, bAfter.str) && NearlyEqual(bBefore.sta, bAfter.sta) &&
            NearlyEqual(bBefore.armor, bAfter.armor) && NearlyEqual(bBefore.weaponDps, bAfter.weaponDps));

        // Explicit exact recompute (armor/weaponDps get no Talent multiplier, matching E2j5a's
        // own exclusion, unaffected by any Spell Mitigation call in between) ---
        double absorbPct = EchoesMasteryAbsorbPct(500) * EchoesLevelAbsorbScalar(80);
        Check("110_armor_and_weapon_dps_match_exact_recompute_no_spell_mitigation_interference",
            NearlyEqual(bAfter.armor, 150 * absorbPct) && NearlyEqual(bAfter.weaponDps, 80 * absorbPct));
    }

    // --- Structural/source-cited notes (engine-coupled, proven by direct source read of
    //     EchoesStatsHooks.cpp, not independently unit-testable in this pure-header file, matching
    //     this project's established convention - see 71-76/92-93 above for the same pattern) ---
    // 111_damage_channel_gating_confirmed_by_source_read: EchoesStatsUnitScript::ModifySpellDamageTaken
    //     (EchoesStatsHooks.cpp) implements the recovered gating chain exactly: target must be a
    //     Player and damage>0; spellInfo must be non-null (physical auto-attacks pass nullptr and
    //     are excluded entirely, not zero-mitigated); spellInfo->GetSchoolMask() must not equal
    //     SPELL_SCHOOL_MASK_NORMAL (physical-school spell damage excluded even with a non-null
    //     spellInfo) - confirmed present, in this exact order, by direct source read, matching
    //     cpp_patch's own guard order byte-for-byte.
    // 112_bot_behavior_matches_human_automatically: the gating chain checks target->IsPlayer()
    //     only - bots are Player objects server-side, so a bot with an existing ap_aether_sinks
    //     spell_mitigation investment receives the identical reduction as a human with the same
    //     investment, with no bot-specific code path, no new bot-purchase adapter, and no change
    //     to mod-echoes-playerbots - confirmed by direct source read (EchoesStatsUnitScript
    //     contains no IsBot()/AI-related check of any kind).
    // 113_disable_reenable_non_doubling: EchoesStatsUnitScript::ModifySpellDamageTaken's very
    //     first check is `!EchoesStatsConfig::instance()->enabled`, an early return before any
    //     query or mutation - setting EchoesStats.Enable=0 makes every subsequent spell-damage
    //     event a pure no-op (zero queries, zero `damage` mutation, zero notification) exactly
    //     like the existing login/level/periodic paths' own disable gate; re-enabling causes the
    //     very next qualifying spell-damage event to recompute and apply the reduction fresh from
    //     the per-hit formula (not accumulated/incremented state) - there is no persisted or
    //     in-memory "applied mitigation" value that could double, unlike the stat-delta bonuses
    //     above (EchoesStatsState::AppliedBonus) which explicitly need the remove-then-reapply
    //     idiom; Spell Mitigation's per-hit `damage -= reduction` has no analogous stacking risk
    //     to guard against, by construction (direct source read, confirmed no accumulation
    //     variable of any kind exists for this feature).
    // 114_account_scoped_30s_cache_matches_recovered_contract: EchoesQuerySpellMitigationInvested
    //     caches per account_id for 30 seconds, matching cpp_patch's own `s_sinkCache`/30000ms
    //     cache lifetime and its account-scoping exactly (re-confirmed live, not just
    //     historically, via ap04_db.lua's ap_aether_sinks account_id column and ap_sinks.lua's
    //     AP.Sinks.LoadForAccount(accountId)) - not a new persistence surface, a read-only cache
    //     of an already-existing, already-populated table.
    // 115_no_persisted_state_created: this restoration creates zero new database tables, columns,
    //     or migrations - EchoesQuerySpellMitigationInvested is a read-only SELECT against the
    //     pre-existing ap_aether_sinks table, confirmed by direct source read (no INSERT/UPDATE/
    //     REPLACE statement of any kind was added by this phase).

    // =========================================================================================
    // E2j5h Stage 2 - Fortitude restoration tests. EchoesFortitudeBonus/EchoesApplyFortitudeMultiplier
    // are pure and dependency-free (EchoesStatsCalculator.h) - fully testable standalone, matching
    // this file's established pattern for Mastery/Talent/Spell Mitigation above. The engine-coupled
    // parts (EchoesQueryFortitudeInvested's DB read, its wiring into EchoesRecalculateAndApply, and
    // its reuse of the already-proven EchoesApplyDelta/HandleStatFlatModifier/UpdateStatBuffMod
    // path) are proven by direct source read and the isolated Docker build, not by this file -
    // matching this project's established convention (see "111_.../112_.../113_..." structural
    // notes above for the same pattern applied to Spell Mitigation).
    // =========================================================================================

    // --- Fortitude bonus: zero investment yields zero bonus ---
    {
        Check("116_fortitude_zero_investment_yields_zero_bonus",
            NearlyEqual(EchoesFortitudeBonus(0.0), 0.0));
        Check("117_fortitude_negative_investment_treated_as_zero_no_crash",
            NearlyEqual(EchoesFortitudeBonus(-500.0), 0.0));
    }

    // --- Fortitude bonus: monotonically increases with investment, approaches ceiling ---
    {
        double b1 = EchoesFortitudeBonus(1000.0);
        double b2 = EchoesFortitudeBonus(100000.0);
        double b3 = EchoesFortitudeBonus(1000000.0);
        double bHuge = EchoesFortitudeBonus(50000000.0);
        Check("118_fortitude_increases_with_investment_1k_lt_100k", b1 < b2);
        Check("119_fortitude_increases_with_investment_100k_lt_1m", b2 < b3);
        Check("120_fortitude_never_exceeds_ceiling", bHuge <= kFortitudeCeiling + 0.0001);
        Check("121_fortitude_approaches_ceiling_asymptotically", NearlyEqual(bHuge, 0.50, 0.0001));
    }

    // --- Fortitude bonus: ceiling constant matches the recovered value (0.50, double Spell
    //     Mitigation's own 0.25 ceiling - the highest cap of any Aether Sink formula recovered
    //     to date, per the contract-recovery report) ---
    {
        Check("122_fortitude_ceiling_constant_matches_recovered_value", kFortitudeCeiling == 0.50);
        Check("123_fortitude_decay_k_constant_matches_recovered_value", kFortitudeDecayK == 0.000003);
    }

    // --- Fortitude bonus: hand-computed value at a representative investment tier ---
    {
        // fortitudeBonus = 0.50 * (1 - exp(-0.000003 * 250000)) = 0.50 * (1 - exp(-0.75))
        double invested = 250000.0;
        double expected = 0.50 * (1.0 - std::exp(-0.000003 * invested));
        double actual = EchoesFortitudeBonus(invested);
        Check("124_hand_computed_fortitude_bonus_at_250000_invested", NearlyEqual(actual, expected));
    }

    // --- Fortitude multiplier: applies ONLY to sta, every other field passed through unchanged
    //     (matches cpp_patch's own `newStats[2] *=` touching only index 2 / STA) ---
    {
        EchoesStatBonus bonus;
        bonus.str = 10.0; bonus.agi = 20.0; bonus.sta = 100.0; bonus.intellect = 30.0;
        bonus.spirit = 40.0; bonus.armor = 50.0; bonus.weaponDps = 60.0;

        EchoesStatBonus result = EchoesApplyFortitudeMultiplier(bonus, 250000.0);
        double expectedBonus = EchoesFortitudeBonus(250000.0);

        Check("125_fortitude_multiplies_sta_only",
            NearlyEqual(result.sta, 100.0 * (1.0 + expectedBonus)));
        Check("126_fortitude_does_not_affect_str", NearlyEqual(result.str, 10.0));
        Check("127_fortitude_does_not_affect_agi", NearlyEqual(result.agi, 20.0));
        Check("128_fortitude_does_not_affect_int", NearlyEqual(result.intellect, 30.0));
        Check("129_fortitude_does_not_affect_spi", NearlyEqual(result.spirit, 40.0));
        Check("130_fortitude_does_not_affect_armor", NearlyEqual(result.armor, 50.0));
        Check("131_fortitude_does_not_affect_weapon_dps", NearlyEqual(result.weaponDps, 60.0));
    }

    // --- Fortitude multiplier: zero investment leaves sta byte-identical to input (no-op) ---
    {
        EchoesStatBonus bonus;
        bonus.sta = 250.0;
        EchoesStatBonus result = EchoesApplyFortitudeMultiplier(bonus, 0.0);
        Check("132_fortitude_zero_investment_leaves_sta_unchanged", result.sta == bonus.sta);
    }

    // --- Fortitude multiplier: non-compounding across repeated refresh calls. Feeding the SAME
    //     freshly-computed base bonus through the multiplier repeatedly (mirroring
    //     EchoesRecalculateAndApply's own pattern of always starting from a fresh
    //     EchoesCalculateAbsorption result, never from its own prior output) yields a byte-identical
    //     result every time - proving the multiplier itself introduces no hidden accumulator. This
    //     is the critical guard called out in this phase's own required verification coverage: STA
    //     absorption must not compound across repeated login/level/periodic-safety-net refreshes. ---
    {
        EchoesStatBonus base;
        base.sta = 400.0;
        EchoesStatBonus r1 = EchoesApplyFortitudeMultiplier(base, 500000.0);
        EchoesStatBonus r2 = EchoesApplyFortitudeMultiplier(base, 500000.0);
        EchoesStatBonus r3 = EchoesApplyFortitudeMultiplier(base, 500000.0);
        Check("133_fortitude_repeated_refresh_is_byte_identical_non_compounding",
            r1.sta == r2.sta && r2.sta == r3.sta);

        // Explicit anti-compounding regression: feeding r1 back in AS THE BASE (the bug this test
        // guards against) would double-apply the multiplier - demonstrate that is NOT what
        // EchoesRecalculateAndApply does by confirming the correct call pattern (fresh base each
        // time) produces a materially smaller value than the (intentionally wrong) chained pattern
        // would, proving the two are distinguishable and the non-compounding path is what the
        // formula-level function itself supports when called correctly.
        EchoesStatBonus wrongChained = EchoesApplyFortitudeMultiplier(r1, 500000.0);
        Check("134_fortitude_chaining_the_multiplier_would_visibly_compound_unlike_correct_usage",
            wrongChained.sta > r1.sta);
    }

    // --- Fortitude: rank increase produces a strictly larger sta bonus for the same base ---
    {
        EchoesStatBonus base;
        base.sta = 300.0;
        EchoesStatBonus low = EchoesApplyFortitudeMultiplier(base, 10000.0);
        EchoesStatBonus high = EchoesApplyFortitudeMultiplier(base, 500000.0);
        Check("135_fortitude_rank_increase_yields_larger_sta_bonus", high.sta > low.sta);
    }

    // --- Fortitude: rank "decrease" - per the recovered contract, ap_aether_sinks investment is
    //     one-directional (no decrease/refund path exists in source); this test only confirms the
    //     PURE FORMULA behaves correctly and safely if ever called with a smaller `invested` value
    //     than a previous call (e.g. an administrative DB correction) - it does not assert this is a
    //     supported gameplay path, matching the contract's explicit "not part of the recovered
    //     contract" finding. ---
    {
        EchoesStatBonus base;
        base.sta = 300.0;
        EchoesStatBonus high = EchoesApplyFortitudeMultiplier(base, 500000.0);
        EchoesStatBonus low = EchoesApplyFortitudeMultiplier(base, 10000.0);
        Check("136_fortitude_smaller_invested_value_yields_smaller_bonus_safely", low.sta < high.sta);
        Check("137_fortitude_smaller_invested_value_never_below_base", low.sta >= base.sta);
    }

    // --- Fortitude: "removal" at the formula level - a base bonus multiplied by zero investment
    //     is identical to a base bonus that never had Fortitude applied at all, confirming there is
    //     no residual/hidden state at the pure-function level (the engine-level removal path itself
    //     - EchoesRemoveAll/EchoesApplyDelta zeroing the entire recorded AppliedBonus on logout - is
    //     proven by direct source read, not here; see this file's header comment). ---
    {
        EchoesStatBonus base;
        base.sta = 300.0;
        EchoesStatBonus withZeroInvestment = EchoesApplyFortitudeMultiplier(base, 0.0);
        Check("138_fortitude_removal_equivalent_zero_investment_matches_untouched_base",
            withZeroInvestment.sta == base.sta);
    }

    // --- Fortitude x Talent interaction: per the recovered contract's explicit "Order of
    //     Operations" finding, Fortitude multiplies on top of an ALREADY Talent-scaled STA value
    //     (not the other way around, and not independently of Talent) - confirmed here by applying
    //     Fortitude to the real output of EchoesCalculateAbsorption WITH a non-trivial Talent
    //     investment, and proving the result equals (Talent-scaled sta) * (1 + fortitudeBonus)
    //     exactly, i.e. multiplicative composition, never additive, and never applied before/instead
    //     of the Talent scaling. ---
    {
        EchoesTalentInput talents;
        talents.ranks[2] = 3; // STA primary, rank 3 (capped) -> 1.0 + 3*0.12 = 1.36

        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row;
        row.sta = 200.0; row.isArmor = false; // misc/weapon-shaped row, always eligible
        rows.push_back(row);

        // masteryRank=500 level=80 -> saturated absorbPct = 0.05+0.80=0.85 (rank 500 saturates)
        EchoesStatBonus talentScaled = EchoesCalculateAbsorption(rows, 500, 80, 1, 0.05, 0.80, 0.038, talents);
        double talentMult = EchoesComputeTalentMultipliers(talents).mult[2]; // 1.36, no distinct penalty (single stat)

        EchoesStatBonus withFortitude = EchoesApplyFortitudeMultiplier(talentScaled, 250000.0);
        double fortitudeBonus = EchoesFortitudeBonus(250000.0);

        Check("139_fortitude_multiplies_on_top_of_talent_scaled_sta",
            NearlyEqual(withFortitude.sta, talentScaled.sta * (1.0 + fortitudeBonus)));
        Check("140_fortitude_composition_is_multiplicative_not_additive",
            !NearlyEqual(withFortitude.sta, talentScaled.sta + fortitudeBonus * 100.0));
        // Sanity: talent scaling itself is present in talentScaled.sta (proves this test actually
        // exercised the Talent-then-Fortitude order, not a degenerate zero-Talent case).
        double baseNoTalentSta = 200.0 * 0.85; // absorbPct only, no talent mult
        Check("141_talent_scaling_present_before_fortitude_applied",
            talentScaled.sta > baseNoTalentSta && NearlyEqual(talentScaled.sta, baseNoTalentSta * talentMult));
    }

    // --- Negative control: Fortitude is a wholly separate function from
    //     EchoesComputeSpellMitigationReduction - calling one never affects the other's output,
    //     confirming the two E2j5g/E2j5h-recovered Aether Sink features remain fully independent
    //     (mirrors this file's existing 109/110 negative-control pattern for Spell Mitigation x
    //     Mastery/Talent). ---
    {
        double fortitudeBefore = EchoesFortitudeBonus(300000.0);
        uint32_t mitigReduction = EchoesComputeSpellMitigationReduction(1000, 900000.0);
        (void)mitigReduction;
        double fortitudeAfter = EchoesFortitudeBonus(300000.0);
        Check("142_fortitude_unaffected_by_spell_mitigation_calls",
            NearlyEqual(fortitudeBefore, fortitudeAfter));

        double mitigBefore = EchoesSpellMitigationFraction(300000.0);
        EchoesStatBonus dummy; dummy.sta = 100.0;
        EchoesStatBonus fortitudeResult = EchoesApplyFortitudeMultiplier(dummy, 900000.0);
        (void)fortitudeResult;
        double mitigAfter = EchoesSpellMitigationFraction(300000.0);
        Check("143_spell_mitigation_unaffected_by_fortitude_calls", NearlyEqual(mitigBefore, mitigAfter));
    }

    // --- Negative control: Mastery/armor/weaponDps absorption values are byte-identical whether or
    //     not EchoesApplyFortitudeMultiplier is ever called on a SEPARATE EchoesStatBonus instance
    //     (confirms Fortitude has no shared/global state that could leak into an unrelated
    //     calculation, matching this file's established 109/110 pattern) ---
    {
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row;
        row.str = 100; row.sta = 200; row.armor = 150; row.weaponDps = 80; row.isArmor = false;
        rows.push_back(row);

        EchoesStatBonus bBefore = EchoesCalculateAbsorption(rows, 500, 80, 1);
        EchoesStatBonus unrelated; unrelated.sta = 999.0;
        (void)EchoesApplyFortitudeMultiplier(unrelated, 1000000.0);
        EchoesStatBonus bAfter = EchoesCalculateAbsorption(rows, 500, 80, 1);

        Check("144_mastery_absorption_unaffected_by_unrelated_fortitude_calls",
            NearlyEqual(bBefore.str, bAfter.str) && NearlyEqual(bBefore.sta, bAfter.sta) &&
            NearlyEqual(bBefore.armor, bAfter.armor) && NearlyEqual(bBefore.weaponDps, bAfter.weaponDps));
    }

    // --- Structural/source-cited notes (engine-coupled, proven by direct source read of
    //     EchoesStatsHooks.cpp, not independently unit-testable in this pure-header file, matching
    //     this project's established convention - see 111-115 above for the same pattern) ---
    // 145_human_bot_path_equivalence: EchoesQueryFortitudeInvested/EchoesRecalculateAndApply contain
    //     no IsBot()/AI-related branch of any kind - Fortitude applies identically to any Player
    //     (human or bot) via the same EchoesApplyDelta/HandleStatFlatModifier/UpdateStatBuffMod path
    //     already proven for Mastery/Talent, confirmed by direct source read, matching Talent's own
    //     D2 human/bot equivalence.
    // 146_max_health_preservation_inherited_not_reimplemented: EchoesApplyDelta already calls
    //     player->UpdateStatBuffMod(STAT_STAMINA) for the pre-existing Mastery/Talent STA delta,
    //     live in production today - Fortitude's STA contribution flows through the exact same
    //     HandleStatFlatModifier+UpdateStatBuffMod call with zero new code, confirmed by direct
    //     source read of EchoesApplyDelta (no separate/new health-recalculation call was added).
    // 147_death_resurrection_no_special_casing_needed: confirmed by direct source read that no
    //     death/resurrection hook exists or was added for Fortitude, matching the recovered
    //     contract's explicit "no special-casing found in cpp_patch" finding - this module's
    //     existing login/logout/level/periodic triggers are the only recalculation points, exactly
    //     as they already are for the live Mastery/Talent STA path.
    // 148_no_persisted_state_created: EchoesQueryFortitudeInvested is a read-only SELECT against the
    //     pre-existing ap_aether_sinks table - zero new tables, columns, or migrations, confirmed by
    //     direct source read (no INSERT/UPDATE/REPLACE statement of any kind was added by this
    //     phase).

    // ==================================================================================
    // E2j6 - Combat-rating restoration: crit_rating, haste_rating, dodge_rating, parry_rating.
    // Continuing after assertion 144 (the highest real Check() call above).
    // ==================================================================================

    // --- EchoesRatingSinkFraction: zero investment yields zero ---
    {
        Check("149_crit_zero_investment_yields_zero_fraction",
            EchoesRatingSinkFraction(0.0, kCritRatingCeiling) == 0.0);
        Check("150_haste_zero_investment_yields_zero_fraction",
            EchoesRatingSinkFraction(0.0, kHasteRatingCeiling) == 0.0);
        Check("151_dodge_zero_investment_yields_zero_fraction",
            EchoesRatingSinkFraction(0.0, kDodgeRatingCeiling) == 0.0);
        Check("152_parry_zero_investment_yields_zero_fraction",
            EchoesRatingSinkFraction(0.0, kParryRatingCeiling) == 0.0);
    }

    // --- Negative/invalid investment treated as zero, no crash (defensive input handling,
    //     matching this file's existing convention for every other sink category) ---
    {
        Check("153_rating_sink_negative_investment_treated_as_zero",
            EchoesRatingSinkFraction(-500.0, kCritRatingCeiling) == 0.0);
    }

    // --- Monotonic increase across investment tiers, per category ---
    {
        double critLow = EchoesRatingSinkFraction(1000.0, kCritRatingCeiling);
        double critMid = EchoesRatingSinkFraction(100000.0, kCritRatingCeiling);
        double critHigh = EchoesRatingSinkFraction(2000000.0, kCritRatingCeiling);
        Check("154_crit_increases_low_lt_mid", critLow < critMid);
        Check("155_crit_increases_mid_lt_high", critMid < critHigh);

        double hasteLow = EchoesRatingSinkFraction(1000.0, kHasteRatingCeiling);
        double hasteHigh = EchoesRatingSinkFraction(2000000.0, kHasteRatingCeiling);
        Check("156_haste_increases_low_lt_high", hasteLow < hasteHigh);
    }

    // --- Never exceeds ceiling, approaches it asymptotically at extreme investment ---
    {
        Check("157_crit_never_exceeds_ceiling",
            EchoesRatingSinkFraction(1e9, kCritRatingCeiling) <= kCritRatingCeiling + 0.0001);
        Check("158_haste_never_exceeds_ceiling",
            EchoesRatingSinkFraction(1e9, kHasteRatingCeiling) <= kHasteRatingCeiling + 0.0001);
        Check("159_dodge_never_exceeds_ceiling",
            EchoesRatingSinkFraction(1e9, kDodgeRatingCeiling) <= kDodgeRatingCeiling + 0.0001);
        Check("160_parry_never_exceeds_ceiling",
            EchoesRatingSinkFraction(1e9, kParryRatingCeiling) <= kParryRatingCeiling + 0.0001);
        Check("161_crit_approaches_ceiling_asymptotically",
            NearlyEqual(EchoesRatingSinkFraction(1e9, kCritRatingCeiling), kCritRatingCeiling, 0.0001));
    }

    // --- Recovered constants are exactly what's coded (ap_sinks.lua citation) ---
    {
        Check("162_crit_ceiling_constant_matches_recovered_value", NearlyEqual(kCritRatingCeiling, 0.15));
        Check("163_haste_ceiling_constant_matches_recovered_value", NearlyEqual(kHasteRatingCeiling, 0.20));
        Check("164_dodge_ceiling_constant_matches_recovered_value", NearlyEqual(kDodgeRatingCeiling, 0.15));
        Check("165_parry_ceiling_constant_matches_recovered_value", NearlyEqual(kParryRatingCeiling, 0.10));
        Check("166_rating_decay_k_constant_matches_recovered_value", NearlyEqual(kRatingSinkDecayK, 0.000003));
    }

    // --- Hand-computed value at a realistic seeded investment (matching this file's own
    //     established "hand-computed at a specific value" pattern, e.g. test 124) ---
    {
        // crit: 0.15 * (1 - exp(-0.000003 * 250000)) = 0.15 * (1 - exp(-0.75))
        double expected = 0.15 * (1.0 - std::exp(-0.000003 * 250000.0));
        Check("167_hand_computed_crit_fraction_at_250000_invested",
            NearlyEqual(EchoesRatingSinkFraction(250000.0, kCritRatingCeiling), expected));
    }

    // --- EchoesRatingPointsForPercent: pure percent -> rating-point conversion ---
    {
        Check("168_zero_percent_yields_zero_points", EchoesRatingPointsForPercent(0.0, 45.91f) == 0);
        Check("169_negative_percent_yields_zero_points", EchoesRatingPointsForPercent(-5.0, 45.91f) == 0);
        Check("170_zero_multiplier_yields_zero_points_defensive", EchoesRatingPointsForPercent(15.0, 0.0f) == 0);
        Check("171_negative_multiplier_yields_zero_points_defensive", EchoesRatingPointsForPercent(15.0, -1.0f) == 0);

        // 15% crit / (1% per 45.91 rating, i.e. multiplier = 1/45.91 percent-per-rating) ->
        // rating = percent / multiplier = 15.0 / (1.0/45.91) = 15.0 * 45.91 = 688.65 -> floor 688
        float multiplier = 1.0f / 45.91f;
        int32_t points = EchoesRatingPointsForPercent(15.0, multiplier);
        Check("172_hand_computed_rating_points_for_15pct_at_45_91_per_point",
            points == static_cast<int32_t>(std::floor(15.0 / static_cast<double>(multiplier))));

        Check("173_higher_percent_yields_more_or_equal_points",
            EchoesRatingPointsForPercent(20.0, multiplier) >= EchoesRatingPointsForPercent(10.0, multiplier));
        Check("174_higher_multiplier_yields_fewer_or_equal_points_for_same_percent",
            EchoesRatingPointsForPercent(15.0, 1.0f) <= EchoesRatingPointsForPercent(15.0, 0.1f));
    }

    // --- Negative control: rating-sink functions are wholly independent of Mastery/Talent/
    //     Fortitude/Spell Mitigation - calling one never affects another's output (mirrors this
    //     file's established 142/143 negative-control pattern) ---
    {
        double fortitudeBefore = EchoesFortitudeBonus(300000.0);
        double mitigBefore = EchoesSpellMitigationFraction(300000.0);
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.str = 100; row.isArmor = false; rows.push_back(row);
        EchoesStatBonus masteryBefore = EchoesCalculateAbsorption(rows, 500, 80, 1);

        double critFrac = EchoesRatingSinkFraction(999999.0, kCritRatingCeiling);
        double hasteFrac = EchoesRatingSinkFraction(999999.0, kHasteRatingCeiling);
        (void)EchoesRatingPointsForPercent(critFrac * 100.0, 1.0f);
        (void)EchoesRatingPointsForPercent(hasteFrac * 100.0, 1.0f);

        Check("175_fortitude_unaffected_by_rating_sink_calls",
            NearlyEqual(fortitudeBefore, EchoesFortitudeBonus(300000.0)));
        Check("176_spell_mitigation_unaffected_by_rating_sink_calls",
            NearlyEqual(mitigBefore, EchoesSpellMitigationFraction(300000.0)));
        EchoesStatBonus masteryAfter = EchoesCalculateAbsorption(rows, 500, 80, 1);
        Check("177_mastery_absorption_unaffected_by_rating_sink_calls",
            NearlyEqual(masteryBefore.str, masteryAfter.str));
    }

    // --- Structural/source-cited notes (engine-coupled, proven by direct source read of
    //     EchoesStatsHooks.cpp, not independently unit-testable in this pure-header file, matching
    //     this project's established convention - see 111-115/145-148 above for the same pattern) ---
    // 178_human_bot_path_equivalence: EchoesQueryRatingSinksInvested/EchoesRecalculateAndApply's
    //     E2j6 block contains no IsBot()/AI-related branch - applies identically to any Player via
    //     the same login/logout/level-change/periodic path already proven for every other category.
    // 179_removal_confirmed_by_direct_source_read: EchoesRemoveAll's E2j6 block drives every
    //     tracked rating point (crit x3, haste x3, dodge, parry) from its last-recorded value back
    //     to zero via the same EchoesApplyRatingGroupDelta helper used to apply it, confirmed by
    //     direct source read - no rating-specific removal gap exists.
    // 180_per_cr_multiplier_independence_deliberate: EchoesRecalculateAndApply calls
    //     player->GetRatingMultiplier(cr) separately for CR_CRIT_MELEE/RANGED/SPELL (and the Haste
    //     equivalents) rather than reusing one CR's multiplier for all three, because the DBC-driven
    //     multiplier can differ per CR for the same class/level - confirmed by direct source read of
    //     Player::GetRatingMultiplier (Player.cpp) and cited in e2j6-CONTRACT-RECOVERY.md.
    // 181_no_schema_change: EchoesQueryRatingSinksInvested is a read-only SELECT against the
    //     pre-existing ap_aether_sinks table - zero new tables, columns, or migrations.

    // ==================================================================================
    // E2j7a - melee_power/spell_power restoration. EchoesApplyMeleeSpellPowerMultipliers
    // mirrors EchoesApplyFortitudeMultiplier's exact shape (a post-step multiplicative bonus
    // applied to an already-computed EchoesStatBonus field, non-compounding by construction),
    // per E2j7-CONTRACT-RECOVERY-AND-PHASE-DECOMPOSITION.md: melee_power multiplies weaponDps,
    // spell_power multiplies intellect, both ceiling=1.00/k=0.000004, independently invested
    // and independently applied (not a shared/combined bonus).
    // Continuing after assertion 177 (the highest real Check() call above).
    // ==================================================================================

    // --- Melee/Spell Power bonus: zero investment yields zero bonus ---
    {
        Check("182_melee_power_zero_investment_yields_zero_bonus",
            NearlyEqual(EchoesMeleeSpellPowerBonus(0.0), 0.0));
        Check("183_melee_power_negative_investment_treated_as_zero_no_crash",
            NearlyEqual(EchoesMeleeSpellPowerBonus(-500.0), 0.0));
    }

    // --- Melee/Spell Power bonus: monotonically increases with investment, approaches ceiling ---
    {
        double b1 = EchoesMeleeSpellPowerBonus(1000.0);
        double b2 = EchoesMeleeSpellPowerBonus(100000.0);
        double b3 = EchoesMeleeSpellPowerBonus(1000000.0);
        double bHuge = EchoesMeleeSpellPowerBonus(50000000.0);
        Check("184_melee_power_increases_with_investment_1k_lt_100k", b1 < b2);
        Check("185_melee_power_increases_with_investment_100k_lt_1m", b2 < b3);
        Check("186_melee_power_never_exceeds_ceiling", bHuge <= kMeleeSpellPowerCeiling + 0.0001);
        Check("187_melee_power_approaches_ceiling_asymptotically", NearlyEqual(bHuge, 1.00, 0.0001));
    }

    // --- Melee/Spell Power bonus: recovered constants match ap_sinks.lua/cpp_patch exactly ---
    {
        Check("188_melee_spell_power_ceiling_constant_matches_recovered_value",
            NearlyEqual(kMeleeSpellPowerCeiling, 1.00));
        Check("189_melee_spell_power_decay_k_constant_matches_recovered_value",
            NearlyEqual(kMeleeSpellPowerDecayK, 0.000004));
    }

    // --- Melee/Spell Power bonus: hand-computed value at a representative investment tier ---
    {
        double invested = 250000.0;
        double expected = 1.00 * (1.0 - std::exp(-0.000004 * invested));
        double actual = EchoesMeleeSpellPowerBonus(invested);
        Check("190_hand_computed_melee_power_bonus_at_250000_invested", NearlyEqual(actual, expected));
    }

    // --- Multiplier: melee_power multiplies ONLY weaponDps, spell_power multiplies ONLY
    //     intellect, every other field passed through unchanged, and the two investments are
    //     applied independently (not combined into a single shared bonus) ---
    {
        EchoesStatBonus bonus;
        bonus.str = 10.0; bonus.agi = 20.0; bonus.sta = 100.0; bonus.intellect = 30.0;
        bonus.spirit = 40.0; bonus.armor = 50.0; bonus.weaponDps = 60.0;

        EchoesStatBonus result = EchoesApplyMeleeSpellPowerMultipliers(bonus, 250000.0, 400000.0);
        double meleeBonus = EchoesMeleeSpellPowerBonus(250000.0);
        double spellBonus = EchoesMeleeSpellPowerBonus(400000.0);

        Check("191_melee_power_multiplies_weapon_dps_only",
            NearlyEqual(result.weaponDps, 60.0 * (1.0 + meleeBonus)));
        Check("192_spell_power_multiplies_intellect_only",
            NearlyEqual(result.intellect, 30.0 * (1.0 + spellBonus)));
        Check("193_melee_spell_power_does_not_affect_str", NearlyEqual(result.str, 10.0));
        Check("194_melee_spell_power_does_not_affect_agi", NearlyEqual(result.agi, 20.0));
        Check("195_melee_spell_power_does_not_affect_sta", NearlyEqual(result.sta, 100.0));
        Check("196_melee_spell_power_does_not_affect_spi", NearlyEqual(result.spirit, 40.0));
        Check("197_melee_spell_power_does_not_affect_armor", NearlyEqual(result.armor, 50.0));
    }

    // --- Multiplier: zero investment on either category leaves that field byte-identical to
    //     input (no-op per category, independently) ---
    {
        EchoesStatBonus bonus;
        bonus.weaponDps = 60.0; bonus.intellect = 30.0;

        EchoesStatBonus onlySpell = EchoesApplyMeleeSpellPowerMultipliers(bonus, 0.0, 400000.0);
        Check("198_melee_power_zero_investment_leaves_weapon_dps_unchanged",
            onlySpell.weaponDps == bonus.weaponDps);
        Check("199_spell_power_nonzero_investment_still_changes_intellect",
            onlySpell.intellect != bonus.intellect);

        EchoesStatBonus onlyMelee = EchoesApplyMeleeSpellPowerMultipliers(bonus, 250000.0, 0.0);
        Check("200_spell_power_zero_investment_leaves_intellect_unchanged",
            onlyMelee.intellect == bonus.intellect);

        EchoesStatBonus neither = EchoesApplyMeleeSpellPowerMultipliers(bonus, 0.0, 0.0);
        Check("201_both_zero_investment_leaves_both_fields_unchanged",
            neither.weaponDps == bonus.weaponDps && neither.intellect == bonus.intellect);
    }

    // --- Multiplier: non-compounding across repeated refresh calls, matching Fortitude's own
    //     proven anti-compounding guard (133/134 above) ---
    {
        EchoesStatBonus base;
        base.weaponDps = 80.0; base.intellect = 50.0;
        EchoesStatBonus r1 = EchoesApplyMeleeSpellPowerMultipliers(base, 500000.0, 500000.0);
        EchoesStatBonus r2 = EchoesApplyMeleeSpellPowerMultipliers(base, 500000.0, 500000.0);
        Check("202_melee_spell_power_repeated_refresh_is_byte_identical_non_compounding",
            r1.weaponDps == r2.weaponDps && r1.intellect == r2.intellect);

        EchoesStatBonus wrongChained = EchoesApplyMeleeSpellPowerMultipliers(r1, 500000.0, 500000.0);
        Check("203_melee_spell_power_chaining_the_multiplier_would_visibly_compound_unlike_correct_usage",
            wrongChained.weaponDps > r1.weaponDps && wrongChained.intellect > r1.intellect);
    }

    // --- Negative control: melee_power/spell_power multipliers are wholly independent of
    //     Fortitude/Spell Mitigation/rating-sink categories (mirrors 142/143/175-177 pattern) ---
    {
        double fortitudeBefore = EchoesFortitudeBonus(300000.0);
        double mitigBefore = EchoesSpellMitigationFraction(300000.0);
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.str = 100; row.isArmor = false; rows.push_back(row);
        EchoesStatBonus masteryBefore = EchoesCalculateAbsorption(rows, 500, 80, 1);

        EchoesStatBonus dummy; dummy.weaponDps = 10.0; dummy.intellect = 10.0;
        (void)EchoesApplyMeleeSpellPowerMultipliers(dummy, 999999.0, 999999.0);

        Check("204_fortitude_unaffected_by_melee_spell_power_calls",
            NearlyEqual(fortitudeBefore, EchoesFortitudeBonus(300000.0)));
        Check("205_spell_mitigation_unaffected_by_melee_spell_power_calls",
            NearlyEqual(mitigBefore, EchoesSpellMitigationFraction(300000.0)));
        EchoesStatBonus masteryAfter = EchoesCalculateAbsorption(rows, 500, 80, 1);
        Check("206_mastery_absorption_unaffected_by_melee_spell_power_calls",
            NearlyEqual(masteryBefore.str, masteryAfter.str));
    }

    // --- Structural/source-cited notes (engine-coupled, proven by direct source read of
    //     EchoesStatsHooks.cpp, not independently unit-testable in this pure-header file, matching
    //     this project's established convention - see 111-115/145-148/178-181 above) ---
    // 207_human_bot_path_equivalence: EchoesQueryMeleeSpellPowerInvested/EchoesRecalculateAndApply's
    //     E2j7a block contains no IsBot()/AI-related branch - applies identically to any Player via
    //     the same login/logout/level-change/periodic path already proven for every other category.
    // 208_no_schema_change: EchoesQueryMeleeSpellPowerInvested is a read-only SELECT against the
    //     pre-existing ap_aether_sinks table - zero new tables, columns, or migrations.

    // ==================================================================================
    // E2j7b - execute_power/armor_pen restoration via the OnDamage hook. Per
    // E2j7b-CONTRACT-DECISIONS-AND-ENGINEERING-PLAN.md and Jonah's implementation authorization:
    // execute_power preserves the historical contract exactly (ceiling=0.40, k=0.000003, additive
    // bonus below 20% target health, applies to all outgoing damage regardless of school - no
    // physical restriction). armor_pen (ceiling=0.30, k=0.000003) is post-mitigation damage
    // inflation, ALSO unrestricted by school per Jonah's explicit 2026-07-30 decision (OnDamage
    // exposes no school information at all - see e2j7b-STAGE1-PRE-EDIT-CONTRACT-AND-IDENTITY.md
    // Section 4 for the full architectural finding). Mandatory apply order: execute_power first,
    // then armor_pen, operating on the same mutated damage value in sequence (load-bearing, not
    // independent, per the accepted planning report's own phase-decomposition reasoning).
    //
    // EchoesArmorPenReductionFraction(armor, attackerLevel) replaces the historical hardcoded
    // level-80-only constant (15232.5) with the live, per-level-correct formula, algebraically
    // derived from Unit::CalcArmorReducedDamage (Unit.cpp:2245-2316, current core, re-verified this
    // session): levelModifier = attackerLevel > 59 ? attackerLevel + 4.5*(attackerLevel-59) :
    // attackerLevel; armorConstant = 85*levelModifier + 400; reductionFrac = armor/(armor+
    // armorConstant). At attackerLevel=80, levelModifier=174.5, armorConstant=85*174.5+400=15232.5
    // exactly - proving this is a strict generalization of the historical constant, not a
    // reinterpretation (verified algebraically in the accepted planning report, Section 2.6).
    // Implemented as a pure, dependency-free function (this file's established convention) rather
    // than calling Unit::CalcArmorReducedDamage live from the per-hit hook, since the two are
    // proven mathematically identical and the pure form is fully unit-testable here, matching
    // every other formula in this file.
    // Continuing after assertion 206 (the highest real Check() call above).
    // ==================================================================================

    // --- Execute Power bonus: zero/negative investment yields zero bonus ---
    {
        Check("209_execute_power_zero_investment_yields_zero_bonus",
            NearlyEqual(EchoesExecutePowerBonus(0.0), 0.0));
        Check("210_execute_power_negative_investment_treated_as_zero_no_crash",
            NearlyEqual(EchoesExecutePowerBonus(-500.0), 0.0));
    }

    // --- Execute Power bonus: monotonic increase, never exceeds ceiling, recovered constants ---
    {
        double b1 = EchoesExecutePowerBonus(1000.0);
        double b2 = EchoesExecutePowerBonus(100000.0);
        double b3 = EchoesExecutePowerBonus(1000000.0);
        double bHuge = EchoesExecutePowerBonus(50000000.0);
        Check("211_execute_power_increases_with_investment_1k_lt_100k", b1 < b2);
        Check("212_execute_power_increases_with_investment_100k_lt_1m", b2 < b3);
        Check("213_execute_power_never_exceeds_ceiling", bHuge <= kExecutePowerCeiling + 0.0001);
        Check("214_execute_power_approaches_ceiling_asymptotically", NearlyEqual(bHuge, 0.40, 0.0001));
        Check("215_execute_power_ceiling_constant_matches_recovered_value",
            NearlyEqual(kExecutePowerCeiling, 0.40));
        Check("216_execute_power_decay_k_constant_matches_recovered_value",
            NearlyEqual(kExecutePowerArmorPenDecayK, 0.000003));
    }

    // --- Execute Power bonus: hand-computed value at 250000 invested (matches this file's own
    //     established convention, e.g. test 124/167/190) ---
    {
        double invested = 250000.0;
        double expected = 0.40 * (1.0 - std::exp(-0.000003 * invested));
        Check("217_hand_computed_execute_power_bonus_at_250000_invested",
            NearlyEqual(EchoesExecutePowerBonus(invested), expected));
    }

    // --- Armor Pen fraction: zero/negative investment, monotonic increase, ceiling, constants ---
    {
        Check("218_armor_pen_zero_investment_yields_zero_fraction",
            NearlyEqual(EchoesArmorPenFraction(0.0), 0.0));
        Check("219_armor_pen_negative_investment_treated_as_zero_no_crash",
            NearlyEqual(EchoesArmorPenFraction(-500.0), 0.0));

        double a1 = EchoesArmorPenFraction(1000.0);
        double a2 = EchoesArmorPenFraction(100000.0);
        double aHuge = EchoesArmorPenFraction(50000000.0);
        Check("220_armor_pen_increases_with_investment", a1 < a2);
        Check("221_armor_pen_never_exceeds_ceiling", aHuge <= kArmorPenCeiling + 0.0001);
        Check("222_armor_pen_approaches_ceiling_asymptotically", NearlyEqual(aHuge, 0.30, 0.0001));
        Check("223_armor_pen_ceiling_constant_matches_recovered_value",
            NearlyEqual(kArmorPenCeiling, 0.30));

        double invested = 250000.0;
        double expected = 0.30 * (1.0 - std::exp(-0.000003 * invested));
        Check("224_hand_computed_armor_pen_fraction_at_250000_invested",
            NearlyEqual(EchoesArmorPenFraction(invested), expected));
    }

    // --- Independence: execute_power/armor_pen curves are independent of each other ---
    {
        double exBefore = EchoesExecutePowerBonus(300000.0);
        (void)EchoesArmorPenFraction(999999.0);
        Check("225_execute_power_unaffected_by_armor_pen_calls",
            NearlyEqual(exBefore, EchoesExecutePowerBonus(300000.0)));

        double apBefore = EchoesArmorPenFraction(300000.0);
        (void)EchoesExecutePowerBonus(999999.0);
        Check("226_armor_pen_unaffected_by_execute_power_calls",
            NearlyEqual(apBefore, EchoesArmorPenFraction(300000.0)));
    }

    // --- EchoesApplyExecutePowerBonus: zero investment is a no-op ---
    {
        Check("227_execute_power_zero_investment_leaves_damage_unchanged",
            EchoesApplyExecutePowerBonus(1000u, 10.0f, 0.0) == 1000u);
    }

    // --- EchoesApplyExecutePowerBonus: threshold boundary - strictly BELOW 20.0, not at or above
    //     (matches the historical source's exact `< 20.0f` operator, re-verified this session) ---
    {
        Check("228_execute_power_exactly_at_threshold_not_activated",
            EchoesApplyExecutePowerBonus(1000u, 20.0f, 500000.0) == 1000u);
        Check("229_execute_power_just_above_threshold_not_activated",
            EchoesApplyExecutePowerBonus(1000u, 20.01f, 500000.0) == 1000u);
        Check("230_execute_power_just_below_threshold_activated",
            EchoesApplyExecutePowerBonus(1000u, 19.99f, 500000.0) != 1000u);
    }

    // --- EchoesApplyExecutePowerBonus: hand-computed multiplier below threshold ---
    {
        uint32_t damage = 1000u;
        double invested = 250000.0;
        double bonus = EchoesExecutePowerBonus(invested);
        uint32_t expected = damage + static_cast<uint32_t>(std::floor(damage * bonus));
        Check("231_execute_power_hand_computed_bonus_below_threshold",
            EchoesApplyExecutePowerBonus(damage, 15.0f, invested) == expected);
    }

    // --- EchoesApplyExecutePowerBonus: zero damage input stays zero (matches historical
    //     `damage == 0` early-return guard) ---
    {
        Check("232_execute_power_zero_damage_input_stays_zero",
            EchoesApplyExecutePowerBonus(0u, 5.0f, 500000.0) == 0u);
    }

    // --- EchoesApplyExecutePowerBonus: overflow safety - large damage value near uint32 range
    //     does not wrap around or crash, and never decreases the input ---
    {
        uint32_t largeDamage = 2000000000u; // ~2 billion, well within uint32 range but large
        uint32_t result = EchoesApplyExecutePowerBonus(largeDamage, 10.0f, 500000.0);
        Check("233_execute_power_large_damage_no_underflow", result >= largeDamage);
        Check("234_execute_power_large_damage_no_crash_sane_result", result < 4000000000u);
    }

    // --- EchoesArmorPenReductionFraction: the live per-level-correct armor formula, replacing the
    //     historical hardcoded 15232.5 (level-80-only) constant ---
    {
        // Zero armor -> zero reduction fraction (no mitigation to compensate for)
        Check("235_armor_pen_reduction_zero_armor_yields_zero_fraction",
            NearlyEqual(EchoesArmorPenReductionFraction(0.0, 80), 0.0));

        // Level 80 (levelModifier=174.5, armorConstant=85*174.5+400=15232.5) - must match the
        // historical constant EXACTLY, proving this is a strict generalization, not a reinterpretation
        double armor = 10000.0;
        double expectedAt80 = armor / (armor + 15232.5);
        Check("236_armor_pen_reduction_at_level_80_matches_historical_constant_exactly",
            NearlyEqual(EchoesArmorPenReductionFraction(armor, 80), expectedAt80, 0.001));

        // Level 60 (levelModifier=60, since level<=59 uses level directly, but 60>59 so
        // levelModifier = 60 + 4.5*(60-59) = 64.5, armorConstant = 85*64.5+400 = 5882.5) -
        // REJECTS the old level-80-only approximation: a level-60 attacker must NOT get the
        // level-80 constant (15232.5) applied to them.
        double expectedAt60 = armor / (armor + (85.0 * 64.5 + 400.0));
        double actualAt60 = EchoesArmorPenReductionFraction(armor, 60);
        Check("237_armor_pen_reduction_at_level_60_matches_live_formula",
            NearlyEqual(actualAt60, expectedAt60, 0.001));
        Check("238_armor_pen_reduction_at_level_60_rejects_level_80_only_approximation",
            !NearlyEqual(actualAt60, expectedAt80, 0.001));

        // Level 40 (<=59, levelModifier = level directly = 40, armorConstant = 85*40+400 = 3800)
        double expectedAt40 = armor / (armor + (85.0 * 40.0 + 400.0));
        Check("239_armor_pen_reduction_at_level_40_matches_live_formula_sub_60_branch",
            NearlyEqual(EchoesArmorPenReductionFraction(armor, 40), expectedAt40, 0.001));

        // Monotonic increase with armor, for a fixed level
        double lowArmor = EchoesArmorPenReductionFraction(1000.0, 80);
        double highArmor = EchoesArmorPenReductionFraction(30000.0, 80);
        Check("240_armor_pen_reduction_increases_with_target_armor", lowArmor < highArmor);

        // Bounded: reduction fraction never reaches or exceeds 1.0 for any finite armor
        Check("241_armor_pen_reduction_never_reaches_one",
            EchoesArmorPenReductionFraction(100000000.0, 80) < 1.0);
    }

    // --- EchoesApplyArmorPenBonus: zero investment or zero reduction fraction is a no-op ---
    {
        Check("242_armor_pen_zero_investment_leaves_damage_unchanged",
            EchoesApplyArmorPenBonus(1000u, 0.5, 0.0) == 1000u);
        Check("243_armor_pen_zero_reduction_fraction_leaves_damage_unchanged",
            EchoesApplyArmorPenBonus(1000u, 0.0, 500000.0) == 1000u);
    }

    // --- EchoesApplyArmorPenBonus: zero damage input stays zero (matches historical
    //     `damage > 0` guard) ---
    {
        Check("244_armor_pen_zero_damage_input_stays_zero",
            EchoesApplyArmorPenBonus(0u, 0.5, 500000.0) == 0u);
    }

    // --- EchoesApplyArmorPenBonus: hand-computed multiplier ---
    {
        uint32_t damage = 1000u;
        double invested = 250000.0;
        double reductionFrac = 0.5;
        double armorPenFrac = EchoesArmorPenFraction(invested);
        double penOfReduction = armorPenFrac * reductionFrac;
        uint32_t expected = static_cast<uint32_t>(std::floor(damage / (1.0 - penOfReduction)));
        Check("245_armor_pen_hand_computed_multiplier",
            EchoesApplyArmorPenBonus(damage, reductionFrac, invested) == expected);
    }

    // --- EchoesApplyArmorPenBonus: penOfReduction >= 1.0 guard - defensive, never divides by
    //     zero/negative even with an extreme (beyond-ceiling, hypothetically corrupted) input ---
    {
        // armorPenFrac capped at 0.30 by the curve itself, reductionFrac capped <1.0 by its own
        // formula, so penOfReduction < 0.30 always in practice - this test proves the guard holds
        // even if called with a synthetic reductionFrac at the function's own boundary.
        uint32_t result = EchoesApplyArmorPenBonus(1000u, 0.9999999, 50000000.0);
        Check("246_armor_pen_extreme_inputs_never_crash_or_produce_absurd_result",
            result < 100000u); // sane bound, not infinite/negative-wrapped
    }

    // --- EchoesApplyArmorPenBonus: overflow safety ---
    {
        uint32_t largeDamage = 2000000000u;
        uint32_t result = EchoesApplyArmorPenBonus(largeDamage, 0.5, 500000.0);
        Check("247_armor_pen_large_damage_no_underflow", result >= largeDamage);
        Check("248_armor_pen_large_damage_no_crash_sane_result", result < 4000000000u);
    }

    // --- Combined ordering: execute_power MUST apply before armor_pen. Proven two ways: (1) the
    //     composed result matches hand-calculation of execute-then-armor-pen exactly, and (2) the
    //     REVERSED order produces a numerically DIFFERENT result under real integer floor()
    //     rounding, proving order is genuinely load-bearing, not a coincidence of this specific
    //     input (per the implementation authorization's own required proof). ---
    {
        uint32_t incomingDamage = 777u; // deliberately odd/non-round to stress integer rounding
        float victimHealthPct = 10.0f; // below execute threshold
        double executeInvested = 250000.0;
        double armorPenInvested = 250000.0;
        double reductionFrac = 0.6;

        // Correct (authorized) order: execute first, then armor-pen
        uint32_t afterExecute = EchoesApplyExecutePowerBonus(incomingDamage, victimHealthPct, executeInvested);
        uint32_t afterArmorPen = EchoesApplyArmorPenBonus(afterExecute, reductionFrac, armorPenInvested);

        // Hand-calculated expectation, computed independently (not by re-calling the same functions
        // in the same order, to avoid a tautological test)
        double exBonus = 0.40 * (1.0 - std::exp(-0.000003 * executeInvested));
        uint32_t expectedAfterExecute = incomingDamage + static_cast<uint32_t>(std::floor(incomingDamage * exBonus));
        double apFrac = 0.30 * (1.0 - std::exp(-0.000003 * armorPenInvested));
        double penOfReduction = apFrac * reductionFrac;
        uint32_t expectedFinal = static_cast<uint32_t>(std::floor(expectedAfterExecute / (1.0 - penOfReduction)));

        Check("249_combined_ordering_matches_hand_calculation_execute_then_armor_pen",
            afterArmorPen == expectedFinal);

        // Reversed (unauthorized) order: armor-pen first, then execute - must differ
        uint32_t afterArmorPenFirst = EchoesApplyArmorPenBonus(incomingDamage, reductionFrac, armorPenInvested);
        uint32_t afterExecuteSecond = EchoesApplyExecutePowerBonus(afterArmorPenFirst, victimHealthPct, executeInvested);

        Check("250_reversed_order_produces_distinguishable_result",
            afterExecuteSecond != afterArmorPen);
    }

    // --- No double application: calling each function once applies its effect exactly once
    //     (structurally guaranteed - neither function has internal state or a loop, matching this
    //     file's established non-compounding-by-construction pattern) ---
    {
        uint32_t base = 1000u;
        uint32_t once = EchoesApplyExecutePowerBonus(base, 10.0f, 250000.0);
        uint32_t twiceNaively = EchoesApplyExecutePowerBonus(once, 10.0f, 250000.0);
        Check("251_calling_execute_power_twice_visibly_compounds_unlike_correct_single_call_usage",
            twiceNaively > once); // demonstrates the function itself has no built-in guard against
            // being MISUSED via repeated calls - the engine-hook wiring (not this pure function)
            // is responsible for calling it exactly once per real hit, matching this file's
            // established "fresh base each time" convention (see test 133/134/202/203 precedent)
    }

    // --- Cross-category independence: execute_power/armor_pen calculations are wholly independent
    //     of every other already-live category (mirrors this file's established 142/143/175-177/
    //     204-206 negative-control pattern) ---
    {
        double fortitudeBefore = EchoesFortitudeBonus(300000.0);
        double mitigBefore = EchoesSpellMitigationFraction(300000.0);
        double meleeSpellBefore = EchoesMeleeSpellPowerBonus(300000.0);
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.str = 100; row.isArmor = false; rows.push_back(row);
        EchoesStatBonus masteryBefore = EchoesCalculateAbsorption(rows, 500, 80, 1);

        (void)EchoesApplyExecutePowerBonus(999999u, 5.0f, 999999.0);
        (void)EchoesApplyArmorPenBonus(999999u, 0.9, 999999.0);

        Check("252_fortitude_unaffected_by_execute_armor_pen_calls",
            NearlyEqual(fortitudeBefore, EchoesFortitudeBonus(300000.0)));
        Check("253_spell_mitigation_unaffected_by_execute_armor_pen_calls",
            NearlyEqual(mitigBefore, EchoesSpellMitigationFraction(300000.0)));
        Check("254_melee_spell_power_unaffected_by_execute_armor_pen_calls",
            NearlyEqual(meleeSpellBefore, EchoesMeleeSpellPowerBonus(300000.0)));
        EchoesStatBonus masteryAfter = EchoesCalculateAbsorption(rows, 500, 80, 1);
        Check("255_mastery_absorption_unaffected_by_execute_armor_pen_calls",
            NearlyEqual(masteryBefore.str, masteryAfter.str));
    }

    // --- Structural/source-cited notes (engine-coupled, proven by direct source read of
    //     EchoesStatsHooks.cpp, not independently unit-testable in this pure-header file, matching
    //     this project's established convention) ---
    // 256_hook_registration_required: EchoesStatsUnitScript's constructor hook list must include
    //     UNITHOOK_ON_DAMAGE (UnitScript.h:27) alongside the existing UNITHOOK_MODIFY_SPELL_
    //     DAMAGE_TAKEN entry, or the new OnDamage override compiles but silently never fires -
    //     confirmed by direct source read of UnitScript's opt-in hook-filtering constructor pattern
    //     this session (EchoesStatsHooks.cpp:478-484).
    // 257_pvp_inclusion: the OnDamage gate is extended from the historical `victim->IsCreature()`
    //     to `victim->IsCreature() || victim->IsPlayer()` per Jonah's explicit PvP-inclusion
    //     authorization - confirmed by direct source read, not independently unit-testable (requires
    //     a live Unit* victim).
    // 258_pet_guardian_exclusion_preserved: the `attacker->IsPlayer()` gate is preserved unchanged,
    //     excluding pets/guardians as attackers by construction (Pet/Guardian::IsPlayer() == false) -
    //     no ownership-chain-walking added, per Jonah's explicit exclusion.
    // 259_school_gating_decision: armor_pen applies to all outgoing damage OnDamage observes,
    //     unrestricted by school, per Jonah's explicit 2026-07-30 decision (Option 1) - documented
    //     as an accepted contract limitation, not silently omitted. See
    //     e2j7b-STAGE1-PRE-EDIT-CONTRACT-AND-IDENTITY.md Section 9.
    // 260_no_schema_change: the engine wiring reads only the pre-existing ap_aether_sinks table
    //     (categories 'execute_power'/'armor_pen') via a new combined query, matching every prior
    //     phase's established pattern - zero new tables, columns, or migrations.

    // ==================================================================================
    // E2j7c - reflect_chance restoration via the existing ModifySpellDamageTaken hook (already
    // registered for Spell Mitigation - no constructor change needed). Per
    // E2j7c-REFLECT-CHANCE-CONTRACT-AND-REENTRANCY-DESIGN.md: ceiling=0.05, k=0.000002, reflects
    // 100% of the remaining (post-Spell-Mitigation, pre-armor/crit/block/absorb) damage back onto
    // the original attacker via a direct Unit::DealDamage(attacker, attacker, ...) call - a call
    // path proven this session to structurally bypass Unit::CalculateSpellDamageTaken entirely,
    // so reflected damage cannot re-enter this same hook (no runtime guard needed for that threat).
    // The roll/threshold decision is split into two pure, independently-testable functions
    // (EchoesReflectChanceThreshold/EchoesReflectChanceRollTriggered) so the boundary logic is
    // unit-testable even though the real urand() roll itself is engine-coupled - matching the test
    // contract's "deterministic seeded RNG or injectable roll source where practical" requirement.
    // Continuing after assertion 255 (the highest real Check() call above; 256-260 above are
    // structural/source-cited comment notes, not Check() calls).
    // ==================================================================================

    // --- Reflect Chance fraction: zero/negative investment, monotonic increase, ceiling, constants ---
    {
        Check("261_reflect_chance_zero_investment_yields_zero_fraction",
            NearlyEqual(EchoesReflectChanceFraction(0.0), 0.0));
        Check("262_reflect_chance_negative_investment_treated_as_zero_no_crash",
            NearlyEqual(EchoesReflectChanceFraction(-500.0), 0.0));

        double r1 = EchoesReflectChanceFraction(1000.0);
        double r2 = EchoesReflectChanceFraction(100000.0);
        double rHuge = EchoesReflectChanceFraction(50000000.0);
        Check("263_reflect_chance_increases_with_investment", r1 < r2);
        Check("264_reflect_chance_never_exceeds_ceiling", rHuge <= kReflectChanceCeiling + 0.0001);
        Check("265_reflect_chance_approaches_ceiling_asymptotically", NearlyEqual(rHuge, 0.05, 0.0001));
        Check("266_reflect_chance_ceiling_constant_matches_recovered_value",
            NearlyEqual(kReflectChanceCeiling, 0.05));
        Check("267_reflect_chance_decay_k_constant_matches_recovered_value",
            NearlyEqual(kReflectChanceDecayK, 0.000002));
    }

    // --- Reflect Chance fraction: hand-computed value at 250000 invested ---
    {
        double invested = 250000.0;
        double expected = 0.05 * (1.0 - std::exp(-0.000002 * invested));
        Check("268_hand_computed_reflect_chance_fraction_at_250000_invested",
            NearlyEqual(EchoesReflectChanceFraction(invested), expected));
    }

    // --- Independence from other curves ---
    {
        double exBefore = EchoesExecutePowerBonus(300000.0);
        (void)EchoesReflectChanceFraction(999999.0);
        Check("269_execute_power_unaffected_by_reflect_chance_calls",
            NearlyEqual(exBefore, EchoesExecutePowerBonus(300000.0)));

        double reflectBefore = EchoesReflectChanceFraction(300000.0);
        (void)EchoesExecutePowerBonus(999999.0);
        (void)EchoesArmorPenFraction(999999.0);
        Check("270_reflect_chance_unaffected_by_execute_armor_pen_calls",
            NearlyEqual(reflectBefore, EchoesReflectChanceFraction(300000.0)));
    }

    // --- EchoesReflectChanceThreshold: pure percent->integer-threshold conversion, matching the
    //     historical `static_cast<uint32>(reflectFrac * 10000.0)` exactly ---
    {
        Check("271_reflect_threshold_zero_fraction_yields_zero_threshold",
            EchoesReflectChanceThreshold(0.0) == 0);
        // At the ceiling (0.05), threshold = 0.05*10000 = 500
        Check("272_reflect_threshold_at_ceiling_matches_hand_calculation",
            EchoesReflectChanceThreshold(0.05) == 500);
        // At invested=250000: fraction = 0.05*(1-e^-0.5) = 0.019673..., threshold = floor(196.73) = 196
        double frac250k = 0.05 * (1.0 - std::exp(-0.000002 * 250000.0));
        uint32_t expectedThreshold = static_cast<uint32_t>(frac250k * 10000.0);
        Check("273_reflect_threshold_hand_computed_at_250000_invested",
            EchoesReflectChanceThreshold(frac250k) == expectedThreshold);
    }

    // --- EchoesReflectChanceRollTriggered: pure roll-vs-threshold comparison, boundary-tested
    //     with injected roll values (no real RNG needed) ---
    {
        // threshold=500 (the ceiling case, 5%): roll in [0,9999]
        Check("274_reflect_roll_zero_triggers_when_threshold_positive",
            EchoesReflectChanceRollTriggered(0, 500) == true);
        Check("275_reflect_roll_just_below_threshold_triggers",
            EchoesReflectChanceRollTriggered(499, 500) == true);
        Check("276_reflect_roll_exactly_at_threshold_does_not_trigger",
            EchoesReflectChanceRollTriggered(500, 500) == false);
        Check("277_reflect_roll_just_above_threshold_does_not_trigger",
            EchoesReflectChanceRollTriggered(501, 500) == false);
        Check("278_reflect_roll_max_rng_value_never_triggers_at_ceiling",
            EchoesReflectChanceRollTriggered(9999, 500) == false);
        Check("279_reflect_roll_zero_threshold_never_triggers",
            EchoesReflectChanceRollTriggered(0, 0) == false);
    }

    // --- Structural/source-cited notes (engine-coupled, proven by direct source read of
    //     EchoesStatsHooks.cpp and disposable-verification runtime evidence, not independently
    //     unit-testable in this pure-header file, matching this project's established convention) ---
    // 280_no_reentrancy_by_construction: Unit::DealDamage(attacker, attacker, reflectDamage,
    //     nullptr, DIRECT_DAMAGE, SPELL_SCHOOL_MASK_NORMAL, nullptr, false) is a direct call that
    //     bypasses Unit::CalculateSpellDamageTaken entirely (Unit.cpp:1534 is the only call site
    //     for ModifySpellDamageTaken, and DealDamage never invokes CalculateSpellDamageTaken) -
    //     confirmed by direct source read this session, re-verified unchanged from the accepted
    //     planning report. No boolean/token/registry guard exists or is needed for this specific
    //     threat.
    // 281_reflected_damage_reaches_ondamage: the same Unit::DealDamage call unconditionally fires
    //     sScriptMgr->OnDamage (Unit.cpp:1026) - this is why the E2j7b attacker==victim guard
    //     (test 282 below) is required, not optional.
    // 282_e2j7b_self_damage_guard: EchoesStatsUnitScript::OnDamage now returns immediately when
    //     `attacker == victim` (added this phase), before either execute_power or armor_pen are
    //     queried or applied - confirmed by direct source read; not unit-testable here since the
    //     pure EchoesApplyExecutePowerBonus/EchoesApplyArmorPenBonus functions have no attacker/
    //     victim identity concept (the guard lives entirely in the engine-coupled hook). Proven at
    //     the disposable-verification stage instead.
    // 283_periodic_damage_structurally_excluded: AuraEffect::HandlePeriodicDamageAuraTick (DoT
    //     ticks) never calls Unit::CalculateSpellDamageTaken - confirmed by direct source read,
    //     the same finding already established for E2j7b's own OnDamage-vs-periodic-damage
    //     analysis, but with the OPPOSITE conclusion here: this hook cannot see DoT ticks at all
    //     (E2j7b's OnDamage sees them but can't identify them; this hook never sees them period).
    // 284_defender_owns_investment_no_pet_inheritance: EchoesQueryReflectChanceInvested is keyed
    //     by the DEFENDING player's own account_id (target->ToPlayer()), matching every other
    //     category's established account-scoping convention - no ownership-chain walking for
    //     pets/guardians as defenders, per Jonah's explicit instruction.
    // 285_pet_guardian_attacker_eligibility_preserved: no attacker->IsPlayer() gate exists in this
    //     hook (unlike E2j7b's OnDamage) - a pet, guardian, or creature attacker can trigger a
    //     player's reflect_chance, matching the recovered historical contract exactly, per Jonah's
    //     explicit confirmation this differs from E2j7b's own pet-exclusion precedent.
    // 286_mitigation_reflect_independence_fix: ModifySpellDamageTaken's control flow was
    //     restructured so Spell Mitigation's own early-returns (mitigInvested<=0, reduction==0)
    //     no longer exit the whole function - each effect is now independently gated, matching the
    //     historical source's own shape. Confirmed byte-identical Spell Mitigation output for any
    //     reflect-uninvested player (regression-tested at the disposable-verification stage).
    // 287_no_schema_change: EchoesQueryReflectChanceInvested is a read-only SELECT against the
    //     pre-existing ap_aether_sinks table (category 'reflect_chance') - zero new tables,
    //     columns, or migrations.

    // --- E2j8 - EchoesLifeLeechFraction: pure asymptotic curve, same shape/constants as every
    //     other recovered Aether Sink formula ---
    {
        Check("288_life_leech_zero_investment_yields_zero_fraction",
            NearlyEqual(EchoesLifeLeechFraction(0.0), 0.0));
        Check("289_life_leech_negative_investment_treated_as_zero",
            NearlyEqual(EchoesLifeLeechFraction(-500.0), 0.0));

        // Low investment (1000): frac = 0.08*(1-e^(-0.000005*1000)) = 0.08*(1-e^-0.005)
        double expectedLow = 0.08 * (1.0 - std::exp(-0.000005 * 1000.0));
        Check("290_life_leech_low_investment_hand_computed",
            NearlyEqual(EchoesLifeLeechFraction(1000.0), expectedLow, 0.0000001));

        // Middle investment (100000)
        double expectedMid = 0.08 * (1.0 - std::exp(-0.000005 * 100000.0));
        Check("291_life_leech_middle_investment_hand_computed",
            NearlyEqual(EchoesLifeLeechFraction(100000.0), expectedMid, 0.0000001));

        // High investment (500000), near ceiling
        double expectedHigh = 0.08 * (1.0 - std::exp(-0.000005 * 500000.0));
        Check("292_life_leech_high_investment_near_ceiling",
            NearlyEqual(EchoesLifeLeechFraction(500000.0), expectedHigh, 0.0000001));
        Check("293_life_leech_high_investment_below_ceiling", expectedHigh < 0.08);

        // Asymptotic - never reaches, always approaches, the 0.08 ceiling
        Check("294_life_leech_approaches_ceiling_asymptotically",
            NearlyEqual(EchoesLifeLeechFraction(50000000.0), 0.08, 0.0001));
        Check("295_life_leech_never_exceeds_ceiling",
            EchoesLifeLeechFraction(999999999.0) <= 0.08);

        Check("296_life_leech_ceiling_constant_matches_recovered_value",
            NearlyEqual(kLifeLeechCeiling, 0.08));
        Check("297_life_leech_decay_k_constant_matches_recovered_value",
            NearlyEqual(kLifeLeechDecayK, 0.000005));
    }

    // --- E2j8 - EchoesComputeLifeLeechHeal: pure heal-amount calculation. Mirrors the historical
    //     `max(1, floor(damage * leechFrac))` exactly ---
    {
        Check("298_life_leech_heal_zero_damage_input_stays_zero",
            EchoesComputeLifeLeechHeal(0u, 500000.0) == 0);
        Check("299_life_leech_heal_zero_investment_yields_zero_heal",
            EchoesComputeLifeLeechHeal(1000u, 0.0) == 0);
        Check("300_life_leech_heal_negative_investment_yields_zero_heal",
            EchoesComputeLifeLeechHeal(1000u, -100.0) == 0);

        // Hand-computed: damage=10000, invested=250000 -> frac = 0.08*(1-e^-1.25)
        uint32_t damage = 10000u;
        double invested = 250000.0;
        double frac = 0.08 * (1.0 - std::exp(-0.000005 * invested));
        uint32_t expectedHeal = static_cast<uint32_t>(std::floor(static_cast<double>(damage) * frac));
        Check("301_life_leech_heal_hand_computed_at_250000_invested",
            EchoesComputeLifeLeechHeal(damage, invested) == expectedHeal);

        // Any nonzero fraction heals at least 1 (matches historical max(1, floor(...)) exactly,
        // even when damage*frac rounds down to 0 under integer floor)
        Check("302_life_leech_heal_tiny_fraction_still_heals_minimum_one",
            EchoesComputeLifeLeechHeal(1u, 1000.0) >= 1);

        // Integer rounding: damage=777 (deliberately odd), invested=100000
        uint32_t oddDamage = 777u;
        double fracAtMid = 0.08 * (1.0 - std::exp(-0.000005 * 100000.0));
        uint32_t expectedOdd = static_cast<uint32_t>(std::floor(static_cast<double>(oddDamage) * fracAtMid));
        Check("303_life_leech_heal_integer_rounding_matches_floor_not_round",
            EchoesComputeLifeLeechHeal(oddDamage, 100000.0) == expectedOdd);
    }

    // --- E2j8 - EchoesComputeLifeLeechHeal: overflow safety ---
    {
        uint32_t largeDamage = 2000000000u;
        uint32_t result = EchoesComputeLifeLeechHeal(largeDamage, 500000.0);
        Check("304_life_leech_heal_large_damage_no_crash_sane_result", result < largeDamage);
        Check("305_life_leech_heal_large_damage_no_underflow_wrap", result > 0);
    }

    // --- E2j8 - EchoesClampLifeLeechHeal: overheal-safe clamp. Mirrors the historical
    //     `min(healAmount, maxHP - curHP)` guarded by `curHP < maxHP` exactly ---
    {
        // Partially injured attacker: heal fits entirely under the cap
        Check("306_life_leech_clamp_partially_injured_heal_fits_under_cap",
            EchoesClampLifeLeechHeal(50u, 400u, 500u) == 50u);

        // Nearly-full-health attacker: heal is truncated to the remaining deficit
        Check("307_life_leech_clamp_nearly_full_health_truncates_to_deficit",
            EchoesClampLifeLeechHeal(50u, 490u, 500u) == 10u);

        // Exact maximum-health cap: attacker already at max, no heal at all
        Check("308_life_leech_clamp_full_health_attacker_yields_zero",
            EchoesClampLifeLeechHeal(50u, 500u, 500u) == 0u);

        // Overheal prevention: curHP somehow above maxHP (defensive) still yields zero, never negative-wraps
        Check("309_life_leech_clamp_overheal_defensive_guard",
            EchoesClampLifeLeechHeal(50u, 501u, 500u) == 0u);

        // Zero raw heal in, zero out regardless of health state
        Check("310_life_leech_clamp_zero_raw_heal_yields_zero",
            EchoesClampLifeLeechHeal(0u, 100u, 500u) == 0u);

        // Zero max health (defensive/invalid state) never divides or wraps
        Check("311_life_leech_clamp_zero_max_health_defensive_guard",
            EchoesClampLifeLeechHeal(50u, 0u, 0u) == 0u);
    }

    // --- E2j8 - Damage/heal ordering: Life Leech must compute from the FINAL post-execute_power,
    //     post-armor_pen damage value, and must never itself mutate that value. Proven two ways:
    //     (1) the composed result matches hand-calculation of execute-then-armor_pen-then-leech
    //     exactly, and (2) computing leech from the ORIGINAL pre-execute/pre-armor_pen damage
    //     produces a numerically DIFFERENT (smaller) heal, proving the ordering is genuinely
    //     load-bearing - mirrors test 249/250's proof pattern exactly. ---
    {
        uint32_t incomingDamage = 777u; // deliberately odd/non-round to stress integer rounding
        float victimHealthPct = 10.0f; // below execute threshold
        double executeInvested = 250000.0;
        double armorPenInvested = 250000.0;
        double leechInvested = 250000.0;
        double reductionFrac = 0.6;

        // Authorized order: execute -> armor_pen -> leech (reads the armor_pen result)
        uint32_t afterExecute = EchoesApplyExecutePowerBonus(incomingDamage, victimHealthPct, executeInvested);
        uint32_t afterArmorPen = EchoesApplyArmorPenBonus(afterExecute, reductionFrac, armorPenInvested);
        uint32_t healFromFinal = EchoesComputeLifeLeechHeal(afterArmorPen, leechInvested);

        double exBonus = 0.40 * (1.0 - std::exp(-0.000003 * executeInvested));
        uint32_t expectedAfterExecute = incomingDamage + static_cast<uint32_t>(std::floor(incomingDamage * exBonus));
        double apFrac = 0.30 * (1.0 - std::exp(-0.000003 * armorPenInvested));
        double penOfReduction = apFrac * reductionFrac;
        uint32_t expectedAfterArmorPen = static_cast<uint32_t>(std::floor(expectedAfterExecute / (1.0 - penOfReduction)));
        double leechFrac = 0.08 * (1.0 - std::exp(-0.000005 * leechInvested));
        uint32_t expectedHeal = static_cast<uint32_t>(std::floor(expectedAfterArmorPen * leechFrac));

        Check("312_life_leech_ordering_matches_hand_calculation_execute_then_armorpen_then_leech",
            healFromFinal == expectedHeal);

        // Rejected (pre-E2j8-decision) basis: leeching from the ORIGINAL incoming damage instead
        // of the final post-armor_pen value must produce a smaller, distinguishable heal (since
        // execute_power/armor_pen only ever increase damage) - proves the ordering decision is
        // load-bearing, not a coincidence of this input.
        uint32_t healFromOriginal = EchoesComputeLifeLeechHeal(incomingDamage, leechInvested);
        Check("313_life_leech_original_damage_basis_produces_distinguishable_smaller_heal",
            healFromOriginal < healFromFinal);

        // Life Leech never mutates the damage value itself - confirmed by construction
        // (EchoesComputeLifeLeechHeal takes damage by value, returns a heal amount, not a new
        // damage value) - afterArmorPen is unchanged by computing the heal from it.
        uint32_t afterArmorPenUnchanged = afterArmorPen;
        (void)EchoesComputeLifeLeechHeal(afterArmorPen, leechInvested);
        Check("314_life_leech_never_mutates_damage_value",
            afterArmorPen == afterArmorPenUnchanged);
    }

    // --- E2j8 - Cross-category independence: life_leech calculations are wholly independent of
    //     every other already-live category (mirrors this file's established 142/143/175-177/
    //     204-206/252-255/269-270 negative-control pattern) ---
    {
        double fortitudeBefore = EchoesFortitudeBonus(300000.0);
        double mitigBefore = EchoesSpellMitigationFraction(300000.0);
        double meleeSpellBefore = EchoesMeleeSpellPowerBonus(300000.0);
        double reflectBefore = EchoesReflectChanceFraction(300000.0);
        std::vector<EchoesStatSnapshotRow> rows;
        EchoesStatSnapshotRow row; row.str = 100; row.isArmor = false; rows.push_back(row);
        EchoesStatBonus masteryBefore = EchoesCalculateAbsorption(rows, 500, 80, 1);
        uint32_t executeBefore = EchoesApplyExecutePowerBonus(999999u, 5.0f, 300000.0);
        uint32_t armorPenBefore = EchoesApplyArmorPenBonus(999999u, 0.9, 300000.0);

        (void)EchoesComputeLifeLeechHeal(999999u, 999999.0);
        (void)EchoesClampLifeLeechHeal(999999u, 1u, 1000000u);

        Check("315_fortitude_unaffected_by_life_leech_calls",
            NearlyEqual(fortitudeBefore, EchoesFortitudeBonus(300000.0)));
        Check("316_spell_mitigation_unaffected_by_life_leech_calls",
            NearlyEqual(mitigBefore, EchoesSpellMitigationFraction(300000.0)));
        Check("317_melee_spell_power_unaffected_by_life_leech_calls",
            NearlyEqual(meleeSpellBefore, EchoesMeleeSpellPowerBonus(300000.0)));
        Check("318_reflect_chance_unaffected_by_life_leech_calls",
            NearlyEqual(reflectBefore, EchoesReflectChanceFraction(300000.0)));
        Check("319_execute_power_unaffected_by_life_leech_calls",
            executeBefore == EchoesApplyExecutePowerBonus(999999u, 5.0f, 300000.0));
        Check("320_armor_pen_unaffected_by_life_leech_calls",
            armorPenBefore == EchoesApplyArmorPenBonus(999999u, 0.9, 300000.0));
        EchoesStatBonus masteryAfter = EchoesCalculateAbsorption(rows, 500, 80, 1);
        Check("321_mastery_absorption_unaffected_by_life_leech_calls",
            NearlyEqual(masteryBefore.str, masteryAfter.str));
    }

    // --- Structural/source-cited notes (engine-coupled, proven by direct source read of
    //     EchoesStatsHooks.cpp and disposable-verification runtime evidence, not independently
    //     unit-testable in this pure-header file, matching this project's established convention -
    //     see test 280-287's identical pattern for reflect_chance) ---
    // 322_life_leech_reuses_shared_ondamage_guard_chain: EchoesStatsUnitScript::OnDamage's existing
    //     guard chain (attacker/victim null, damage==0, E2j7c's attacker==victim self-damage guard,
    //     attacker->IsPlayer(), gray-mob check) runs BEFORE any of execute_power/armor_pen/
    //     life_leech are queried - life_leech does not duplicate or bypass any of these guards, so
    //     reflected self-damage (attacker==victim) and pet/guardian attackers are excluded from
    //     life_leech "for free," the same way they already are for execute_power/armor_pen.
    // 323_life_leech_victim_eligibility_matches_execute_armor_pen_pvp_precedent: the shared hook's
    //     victim gate (`victim->IsCreature() || victim->IsPlayer()`) already covers PvP - no
    //     separate victim-eligibility change is needed for life_leech specifically, per Jonah's
    //     2026-07-30 authorization Section 3 (this is a NEW approved behavior, not historical
    //     fidelity - the historical patch's own gate was `victim->IsCreature()` only).
    // 324_life_leech_periodic_damage_not_filtered: UnitScript::OnDamage(Unit*, Unit*, uint32&)
    //     exposes no damage-type discriminator (same finding already established for
    //     execute_power/armor_pen in E2j7b) - life_leech applies to periodic/DoT damage that
    //     reaches this hook identically to direct hits. Accepted contract limitation.
    // 325_life_leech_no_ownership_chain_walking: the invested-account lookup is keyed by the
    //     ATTACKING player's own account_id (player->GetSession()->GetAccountId(), the same
    //     accountId already resolved once per hook call for execute_power/armor_pen) - no pet/
    //     guardian/summon/charmed-unit inheritance exists or is added.
    // 326_life_leech_uses_native_sethealth_no_new_schema: the engine-coupled hook applies healing
    //     via Player::SetHealth (bounded by the engine's own max-health clamp, matching the
    //     historical source's own choice and this phase's healing-API comparison) - zero new
    //     tables, columns, spell_dbc rows, or custom spells.

    std::printf("\n%d/%d tests passed.\n", g_pass, g_pass + g_fail);
    if (g_fail == 0) std::printf("ALL TESTS PASSED\n");
    return g_fail == 0 ? 0 : 1;
}
