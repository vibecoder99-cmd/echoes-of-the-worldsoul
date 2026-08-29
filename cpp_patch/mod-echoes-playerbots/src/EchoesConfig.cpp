#include "EchoesConfig.h"
#include "Config.h"

static uint32 ClampU32(uint32 v, uint32 lo, uint32 hi)
{
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

void EchoesConfig::Load()
{
    enabled = sConfigMgr->GetOption<bool>("EchoesPlayerbots.Enable", false);

    meaningfulAttunementPct =
        ClampU32(sConfigMgr->GetOption<uint32>("EchoesPlayerbots.MeaningfulAttunementPct", 25), 1, 99);

    clearUpgradeMarginPct =
        ClampU32(sConfigMgr->GetOption<uint32>("EchoesPlayerbots.ClearUpgradeMarginPct", 15), 1, 200);

    presenceRecheckMinutes =
        ClampU32(sConfigMgr->GetOption<uint32>("EchoesPlayerbots.PresenceRecheckMinutes", 10), 1, 1440);

    compatibleVersionPrefix =
        sConfigMgr->GetOption<std::string>("EchoesPlayerbots.CompatibleVersionPrefix", "2.0.");

    // Layer 2 (E2i4 prototype)
    layer2Enabled = sConfigMgr->GetOption<bool>("EchoesPlayerbots.Layer2.Enable", false);

    layer2MinAttunementForRetention =
        ClampU32(sConfigMgr->GetOption<uint32>("EchoesPlayerbots.Layer2.MinAttunementForRetention", 25), 1, 99);

    layer2MaxProtectedItemsPerBot =
        ClampU32(sConfigMgr->GetOption<uint32>("EchoesPlayerbots.Layer2.MaxProtectedItemsPerBot", 3), 1, 20);

    layer2BagFreeSlotReserve =
        ClampU32(sConfigMgr->GetOption<uint32>("EchoesPlayerbots.Layer2.BagFreeSlotReserve", 2), 0, 20);

    // E2i6 prototype: action bridge
    bridgeEnabled = sConfigMgr->GetOption<bool>("EchoesPlayerbots.Bridge.Enable", false);
    rackEnabled = sConfigMgr->GetOption<bool>("EchoesPlayerbots.Bridge.Rack.Enable", false);
    dissolveEnabled = sConfigMgr->GetOption<bool>("EchoesPlayerbots.Bridge.Dissolve.Enable", false);
    forgeEnabled = sConfigMgr->GetOption<bool>("EchoesPlayerbots.Bridge.Forge.Enable", false);

    // E2i8: Dissolution (Legacy Forge) decision policy + safeguarded execution
    dissolutionDryRunEnabled =
        sConfigMgr->GetOption<bool>("EchoesPlayerbots.Bridge.Dissolution.DryRun.Enable", true);
    dissolutionExecuteEnabled =
        sConfigMgr->GetOption<bool>("EchoesPlayerbots.Bridge.Dissolution.Execute.Enable", false);

    // E2j9a - deterministic test harness safety gate.
    testHarnessEnabled =
        sConfigMgr->GetOption<bool>("EchoesPlayerbots.TestHarness.Enable", false);
    dissolutionRequiresFullAttunement =
        sConfigMgr->GetOption<bool>("EchoesPlayerbots.Bridge.Dissolution.RequireFullAttunement", true);
    dissolutionRejectsRackProtected =
        sConfigMgr->GetOption<bool>("EchoesPlayerbots.Bridge.Dissolution.RejectRackProtected", true);

    // E2i9-R1: bounded login-reconciliation trigger
    loginReconciliationEnabled =
        sConfigMgr->GetOption<bool>("EchoesPlayerbots.LoginReconciliation.Enable", false);
    loginReconciliationMaxItemsPerLogin =
        ClampU32(sConfigMgr->GetOption<uint32>("EchoesPlayerbots.LoginReconciliation.MaxItemsPerLogin", 10), 1, 50);

    // E2j1: bounded bot progression-economy spending
    progressionSpendingEnabled =
        sConfigMgr->GetOption<bool>("EchoesPlayerbots.Progression.Spending.Enable", false);
    progressionReserveEssence =
        sConfigMgr->GetOption<uint32>("EchoesPlayerbots.Progression.ReserveEssence", 500);
    progressionMaxSpendPerDecision =
        ClampU32(sConfigMgr->GetOption<uint32>("EchoesPlayerbots.Progression.MaxSpendPerDecision", 2000), 1, 100000);
    progressionMaxSpendActionsPerLogin =
        ClampU32(sConfigMgr->GetOption<uint32>("EchoesPlayerbots.Progression.MaxSpendActionsPerLogin", 3), 1, 25);
    progressionSpendCooldownSeconds =
        ClampU32(sConfigMgr->GetOption<uint32>("EchoesPlayerbots.Progression.SpendCooldownSeconds", 3600), 60, 86400);

    // E2j2: recurring bounded progression-economy scheduler
    progressionSchedulerEnabled =
        sConfigMgr->GetOption<bool>("EchoesPlayerbots.Progression.Scheduler.Enable", false);
    progressionSchedulerIntervalSeconds =
        ClampU32(sConfigMgr->GetOption<uint32>("EchoesPlayerbots.Progression.Scheduler.IntervalSeconds", 900), 60, 86400);
    progressionSchedulerJitterSeconds =
        ClampU32(sConfigMgr->GetOption<uint32>("EchoesPlayerbots.Progression.Scheduler.JitterSeconds", 180), 0, 3600);
    progressionSchedulerMaxBotsPerPass =
        ClampU32(sConfigMgr->GetOption<uint32>("EchoesPlayerbots.Progression.Scheduler.MaxBotsPerPass", 5), 1, 100);
    progressionSchedulerPerBotRecheckSeconds =
        ClampU32(sConfigMgr->GetOption<uint32>("EchoesPlayerbots.Progression.Scheduler.PerBotRecheckSeconds", 900), 60, 86400);

    progressionMasteryPurchaseEnabled =
        sConfigMgr->GetOption<bool>("EchoesPlayerbots.Progression.Mastery.Enable", false);

    progressionResidueSpendingEnabled =
        sConfigMgr->GetOption<bool>("EchoesPlayerbots.Progression.Residue.Enable", false);
}
