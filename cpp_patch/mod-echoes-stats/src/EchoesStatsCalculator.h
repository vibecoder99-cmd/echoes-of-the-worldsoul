#ifndef MODULE_ECHOES_STATS_CALCULATOR_H
#define MODULE_ECHOES_STATS_CALCULATOR_H

#include <cstdint>
#include <vector>
#include <cmath>

// E2j3 - pure, dependency-free calculation of Echoes' snapshot-absorption stat bonus.
// Deliberately separated from EchoesStatsHooks.cpp (which needs Player*/ItemTemplate/DB access
// and is proven only via isolated runtime evidence) so this formula is fully unit-testable
// standalone, matching this project's established pattern (EchoesProgressionBudgetPolicy.h,
// EchoesProgressionSchedulerPolicy.h).
//
// Formula recovered from ap_core.lua (isolated tree, authoritative source - AP.CalculateAbsorption,
// AP.MasteryAbsorbPct, AP.LevelAbsorbScalar):
//   masteryPct = MasteryBaseAbsorb + MasteryMaxAbsorb * (1 - exp(-MasteryDecayK * masteryRank))
//   levelScale = (level <= 9) ? 0 : min(1.0, (level - 9) / 71.0)
//   absorbPct  = masteryPct * levelScale
//   for each eligible snapshot row: bonus[stat] += row[stat] * absorbPct
// "Eligible" = item's armor subclass is within the player's class armor range (or misc/jewelry,
// subclass 0), per ap_core.lua's AP.ClassArmorRange table - reproduced exactly below, not
// reinvented.

struct EchoesStatSnapshotRow
{
    double str = 0.0;
    double agi = 0.0;
    double sta = 0.0;
    double intellect = 0.0;
    double spirit = 0.0;
    uint8_t armorSubClass = 0; // 0 = misc/jewelry (always eligible), 1=Cloth,2=Leather,3=Mail,4=Plate
    bool isArmor = true;       // false = weapon or non-armor item; armor-class filter does not apply

    // E2j5a - armor/weapon-damage restoration. See EchoesStatsHooks.cpp's EchoesQuerySnapshots
    // header comment for the full historical-source citation (cpp_patch/mod_attunement_plus.patch).
    //
    // `armor`: resolved LIVE from the item's current ItemTemplate::Armor by the caller (NOT read
    // from the ap_item_snapshot.armor DB column - that column is populated for the separate
    // Lua-native display track only). This matches the historical patch's own actually-executed
    // CalculateAbsorption behavior exactly (its own comment: "DB column unreliable for WotLK
    // items whose armor is calculated dynamically... not stored in armor column").
    double armor = 0.0;

    // `weaponDps`: FROZEN at attunement time, read from the ap_item_snapshot.weapon_dps DB
    // column (unlike armor) - matches the historical patch's own actually-executed behavior,
    // which read weapon_dps from the snapshot row, not live.
    double weaponDps = 0.0;
};

struct EchoesStatBonus
{
    double str = 0.0;
    double agi = 0.0;
    double sta = 0.0;
    double intellect = 0.0;
    double spirit = 0.0;
    double armor = 0.0;      // E2j5a
    double weaponDps = 0.0;  // E2j5a - absorbed DPS; converted to flat Attack Power at apply time
};

// E2j5a: historical conversion constant recovered exactly from cpp_patch/mod_attunement_plus.patch
// ("Apply weapon DPS as flat attack power (absorbed_dps * 7 ~ flat AP equivalent)"). This is an
// already-decided, already-tuned value (the patch's own comment notes an earlier value was higher
// and this was already tuned down) - not a new balance choice introduced by this phase.
constexpr double kWeaponDpsToAttackPowerFactor = 7.0;

// Pure, deterministic conversion - never mutates, matches the historical patch's own
// std::floor(weaponDpsVal * 7.0f) exactly.
inline double EchoesWeaponDpsToAttackPower(double absorbedWeaponDps)
{
    if (absorbedWeaponDps <= 0.0)
        return 0.0;
    return std::floor(absorbedWeaponDps * kWeaponDpsToAttackPowerFactor);
}

// E2j5e - Talent stat-multiplier restoration. Recovered EXACTLY from
// cpp_patch/mod_attunement_plus.patch (talent-computation block, ~line 287-329), corroborated
// byte-for-byte by the vault's Talents.md and E2j3's own prior formula recovery in ap_core.lua
// (AP.LoadTalents/AP.SaveTalent, `ap_talents`: guid, stat_index [0-4: STR/AGI/STA/INT/SPI], rank).
//
// Historical source (verbatim structure, adapted only to this project's naming conventions):
//   float talentMult[5] = {1,1,1,1,1}; int talentRanks[5] = {0,0,0,0,0}; int maxRank=0, primaryStat=-1;
//   SELECT stat_index, rank FROM ap_talents WHERE guid = {guid}
//   for each row: talentRanks[idx] = rank; if (rank > maxRank) { maxRank = rank; primaryStat = idx; }
//   for i in 0..4: if (talentRanks[i] <= 0) continue;
//       bonus = talentRanks[i] * (i==primaryStat ? 0.12 : 0.08); talentMult[i] = 1.0 + bonus;
//   distinctStats = count(talentRanks[i] > 0); distinctPenalty = distinctStats>1 ? pow(0.85, distinctStats-1) : 1.0
//   absorbedStats[i] = snap[i] * effective * talentMult[i] * distinctPenalty   (i in 0..4 ONLY -
//     never applied to armor/weapon-dps, which the patch's own SELECT/loop structure excludes)
//
// "Primary" is dynamic (whichever invested stat currently holds the highest rank), matching the
// already-decided, already-documented design in Talents.md - not re-derived here.
//
// Deliberate adaptation for determinism: the historical patch iterates whatever row order MySQL
// returns for `SELECT ... WHERE guid = {}` (no ORDER BY) when picking primaryStat via strict `>`.
// This module instead always evaluates stat_index in ascending 0..4 order (EchoesTalentInput's
// ranks[] is indexed by stat_index by construction), which is at least as deterministic as the
// historical behavior and preserves the identical tie-break rule (first/lowest index keeps
// primary status on an exact tie) without depending on unspecified SQL row order.
struct EchoesTalentInput
{
    // Index 0=STR 1=AGI 2=STA 3=INT 4=SPI, matching ap_talents.stat_index exactly. rank=0 means
    // "not invested" - default-constructed (all zeros) is the correct "no Talents purchased" input
    // and must produce byte-identical output to the pre-E2j5e formula (verified by test).
    int ranks[5] = {0, 0, 0, 0, 0};
};

