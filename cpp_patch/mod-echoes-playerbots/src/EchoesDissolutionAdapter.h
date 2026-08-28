#ifndef MODULE_ECHOES_PLAYERBOTS_DISSOLUTION_ADAPTER_H
#define MODULE_ECHOES_PLAYERBOTS_DISSOLUTION_ADAPTER_H

#include "EchoesAdapterFactory.h"
#include "EchoesDissolutionPolicy.h"
#include <string>

// E2i8: Dissolution ("Legacy Forge") adapter. Supersedes the E2i6/E2i7
// EchoesDissolveAdapter (dry-run-only prototype) with the full conservative
// decision policy (EchoesDissolutionPolicy.h) plus a safeguarded, gated
// execution path that calls the REAL AP.Forge.Dissolve mutation - never
// reimplements it.
//
// "Legacy Forge" IS Dissolution (see the E2i8 Stage 2 source audit,
// env/backups/e2i8/.../source-audit/) - this class is registered under
// CapabilityName() "Dissolution", with "LegacyForge" reported as an explicit
// alias, never a second implementation.
class EchoesDissolutionAdapter : public IEchoesActionAdapter
{
public:
    char const* CapabilityName() const override { return "Dissolution"; }
    char const* TelemetryCategory() const override { return "dissolution"; }
    static char const* LegacyAliasName() { return "LegacyForge"; }

    bool IsEligible(EchoesAdapterContext const& ctx) const override;
    EchoesBotAction::Result Evaluate(EchoesAdapterContext const& ctx) override; // dry-run preview only
    void InterpretResult(EchoesBotAction::Result const& result) override;
    void UpdateBotState(EchoesAdapterContext const& ctx, EchoesBotAction::Result const& result) override;
    void Fallback(EchoesAdapterContext const& ctx) override;

    bool IsEnabled() const override;         // adapter present at all (dry-run gate)
    bool IsDryRunOnly() const override;      // true unless EchoesConfig::dissolutionExecuteEnabled

    // Builds the local (non-Lua) policy context from real game state, then
    // runs EvaluateDissolutionEligibility. Exposed separately from
    // IsEligible() (which stays a cheap bool per the factory interface) so
    // the richer decision + reason can be logged/tested.
    DissolutionPolicyDecision EvaluateLocalPolicy(EchoesAdapterContext const& ctx) const;

    // Real, gated execution path (Stage 6). Only ever called after a caller
    // has already obtained ELIGIBLE_FOR_PREVIEW locally AND a SUCCESS dry-run
    // result from the bridge. Performs a fresh revalidation immediately
    // before calling the bridge's non-dry-run ExecuteBotAction.
    EchoesBotAction::Result Execute(EchoesAdapterContext const& ctx, std::string const& idempotencyToken);

    uint32 GetEvaluations() const { return evaluations; }
    uint32 GetEligibleDryRuns() const { return eligibleDryRuns; }
    uint32 GetRejections() const { return rejections; }
    uint32 GetExecutionsSucceeded() const { return executionsSucceeded; }
    uint32 GetExecutionsRejected() const { return executionsRejected; }
    uint32 GetExecutionsBlockedByGate() const { return executionsBlockedByGate; }

private:
    uint32 evaluations = 0;
    uint32 eligibleDryRuns = 0;
    uint32 rejections = 0;
    uint32 executionsSucceeded = 0;
    uint32 executionsRejected = 0;
    uint32 executionsBlockedByGate = 0;
};

#endif
