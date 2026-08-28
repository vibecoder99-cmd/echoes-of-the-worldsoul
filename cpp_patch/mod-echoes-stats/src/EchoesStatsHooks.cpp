#include "EchoesStatsConfig.h"
#include "EchoesStatsCalculator.h"

#include "ScriptMgr.h"
#include "Player.h"
#include "ItemTemplate.h"
#include "ObjectMgr.h"
#include "DatabaseEnv.h"
#include "QueryResult.h"
#include "GameTime.h"
#include "Log.h"
#include "SpellInfo.h"
#include "SharedDefines.h"
#include "Chat.h"
#include <unordered_map>
#include <initializer_list>

// E2j3: engine-level stat application for Echoes' snapshot-absorption (Mastery) bonus.
//
// IMPORTANT correctness note, established directly from ap_core.lua's AP.CalculateAbsorption:
// the bonus is a function of Mastery rank, character level, and ALL of the account's
// ap_item_snapshot rows (filtered only by class-armor eligibility) - it does NOT depend on
// which items are currently equipped. An item contributes to the bonus once it has been
// snapshotted (fully attuned), permanently, regardless of bag/bank/equip location. This means
// equip/unequip events are NOT a correctness-relevant trigger for this specific bonus, unlike
// what an initial (incorrect) assumption might suggest - only Mastery-rank changes, new/updated
// snapshots, and level changes actually move the calculated bonus.
//
// Hook set, deliberately minimal and matching that reality:
//   - OnPlayerLogin: apply.
//   - OnPlayerLogout: remove, clear tracked state.
//   - OnPlayerLevelChanged: levelScale changed - recalculate.
//   - Bounded periodic safety-net recheck (WorldScript::OnUpdate, rate-limited, only for
//     currently-online players, never a full-account/global scan) - catches a Mastery purchase
//     or new snapshot without requiring a new Lua->C++ signaling boundary, which this phase's
//     time budget does not extend to building safely. This is a deliberate, documented scope
//     tradeoff: the bonus becomes correct within one recheck interval of a purchase, not
//     instantly. See e2j3-CLOSURE-REPORT.md's Stage 7 section.
namespace EchoesStatsState
{
    struct AppliedBonus
    {
        double str = 0.0, agi = 0.0, sta = 0.0, intellect = 0.0, spirit = 0.0;
        double armor = 0.0;       // E2j5a
        double attackPower = 0.0; // E2j5a - already-converted from absorbed weaponDps
        // E2j6 - already-converted rating POINTS (not percent), one slot per CombatRating actually
        // touched. Separate slots per CR (not one aggregate per category) because
        // Player::GetRatingMultiplier(cr) can differ between CR_CRIT_MELEE/RANGED/SPELL (and
        // between CR_HASTE_MELEE/RANGED/SPELL) for the same class/level, so the same target
        // percentage can require different rating points per CR.
        int32_t critMeleePoints = 0, critRangedPoints = 0, critSpellPoints = 0;
        int32_t hasteMeleePoints = 0, hasteRangedPoints = 0, hasteSpellPoints = 0;
        int32_t dodgePoints = 0, parryPoints = 0;
    };
    // In-memory only, per online player - the single authoritative record of what THIS module
    // has currently added to the player's stats. Never persisted; cleared on logout and on
    // shutdown, matching every other Echoes module's "purely in-process bookkeeping" convention.
    static std::unordered_map<uint32_t, AppliedBonus> appliedByGuid;
    static std::unordered_map<uint32_t, uint32_t> lastRecalcSecsByGuid;
    static uint32_t lastPeriodicPassSecs = 0;

    // E2j4: dedup key for the bounded input-ceiling warning - one warning per (guid, distinct raw
    // value), not one per recalculation. A bot sitting above the ceiling gets rechecked every
    // ~60s by the periodic safety net; without this, that alone would spam the log forever.
    static std::unordered_map<uint32_t, int64_t> lastWarnedRawMasteryRankByGuid;

    // E2j5g Stage 7 - Spell Mitigation restoration. Per-account 30-second investment cache,
    // matching cpp_patch's own `s_sinkCache`/`ApSinkCacheEntry::mitigInvested` exactly (recovered
    // and re-verified directly against cpp_patch/mod_attunement_plus.patch, not just the
    // contract-recovery report's paraphrase). Deliberately account-scoped (not character-guid
    // scoped, unlike ap_mastery/ap_talents above) - `ap_aether_sinks` is an account-wide table,
    // confirmed via ap_sinks.lua's own `AP.Sinks.LoadForAccount(accountId)`/`account_id` column.
    struct SpellMitigationCacheEntry
    {
        double mitigInvested = 0.0;
        uint32_t lastQueryMs = 0;
    };
    static std::unordered_map<uint32_t, SpellMitigationCacheEntry> mitigCacheByAccountId;

    // 5-second per-player notification throttle, matching cpp_patch's own `s_mitigNotifyTime`.
    static std::unordered_map<uint32_t, uint32_t> mitigNotifyTimeByGuid;

    // E2j7b - execute_power/armor_pen restoration. Per-account 30-second investment cache, same
    // shape/TTL as SpellMitigationCacheEntry above (this hook, like ModifySpellDamageTaken, fires
    // per-hit rather than on the infrequent login/logout/level/60s-periodic triggers Fortitude/
    // rating-sinks/E2j7a use) - matches the historical `s_sinkCache`'s own combined-category read
    // shape more closely than a single-category query would (mirrors EchoesQueryRatingSinksInvested/
    // EchoesQueryMeleeSpellPowerInvested's own combined-query precedent for a phase's own two
    // categories).
    struct ArmorPenExecutePowerCacheEntry
    {
        double executePowerInvested = 0.0;
        double armorPenInvested = 0.0;
        uint32_t lastQueryMs = 0;
    };
    static std::unordered_map<uint32_t, ArmorPenExecutePowerCacheEntry> armorPenExecutePowerCacheByAccountId;

    // E2j7c - reflect_chance restoration. Per-account 30-second investment cache, same shape/TTL
    // as SpellMitigationCacheEntry (this category shares the same per-hit hook).
    struct ReflectChanceCacheEntry
    {
        double reflectInvested = 0.0;
        uint32_t lastQueryMs = 0;
    };
    static std::unordered_map<uint32_t, ReflectChanceCacheEntry> reflectCacheByAccountId;

    // 8-second per-player notification throttle (NOT 5 seconds like Spell Mitigation's own
    // mitigNotifyTimeByGuid - re-verified directly against the historical source this session:
    // "8-second throttle: reflect is rare enough that each proc warrants a notification",
    // matching cpp_patch's own `s_reflectNotifyTime` exactly).
    static std::unordered_map<uint32_t, uint32_t> reflectNotifyTimeByGuid;

    // E2j8 - life_leech restoration. Per-account 30-second investment cache, same shape/TTL as
    // ReflectChanceCacheEntry (this category shares the same per-hit OnDamage hook as
    // execute_power/armor_pen, but is queried and cached independently - see
    // EchoesQueryLifeLeechInvested's own comment for why this is a separate query rather than
    // folded into EchoesQueryArmorPenExecutePowerInvested).
    struct LifeLeechCacheEntry
    {
        double leechInvested = 0.0;
        uint32_t lastQueryMs = 0;
    };
    static std::unordered_map<uint32_t, LifeLeechCacheEntry> lifeLeechCacheByAccountId;

    // 5-second per-player notification throttle, matching cpp_patch's own `s_leechNotifyTime`/
    // NotifyLeechThrottled exactly (mod_attunement_plus.cpp lines 180-197).
    static std::unordered_map<uint32_t, uint32_t> lifeLeechNotifyTimeByGuid;
}

// Reads ap_mastery.mastery for this CHARACTER guid (character-scoped, confirmed via schema:
// ap_mastery PRIMARY KEY is `guid`, the real character guid - unlike ap_item_snapshot below).
//
// E2j4: returns the RAW, unvalidated value using a wide signed type (int64_t). The column itself
// is `int unsigned` (max ~4.29e9), so int64_t holds its full range with headroom; validation
// against the calculation ceiling (EchoesValidateMasteryRankForCalculation) happens in the caller,
// not here - this function's only job is an honest, non-narrowing read.
static int64_t EchoesQueryMasteryRankRaw(uint32_t charGuid)
{
    QueryResult result = CharacterDatabase.Query(
        "SELECT `mastery` FROM `ap_mastery` WHERE `guid` = {}", charGuid);
    if (!result)
        return 0; // no row - zero rank, never guess
    return (*result)[0].Get<int64_t>();
}

