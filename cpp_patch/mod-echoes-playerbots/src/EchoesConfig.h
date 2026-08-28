#ifndef MODULE_ECHOES_PLAYERBOTS_CONFIG_H
#define MODULE_ECHOES_PLAYERBOTS_CONFIG_H

#include "EchoesPlayerbotsCommon.h"
#include <string>

// All configuration is read once at startup (OnAfterConfigLoad) and cached.
// No per-bot or per-tick config re-read.
struct EchoesConfig
{
    // Master enable switch. Default OFF - integration is opt-in, never
    // silently active. When false, the presence handshake short-circuits
    // to DISABLED and no Echoes query of any kind is performed.
    bool enabled = false;

    // Minimum "meaningful attunement" percent (0-100) at which the
    // awareness policy starts protecting an item from a marginal upgrade.
    // Conservative default per E2i1 Stage 8.
    uint32 meaningfulAttunementPct = 25;

    // An upgrade below this percent improvement (relative to the
    // Playerbots-computed item score) is considered "marginal" and will be
    // rejected in favor of keeping meaningfully-attuned gear.
    // An upgrade at or above this percent is always accepted regardless of
    // attunement (a "clear upgrade"), per E2i1's explicit instruction not
    // to block clear/role-critical upgrades.
    uint32 clearUpgradeMarginPct = 15;

    // Bounded low-frequency re-check interval (minutes) for the presence
    // handshake once ACTIVE/DEGRADED, to detect a hot-uninstall without a
    // restart. This is a single global timer, never a per-bot query.
    uint32 presenceRecheckMinutes = 10;

    // Compatible Echoes schema/runtime version prefix. Kept as a simple
    // prefix match (e.g. "1.6.") rather than exact-string, so patch
    // releases remain compatible without a config change.
    std::string compatibleVersionPrefix = "1.6.";

    // --- Layer 2 (E2i4 prototype): KEEP_IN_BAG / PROTECT_FROM_DISPOSITION ---

    // Master Layer 2 switch, independent of Layer 1's `enabled`. Default OFF.
    // Layer 1 continues to function unchanged regardless of this setting.
    bool layer2Enabled = false;

    // Reuses the same "meaningful attunement" threshold concept as Layer 1
    // (E2i1/E2i3 definitions), applied to the retention decision instead of
    // the equip decision.
    uint32 layer2MinAttunementForRetention = 25;

    // Hard cap on how many unequipped items a single bot may have protected
    // from disposal at once. Never unlimited.
    uint32 layer2MaxProtectedItemsPerBot = 3;

    // Free-bag-slot threshold at or below which protection is released
    // (least-attuned protected item first) rather than blocking cleanup.
    uint32 layer2BagFreeSlotReserve = 2;

    // --- E2i6 prototype: Echoes-owned action bridge (Rack/Dissolve/Forge) ---

    // Master bridge switch, independent of Layer 1/2. Default OFF. When
    // false, no adapter is ever evaluated and zero AP.API.* calls are made.
    bool bridgeEnabled = false;

    // Per-adapter flags, each independently controllable per Stage 8's
    // explicit requirement. All default OFF.
    bool rackEnabled = false;
    bool dissolveEnabled = false;   // adapter presence (dry-run gate) - E2i6/E2i7 key, kept for
                                     // backward compatibility with the accepted production config
    bool forgeEnabled = false;      // permanently inert - there is no separate upgrade/crafting
                                     // Forge; see EchoesForgeAdapter and the E2i8 naming correction

    // --- E2i8: Dissolution (Legacy Forge) decision policy + safeguarded execution ---

    // Independent dry-run gate (default ON when the adapter itself is enabled) - separate from
    // dissolveEnabled so a future production phase (E2i9) can enable dry-run observation without
    // enabling destructive execution.
    bool dissolutionDryRunEnabled = true;

    // The real destructive-execution gate. Independent of Layer 1, Layer 2, Bridge, and Rack, per
    // E2i8 Stage 3's explicit requirement. Default OFF - this phase never enables it in production.
    bool dissolutionExecuteEnabled = false;

    // E2j9a - deterministic test harness safety gate. Independent of every other flag in this
    // struct: even a SEC_ADMINISTRATOR-only, console-gated command should not be reachable at all
    // in ordinary production operation. Default OFF - a checkpoint enables it explicitly and
    // returns it to OFF afterward, per the implementation authorization's explicit instruction.
    bool testHarnessEnabled = false;

    // Authoritative eligibility threshold, established from Echoes' own source (ap_forge.lua's
    // ShowPage/Dissolve queries both require ap_item_attune.attuned = 1) - NOT an independently
    // chosen value. Kept as a config key (rather than a hardcoded literal) only so a future phase
    // could observe Echoes' own threshold changing without a code change; the accepted default
    // documents where the number comes from, per E2i8 Stage 4's explicit instruction not to guess.
    bool dissolutionRequiresFullAttunement = true;

    // Bot-specific safety margin (stricter than the human path, which the E2i8 phase explicitly
    // permits): a Rack-tracked item is never offered to the Dissolution adapter, even though
    // Echoes' own human-facing Dissolve() does not itself block a Racked item (it just also clears
    // the Rack slot as a side effect - see the Stage 2 source audit).
    bool dissolutionRejectsRackProtected = true;

