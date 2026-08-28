#ifndef MODULE_ECHOES_PLAYERBOTS_AWARENESS_H
#define MODULE_ECHOES_PLAYERBOTS_AWARENESS_H

// Deliberately dependency-free (standard <cstdint> only, no Common.h/no
// AzerothCore headers) so this file - the entire Layer 1 decision policy -
// can be compiled and unit-tested completely standalone, outside the full
// worldserver build. See tests/EchoesAwarenessTests.cpp.
#include <cstdint>

// Layer 1 decision outcomes, exactly as specified in the E2i2 authorization
// (Stage 7). No other outcomes exist at this layer.
enum class EchoesAwarenessDecision : std::uint8_t
{
    DEFAULT_PLAYERBOTS_DECISION = 0, // Echoes had no opinion; defer entirely.
    KEEP_ATTUNED_ITEM = 1,           // Veto the equip: current gear is meaningfully attuned, candidate is only marginal.
    ACCEPT_CLEAR_UPGRADE = 2,        // Allow the equip: candidate is a clear upgrade regardless of attunement.
    FALLBACK_STATE_UNAVAILABLE = 3   // Cache/DB/integration state unavailable - always defer to default Playerbots behavior.
};

char const* EchoesAwarenessDecisionToString(EchoesAwarenessDecision d);

// Pure function, no DB/game engine dependency - deterministic and directly
// unit-testable (E2i2 Stage 9). This is the *entire* Layer 1 policy; it
// deliberately does not know about Rack/Forge/Dissolve/vendor economics,
// bag pressure, or role/spec beyond what is already folded into the two
// input scores (which come from Playerbots' own StatsWeightCalculator,
// reusing its existing scoring rather than inventing a new one, per the
// E2i1 design's explicit instruction).
//
// currentItemScore / candidateItemScore: Playerbots' own item scores for
//   the currently-equipped item and the candidate replacement (0 if the
//   slot is currently empty - in which case this function always allows
//   the equip, since there is nothing to protect).
// attunementPct: 0-100, current item's attunement percent (0 if unknown or
//   never attuned).
// fullyAttuned: true if the current item's Echoes attunement is complete.
// meaningfulAttunementPct / clearUpgradeMarginPct: EchoesConfig thresholds.
// stateAvailable: false if the presence handshake is not ACTIVE, or the
//   cache lookup failed - forces FALLBACK_STATE_UNAVAILABLE regardless of
//   every other input, per the "fail dormant" contract.
EchoesAwarenessDecision EvaluateAwareness(
    bool stateAvailable,
    float currentItemScore,
    float candidateItemScore,
    std::uint32_t attunementPct,
    bool fullyAttuned,
    std::uint32_t meaningfulAttunementPct,
    std::uint32_t clearUpgradeMarginPct);

#endif