// Reads ap_item_snapshot for this ACCOUNT id. Verified directly against Lua source
// (AP.SaveSnapshotAccountWide inserts using accountId into the `guid` column of
// ap_item_snapshot - despite the column name, this table is account-scoped, not
// character-scoped. Never infer scope from a column name alone.
//
// E2j5a: armor/weapon-damage restoration. Historical source: cpp_patch/mod_attunement_plus.patch
// (echoes-of-the-worldsoul repo, the real working native implementation - never applied to any
// deployed tree, recovered by direct source read). Two deliberately DIFFERENT sourcing strategies,
// matching that patch's own actually-executed behavior exactly:
//   - armor: resolved LIVE from ItemTemplate::Armor here (NOT read from the DB's own `armor`
//     column - that column exists and is populated by ap_core.lua for the separate Lua-native
//     display track only). The historical patch's own comment explains why: "DB column unreliable
//     for WotLK items whose armor is calculated dynamically... not stored in armor column." The
//     patch also contained a ScalingStatValue-adjusted self-heal path (PatchEquippedItemArmor)
//     that wrote an adjusted value into the snapshot's armor column - but its own
//     CalculateAbsorption function never read that column back (its SELECT omits `armor`
//     entirely), so that adjustment was write-only/dead code even in the original historical
//     source. This module replicates the ACTUALLY-EXECUTED behavior (raw ItemTemplate::Armor),
//     not the write-only self-heal path - a known limitation for ScalingStatValue (heirloom/PvP
//     scaling) items, inherited unchanged from history, not introduced by this phase.
//   - weaponDps: read from the DB's own `weapon_dps` column - FROZEN at attunement time by
//     ap_core.lua's AP.ComputeSnapshotStatsFromItemTemplate, exactly matching the historical
//     patch's own behavior (which read weapon_dps from the snapshot row, not live).
static std::vector<EchoesStatSnapshotRow> EchoesQuerySnapshots(uint32_t accountId)
{
    std::vector<EchoesStatSnapshotRow> rows;
    QueryResult result = CharacterDatabase.Query(
        "SELECT `item_entry`, `str`, `agi`, `sta`, `int`, `spi`, `weapon_dps` FROM `ap_item_snapshot` WHERE `guid` = {}",
        accountId);
    if (!result)
        return rows;

    do
    {
        Field* f = result->Fetch();
        uint32_t itemEntry = f[0].Get<uint32_t>();
        EchoesStatSnapshotRow row;
        row.str = f[1].Get<float>();
        row.agi = f[2].Get<float>();
        row.sta = f[3].Get<float>();
        row.intellect = f[4].Get<float>();
        row.spirit = f[5].Get<float>();
        row.weaponDps = f[6].Get<float>();

        ItemTemplate const* proto = sObjectMgr->GetItemTemplate(itemEntry);
        if (proto && proto->Class == ITEM_CLASS_ARMOR)
        {
            row.isArmor = true;
            row.armorSubClass = static_cast<uint8_t>(proto->SubClass);
        }
        else
        {
            row.isArmor = false; // weapon or unknown - never filtered by armor class
            row.armorSubClass = 0;
        }
        // Live armor lookup - see header comment above. proto may be null for a deleted/renamed
        // item_entry; row.armor correctly stays 0 in that case (never fabricated).
        row.armor = proto ? static_cast<double>(proto->Armor) : 0.0;
        rows.push_back(row);
    } while (result->NextRow());

    return rows;
}

// E2j5e: reads ap_talents for this CHARACTER guid - same scope as ap_mastery (confirmed via
// ap_core.lua's AP.LoadTalents/AP.SaveTalent, both keyed by AP.RT.GetGUID(player), the character
// guid, exactly like AP.LoadTalents's sibling ap_mastery reads), and exactly matching the
// historical patch's own single `guid` variable shared by both its Mastery and Talent queries.
// Schema confirmed via env/dist/lua_scripts/ap04_db.lua's REQUIRED_TABLES/REQUIRED_COLUMNS
// (`ap_talents`: guid, stat_index, rank) and ap_core.lua lines 545-577 - read-only input, this
// phase does not modify persistence, purchase cost, or the Lua UI in any way.
static EchoesTalentInput EchoesQueryTalents(uint32_t charGuid)
{
    EchoesTalentInput input;
    QueryResult result = CharacterDatabase.Query(
        "SELECT `stat_index`, `rank` FROM `ap_talents` WHERE `guid` = {}", charGuid);
    if (!result)
        return input; // no rows - zero investment, never guess

    do
    {
        Field* f = result->Fetch();
        int32_t idx = f[0].Get<int32_t>();
        int32_t rank = f[1].Get<int32_t>();
        if (idx >= 0 && idx < 5)
            input.ranks[idx] = rank; // fail closed on any out-of-range stat_index (ignore, don't guess)
    } while (result->NextRow());

    return input;
}

// ---------------------------------------------------------------------------
// E2j5h Stage 2 - Fortitude restoration.
//
// Owner: mod-echoes-stats, per the same Stage-3 recommendation as Spell Mitigation (this module
// already owns Mastery/Talent/armor/weapon-dps absorption via the same cpp_patch lineage).
//
// Unlike Spell Mitigation (a brand-new UnitScript::ModifySpellDamageTaken hook - new engine
// surface), Fortitude introduces NO new engine surface at all: the recovered application primitive
// is `player->ApplyStatBuffMod(AP_STATS[2], val, true)`, and this module's already-live,
// already-proven EchoesApplyDelta()/HandleStatFlatModifier(...STAT_STAMINA...)/UpdateStatBuffMod
// path is the modern equivalent already running today for the STA component of the 5-primary-stat
// absorption bonus. Fortitude is wired in by reading one more ap_aether_sinks category and folding
// one more multiplier into the SAME EchoesStatBonus that EchoesRecalculateAndApply already computes
// and applies via the SAME EchoesApplyDelta call - no new hook registration, no new apply/removal
// codepath, no new engine call. This is the lowest-risk of the three E2j5g-recovered gaps per the
// contract-recovery report's own comparison, confirmed again here by direct re-inspection: it reuses
// 100% of the already-proven Mastery/Talent stat-application machinery below.
//
// Refresh triggers: identical to the rest of this module's recalculation triggers (login, logout,
// level-change, plus the bounded 60s periodic safety net) - no new trigger is added, matching the
// recovered contract's finding that Fortitude's only listed triggers (login/logout/level/equip) are
// already covered by this module's existing hook set for exactly the reason explained in this file's
// own header comment (equip is not a correctness-relevant trigger for the account-wide,
// not-per-item Aether Sink investment either - Fortitude's `invested` value, like Mastery rank, does
// not depend on what is currently equipped).
//
// Death/resurrection: no special-casing exists in cpp_patch for Fortitude (confirmed by this
// phase's own direct re-read - see EchoesStatsCalculator.h's citation above), and none is added
// here - this relies entirely on the same AzerothCore stat-modifier/health-recalculation behavior
// the live Mastery/Talent STA path already exercises today, not a new risk surface.
//
// Max-health recalculation safety: NOT independently re-derived from AzerothCore core source in
// this pass (the recovered contract itself flags this as "inferred by analogy, not
// independently re-derived"). This module's EchoesApplyDelta already calls
// player->UpdateStatBuffMod(STAT_STAMINA) after every STA HandleStatFlatModifier change for the
// existing Mastery/Talent bonus, today, in production - Fortitude's STA delta flows through that
// exact same call with no new code path, so whatever health-preservation guarantee that call
// already provides for the live STA bonus applies identically to Fortitude's contribution. No
// engine-source finding in this pass contradicts the recovered contract's expectation.
//
// Removal / rank-decrease: per the recovered contract, Crucible investments are one-directional
// accumulation - no decrease/refund path exists in ap_aether_sinks, so "rank decrease" is not part
// of the recovered contract and is not implemented here. "Removal" in this module's own sense
// (OnPlayerLogout) is already handled for free by the existing EchoesRemoveAll/EchoesApplyDelta
// idiom, which zeroes out the entire recorded AppliedBonus (Fortitude-inflated STA included)
// exactly like every other stat this module tracks - no Fortitude-specific removal code is needed.
//
// Order of operations: per the recovered contract, Fortitude multiplies whatever STA value
// EchoesCalculateAbsorption already produced (already Mastery-scaled per-row, already
// Talent-scaled per-row since E2j5e) - applied here as a single post-step multiplier on the
// finished EchoesStatBonus::sta, mathematically identical to applying it inside the per-row loop
// (see EchoesStatsCalculator.h's EchoesApplyFortitudeMultiplier comment for the distributivity
// argument). Spell Mitigation independence: Fortitude is consumed only inside
// EchoesRecalculateAndApply (login/logout/level/periodic path); Spell Mitigation is consumed only
// inside EchoesStatsUnitScript::ModifySpellDamageTaken (per-hit path) - the two share no state,
// confirmed by direct source read (EchoesStatsState::mitigCacheByAccountId/mitigNotifyTimeByGuid
// are never read by EchoesRecalculateAndApply, and EchoesStatsState::appliedByGuid is never read by
// ModifySpellDamageTaken).
//
// Reads ap_aether_sinks for this ACCOUNT id, category='fortitude' only - same account-wide scope
// as Spell Mitigation's own category read (both confirmed via ap_sinks.lua's
// AP.Sinks.LoadForAccount(accountId)/account_id column). Deliberately NOT cached (unlike Spell
// Mitigation's 30-second cache): EchoesRecalculateAndApply is only ever called on discrete,
// infrequent triggers (login/logout/level-change) or at most once per 60 seconds per player via the
// periodic safety net - already far less frequent than Spell Mitigation's per-hit call site, which
// is what motivated that cache in the first place. Matches this module's existing
// EchoesQueryMasteryRankRaw/EchoesQueryTalents query style (direct, uncached) rather than
// introducing an unnecessary second caching convention for a call site that does not need one.
static double EchoesQueryFortitudeInvested(uint32_t accountId)
{
    QueryResult result = CharacterDatabase.Query(
        "SELECT `invested` FROM `ap_aether_sinks` WHERE `account_id` = {} AND `category` = 'fortitude'",
        accountId);
    if (!result)
        return 0.0; // no row - zero investment, never guess
    return static_cast<double>((*result)[0].Get<uint32>());
}

