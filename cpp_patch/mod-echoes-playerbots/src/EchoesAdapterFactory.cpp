#include "EchoesAdapterFactory.h"

void EchoesAdapterFactory::Register(std::unique_ptr<IEchoesActionAdapter> adapter)
{
    adapters_.push_back(std::move(adapter));
}

IEchoesActionAdapter* EchoesAdapterFactory::Get(std::string const& capabilityName) const
{
    for (auto const& a : adapters_)
        if (capabilityName == a->CapabilityName())
            return a.get();
    return nullptr;
}

std::vector<IEchoesActionAdapter*> EchoesAdapterFactory::GetAll() const
{
    std::vector<IEchoesActionAdapter*> result;
    result.reserve(adapters_.size());
    for (auto const& a : adapters_)
        result.push_back(a.get());
    return result;
}

bool EchoesAdapterFactory::TryAcquireLease(ObjectGuid itemGuid, uint32 nowSeconds, uint32 cooldownSeconds)
{
    std::lock_guard<std::mutex> lock(leaseMutex_);
    auto it = leaseExpiryByItem_.find(itemGuid);
    if (it != leaseExpiryByItem_.end() && it->second > nowSeconds)
        return false; // already leased by another adapter/evaluation

    leaseExpiryByItem_[itemGuid] = nowSeconds + cooldownSeconds;
    return true;
}

void EchoesAdapterFactory::ReleaseLease(ObjectGuid itemGuid)
{
    std::lock_guard<std::mutex> lock(leaseMutex_);
    leaseExpiryByItem_.erase(itemGuid);
}

void EchoesAdapterFactory::ClearLeases()
{
    std::lock_guard<std::mutex> lock(leaseMutex_);
    leaseExpiryByItem_.clear();
}
