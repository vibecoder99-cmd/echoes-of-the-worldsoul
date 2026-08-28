#include "EchoesPlayerbotsCommon.h"
#include "EchoesConfig.h"
#include "EchoesPresence.h"
#include "EchoesBotCache.h"
#include "EchoesAwareness.h"
#include "EchoesDisposition.h"
#include "EchoesProtection.h"
#include "EchoesAdapterFactory.h"
#include "EchoesRackAdapter.h"
#include "EchoesDissolutionAdapter.h"
#include "EchoesForgeAdapter.h"
#include "EchoesActionBridge.h"
#include "EchoesProgressionBudgetPolicy.h"
#include "EchoesProgressionSchedulerPolicy.h"
#include "EchoesResidueSpendingPolicy.h"

#include "ScriptMgr.h"
#include "Player.h"
#include "Item.h"
#include "Bag.h"
#include "ItemTemplate.h"
#include "GameTime.h"
#include "Log.h"
#include "DatabaseEnv.h"
#include "QueryResult.h"
#include "ObjectAccessor.h"
#ifdef MOD_PLAYERBOTS
#include "RandomPlayerbotMgr.h"
#endif
#include <deque>
#include <unordered_set>
#include <unordered_map>
#include <sstream>
#include <fstream>
#include <cstdio>

// Playerbots' own public interface - GET_PLAYERBOT_AI is the source-proven,
// non-invasive way to distinguish a bot Player* from a human one (E2i1
// Stage 3). This module never modifies mod-playerbots; it only consumes
// its public headers/macros, exactly as any other AzerothCore module
// consumes core's public interface.
//
// StatsWeightCalculator is likewise part of Playerbots' own public,
// includable interface (used the same way by EquipAction.cpp) - reusing
// it here means this module scores items with Playerbots' *own* logic
// rather than inventing a new scoring system, per the explicit E2i1/E2i2
// instruction.
//
// E2j14 Workstream B: both headers (and every symbol they declare -
// GET_PLAYERBOT_AI, StatsWeightCalculator, sRandomPlayerbotMgr, PlayerbotAI)
// are only ever available when mod-playerbots is present in modules/. Guarded
// so this module remains buildable in a Playerbots-absent, human-only
// configuration - see the -DMOD_PLAYERBOTS mechanism in modules/CMakeLists.txt.
#ifdef MOD_PLAYERBOTS
#include "Playerbots.h"
#include "StatsWeightCalculator.h"
#endif

// ── Aggregate instrumentation (no player data, no inventory contents) ──
namespace EchoesStats
{
    static uint32 decisionsEvaluated = 0;
    static uint32 decisionsModified = 0;
    static uint32 defaultFallbacks = 0;
    static uint32 humanBypasses = 0;
    static uint32 disabledBypasses = 0;
    static uint32 errors = 0;

    // Layer 2 (E2i4 prototype) - separate counters, never mixed with Layer 1's.
    namespace L2
    {
        static uint32 dispositionEvaluations = 0;
        static uint32 protectedItems = 0;
        static uint32 releasedProtections = 0;
        static uint32 bagPressureReleases = 0;
        static uint32 defaultDispositions = 0;
        static uint32 cacheUnavailableFallbacks = 0;
        static uint32 humanBypasses = 0;
        static uint32 disabledBypasses = 0;
        static uint32 staleOrMissingReleases = 0;
        static uint32 errors = 0;
    }

    // E2i6 prototype - bridge/adapter counters, separate namespace again.
    namespace Bridge
    {
        static uint32 rackEvaluations = 0;
        static uint32 rackStoresSucceeded = 0;
        static uint32 rackRejections = 0;
        static uint32 leaseConflicts = 0;
        static uint32 bridgeUnavailable = 0;
    }

    // E2i8: Dissolution ("Legacy Forge") auto-trigger counters. The automatic
    // equip-decision path only ever previews (dry-run) - see
    // MaybeOfferToDissolution's own comment for why it never calls Execute().
    namespace Dissolution
    {
        static uint32 leaseConflicts = 0;

        // E2i9: bounded production decision-observability (Stage 8/9 of the
        // E2i9 phase). Every counter below is incremented only from the one
        // real automatic-consideration call site (MaybeOfferToDissolution) -
        // never per-tick, never proportional to anything but genuine
        // equip-replacement events. botsSeen is a set of bot GUIDs, which is
        // inherently bounded by the server's own hard bot-population cap
        // (AC_AI_PLAYERBOT_MAX_RANDOM_BOTS), never unbounded in practice.
        static uint32 itemsConsidered = 0;
        static std::unordered_set<uint32> botsSeen;
        static constexpr size_t kDecisionSlots = 32; // > highest DissolutionPolicyDecision enum value
        static uint32 decisionCounts[kDecisionSlots] = {0};
        static uint32 previewSuccesses = 0;
        static uint32 previewFailures = 0;

        // E2j11: live execution observability, incremented only from the same
        // MaybeOfferToDissolution call site as the dry-run counters above, only ever reached
        // after a SUCCESS dry-run AND EchoesConfig::dissolutionExecuteEnabled is true. Distinct
        // from EchoesDissolutionAdapter's own internal executionsSucceeded/executionsRejected/
        // executionsBlockedByGate counters (those live per-adapter-instance; these are the
        // module-wide, report-visible equivalents, matching every other Dissolution counter's
        // existing convention).
        static uint32 executionsAttempted = 0;
        static uint32 executionsSucceeded = 0;
        static uint32 executionsFailed = 0;

        // Bounded ring of the most recent conclusively-obsolete, dry-run-
        // eligible candidates - exactly the set Stage 9's candidate audit
        // needs. Capped at kMaxSamples; oldest entry evicted first. Never
        // logs full inventory or player-identifying data beyond a bot GUID.
        struct EligibleSample { uint32 botGuidLow; uint32 itemEntry; uint32 previewReward; uint32 ts; };
        static constexpr size_t kMaxSamples = 50;
        static std::deque<EligibleSample> eligibleSamples;

        static uint32 lastReportLogSecs = 0; // rate-limits the periodic bounded log line
    }

    // E2j1: bounded bot progression-economy spending counters. Every counter increments only
    // from MaybeReconcileProgressionSpending, itself only reachable from OnPlayerLogin - never
    // per-tick, never proportional to bot count beyond one bounded pass per login.
    //
    // E2j14 Workstream B: this entire namespace's counters are only ever written by the
    // Playerbots-only functions guarded below (TryOneProgressionSpendForBot,
    // RunProgressionSchedulerPass) and have no accessor functions exposing them outside this
    // TU (unlike L2/Bridge/Dissolution, which are still read by EchoesPB_*_Get* accessors
    // further down and so stay declared unconditionally) - guarding the whole namespace avoids
    // leaving genuinely-unused static counters in a Playerbots-absent build.
#ifdef MOD_PLAYERBOTS
    namespace Progression
    {
        static uint32 loginPassesRun = 0;
        static uint32 candidatesEvaluated = 0;
        static constexpr size_t kDecisionSlots = 16; // > highest ProgressionSpendDecision enum value
        static uint32 decisionCounts[kDecisionSlots] = {0};
        static uint32 spendsSucceeded = 0;
        static uint32 spendsFailedPostVerify = 0; // bridge reported ok=true but balance didn't move
        static uint32 sinkInvestSucceeded = 0;
        static uint32 rackExpandSucceeded = 0;
        // E2j5: Mastery as a bounded bot spending target.
        static uint32 masteryPurchaseSucceeded = 0;
        static uint32 masteryInsufficientEssence = 0;
        static uint32 masteryServiceUnavailable = 0;
        static uint32 masteryDatabaseFailure = 0;
        static uint32 masteryRefreshRequested = 0;
        static uint32 residueRackSucceeded = 0;
        static uint32 catalystSucceeded = 0;
        static uint32 residueAttemptsFailed = 0;
        static uint32 residuePhysicalSyncDeferred = 0;

        // Resource-level lease, keyed on (botGuidLow, resourceTypeId) - separate from
        // EchoesAdapterFactory's item-instance ObjectGuid lease (a spend has no Item* to key
        // on), per the Stage 2 integration-coherence audit's explicit recommendation. Same
        // expiry-map shape, kept file-local since this is the only call site.
        // E2j2: SinkAttunementEcho renamed conceptually to SinkInvestment now that the sink
        // category is chosen per-bot (see SelectSinkCategoryForBot) rather than hardcoded -
        // the cooldown lease is still keyed on "any sink spend for this bot", not per-category,
        // since a bot commits to one deterministic category for its whole lifetime.
        enum class ResourceType : uint32
        {
            SinkInvestment = 1,
            RackExpansion = 2,
            MasteryPurchase = 3,
            ResidueSpending = 4
        };
        static std::unordered_map<uint64, uint32> lastSpendSecondsByKey; // key -> last spend timestamp

        // E2j2: recurring scheduler counters, incremented only from the bounded, rate-limited
        // scheduler pass (never per-tick, never proportional to total bot count beyond
        // progressionSchedulerMaxBotsPerPass per pass).
        static uint32 schedulerPassesRun = 0;
        static uint32 schedulerBotsConsidered = 0;
        static uint32 schedulerBotsSkippedRecheckCooldown = 0;
        static uint32 schedulerBotsSkippedControlled = 0; // master-controlled (party) bot, not autonomous
        static std::unordered_map<uint32, uint32> lastSchedulerCheckSecsByGuid; // botGuidLow -> last pass timestamp
        static uint32 schedulerCursorGuid = 0; // rotating cursor for bounded per-pass bot selection
        static uint32 schedulerLastPassSecs = 0; // rate-limits OnUpdate's scheduler gate, same pattern as Dissolution's lastReportLogSecs
    }
#endif // MOD_PLAYERBOTS
}

// Forward declaration - defined at the bottom of this file alongside the
// other instrumentation accessors; needed here because OnUpdate() (below)
// calls it before that point in translation order.
std::string EchoesPB_Dissolution_BuildDecisionReport();

// ── E2j2/E2j9: functional-only Crucible category selection and shared spend logic ──
//
// The category allowlist and the deterministic guid(+class)->category assignment both live in
// EchoesProgressionSchedulerPolicy.h (pure, dependency-free, independently unit-tested) - see
// EchoesExpandedFunctionalCrucibleCategories/EchoesSelectSinkCategoryForGuidClassAware there for
// the full citation of which of the 18 AP.SinkDefs categories are genuinely functional (17 of 18
// as of E2j9 - only `threat_reduction` excluded, see THREAT-REDUCTION-CONTRACT-AND-DESIGN.md) and
// the class-aware weighted-pool policy. E2j9 expanded this from the original E2j2 6-category
// flat pool to a 17-category, class-filtered, weighted pool - `player->getClass()` is passed
// through so `melee_power`/`spell_power` resolve only for classes that can plausibly benefit.
//
// E2j14 Workstream B: this helper and everything through RunProgressionSchedulerPass below is
// bot progression-economy spending logic, reachable only via TryOneProgressionSpendForBot,
// which itself gates on GET_PLAYERBOT_AI as its very first check - i.e. it is Playerbots-only
// functionality end to end. Guarded (rather than left with a fallback body) because Playerbots'
// own GET_PLAYERBOT_AI macro/type is not declared at all when MOD_PLAYERBOTS is undefined.
#ifdef MOD_PLAYERBOTS
static char const* SelectSinkCategoryForBot(Player* player)
{
    return EchoesSelectSinkCategoryForGuidClassAware(
        player->GetGUID().GetCounter(), player->getClass());
}