struct EchoesTalentMultipliers
{
    double mult[5] = {1.0, 1.0, 1.0, 1.0, 1.0};
    double distinctPenalty = 1.0;
    int primaryStat = -1; // -1 = no stat invested
};

constexpr double kTalentPrimaryPctPerRank = 0.12;
constexpr double kTalentSecondaryPctPerRank = 0.08;
constexpr int kTalentPrimaryMaxRank = 3;
constexpr int kTalentSecondaryMaxRank = 2;
constexpr double kTalentDiminishingReturnsBase = 0.85;

// Pure, deterministic - never mutates. Defensive rank capping (kTalentPrimaryMaxRank/
// kTalentSecondaryMaxRank) mirrors this project's established defensive-ceiling pattern
// (EchoesValidateMasteryRankForCalculation) - the purchase path (ap_core.lua, unmodified by this
// phase) already enforces these caps at buy time, so this capping is a calculation-input safety
// net only, never a new gameplay rule.
inline EchoesTalentMultipliers EchoesComputeTalentMultipliers(EchoesTalentInput const& input)
{
    EchoesTalentMultipliers result;

    int maxRank = 0;
    int primaryStat = -1;
    for (int i = 0; i < 5; ++i)
    {
        if (input.ranks[i] > maxRank)
        {
            maxRank = input.ranks[i];
            primaryStat = i;
        }
    }
    result.primaryStat = primaryStat;

    int distinctStats = 0;
    for (int i = 0; i < 5; ++i)
    {
        int rank = input.ranks[i];
        if (rank <= 0)
            continue;
        ++distinctStats;
        bool isPrimary = (i == primaryStat);
        int cappedRank = isPrimary
            ? (rank < kTalentPrimaryMaxRank ? rank : kTalentPrimaryMaxRank)
            : (rank < kTalentSecondaryMaxRank ? rank : kTalentSecondaryMaxRank);
        double pctPerRank = isPrimary ? kTalentPrimaryPctPerRank : kTalentSecondaryPctPerRank;
        result.mult[i] = 1.0 + static_cast<double>(cappedRank) * pctPerRank;
    }

    result.distinctPenalty = (distinctStats > 1)
        ? std::pow(kTalentDiminishingReturnsBase, distinctStats - 1)
        : 1.0;
    return result;
}

// ap_core.lua's AP.ClassArmorRange, reproduced exactly (min/max inclusive armor subclass a class
// may absorb). Index by WoW class ID (1=Warrior..11=Druid, sparse - class 10 does not exist).
struct EchoesClassArmorRange { uint8_t minSub; uint8_t maxSub; bool valid; };

inline EchoesClassArmorRange EchoesGetClassArmorRange(uint8_t wowClassId)
{
    switch (wowClassId)
    {
        case 1:  return {3, 4, true};  // Warrior: mail+plate
        case 2:  return {3, 4, true};  // Paladin: mail+plate
        case 3:  return {2, 3, true};  // Hunter: leather+mail
        case 4:  return {1, 2, true};  // Rogue: cloth+leather
        case 5:  return {1, 1, true};  // Priest: cloth
        case 6:  return {3, 4, true};  // Death Knight: mail+plate
        case 7:  return {2, 3, true};  // Shaman: leather+mail
        case 8:  return {1, 1, true};  // Mage: cloth
        case 9:  return {1, 1, true};  // Warlock: cloth
        case 11: return {1, 2, true};  // Druid: cloth+leather
        default: return {0, 0, false};
    }
}

// E2j4 defensive calculation-input ceiling.
//
// Mastery Rank is INTENTIONALLY UNCAPPED as a gameplay/progression system - this is not a
// player-facing maximum, must never be described as one, and never blocks or reinterprets a
// legitimate purchase or stored row. Its sole purpose is to keep this calculation layer's
// arithmetic (exponent evaluation in EchoesMasteryAbsorbPct, int->double conversions) safe
// against corrupt, malformed, or adversarial database values, independent of how large gameplay
// progression is ever allowed to grow.
//
// Verified safe at this value: exp(-0.038 * 1,000,000) = exp(-38000) underflows cleanly to 0.0 in
// IEEE 754 double arithmetic (no trap, no NaN, no overflow - double underflows to zero for any
// exponent below roughly -745, and -38000 is far past that floor). The absorption formula
// saturates at base+max (5%+80%=85%) long before rank reaches even a few hundred, so calculating
// with a clamped rank of 1,000,000 instead of the true stored rank produces an absorption
// percentage indistinguishable from the true (uncapped) value to far more decimal places than the
// game will ever display.
constexpr int64_t kMasteryRankCalculationCeiling = 1000000;

struct EchoesMasteryRankValidation
{
    uint32_t validatedRank = 0;      // safe to pass into EchoesMasteryAbsorbPct
    bool wasNegativeOrInvalid = false; // raw value < 0 -> treated as Rank 0 for calculation only
    bool wasAboveCeiling = false;      // raw value > ceiling -> clamped to ceiling for calculation only
};

