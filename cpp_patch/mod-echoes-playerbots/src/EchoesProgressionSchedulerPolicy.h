#ifndef MODULE_ECHOES_PLAYERBOTS_PROGRESSION_SCHEDULER_POLICY_H
#define MODULE_ECHOES_PLAYERBOTS_PROGRESSION_SCHEDULER_POLICY_H

#include <cstdint>
#include <cstddef>

// E2j2 - pure, dependency-free scheduler-decision logic, deliberately separated from
// EchoesHooks.cpp's engine-coupled RunProgressionSchedulerPass() (which needs Player*,
// ObjectAccessor, GameTime, etc. and is proven correct only via integration/disposable-lab
// evidence - see EchoesProgressionSchedulerPolicyTests.cpp's structural notes). Everything in
// this header compiles and is fully unit-testable standalone, matching
// EchoesProgressionBudgetPolicy.h's own established pattern exactly.

// E2j2 Stage 2's source-cited audit found exactly 6 of the 18 Crucible categories have a real
// working Lua gameplay consumer (see e2j2-stage2-crucible-audit.md). Kept here (not only in
// EchoesHooks.cpp) so the category-selection function below is independently testable without
// pulling in any AzerothCore engine headers.
inline char const* const* EchoesFunctionalCrucibleCategories(std::size_t& outCount)
{
    static char const* const categories[] = {
        "attunement_echo",
        "aether_surge",
        "cooldown_reduction",
        "movement_speed",
        "res_resilience",
        "life_leech",
    };
    outCount = sizeof(categories) / sizeof(categories[0]);
    return categories;
}

// Deterministic, guid-derived, never-random category assignment. A given bot guid always
// resolves to the same category - see EchoesHooks.cpp's SelectSinkCategoryForBot comment for
// why that is intentional (population-level diversification, not per-bot portfolio rotation).
//
// Kept unchanged for E2j9 (still exactly the original 6-category pool) - existing tests and
// callers depending on this exact function's 6-category behavior are not disturbed. Production
// bot category assignment now uses EchoesSelectSinkCategoryForGuidClassAware below instead; this
// function remains as the proven E2j2 baseline and this file's own fallback path.
inline char const* EchoesSelectSinkCategoryForGuid(uint32_t guidLow)
{
    std::size_t count = 0;
    char const* const* categories = EchoesFunctionalCrucibleCategories(count);
    return categories[guidLow % count];
}

// ============================================================================
// E2j9 - Playerbot Crucible Scheduler Expansion.
//
// Recovered scope: the Pre-E2j9 Finalization Sprint's parity audit
// (env/backups/pre-e2j9-finalization/20260730T210000+0000/reports/CRUCIBLE-18-CATEGORY-PARITY-AUDIT.md)
// and scope-preparation report found 17 of 18 Crucible categories have a real, live-verified
// engine consumer as of E2j8's close - only `threat_reduction` remains excluded (contract
// recovered, no authorized engine-mechanism path - see THREAT-REDUCTION-CONTRACT-AND-DESIGN.md).
// This is the durable, explicit, evidence-cited list of those 17 - `threat_reduction` MUST NEVER
// appear here. Each entry's "live consumer" status is proven by its own phase's closure evidence
// (cited per-category below), not re-derived from a comment claim the way E2j2's original audit
// trusted OnKillCreature_Leech's mere existence without checking its registration was live - the
// exact mistake that made `life_leech` silently inert for ~9 days before E2j8.
inline char const* const* EchoesExpandedFunctionalCrucibleCategories(std::size_t& outCount)
{
    static char const* const categories[] = {
        // Original E2j2 whitelist (unchanged) - Lua event-registration-verified live.
        "attunement_echo", "aether_surge", "cooldown_reduction", "movement_speed",
        "res_resilience",
        "life_leech",           // E2j8 - C++ OnDamage, registration-liveness re-verified live 2026-07-30
        // E2j9 additions - each backed by its own phase's production deployment + runtime evidence.
        "fortitude",             // pre-E2j6, mod-echoes-stats
        "spell_mitigation",      // E2j5g, ModifySpellDamageTaken
        "crit_rating",           // E2j6, Player::ApplyRatingMod
        "haste_rating",          // E2j6
        "dodge_rating",          // E2j6
        "parry_rating",          // E2j6
        "melee_power",           // E2j7a
        "spell_power",           // E2j7a
        "execute_power",         // E2j7b, OnDamage
        "armor_pen",             // E2j7b, OnDamage
        "reflect_chance",        // E2j7c, ModifySpellDamageTaken
    };
    outCount = sizeof(categories) / sizeof(categories[0]);
    return categories;
}