// Shared core: attempt at most one progression spend for one bot, trying the bot's assigned
// functional Crucible category first, falling back to Essence-funded Rack expansion. This is
// the exact E2j1 Stage 10-proven one-action-per-pass, fail-closed logic - unchanged in shape,
// only parameterized by category so both the login-triggered path (EchoesPlayerScript) and the
// E2j2 recurring scheduler (EchoesWorldScript) share one implementation rather than two
// divergent copies.
static void TryOneProgressionSpendForBot(Player* player, char const* sinkCategory)
{
    if (!player || !GET_PLAYERBOT_AI(player))
        return; // human isolation - identical invariant to every other hook in this module

    if (!EchoesConfig::instance()->progressionSpendingEnabled)
        return;

    if (!EchoesPresence::instance()->IsActiveOrDegraded())
        return;

    auto* bridge = EchoesActionBridge::instance();
    EchoesActionBridge::ProgressionSnapshot snap = bridge->GetProgressionSnapshot(player);
    if (!snap.ok)
        return; // fails closed - never guess a balance

    ++EchoesStats::Progression::loginPassesRun;

    uint32 guidLow = player->GetGUID().GetCounter();
    uint32 now = static_cast<uint32>(GameTime::GetGameTime().count());
    uint32 actionsThisLogin = 0;
    uint32 maxActions = EchoesConfig::instance()->progressionMaxSpendActionsPerLogin;
    int64_t balance = snap.essence;

    // E2j1 Stage 10 finding: both AP.Sinks.Invest and AP.Rack.Expand use fire-and-forget
    // async DB writes (documented, pre-existing non-atomicity in ap_sinks.lua - "a crash
    // between these two commits can deduct Aether without the corresponding investment
    // being recorded... Non-exploitable"). That gap was accepted for a single human-paced
    // spend; chaining a second bot-driven spend immediately afterward in the same pass
    // exposed it as a real race - a synchronous post-verify read can run ahead of the
    // first spend's async write, leaving the second candidate's eligibility check using a
    // stale balance. Fix: attempt at most one spend action per pass, never two back-to-back,
    // removing the race window entirely. This invariant holds for the scheduler path too -
    // never chain two async Essence deductions regardless of trigger source.
    bool spendAttemptedThisPass = false;

    // --- Candidate 1: this bot's assigned functional Crucible category ---
    if (actionsThisLogin < maxActions && !spendAttemptedThisPass)
    {
        ++EchoesStats::Progression::candidatesEvaluated;
        EchoesActionBridge::SinkInvestPreview sinkPreview = bridge->PreviewSinkInvest(sinkCategory,
            EchoesConfig::instance()->progressionMaxSpendPerDecision);
        if (sinkPreview.ok)
        {
            uint32 resourceKey = static_cast<uint32>(EchoesStats::Progression::ResourceType::SinkInvestment);
            uint64 leaseKey = (static_cast<uint64>(guidLow) << 32) | resourceKey;
            auto it = EchoesStats::Progression::lastSpendSecondsByKey.find(leaseKey);
            uint32 secondsSince = (it == EchoesStats::Progression::lastSpendSecondsByKey.end())
                ? EchoesConfig::instance()->progressionSpendCooldownSeconds
                : (now > it->second ? now - it->second : 0);

            ProgressionBudgetContext ctx;
            ctx.adapterEnabled = true;
            ctx.currentBalance = balance;
            ctx.reserveEssence = EchoesConfig::instance()->progressionReserveEssence;
            ctx.maxSpendPerDecision = EchoesConfig::instance()->progressionMaxSpendPerDecision;
            ctx.proposedCost = sinkPreview.cost;
            ctx.actionsAlreadyThisLogin = actionsThisLogin;
            ctx.maxActionsPerLogin = maxActions;
            ctx.secondsSinceLastSpend = secondsSince;
            ctx.cooldownSeconds = EchoesConfig::instance()->progressionSpendCooldownSeconds;
            ctx.balanceIsFresh = true;

            ProgressionSpendDecision decision = EvaluateProgressionSpend(ctx);
            uint32 decisionIdx = static_cast<uint32>(decision);
            if (decisionIdx < EchoesStats::Progression::kDecisionSlots)
                ++EchoesStats::Progression::decisionCounts[decisionIdx];

            if (decision == ProgressionSpendDecision::ELIGIBLE_TO_SPEND)
            {
                spendAttemptedThisPass = true;
                bool ok = bridge->ExecuteSinkInvest(player, sinkCategory, sinkPreview.cost);
                if (ok)
                {
                    // E2j2 Stage 9 finding: the post-spend verification read below can (and in
                    // this environment, does, consistently) race ahead of AP.Sinks.Invest's own
                    // async DB write (the same documented, pre-existing non-atomicity gap cited
                    // in ap_sinks.lua), reading the OLD balance before the deduction has landed.
                    // The cooldown lease MUST be recorded as soon as the bridge accepted the
                    // spend attempt (ok=true), independent of whether this immediate re-read
                    // happens to observe it in time - otherwise a raced verify silently disables
                    // the cooldown entirely, letting the same bot spend again on literally the
                    // very next opportunity with no enforcement at all (observed directly: a
                    // bot spent 4 times in ~7 minutes against a configured 3600s cooldown before
                    // this fix, confirmed via leaseFound=false on every one of its repeat
                    // attempts). spendsSucceeded/spendsFailedPostVerify remain pure observability
                    // counters below and no longer gate the lease write.
                    EchoesStats::Progression::lastSpendSecondsByKey[leaseKey] = now;

                    // Post-spend verification: re-read the balance rather than trusting the
                    // bridge's own ok=true, per the E2j1 Stage 2 currency-economy research's
                    // explicit finding that spend paths can report success without the
                    // corresponding state actually landing. A failed post-verify here also
                    // correctly invalidates the stale in-memory `balance` local - candidate 2
                    // below is gated off entirely by spendAttemptedThisPass regardless of
                    // whether this branch's mutation ultimately lands, so no cache/state is
                    // ever read again this pass using a value that might already be stale.
                    EchoesActionBridge::ProgressionSnapshot after = bridge->GetProgressionSnapshot(player);
                    if (after.ok && after.essence <= static_cast<uint32>(balance) - 1)
                    {
                        ++EchoesStats::Progression::spendsSucceeded;
                        ++EchoesStats::Progression::sinkInvestSucceeded;
                        balance = after.essence;
                        ++actionsThisLogin;
                    }
                    else
                    {
                        ++EchoesStats::Progression::spendsFailedPostVerify;
                    }
                }
            }
        }
    }

    // --- Candidate 2: Mastery purchase (E2j5) ---
    //
    // Placed between the functional-Crucible candidate and the Rack-expansion fallback, per
    // this phase's default conservative policy order: 1) preserve reserve, 2) one functional
    // Crucible investment, 3) otherwise one Mastery purchase, 4) otherwise one Rack expansion.
    // Uses the exact same EvaluateProgressionSpend budget/reserve/cooldown gate as Candidates 1
    // and 3 - no separate Mastery-only affordability logic. Unlike the Sink/Rack paths,
    // AP.Mastery.Purchase performs a SYNCHRONOUS (ExecuteCritical) write, so its returned
    // old/new rank and balance are already authoritative - no separate post-verify re-read is
    // needed or performed here (there is no async-write race window to guard against for this
    // specific call, unlike Sinks/Rack).
    if (EchoesConfig::instance()->progressionMasteryPurchaseEnabled &&
        actionsThisLogin < maxActions && !spendAttemptedThisPass)
    {
        ++EchoesStats::Progression::candidatesEvaluated;
        EchoesActionBridge::MasteryPurchasePreview masteryPreview = bridge->PreviewMasteryPurchase(player);
        if (masteryPreview.ok)
        {
            uint32 resourceKey = static_cast<uint32>(EchoesStats::Progression::ResourceType::MasteryPurchase);
            uint64 leaseKey = (static_cast<uint64>(guidLow) << 32) | resourceKey;
            auto it = EchoesStats::Progression::lastSpendSecondsByKey.find(leaseKey);
            uint32 secondsSince = (it == EchoesStats::Progression::lastSpendSecondsByKey.end())
                ? EchoesConfig::instance()->progressionSpendCooldownSeconds
                : (now > it->second ? now - it->second : 0);

            ProgressionBudgetContext ctx;
            ctx.adapterEnabled = true;
            ctx.currentBalance = balance;
            ctx.reserveEssence = EchoesConfig::instance()->progressionReserveEssence;
            ctx.maxSpendPerDecision = EchoesConfig::instance()->progressionMaxSpendPerDecision;
            ctx.proposedCost = masteryPreview.cost;
            ctx.actionsAlreadyThisLogin = actionsThisLogin;
            ctx.maxActionsPerLogin = maxActions;
            ctx.secondsSinceLastSpend = secondsSince;
            ctx.cooldownSeconds = EchoesConfig::instance()->progressionSpendCooldownSeconds;
            ctx.balanceIsFresh = true;

            // Never a rank ceiling here - masteryPreview.cost/currentRank come straight from
            // AP.MasteryCost/AP.LoadMastery via the bridge, uncapped, exactly as the human path
            // computes them. This budget check is purely an Essence-affordability/reserve/
            // cooldown gate, identical in shape to Candidates 1 and 3 - it never rejects based
            // on rank magnitude alone (e.g. Rank 8000 or above is never treated as a cap here).
            ProgressionSpendDecision decision = EvaluateProgressionSpend(ctx);
            uint32 decisionIdx = static_cast<uint32>(decision);
            if (decisionIdx < EchoesStats::Progression::kDecisionSlots)
                ++EchoesStats::Progression::decisionCounts[decisionIdx];

            if (decision == ProgressionSpendDecision::ELIGIBLE_TO_SPEND)
            {
                spendAttemptedThisPass = true;
                EchoesActionBridge::MasteryPurchaseResult result = bridge->ExecuteMasteryPurchase(player);
                if (result.status == "SUCCESS")
                {
                    // Synchronous write already confirmed by the Lua service itself - record the
                    // lease and advance local counters directly from the authoritative result,
                    // no post-verify re-read race exists to guard against here.
                    EchoesStats::Progression::lastSpendSecondsByKey[leaseKey] = now;
                    ++EchoesStats::Progression::spendsSucceeded;
                    ++EchoesStats::Progression::masteryPurchaseSucceeded;
                    balance = result.newBalance;
                    ++actionsThisLogin;

                    // Bounded, narrow refresh signal: mod-echoes-stats' own periodic safety-net
                    // recheck (EchoesStatsHooks.cpp, E2j3/E2j4) will pick up the new persisted
                    // ap_mastery.mastery row within its own bounded interval regardless of this
                    // call - this counter is purely observability (E2j5 Stage 5/7 requirement to
                    // record refresh success separately from purchase success), not a second
                    // stat-application path. No stat is ever applied from this module.
                    ++EchoesStats::Progression::masteryRefreshRequested;
                }
                else if (result.status == "INSUFFICIENT_ESSENCE")
                {
                    ++EchoesStats::Progression::masteryInsufficientEssence;
                }
                else if (result.status == "DATABASE_FAILURE")
                {
                    ++EchoesStats::Progression::masteryDatabaseFailure;
                }
                else
                {
                    ++EchoesStats::Progression::masteryServiceUnavailable;
                }
            }
        }
    }

    // --- Candidate 3: Essence-funded Rack expansion fallback (never Residue-funded here) ---
    if (actionsThisLogin < maxActions && !spendAttemptedThisPass)
    {
        ++EchoesStats::Progression::candidatesEvaluated;
        EchoesActionBridge::RackExpandPreview rackPreview = bridge->PreviewRackExpand(player);
        // E2j2: explicitly Essence-only. A Residue-funded tier (rackPreview.residueCost > 0)
        // is never attempted here - Residue-funded Rack expansion requires a separately proven
        // adapter per the phase's explicit instruction, not attempted in E2j2.
        if (rackPreview.ok && !rackPreview.atMaxCapacity && rackPreview.essenceCost > 0 && rackPreview.residueCost == 0)
        {
            uint32 resourceKey = static_cast<uint32>(EchoesStats::Progression::ResourceType::RackExpansion);
            uint64 leaseKey = (static_cast<uint64>(guidLow) << 32) | resourceKey;
            auto it = EchoesStats::Progression::lastSpendSecondsByKey.find(leaseKey);
            uint32 secondsSince = (it == EchoesStats::Progression::lastSpendSecondsByKey.end())
                ? EchoesConfig::instance()->progressionSpendCooldownSeconds
                : (now > it->second ? now - it->second : 0);

            ProgressionBudgetContext ctx;
            ctx.adapterEnabled = true;
            ctx.currentBalance = balance;
            ctx.reserveEssence = EchoesConfig::instance()->progressionReserveEssence;
            ctx.maxSpendPerDecision = EchoesConfig::instance()->progressionMaxSpendPerDecision;
            ctx.proposedCost = rackPreview.essenceCost;
            ctx.actionsAlreadyThisLogin = actionsThisLogin;
            ctx.maxActionsPerLogin = maxActions;
            ctx.secondsSinceLastSpend = secondsSince;
            ctx.cooldownSeconds = EchoesConfig::instance()->progressionSpendCooldownSeconds;
            ctx.balanceIsFresh = true;

            ProgressionSpendDecision decision = EvaluateProgressionSpend(ctx);
            uint32 decisionIdx = static_cast<uint32>(decision);
            if (decisionIdx < EchoesStats::Progression::kDecisionSlots)
                ++EchoesStats::Progression::decisionCounts[decisionIdx];

            if (decision == ProgressionSpendDecision::ELIGIBLE_TO_SPEND)
            {
                spendAttemptedThisPass = true;
                bool ok = bridge->ExecuteRackExpand(player);
                if (ok)
                {
                    // Same E2j2 Stage 9 fix as Candidate 1 above: record the cooldown lease as
                    // soon as the bridge accepts the mutation, not gated on the immediate
                    // post-verify race.
                    EchoesStats::Progression::lastSpendSecondsByKey[leaseKey] = now;

                    EchoesActionBridge::ProgressionSnapshot after = bridge->GetProgressionSnapshot(player);
                    if (after.ok && after.rackSlots > snap.rackSlots)
                    {
                        ++EchoesStats::Progression::spendsSucceeded;
                        ++EchoesStats::Progression::rackExpandSucceeded;
                        ++actionsThisLogin;
                    }
                    else
                    {
                        ++EchoesStats::Progression::spendsFailedPostVerify;
                    }
                }
            }
        }
    }

    // --- E2j10 Candidate 4: account-level Worldsoul Residue spending ---
    // Runs inside the same one-action pipeline and only after every established
    // Essence candidate declined. Rack is the permanent foundational choice;
    // Catalyst is considered only when no Residue-funded Rack tier is pending.
    if (EchoesConfig::instance()->progressionResidueSpendingEnabled &&
        actionsThisLogin < maxActions && !spendAttemptedThisPass)
    {
        ++EchoesStats::Progression::candidatesEvaluated;
        EchoesActionBridge::RackExpandPreview rackPreview = bridge->PreviewRackExpand(player);
        EchoesActionBridge::CatalystPreview catalystPreview = bridge->PreviewCatalyst(player);

        bool residueRackPending = rackPreview.ok && !rackPreview.atMaxCapacity &&
            rackPreview.essenceCost == 0 && rackPreview.residueCost > 0;

        EchoesResidueSpendingContext ctx;
        ctx.adapterEnabled = true;
        ctx.rackPreviewOk = rackPreview.ok;
        ctx.rackAtMaxCapacity = rackPreview.atMaxCapacity;
        ctx.rackEssenceCost = rackPreview.essenceCost;
        ctx.rackResidueCost = rackPreview.residueCost;
        ctx.catalystCost = catalystPreview.ok ? catalystPreview.cost : 0;
        ctx.balanceIsFresh = residueRackPending || catalystPreview.ok;
        ctx.residue = residueRackPending ? rackPreview.expectedResidue : catalystPreview.expectedResidue;

        EchoesResidueAction action = EvaluateEchoesResidueSpending(ctx);
        if (action != EchoesResidueAction::None)
        {
            uint32 resourceKey = static_cast<uint32>(EchoesStats::Progression::ResourceType::ResidueSpending);
            uint64 leaseKey = (static_cast<uint64>(guidLow) << 32) | resourceKey;
            auto it = EchoesStats::Progression::lastSpendSecondsByKey.find(leaseKey);
            uint32 secondsSince = (it == EchoesStats::Progression::lastSpendSecondsByKey.end())
                ? EchoesConfig::instance()->progressionSpendCooldownSeconds
                : (now > it->second ? now - it->second : 0);

            if (secondsSince >= EchoesConfig::instance()->progressionSpendCooldownSeconds)
            {
                spendAttemptedThisPass = true;
                EchoesActionBridge::ResiduePurchaseResult result;
                if (action == EchoesResidueAction::RackExpansion)
                    result = bridge->ExecuteResidueRackExpand(player, rackPreview);
                else
                    result = bridge->ExecuteCatalyst(player, catalystPreview);

                if (result.ok)
                {
                    EchoesStats::Progression::lastSpendSecondsByKey[leaseKey] = now;
                    ++EchoesStats::Progression::spendsSucceeded;
                    ++actionsThisLogin;
                    if (action == EchoesResidueAction::RackExpansion)
                        ++EchoesStats::Progression::residueRackSucceeded;
                    else
                        ++EchoesStats::Progression::catalystSucceeded;
                    if (!result.physicalSynced)
                        ++EchoesStats::Progression::residuePhysicalSyncDeferred;
                }
                else
                {
                    ++EchoesStats::Progression::residueAttemptsFailed;
                }
            }
        }
    }
}