// ---------------------------------------------------------------------------
// E2j7a - melee_power/spell_power restoration.
//
// Owner: mod-echoes-stats, same lineage as Fortitude/Spell Mitigation/rating sinks. See
// EchoesStatsCalculator.h's citation above EchoesApplyMeleeSpellPowerMultipliers for the full
// formula/ceiling/k recovery.
//
// Refresh triggers, removal, and order-of-operations: identical to Fortitude (see
// EchoesQueryFortitudeInvested's header comment above) - applied AFTER EchoesCalculateAbsorption
// returns, multiplying the already Mastery/Talent-scaled weaponDps and intellect values; removal
// handled for free by the existing EchoesRemoveAll/EchoesApplyDelta idiom.
//
// Reads both categories in one combined query, matching EchoesQueryRatingSinksInvested's combined
// style (two related categories, one query) rather than EchoesQueryFortitudeInvested's single-
// category style (one category alone). Deliberately NOT cached, same reasoning as Fortitude/
// rating sinks: this call site fires only on login/logout/level-change or at most once per 60s.
struct EchoesMeleeSpellPowerInvested
{
    double melee = 0.0, spell = 0.0;
};

static EchoesMeleeSpellPowerInvested EchoesQueryMeleeSpellPowerInvested(uint32_t accountId)
{
    EchoesMeleeSpellPowerInvested inv;
    QueryResult result = CharacterDatabase.Query(
        "SELECT `category`, `invested` FROM `ap_aether_sinks` WHERE `account_id` = {} AND `category` IN "
        "('melee_power', 'spell_power')", accountId);
    if (!result)
        return inv; // no rows - zero investment for both, never guess

    do
    {
        Field* f = result->Fetch();
        std::string category = f[0].Get<std::string>();
        double invested = static_cast<double>(f[1].Get<uint32>());
        if (category == "melee_power")      inv.melee = invested;
        else if (category == "spell_power") inv.spell = invested;
    } while (result->NextRow());

    return inv;
}

// ---------------------------------------------------------------------------
// E2j6 - Combat-rating restoration: crit_rating, haste_rating, dodge_rating, parry_rating.
//
// Owner: mod-echoes-stats, same lineage as Fortitude/Spell Mitigation/armor/weapon-dps (all
// recovered from the same cpp_patch/mod_attunement_plus.patch source and ap_sinks.lua's
// AP.SinkDefs). See EchoesStatsCalculator.h's citation above for the full formula/ceiling/k
// recovery and the documented GetRatingMultiplier-vs-historical-hardcoded-constant deviation.
//
// Refresh triggers: identical to Fortitude - login/logout/level-change/60s periodic safety net.
// No new trigger needed (rating-sink `invested` does not depend on equip state, same as every
// other Aether Sink category).
//
// Removal: handled for free by the existing EchoesRemoveAll/EchoesApplyDelta idiom (zeroes the
// entire AppliedBonus, rating fields included) - no rating-specific removal code needed.
//
// Reads all four categories in one combined query (matching cpp_patch's own combined multi-
// category query shape more closely than four separate single-category queries would - see
// EchoesQueryFortitudeInvested's single-category style above, used here only per-row, not
// per-query). Deliberately NOT cached, same reasoning as EchoesQueryFortitudeInvested: this call
// site fires only on login/logout/level-change or at most once per 60s per player via the
// periodic safety net, far less often than Spell Mitigation's per-hit call site that actually
// motivated its 30s cache.
struct EchoesRatingSinksInvested
{
    double crit = 0.0, haste = 0.0, dodge = 0.0, parry = 0.0;
};

static EchoesRatingSinksInvested EchoesQueryRatingSinksInvested(uint32_t accountId)
{
    EchoesRatingSinksInvested inv;
    QueryResult result = CharacterDatabase.Query(
        "SELECT `category`, `invested` FROM `ap_aether_sinks` WHERE `account_id` = {} AND `category` IN "
        "('crit_rating', 'haste_rating', 'dodge_rating', 'parry_rating')", accountId);
    if (!result)
        return inv; // no rows - zero investment for all four, never guess

    do
    {
        Field* f = result->Fetch();
        std::string category = f[0].Get<std::string>();
        double invested = static_cast<double>(f[1].Get<uint32>());
        if (category == "crit_rating")       inv.crit  = invested;
        else if (category == "haste_rating") inv.haste = invested;
        else if (category == "dodge_rating") inv.dodge = invested;
        else if (category == "parry_rating") inv.parry = invested;
    } while (result->NextRow());

    return inv;
}

// Compact helper around rating-delta application - the rating-space equivalent of
// EchoesApplyDelta's "remove old contribution (apply=false), apply new contribution (apply=true)"
// idiom, generalized over a small fixed list of CombatRating enums so one call covers Crit's 3 CRs
// or Haste's 3 CRs (and a single-element list covers Dodge/Parry) without duplicating the
// old/new-comparison logic four times. `ApplyRatingMod` already calls UpdateRating(cr) internally
// (confirmed in e2j6-CONTRACT-RECOVERY.md), so no separate recalculation call is needed here,
// unlike EchoesApplyDelta's primary-stat/armor/attack-power branches.
static void EchoesApplyRatingGroupDelta(Player* player, std::initializer_list<CombatRating> crs,
    int32_t const* oldPoints, int32_t const* newPoints)
{
    size_t i = 0;
    for (CombatRating cr : crs)
    {
        int32_t oldVal = oldPoints[i];
        int32_t newVal = newPoints[i];
        ++i;
        if (oldVal == newVal)
            continue;
        if (oldVal != 0)
            player->ApplyRatingMod(cr, oldVal, false);
        if (newVal != 0)
            player->ApplyRatingMod(cr, newVal, true);
    }
}

// ---------------------------------------------------------------------------
// E2j5g Stage 7 - Spell Mitigation restoration.
//
// Evidence gate (per this phase's own required reading, step 1): a direct source read of
// EchoesStatsHooks.cpp/EchoesStatsCalculator.h BEFORE this change confirmed zero existing
// spell-damage-taken consumer anywhere in this module or the rest of the current DML tree - the
// only hooks previously registered here were PLAYERHOOK_ON_LOGIN/ON_LOGOUT/ON_LEVEL_CHANGED
// (PlayerScript) and the WORLDHOOK_* set (WorldScript). No UnitScript subclass existed in this
// module, and a tree-wide grep for "public UnitScript" (src/ and modules/) returned zero matches
// anywhere in the current DML tree - `UnitScript::ModifySpellDamageTaken` is genuinely unused
// engine surface being wired for the first time by this change, exactly as the contract-recovery
// report's "Current source surface: none" finding stated.
//
// Historical source, re-verified directly against cpp_patch/mod_attunement_plus.patch (not just
// the contract-recovery report's paraphrase) before writing this hook - see
// EchoesStatsCalculator.h's own citation above for the exact recovered formula/gating structure.
// Owner: mod-echoes-stats, per Jonah's explicit resolution of Stage 7's ownership question
// (this module already owns Mastery/Talent/armor/weapon-dps absorption via the same
// cpp_patch/mod_attunement_plus.patch lineage).
//
// Engine hook verified against the CURRENT core (not assumed from the historical patch): the
// historical patch's own `ModifySpellDamageTaken(Unit*, Unit*, int32&, SpellInfo const*)`
// UnitScript override signature is confirmed byte-identical to the live declaration in this core's
// src/server/game/Scripting/ScriptDefines/UnitScript.h (UNITHOOK_MODIFY_SPELL_DAMAGE_TAKEN, called
// from Unit.cpp's Unit::SpellDamageBonusTaken path via
// sScriptMgr->ModifySpellDamageTaken(damageInfo->target, damageInfo->attacker, damage, spellInfo)
// - "post class mitigation calculations" per that call site's own comment). Nothing about this
// hook's name, signature, or firing point has changed since the historical patch was written.