// Class-mask bit convention: 1 << (class - 1), matching AzerothCore's own native CLASSMASK_*
// convention exactly (e.g. druid, class ID 11, is bit 10 / 0x400) - not a bespoke encoding.
// WotLK 3.3.5a class IDs: Warrior=1, Paladin=2, Hunter=3, Rogue=4, Priest=5, DeathKnight=6,
// Shaman=7, Mage=8, Warlock=9, Druid=11 (10 is unused).
//
// `melee_power`/`spell_power` eligibility is deliberately CLASS-level, not spec/role-level. A
// spec-aware refinement (e.g. excluding Holy Paladin from melee_power, or Enhancement Shaman from
// spell_power) was evaluated and rejected for E2j9: the one real, already-proven spec/role source
// in this codebase, `AiFactory::GetPlayerRoles` (mod-playerbots), lives in a header
// (`Bot/Factory/AiFactory.h`) this module has no existing include-path precedent for reaching, and
// verifying that dependency safely was judged higher-risk than the value of finer-grained
// targeting for a first pass. This is the explicit "conservative class-level policy" fallback the
// implementation authorization itself sanctions when reliable spec/role information isn't already
// safely reachable - not an oversight. A hybrid class (Paladin/Shaman/Druid) that could plausibly
// spec into either archetype is included in BOTH masks below, rather than guessed at or excluded.
constexpr uint32_t kEchoesMeleePowerClassMask =
    (1u << (1 - 1)) |  // Warrior
    (1u << (2 - 1)) |  // Paladin (Retribution/Protection are melee; included as a hybrid)
    (1u << (3 - 1)) |  // Hunter (ranged weapon DPS - weaponDps snapshot covers any equipped weapon)
    (1u << (4 - 1)) |  // Rogue
    (1u << (6 - 1)) |  // Death Knight
    (1u << (7 - 1)) |  // Shaman (Enhancement is melee; included as a hybrid)
    (1u << (11 - 1));  // Druid (Feral is melee; included as a hybrid)

constexpr uint32_t kEchoesSpellPowerClassMask =
    (1u << (2 - 1)) |  // Paladin (Holy is a healer; included as a hybrid)
    (1u << (5 - 1)) |  // Priest (always Intellect-scaling, damage or healing)
    (1u << (7 - 1)) |  // Shaman (Elemental/Restoration are Intellect-scaling; included as a hybrid)
    (1u << (8 - 1)) |  // Mage
    (1u << (9 - 1)) |  // Warlock
    (1u << (11 - 1));  // Druid (Balance/Restoration are Intellect-scaling; included as a hybrid)

struct EchoesCrucibleCategoryPolicyEntry
{
    char const* name;
    uint32_t classMask; // 0 = universal (every class eligible)
    uint32_t weight;    // relative pool weight - higher means more likely to be a given bot's
                         // deterministically-assigned category (see the pool-repetition
                         // mechanism in EchoesSelectSinkCategoryForGuidClassAware below)
};

// Weight-tier rationale (recovered in THREAT-REDUCTION-CONTRACT-AND-DESIGN.md's sibling report,
// the Pre-E2j9 E2j9-SCOPE-PREPARATION.md and CRUCIBLE-18-CATEGORY-PARITY-AUDIT.md):
//   weight 2 - the original six (unchanged proportional treatment) plus every universally-useful
//     addition with no known downside (defensive: fortitude/spell_mitigation; offensive:
//     crit/haste/execute_power/armor_pen - armor_pen confirmed universal, not physical-only, per
//     E2j7b's own recovered contract: OnDamage cannot discriminate school, so it boosts melee,
//     ranged, AND spell damage alike) - and the two class-gated categories, since within their
//     eligible class subset they are just as broadly useful as the weight-2 universal tier.
//   weight 1 - lower-value-but-not-excluded tier: dodge_rating/parry_rating (avoidance value is
//     real for any class but disproportionately more valuable for melee/tank bots that actually
//     take melee hits - role-aware weighting was considered, per §10, but deferred for the same
//     reachable-dependency reason as melee_power/spell_power's role refinement) and
//     reflect_chance (real ceiling is low, 5%, and the Pre-E2j9 Finalization Sprint's own Part A
//     diagnostic found zero live triggers across 194 real combat events in a 13-minute window -
//     not broken, just naturally low-yield for autonomous bot investment relative to Aether
//     spent).
inline EchoesCrucibleCategoryPolicyEntry const* EchoesCrucibleCategoryPolicyTable(std::size_t& outCount)
{
    static const EchoesCrucibleCategoryPolicyEntry table[] = {
        {"attunement_echo",    0u, 2u},
        {"aether_surge",       0u, 2u},
        {"cooldown_reduction", 0u, 2u},
        {"movement_speed",     0u, 2u},
        {"res_resilience",     0u, 2u},
        {"life_leech",         0u, 2u},
        {"fortitude",          0u, 2u},
        {"spell_mitigation",   0u, 2u},
        {"crit_rating",        0u, 2u},
        {"haste_rating",       0u, 2u},
        {"execute_power",      0u, 2u},
        {"armor_pen",          0u, 2u},
        {"dodge_rating",       0u, 1u},
        {"parry_rating",       0u, 1u},
        {"reflect_chance",     0u, 1u},
        {"melee_power",        kEchoesMeleePowerClassMask, 2u},
        {"spell_power",        kEchoesSpellPowerClassMask, 2u},
    };
    outCount = sizeof(table) / sizeof(table[0]);
    return table;
}