// E2j2: recurring bounded progression-economy scheduler pass. Called from
// EchoesWorldScript::OnUpdate, itself only invoked when the module-level rate-limit gate there
// opens (see OnUpdate below) - this function's own body still enforces the SAME set of
// guarantees defensively (never trust the caller alone), matching this module's established
// belt-and-suspenders convention:
//   - never scans every online player's items or every account (bounded per-pass work budget);
//   - never touches a human (GET_PLAYERBOT_AI gate, identical to every other hook);
//   - never touches a master-controlled ("party") bot - GetMaster() != nullptr means a real
//     player is actively controlling this bot, which is out of scope for autonomous economy
//     management;
//   - never re-checks the same bot more often than progressionSchedulerPerBotRecheckSeconds;
//   - applies a deterministic per-bot jitter offset (derived from guid, never random) so a
//     large population does not all become eligible for recheck in the same instant;
//   - delegates the actual one-action-per-pass spend decision to the exact same
//     TryOneProgressionSpendForBot used by the login path - no divergent logic, no chained
//     async deductions, ever.
static void RunProgressionSchedulerPass()
{
    if (!EchoesConfig::instance()->progressionSchedulerEnabled)
        return;
    if (!EchoesConfig::instance()->progressionSpendingEnabled)
        return; // scheduler is a trigger mechanism only - never spends if spending itself is off
    if (!EchoesPresence::instance()->IsActiveOrDegraded())
        return;
    auto* bridge = EchoesActionBridge::instance();
    if (!bridge)
        return;

    ++EchoesStats::Progression::schedulerPassesRun;

    uint32 now = static_cast<uint32>(GameTime::GetGameTime().count());
    uint32 recheckFloor = EchoesConfig::instance()->progressionSchedulerPerBotRecheckSeconds;
    uint32 jitterWindow = EchoesConfig::instance()->progressionSchedulerJitterSeconds;
    uint32 budget = EchoesConfig::instance()->progressionSchedulerMaxBotsPerPass;
    uint32 evaluatedThisPass = 0;

    // Bounded snapshot of currently in-world players. This runs at most once per
    // progressionSchedulerIntervalSeconds (default 900s) - not per-tick - so a full pass over
    // the in-world player map at that reduced frequency is the established, safe pattern (the
    // same ObjectAccessor::GetPlayers() call is used by core's own WhoListCacheMgr and
    // WorldSessionMgr, both also low-frequency, both also full-population reads).
    // Rotating cursor: start just past the last GUID processed last pass, so a large population
    // is covered evenly over successive passes rather than always starting from the same point.
    uint32 cursor = EchoesStats::Progression::schedulerCursorGuid;
    uint32 firstConsideredGuid = 0;
    bool wrapped = false;

    for (auto const& [guid, botPlayer] : ObjectAccessor::GetPlayers())
    {
        if (evaluatedThisPass >= budget)
            break;

        if (!botPlayer || !botPlayer->IsInWorld())
            continue;

        uint32 guidLow = botPlayer->GetGUID().GetCounter();

        // Rotating-cursor gate: only consider guids strictly after the cursor this pass, unless
        // we have wrapped around once already (handles the case where the eligible population
        // is smaller than the cursor's current position, e.g. after a population shrink).
        if (!wrapped && guidLow <= cursor)
            continue;
        if (firstConsideredGuid == 0)
            firstConsideredGuid = guidLow;

        Player* botAiCheck = botPlayer; // GET_PLAYERBOT_AI takes Player*
        auto* botAi = GET_PLAYERBOT_AI(botAiCheck);
        if (!botAi)
            continue; // human isolation

        if (botAi->GetMaster() != nullptr)
        {
            ++EchoesStats::Progression::schedulerBotsSkippedControlled;
            continue; // master-controlled (party) bot, not autonomous - out of scope
        }

        auto it = EchoesStats::Progression::lastSchedulerCheckSecsByGuid.find(guidLow);
        uint32 lastChecked = (it == EchoesStats::Progression::lastSchedulerCheckSecsByGuid.end()) ? 0 : it->second;
        // Pure decision extracted to EchoesProgressionSchedulerPolicy.h (independently unit
        // tested) - deterministic per-bot jitter derived from guid, never a random draw.
        if (EchoesShouldSkipSchedulerRecheck(now, lastChecked, recheckFloor, jitterWindow, guidLow))
        {
            ++EchoesStats::Progression::schedulerBotsSkippedRecheckCooldown;
            continue;
        }

        ++EchoesStats::Progression::schedulerBotsConsidered;
        ++evaluatedThisPass;
        EchoesStats::Progression::lastSchedulerCheckSecsByGuid[guidLow] = now;
        EchoesStats::Progression::schedulerCursorGuid = guidLow;

        TryOneProgressionSpendForBot(botPlayer, SelectSinkCategoryForBot(botPlayer));
    }

    // If we never advanced past the old cursor (population fully consumed, or empty), reset to
    // 0 so the next pass starts from the beginning again rather than staying stuck.
    if (evaluatedThisPass == 0)
        EchoesStats::Progression::schedulerCursorGuid = 0;
}
#endif // MOD_PLAYERBOTS

