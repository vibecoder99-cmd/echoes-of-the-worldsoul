#include "EchoesBotCache.h"
#include "EchoesActionBridge.h"
#include "DatabaseEnv.h"
#include "QueryResult.h"

std::optional<EchoesAttuneInfo> EchoesBotCache::Get(uint32 botGuidLow, uint32 itemEntry, uint32 nowSeconds)
{
    uint64 key = MakeKey(botGuidLow, itemEntry);

    {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = cache_.find(key);
        if (it != cache_.end() && (nowSeconds - it->second.loadedAtSeconds) < TTL_SECONDS)
        {
            ++hitCount;
            return it->second.info;
        }
    }

    ++missCount;
    ++loadCount;

    // Single indexed primary-key lookup (guid, item_entry) - not a scan,
    // not per-tick, fired only from the equip-decision event path.
    QueryResult result = CharacterDatabase.Query(
        "SELECT progress, attuned FROM ap_item_attune WHERE guid = {} AND item_entry = {} LIMIT 1",
        botGuidLow, itemEntry);

    EchoesAttuneInfo info; // defaults: progress 0, not attuned - safe "no investment" default
    if (result)
    {
        Field* fields = result->Fetch();
        info.progress = fields[0].Get<uint32>();
        info.fullyAttuned = fields[1].Get<uint32>() != 0;
    }
    // No row is a normal, expected case (item never attuned) - not an error.

    // E2i8-R1 correction: the real per-item cap is a level-scaled quadratic
    // formula owned by Echoes (AP.GetScaledCap in ap_core.lua), never a flat
    // constant - see EchoesBotCache.h's struct comment for why. This module
    // must never guess or duplicate that formula in C++, so it is fetched
    // through the same whitelisted Lua bridge every other Echoes-owned value
    // already goes through. If the cap genuinely cannot be determined (Echoes/
    // ALE unreachable, or a malformed/zero result), this is treated exactly
    // like any other DB read failure: Get() fails closed by returning
    // std::nullopt rather than substituting a guessed cap, so every existing
    // caller's already-tested "cache unavailable -> defer to default
    // Playerbots behavior" fallback (EvaluateAwareness's
    // FALLBACK_STATE_UNAVAILABLE, EvaluateProtectionCandidate's own
    // stateAvailable=false path) applies unchanged - no new fallback
    // behavior was invented for this fix.
    std::optional<uint32> cap = EchoesActionBridge::instance()->GetAttunementCap(itemEntry);
    if (!cap.has_value())
    {
        ++errorCount;
        return std::nullopt;
    }
    info.cap = *cap;

    {
        std::lock_guard<std::mutex> lock(mutex_);
        cache_[key] = Entry{info, nowSeconds};
    }

    return info;
}

void EchoesBotCache::InvalidateBot(uint32 botGuidLow)
{
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto it = cache_.begin(); it != cache_.end();)
    {
        uint32 keyGuid = static_cast<uint32>(it->first >> 32);
        if (keyGuid == botGuidLow)
            it = cache_.erase(it);
        else
            ++it;
    }
}

void EchoesBotCache::Clear()
{
    std::lock_guard<std::mutex> lock(mutex_);
    cache_.clear();
}