// Validates a RAW, possibly-corrupt database value using a wide signed type - int64_t safely
// holds the full range of the actual ap_mastery.mastery column (an unsigned 32-bit int, max
// ~4.29e9) with headroom to spare, so no narrowing/overflow can occur before this check runs.
// This function only ever affects what is used for THIS calculation; it never reads or writes the
// stored database row.
inline EchoesMasteryRankValidation EchoesValidateMasteryRankForCalculation(int64_t rawRank)
{
    EchoesMasteryRankValidation result;
    if (rawRank < 0)
    {
        result.wasNegativeOrInvalid = true;
        result.validatedRank = 0;
        return result;
    }
    if (rawRank > kMasteryRankCalculationCeiling)
    {
        result.wasAboveCeiling = true;
        result.validatedRank = static_cast<uint32_t>(kMasteryRankCalculationCeiling);
        return result;
    }
    result.validatedRank = static_cast<uint32_t>(rawRank);
    return result;
}

inline double EchoesMasteryAbsorbPct(uint32_t masteryRank,
    double baseAbsorb = 0.05, double maxAbsorb = 0.80, double decayK = 0.038)
{
    if (masteryRank == 0)
        return baseAbsorb; // exp(0)=1, base + max*(1-1) = base; matches formula at rank 0
    return baseAbsorb + maxAbsorb * (1.0 - std::exp(-decayK * static_cast<double>(masteryRank)));
}

inline double EchoesLevelAbsorbScalar(uint32_t level)
{
    if (level <= 9)
        return 0.0;
    double scalar = static_cast<double>(level - 9) / 71.0;
    return scalar > 1.0 ? 1.0 : scalar;
}

// True if this snapshot row's item is eligible to contribute for this class, per
// ap_core.lua's AP.ClassArmorRange rule (misc/jewelry and non-armor items always eligible).
inline bool EchoesSnapshotRowEligible(EchoesStatSnapshotRow const& row, uint8_t wowClassId)
{
    if (!row.isArmor)
        return true; // weapons and non-armor items are never filtered by armor class
    if (row.armorSubClass == 0)
        return true; // misc/jewelry always eligible
    EchoesClassArmorRange range = EchoesGetClassArmorRange(wowClassId);
    if (!range.valid)
        return false; // unknown class - fail closed, never guess
    return row.armorSubClass >= range.minSub && row.armorSubClass <= range.maxSub;
}

// Core calculation: sum eligible snapshot rows, scaled by masteryPct * levelScale.
// Never mutates anything - pure function of its inputs.
inline EchoesStatBonus EchoesCalculateAbsorption(
    std::vector<EchoesStatSnapshotRow> const& snapshots,
    uint32_t masteryRank,
    uint32_t level,
    uint8_t wowClassId,
    double baseAbsorb = 0.05,
    double maxAbsorb = 0.80,
    double decayK = 0.038,
    // E2j5e: defaults to "no Talents purchased" (all ranks 0) - callers that do not pass this
    // argument (every pre-E2j5e call site/test) get talentMult=[1,1,1,1,1] and distinctPenalty=1,
    // i.e. byte-identical output to the pre-Talent formula.
    EchoesTalentInput const& talents = EchoesTalentInput())
{
    EchoesStatBonus bonus;
    double absorbPct = EchoesMasteryAbsorbPct(masteryRank, baseAbsorb, maxAbsorb, decayK) * EchoesLevelAbsorbScalar(level);
    if (absorbPct <= 0.0)
        return bonus;

    // E2j5e: talentMult/distinctPenalty computed once per call (not per-row) - matches the
    // historical patch's structure exactly (talent lookup happens once, outside the per-item loop).
    EchoesTalentMultipliers talentMults = EchoesComputeTalentMultipliers(talents);

    for (auto const& row : snapshots)
    {
        if (!EchoesSnapshotRowEligible(row, wowClassId))
            continue;
        // E2j5e: absorbedStats[i] = snap[i] * effective * talentMult[i] * distinctPenalty,
        // recovered exactly from cpp_patch/mod_attunement_plus.patch line ~361-367
        // ("effective" == this file's absorbPct). Applies ONLY to the 5 primary-stat indices.
        bonus.str += row.str * absorbPct * talentMults.mult[0] * talentMults.distinctPenalty;
        bonus.agi += row.agi * absorbPct * talentMults.mult[1] * talentMults.distinctPenalty;
        bonus.sta += row.sta * absorbPct * talentMults.mult[2] * talentMults.distinctPenalty;
        bonus.intellect += row.intellect * absorbPct * talentMults.mult[3] * talentMults.distinctPenalty;
        bonus.spirit += row.spirit * absorbPct * talentMults.mult[4] * talentMults.distinctPenalty;
        // E2j5a: same absorbPct, same eligibility gate as the five primary stats - no separate
        // formula, no talent multiplier (matches the historical patch, which only applied
        // talentMult to indices 0-4; E2j5e's talentMult/distinctPenalty are deliberately NOT
        // applied here, preserving that exclusion exactly).
        bonus.armor += row.armor * absorbPct;
        bonus.weaponDps += row.weaponDps * absorbPct;
    }
    return bonus;
}

