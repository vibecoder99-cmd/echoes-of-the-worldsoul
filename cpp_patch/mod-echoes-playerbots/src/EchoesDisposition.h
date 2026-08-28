#ifndef MODULE_ECHOES_PLAYERBOTS_DISPOSITION_H
#define MODULE_ECHOES_PLAYERBOTS_DISPOSITION_H

#include <cstdint>

// Layer 2 (E2i4 prototype): pure, dependency-free decision policy for item retention
// ("KEEP_IN_BAG" / "PROTECT_FROM_DISPOSITION"). Deliberately has zero AzerothCore/Playerbots/
// Echoes dependency (mirrors EchoesAwareness.h's own pattern) so it is standalone-testable
// and trivially reviewable in isolation from any runtime state.
//
// Two independent decision points, matching the two real call sites:
//   1. EvaluateProtectionCandidate - fired once, at the moment a meaningfully-attuned item is
//      unequipped in favor of a clear upgrade (Layer 1's own ACCEPT_CLEAR_UPGRADE outcome).
//      Decides whether to START protecting that item.
//   2. EvaluateSellVeto - fired from PlayerScript::OnPlayerCanSellItem, only ever for items
//      already tracked as protected. Decides whether to veto the sell (keep protecting) or
//      release protection (allow the sell), factoring in bag-pressure release ordering.

enum class EchoesDispositionDecision : std::uint8_t
{
    DEFAULT_PLAYERBOTS_DISPOSITION = 0,  // no opinion - defer entirely to Playerbots
    PROTECT_IN_BAG = 1,                  // start or continue protecting (veto sell)
    RELEASE_PROTECTION = 2,              // stop protecting (allow default disposition)
    FALLBACK_STATE_UNAVAILABLE = 3       // uncertainty - always defer to default Playerbots behavior
};

char const* EchoesDispositionDecisionToString(EchoesDispositionDecision d);

// Called once, at the exact moment Layer 1 accepts a clear upgrade over a meaningfully-attuned
// currently-equipped item (i.e. the item is about to become ordinary bag inventory). Never
// called for items with no meaningful attunement - "marginal upgrade, no attunement to protect"
// is already handled entirely by Layer 1's own DEFAULT_PLAYERBOTS_DECISION outcome and never
// reaches this function at all.
EchoesDispositionDecision EvaluateProtectionCandidate(
    bool stateAvailable,                  // cache/presence state available (fail-dormant otherwise)
    std::uint32_t attunementPct,
    bool fullyAttuned,
    bool isQuestItem,                     // quest items are never eligible via this path
    bool wasPreviouslyEquipped,           // this function is only ever called for such items;
                                           // kept explicit so the pure function itself documents
                                           // and enforces the invariant, not just the caller
    std::uint32_t meaningfulAttunementPct,
    std::uint32_t currentProtectedCount,
    std::uint32_t maxProtectedItems);

// Called from the sell-veto hook, only for items the caller has already confirmed are tracked
// as protected for this bot (an item not tracked at all never reaches this function - the
// caller returns DEFAULT_PLAYERBOTS_DISPOSITION directly in that case without calling this).
EchoesDispositionDecision EvaluateSellVeto(
    bool stateAvailable,
    bool isQuestItem,                     // defensive: never protect a quest item through this path
                                           // either, even if it were somehow tracked
    bool bagPressureCritical,             // free bag slots <= configured reserve
    bool isLeastValuedProtectedUnderPressure); // under pressure: is this the item to release first?

#endif
