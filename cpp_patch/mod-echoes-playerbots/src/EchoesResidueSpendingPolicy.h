#ifndef MODULE_ECHOES_RESIDUE_SPENDING_POLICY_H
#define MODULE_ECHOES_RESIDUE_SPENDING_POLICY_H

#include <cstdint>

enum class EchoesResidueAction : std::uint8_t
{
    None = 0,
    RackExpansion,
    Catalyst
};

struct EchoesResidueSpendingContext
{
    bool adapterEnabled = false;
    bool balanceIsFresh = false;
    std::uint32_t residue = 0;
    bool rackPreviewOk = false;
    bool rackAtMaxCapacity = false;
    std::uint32_t rackEssenceCost = 0;
    std::uint32_t rackResidueCost = 0;
    std::uint32_t catalystCost = 0;
};

inline EchoesResidueAction EvaluateEchoesResidueSpending(EchoesResidueSpendingContext const& ctx)
{
    if (!ctx.adapterEnabled || !ctx.balanceIsFresh || !ctx.rackPreviewOk)
        return EchoesResidueAction::None;
    if (ctx.rackEssenceCost > 0 && ctx.rackResidueCost > 0)
        return EchoesResidueAction::None;
    if (!ctx.rackAtMaxCapacity && ctx.rackResidueCost > 0)
    {
        if (ctx.rackEssenceCost != 0)
            return EchoesResidueAction::None;
        return ctx.residue >= ctx.rackResidueCost
            ? EchoesResidueAction::RackExpansion
            : EchoesResidueAction::None;
    }
    if (ctx.catalystCost == 0)
        return EchoesResidueAction::None;
    return ctx.residue >= ctx.catalystCost
        ? EchoesResidueAction::Catalyst
        : EchoesResidueAction::None;
}

#endif
