#include "EchoesAwareness.h"

char const* EchoesAwarenessDecisionToString(EchoesAwarenessDecision d)
{
    switch (d)
    {
        case EchoesAwarenessDecision::DEFAULT_PLAYERBOTS_DECISION: return "DEFAULT_PLAYERBOTS_DECISION";
        case EchoesAwarenessDecision::KEEP_ATTUNED_ITEM: return "KEEP_ATTUNED_ITEM";
        case EchoesAwarenessDecision::ACCEPT_CLEAR_UPGRADE: return "ACCEPT_CLEAR_UPGRADE";
        case EchoesAwarenessDecision::FALLBACK_STATE_UNAVAILABLE: return "FALLBACK_STATE_UNAVAILABLE";
    }
    return "UNKNOWN";
}

EchoesAwarenessDecision EvaluateAwareness(
    bool stateAvailable,
    float currentItemScore,
    float candidateItemScore,
    std::uint32_t attunementPct,
    bool fullyAttuned,
    std::uint32_t meaningfulAttunementPct,
    std::uint32_t clearUpgradeMarginPct)
{
    // Fail dormant: any uncertainty about integration/cache state always
    // defers to ordinary Playerbots behavior. Never guess.
    if (!stateAvailable)
        return EchoesAwarenessDecision::FALLBACK_STATE_UNAVAILABLE;

    // Nothing currently equipped in the slot (or a non-positive score,
    // which Playerbots itself would treat as "no meaningful item") - there
    // is nothing to protect. Defer entirely.
    if (currentItemScore <= 0.0f)
        return EchoesAwarenessDecision::DEFAULT_PLAYERBOTS_DECISION;

    float marginPct = ((candidateItemScore - currentItemScore) / currentItemScore) * 100.0f;

    // A clear, large upgrade is always accepted, regardless of attunement.
    // This is the explicit instruction from E2i1/E2i2: never block a major
    // survivability/role upgrade.
    if (marginPct >= static_cast<float>(clearUpgradeMarginPct))
        return EchoesAwarenessDecision::ACCEPT_CLEAR_UPGRADE;

    // Below the clear-upgrade threshold: only intervene if the currently
    // equipped item represents meaningful (or full) attunement investment.
    bool meaningfullyAttuned = fullyAttuned || attunementPct >= meaningfulAttunementPct;
    if (meaningfullyAttuned)
        return EchoesAwarenessDecision::KEEP_ATTUNED_ITEM;

    // Marginal upgrade, but current item has no meaningful attunement
    // investment worth protecting - Echoes has no opinion either way.
    return EchoesAwarenessDecision::DEFAULT_PLAYERBOTS_DECISION;
}