// Deterministic, guid-derived, class-filtered, weighted category assignment - the E2j9
// production selection function. Builds a per-call weighted pool (each eligible category
// repeated `weight` times), filtered to categories that are either universal (classMask==0) or
// explicitly include this bot's class, then indexes into that pool via guidLow % poolSize -
// exactly the same deterministic-assignment mechanism as EchoesSelectSinkCategoryForGuid above,
// just over a larger, class-aware, weighted pool. A given (guid, class) pair always resolves to
// the same category; changing the pool's composition (as this phase does) can and does reassign
// which category some existing bots resolve to going forward - an accepted, inherent property of
// this design already disclosed in the original E2j2 comment ("population-level diversification,
// not per-bot portfolio rotation"), not a new risk introduced here. Existing investment rows in a
// bot's previous category are never modified or lost; the bot simply accumulates its next
// purchase in whichever category it now resolves to.
inline char const* EchoesSelectSinkCategoryForGuidClassAware(uint32_t guidLow, uint8_t playerClass)
{
    std::size_t tableCount = 0;
    EchoesCrucibleCategoryPolicyEntry const* table = EchoesCrucibleCategoryPolicyTable(tableCount);

    uint32_t classBit = (playerClass >= 1 && playerClass <= 32) ? (1u << (playerClass - 1)) : 0u;

    static constexpr std::size_t kMaxPoolSlots = 64; // generous static bound - real max is 31 slots
    char const* pool[kMaxPoolSlots];
    std::size_t poolSize = 0;

    for (std::size_t i = 0; i < tableCount && poolSize < kMaxPoolSlots; ++i)
    {
        bool eligible = (table[i].classMask == 0u) || ((table[i].classMask & classBit) != 0u);
        if (!eligible)
            continue;
        for (uint32_t w = 0; w < table[i].weight && poolSize < kMaxPoolSlots; ++w)
            pool[poolSize++] = table[i].name;
    }

    if (poolSize == 0)
        return EchoesSelectSinkCategoryForGuid(guidLow); // defensive fallback - unreachable in
            // practice since every class matches at least the universal (classMask==0) entries

    return pool[guidLow % poolSize];
}

// Pure decision: should the scheduler skip re-checking this bot on this pass? Extracted from
// RunProgressionSchedulerPass's inline logic so the recheck-floor/jitter arithmetic itself is
// independently testable without needing a live Player*/ObjectAccessor.
//
// lastCheckedSecs == 0 means "never checked before" (always eligible - never treated as an
// elapsed-time computation against epoch 0, matching the same convention
// EchoesProgressionBudgetPolicy uses for "never spent before").
inline bool EchoesShouldSkipSchedulerRecheck(
    uint32_t nowSecs,
    uint32_t lastCheckedSecs,
    uint32_t recheckFloorSeconds,
    uint32_t jitterWindowSeconds,
    uint32_t guidLow)
{
    if (lastCheckedSecs == 0)
        return false; // never checked - always eligible

    uint32_t jitterOffset = jitterWindowSeconds > 0 ? (guidLow % jitterWindowSeconds) : 0;
    uint32_t effectiveFloor = recheckFloorSeconds + jitterOffset;

    if (nowSecs < lastCheckedSecs)
        return false; // clock anomaly - fail open to "eligible" rather than getting stuck forever

    return (nowSecs - lastCheckedSecs) < effectiveFloor;
}

#endif