// ── World lifecycle: config load, presence handshake, bounded recheck ──
class EchoesWorldScript : public WorldScript
{
public:
    EchoesWorldScript() : WorldScript("EchoesWorldScript",
        { WORLDHOOK_ON_AFTER_CONFIG_LOAD, WORLDHOOK_ON_STARTUP, WORLDHOOK_ON_UPDATE, WORLDHOOK_ON_SHUTDOWN })
    {
    }

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        EchoesConfig::instance()->Load();
    }

    void OnStartup() override
    {
        EchoesPresence::instance()->InitialCheck();
        LOG_INFO("module", "[{}] Layer 1 awareness module loaded, enabled={}, initial state={}",
                 ECHOES_PB_MODULE_STRING,
                 EchoesConfig::instance()->enabled,
                 EchoesPresenceStateToString(EchoesPresence::instance()->GetState()));
        LOG_INFO("module", "[{}] Layer 2 disposition prototype loaded, enabled={}",
                 ECHOES_PB_MODULE_STRING,
                 EchoesConfig::instance()->layer2Enabled);

        // E2i6 prototype: register the factory exactly once at startup. No
        // adapter performs any work here - registration is pure object
        // construction, zero Lua/DB interaction.
        EchoesAdapterFactory::instance()->Register(std::make_unique<EchoesRackAdapter>());
        EchoesAdapterFactory::instance()->Register(std::make_unique<EchoesDissolutionAdapter>());
        EchoesAdapterFactory::instance()->Register(std::make_unique<EchoesForgeAdapter>());
        // E2i8 naming correction: "Legacy Forge" IS the Dissolution system -
        // this log line must never again read "forge=unavailable" in a way
        // that could be misread as "no Dissolution system exists." Dissolution
        // dry-run availability and execute-enable are reported separately;
        // there is no separate upgrade/crafting Forge to report on at all.
        LOG_INFO("module", "[{}] Action bridge loaded, enabled={}, rack={}, dissolution_dryrun={}, dissolution_execute={} (legacy alias: AP.Forge.*), upgrade_crafting_forge=not_applicable",
                 ECHOES_PB_MODULE_STRING,
                 EchoesConfig::instance()->bridgeEnabled,
                 EchoesConfig::instance()->rackEnabled,
                 EchoesConfig::instance()->dissolutionDryRunEnabled,
                 EchoesConfig::instance()->dissolutionExecuteEnabled);
    }

    void OnUpdate(uint32 /*diff*/) override
    {
        // Single global, bounded, low-frequency recheck. Not per-bot, not
        // per-tick in effect - MaybeRecheck internally rate-limits to
        // EchoesConfig::presenceRecheckMinutes and is a no-op unless the
        // module is currently ACTIVE/DEGRADED.
        EchoesPresence::instance()->MaybeRecheck(static_cast<uint32>(GameTime::GetGameTime().count()));

        // E2j9a - deterministic test harness file-trigger. A secondary invocation path alongside
        // the ".echoes bot login/logout/status" console command (EchoesTestHarnessCommandScript.cpp)
        // - added specifically because scripted, non-interactive console-command delivery into a
        // TTY-allocated container proved impractical to prove out in this project's own tooling
        // environment (readline-based CLI, no reliable headless injection method found), while the
        // console command itself remains the documented primary interface for a real interactive
        // operator. Both paths call the exact same underlying Playerbots API
        // (sRandomPlayerbotMgr.AddPlayerBot/LogoutPlayerBot) - no separate login logic exists.
        // Gated identically behind EchoesConfig::testHarnessEnabled (default OFF). Polls at most
        // once every 2 real seconds - bounded, low-frequency, a single small-file existence check,
        // never per-tick. The request file is deleted immediately after being read, so a stale or
        // repeated file can never cause a double-processed request.
        // E2j14 Workstream B: this whole block only ever calls sRandomPlayerbotMgr, a
        // Playerbots-only global - guarded out entirely (not stubbed) when Playerbots is
        // absent, since there is no bot login/logout machinery for it to drive.
#ifdef MOD_PLAYERBOTS
        if (EchoesConfig::instance()->testHarnessEnabled)
        {
            uint32 nowSecsForHarness = static_cast<uint32>(GameTime::GetGameTime().count());
            static uint32 lastHarnessPollSecs = 0;
            if (nowSecsForHarness - lastHarnessPollSecs >= 2)
            {
                lastHarnessPollSecs = nowSecsForHarness;
                static char const* kRequestPath = "/azerothcore/env/dist/logs/echoes_test_harness_request.txt";
                std::ifstream reqFile(kRequestPath);
                if (reqFile.good())
                {
                    std::string line;
                    std::getline(reqFile, line);
                    reqFile.close();
                    std::remove(kRequestPath); // consume immediately - never processed twice

                    std::istringstream iss(line);
                    std::string action;
                    uint32 lowGuid = 0;
                    iss >> action >> lowGuid;
                    if (lowGuid != 0)
                    {
                        ObjectGuid guid = ObjectGuid::Create<HighGuid::Player>(lowGuid);
                        if (action == "login")
                        {
                            sRandomPlayerbotMgr.AddPlayerBot(guid, 0);
                            LOG_INFO("module", "[EchoesTestHarness] file-trigger login guid={}", lowGuid);
                        }
                        else if (action == "logout")
                        {
                            sRandomPlayerbotMgr.LogoutPlayerBot(guid);
                            LOG_INFO("module", "[EchoesTestHarness] file-trigger logout guid={}", lowGuid);
                        }
                        else
                        {
                            LOG_INFO("module", "[EchoesTestHarness] file-trigger unknown action='{}' guid={}", action, lowGuid);
                        }
                    }
                }
            }
        }
#endif // MOD_PLAYERBOTS

        // E2i9 Stage 8: bounded, rate-limited decision-report log line -
        // fixed-size content (counters + a capped sample list), emitted at
        // most once every 300 seconds. Never a per-tick or per-decision log.
        uint32 nowSecs = static_cast<uint32>(GameTime::GetGameTime().count());
        if (EchoesConfig::instance()->bridgeEnabled && EchoesConfig::instance()->dissolveEnabled
            && nowSecs - EchoesStats::Dissolution::lastReportLogSecs >= 300)
        {
            EchoesStats::Dissolution::lastReportLogSecs = nowSecs;
            LOG_INFO("module", "[{}] {}", ECHOES_PB_MODULE_STRING, EchoesPB_Dissolution_BuildDecisionReport());
        }

        // E2j2: recurring progression-economy scheduler gate. A single cheap timestamp check,
        // identical shape to the presence recheck and Dissolution report gates above - the
        // actual per-pass work (bounded to progressionSchedulerMaxBotsPerPass bots) only runs
        // when this opens, at most once every progressionSchedulerIntervalSeconds.
        // E2j14 Workstream B: RunProgressionSchedulerPass and every counter it produces are
        // Playerbots-only (see the Progression namespace/function guards above) - this whole
        // gate+report block is guarded out entirely when Playerbots is absent, rather than
        // logging a permanently-all-zero report every interval.
#ifdef MOD_PLAYERBOTS
        if (EchoesConfig::instance()->progressionSchedulerEnabled
            && nowSecs - EchoesStats::Progression::schedulerLastPassSecs >= EchoesConfig::instance()->progressionSchedulerIntervalSeconds)
        {
            EchoesStats::Progression::schedulerLastPassSecs = nowSecs;
            RunProgressionSchedulerPass();

            // Bounded, rate-limited aggregate metrics line - fixed-size counters only, never a
            // per-bot or per-decision log, matching the Dissolution decision-report convention.
            LOG_INFO("module", "[{}] progression_scheduler_report passes={} considered={} "
                     "skipped_cooldown={} skipped_controlled={} spends_succeeded={} "
                     "sink_invest_succeeded={} rack_expand_succeeded={} failed_post_verify={} "
                     "mastery_succeeded={} mastery_insufficient_essence={} mastery_db_failure={} "
                     "mastery_service_unavailable={} mastery_refresh_requested={} "
                     "residue_rack_succeeded={} catalyst_succeeded={} residue_attempts_failed={} "
                     "residue_physical_sync_deferred={}",
                     ECHOES_PB_MODULE_STRING,
                     EchoesStats::Progression::schedulerPassesRun,
                     EchoesStats::Progression::schedulerBotsConsidered,
                     EchoesStats::Progression::schedulerBotsSkippedRecheckCooldown,
                     EchoesStats::Progression::schedulerBotsSkippedControlled,
                     EchoesStats::Progression::spendsSucceeded,
                     EchoesStats::Progression::sinkInvestSucceeded,
                     EchoesStats::Progression::rackExpandSucceeded,
                     EchoesStats::Progression::spendsFailedPostVerify,
                     EchoesStats::Progression::masteryPurchaseSucceeded,
                     EchoesStats::Progression::masteryInsufficientEssence,
                     EchoesStats::Progression::masteryDatabaseFailure,
                     EchoesStats::Progression::masteryServiceUnavailable,
                     EchoesStats::Progression::masteryRefreshRequested,
                     EchoesStats::Progression::residueRackSucceeded,
                     EchoesStats::Progression::catalystSucceeded,
                     EchoesStats::Progression::residueAttemptsFailed,
                     EchoesStats::Progression::residuePhysicalSyncDeferred);
        }
#endif // MOD_PLAYERBOTS
    }

    void OnShutdown() override
    {
        EchoesPresence::instance()->BeginShutdown();
        EchoesBotCache::instance()->Clear();
        EchoesProtectionTracker::instance()->Clear(); // Layer 2: full cleanup, no persistence
        EchoesAdapterFactory::instance()->ClearLeases(); // E2i6: no stuck item lease survives a restart

        // E2j2: scheduler state is purely in-process bookkeeping (recheck timestamps, rotating
        // cursor) - never persisted, never referenced after shutdown. Clearing it here is
        // symmetrical with the other Clear() calls above and guarantees a clean restart always
        // starts the rotation from guid 0 rather than an arbitrary stale cursor position. Any
        // already-queued DeferredLoginReconcileEvent on a player's own m_Events is owned by that
        // Player object's event processor, not by this module, and AzerothCore's own shutdown
        // sequence tears down player objects (and their queued events) before this module could
        // ever be asked to do anything with a now-invalid Player* - there is nothing here for
        // this module to unsafely reference during shutdown.
        //
        // E2j14 Workstream B: EchoesStats::Progression is guarded out entirely when
        // MOD_PLAYERBOTS is undefined (see its definition above) - guarded here too, since
        // there is no scheduler state to clear when Playerbots (and therefore the scheduler
        // itself) is absent.
#ifdef MOD_PLAYERBOTS
        EchoesStats::Progression::lastSchedulerCheckSecsByGuid.clear();
        EchoesStats::Progression::schedulerCursorGuid = 0;
#endif
    }
};

