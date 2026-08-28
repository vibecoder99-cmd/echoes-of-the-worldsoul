// E2i6/E2i8 - standalone deterministic tests for the dependency-free
// portion of the bridge (EchoesBotActionTypes.h/.cpp). Zero AzerothCore/Lua
// dependency, mirroring EchoesAwarenessTests.cpp/EchoesDispositionTests.cpp's
// own pattern.
//
// The bridge/adapter/hook logic itself (EchoesActionBridge, EchoesRackAdapter,
// EchoesDissolutionAdapter, EchoesForgeAdapter, the combined-priority wiring in
// EchoesHooks.cpp) cannot be compiled standalone - it requires ALE's
// LuaEngine.h and AzerothCore's Player/Item/ObjectGuid types, none of which
// are available outside the full CMake build. That logic is instead verified
// structurally (code inspection, documented per-adapter in the closure
// report) and at runtime (Stages 15-17 live candidate tests) - exactly the
// same split already established for Layer 1/2's own hook-level cases.
//
// E2i8 naming correction: ActionTypeToString(ActionType::DISSOLVE) now
// returns "DISSOLUTION" (was "DISSOLVE" in E2i6/E2i7) - see
// env/backups/e2i8/.../source-audit/ for why "Legacy Forge IS Dissolution"
// made the old string ambiguous. ActionTypeFromString is the new, permissive,
// alias-accepting direction added in E2i8.

#include "EchoesBotActionTypes.h"
#include <cstdio>
#include <cstring>

static int g_pass = 0;
static int g_fail = 0;

static void CheckStr(char const* name, char const* actual, char const* expected)
{
    bool ok = std::strcmp(actual, expected) == 0;
    if (ok) ++g_pass; else ++g_fail;
    std::printf("%s: %-60s -> %s\n", ok ? "PASS" : "FAIL", name, actual);
}

static void CheckResultCode(char const* name, EchoesBotAction::ResultCode actual, EchoesBotAction::ResultCode expected)
{
    bool ok = actual == expected;
    if (ok) ++g_pass; else ++g_fail;
    std::printf("%s: %-60s -> %s\n", ok ? "PASS" : "FAIL", name, EchoesBotAction::ResultCodeToString(actual));
}

static void CheckActionType(char const* name, EchoesBotAction::ActionType actual, EchoesBotAction::ActionType expected)
{
    bool ok = actual == expected;
    if (ok) ++g_pass; else ++g_fail;
    std::printf("%s: %-60s -> %s\n", ok ? "PASS" : "FAIL", name, EchoesBotAction::ActionTypeToString(actual));
}

