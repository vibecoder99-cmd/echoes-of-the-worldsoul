#ifndef MODULE_ECHOES_PLAYERBOTS_PROGRESSION_BUDGET_POLICY_H
#define MODULE_ECHOES_PLAYERBOTS_PROGRESSION_BUDGET_POLICY_H

#include <cstdint>

// E2j1: the common, reusable resource-spending budget policy shared by every progression
// adapter (Crucible/Sinks, Rack expansion; Mastery/Talents deferred - see EchoesConfig.h).
// Deliberately dependency-free (no AzerothCore/Playerbots headers) so it compiles and is
// unit-testable completely standalone, matching the established pattern of
// EchoesDissolutionPolicy.h/EchoesAwareness.h/EchoesDisposition.h. This class decides ONLY
// whether a proposed spend is safe to attempt - it never itself talks to Lua/DB/game state.
enum class ProgressionSpendDecision : uint32_t
{
    ELIGIBLE_TO_SPEND = 0,
    REJECT_ADAPTER_DISABLED = 1,
    REJECT_INVALID_COST = 2,               // cost <= 0, or balance/reserve fields malformed
    REJECT_BELOW_RESERVE = 3,              // spending would drop balance below the reserve floor
    REJECT_EXCEEDS_PER_DECISION_MAX = 4,   // cost exceeds the configured single-decision ceiling
    REJECT_INSUFFICIENT_BALANCE = 5,       // balance itself is less than cost (even before reserve)
    REJECT_LOGIN_CAP_REACHED = 6,          // this login event already spent its bounded action budget
    REJECT_COOLDOWN_ACTIVE = 7,            // this resource/bot pair spent too recently
    REJECT_STALE_BALANCE = 8,              // balance snapshot is too old to trust for a spend decision
};

inline char const* ProgressionSpendDecisionToString(ProgressionSpendDecision decision)
{
    switch (decision)
    {
        case ProgressionSpendDecision::ELIGIBLE_TO_SPEND: return "ELIGIBLE_TO_SPEND";
        case ProgressionSpendDecision::REJECT_ADAPTER_DISABLED: return "REJECT_ADAPTER_DISABLED";
        case ProgressionSpendDecision::REJECT_INVALID_COST: return "REJECT_INVALID_COST";
        case ProgressionSpendDecision::REJECT_BELOW_RESERVE: return "REJECT_BELOW_RESERVE";
        case ProgressionSpendDecision::REJECT_EXCEEDS_PER_DECISION_MAX: return "REJECT_EXCEEDS_PER_DECISION_MAX";
        case ProgressionSpendDecision::REJECT_INSUFFICIENT_BALANCE: return "REJECT_INSUFFICIENT_BALANCE";
        case ProgressionSpendDecision::REJECT_LOGIN_CAP_REACHED: return "REJECT_LOGIN_CAP_REACHED";
        case ProgressionSpendDecision::REJECT_COOLDOWN_ACTIVE: return "REJECT_COOLDOWN_ACTIVE";
        case ProgressionSpendDecision::REJECT_STALE_BALANCE: return "REJECT_STALE_BALANCE";
        default: return "UNKNOWN";
    }
}

// Every field defaults to the safest/most conservative value, matching EchoesAdapterContext's
// own established convention: an all-default-constructed context always rejects a spend.
struct ProgressionBudgetContext
{
    bool adapterEnabled = false;
    int64_t currentBalance = -1;           // -1 = unknown/unset, always rejected
    uint32_t reserveEssence = 0;
    uint32_t maxSpendPerDecision = 0;
    uint32_t proposedCost = 0;
    uint32_t actionsAlreadyThisLogin = 0;
    uint32_t maxActionsPerLogin = 0;
    uint32_t secondsSinceLastSpend = 0;    // for this exact (bot, resource) pair
    uint32_t cooldownSeconds = 0;
    bool balanceIsFresh = false;           // caller must prove the balance was just read, never assumed
};

// Pure, deterministic. Checked in a fixed, documented order so any two callers evaluating the
// same context always agree, and so the FIRST failing reason is always the one reported -
// mirrors EvaluateDissolutionEligibility's own ordered-gate convention exactly.
inline ProgressionSpendDecision EvaluateProgressionSpend(ProgressionBudgetContext const& ctx)
{
    if (!ctx.adapterEnabled)
        return ProgressionSpendDecision::REJECT_ADAPTER_DISABLED;

    if (ctx.proposedCost == 0 || ctx.maxSpendPerDecision == 0)
        return ProgressionSpendDecision::REJECT_INVALID_COST;

    if (!ctx.balanceIsFresh || ctx.currentBalance < 0)
        return ProgressionSpendDecision::REJECT_STALE_BALANCE;

    if (ctx.actionsAlreadyThisLogin >= ctx.maxActionsPerLogin)
        return ProgressionSpendDecision::REJECT_LOGIN_CAP_REACHED;

    if (ctx.cooldownSeconds > 0 && ctx.secondsSinceLastSpend < ctx.cooldownSeconds)
        return ProgressionSpendDecision::REJECT_COOLDOWN_ACTIVE;

    if (ctx.proposedCost > ctx.maxSpendPerDecision)
        return ProgressionSpendDecision::REJECT_EXCEEDS_PER_DECISION_MAX;

    if (static_cast<int64_t>(ctx.proposedCost) > ctx.currentBalance)
        return ProgressionSpendDecision::REJECT_INSUFFICIENT_BALANCE;

    int64_t balanceAfterSpend = ctx.currentBalance - static_cast<int64_t>(ctx.proposedCost);
    if (balanceAfterSpend < static_cast<int64_t>(ctx.reserveEssence))
        return ProgressionSpendDecision::REJECT_BELOW_RESERVE;

    return ProgressionSpendDecision::ELIGIBLE_TO_SPEND;
}

#endif
