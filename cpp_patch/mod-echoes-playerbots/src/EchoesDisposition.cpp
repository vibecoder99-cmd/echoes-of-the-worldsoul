#include "EchoesDisposition.h"

char const* EchoesDispositionDecisionToString(EchoesDispositionDecision d)
{
    switch (d)
    {
        case EchoesDispositionDecision::DEFAULT_PLAYERBOTS_DISPOSITION: return "DEFAULT_PLAYERBOTS_DISPOSITION";
        case EchoesDispositionDecision::PROTECT_IN_BAG: return "PROTECT_IN_BAG";
        case EchoesDispositionDecision::RELEASE_PROTECTION: return "RELEASE_PROTECTION";
        case EchoesDispositionDecision::FALLBACK_STATE_UNAVAILABLE: return "FALLBACK_STATE_UNAVAILABLE";
    }
    return "UNKNOWN";
}

EchoesDispositionDecision EvaluateProtectionCandidate(
    bool stateAvailable,
    std::uint32_t attunementPct,
    bool fullyAttuned,
    bool isQuestItem,
    bool wasPreviouslyEquipped,
    std::uint32_t meaningfulAttunementPct,
    std::uint32_t currentProtectedCount,
    std::uint32_t maxProtectedItems)
{
    // Fail dormant: any uncertainty defers to ordinary Playerbots behavior. Never guess.
    if (!stateAvailable)
        return EchoesDispositionDecision::FALLBACK_STATE_UNAVAILABLE;

    // Structural invariants this function enforces regardless of caller correctness - never
    // protect a quest item through this path, never protect something that was not actually
    // equipped gear.
    if (isQuestItem || !wasPreviouslyEquipped)
        return EchoesDispositionDecision::DEFAULT_PLAYERBOTS_DISPOSITION;

    bool meaningfullyAttuned = fullyAttuned || attunementPct >= meaningfulAttunementPct;
    if (!meaningfullyAttuned)
        return EchoesDispositionDecision::DEFAULT_PLAYERBOTS_DISPOSITION;

    // Do not protect unlimited items. The caller is responsible for releasing the least-valued
    // existing protection first if it wants to make room; this function only ever refuses to
    // grow past the configured limit, it never itself evicts another entry.
    if (currentProtectedCount >= maxProtectedItems)
        return EchoesDispositionDecision::DEFAULT_PLAYERBOTS_DISPOSITION;

    return EchoesDispositionDecision::PROTECT_IN_BAG;
}

EchoesDispositionDecision EvaluateSellVeto(
    bool stateAvailable,
    bool isQuestItem,
    bool bagPressureCritical,
    bool isLeastValuedProtectedUnderPressure)
{
    if (!stateAvailable)
        return EchoesDispositionDecision::FALLBACK_STATE_UNAVAILABLE;

    if (isQuestItem)
        return EchoesDispositionDecision::RELEASE_PROTECTION;

    // Bag-pressure release ordering: never block all inventory cleanup. Under critical
    // pressure, release the least-valued protected item first rather than refusing every sell.
    if (bagPressureCritical && isLeastValuedProtectedUnderPressure)
        return EchoesDispositionDecision::RELEASE_PROTECTION;

    return EchoesDispositionDecision::PROTECT_IN_BAG;
}