// ---------------------------------------------------------------------------
// E2j5g Stage 7 - Spell Mitigation restoration. Recovered EXACTLY from
// cpp_patch/mod_attunement_plus.patch's ModifySpellDamageTaken block (~line 967-997),
// re-verified byte-for-byte by this phase's own direct re-read of that source (not just the
// e2j5g-HIGH-IMPACT-CONTRACT-RECOVERY.md paraphrase) before writing any code here, matching the
// project's established evidence-gate discipline (E2j5a/E2j5e).
//
// Historical source (verbatim structure, adapted only to this project's naming conventions):
//   mitigFrac = ApSinkEffect(0.25, 0.000004, mitigInvested)   // ApSinkEffect(ceiling,k,invested) =
//                                                              // ceiling * (1 - e^(-k*invested))
//   if (mitigFrac > 0.0) {
//       reduction = floor(damage * mitigFrac)
//       if (reduction >= damage) reduction = damage - 1        // never reduce to zero from
//                                                                // mitigation alone
//       damage -= reduction
//   }
//
// This is deliberately kept a separate constant/formula pair from EchoesMasteryAbsorbPct's
// 0.05/0.80/0.038 - Spell Mitigation is its own Crucible sink category (`ap_aether_sinks`,
// category='spell_mitigation'), sharing only the shape of the diminishing-returns curve
// (ApSinkEffect in the historical patch), not any of Mastery's specific constants or code path.
// No interaction with Mastery or Talent was found in cpp_patch (see the contract-recovery report's
// "Mastery / Talent / Crucible Interaction" section) - this function is intentionally NOT wired
// into EchoesCalculateAbsorption above; it is a wholly separate per-hit damage-event calculation,
// consumed by a new UnitScript::ModifySpellDamageTaken hook (EchoesStatsHooks.cpp), not by the
// login/level/equip snapshot-absorption pipeline.
constexpr double kSpellMitigationCeiling = 0.25;
constexpr double kSpellMitigationDecayK = 0.000004;

// Pure asymptotic diminishing-returns curve - identical shape to EchoesMasteryAbsorbPct's own
// exponential term, but deliberately a separate function (not a shared helper) since the two
// formulas are not otherwise coupled in the historical source and this project's established
// convention (see EchoesMasteryAbsorbPct/EchoesComputeTalentMultipliers above) is one dedicated,
// clearly-cited function per recovered historical formula, not a premature shared abstraction.
inline double EchoesSpellMitigationFraction(double invested,
    double ceiling = kSpellMitigationCeiling, double k = kSpellMitigationDecayK)
{
    if (invested <= 0.0)
        return 0.0;
    return ceiling * (1.0 - std::exp(-k * invested));
}

// Pure, deterministic - never mutates `damage` itself (the caller, EchoesStatsHooks.cpp's
// ModifySpellDamageTaken override, owns the actual int32&damage mutation and the throttled
// notification; this function only computes the reduction amount). Matches the historical patch's
// exact floor-safety rule: damage is never reduced to zero by mitigation alone.
inline uint32_t EchoesComputeSpellMitigationReduction(int32_t damage, double invested,
    double ceiling = kSpellMitigationCeiling, double k = kSpellMitigationDecayK)
{
    if (damage <= 0 || invested <= 0.0)
        return 0;

    double frac = EchoesSpellMitigationFraction(invested, ceiling, k);
    if (frac <= 0.0)
        return 0;

    uint32_t udamage = static_cast<uint32_t>(damage);
    uint32_t reduction = static_cast<uint32_t>(std::floor(static_cast<double>(damage) * frac));
    if (reduction >= udamage)
        reduction = udamage - 1; // floor-safety: never reduce damage below 1 from mitigation alone
    return reduction;
}

// ---------------------------------------------------------------------------
// E2j5h Stage 2 - Fortitude restoration. Recovered EXACTLY from
// cpp_patch/mod_attunement_plus.patch's "Aether Sink Phase 1+2" block (~line 478-534), re-verified
// byte-for-byte by this phase's own direct re-read of that source (not just
// e2j5g-HIGH-IMPACT-CONTRACT-RECOVERY.md's paraphrase) before writing any code here, matching the
// project's established evidence-gate discipline (E2j5a/E2j5e/E2j5g).
//
// Historical source (verbatim structure, adapted only to this project's naming conventions):
//   fortitudeBonus = ApSinkEffect(0.50, 0.000003, fortitudeInvested)   // asymptotic ceiling 50%
//   newStats[2] *= (1.0 + fortitudeBonus)                              // newStats[2] = STA index
//
// `newStats[2]` at the point this multiplier is applied in cpp_patch already holds the
// Mastery-scaled (and, in the now-modernized live pipeline, Talent-scaled) STA absorption bonus -
// Fortitude multiplies that ALREADY-ACCUMULATED value, it does not read or modify the player's raw
// base STA directly, and it is a single scalar multiplier applied once per recalculation (not
// per-item), unlike Talent's per-row multiplier. Because a single scalar multiplier distributes
// identically whether applied to each addend before summation or to the finished sum, applying it
// once to the finished EchoesStatBonus::sta (below) is mathematically identical to the historical
// patch's own "after the per-item accumulation loop" placement - not a behavioral reinterpretation.
//
// Deliberately a wholly separate function from EchoesCalculateAbsorption (not folded into it) -
// this mirrors E2j5g Spell Mitigation's own precedent (a new recovered formula gets its own
// dedicated, clearly-cited function) and keeps EchoesCalculateAbsorption - already proven correct
// for Mastery/Talent/armor/weapon-dps by 90 existing passing assertions - completely untouched by
// this change, minimizing blast radius. The recovered contract-recovery report itself flags "fold
// into EchoesCalculateAbsorption vs. separate post-step" as an UNRESOLVED design decision (Jonah has
// not decided); both options are byte-identical in OUTPUT (per the distributivity argument above),
// so this is a pure code-organization choice, not an invented behavior - the separate-function
// approach is chosen here as the lower-blast-radius option, consistent with Spell Mitigation's own
// precedent in this same file.
constexpr double kFortitudeCeiling = 0.50;
constexpr double kFortitudeDecayK = 0.000003;

// Pure asymptotic diminishing-returns curve - identical shape to EchoesSpellMitigationFraction's
// own exponential term (both mirror cpp_patch's shared ApSinkEffect(ceiling, k, invested) helper),
// but deliberately a separate function per this file's established one-function-per-recovered-
// formula convention.
inline double EchoesFortitudeBonus(double invested,
    double ceiling = kFortitudeCeiling, double k = kFortitudeDecayK)
{
    if (invested <= 0.0)
        return 0.0;
    return ceiling * (1.0 - std::exp(-k * invested));
}