    // --- E2i9-R1: bounded login-reconciliation trigger ---

    // Master switch for the login reconciliation scan. Default OFF - purely additive, opt-in,
    // matching this module's established "never silently active" convention. When false,
    // OnPlayerLogin performs zero Echoes work, identical to pre-E2i9-R1 behavior.
    bool loginReconciliationEnabled = false;

    // Hard per-login cap on how many bag items are examined. Bounded so this can never become
    // per-login query amplification across a large bot population - a fixed, small ceiling,
    // never proportional to bag size beyond this cap.
    uint32 loginReconciliationMaxItemsPerLogin = 10;

    // --- E2j1: bounded bot progression-economy spending ---

    // Master switch. Default OFF - purely additive, opt-in. When false, zero Essence/Rack spend
    // work occurs, identical to pre-E2j1 behavior.
    bool progressionSpendingEnabled = false;

    // Minimum Essence balance a bot will never spend below - always retained, never touched.
    // Conservative default preserves a meaningful reserve rather than spending to zero.
    uint32 progressionReserveEssence = 500;

    // Hard cap on Essence committed in a single spend decision. Prevents one decision from
    // draining a large balance at once, regardless of how much is spendable.
    uint32 progressionMaxSpendPerDecision = 2000;

    // Hard per-login cap on how many spend actions (across all adapters) a single login event
    // may attempt. Bounded so this can never become per-login query/mutation amplification
    // across a large bot population - a fixed, small ceiling, matching the loginReconciliation
    // precedent exactly.
    uint32 progressionMaxSpendActionsPerLogin = 3;

    // Per-bot cooldown (seconds) between spend actions of the same kind, independent of the
    // per-item Dissolution/Rack lease mechanism - this is a resource-level lease, not an
    // item-level one.
    uint32 progressionSpendCooldownSeconds = 3600;

    // --- E2j2: recurring bounded progression-economy scheduler ---
    //
    // E2j1 Stage 11 proved the login-only trigger gives each autonomous bot exactly one
    // reconciliation opportunity per session, near session start when balance is lowest -
    // effectively inert for long-lived randombot-autologin populations. This adds a second,
    // independent, low-frequency global trigger via WORLDHOOK_ON_UPDATE (matching the existing
    // presence-recheck/dissolution-report pattern in this file - a single cheap timestamp gate,
    // never per-tick work). Reuses MaybeReconcileProgressionSpending's exact one-action-per-pass,
    // fail-closed, reserve/cap/cooldown-respecting logic - this is a new TRIGGER, not a new
    // spending mechanism.

    // Master switch. Default OFF - purely additive, opt-in, identical convention to every other
    // switch in this file.
    bool progressionSchedulerEnabled = false;

    // Base interval (seconds) between scheduler passes. A pass does not touch every bot - it
    // advances a bounded rotating cursor (see progressionSchedulerMaxBotsPerPass) over the
    // current in-world autonomous-bot population.
    uint32 progressionSchedulerIntervalSeconds = 900;

    // Per-bot jitter window (seconds), applied as a deterministic offset derived from the bot's
    // own GUID (never true randomness - reproducible, auditable) so that bots do not all become
    // eligible for a recheck at the exact same instant. Spreads load without adding
    // non-determinism to spending decisions themselves.
    uint32 progressionSchedulerJitterSeconds = 180;

    // Hard per-pass work budget: the maximum number of bots evaluated in a single scheduler
    // pass, regardless of how many are online. Never proportional to total bot count - this is
    // the global work-budget requirement.
    uint32 progressionSchedulerMaxBotsPerPass = 5;

    // Minimum interval (seconds) between two scheduler-driven reconciliation passes for the
    // SAME bot, independent of progressionSpendCooldownSeconds (which gates repeat spends of the
    // same resource). This is a recheck-frequency floor, so a small online population cannot
    // cause the same handful of bots to be re-evaluated every pass.
    uint32 progressionSchedulerPerBotRecheckSeconds = 900;

    // --- E2j5: Mastery as a bounded bot spending target ---
    //
    // Master switch. Default OFF - purely additive, opt-in, identical convention to every other
    // switch in this file. When false, Mastery is never considered as a spend candidate - zero
    // AP.Mastery.Purchase calls, identical to pre-E2j5 behavior. Reuses every existing
    // progressionReserveEssence/progressionMaxSpendPerDecision/progressionSpendCooldownSeconds/
    // progressionSchedulerMaxBotsPerPass knob above - no separate Mastery-only budget/cooldown
    // config exists, by design, to avoid a second parallel tuning surface.
    bool progressionMasteryPurchaseEnabled = false;

    // E2j10: autonomous account-level Worldsoul Residue spending. Independent
    // default-OFF gate so ordinary progression spending cannot silently enable
    // Rack/Catalyst purchases. Reuses the existing scheduler/cooldown bounds.
    bool progressionResidueSpendingEnabled = false;

    static EchoesConfig* instance()
    {
        static EchoesConfig cfg;
        return &cfg;
    }

    void Load();
};

#endif
