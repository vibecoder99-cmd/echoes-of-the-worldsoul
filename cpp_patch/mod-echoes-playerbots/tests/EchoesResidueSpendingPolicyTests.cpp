#include "EchoesResidueSpendingPolicy.h"
#include <cstdio>
#include <initializer_list>

static int gPass = 0;
static int gFail = 0;
static void Check(char const* name, bool condition)
{
    if (condition) { ++gPass; std::printf("PASS: %s\n", name); }
    else { ++gFail; std::printf("FAIL: %s\n", name); }
}
static EchoesResidueSpendingContext Base()
{
    EchoesResidueSpendingContext ctx;
    ctx.adapterEnabled = true; ctx.balanceIsFresh = true; ctx.rackPreviewOk = true;
    ctx.rackEssenceCost = 500; ctx.catalystCost = 10;
    return ctx;
}
int main()
{
    { auto c=Base(); c.adapterEnabled=false; c.residue=1000; Check("01_disabled", EvaluateEchoesResidueSpending(c)==EchoesResidueAction::None); }
    { auto c=Base(); c.balanceIsFresh=false; c.residue=1000; Check("02_unverified_balance", EvaluateEchoesResidueSpending(c)==EchoesResidueAction::None); }
    { auto c=Base(); c.rackPreviewOk=false; c.residue=1000; Check("03_unverified_rack", EvaluateEchoesResidueSpending(c)==EchoesResidueAction::None); }
    for (std::uint32_t n : {0u,1u,9u}) { auto c=Base(); c.residue=n; Check("04_below_catalyst", EvaluateEchoesResidueSpending(c)==EchoesResidueAction::None); }
    { auto c=Base(); c.residue=10; Check("05_exact_catalyst", EvaluateEchoesResidueSpending(c)==EchoesResidueAction::Catalyst); }
    { auto c=Base(); c.residue=1000000; Check("06_large_catalyst", EvaluateEchoesResidueSpending(c)==EchoesResidueAction::Catalyst); }
    { auto c=Base(); c.rackEssenceCost=0; c.rackResidueCost=15; c.residue=15; Check("07_exact_rack", EvaluateEchoesResidueSpending(c)==EchoesResidueAction::RackExpansion); }
    { auto c=Base(); c.rackEssenceCost=0; c.rackResidueCost=40; c.residue=39; Check("08_reserve_for_rack", EvaluateEchoesResidueSpending(c)==EchoesResidueAction::None); }
    { auto c=Base(); c.rackEssenceCost=0; c.rackResidueCost=100; c.residue=1000000; Check("09_large_rack", EvaluateEchoesResidueSpending(c)==EchoesResidueAction::RackExpansion); }
    { auto c=Base(); c.rackAtMaxCapacity=true; c.rackEssenceCost=0; c.residue=10; Check("10_max_allows_catalyst", EvaluateEchoesResidueSpending(c)==EchoesResidueAction::Catalyst); }
    { auto c=Base(); c.rackEssenceCost=500; c.rackResidueCost=15; c.residue=100; Check("11_mixed_cost_fails", EvaluateEchoesResidueSpending(c)==EchoesResidueAction::None); }
    { auto c=Base(); c.catalystCost=0; c.residue=100; Check("12_invalid_catalyst", EvaluateEchoesResidueSpending(c)==EchoesResidueAction::None); }
    std::printf("RESULT: %d passed, %d failed\n", gPass, gFail);
    return gFail == 0 ? 0 : 1;
}