// Pure, deterministic, never mutates its input - returns a NEW EchoesStatBonus with `sta`
// multiplied by (1 + fortitudeBonus) and every other field passed through unchanged. Matches the
// recovered contract's explicit finding: Fortitude has no interaction with STR/AGI/INT/SPI, armor,
// or weaponDps (cpp_patch's own `newStats[2] *=` line touches only index 2 / STA).
//
// Non-compounding by construction: this function always computes the multiplier fresh from the
// CALLER's already-computed `bonus.sta` (the freshly-recalculated Mastery+Talent-scaled value for
// THIS call), never from a previously-multiplied stored value - so calling this repeatedly with the
// same inputs is byte-identical every time (verified by test), and it can never compound across
// repeated refreshes the way an in-place `sta *= ...` accumulator would if fed its own prior output.
inline EchoesStatBonus EchoesApplyFortitudeMultiplier(EchoesStatBonus const& bonus, double fortitudeInvested,
    double ceiling = kFortitudeCeiling, double k = kFortitudeDecayK)
{
    EchoesStatBonus result = bonus;
    double fortitudeBonus = EchoesFortitudeBonus(fortitudeInvested, ceiling, k);
    if (fortitudeBonus > 0.0)
        result.sta = bonus.sta * (1.0 + fortitudeBonus);
    return result;
}

// ---------------------------------------------------------------------------
// E2j6 - Combat-rating restoration: crit_rating, haste_rating, dodge_rating, parry_rating.
// Recovered EXACTLY from env/dist/lua_scripts/ap_sinks.lua's AP.SinkDefs (the live authoritative
// Lua source, re-verified directly, not paraphrased) and corroborated byte-for-byte by
// cpp_patch/mod_attunement_plus.patch's own `ApSinkEffect(ceiling, k, invested)` calls for these
// four categories (echoes-of-the-worldsoul repo, citation-only, never deployed). Same asymptotic
// diminishing-returns curve shape as Fortitude/Spell Mitigation above.
//
// All four categories share the identical k (0.000003, identical to kFortitudeDecayK) and the
// identical consumption shape (a percentage fed into Player::ApplyRatingMod via a rating-point
// conversion) - unlike Fortitude (a one-off STA multiplier) and Spell Mitigation (a per-hit damage
// reduction), which are each consumed differently and so each got their own dedicated function.
// Here, one shared curve function plus one shared percent->rating-point conversion function
// avoids four near-identical duplicates without hiding any behavior - the per-category ceiling
// stays an explicit, separately-named constant (matching this file's existing convention), only
// the curve shape and the engine-unit conversion are shared.
constexpr double kCritRatingCeiling = 0.15;   // up to +15% crit (melee+ranged+spell simultaneously)
constexpr double kHasteRatingCeiling = 0.20;  // up to +20% haste (melee+ranged+spell simultaneously)
constexpr double kDodgeRatingCeiling = 0.15;  // up to +15% dodge
constexpr double kParryRatingCeiling = 0.10;  // up to +10% parry
constexpr double kRatingSinkDecayK = 0.000003;

// Pure asymptotic diminishing-returns curve, identical shape to EchoesFortitudeBonus/
// EchoesSpellMitigationFraction - returns a FRACTION (0.0..ceiling), e.g. 0.15 = 15%, not a
// percentage-points number.
inline double EchoesRatingSinkFraction(double invested, double ceiling, double k = kRatingSinkDecayK)
{
    if (invested <= 0.0)
        return 0.0;
    return ceiling * (1.0 - std::exp(-k * invested));
}

// Pure, engine-independent conversion: `percent` is a percentage-POINTS value (e.g. 15.0, not
// 0.15) and `ratingMultiplier` is the caller-supplied result of the current core's
// Player::GetRatingMultiplier(cr) (percent-per-rating-point, DBC-driven, varies by level and
// class - see EchoesStatsHooks.cpp for that call site). Deliberately takes the multiplier as a
// plain float parameter rather than a Player*, keeping this function dependency-free and
// standalone-testable like every other formula in this file - EchoesStatsHooks.cpp owns the
// actual player->GetRatingMultiplier(cr) call and the per-CombatRating loop.
//
// This is the piece that deliberately replaces the historical cpp_patch's own hardcoded
// level-80-only approximation (e.g. "~39.35 rating per 1% dodge") with the current core's real,
// live conversion - see e2j6-CONTRACT-RECOVERY.md for the full citation of why this is a
// documented adaptation, not a reinterpretation of the recovered ceiling/k/percentage-intent.
inline int32_t EchoesRatingPointsForPercent(double percent, float ratingMultiplier)
{
    if (percent <= 0.0 || ratingMultiplier <= 0.0f)
        return 0;
    return static_cast<int32_t>(std::floor(percent / static_cast<double>(ratingMultiplier)));
}

// ---------------------------------------------------------------------------
// E2j7a - melee_power/spell_power restoration. Recovered from ap_sinks.lua's AP.SinkDefs
// (both categories, ceiling=1.00, k=0.000004, phase=1) and cross-checked against
// cpp_patch/mod_attunement_plus.patch's own ApSinkEffect(1.00, 0.000004, invested) calls for
// these two categories - see E2j7-CONTRACT-RECOVERY-AND-PHASE-DECOMPOSITION.md.
//
// Historical source (verbatim structure, adapted only to this project's naming conventions):
//   meleePowerBonus = ApSinkEffect(1.00, 0.000004, meleePowerInvested)
//   newStats[6] *= (1.0 + meleePowerBonus)   // newStats[6] = absorbed weapon-DPS
//   spellPowerBonus = ApSinkEffect(1.00, 0.000004, spellPowerInvested)
//   newStats[3] *= (1.0 + spellPowerBonus)   // newStats[3] = INT
//
// Identical shape to EchoesApplyFortitudeMultiplier: a post-step multiplicative bonus applied
// once per recalculation to an already-computed EchoesStatBonus field, non-compounding by
// construction (always computed fresh from the caller's already-computed bonus, never chained
// from its own prior output). The two categories are independently invested and independently
// applied to different fields (weaponDps vs. intellect) - not a shared/combined bonus.
constexpr double kMeleeSpellPowerCeiling = 1.00;
constexpr double kMeleeSpellPowerDecayK = 0.000004;

