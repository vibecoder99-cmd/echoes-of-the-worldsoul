#include "EchoesPresence.h"
#include "EchoesConfig.h"
#include "DatabaseEnv.h"
#include "QueryResult.h"
#include "Log.h"

char const* EchoesPresenceStateToString(EchoesPresenceState state)
{
    switch (state)
    {
        case EchoesPresenceState::DISABLED: return "DISABLED";
        case EchoesPresenceState::ECHOES_ABSENT: return "ECHOES_ABSENT";
        case EchoesPresenceState::SCHEMA_ABSENT: return "SCHEMA_ABSENT";
        case EchoesPresenceState::VERSION_INCOMPATIBLE: return "VERSION_INCOMPATIBLE";
        case EchoesPresenceState::RUNTIME_NOT_READY: return "RUNTIME_NOT_READY";
        case EchoesPresenceState::ACTIVE: return "ACTIVE";
        case EchoesPresenceState::DEGRADED: return "DEGRADED";
        case EchoesPresenceState::SHUTTING_DOWN: return "SHUTTING_DOWN";
    }
    return "UNKNOWN";
}

void EchoesPresence::SetState(EchoesPresenceState newState)
{
    EchoesPresenceState old = state.exchange(newState, std::memory_order_relaxed);
    if (old != newState)
    {
        LOG_INFO("module", "[{}] presence state {} -> {}",
                 ECHOES_PB_MODULE_STRING, EchoesPresenceStateToString(old), EchoesPresenceStateToString(newState));
    }
}

void EchoesPresence::InitialCheck()
{
    if (!EchoesConfig::instance()->enabled)
    {
        SetState(EchoesPresenceState::DISABLED);
        return;
    }

    // Config is enabled, but the handshake itself has not run yet - this is
    // the real, brief RUNTIME_NOT_READY window. Honest limitation (see
    // header): this module cannot observe Echoes' own in-Lua runtime-ready
    // flag directly. It only checks schema/version metadata, which is a
    // proven-safe, read-only, existence-gated pattern (mirrors Echoes' own
    // ap04_db.lua REQUIRED_TABLES check). Since this module's own hooks
    // (login/equip) cannot fire before the world is ready - and ALE/Echoes
    // Lua load during worldserver startup, strictly before world-ready -
    // this proxy is sufficient in practice for this module's actual
    // interception points, even though it is not a direct observation of
    // Echoes' internal Lua state.
    SetState(EchoesPresenceState::RUNTIME_NOT_READY);
    RunHandshake();
}

void EchoesPresence::MaybeRecheck(uint32 nowSeconds)
{
    if (!IsActiveOrDegraded())
        return;

    uint32 last = lastRecheckSeconds.load(std::memory_order_relaxed);
    uint32 intervalSeconds = EchoesConfig::instance()->presenceRecheckMinutes * 60;
    if (nowSeconds < last + intervalSeconds)
        return;

    // Single global recheck, not per-bot. CAS guard so overlapping calls
    // (e.g. from more than one caller) do not double-fire.
    if (lastRecheckSeconds.compare_exchange_strong(last, nowSeconds, std::memory_order_relaxed))
        RunHandshake();
}

void EchoesPresence::BeginShutdown()
{
    SetState(EchoesPresenceState::SHUTTING_DOWN);
}

void EchoesPresence::RunHandshake()
{
    handshakeCheckCount.fetch_add(1, std::memory_order_relaxed);

    // Metadata-only existence check - identical pattern/spirit to
    // ap04_db.lua's own REQUIRED_TABLES check. Never DDL, never a full
    // table scan, never per-bot.
    QueryResult tableCheck = CharacterDatabase.Query(
        "SELECT COUNT(*) FROM information_schema.tables "
        "WHERE table_schema = DATABASE() AND table_name = 'ap_schema_version'");

    if (!tableCheck || tableCheck->Fetch()[0].Get<uint32>() == 0)
    {
        SetState(EchoesPresenceState::ECHOES_ABSENT);
        return;
    }

    QueryResult versionRow = CharacterDatabase.Query("SELECT version FROM ap_schema_version LIMIT 1");
    if (!versionRow)
    {
        SetState(EchoesPresenceState::SCHEMA_ABSENT);
        return;
    }

    std::string version = versionRow->Fetch()[0].Get<std::string>();
    std::string const& prefix = EchoesConfig::instance()->compatibleVersionPrefix;
    if (version.rfind(prefix, 0) != 0) // version does not start with prefix
    {
        SetState(EchoesPresenceState::VERSION_INCOMPATIBLE);
        return;
    }

    SetState(EchoesPresenceState::ACTIVE);
}