// ── Per-player: login/logout cache lifecycle, equip-decision veto point ──
class EchoesPlayerScript : public PlayerScript
{
public:
    // E2j14 Workstream B: PLAYERHOOK_CAN_EQUIP_ITEM/PLAYERHOOK_CAN_SELL_ITEM are only
    // registered when Playerbots is present - OnPlayerCanEquipItem/OnPlayerCanSellItem below
    // are themselves guarded out (not overridden at all) when MOD_PLAYERBOTS is undefined, so
    // PlayerScript's own base-class default (`return true;` for both, see
    // src/server/game/Scripting/ScriptDefines/PlayerScript.h) applies unchanged - registering
    // the hook for a method that no longer exists as an override would be inconsistent.
    EchoesPlayerScript() : PlayerScript("EchoesPlayerScript",
#ifdef MOD_PLAYERBOTS
        { PLAYERHOOK_ON_LOGIN, PLAYERHOOK_ON_LOGOUT, PLAYERHOOK_CAN_EQUIP_ITEM, PLAYERHOOK_CAN_SELL_ITEM })
#else
        { PLAYERHOOK_ON_LOGIN, PLAYERHOOK_ON_LOGOUT })
#endif
    {
    }

    // E2j1 Stage 10 finding: GET_PLAYERBOT_AI(player) reads false for every random-autologin
    // bot at the exact instant PLAYERHOOK_ON_LOGIN fires (proven via direct diagnostic logging,
    // 9/9 bots, 9/9 rejections in a disposable-lab run) - mod-playerbots' own AI-attachment call
    // lives in a PlayerScript registered for the same hook, and script execution order between
    // independently-registered PlayerScripts is not guaranteed, so Echoes' check can run before
    // the AI object exists. Both MaybeReconcileLoginInventory (E2i9-R1, already production-
    // deployed) and MaybeReconcileProgressionSpending (E2j1) share this gate and were silently
    // no-op'ing for every autologin bot as a result. Fix: defer both checks by one short delay
    // via the player's own event queue (the same m_Events/BasicEvent idiom Unit.cpp uses
    // elsewhere in core, e.g. RedirectSpellEvent) instead of calling them synchronously inside
    // OnPlayerLogin - by the time this fires, mod-playerbots' own login handling has long since
    // attached the AI. GUID-based lookup (not a raw Player*) so a player who logs out during the
    // delay window is safely skipped rather than dereferenced.
    class DeferredLoginReconcileEvent : public BasicEvent
    {
    public:
        explicit DeferredLoginReconcileEvent(ObjectGuid guid) : _guid(guid) {}

        bool Execute(uint64 /*e_time*/, uint32 /*p_time*/) override
        {
            // Both reconciliation calls below are Playerbots-only (guarded out entirely when
            // MOD_PLAYERBOTS is undefined - see their definitions further down) - there is
            // nothing left for this deferred event to do in a Playerbots-absent build.
#ifdef MOD_PLAYERBOTS
            if (Player* player = ObjectAccessor::FindPlayer(_guid))
            {
                MaybeReconcileLoginInventory(player);
                MaybeReconcileProgressionSpending(player);
            }
#endif
            return true; // one-shot, always consume
        }

    private:
        ObjectGuid _guid;
    };

    void OnPlayerLogin(Player* player) override
    {
        if (!player)
            return;

        // See DeferredLoginReconcileEvent above for why this is deferred rather than run
        // synchronously here. 1500ms is comfortably past mod-playerbots' own same-hook AI
        // attachment while still being "at login" for all practical bounded-reconciliation
        // purposes.
        player->m_Events.AddEvent(new DeferredLoginReconcileEvent(player->GetGUID()),
            player->m_Events.CalculateTime(1500));
    }

    void OnPlayerLogout(Player* player) override
    {
        if (!player)
            return;
        // Always safe/cheap to call even for humans (who never had cache
        // entries in the first place) - InvalidateBot is a no-op if the
        // guid was never cached.
        uint32 guidLow = player->GetGUID().GetCounter();
        EchoesBotCache::instance()->InvalidateBot(guidLow);
        EchoesProtectionTracker::instance()->ReleaseAllForBot(guidLow); // Layer 2 logout cleanup
    }

    // E2j14 Workstream B: this whole override (through its closing brace, plus the
    // MaybeProtectFormerEquipment/MaybeOfferToRack/MaybeOfferToDissolution helpers it alone
    // calls, further below) is guarded out entirely when MOD_PLAYERBOTS is undefined, rather
    // than kept as a "return true" stub. This is a deliberate, verified choice, not an
    // oversight: PlayerScript::OnPlayerCanEquipItem's own base-class default (see
    // src/server/game/Scripting/ScriptDefines/PlayerScript.h) is already `return true;`, and
    // PLAYERHOOK_CAN_EQUIP_ITEM is no longer registered for this script above when
    // MOD_PLAYERBOTS is undefined - so simply not overriding this method reproduces the exact
    // same "never influence a human decision" behavior for free, with zero integration code
    // present in the binary, exactly as instructed.
#ifdef MOD_PLAYERBOTS
    bool OnPlayerCanEquipItem(Player* player, uint8 /*slot*/, uint16& /*dest*/, Item* pItem, bool /*swap*/, bool /*not_loading*/) override
    {
        // Human-player isolation is the first and only mandatory check.
        // Every other line in this function only ever runs for a
        // confirmed Playerbot. This is the single most important
        // invariant in the whole module (E2i1 Stage 13).
        if (!player || !GET_PLAYERBOT_AI(player))
        {
            ++EchoesStats::humanBypasses;
            return true; // never influence a human decision
        }

        if (!EchoesPresence::instance()->IsActiveOrDegraded())
        {
            ++EchoesStats::disabledBypasses;
            return true; // dormant: zero behavior change
        }

        if (!pItem)
            return true;

        ItemTemplate const* candidateProto = pItem->GetTemplate();
        if (!candidateProto)
            return true;

        // Only ever consider gear slots (weapons/armor) - never interfere
        // with bags, ammo, or anything ItemUsageValue itself would not
        // treat as an equip-comparable slot.
        uint8 invType = candidateProto->InventoryType;
        if (invType == INVTYPE_NON_EQUIP || invType == INVTYPE_BAG || invType == INVTYPE_AMMO)
            return true;

        // swap=true is required here (not merely a style choice): FindEquipSlot's own
        // "search free slot at first" logic (PlayerStorage.cpp) returns NULL_SLOT whenever
        // every matching slot is already occupied unless swap=true, even though this call's
        // entire purpose is to identify the (almost always occupied) slot this candidate
        // would replace so it can be scored against. FindEquipSlot itself never mutates
        // anything regardless of swap - it is a pure slot-number lookup - so this is a safe,
        // read-only correction, not a behavior change to equip/swap execution itself.
        uint8 equipSlot = player->FindEquipSlot(candidateProto, NULL_SLOT, true);
        if (equipSlot == NULL_SLOT)
            return true;

        Item* currentItem = player->GetItemByPos(INVENTORY_SLOT_BAG_0, equipSlot);

        ++EchoesStats::decisionsEvaluated;

        // Reuse Playerbots' own item scoring (StatsWeightCalculator) -
        // never invent a new scoring system.
        StatsWeightCalculator calculator(player);
        calculator.SetItemSetBonus(false);
        calculator.SetOverflowPenalty(false);

        float candidateScore = calculator.CalculateItem(candidateProto->ItemId, pItem->GetItemRandomPropertyId());
        float currentScore = currentItem
            ? calculator.CalculateItem(currentItem->GetTemplate()->ItemId, currentItem->GetItemRandomPropertyId())
            : 0.0f;

        bool stateAvailable = true;
        uint32 attunementPct = 0;
        bool fullyAttuned = false;

        if (currentItem)
        {
            auto info = EchoesBotCache::instance()->Get(
                player->GetGUID().GetCounter(),
                currentItem->GetTemplate()->ItemId,
                static_cast<uint32>(GameTime::GetGameTime().count()));

            if (!info.has_value())
            {
                stateAvailable = false;
                ++EchoesStats::errors;
            }
            else
            {
                attunementPct = info->PercentAttuned();
                fullyAttuned = info->fullyAttuned;
            }
        }

        EchoesAwarenessDecision decision = EvaluateAwareness(
            stateAvailable,
            currentScore,
            candidateScore,
            attunementPct,
            fullyAttuned,
            EchoesConfig::instance()->meaningfulAttunementPct,
            EchoesConfig::instance()->clearUpgradeMarginPct);

        switch (decision)
        {
            case EchoesAwarenessDecision::KEEP_ATTUNED_ITEM:
                ++EchoesStats::decisionsModified;
                return false; // veto the equip - this is the entire Layer 1 behavior
            case EchoesAwarenessDecision::FALLBACK_STATE_UNAVAILABLE:
                ++EchoesStats::defaultFallbacks;
                return true;
            case EchoesAwarenessDecision::ACCEPT_CLEAR_UPGRADE:
            {
                // Layer 2 (E2i4 prototype): the currently-equipped item is about to become
                // ordinary bag inventory. If it was meaningfully attuned, consider protecting
                // it from disposal. Read-only, process-local only - never re-equips, never
                // touches attunement, never spends resources, never queries per-tick.
                bool protectedInBag = false;
                if (currentItem && stateAvailable && EchoesConfig::instance()->layer2Enabled
                    && EchoesPresence::instance()->IsActiveOrDegraded())
                {
                    protectedInBag = MaybeProtectFormerEquipment(player, currentItem, attunementPct, fullyAttuned, equipSlot);
                }

                // E2i6/E2i8 combined priority chain: KEEP_IN_BAG (Layer 2) -> Rack ->
                // Dissolution preview. Only if Layer 2 did NOT protect this item does
                // the bridge get a turn to offer Rack; only if Rack did NOT store it
                // does Dissolution get a turn to preview it. Rack takes precedence over
                // Dissolution per Stage 4's explicit requirement (an item worth Racking
                // is never simultaneously offered to Dissolution) - this ordering is the
                // entire "prevent multiple adapters acting on the same item" guarantee
                // for this call site. Dissolution's automatic path is dry-run/preview
                // only (see MaybeOfferToDissolution) - real execution is never triggered
                // from ordinary gameplay in this phase.
                bool storedToRack = false;
                if (!protectedInBag && currentItem && stateAvailable
                    && EchoesConfig::instance()->bridgeEnabled && EchoesConfig::instance()->rackEnabled)
                {
                    storedToRack = MaybeOfferToRack(player, currentItem, attunementPct, fullyAttuned);
                }

                if (!protectedInBag && !storedToRack && currentItem && stateAvailable
                    && EchoesConfig::instance()->bridgeEnabled && EchoesConfig::instance()->dissolveEnabled)
                {
                    // E2i8-R1: this branch is only ever reached when EvaluateAwareness
                    // already returned ACCEPT_CLEAR_UPGRADE, which by construction means
                    // marginPct >= clearUpgradeMarginPct already held for THIS exact
                    // currentItem/candidate pair - Playerbots' own authoritative scoring
                    // already proved the incoming item is a clear upgrade over it. Passed
                    // through explicitly (not assumed) so the obsolescence proof is a real,
                    // traceable fact rather than an implicit "we're in this branch" inference.
                    MaybeOfferToDissolution(player, currentItem, attunementPct, fullyAttuned, /*replacementProven=*/true);
                }
                return true;
            }
            case EchoesAwarenessDecision::DEFAULT_PLAYERBOTS_DECISION:
            default:
                return true;
        }
    }
#endif // MOD_PLAYERBOTS

    // E2j14 Workstream B: same reasoning and same treatment as OnPlayerCanEquipItem above -
    // guarded out entirely (not stubbed) when MOD_PLAYERBOTS is undefined.
    // PlayerScript::OnPlayerCanSellItem's own base-class default is already `return true;` and
    // PLAYERHOOK_CAN_SELL_ITEM is no longer registered above in that configuration, so omitting
    // this override reproduces identical "never influence a human decision" behavior for free.