// Pure asymptotic diminishing-returns curve, identical shape to EchoesFortitudeBonus - shared by
// both melee_power and spell_power since they use the same ceiling/k (unlike the four E2j6
// rating categories, which differ per-category and so pass ceiling as a parameter; here the
// ceiling is identical for both callers, so it is baked into the constant rather than threaded
// through as a parameter, matching this file's "no unnecessary parameterization" precedent).
inline double EchoesMeleeSpellPowerBonus(double invested)
{
    if (invested <= 0.0)
        return 0.0;
    return kMeleeSpellPowerCeiling * (1.0 - std::exp(-kMeleeSpellPowerDecayK * invested));
}

// Pure, deterministic, never mutates its input - returns a NEW EchoesStatBonus with `weaponDps`
// multiplied by (1 + meleePowerBonus) and `intellect` multiplied by (1 + spellPowerBonus),
// every other field passed through unchanged. Matches the recovered contract's explicit finding:
// melee_power touches only newStats[6] (weaponDps) and spell_power touches only newStats[3]
// (intellect) - no interaction with STR/AGI/STA/SPI/armor, and no interaction with each other.
inline EchoesStatBonus EchoesApplyMeleeSpellPowerMultipliers(EchoesStatBonus const& bonus,
    double meleePowerInvested, double spellPowerInvested)
{
    EchoesStatBonus result = bonus;
    double meleeBonus = EchoesMeleeSpellPowerBonus(meleePowerInvested);
    if (meleeBonus > 0.0)
        result.weaponDps = bonus.weaponDps * (1.0 + meleeBonus);
    double spellBonus = EchoesMeleeSpellPowerBonus(spellPowerInvested);
    if (spellBonus > 0.0)
        result.intellect = bonus.intellect * (1.0 + spellBonus);
    return result;
}

// ---------------------------------------------------------------------------
// E2j7b - execute_power/armor_pen restoration via the OnDamage hook (post-mitigation, per
// E2j7b-CONTRACT-DECISIONS-AND-ENGINEERING-PLAN.md). Both categories recovered from ap_sinks.lua's
// AP.SinkDefs and cross-checked against the historical source, re-located this phase to
// C:\Azerothcore\modules\mod-attunement-plus\src\mod_attunement_plus.cpp (SHA-256
// e23504812bc2ad952b14897a165dde32729cfa1265ada0a3d20d09d8a289757a, lines 892-969) - the prior
// "cpp_patch/mod_attunement_plus.patch" citation does not exist on this host and is corrected here.
//
// Historical source (verbatim structure, execute_power/armor_pen extracted from the shared
// OnDamage block, Life Leech excluded - not part of E2j7b's scope):
//   exBonus = ApSinkEffect(0.40, 0.000003, executePowerInvested)
//   damage += floor(damage * exBonus)                    if victim->GetHealthPct() < 20.0f
//   armorPenFrac = ApSinkEffect(0.30, 0.000003, armorPenInvested)
//   reductionFrac = targetArmor / (targetArmor + 15232.5) // level-80-only hardcoded constant
//   penOfReduction = armorPenFrac * reductionFrac
//   damage = floor(damage / (1 - penOfReduction))         if it increases damage
//
// Mandatory apply order: execute_power FIRST, then armor_pen, operating on the same mutated
// damage value in sequence - load-bearing per the historical source's own ordering (execute runs
// before armor-pen in the original OnDamage block) and the accepted planning report's own
// phase-decomposition reasoning (this is the first case in this project where two categories in
// the same hook have an order dependency on each other).
//
// School gating: per Jonah's explicit decision (2026-07-30), NEITHER category is restricted by
// damage school - execute_power was never authorized to be restricted, and armor_pen's intended
// physical-only restriction was found to be unimplementable inside OnDamage (which receives no
// school/spellInfo information at all - confirmed by direct re-read of UnitScript::OnDamage's
// declaration and its single call site, Unit.cpp:1026, this session) without either expanding the
// hook architecture or building a fragile cross-hook heuristic, neither authorized. Documented as
// an accepted contract limitation, not a silent omission - see
// e2j7b-STAGE1-PRE-EDIT-CONTRACT-AND-IDENTITY.md Section 4/9 for the full finding and balance
// analysis (at invested=250000, the bonus ranges 0%-11.7% depending on target armor; at the
// mathematical ceiling, ~25% against the heaviest-armored targets - comparable to Fortitude's
// already-shipped 50% ceiling).
constexpr double kExecutePowerCeiling = 0.40;
constexpr double kArmorPenCeiling = 0.30;
constexpr double kExecutePowerArmorPenDecayK = 0.000003;
constexpr double kExecutePowerHealthPctThreshold = 20.0;

// Pure asymptotic diminishing-returns curve, identical shape to every other recovered Aether Sink
// formula in this file.
inline double EchoesExecutePowerBonus(double invested)
{
    if (invested <= 0.0)
        return 0.0;
    return kExecutePowerCeiling * (1.0 - std::exp(-kExecutePowerArmorPenDecayK * invested));
}

inline double EchoesArmorPenFraction(double invested)
{
    if (invested <= 0.0)
        return 0.0;
    return kArmorPenCeiling * (1.0 - std::exp(-kExecutePowerArmorPenDecayK * invested));
}

