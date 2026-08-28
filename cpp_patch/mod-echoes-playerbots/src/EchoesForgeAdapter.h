#ifndef MODULE_ECHOES_PLAYERBOTS_FORGE_ADAPTER_H
#define MODULE_ECHOES_PLAYERBOTS_FORGE_ADAPTER_H

#include "EchoesAdapterFactory.h"

// E2i6 Stage 11: Forge adapter - DEFERRED shell only. Confirmed during Stage
// 6 Lua research: ap_forge.lua implements only Dissolve; there is no separate
// item-upgrade/crafting mutation function anywhere in Echoes today for this
// adapter to bridge to. Building a real "upgrade" mechanic would mean
// inventing new Echoes game rules in C++, which is explicitly prohibited
// ("do not duplicate Echoes formulas in C++" applies equally to formulas that
// do not yet exist). This class exists only to prove the factory pattern
// generalizes to a third adapter - IsEligible always returns false and
// Evaluate always returns CAPABILITY_UNAVAILABLE, exactly matching
// AP.API.GetCapabilities().canForge, which is permanently false.
class EchoesForgeAdapter : public IEchoesActionAdapter
{
public:
    char const* CapabilityName() const override { return "Forge"; }
    char const* TelemetryCategory() const override { return "forge"; }

    bool IsEligible(EchoesAdapterContext const& /*ctx*/) const override { return false; }

    EchoesBotAction::Result Evaluate(EchoesAdapterContext const& /*ctx*/) override
    {
        ++evaluations;
        EchoesBotAction::Result result;
        result.resultCode = EchoesBotAction::ResultCode::CAPABILITY_UNAVAILABLE;
        result.reasonCode = "forge_not_implemented";
        return result;
    }

    void InterpretResult(EchoesBotAction::Result const& /*result*/) override {}
    void UpdateBotState(EchoesAdapterContext const& /*ctx*/, EchoesBotAction::Result const& /*result*/) override {}
    void Fallback(EchoesAdapterContext const& /*ctx*/) override {}

    bool IsEnabled() const override { return false; } // permanently disabled - no capability
    bool IsDryRunOnly() const override { return true; }

    uint32 GetEvaluations() const { return evaluations; }

private:
    uint32 evaluations = 0;
};

#endif
