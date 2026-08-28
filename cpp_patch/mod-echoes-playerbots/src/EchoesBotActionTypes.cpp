#include "EchoesBotActionTypes.h"

namespace EchoesBotAction
{
    char const* ActionTypeToString(ActionType t)
    {
        switch (t)
        {
            case ActionType::RACK_STORE: return "RACK_STORE";
            case ActionType::RACK_RETRIEVE: return "RACK_RETRIEVE";
            case ActionType::DISSOLVE: return "DISSOLUTION"; // canonical wire name (E2i8)
            case ActionType::FORGE: return "FORGE";
        }
        return "UNKNOWN";
    }

    ActionType ActionTypeFromString(std::string const& s)
    {
        if (s == "RACK_STORE") return ActionType::RACK_STORE;
        if (s == "RACK_RETRIEVE") return ActionType::RACK_RETRIEVE;
        // "DISSOLUTION" (canonical), "LEGACY_FORGE" (alias), "DISSOLVE" (E2i6/E2i7
        // backward compatibility) all resolve to the same, single Dissolution action.
        if (s == "DISSOLUTION" || s == "LEGACY_FORGE" || s == "DISSOLVE") return ActionType::DISSOLVE;
        if (s == "FORGE") return ActionType::FORGE;
        return ActionType::FORGE; // unrecognized -> fails closed to the permanently-unavailable placeholder
    }

    char const* ResultCodeToString(ResultCode c)
    {
        switch (c)
        {
            case ResultCode::SUCCESS: return "SUCCESS";
            case ResultCode::REJECTED: return "REJECTED";
            case ResultCode::RETRYABLE: return "RETRYABLE";
            case ResultCode::STALE_STATE: return "STALE_STATE";
            case ResultCode::CAPABILITY_UNAVAILABLE: return "CAPABILITY_UNAVAILABLE";
            case ResultCode::VERSION_MISMATCH: return "VERSION_MISMATCH";
            case ResultCode::ITEM_NOT_FOUND: return "ITEM_NOT_FOUND";
            case ResultCode::NOT_OWNER: return "NOT_OWNER";
            case ResultCode::INSUFFICIENT_RESOURCES: return "INSUFFICIENT_RESOURCES";
            case ResultCode::BAG_SPACE_REQUIRED: return "BAG_SPACE_REQUIRED";
            case ResultCode::ALREADY_APPLIED: return "ALREADY_APPLIED";
            case ResultCode::INTERNAL_ERROR: return "INTERNAL_ERROR";
            case ResultCode::BRIDGE_UNAVAILABLE: return "BRIDGE_UNAVAILABLE";
        }
        return "UNKNOWN";
    }

    ResultCode ResultCodeFromString(std::string const& s)
    {
        if (s == "SUCCESS") return ResultCode::SUCCESS;
        if (s == "REJECTED") return ResultCode::REJECTED;
        if (s == "RETRYABLE") return ResultCode::RETRYABLE;
        if (s == "STALE_STATE") return ResultCode::STALE_STATE;
        if (s == "CAPABILITY_UNAVAILABLE") return ResultCode::CAPABILITY_UNAVAILABLE;
        if (s == "VERSION_MISMATCH") return ResultCode::VERSION_MISMATCH;
        if (s == "ITEM_NOT_FOUND") return ResultCode::ITEM_NOT_FOUND;
        if (s == "NOT_OWNER") return ResultCode::NOT_OWNER;
        if (s == "INSUFFICIENT_RESOURCES") return ResultCode::INSUFFICIENT_RESOURCES;
        if (s == "BAG_SPACE_REQUIRED") return ResultCode::BAG_SPACE_REQUIRED;
        if (s == "ALREADY_APPLIED") return ResultCode::ALREADY_APPLIED;
        return ResultCode::INTERNAL_ERROR;
    }
}