// Reads ap_aether_sinks for this ACCOUNT id, category='spell_mitigation' only - deliberately a
// narrower single-category query than cpp_patch's own combined 5-category `s_sinkCache` (that
// patch's other 4 cached categories - life_leech, armor_pen, execute_power, reflect_chance - are
// NOT part of this phase's scope and are not restored here; see this phase's explicit exclusions).
// Cached 30 seconds per account, matching cpp_patch's `s_sinkCache` cache lifetime exactly.
// Schema confirmed live (not just historically) via env/dist/lua_scripts/ap04_db.lua's
// REQUIRED_TABLES/REQUIRED_COLUMNS ("ap_aether_sinks": account_id, category, invested) and
// ap_sinks.lua's own AP.Sinks.LoadForAccount/AP.Sinks.Invest, both account_id-scoped, matching
// cpp_patch's own query shape exactly - no schema drift between the historical patch and the
// live table.
static double EchoesQuerySpellMitigationInvested(uint32_t accountId)
{
    uint32_t now = getMSTime();
    auto& entry = EchoesStatsState::mitigCacheByAccountId[accountId];
    if (entry.lastQueryMs != 0 && (now - entry.lastQueryMs) < 30000)
        return entry.mitigInvested;

    QueryResult result = CharacterDatabase.Query(
        "SELECT `invested` FROM `ap_aether_sinks` WHERE `account_id` = {} AND `category` = 'spell_mitigation'",
        accountId);

    entry.mitigInvested = 0.0; // no row - zero investment, never guess
    if (result)
        entry.mitigInvested = static_cast<double>((*result)[0].Get<uint32>());

    entry.lastQueryMs = now;
    return entry.mitigInvested;
}

// E2j7b - reads both execute_power/armor_pen in one combined query, 30-second account-scoped
// cache (same reasoning as EchoesQuerySpellMitigationInvested above - this call site fires per-hit,
// far more often than the login/logout/level/60s-periodic triggers the uncached categories use).
static void EchoesQueryArmorPenExecutePowerInvested(uint32_t accountId, double& executePowerInvested, double& armorPenInvested)
{
    uint32_t now = getMSTime();
    auto& entry = EchoesStatsState::armorPenExecutePowerCacheByAccountId[accountId];
    if (entry.lastQueryMs != 0 && (now - entry.lastQueryMs) < 30000)
    {
        executePowerInvested = entry.executePowerInvested;
        armorPenInvested = entry.armorPenInvested;
        return;
    }

    entry.executePowerInvested = 0.0;
    entry.armorPenInvested = 0.0;

    QueryResult result = CharacterDatabase.Query(
        "SELECT `category`, `invested` FROM `ap_aether_sinks` WHERE `account_id` = {} AND `category` IN "
        "('execute_power', 'armor_pen')", accountId);
    if (result)
    {
        do
        {
            Field* f = result->Fetch();
            std::string category = f[0].Get<std::string>();
            double invested = static_cast<double>(f[1].Get<uint32>());
            if (category == "execute_power")   entry.executePowerInvested = invested;
            else if (category == "armor_pen")  entry.armorPenInvested = invested;
        } while (result->NextRow());
    }

    entry.lastQueryMs = now;
    executePowerInvested = entry.executePowerInvested;
    armorPenInvested = entry.armorPenInvested;
}

// E2j7c - single-category query for reflect_chance, matching EchoesQuerySpellMitigationInvested's
// exact precedent (30-second account-scoped cache, same per-hit-hook reasoning). Reads only the
// DEFENDING player's own account_id - no ownership-chain walking for pets/guardians as defenders,
// per Jonah's explicit instruction that the defender itself must own the investment row.
static double EchoesQueryReflectChanceInvested(uint32_t accountId)
{
    uint32_t now = getMSTime();
    auto& entry = EchoesStatsState::reflectCacheByAccountId[accountId];
    if (entry.lastQueryMs != 0 && (now - entry.lastQueryMs) < 30000)
        return entry.reflectInvested;

    QueryResult result = CharacterDatabase.Query(
        "SELECT `invested` FROM `ap_aether_sinks` WHERE `account_id` = {} AND `category` = 'reflect_chance'",
        accountId);

    entry.reflectInvested = 0.0; // no row - zero investment, never guess
    if (result)
        entry.reflectInvested = static_cast<double>((*result)[0].Get<uint32>());

    entry.lastQueryMs = now;
    return entry.reflectInvested;
}

// E2j8 - single-category query for life_leech, matching EchoesQueryReflectChanceInvested's exact
// precedent (30-second account-scoped cache, same per-hit-hook reasoning). Kept as its own query
// rather than folded into EchoesQueryArmorPenExecutePowerInvested deliberately - that function is
// already shipped and tested (E2j7b), and life_leech's own eligibility gate in OnDamage (see below)
// needs its own investment value queried BEFORE the combined execute/armor_pen early-return check,
// so a player with ONLY life_leech invested (the real-world common case - see
// LIFE-LEECH-CONTRACT-RECOVERY-AND-RESTORATION-ENGINEERING-PLAN.md Section 5) is not skipped.
static double EchoesQueryLifeLeechInvested(uint32_t accountId)
{
    uint32_t now = getMSTime();
    auto& entry = EchoesStatsState::lifeLeechCacheByAccountId[accountId];
    if (entry.lastQueryMs != 0 && (now - entry.lastQueryMs) < 30000)
        return entry.leechInvested;

    QueryResult result = CharacterDatabase.Query(
        "SELECT `invested` FROM `ap_aether_sinks` WHERE `account_id` = {} AND `category` = 'life_leech'",
        accountId);

    entry.leechInvested = 0.0; // no row - zero investment, never guess
    if (result)
        entry.leechInvested = static_cast<double>((*result)[0].Get<uint32>());

    entry.lastQueryMs = now;
    return entry.leechInvested;
}

// 5-second per-player throttle, matching cpp_patch's own NotifyLeechThrottled exactly (including
// its notification text, recovered verbatim this session - mod_attunement_plus.cpp lines 184-197).
static void EchoesNotifyLifeLeechThrottled(Player* player, uint32 healAmt)
{
    uint32 now = getMSTime();
    uint32 guid = player->GetGUID().GetCounter();
    auto it = EchoesStatsState::lifeLeechNotifyTimeByGuid.find(guid);
    if (it != EchoesStatsState::lifeLeechNotifyTimeByGuid.end() && (now - it->second) < 5000)
        return;
    EchoesStatsState::lifeLeechNotifyTimeByGuid[guid] = now;

    ChatHandler(player->GetSession()).PSendSysMessage(
        "|cff9966ff[Worldsoul]|r The fallen sustain you. (+{} HP)", healAmt);
}

// 8-second per-player throttle, matching cpp_patch's own NotifyReflectThrottled exactly (including
// its notification text, recovered verbatim this session - NOT the same 5-second cadence or text
// as Spell Mitigation's own throttle, re-verified directly rather than assumed).
static void EchoesNotifyReflectThrottled(Player* player, uint32 reflectDamage)
{
    uint32 now = getMSTime();
    uint32 guid = player->GetGUID().GetCounter();
    auto it = EchoesStatsState::reflectNotifyTimeByGuid.find(guid);
    if (it != EchoesStatsState::reflectNotifyTimeByGuid.end() && (now - it->second) < 8000)
        return;
    EchoesStatsState::reflectNotifyTimeByGuid[guid] = now;

    ChatHandler(player->GetSession()).PSendSysMessage(
        "|cff9966ff[Worldsoul]|r Their power returns to them. ({} damage)", reflectDamage);
}

// 5-second per-player throttle, matching cpp_patch's own NotifyMitigationThrottled exactly
// (including its notification text, recovered verbatim - Stage 7's contract-recovery explicitly
// listed this text as part of the recovered contract, and Jonah's "nothing should change"
// resolution covers it).
static void EchoesNotifySpellMitigationThrottled(Player* player, uint32 reduction)
{
    uint32 now = getMSTime();
    uint32 guid = player->GetGUID().GetCounter();
    auto it = EchoesStatsState::mitigNotifyTimeByGuid.find(guid);
    if (it != EchoesStatsState::mitigNotifyTimeByGuid.end() && (now - it->second) < 5000)
        return;
    EchoesStatsState::mitigNotifyTimeByGuid[guid] = now;

    ChatHandler(player->GetSession()).PSendSysMessage(
        "|cff9966ff[Worldsoul]|r The Worldsoul shields your spirit. (-{} damage)", reduction);
}