// Pure, deterministic damage-scaling function. Mirrors the historical `damage += floor(damage *
// exBonus)` step exactly, gated on `victimHealthPct < 20.0` (strictly below, re-verified against
// the historical source's own `< 20.0f` operator this session - not `<=`). `victimHealthPct` is
// read by the caller BEFORE this hit's damage is subtracted from the victim's health (matching
// Unit::DealDamage's own ordering: OnDamage fires before Unit::ModifyHealth, Unit.cpp:1026 vs.
// 1276) - a hit that brings a target from above 20% to below 20% does NOT retroactively receive
// the bonus for that same hit, since the threshold check uses pre-hit health.
inline uint32_t EchoesApplyExecutePowerBonus(uint32_t damage, float victimHealthPct, double executePowerInvested)
{
    if (damage == 0 || executePowerInvested <= 0.0)
        return damage;
    if (victimHealthPct >= static_cast<float>(kExecutePowerHealthPctThreshold))
        return damage;
    double bonus = EchoesExecutePowerBonus(executePowerInvested);
    if (bonus <= 0.0)
        return damage;
    return damage + static_cast<uint32_t>(std::floor(static_cast<double>(damage) * bonus));
}

// Pure, per-level-correct armor-mitigation-reduction formula, replacing the historical hardcoded
// level-80-only constant (15232.5). Algebraically derived from the current core's own live
// Unit::CalcArmorReducedDamage (Unit.cpp:2245-2316, re-verified this session):
//   levelModifier = attackerLevel > 59 ? attackerLevel + 4.5*(attackerLevel-59) : attackerLevel
//   armorConstant = 85*levelModifier + 400   (from tmpvalue = 0.1*armor/(8.5*levelModifier+40),
//                                              tmpvalue/(1+tmpvalue) collapsing to armor/(armor+
//                                              85*levelModifier+400) - see the accepted planning
//                                              report's Section 2.6 for the full algebraic proof)
//   reductionFrac = armor / (armor + armorConstant)
// At attackerLevel=80: levelModifier=174.5, armorConstant=85*174.5+400=15232.5 EXACTLY - proving
// this is a strict generalization of the historical constant, not a reinterpretation (test 236).
// Implemented as a pure function (not a live Unit::CalcArmorReducedDamage sample) since the two
// are proven mathematically identical and the pure form is fully unit-testable, matching this
// file's established dependency-free convention for every other formula.
inline double EchoesArmorPenReductionFraction(double armor, uint32_t attackerLevel)
{
    if (armor <= 0.0)
        return 0.0;
    double levelModifier = static_cast<double>(attackerLevel);
    if (levelModifier > 59.0)
        levelModifier = levelModifier + 4.5 * (levelModifier - 59.0);
    double armorConstant = 85.0 * levelModifier + 400.0;
    return armor / (armor + armorConstant);
}

// Pure, deterministic damage-scaling function. Mirrors the historical armor-pen block exactly:
// derives penOfReduction from the (caller-supplied, already-level-correct) reductionFrac, inflates
// damage only if doing so increases it, guards penOfReduction < 1.0 to avoid division by zero or a
// negative multiplier (matches the historical source's own guard). `reductionFrac` is taken as a
// plain double parameter rather than requiring a Unit*/Player*, matching this file's established
// convention (e.g. EchoesRatingPointsForPercent takes `ratingMultiplier` as a plain float) - the
// caller (EchoesStatsHooks.cpp) is responsible for computing it via
// EchoesArmorPenReductionFraction(victim->GetArmor(), attacker->GetLevel()).
inline uint32_t EchoesApplyArmorPenBonus(uint32_t damage, double reductionFrac, double armorPenInvested)
{
    if (damage == 0 || armorPenInvested <= 0.0 || reductionFrac <= 0.0)
        return damage;
    double armorPenFrac = EchoesArmorPenFraction(armorPenInvested);
    if (armorPenFrac <= 0.0)
        return damage;
    double penOfReduction = armorPenFrac * reductionFrac;
    if (penOfReduction >= 1.0)
        return damage; // defensive guard - never divide by zero/negative
    uint32_t newDamage = static_cast<uint32_t>(std::floor(static_cast<double>(damage) / (1.0 - penOfReduction)));
    return newDamage > damage ? newDamage : damage;
}

// ---------------------------------------------------------------------------
// E2j8 - life_leech restoration via the same OnDamage hook as execute_power/armor_pen. Recovered
// from ap_sinks.lua's AP.SinkDefs.life_leech and cross-checked against the historical source
// (C:\Azerothcore\modules\mod-attunement-plus\src\mod_attunement_plus.cpp, SHA-256
// e23504812bc2ad952b14897a165dde32729cfa1265ada0a3d20d09d8a289757a, lines 892-969) - see
// LIFE-LEECH-CONTRACT-RECOVERY-AND-RESTORATION-ENGINEERING-PLAN.md for the full contract recovery.
//
// Historical source (verbatim structure, life_leech extracted from the shared OnDamage block):
//   leechFrac  = ApSinkEffect(0.08, 0.000005, leechInvested)
//   healAmount = max(1, floor(damage * leechFrac))
//   actualHeal = min(healAmount, maxHP - curHP)          // if curHP < maxHP
//
// E2j8 contract decisions (Jonah, 2026-07-30 implementation authorization), NOT a byte-for-byte
// historical restoration:
//   - Damage basis changed from the historical "reads damage BEFORE execute_power/armor_pen" to
//     the OPPOSITE: Life Leech now reads damage AFTER both have already mutated it (heals from the
//     final E2j7b-modified outgoing value). Life Leech itself never mutates damage - it is placed
//     last in the OnDamage apply order specifically so it cannot influence execute_power's or
//     armor_pen's own math, only observe their combined result.
//   - Victim eligibility extended from the historical `victim->IsCreature()`-only gate to
//     `victim->IsCreature() || victim->IsPlayer()`, matching the PvP-inclusion precedent already
//     shipped for execute_power/armor_pen (E2j7b) and reflect_chance (E2j7c). This is a new
//     approved Echoes 2.0 behavior, not historical fidelity - Life Leech never worked in PvP in any
//     prior version of this mod.
//   - Attacker eligibility, gray-mob exclusion, and self-damage exclusion are unchanged from the
//     shared OnDamage guard chain already enforced by EchoesStatsUnitScript::OnDamage (attacker
//     must be a Player - excludes pets/guardians by construction; attacker == victim is skipped
//     before any category runs, which also excludes E2j7c's reflected self-damage for free).
//   - DoT/periodic damage is not filtered, for the same structural reason execute_power/armor_pen
//     don't filter it: UnitScript::OnDamage(Unit*, Unit*, uint32&) exposes no damage-type
//     discriminator. Accepted contract limitation, not a silent omission.
constexpr double kLifeLeechCeiling = 0.08;
constexpr double kLifeLeechDecayK = 0.000005;

