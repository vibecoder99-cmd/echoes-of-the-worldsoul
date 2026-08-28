#ifndef MODULE_ECHOES_PLAYERBOTS_BOT_ACTION_TYPES_H
#define MODULE_ECHOES_PLAYERBOTS_BOT_ACTION_TYPES_H

#include <cstdint>
#include <string>

// E2i6/E2i8: shared, dependency-free request/result protocol for the
// Echoes-owned action bridge (Rack/Dissolution). Deliberately has zero
// AzerothCore/Playerbots/Lua dependency (mirrors EchoesAwareness.h/
// EchoesDisposition.h's own pattern) so the adapter decision logic that
// consumes these types remains standalone-testable.
//
// E2i8 naming correction: "Legacy Forge" IS Echoes' Dissolution system
// (confirmed against ap_forge.lua's own header comment and ap_ui.lua's own
// "LEGACY FORGE" UI section label - see env/backups/e2i8/.../source-audit/).
// There is no separate upgrade/crafting Forge mechanic. The DISSOLVE enum
// value (unchanged since E2i6, never renumbered) is now the single action
// both "DISSOLUTION" and the legacy "LEGACY_FORGE" wire strings resolve to.

namespace EchoesBotAction
{
    constexpr std::uint32_t kProtocolVersion = 1;

    enum class ActionType : std::uint8_t
    {
        RACK_STORE = 0,
        RACK_RETRIEVE = 1,
        DISSOLVE = 2,   // wire name "DISSOLUTION"; "LEGACY_FORGE" is an accepted alias, same value
        FORGE = 3       // reserved, permanently unavailable - there is no separate upgrade/crafting
                        // Forge; use DISSOLVE for the real Legacy Forge/Dissolution system
    };

    // Canonical string is "DISSOLUTION" for ActionType::DISSOLVE. Retained for
    // logging/telemetry; wire parsing (ActionTypeFromString) is the
    // permissive/alias-accepting direction.
    char const* ActionTypeToString(ActionType t);

    // Accepts "DISSOLUTION" (canonical), "LEGACY_FORGE" (alias), and the
    // original E2i6/E2i7 "DISSOLVE" (backward compatibility) - all three
    // resolve to ActionType::DISSOLVE. Unrecognized strings resolve to
    // ActionType::FORGE (the permanently-unavailable placeholder), which
    // fails closed rather than silently mapping to an unintended action.
    ActionType ActionTypeFromString(std::string const& s);

    enum class ResultCode : std::uint8_t
    {
        SUCCESS = 0,
        REJECTED = 1,
        RETRYABLE = 2,
        STALE_STATE = 3,
        CAPABILITY_UNAVAILABLE = 4,
        VERSION_MISMATCH = 5,
        ITEM_NOT_FOUND = 6,
        NOT_OWNER = 7,
        INSUFFICIENT_RESOURCES = 8,
        BAG_SPACE_REQUIRED = 9,
        ALREADY_APPLIED = 10,
        INTERNAL_ERROR = 11,
        // Bridge-local codes that never cross the Lua boundary, added for a
        // caller who could not even reach Lua (disabled/absent/bridge-down).
        BRIDGE_UNAVAILABLE = 12
    };

    ResultCode ResultCodeFromString(std::string const& s);
    char const* ResultCodeToString(ResultCode c);

    // Request fields: only what is required. No cost/reward/formula field is
    // ever supplied by the caller - Echoes Lua computes and returns those
    // authoritatively in the result.
    struct Request
    {
        std::uint32_t protocolVersion = kProtocolVersion;
        ActionType actionType = ActionType::RACK_STORE;
        std::uint32_t botGuidLow = 0;
        std::uint32_t accountId = 0;
        std::uint32_t itemEntry = 0;
        std::uint64_t itemGuidRaw = 0; // full ObjectGuid raw value of the item instance (E2i8: used
                                        // by Dissolution's stale/missing-item checks; 0 = unset)
        std::string idempotencyToken;
        bool dryRun = true;
    };

    // Result fields: bounded, action-specific, never secrets/arbitrary SQL.
    struct Result
    {
        ResultCode resultCode = ResultCode::INTERNAL_ERROR;
        std::int64_t authoritativeCost = 0;
        std::int64_t authoritativeReward = 0;
        std::string destinationRef;
        std::string stateVersionAfter;
        std::string reasonCode;
    };
}

#endif