#ifdef MOD_PLAYERBOTS
    bool OnPlayerCanSellItem(Player* player, Item* pItem, Creature* /*creature*/) override
    {
        // Identical human-isolation invariant as the equip hook, applied to the sell path.
        if (!player || !GET_PLAYERBOT_AI(player))
        {
            ++EchoesStats::L2::humanBypasses;
            return true;
        }

        if (!EchoesConfig::instance()->layer2Enabled || !EchoesPresence::instance()->IsActiveOrDegraded())
        {
            ++EchoesStats::L2::disabledBypasses;
            return true; // dormant: zero behavior change, including when Layer 1 is active but Layer 2 is not
        }

        if (!pItem)
            return true;

        ++EchoesStats::L2::dispositionEvaluations;

        uint32 guidLow = player->GetGUID().GetCounter();
        ObjectGuid itemGuid = pItem->GetGUID();

        uint32 trackedAttunementPct = 0;
        bool isTracked = EchoesProtectionTracker::instance()->IsProtected(guidLow, itemGuid, trackedAttunementPct);
        if (!isTracked)
        {
            ++EchoesStats::L2::defaultDispositions;
            return true; // never opined on - not a protected item, defer entirely
        }

        ItemTemplate const* proto = pItem->GetTemplate();
        bool isQuestItem = proto && proto->Class == ITEM_CLASS_QUEST;

        uint32 freeSlots = player->GetFreeInventorySpace();
        bool bagPressureCritical = freeSlots <= EchoesConfig::instance()->layer2BagFreeSlotReserve;
        bool isLeastValued = bagPressureCritical
            && EchoesProtectionTracker::instance()->IsLeastValued(guidLow, itemGuid);

        EchoesDispositionDecision decision = EvaluateSellVeto(
            /*stateAvailable*/ true, // presence/enable already gated above; tracked-state is itself the "state"
            isQuestItem,
            bagPressureCritical,
            isLeastValued);

        switch (decision)
        {
            case EchoesDispositionDecision::PROTECT_IN_BAG:
                ++EchoesStats::L2::protectedItems;
                return false; // veto the sell - this is the entire Layer 2 prototype behavior
            case EchoesDispositionDecision::RELEASE_PROTECTION:
                EchoesProtectionTracker::instance()->Release(guidLow, itemGuid);
                ++EchoesStats::L2::releasedProtections;
                if (bagPressureCritical)
                    ++EchoesStats::L2::bagPressureReleases;
                if (isQuestItem)
                    ++EchoesStats::L2::staleOrMissingReleases;
                return true;
            case EchoesDispositionDecision::FALLBACK_STATE_UNAVAILABLE:
                ++EchoesStats::L2::cacheUnavailableFallbacks;
                return true;
            case EchoesDispositionDecision::DEFAULT_PLAYERBOTS_DISPOSITION:
            default:
                ++EchoesStats::L2::defaultDispositions;
                return true;
        }
    }
#endif // MOD_PLAYERBOTS

private:
    // E2j14 Workstream B: every private helper below is reachable only from the now-guarded
    // OnPlayerCanEquipItem/OnPlayerCanSellItem/DeferredLoginReconcileEvent call sites above -
    // MaybeProtectFormerEquipment, IsItemRackTracked, MaybeOfferToRack and
    // MaybeOfferToDissolution exist solely to serve OnPlayerCanEquipItem's ACCEPT_CLEAR_UPGRADE
    // branch; MaybeReconcileLoginInventory/ReconcileOneBagItem/MaybeReconcileProgressionSpending
    // are the deferred-login reconciliation pair. None has any other caller in this module, so
    // all are guarded out together rather than left as orphaned, uncallable code.
