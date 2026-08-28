#ifndef MODULE_ECHOES_PLAYERBOTS_PROTECTION_H
#define MODULE_ECHOES_PLAYERBOTS_PROTECTION_H

#include "EchoesPlayerbotsCommon.h"
#include "ObjectGuid.h"
#include <mutex>
#include <unordered_map>
#include <vector>

// Layer 2 (E2i4 prototype) process-local protection tracker.
//
// Deliberately NOT a database cache - unlike EchoesBotCache (which caches reads of Echoes'
// own ap_item_attune table), this class tracks a purely in-memory bookkeeping decision this
// module itself makes ("this bot is currently choosing to keep this item in its bags").
// Nothing here is persisted to any Echoes table, per E2i4 Stage 6's explicit requirement.
//
// Bounded by design: at most EchoesConfig::layer2MaxProtectedItemsPerBot entries per bot,
// enforced by the caller via EvaluateProtectionCandidate before ever calling TryProtect.
struct EchoesProtectedItemEntry
{
    ObjectGuid itemGuid;
    uint32 attunementPct = 0;
    uint8 priorSlot = 0;
    uint32 recordedAtSeconds = 0;
};

class EchoesProtectionTracker
{
public:
    static EchoesProtectionTracker* instance()
    {
        static EchoesProtectionTracker inst;
        return &inst;
    }

    // Caller must have already confirmed count < maxProtectedItems via
    // EvaluateProtectionCandidate before calling this - this function does not itself enforce
    // the limit, it only records.
    void Protect(uint32 botGuidLow, ObjectGuid itemGuid, uint32 attunementPct, uint8 priorSlot, uint32 nowSeconds);

    // Returns true and fills attunementPct if the given item is currently tracked as protected
    // for this bot. Also structurally guarantees "never protect an item whose instance GUID
    // does not match current inventory": if the caller only ever queries with a live Item*'s
    // real ObjectGuid (as the sell hook does), a positive match is definitionally current -
    // there is no way for this tracker to hold a stale GUID a bot's inventory no longer has,
    // because entries are only ever added from a live Item* at protection time.
    bool IsProtected(uint32 botGuidLow, ObjectGuid itemGuid, uint32& outAttunementPct) const;

    // True if itemGuid is the lowest-attunementPct entry among this bot's currently protected
    // items - used to implement "release the least valuable first" bag-pressure ordering.
    bool IsLeastValued(uint32 botGuidLow, ObjectGuid itemGuid) const;

    void Release(uint32 botGuidLow, ObjectGuid itemGuid);
    void ReleaseAllForBot(uint32 botGuidLow); // logout cleanup
    void Clear();                             // shutdown / disable / version-change cleanup

    uint32 CountForBot(uint32 botGuidLow) const;

private:
    EchoesProtectionTracker() = default;

    mutable std::mutex mutex_;
    std::unordered_map<uint32, std::vector<EchoesProtectedItemEntry>> perBot_;
};

#endif
