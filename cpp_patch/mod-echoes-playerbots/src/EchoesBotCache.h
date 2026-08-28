#ifndef MODULE_ECHOES_PLAYERBOTS_BOTCACHE_H
#define MODULE_ECHOES_PLAYERBOTS_BOTCACHE_H

#include "EchoesPlayerbotsCommon.h"
#include <optional>
#include <unordered_map>
#include <mutex>

// Minimal read-only attunement snapshot for one (bot guid, item entry) pair.
// Mirrors exactly the ap_item_attune columns this module needs, plus the
// item's real per-item attunement cap.
//
// E2i8-R1 correction: `cap` is NOT a flat constant. Echoes' own cap formula
// (AP.GetScaledCap in ap_core.lua) is a level-scaled quadratic curve -
// cap = max(100, floor(CapPerItem * (RequiredLevel/80)^2)) - so a flat
// CapPerItem (10000) badly overestimates the true cap for any item with
// RequiredLevel below 80, which in turn underestimates PercentAttuned() for
// exactly those items. This struct's `cap` field is now always populated
// from EchoesActionBridge::GetAttunementCap(), which delegates to Echoes'
// own formula (never duplicated in C++) - see EchoesBotCache.cpp. The
// default value below is never actually returned to a caller: EchoesBotCache
// ::Get() returns std::nullopt (cache genuinely unavailable) rather than an
// EchoesAttuneInfo with a guessed cap, so this default only matters for
// local construction before the real value is assigned.
struct EchoesAttuneInfo
{
    uint32 progress = 0;
    uint32 cap = 10000;
    bool fullyAttuned = false;

    uint32 PercentAttuned() const
    {
        if (cap == 0)
            return 0;
        uint64 pct = (static_cast<uint64>(progress) * 100) / cap;
        return pct > 100 ? 100 : static_cast<uint32>(pct);
    }
};

// Per-bot, per-item lazy read cache. Layer 1 is read-only with respect to
// Echoes state (per E2i1 Stage 7) - this cache never writes ap_* tables.
// Populated lazily on first decision need, never at login, never per-tick.
// A short TTL (not event-driven invalidation on Echoes' own writes, which
// would require a Lua-side hook this phase does not add) keeps entries
// bounded-fresh without adding query volume proportional to bot count.
class EchoesBotCache
{
public:
    static EchoesBotCache* instance()
    {
        static EchoesBotCache inst;
        return &inst;
    }

    // Returns cached or freshly-queried attunement info for (botGuid,
    // itemEntry). Returns std::nullopt only on a genuine DB read failure -
    // callers must treat nullopt as "cache unavailable" and fall back to
    // default Playerbots behavior (never block on this).
    std::optional<EchoesAttuneInfo> Get(uint32 botGuidLow, uint32 itemEntry, uint32 nowSeconds);

    // Called on PLAYERHOOK_ON_LOGOUT. Drops all cached entries for this
    // bot - never carry stale state across sessions.
    void InvalidateBot(uint32 botGuidLow);

    // Called on WorldScript::OnShutdown(). Drops everything.
    void Clear();

    // Aggregate instrumentation only - no player data, no inventory
    // contents.
    uint32 GetLoadCount() const { return loadCount; }
    uint32 GetHitCount() const { return hitCount; }
    uint32 GetMissCount() const { return missCount; }
    uint32 GetErrorCount() const { return errorCount; }

private:
    EchoesBotCache() = default;

    struct Entry
    {
        EchoesAttuneInfo info;
        uint32 loadedAtSeconds = 0;
    };

    static constexpr uint32 TTL_SECONDS = 60;

    std::mutex mutex_;
    std::unordered_map<uint64, Entry> cache_; // key = (botGuidLow << 32) | itemEntry

    uint32 loadCount = 0;
    uint32 hitCount = 0;
    uint32 missCount = 0;
    uint32 errorCount = 0;

    static uint64 MakeKey(uint32 botGuidLow, uint32 itemEntry)
    {
        return (static_cast<uint64>(botGuidLow) << 32) | itemEntry;
    }
};

#endif