#ifdef MOD_PLAYERBOTS
    // Records a newly-unequipped, meaningfully-attuned item as a protection candidate.
    // Called only from the ACCEPT_CLEAR_UPGRADE branch above - never for marginal upgrades
    // (Layer 1 already handles those via KEEP_ATTUNED_ITEM, which never reaches this point).
    // Returns true if the item was actually protected (used by the caller to decide
    // whether the bridge's Rack adapter should get a turn as the next-best fallback).
    static bool MaybeProtectFormerEquipment(Player* player, Item* currentItem, uint32 attunementPct, bool fullyAttuned, uint8 priorSlot)
    {
        ItemTemplate const* proto = currentItem->GetTemplate();
        bool isQuestItem = proto && proto->Class == ITEM_CLASS_QUEST;

        uint32 guidLow = player->GetGUID().GetCounter();
        uint32 currentProtectedCount = EchoesProtectionTracker::instance()->CountForBot(guidLow);

        EchoesDispositionDecision decision = EvaluateProtectionCandidate(
            /*stateAvailable*/ true,
            attunementPct,
            fullyAttuned,
            isQuestItem,
            /*wasPreviouslyEquipped*/ true,
            EchoesConfig::instance()->layer2MinAttunementForRetention,
            currentProtectedCount,
            EchoesConfig::instance()->layer2MaxProtectedItemsPerBot);

        if (decision == EchoesDispositionDecision::PROTECT_IN_BAG)
        {
            EchoesProtectionTracker::instance()->Protect(
                guidLow, currentItem->GetGUID(), attunementPct, priorSlot,
                static_cast<uint32>(GameTime::GetGameTime().count()));
            return true;
        }
        return false;
    }

    // Read-only, single indexed lookup (guid, item_entry) mirroring
    // EchoesBotCache::Get's own query pattern - never a scan, only fired from
    // this decision-triggered event path. ap_rack tracks items purely as a
    // (guid, item_entry) row; item_entry = 0 means an empty slot (see
    // ap_rack.lua's RemoveItem, which clears to item_entry=0 rather than
    // deleting the row) so that must be excluded explicitly.
    static bool IsItemRackTracked(uint32 botGuidLow, uint32 itemEntry)
    {
        QueryResult result = CharacterDatabase.Query(
            "SELECT 1 FROM ap_rack WHERE guid = {} AND item_entry = {} LIMIT 1",
            botGuidLow, itemEntry);
        return result != nullptr;
    }

    // E2i6 prototype: offers a formerly-equipped item to the Rack adapter as the
    // next-best fallback when Layer 2 chose not to protect it. Dry-run first,
    // execute only on a SUCCESS dry-run result, guarded by the shared per-item
    // lease so no other adapter/evaluation can act on the same item concurrently.
    // Returns true only if the item was actually stored, so the caller can
    // decide whether Dissolution should get a turn as the next fallback.
    static bool MaybeOfferToRack(Player* player, Item* currentItem, uint32 attunementPct, bool fullyAttuned)
    {
        auto* rack = static_cast<EchoesRackAdapter*>(EchoesAdapterFactory::instance()->Get("Rack"));
        if (!rack || !rack->IsEnabled())
            return false;

        EchoesAdapterContext ctx;
        ctx.player = player;
        ctx.item = currentItem;
        ctx.attunementPct = attunementPct;
        ctx.fullyAttuned = fullyAttuned;

        if (!rack->IsEligible(ctx))
            return false;

        ObjectGuid itemGuid = currentItem->GetGUID();
        uint32 now = static_cast<uint32>(GameTime::GetGameTime().count());
        if (!EchoesAdapterFactory::instance()->TryAcquireLease(itemGuid, now, 60))
        {
            ++EchoesStats::Bridge::leaseConflicts;
            return false;
        }

        EchoesBotAction::Result dryRunResult = rack->Evaluate(ctx);
        rack->InterpretResult(dryRunResult);

        bool stored = false;
        if (dryRunResult.resultCode == EchoesBotAction::ResultCode::SUCCESS)
        {
            std::string token = std::to_string(player->GetGUID().GetCounter()) + ":" +
                                 std::to_string(currentItem->GetGUID().GetRawValue()) + ":rack_store";
            EchoesBotAction::Result execResult = rack->Store(ctx, token);
            if (execResult.resultCode == EchoesBotAction::ResultCode::SUCCESS)
            {
                ++EchoesStats::Bridge::rackStoresSucceeded;
                rack->UpdateBotState(ctx, execResult);
                stored = true;
            }
            else if (execResult.resultCode == EchoesBotAction::ResultCode::BRIDGE_UNAVAILABLE)
            {
                ++EchoesStats::Bridge::bridgeUnavailable;
            }
            else
            {
                ++EchoesStats::Bridge::rackRejections;
            }
        }
        else if (dryRunResult.resultCode == EchoesBotAction::ResultCode::BRIDGE_UNAVAILABLE)
        {
            ++EchoesStats::Bridge::bridgeUnavailable;
        }
        else
        {
            ++EchoesStats::Bridge::rackRejections;
        }

        ++EchoesStats::Bridge::rackEvaluations;
        EchoesAdapterFactory::instance()->ReleaseLease(itemGuid);
        return stored;
    }

    // E2i8: offers a formerly-equipped item to the Dissolution adapter as the
    // last fallback in the chain, only when Rack did not already claim it.
    // E2i8-through-E2j9: dry-run/preview ONLY - this automatic gameplay path never called
    // EchoesDissolutionAdapter::Execute(); real (destructive) execution was reserved for a
    // separate, never-production-wired fixture path, regardless of whether
    // EchoesConfig::dissolutionExecuteEnabled was true.
    // E2j11: this is now the ONE call site that also performs live execution - see the
    // dissolutionExecuteEnabled-gated block below, immediately after a SUCCESS dry-run. Nothing
    // about the dry-run path itself changed; execution is strictly additive and remains globally
    // OFF by default (dissolutionExecuteEnabled=false, unchanged production default).
    // E2i8-R1: `replacementProven` must be a real, already-computed fact -
    // the caller (the ACCEPT_CLEAR_UPGRADE branch below) passes the actual
    // marginPct>=clearUpgradeMarginPct result Layer 1 already derived from
    // Playerbots' own StatsWeightCalculator, never a hardcoded true. This is
    // the positive obsolescence proof Dissolution now requires.
    static void MaybeOfferToDissolution(Player* player, Item* currentItem, uint32 attunementPct, bool fullyAttuned, bool replacementProven)
    {
        auto* dissolution = static_cast<EchoesDissolutionAdapter*>(EchoesAdapterFactory::instance()->Get("Dissolution"));
        if (!dissolution || !dissolution->IsEnabled())
            return;

        ItemTemplate const* proto = currentItem->GetTemplate();
        if (!proto)
            return;

        uint32 guidLow = player->GetGUID().GetCounter();

        EchoesAdapterContext ctx;
        ctx.player = player;
        ctx.item = currentItem;
        ctx.attunementPct = attunementPct;
        ctx.fullyAttuned = fullyAttuned;

        // Real game-state population (E2i8 Stage 4) - every field defaults to
        // the safest value in EchoesAdapterContext itself, so anything left
        // unset below stays conservative rather than accidentally permissive.
        ctx.requestingBotOwnsItem = true;   // this item is in this bot's own bag by construction
        ctx.isEquipped = false;             // this call site only ever reaches formerly-equipped bag items
        ctx.isSelectedForEquip = false;     // a different item was just chosen as the new equip
        ctx.layer1Protected = false;        // Layer 1 already permitted this exact swap (ACCEPT_CLEAR_UPGRADE)
        ctx.keepInBagProtected = false;     // caller already confirmed Layer 2 did not protect this item
        ctx.rackProtected = IsItemRackTracked(guidLow, proto->ItemId);
        ctx.isQuestItem = proto->Class == ITEM_CLASS_QUEST;
        ctx.isUniqueItem = proto->MaxCount == 1; // AzerothCore's own "unique" stacking-cap convention
        ctx.isConjuredOrTemporary = proto->HasFlag(ITEM_FLAG_CONJURED) || proto->Duration > 0;
        ctx.isLockedOrInUse = false;        // just came out of this bot's own equip slot - cannot be
                                             // simultaneously in trade/mail/auction at this instant
        ctx.hasStableItemGuid = true;
        ctx.stateIsFresh = true;
        ctx.hasPendingActionConflict = false; // guaranteed by the lease acquired immediately below
        ctx.replacementProvenSuperior = replacementProven;
        ctx.saferAlternativeExists = false; // no ordinary-vendor-junk comparison implemented in this
                                             // phase - documented limitation, never inflates eligibility

        // E2i9: bounded decision observability. Purely additive - never
        // changes the gate below. EvaluateLocalPolicy is cheap (in-memory
        // struct comparisons only) and this call site only ever fires from
        // a genuine ACCEPT_CLEAR_UPGRADE event, never per-tick.
        ++EchoesStats::Dissolution::itemsConsidered;
        EchoesStats::Dissolution::botsSeen.insert(guidLow);
        DissolutionPolicyDecision observedDecision = dissolution->EvaluateLocalPolicy(ctx);
        uint32 decisionIdx = static_cast<uint32>(observedDecision);
        if (decisionIdx < EchoesStats::Dissolution::kDecisionSlots)
            ++EchoesStats::Dissolution::decisionCounts[decisionIdx];

        if (!dissolution->IsEligible(ctx))
            return;

        ObjectGuid itemGuid = currentItem->GetGUID();
        uint32 now = static_cast<uint32>(GameTime::GetGameTime().count());
        if (!EchoesAdapterFactory::instance()->TryAcquireLease(itemGuid, now, 60))
        {
            ++EchoesStats::Dissolution::leaseConflicts;
            return;
        }

        EchoesBotAction::Result dryRunResult = dissolution->Evaluate(ctx);
        dissolution->InterpretResult(dryRunResult);

        if (dryRunResult.resultCode == EchoesBotAction::ResultCode::SUCCESS)
        {
            ++EchoesStats::Dissolution::previewSuccesses;
            if (EchoesStats::Dissolution::eligibleSamples.size() >= EchoesStats::Dissolution::kMaxSamples)
                EchoesStats::Dissolution::eligibleSamples.pop_front();
            EchoesStats::Dissolution::eligibleSamples.push_back({
                guidLow, proto->ItemId, dryRunResult.authoritativeReward,
                static_cast<uint32>(GameTime::GetGameTime().count())});

            // E2j11: live execution. Reuses 100% of the already-built, already-tested
            // EchoesDissolutionAdapter::Execute() path (fresh revalidation, execution gate,
            // idempotency token, real AP.API.ExecuteBotAction mutation) - this is the ONLY call
            // site in the entire module that ever calls Execute() with dryRun=false. Gated
            // strictly behind EchoesConfig::dissolutionExecuteEnabled (default false, unchanged
            // production default) - when false, behavior here is byte-identical to the pre-E2j11
            // dry-run-only path. The lease acquired above is held through this call (released
            // only after, below) so no other Dissolution/Rack decision can touch this exact item
            // guid concurrently.
            if (EchoesConfig::instance()->dissolutionExecuteEnabled)
            {
                ++EchoesStats::Dissolution::executionsAttempted;

                // Idempotency token: unique per (bot, item, decision-tick) - the same
                // granularity every other lease/cooldown key in this module already uses. The
                // real dedup authority is Lua/DB-side (ap_dissolution_pending, E2j5h transaction
                // safety); this token only needs to be unique per genuine attempt, never reused.
                std::ostringstream tokenStream;
                tokenStream << "e2j11-" << guidLow << "-" << itemGuid.GetCounter() << "-" << now;
                std::string idempotencyToken = tokenStream.str();

                EchoesBotAction::Result execResult = dissolution->Execute(ctx, idempotencyToken);
                if (execResult.resultCode == EchoesBotAction::ResultCode::SUCCESS)
                {
                    ++EchoesStats::Dissolution::executionsSucceeded;
                    LOG_INFO("module", "[{}] dissolution_executed bot={} item={} reward={} token={}",
                        ECHOES_PB_MODULE_STRING, guidLow, proto->ItemId,
                        execResult.authoritativeReward, idempotencyToken);
                }
                else
                {
                    ++EchoesStats::Dissolution::executionsFailed;
                    LOG_INFO("module", "[{}] dissolution_execution_failed bot={} item={} reasonCode={} token={}",
                        ECHOES_PB_MODULE_STRING, guidLow, proto->ItemId,
                        execResult.reasonCode, idempotencyToken);
                }
            }
        }
        else
        {
            ++EchoesStats::Dissolution::previewFailures;
        }

        EchoesAdapterFactory::instance()->ReleaseLease(itemGuid);
    }

    // E2i9-R1: bounded login-reconciliation scan. Human isolation, module/bridge/adapter gates,
    // and the per-login item cap are all checked before any bag is touched. Reuses the exact
    // same Dissolution decision pipeline (EvaluateLocalPolicy/IsEligible/Evaluate/InterpretResult)
    // as the live equip-swap trigger - never a second implementation.
    static void MaybeReconcileLoginInventory(Player* player)
    {
        if (!player || !GET_PLAYERBOT_AI(player))
            return; // human isolation - identical invariant to every other hook in this module

        if (!EchoesConfig::instance()->loginReconciliationEnabled)
        {
            return;
        }

        if (!EchoesPresence::instance()->IsActiveOrDegraded())
        {
            return;
        }

        if (!EchoesConfig::instance()->bridgeEnabled || !EchoesConfig::instance()->dissolveEnabled)
        {
            return;
        }

        auto* dissolution = static_cast<EchoesDissolutionAdapter*>(EchoesAdapterFactory::instance()->Get("Dissolution"));
        if (!dissolution || !dissolution->IsEnabled())
        {
            return;
        }

        uint32 guidLow = player->GetGUID().GetCounter();
        uint32 now = static_cast<uint32>(GameTime::GetGameTime().count());
        uint32 scanned = 0;
        uint32 maxItems = EchoesConfig::instance()->loginReconciliationMaxItemsPerLogin;

        // E2j11: at most ONE real execution per login-reconciliation scan, even though up to
        // maxItems bag items may be dry-run-evaluated - the conservative "one bounded transaction
        // per invocation" default from the implementation authorization (Section 15), distinct
        // from and narrower than the scan's own dry-run item cap.
        bool executedThisLogin = false;

        StatsWeightCalculator calculator(player);
        calculator.SetItemSetBonus(false);
        calculator.SetOverflowPenalty(false);

        // Backpack slots + equipped bag containers - the exact same enumeration shape
        // mod-playerbots' own InventoryAction::IterateItemsInBags uses (Item* -> Bag* cast via
        // GetItemByPos, not a separate accessor) - reused verbatim, not reinvented.
        for (uint32 slot = INVENTORY_SLOT_ITEM_START; slot < INVENTORY_SLOT_ITEM_END && scanned < maxItems; ++slot)
        {
            if (Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
            {
                ReconcileOneBagItem(player, item, dissolution, calculator, guidLow, now, scanned, executedThisLogin);
            }
        }
        for (uint32 bagSlot = INVENTORY_SLOT_BAG_START; bagSlot < INVENTORY_SLOT_BAG_END && scanned < maxItems; ++bagSlot)
        {
            if (Bag* bag = (Bag*)player->GetItemByPos(INVENTORY_SLOT_BAG_0, bagSlot))
            {
                for (uint32 j = 0; j < bag->GetBagSize() && scanned < maxItems; ++j)
                {
                    if (Item* item = bag->GetItemByPos(j))
                    {
                        ReconcileOneBagItem(player, item, dissolution, calculator, guidLow, now, scanned, executedThisLogin);
                    }
                }
            }
        }
    }

    static void ReconcileOneBagItem(Player* player, Item* item, EchoesDissolutionAdapter* dissolution,
                                     StatsWeightCalculator& calculator, uint32 guidLow, uint32 now, uint32& scanned,
                                     bool& executedThisLogin)
    {
        ItemTemplate const* proto = item->GetTemplate();
        if (!proto)
            return;
        if (!((proto->Class == ITEM_CLASS_WEAPON || proto->Class == ITEM_CLASS_ARMOR) && proto->InventoryType > 0))
            return;

        ++scanned;
        ++EchoesStats::Dissolution::itemsConsidered;
        EchoesStats::Dissolution::botsSeen.insert(guidLow);

        auto info = EchoesBotCache::instance()->Get(guidLow, proto->ItemId, now);
        if (!info.has_value() || !info->fullyAttuned)
            return; // not fully attuned (or lookup failure - fails closed) - correctly excluded,
                     // never counted as a decision (matches the live path: only a currentItem
                     // reaching this point is ever evaluated against the policy)

        // Retroactive obsolescence proof: compare this bag item's score against whatever is
        // currently equipped in the same slot, reusing Playerbots' own StatsWeightCalculator and
        // the exact same clearUpgradeMarginPct threshold Layer 1 already uses live. A bag item
        // is never assumed obsolete merely for being unequipped - this is a real, evidence-based
        // comparison, never fabricated (E2i8-R1's own obsolescence-proof requirement applies
        // identically here).
        bool replacementProven = false;
        // swap=true - see the identical fix/rationale on the OnPlayerCanEquipItem call site
        // above (E2j11 root-cause diagnostic): without it, FindEquipSlot returns NULL_SLOT
        // whenever the slot is already occupied, which is the normal case for any bot with
        // gear on, defeating this comparison's entire purpose. Read-only; no behavior change
        // to actual equip/swap execution.
        uint8 equipSlot = player->FindEquipSlot(proto, NULL_SLOT, true);
        if (equipSlot != NULL_SLOT)
        {
            if (Item* equipped = player->GetItemByPos(INVENTORY_SLOT_BAG_0, equipSlot))
            {
                float equippedScore = calculator.CalculateItem(equipped->GetTemplate()->ItemId, equipped->GetItemRandomPropertyId());
                float bagItemScore = calculator.CalculateItem(proto->ItemId, item->GetItemRandomPropertyId());
                if (bagItemScore > 0.0f)
                {
                    float marginPct = (equippedScore - bagItemScore) / bagItemScore * 100.0f;
                    replacementProven = marginPct >= EchoesConfig::instance()->clearUpgradeMarginPct;
                }
            }
        }

        uint32 trackedAttunementPct = 0;
        EchoesAdapterContext ctx;
        ctx.player = player;
        ctx.item = item;
        ctx.attunementPct = info->PercentAttuned();
        ctx.fullyAttuned = true;
        ctx.requestingBotOwnsItem = true;
        ctx.isEquipped = false;
        ctx.isSelectedForEquip = false;
        ctx.layer1Protected = false;
        ctx.keepInBagProtected = EchoesProtectionTracker::instance()->IsProtected(guidLow, item->GetGUID(), trackedAttunementPct);
        ctx.rackProtected = IsItemRackTracked(guidLow, proto->ItemId);
        ctx.isQuestItem = proto->Class == ITEM_CLASS_QUEST;
        ctx.isUniqueItem = proto->MaxCount == 1;
        ctx.isConjuredOrTemporary = proto->HasFlag(ITEM_FLAG_CONJURED) || proto->Duration > 0;
        ctx.isLockedOrInUse = false; // documented conservative assumption - a sitting bag item's
                                     // trade/mail state is not queryable here; known limitation,
                                     // never inflates eligibility (false here can only add
                                     // caution relative to a true value, never remove it)
        ctx.hasStableItemGuid = true;
        ctx.stateIsFresh = true;
        ctx.hasPendingActionConflict = false;
        ctx.replacementProvenSuperior = replacementProven;
        ctx.saferAlternativeExists = false;

        DissolutionPolicyDecision decision = dissolution->EvaluateLocalPolicy(ctx);
        uint32 decisionIdx = static_cast<uint32>(decision);
        if (decisionIdx < EchoesStats::Dissolution::kDecisionSlots)
            ++EchoesStats::Dissolution::decisionCounts[decisionIdx];

        bool eligible = dissolution->IsEligible(ctx);
        if (!eligible)
            return;

        ObjectGuid itemGuid = item->GetGUID();
        if (!EchoesAdapterFactory::instance()->TryAcquireLease(itemGuid, now, 60))
        {
            ++EchoesStats::Dissolution::leaseConflicts;
            return;
        }

        EchoesBotAction::Result dryRunResult = dissolution->Evaluate(ctx);
        dissolution->InterpretResult(dryRunResult);

        if (dryRunResult.resultCode == EchoesBotAction::ResultCode::SUCCESS)
        {
            ++EchoesStats::Dissolution::previewSuccesses;
            if (EchoesStats::Dissolution::eligibleSamples.size() >= EchoesStats::Dissolution::kMaxSamples)
                EchoesStats::Dissolution::eligibleSamples.pop_front();
            EchoesStats::Dissolution::eligibleSamples.push_back({guidLow, proto->ItemId, dryRunResult.authoritativeReward, now});

            // E2j11: live execution, same gate/pattern as MaybeOfferToDissolution, capped to at
            // most one real execution per login scan via executedThisLogin (set by the caller,
            // shared across every item this login considers).
            if (!executedThisLogin && EchoesConfig::instance()->dissolutionExecuteEnabled)
            {
                executedThisLogin = true;
                ++EchoesStats::Dissolution::executionsAttempted;

                std::ostringstream tokenStream;
                tokenStream << "e2j11-login-" << guidLow << "-" << itemGuid.GetCounter() << "-" << now;
                std::string idempotencyToken = tokenStream.str();

                EchoesBotAction::Result execResult = dissolution->Execute(ctx, idempotencyToken);
                if (execResult.resultCode == EchoesBotAction::ResultCode::SUCCESS)
                {
                    ++EchoesStats::Dissolution::executionsSucceeded;
                    LOG_INFO("module", "[{}] dissolution_executed bot={} item={} reward={} token={}",
                        ECHOES_PB_MODULE_STRING, guidLow, proto->ItemId,
                        execResult.authoritativeReward, idempotencyToken);
                }
                else
                {
                    ++EchoesStats::Dissolution::executionsFailed;
                    LOG_INFO("module", "[{}] dissolution_execution_failed bot={} item={} reasonCode={} token={}",
                        ECHOES_PB_MODULE_STRING, guidLow, proto->ItemId,
                        execResult.reasonCode, idempotencyToken);
                }
            }
        }
        else
        {
            ++EchoesStats::Dissolution::previewFailures;
        }

        EchoesAdapterFactory::instance()->ReleaseLease(itemGuid);
    }

    // E2j1/E2j2/E2j9: bounded bot progression-economy spending, triggered here by the deferred
    // login event. See TryOneProgressionSpendForBot (file scope, above) for the actual gate/spend
    // logic, shared with the E2j2 recurring scheduler in EchoesWorldScript::OnUpdate. This
    // wrapper only resolves which of the 17 functional Crucible categories this bot is
    // deterministically assigned to (see SelectSinkCategoryForBot).
    static void MaybeReconcileProgressionSpending(Player* player)
    {
        if (!player)
            return;
        TryOneProgressionSpendForBot(player, SelectSinkCategoryForBot(player));
    }
#endif // MOD_PLAYERBOTS
};