// New UnitScript - the first one this module (or any current Echoes module) registers. Fires for
// every spell-damage-taken event server-wide (any Unit, not just players); the gating chain below
// (recovered exactly from cpp_patch, re-verified in this phase's own direct source re-read) is
// what narrows this to the intended scope, matching the historical patch's own guard order exactly:
//   1. target must exist, be a Player, and damage > 0 (bots ARE Player objects server-side, so
//      this includes bots automatically - excludes only non-player targets, e.g. NPCs/pets).
//   2. spellInfo must be non-null - nullptr means a physical auto-attack, which never reaches this
//      hook's mitigation logic at all (excluded, not zero-mitigated).
//   3. spellInfo's school mask must not be SPELL_SCHOOL_MASK_NORMAL - physical-school spell damage
//      is excluded even when spellInfo is non-null, exactly matching cpp_patch's own second guard.
// No config-enabled gate existed in the historical patch for this specific hook (it was a bare
// UnitScript override with no module-enable check at all); this module's EchoesStatsConfig
// convention gates every OTHER hook it registers, so the same convention is applied here too,
// consistent with the disable/re-enable behavior already proven for the rest of this module
// (see the test file's "disable/re-enable non-doubling" structural notes) - this does not change
// any of the recovered formula/gating/floor-rule constants themselves, only whether the module as
// a whole is active at all.
class EchoesStatsUnitScript : public UnitScript
{
public:
    // E2j7b - UNITHOOK_ON_DAMAGE added to this opt-in hook list. Without it, an OnDamage override
    // on this class would compile cleanly but silently never fire (AzerothCore's UnitScript base
    // filters dispatch to only the hooks a script explicitly registers for) - confirmed by direct
    // source read of this constructor's own pre-existing pattern this session, not a hypothetical
    // risk.
    EchoesStatsUnitScript() : UnitScript("EchoesStatsUnitScript", true,
        { UNITHOOK_MODIFY_SPELL_DAMAGE_TAKEN, UNITHOOK_ON_DAMAGE })
    {
    }

    // E2j7b - execute_power/armor_pen restoration. Recovered gate, re-verified directly against
    // the historical source this session (C:\Azerothcore\modules\mod-attunement-plus\src\
    // mod_attunement_plus.cpp, lines 892-969): attacker must be a Player (excludes pets/guardians
    // by construction - Jonah's explicit decision NOT to walk ownership chains), damage must be
    // nonzero, and the gray-mob exclusion (victim 10+ levels below attacker) is preserved
    // unchanged from the historical source, applied uniformly to creature and player victims.
    //
    // Victim eligibility extended from the historical `victim->IsCreature()`-only gate to
    // `victim->IsCreature() || victim->IsPlayer()` per Jonah's explicit PvP-inclusion
    // authorization (2026-07-29 implementation authorization, Section 1) - normal AzerothCore
    // hostility/immunity/damage-validity rules still gate what damage events even reach this hook
    // in the first place (Unit::DealDamage's own callers already filter to valid hostile damage).
    //
    // Mandatory apply order: execute_power FIRST, then armor_pen (load-bearing - see
    // EchoesStatsCalculator.h's citation above EchoesApplyExecutePowerBonus/EchoesApplyArmorPenBonus
    // for the full ordering rationale and test 249/250's proof this is not interchangeable).
    //
    // School gating: NEITHER category is restricted by damage school - Jonah's explicit 2026-07-30
    // decision for armor_pen (OnDamage exposes no school information; see
    // e2j7b-STAGE1-PRE-EDIT-CONTRACT-AND-IDENTITY.md Section 4/9), execute_power was never
    // authorized to be restricted in the first place.
    void OnDamage(Unit* attacker, Unit* victim, uint32& damage) override
    {
        if (!EchoesStatsConfig::instance()->enabled)
            return;
        if (!attacker || !victim || damage == 0)
            return;
        // E2j7c - self-damage guard: reflect_chance deals damage from a player to themselves via
        // Unit::DealDamage(attacker, attacker, ...), which unconditionally reaches this hook.
        // Without this guard, a player's own execute_power/armor_pen investment would amplify
        // their own reflected self-damage - never part of either category's intended contract
        // (E2j7b shipped before this mechanism existed, so this case was never exercised until
        // now). Narrowly scoped: excludes only the attacker==victim case, changes nothing about
        // ordinary attacker-versus-victim damage, PvP, or bot behavior.
        if (attacker == victim)
            return;
        if (!attacker->IsPlayer())
            return; // pet/guardian exclusion by construction - no ownership-chain walking
        if (!victim->IsCreature() && !victim->IsPlayer())
            return; // PvE + PvP per Jonah's explicit decision

        Player* player = attacker->ToPlayer();
        // Gray-mob check, preserved unchanged from the historical source - applies uniformly to
        // creature and player victims (a recovered contract element, not re-derived for PvP).
        if (victim->GetLevel() + 10 < player->GetLevel())
            return;
        if (!player->GetSession())
            return; // fail closed - never guess account scope (same convention as ModifySpellDamageTaken)
        uint32_t accountId = player->GetSession()->GetAccountId();

        double executePowerInvested = 0.0;
        double armorPenInvested = 0.0;
        EchoesQueryArmorPenExecutePowerInvested(accountId, executePowerInvested, armorPenInvested);
        // E2j8 - life_leech queried here, BEFORE the combined early-return gate below, and folded
        // into that gate's condition. Without this, a player with ONLY life_leech invested (no
        // execute_power/armor_pen) would hit the pre-existing "neither invested" early return and
        // Life Leech would never run - this is the real-world common case (see
        // LIFE-LEECH-CONTRACT-RECOVERY-AND-RESTORATION-ENGINEERING-PLAN.md Section 5: the one real
        // human account with an existing investment, and most of the 14 bot accounts, hold ONLY
        // life_leech, not execute_power/armor_pen).
        double leechInvested = EchoesQueryLifeLeechInvested(accountId);
        if (executePowerInvested <= 0.0 && armorPenInvested <= 0.0 && leechInvested <= 0.0)
            return; // none invested - explicit no-op

        // Mandatory order: execute_power first, then armor_pen, then life_leech (E2j8 - Jonah's
        // 2026-07-30 implementation authorization Section 4). Life Leech heals from the FINAL
        // damage value after both prior categories have mutated it, and never itself mutates
        // `damage` - see EchoesComputeLifeLeechHeal's own citation in EchoesStatsCalculator.h and
        // test 312-314's proof this ordering is load-bearing. Diagnostic instrumentation
        // (isolated-validation/disposable/production-checkpoint observability, matching this
        // project's established per-phase instrumentation convention) captures each stage's
        // damage value - unthrottled, but only ever reached when at least one category is
        // invested (the early-return above), naturally bounding volume to investing players only.
        uint32_t incomingDamage = damage;
        float victimHealthPct = victim->GetHealthPct();
        damage = EchoesApplyExecutePowerBonus(damage, victimHealthPct, executePowerInvested);
        uint32_t afterExecute = damage;

        double reductionFrac = 0.0;
        uint32_t afterArmorPen = damage;
        if (armorPenInvested > 0.0)
        {
            reductionFrac = EchoesArmorPenReductionFraction(
                static_cast<double>(victim->GetArmor()), player->GetLevel());
            damage = EchoesApplyArmorPenBonus(damage, reductionFrac, armorPenInvested);
            afterArmorPen = damage;
        }

        // E2j8 - life_leech: heals the attacker for a percentage of the final (post-execute_power,
        // post-armor_pen) damage value. Read-only with respect to `damage` - never mutates it.
        // Victim eligibility (creature or player, per the shared guard chain above) already
        // includes PvP - a NEW approved Echoes 2.0 behavior, not historical fidelity (the
        // historical patch's own gate was `victim->IsCreature()`-only). Pet/guardian attackers and
        // reflected self-damage are already excluded by the guard chain above this block runs
        // after (attacker->IsPlayer(), attacker == victim), so no separate guard is needed here.
        uint32_t lifeLeechHeal = 0;
        if (leechInvested > 0.0)
        {
            uint32_t rawHeal = EchoesComputeLifeLeechHeal(damage, leechInvested);
            if (rawHeal > 0)
            {
                uint32_t curHP = player->GetHealth();
                uint32_t maxHP = player->GetMaxHealth();
                lifeLeechHeal = EchoesClampLifeLeechHeal(rawHeal, curHP, maxHP);
                if (lifeLeechHeal > 0)
                {
                    player->SetHealth(curHP + lifeLeechHeal);
                    EchoesNotifyLifeLeechThrottled(player, lifeLeechHeal);
                }
            }
        }

        LOG_INFO("module", "[mod-echoes-stats] E2j7b/E2j8 OnDamage attacker={} victim={} victimIsPlayer={} "
            "victimLevel={} victimHealthPct={:.2f} victimArmor={} attackerLevel={} "
            "executePowerInvested={:.0f} armorPenInvested={:.0f} leechInvested={:.0f} reductionFrac={:.4f} "
            "incomingDamage={} afterExecute={} afterArmorPen={} lifeLeechHeal={}",
            player->GetGUID().GetCounter(), victim->GetGUID().GetCounter(), victim->IsPlayer(),
            victim->GetLevel(), victimHealthPct, victim->GetArmor(), player->GetLevel(),
            executePowerInvested, armorPenInvested, leechInvested, reductionFrac,
            incomingDamage, afterExecute, afterArmorPen, lifeLeechHeal);
    }