// Pure asymptotic diminishing-returns curve, identical shape to every other recovered Aether Sink
// formula in this file.
inline double EchoesLifeLeechFraction(double invested)
{
    if (invested <= 0.0)
        return 0.0;
    return kLifeLeechCeiling * (1.0 - std::exp(-kLifeLeechDecayK * invested));
}

// Pure, deterministic heal-amount calculation. Mirrors the historical `max(1, floor(damage *
// leechFrac))` exactly. `damage` here is the value AFTER execute_power and armor_pen have already
// run (E2j8's damage-basis decision, see block comment above) - the caller is responsible for
// passing the post-armor_pen damage, not the value that entered OnDamage.
inline uint32_t EchoesComputeLifeLeechHeal(uint32_t damage, double leechInvested)
{
    if (damage == 0 || leechInvested <= 0.0)
        return 0;
    double frac = EchoesLifeLeechFraction(leechInvested);
    if (frac <= 0.0)
        return 0;
    uint32_t raw = static_cast<uint32_t>(std::floor(static_cast<double>(damage) * frac));
    return raw > 0 ? raw : 1; // matches historical max(1, floor(...)) - any nonzero fraction heals at least 1
}

// Pure overheal-safe clamp. Mirrors the historical `min(healAmount, maxHP - curHP)` guarded by
// `curHP < maxHP`. Takes plain health values (not Unit*/Player*) so it is testable without engine
// objects, matching this file's established convention (e.g. EchoesApplyArmorPenBonus taking a
// plain reductionFrac rather than a Unit*).
inline uint32_t EchoesClampLifeLeechHeal(uint32_t rawHeal, uint32_t curHP, uint32_t maxHP)
{
    if (rawHeal == 0 || curHP >= maxHP)
        return 0;
    uint32_t missing = maxHP - curHP;
    return rawHeal < missing ? rawHeal : missing;
}

// ---------------------------------------------------------------------------
// E2j7c - reflect_chance restoration via UnitScript::ModifySpellDamageTaken (already registered
// for Spell Mitigation - no new hook registration needed). Recovered from ap_sinks.lua's
// AP.SinkDefs and cross-checked against the historical source
// (C:\Azerothcore\modules\mod-attunement-plus\src\mod_attunement_plus.cpp, SHA-256
// e23504812bc2ad952b14897a165dde32729cfa1265ada0a3d20d09d8a289757a, lines 1003-1024) - see
// E2j7c-REFLECT-CHANCE-CONTRACT-AND-REENTRANCY-DESIGN.md for the full contract recovery and
// recursion-safety analysis.
//
// Historical source (verbatim structure):
//   reflectFrac = ApSinkEffect(0.05, 0.000002, refInvested)
//   roll = urand(0, 9999); threshold = reflectFrac * 10000
//   if roll < threshold: reflectDamage = damage; damage = 0;
//                         Unit::DealDamage(attacker, attacker, reflectDamage, ...)
//
// Reflects 100% of the remaining damage at the point this hook fires - i.e. AFTER Spell
// Mitigation's own reduction, but BEFORE armor/crit/block/absorb are applied elsewhere in the
// spell-damage pipeline (this hook fires from Unit::CalculateSpellDamageTaken, before those later
// steps - re-verified directly against the current core this session). Not "the target's final
// incoming damage" - a materially smaller, earlier-stage number.
//
// Recursion safety: Unit::DealDamage(attacker, attacker, ...) is a DIRECT call that bypasses
// Unit::CalculateSpellDamageTaken (the only call site for this hook, Unit.cpp:1534) entirely - so
// reflected damage cannot re-enter this same hook, for either participant, regardless of their own
// reflect_chance investment. This is a structural (call-graph) guarantee, not a runtime guard -
// no boolean/token/registry is introduced or needed for this specific threat.
constexpr double kReflectChanceCeiling = 0.05;
constexpr double kReflectChanceDecayK = 0.000002;

inline double EchoesReflectChanceFraction(double invested)
{
    if (invested <= 0.0)
        return 0.0;
    return kReflectChanceCeiling * (1.0 - std::exp(-kReflectChanceDecayK * invested));
}

// Pure percent->integer-threshold conversion, matching the historical
// `static_cast<uint32>(reflectFrac * 10000.0)` exactly. Split from the roll comparison below so
// both halves of the trigger decision are independently unit-testable without real RNG.
inline uint32_t EchoesReflectChanceThreshold(double reflectFrac)
{
    if (reflectFrac <= 0.0)
        return 0;
    return static_cast<uint32_t>(reflectFrac * 10000.0);
}

// Pure roll-vs-threshold comparison, matching the historical `roll < threshold` exactly. Takes an
// already-rolled value (real urand(0,9999) call lives in the engine-coupled hook) so the boundary
// behavior (roll one below/at/above threshold, roll=0, roll=9999) is testable via injection,
// matching the test contract's "deterministic seeded RNG or injectable roll source where
// practical" requirement.
inline bool EchoesReflectChanceRollTriggered(uint32_t roll, uint32_t threshold)
{
    return roll < threshold;
}

#endif