void AddSC_EchoesPlayerbotsAwareness()
{
    new EchoesWorldScript();
    new EchoesPlayerScript();
}

// ── Instrumentation accessors (used only by the module's own test/report
//    tooling - not exposed to players, never logs individual inventory) ──
uint32 EchoesPB_GetDecisionsEvaluated() { return EchoesStats::decisionsEvaluated; }
uint32 EchoesPB_GetDecisionsModified() { return EchoesStats::decisionsModified; }
uint32 EchoesPB_GetDefaultFallbacks() { return EchoesStats::defaultFallbacks; }
uint32 EchoesPB_GetHumanBypasses() { return EchoesStats::humanBypasses; }
uint32 EchoesPB_GetDisabledBypasses() { return EchoesStats::disabledBypasses; }
uint32 EchoesPB_GetErrors() { return EchoesStats::errors; }

uint32 EchoesPB_L2_GetDispositionEvaluations() { return EchoesStats::L2::dispositionEvaluations; }
uint32 EchoesPB_L2_GetProtectedItems() { return EchoesStats::L2::protectedItems; }
uint32 EchoesPB_L2_GetReleasedProtections() { return EchoesStats::L2::releasedProtections; }
uint32 EchoesPB_L2_GetBagPressureReleases() { return EchoesStats::L2::bagPressureReleases; }
uint32 EchoesPB_L2_GetDefaultDispositions() { return EchoesStats::L2::defaultDispositions; }
uint32 EchoesPB_L2_GetCacheUnavailableFallbacks() { return EchoesStats::L2::cacheUnavailableFallbacks; }
uint32 EchoesPB_L2_GetHumanBypasses() { return EchoesStats::L2::humanBypasses; }
uint32 EchoesPB_L2_GetDisabledBypasses() { return EchoesStats::L2::disabledBypasses; }
uint32 EchoesPB_L2_GetStaleOrMissingReleases() { return EchoesStats::L2::staleOrMissingReleases; }
uint32 EchoesPB_L2_GetErrors() { return EchoesStats::L2::errors; }

uint32 EchoesPB_Bridge_GetRackEvaluations() { return EchoesStats::Bridge::rackEvaluations; }
uint32 EchoesPB_Bridge_GetRackStoresSucceeded() { return EchoesStats::Bridge::rackStoresSucceeded; }
uint32 EchoesPB_Bridge_GetRackRejections() { return EchoesStats::Bridge::rackRejections; }
uint32 EchoesPB_Bridge_GetLeaseConflicts() { return EchoesStats::Bridge::leaseConflicts; }
uint32 EchoesPB_Bridge_GetBridgeUnavailable() { return EchoesStats::Bridge::bridgeUnavailable; }

// E2i8: Dissolution adapter's own counters are owned by the adapter instance
// itself (registered once in EchoesWorldScript::OnStartup), not duplicated
// here - these accessors just forward to it, plus the one hook-local counter
// (lease conflicts) that belongs to this call site, not the adapter.
uint32 EchoesPB_Dissolution_GetEvaluations()
{
    auto* d = static_cast<EchoesDissolutionAdapter*>(EchoesAdapterFactory::instance()->Get("Dissolution"));
    return d ? d->GetEvaluations() : 0;
}
uint32 EchoesPB_Dissolution_GetEligibleDryRuns()
{
    auto* d = static_cast<EchoesDissolutionAdapter*>(EchoesAdapterFactory::instance()->Get("Dissolution"));
    return d ? d->GetEligibleDryRuns() : 0;
}
uint32 EchoesPB_Dissolution_GetRejections()
{
    auto* d = static_cast<EchoesDissolutionAdapter*>(EchoesAdapterFactory::instance()->Get("Dissolution"));
    return d ? d->GetRejections() : 0;
}
uint32 EchoesPB_Dissolution_GetExecutionsSucceeded()
{
    auto* d = static_cast<EchoesDissolutionAdapter*>(EchoesAdapterFactory::instance()->Get("Dissolution"));
    return d ? d->GetExecutionsSucceeded() : 0;
}
uint32 EchoesPB_Dissolution_GetExecutionsRejected()
{
    auto* d = static_cast<EchoesDissolutionAdapter*>(EchoesAdapterFactory::instance()->Get("Dissolution"));
    return d ? d->GetExecutionsRejected() : 0;
}
uint32 EchoesPB_Dissolution_GetExecutionsBlockedByGate()
{
    auto* d = static_cast<EchoesDissolutionAdapter*>(EchoesAdapterFactory::instance()->Get("Dissolution"));
    return d ? d->GetExecutionsBlockedByGate() : 0;
}
uint32 EchoesPB_Dissolution_GetLeaseConflicts() { return EchoesStats::Dissolution::leaseConflicts; }

// E2i9 Stage 8/9: bounded production decision-observability accessors. All
// read-only; none mutate any counter or sample. Sample identifiers are bot
// GUIDs and item entry IDs only - never character names, never full
// inventory contents.
uint32 EchoesPB_Dissolution_GetItemsConsidered() { return EchoesStats::Dissolution::itemsConsidered; }
uint32 EchoesPB_Dissolution_GetDistinctBotsConsidered() { return static_cast<uint32>(EchoesStats::Dissolution::botsSeen.size()); }
uint32 EchoesPB_Dissolution_GetDecisionCount(uint32 decision)
{
    return decision < EchoesStats::Dissolution::kDecisionSlots ? EchoesStats::Dissolution::decisionCounts[decision] : 0;
}
uint32 EchoesPB_Dissolution_GetPreviewSuccesses() { return EchoesStats::Dissolution::previewSuccesses; }
uint32 EchoesPB_Dissolution_GetPreviewFailures() { return EchoesStats::Dissolution::previewFailures; }

std::string EchoesPB_Dissolution_BuildDecisionReport()
{
    std::ostringstream oss;
    oss << "dissolution_decision_report items_considered=" << EchoesStats::Dissolution::itemsConsidered
        << " distinct_bots=" << EchoesStats::Dissolution::botsSeen.size()
        << " preview_successes=" << EchoesStats::Dissolution::previewSuccesses
        << " preview_failures=" << EchoesStats::Dissolution::previewFailures
        << " lease_conflicts=" << EchoesStats::Dissolution::leaseConflicts
        << " executions_attempted=" << EchoesStats::Dissolution::executionsAttempted
        << " executions_succeeded=" << EchoesStats::Dissolution::executionsSucceeded
        << " executions_failed=" << EchoesStats::Dissolution::executionsFailed;
    for (uint32 i = 0; i < EchoesStats::Dissolution::kDecisionSlots; ++i)
    {
        uint32 v = EchoesStats::Dissolution::decisionCounts[i];
        if (v > 0)
            oss << " " << DissolutionPolicyDecisionToString(static_cast<DissolutionPolicyDecision>(i)) << "=" << v;
    }
    oss << " sample_count=" << EchoesStats::Dissolution::eligibleSamples.size()
        << "(bounded_max=" << EchoesStats::Dissolution::kMaxSamples << ")";
    for (auto const& s : EchoesStats::Dissolution::eligibleSamples)
        oss << " | bot=" << s.botGuidLow << " item=" << s.itemEntry << " reward=" << s.previewReward << " ts=" << s.ts;
    return oss.str();
}