    // E2j7c - restructured to make Spell Mitigation and Reflect Chance independently-gated
    // sequential blocks (each with its own `if (invested > 0.0)` check), matching the historical
    // source's own shape exactly. Previously, `mitigInvested <= 0.0` and `reduction == 0` each
    // returned from the WHOLE function - which would have silently skipped Reflect Chance entirely
    // for any player with reflect_chance invested but not spell_mitigation (or whose mitigation
    // fraction rounds to zero reduction). Confirmed byte-identical Spell Mitigation output for any
    // reflect-uninvested player (disposable-verification regression test, Stage 4) - this is a
    // required structural correction to add Reflect Chance additively, not a Spell Mitigation
    // behavior change.
    void ModifySpellDamageTaken(Unit* target, Unit* attacker, int32& damage, SpellInfo const* spellInfo) override
    {
        if (!EchoesStatsConfig::instance()->enabled)
            return;
        if (!target || !target->IsPlayer() || damage <= 0)
            return;
        // nullptr spellInfo = physical auto-attack; skip all non-spell damage (recovered guard)
        if (!spellInfo)
            return;
        // Skip physical school (SPELL_SCHOOL_MASK_NORMAL) - recovered guard
        if (spellInfo->GetSchoolMask() == SPELL_SCHOOL_MASK_NORMAL)
            return;

        Player* player = target->ToPlayer();
        if (!player->GetSession())
            return; // fail closed - never guess account scope (same convention as EchoesRecalculateAndApply)
        uint32_t accountId = player->GetSession()->GetAccountId();

        double mitigInvested = EchoesQuerySpellMitigationInvested(accountId);
        double reflectInvested = EchoesQueryReflectChanceInvested(accountId);
        if (mitigInvested <= 0.0 && reflectInvested <= 0.0)
            return; // neither invested - explicit no-op

        // Spell Mitigation - unchanged formula/ordering, now independently gated rather than
        // exiting the whole function.
        if (mitigInvested > 0.0)
        {
            uint32_t reduction = EchoesComputeSpellMitigationReduction(damage, mitigInvested);
            if (reduction > 0)
            {
                damage -= static_cast<int32>(reduction);
                EchoesNotifySpellMitigationThrottled(player, reduction);
            }
        }

        // Reflect Chance - operates on the (possibly Spell-Mitigation-reduced) remaining damage,
        // matching the historical source's own ordering (mitigation first, reflect second, both
        // inside this same hook). Recovered gate: attacker must exist and differ from target -
        // preserved unchanged. No attacker->IsPlayer() gate here (unlike E2j7b's OnDamage) - a
        // creature, pet, or guardian attacker can trigger a player's reflect_chance, matching the
        // recovered historical contract exactly (Jonah's explicit confirmation this differs from
        // E2j7b's own pet-exclusion precedent).
        if (reflectInvested > 0.0 && damage > 0 && attacker && attacker != target)
        {
            double reflectFrac = EchoesReflectChanceFraction(reflectInvested);
            uint32_t threshold = EchoesReflectChanceThreshold(reflectFrac);
            if (threshold > 0)
            {
                uint32_t roll = urand(0, 9999);
                if (EchoesReflectChanceRollTriggered(roll, threshold))
                {
                    uint32_t reflectDamage = static_cast<uint32_t>(damage);
                    damage = 0;

                    // Direct DealDamage call, spellInfo=nullptr - bypasses
                    // Unit::CalculateSpellDamageTaken entirely (the only call site for THIS hook),
                    // so reflected damage cannot re-enter ModifySpellDamageTaken for either
                    // participant. Re-verified against the current core this session
                    // (Unit.cpp:1534 is the sole call site; Unit::DealDamage never invokes it).
                    // This same DealDamage call DOES reach EchoesStatsUnitScript::OnDamage
                    // (Unit.cpp:1026, unconditional) - the attacker==victim guard added to
                    // OnDamage this phase is what prevents execute_power/armor_pen from amplifying
                    // this self-damage.
                    Unit::DealDamage(attacker, attacker, reflectDamage, nullptr,
                        DIRECT_DAMAGE, SPELL_SCHOOL_MASK_NORMAL, nullptr, false);

                    EchoesNotifyReflectThrottled(player, reflectDamage);

                    // Diagnostic instrumentation (isolated-validation/disposable/production-
                    // checkpoint observability, matching E2j7b's own per-hit instrumentation
                    // convention) - unthrottled, but only ever reached on an actual successful
                    // reflect roll, naturally bounding volume.
                    LOG_INFO("module", "[mod-echoes-stats] E2j7c reflect triggered defender={} "
                        "attacker={} reflectInvested={:.0f} reflectFrac={:.4f} threshold={} roll={} "
                        "reflectDamage={}",
                        player->GetGUID().GetCounter(), attacker->GetGUID().GetCounter(),
                        reflectInvested, reflectFrac, threshold, roll, reflectDamage);
                }
            }
        }
    }
};

// Applies the exact delta between the newly-calculated bonus and whatever this module
// currently has applied for this player - the phase's own recommended invariant
// ("desired - currently applied = exact delta to apply"). Uses the same
// Unit::HandleStatFlatModifier(TOTAL_VALUE, amount, apply) primitive real stat auras use
// (AuraEffect::HandleAuraModStat, SpellAuraEffects.cpp) - never SetStatFlatModifier, which
// would silently clobber every other stat source (gear, buffs) sharing that slot.
static void EchoesApplyDelta(Player* player, EchoesStatsState::AppliedBonus const& oldB, EchoesStatBonus const& newB)
{
    struct StatPair { double oldVal; double newVal; Stats stat; };
    StatPair pairs[5] = {
        { oldB.str, newB.str, STAT_STRENGTH },
        { oldB.agi, newB.agi, STAT_AGILITY },
        { oldB.sta, newB.sta, STAT_STAMINA },
        { oldB.intellect, newB.intellect, STAT_INTELLECT },
        { oldB.spirit, newB.spirit, STAT_SPIRIT },
    };

    for (auto const& p : pairs)
    {
        double delta = p.newVal - p.oldVal;
        if (std::abs(delta) < 0.0001)
            continue; // no meaningful change - never apply a zero/near-zero delta
        UnitMods mod = UnitMods(static_cast<uint32>(UNIT_MOD_STAT_START) + static_cast<uint32>(p.stat));
        // Remove the old contribution, apply the new one - two explicit calls rather than one
        // "apply signed delta" call, matching the exact idiom AuraEffect::HandleAuraModStat uses
        // (apply=false then apply=true) so this is provably the same safe pattern, not a novel one.
        if (p.oldVal != 0.0)
            player->HandleStatFlatModifier(mod, TOTAL_VALUE, static_cast<float>(p.oldVal), false);
        if (p.newVal != 0.0)
            player->HandleStatFlatModifier(mod, TOTAL_VALUE, static_cast<float>(p.newVal), true);
        player->UpdateStatBuffMod(p.stat);
    }

    // E2j5a: armor - identical idempotent delta pattern, using UNIT_MOD_ARMOR (verified present
    // in the current core, Unit.h) instead of a STAT_* index. UpdateArmor() is the corresponding
    // recalculation trigger (mirrors UpdateStatBuffMod's role for primary stats) - confirmed via
    // direct source read of Unit.h/Player.h; matches the historical patch's own
    // HandleStatModifier(UNIT_MOD_ARMOR,...)+UpdateArmor() pattern (adapted to this core's actual
    // function name, HandleStatFlatModifier - "HandleStatModifier" does not exist in this core).
    {
        double armorDelta = newB.armor - oldB.armor;
        if (std::abs(armorDelta) >= 0.0001)
        {
            if (oldB.armor != 0.0)
                player->HandleStatFlatModifier(UNIT_MOD_ARMOR, TOTAL_VALUE, static_cast<float>(oldB.armor), false);
            if (newB.armor != 0.0)
                player->HandleStatFlatModifier(UNIT_MOD_ARMOR, TOTAL_VALUE, static_cast<float>(newB.armor), true);
            player->UpdateArmor();
        }
    }

    // E2j5a: weapon-damage absorption, converted to flat Attack Power via the recovered x7
    // constant (EchoesWeaponDpsToAttackPower) - matches the historical patch's own
    // HandleStatModifier(UNIT_MOD_ATTACK_POWER,...)+UpdateAttackPowerAndDamage() pattern exactly,
    // adapted to this core's actual HandleStatFlatModifier function name.
    {
        double newAttackPower = EchoesWeaponDpsToAttackPower(newB.weaponDps);
        double apDelta = newAttackPower - oldB.attackPower;
        if (std::abs(apDelta) >= 0.0001)
        {
            if (oldB.attackPower != 0.0)
                player->HandleStatFlatModifier(UNIT_MOD_ATTACK_POWER, TOTAL_VALUE, static_cast<float>(oldB.attackPower), false);
            if (newAttackPower != 0.0)
                player->HandleStatFlatModifier(UNIT_MOD_ATTACK_POWER, TOTAL_VALUE, static_cast<float>(newAttackPower), true);
            player->UpdateAttackPowerAndDamage();
        }
    }
}

