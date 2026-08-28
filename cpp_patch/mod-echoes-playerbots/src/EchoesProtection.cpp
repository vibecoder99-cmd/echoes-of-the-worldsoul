#include "EchoesProtection.h"
#include <algorithm>

void EchoesProtectionTracker::Protect(uint32 botGuidLow, ObjectGuid itemGuid, uint32 attunementPct, uint8 priorSlot, uint32 nowSeconds)
{
    std::lock_guard<std::mutex> lock(mutex_);
    auto& list = perBot_[botGuidLow];

    // Idempotent: re-protecting an already-tracked item just refreshes its timestamp, never
    // duplicates the entry.
    for (auto& entry : list)
    {
        if (entry.itemGuid == itemGuid)
        {
            entry.attunementPct = attunementPct;
            entry.recordedAtSeconds = nowSeconds;
            return;
        }
    }

    list.push_back(EchoesProtectedItemEntry{itemGuid, attunementPct, priorSlot, nowSeconds});
}

bool EchoesProtectionTracker::IsProtected(uint32 botGuidLow, ObjectGuid itemGuid, uint32& outAttunementPct) const
{
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = perBot_.find(botGuidLow);
    if (it == perBot_.end())
        return false;

    for (auto const& entry : it->second)
    {
        if (entry.itemGuid == itemGuid)
        {
            outAttunementPct = entry.attunementPct;
            return true;
        }
    }
    return false;
}

bool EchoesProtectionTracker::IsLeastValued(uint32 botGuidLow, ObjectGuid itemGuid) const
{
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = perBot_.find(botGuidLow);
    if (it == perBot_.end() || it->second.empty())
        return false;

    auto minIt = std::min_element(it->second.begin(), it->second.end(),
        [](EchoesProtectedItemEntry const& a, EchoesProtectedItemEntry const& b)
        {
            return a.attunementPct < b.attunementPct;
        });

    return minIt->itemGuid == itemGuid;
}

void EchoesProtectionTracker::Release(uint32 botGuidLow, ObjectGuid itemGuid)
{
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = perBot_.find(botGuidLow);
    if (it == perBot_.end())
        return;

    auto& list = it->second;
    list.erase(std::remove_if(list.begin(), list.end(),
        [&itemGuid](EchoesProtectedItemEntry const& e) { return e.itemGuid == itemGuid; }),
        list.end());

    if (list.empty())
        perBot_.erase(it);
}

void EchoesProtectionTracker::ReleaseAllForBot(uint32 botGuidLow)
{
    std::lock_guard<std::mutex> lock(mutex_);
    perBot_.erase(botGuidLow);
}

void EchoesProtectionTracker::Clear()
{
    std::lock_guard<std::mutex> lock(mutex_);
    perBot_.clear();
}

uint32 EchoesProtectionTracker::CountForBot(uint32 botGuidLow) const
{
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = perBot_.find(botGuidLow);
    return it == perBot_.end() ? 0 : static_cast<uint32>(it->second.size());
}
