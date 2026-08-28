#ifndef MODULE_ECHOES_PLAYERBOTS_PRESENCE_H
#define MODULE_ECHOES_PLAYERBOTS_PRESENCE_H

#include "EchoesPlayerbotsCommon.h"
#include <atomic>
#include <string>

// Presence/capability handshake state machine, per the E2i1 design
// (env/backups/e2i1/.../selected-design/e2i1-full-design.md, Stage 6).
//
// Table existence alone is never treated as proof of an active Echoes
// runtime - uninstall may intentionally preserve player data. See the
// honest limitation documented on EchoesPresence::Recheck(): this module
// cannot observe Echoes' own in-Lua runtime-ready flag without a dedicated
// bridge, which was assessed unnecessary for Layer 1 because this module's
// own hooks cannot fire before the world (and therefore ALE/Echoes Lua) has
// finished initializing.
enum class EchoesPresenceState : uint8
{
    DISABLED = 0,
    ECHOES_ABSENT = 1,
    SCHEMA_ABSENT = 2,
    VERSION_INCOMPATIBLE = 3,
    RUNTIME_NOT_READY = 4,
    ACTIVE = 5,
    DEGRADED = 6,
    SHUTTING_DOWN = 7
};

char const* EchoesPresenceStateToString(EchoesPresenceState state);

// One process-local, global cached state. Never per-bot. Never queried
// per-tick. Only re-evaluated at startup and on the bounded, low-frequency
// global timer (EchoesConfig::presenceRecheckMinutes) while ACTIVE/DEGRADED.
class EchoesPresence
{
public:
    static EchoesPresence* instance()
    {
        static EchoesPresence inst;
        return &inst;
    }

    // Called once from WorldScript::OnStartup(), after config is loaded.
    void InitialCheck();

    // Called from the bounded low-frequency global update path only
    // (never per-bot, never per-tick). Safe to call cheaply/often - it
    // internally rate-limits itself to EchoesConfig::presenceRecheckMinutes.
    void MaybeRecheck(uint32 nowSeconds);

    // Called once from WorldScript::OnShutdown().
    void BeginShutdown();

    EchoesPresenceState GetState() const { return state.load(std::memory_order_relaxed); }

    bool IsActiveOrDegraded() const
    {
        EchoesPresenceState s = GetState();
        return s == EchoesPresenceState::ACTIVE || s == EchoesPresenceState::DEGRADED;
    }

    // Total number of handshake DB checks ever performed (startup + bounded
    // rechecks only). Instrumentation counter, not player data.
    uint32 GetHandshakeCheckCount() const { return handshakeCheckCount.load(std::memory_order_relaxed); }

private:
    EchoesPresence() = default;

    // Performs the actual metadata-only checks (mirrors ap04_db.lua's own
    // proven pattern: existence/version checks only, never runtime DDL).
    // Sets `state` and logs a transition exactly once per change.
    void RunHandshake();
    void SetState(EchoesPresenceState newState);

    std::atomic<EchoesPresenceState> state{EchoesPresenceState::DISABLED};
    std::atomic<uint32> handshakeCheckCount{0};
    std::atomic<uint32> lastRecheckSeconds{0};
};

#endif