static void EchoesRecalculateAndApply(Player* player)
{
    if (!player || !player->IsInWorld())
        return;
    if (!EchoesStatsConfig::instance()->enabled)
        return;

    uint32_t guidLow = player->GetGUID().GetCounter();
    uint32_t accountId = player->GetSession() ? player->GetSession()->GetAccountId() : 0;
    if (accountId == 0)
        return; // fail closed - never guess account scope

    int64_t rawMasteryRank = EchoesQueryMasteryRankRaw(guidLow);
    EchoesMasteryRankValidation validation = EchoesValidateMasteryRankForCalculation(rawMasteryRank);
    uint32_t masteryRank = validation.validatedRank; // stored row itself is never touched
    if (validation.wasNegativeOrInvalid || validation.wasAboveCeiling)
    {
        auto warnIt = EchoesStatsState::lastWarnedRawMasteryRankByGuid.find(guidLow);
        bool alreadyWarnedForThisValue = warnIt != EchoesStatsState::lastWarnedRawMasteryRankByGuid.end()
            && warnIt->second == rawMasteryRank;
        if (!alreadyWarnedForThisValue)
        {
            LOG_WARN("module", "[mod-echoes-stats] guid={} raw ap_mastery.mastery={} is {} - "
                "using Rank {} for this calculation only; the stored row is NOT modified. This is "
                "a defensive calculation-input ceiling, not a gameplay progression cap.",
                guidLow, rawMasteryRank,
                validation.wasNegativeOrInvalid ? "negative/invalid" : "above the calculation ceiling",
                masteryRank);
            EchoesStatsState::lastWarnedRawMasteryRankByGuid[guidLow] = rawMasteryRank;
        }
    }

    std::vector<EchoesStatSnapshotRow> snapshots = EchoesQuerySnapshots(accountId);
    uint8_t wowClass = static_cast<uint8_t>(player->getClass());
    uint32_t level = player->GetLevel();
    EchoesTalentInput talents = EchoesQueryTalents(guidLow); // E2j5e

    EchoesStatsConfig* cfg = EchoesStatsConfig::instance();
    EchoesStatBonus newBonus = EchoesCalculateAbsorption(snapshots, masteryRank, level, wowClass,
        cfg->masteryBaseAbsorb, cfg->masteryMaxAbsorb, cfg->masteryDecayK, talents);

    // E2j5h Stage 2 - Fortitude: multiplies the already Mastery+Talent-scaled STA bonus above.
    // See this file's header comment (above EchoesQueryFortitudeInvested) for the full ordering/
    // safety rationale. Deliberately applied AFTER EchoesCalculateAbsorption returns, never inside
    // it - keeps the already-proven absorption function's signature/behavior fully untouched.
    double fortitudeInvested = EchoesQueryFortitudeInvested(accountId);
    newBonus = EchoesApplyFortitudeMultiplier(newBonus, fortitudeInvested);

    // E2j7a - melee_power/spell_power: multiplies the already Mastery+Talent-scaled weaponDps/
    // intellect bonuses above, same post-step ordering as Fortitude immediately above.
    EchoesMeleeSpellPowerInvested meleeSpellInvested = EchoesQueryMeleeSpellPowerInvested(accountId);
    newBonus = EchoesApplyMeleeSpellPowerMultipliers(newBonus, meleeSpellInvested.melee, meleeSpellInvested.spell);

    auto it = EchoesStatsState::appliedByGuid.find(guidLow);
    EchoesStatsState::AppliedBonus oldBonus = (it != EchoesStatsState::appliedByGuid.end()) ? it->second : EchoesStatsState::AppliedBonus{};

    EchoesApplyDelta(player, oldBonus, newBonus);

    // E2j6 - Combat-rating restoration. Computed and applied separately from EchoesApplyDelta
    // (rating-space, not stat/armor/attack-power-space) but using the same old/new-recorded-vs-
    // freshly-calculated pattern as every other bonus this function tracks.
    EchoesRatingSinksInvested ratingInvested = EchoesQueryRatingSinksInvested(accountId);
    double critPct  = EchoesRatingSinkFraction(ratingInvested.crit,  kCritRatingCeiling)  * 100.0;
    double hastePct = EchoesRatingSinkFraction(ratingInvested.haste, kHasteRatingCeiling) * 100.0;
    double dodgePct = EchoesRatingSinkFraction(ratingInvested.dodge, kDodgeRatingCeiling) * 100.0;
    double parryPct = EchoesRatingSinkFraction(ratingInvested.parry, kParryRatingCeiling) * 100.0;

    int32_t newCritPoints[3] = {
        EchoesRatingPointsForPercent(critPct, player->GetRatingMultiplier(CR_CRIT_MELEE)),
        EchoesRatingPointsForPercent(critPct, player->GetRatingMultiplier(CR_CRIT_RANGED)),
        EchoesRatingPointsForPercent(critPct, player->GetRatingMultiplier(CR_CRIT_SPELL)),
    };
    int32_t newHastePoints[3] = {
        EchoesRatingPointsForPercent(hastePct, player->GetRatingMultiplier(CR_HASTE_MELEE)),
        EchoesRatingPointsForPercent(hastePct, player->GetRatingMultiplier(CR_HASTE_RANGED)),
        EchoesRatingPointsForPercent(hastePct, player->GetRatingMultiplier(CR_HASTE_SPELL)),
    };
    int32_t newDodgePoints = EchoesRatingPointsForPercent(dodgePct, player->GetRatingMultiplier(CR_DODGE));
    int32_t newParryPoints = EchoesRatingPointsForPercent(parryPct, player->GetRatingMultiplier(CR_PARRY));

    int32_t oldCritPoints[3] = { oldBonus.critMeleePoints, oldBonus.critRangedPoints, oldBonus.critSpellPoints };
    int32_t oldHastePoints[3] = { oldBonus.hasteMeleePoints, oldBonus.hasteRangedPoints, oldBonus.hasteSpellPoints };

    EchoesApplyRatingGroupDelta(player, { CR_CRIT_MELEE, CR_CRIT_RANGED, CR_CRIT_SPELL }, oldCritPoints, newCritPoints);
    EchoesApplyRatingGroupDelta(player, { CR_HASTE_MELEE, CR_HASTE_RANGED, CR_HASTE_SPELL }, oldHastePoints, newHastePoints);
    EchoesApplyRatingGroupDelta(player, { CR_DODGE }, &oldBonus.dodgePoints, &newDodgePoints);
    EchoesApplyRatingGroupDelta(player, { CR_PARRY }, &oldBonus.parryPoints, &newParryPoints);

    EchoesStatsState::AppliedBonus recorded;
    recorded.str = newBonus.str;
    recorded.agi = newBonus.agi;
    recorded.sta = newBonus.sta;
    recorded.intellect = newBonus.intellect;
    recorded.spirit = newBonus.spirit;
    recorded.armor = newBonus.armor; // E2j5a
    recorded.attackPower = EchoesWeaponDpsToAttackPower(newBonus.weaponDps); // E2j5a - store the
    // already-converted value, matching exactly what EchoesApplyDelta compares against next time.
    recorded.critMeleePoints = newCritPoints[0];
    recorded.critRangedPoints = newCritPoints[1];
    recorded.critSpellPoints = newCritPoints[2];
    recorded.hasteMeleePoints = newHastePoints[0];
    recorded.hasteRangedPoints = newHastePoints[1];
    recorded.hasteSpellPoints = newHastePoints[2];
    recorded.dodgePoints = newDodgePoints;
    recorded.parryPoints = newParryPoints;
    EchoesStatsState::appliedByGuid[guidLow] = recorded;

    // E2j3 isolated-validation observability only (Stage 12/13 gates read this): one line per
    // recalculation, never per-frame, never containing credentials or player-identifying info
    // beyond the character guid already visible in every other AC log line.
    // E2j5e: talentPrimary/distinctPenalty appended for Talent-restoration observability - same
    // convention as E2j5a's armor/weaponDps/attackPower fields above.
    EchoesTalentMultipliers talentMultsForLog = EchoesComputeTalentMultipliers(talents);
    LOG_INFO("module", "[mod-echoes-stats] applied guid={} masteryRank={} level={} snapshots={} "
        "bonus(str={:.2f} agi={:.2f} sta={:.2f} int={:.2f} spi={:.2f} armor={:.2f} weaponDps={:.2f} attackPower={:.2f}) "
        "talentPrimary={} talentDistinctPenalty={:.3f} fortitudeInvested={:.0f} fortitudeBonus={:.4f} "
        "meleePowerInvested={:.0f} meleePowerBonus={:.4f} spellPowerInvested={:.0f} spellPowerBonus={:.4f} "
        "ratingPct(crit={:.4f} haste={:.4f} dodge={:.4f} parry={:.4f}) "
        "ratingPoints(critM={} critR={} critS={} hasteM={} hasteR={} hasteS={} dodge={} parry={})",
        guidLow, masteryRank, level, snapshots.size(),
        newBonus.str, newBonus.agi, newBonus.sta, newBonus.intellect, newBonus.spirit,
        newBonus.armor, newBonus.weaponDps, recorded.attackPower,
        talentMultsForLog.primaryStat, talentMultsForLog.distinctPenalty,
        fortitudeInvested, EchoesFortitudeBonus(fortitudeInvested),
        meleeSpellInvested.melee, EchoesMeleeSpellPowerBonus(meleeSpellInvested.melee),
        meleeSpellInvested.spell, EchoesMeleeSpellPowerBonus(meleeSpellInvested.spell),
        critPct, hastePct, dodgePct, parryPct,
        newCritPoints[0], newCritPoints[1], newCritPoints[2],
        newHastePoints[0], newHastePoints[1], newHastePoints[2],
        newDodgePoints, newParryPoints);
}

