#ifndef MODULE_ECHOES_PLAYERBOTS_RACK_ADAPTER_H
#define MODULE_ECHOES_PLAYERBOTS_RACK_ADAPTER_H

#include "EchoesAdapterFactory.h"

// E2i6 Stage 9: Rack adapter - the first executable adapter because it is
// reversible (AP.Rack.AddItem/RemoveItem only ever toggle a tracking-table
// row; the item never physically leaves the bot's bags either way - see
// ap_rack.lua's own "the Rack tracks items the player carries" comment).
class EchoesRackAdapter : public IEchoesActionAdapter
{
public:
    char const* CapabilityName() const override { return "Rack"; }
    char const* TelemetryCategory() const override { return "rack"; }

    bool IsEligible(EchoesAdapterContext const& ctx) const override;
    EchoesBotAction::Result Evaluate(EchoesAdapterContext const& ctx) override;
    void InterpretResult(EchoesBotAction::Result const& result) override;
    void UpdateBotState(EchoesAdapterContext const& ctx, EchoesBotAction::Result const& result) override;
    void Fallback(EchoesAdapterContext const& ctx) override;

    bool IsEnabled() const override;
    bool IsDryRunOnly() const override { return false; } // executable, per Stage 9

    // Actually stores the item (calls EchoesActionBridge::ExecuteBotAction
    // with dryRun=false). Separate from Evaluate() so a caller can dry-run
    // first and only execute after its own decision to proceed.
    EchoesBotAction::Result Store(EchoesAdapterContext const& ctx, std::string const& idempotencyToken);
    EchoesBotAction::Result Retrieve(EchoesAdapterContext const& ctx, std::string const& idempotencyToken);

    uint32 GetEvaluations() const { return evaluations; }
    uint32 GetStoresSucceeded() const { return storesSucceeded; }
    uint32 GetRetrievesSucceeded() const { return retrievesSucceeded; }
    uint32 GetRejections() const { return rejections; }

private:
    uint32 evaluations = 0;
    uint32 storesSucceeded = 0;
    uint32 retrievesSucceeded = 0;
    uint32 rejections = 0;
};

#endif