int main()
{
    using namespace EchoesBotAction;

    // 1. ActionType round-trip strings (used verbatim as the Lua request's actionType field)
    CheckStr("1_action_type_rack_store", ActionTypeToString(ActionType::RACK_STORE), "RACK_STORE");
    CheckStr("2_action_type_rack_retrieve", ActionTypeToString(ActionType::RACK_RETRIEVE), "RACK_RETRIEVE");
    // E2i8 naming correction: canonical wire string is now "DISSOLUTION",
    // not "DISSOLVE" - the enum value ActionType::DISSOLVE itself is
    // unchanged/unrenumbered (Stage 3's explicit "never renumber" requirement).
    CheckStr("3_action_type_dissolve_canonical_string", ActionTypeToString(ActionType::DISSOLVE), "DISSOLUTION");
    CheckStr("4_action_type_forge", ActionTypeToString(ActionType::FORGE), "FORGE");

    // 1b. ActionTypeFromString (E2i8, new): permissive/alias-accepting parse
    // direction. All three wire strings for Dissolution resolve to the same
    // ActionType::DISSOLVE value - "Legacy Forge" is never a second
    // implementation, just an accepted alias of the one real capability.
    CheckActionType("1b_1_from_string_dissolution_canonical", ActionTypeFromString("DISSOLUTION"), ActionType::DISSOLVE);
    CheckActionType("1b_2_from_string_legacy_forge_alias", ActionTypeFromString("LEGACY_FORGE"), ActionType::DISSOLVE);
    CheckActionType("1b_3_from_string_dissolve_back_compat", ActionTypeFromString("DISSOLVE"), ActionType::DISSOLVE);
    CheckActionType("1b_4_from_string_rack_store", ActionTypeFromString("RACK_STORE"), ActionType::RACK_STORE);
    CheckActionType("1b_5_from_string_rack_retrieve", ActionTypeFromString("RACK_RETRIEVE"), ActionType::RACK_RETRIEVE);
    // Unrecognized strings fail closed to FORGE (permanently-unavailable
    // placeholder) rather than silently mapping to an unintended real action.
    CheckActionType("1b_6_from_string_unknown_fails_closed_to_forge", ActionTypeFromString("something_unexpected"), ActionType::FORGE);
    CheckActionType("1b_7_from_string_empty_fails_closed_to_forge", ActionTypeFromString(""), ActionType::FORGE);
    CheckActionType("1b_8_from_string_forge_itself", ActionTypeFromString("FORGE"), ActionType::FORGE);

    // 2. Every ResultCode Stage 4 requires is representable and round-trips through the string form
    // the Lua side actually returns.
    CheckResultCode("5_result_success", ResultCodeFromString("SUCCESS"), ResultCode::SUCCESS);
    CheckResultCode("6_result_rejected", ResultCodeFromString("REJECTED"), ResultCode::REJECTED);
    CheckResultCode("7_result_retryable", ResultCodeFromString("RETRYABLE"), ResultCode::RETRYABLE);
    CheckResultCode("8_result_stale_state", ResultCodeFromString("STALE_STATE"), ResultCode::STALE_STATE);
    CheckResultCode("9_result_capability_unavailable", ResultCodeFromString("CAPABILITY_UNAVAILABLE"), ResultCode::CAPABILITY_UNAVAILABLE);
    CheckResultCode("10_result_version_mismatch", ResultCodeFromString("VERSION_MISMATCH"), ResultCode::VERSION_MISMATCH);
    CheckResultCode("11_result_item_not_found", ResultCodeFromString("ITEM_NOT_FOUND"), ResultCode::ITEM_NOT_FOUND);
    CheckResultCode("12_result_not_owner", ResultCodeFromString("NOT_OWNER"), ResultCode::NOT_OWNER);
    CheckResultCode("13_result_insufficient_resources", ResultCodeFromString("INSUFFICIENT_RESOURCES"), ResultCode::INSUFFICIENT_RESOURCES);
    CheckResultCode("14_result_bag_space_required", ResultCodeFromString("BAG_SPACE_REQUIRED"), ResultCode::BAG_SPACE_REQUIRED);
    CheckResultCode("15_result_already_applied", ResultCodeFromString("ALREADY_APPLIED"), ResultCode::ALREADY_APPLIED);
    CheckResultCode("16_result_internal_error", ResultCodeFromString("INTERNAL_ERROR"), ResultCode::INTERNAL_ERROR);

    // 3. Unknown/malformed strings fail closed to INTERNAL_ERROR, never crash, never silently
    // default to SUCCESS.
    CheckResultCode("17_unknown_string_fails_closed", ResultCodeFromString("something_unexpected"), ResultCode::INTERNAL_ERROR);
    CheckResultCode("18_empty_string_fails_closed", ResultCodeFromString(""), ResultCode::INTERNAL_ERROR);

    // 4. Default-constructed Request is dry-run by default (fail-safe default: a caller who
    // forgets to set dryRun explicitly can never accidentally trigger a real mutation).
    Request defaultReq;
    bool dryRunDefaultsTrue = defaultReq.dryRun == true;
    if (dryRunDefaultsTrue) ++g_pass; else ++g_fail;
    std::printf("%s: %-60s -> dryRun=%s\n", dryRunDefaultsTrue ? "PASS" : "FAIL",
                "19_request_dry_run_defaults_true", defaultReq.dryRun ? "true" : "false");

    // 5. Protocol version is a fixed, non-zero constant (used for the version-mismatch check).
    bool versionNonZero = kProtocolVersion > 0;
    if (versionNonZero) ++g_pass; else ++g_fail;
    std::printf("%s: %-60s -> %u\n", versionNonZero ? "PASS" : "FAIL", "20_protocol_version_nonzero", kProtocolVersion);

    std::printf("\n%d/%d tests passed.\n", g_pass, g_pass + g_fail);
    if (g_fail == 0)
        std::printf("ALL TESTS PASSED\n");
    return g_fail == 0 ? 0 : 1;
}