static void EchoesRemoveAll(Player* player)
{
    if (!player)
        return;
    uint32_t guidLow = player->GetGUID().GetCounter();
    auto it = EchoesStatsState::appliedByGuid.find(guidLow);
    if (it == EchoesStatsState::appliedByGuid.end())
        return; // nothing applied - nothing to remove

    EchoesStatBonus zero;
    EchoesApplyDelta(player, it->second, zero);

    // E2j6 - rating removal: EchoesApplyDelta only covers stat/armor/attack-power space, so the
    // rating-point contributions recorded in `it->second` need their own explicit old->zero pass.
    EchoesStatsState::AppliedBonus const& old = it->second;
    int32_t oldCritPoints[3] = { old.critMeleePoints, old.critRangedPoints, old.critSpellPoints };
    int32_t oldHastePoints[3] = { old.hasteMeleePoints, old.hasteRangedPoints, old.hasteSpellPoints };
    int32_t zeroCritPoints[3] = { 0, 0, 0 };
    int32_t zeroHastePoints[3] = { 0, 0, 0 };
    int32_t zeroPoint = 0;
    EchoesApplyRatingGroupDelta(player, { CR_CRIT_MELEE, CR_CRIT_RANGED, CR_CRIT_SPELL }, oldCritPoints, zeroCritPoints);
    EchoesApplyRatingGroupDelta(player, { CR_HASTE_MELEE, CR_HASTE_RANGED, CR_HASTE_SPELL }, oldHastePoints, zeroHastePoints);
    EchoesApplyRatingGroupDelta(player, { CR_DODGE }, &old.dodgePoints, &zeroPoint);
    EchoesApplyRatingGroupDelta(player, { CR_PARRY }, &old.parryPoints, &zeroPoint);

    EchoesStatsState::appliedByGuid.erase(it);
    EchoesStatsState::lastRecalcSecsByGuid.erase(guidLow);
    EchoesStatsState::lastWarnedRawMasteryRankByGuid.erase(guidLow);
}

class EchoesStatsPlayerScript : public PlayerScript
{
public:
    EchoesStatsPlayerScript() : PlayerScript("EchoesStatsPlayerScript",
        { PLAYERHOOK_ON_LOGIN, PLAYERHOOK_ON_LOGOUT, PLAYERHOOK_ON_LEVEL_CHANGED })
    {
    }

    void OnPlayerLogin(Player* player) override
    {
        if (!player || !EchoesStatsConfig::instance()->enabled)
            return;
        EchoesRecalculateAndApply(player);
        EchoesStatsState::lastRecalcSecsByGuid[player->GetGUID().GetCounter()] =
            static_cast<uint32_t>(GameTime::GetGameTime().count());
    }

    void OnPlayerLogout(Player* player) override
    {
        EchoesRemoveAll(player);
    }

    void OnPlayerLevelChanged(Player* player, uint8 /*oldLevel*/) override
    {
        if (!player || !EchoesStatsConfig::instance()->enabled)
            return;
        EchoesRecalculateAndApply(player);
    }
};

class EchoesStatsWorldScript : public WorldScript
{
public:
    EchoesStatsWorldScript() : WorldScript("EchoesStatsWorldScript",
        { WORLDHOOK_ON_AFTER_CONFIG_LOAD, WORLDHOOK_ON_STARTUP, WORLDHOOK_ON_UPDATE, WORLDHOOK_ON_SHUTDOWN })
    {
    }

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        EchoesStatsConfig::instance()->Load();
    }

    void OnStartup() override
    {
        LOG_INFO("module", "[mod-echoes-stats] E2j3 engine-level stat module loaded, enabled={}",
            EchoesStatsConfig::instance()->enabled);
    }

    void OnUpdate(uint32 /*diff*/) override
    {
        // Bounded, rate-limited periodic safety-net recheck - see this file's header comment
        // for why this exists (catches Mastery/snapshot changes without a new Lua signal).
        // Never iterates every account - only currently in-world players, at most once every
        // 60 seconds globally, with a further per-player 60s floor.
        if (!EchoesStatsConfig::instance()->enabled)
            return;

        uint32_t nowSecs = static_cast<uint32_t>(GameTime::GetGameTime().count());
        if (nowSecs - EchoesStatsState::lastPeriodicPassSecs < 60)
            return;
        EchoesStatsState::lastPeriodicPassSecs = nowSecs;

        for (auto const& [guid, player] : ObjectAccessor::GetPlayers())
        {
            if (!player || !player->IsInWorld())
                continue;
            uint32_t guidLow = player->GetGUID().GetCounter();
            auto it = EchoesStatsState::lastRecalcSecsByGuid.find(guidLow);
            if (it != EchoesStatsState::lastRecalcSecsByGuid.end() && nowSecs - it->second < 60)
                continue;
            EchoesRecalculateAndApply(player);
            EchoesStatsState::lastRecalcSecsByGuid[guidLow] = nowSecs;
        }
    }

    void OnShutdown() override
    {
        // In-memory bookkeeping only - never persisted, nothing to unwind against the DB.
        // Stat modifiers themselves are owned by the (now-destructing) Player objects, not by
        // this module.
        EchoesStatsState::appliedByGuid.clear();
        EchoesStatsState::lastRecalcSecsByGuid.clear();
        EchoesStatsState::lastWarnedRawMasteryRankByGuid.clear();
        // E2j5g Stage 7 - Spell Mitigation: no persisted state (per the recovered contract's
        // "Persistence Requirements: none" finding) - only these two in-memory caches to clear.
        EchoesStatsState::mitigCacheByAccountId.clear();
        EchoesStatsState::mitigNotifyTimeByGuid.clear();
        // E2j7b - execute_power/armor_pen: same "no persisted state" reasoning - only the
        // in-memory cache needs clearing.
        EchoesStatsState::armorPenExecutePowerCacheByAccountId.clear();
        // E2j7c - reflect_chance: same "no persisted state" reasoning - only the in-memory cache
        // and notification throttle need clearing.
        EchoesStatsState::reflectCacheByAccountId.clear();
        EchoesStatsState::reflectNotifyTimeByGuid.clear();
    }
};

void AddSC_EchoesStats()
{
    new EchoesStatsPlayerScript();
    new EchoesStatsWorldScript();
    new EchoesStatsUnitScript(); // E2j5g Stage 7 - Spell Mitigation
}
