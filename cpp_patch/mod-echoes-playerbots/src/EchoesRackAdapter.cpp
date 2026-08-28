#include "EchoesRackAdapter.h"
#include "EchoesActionBridge.h"
#include "EchoesConfig.h"
#include "Item.h"
#include "ItemTemplate.h"
#include "Player.h"

bool EchoesRackAdapter::IsEligible(EchoesAdapterContext const& ctx) const
{
    if (!IsEnabled())
        return false;
    if (!ctx.item)
        return false;

    ItemTemplate const* proto = ctx.item->GetTemplate();
    if (!proto)
        return false;

    // Mirrors AP.Rack.AddItem's own exploit guard (weapons/armor with a valid
    // equip slot only) - a cheap local pre-check so Evaluate() is only
    // reached for genuinely plausible candidates, never a Lua round-trip for
    // consumables/quest items/reagents.
    if (!((proto->Class == ITEM_CLASS_WEAPON || proto->Class == ITEM_CLASS_ARMOR) && proto->InventoryType > 0))
        return false;

    return true;
}

EchoesBotAction::Result EchoesRackAdapter::Evaluate(EchoesAdapterContext const& ctx)
{
    ++evaluations;

    EchoesBotAction::Request req;
    req.actionType = EchoesBotAction::ActionType::RACK_STORE;
    req.itemEntry = ctx.item->GetTemplate()->ItemId;
    req.dryRun = true;

    EchoesBotAction::Result result;
    if (!EchoesActionBridge::instance()->ValidateBotAction(ctx.player, req, result))
    {
        result.resultCode = EchoesBotAction::ResultCode::BRIDGE_UNAVAILABLE;
    }
    return result;
}

void EchoesRackAdapter::InterpretResult(EchoesBotAction::Result const& result)
{
    if (result.resultCode != EchoesBotAction::ResultCode::SUCCESS)
        ++rejections;
}

void EchoesRackAdapter::UpdateBotState(EchoesAdapterContext const& /*ctx*/, EchoesBotAction::Result const& /*result*/)
{
    // No separate local bot-state to update for Rack in this prototype - the
    // Rack's own Lua-side cache (AP.Rack.Cache) is already the single source
    // of truth, and this module keeps no shadow copy of it.
}

void EchoesRackAdapter::Fallback(EchoesAdapterContext const& /*ctx*/)
{
    // Declining Rack storage leaves the item as ordinary bag inventory -
    // exactly Layer 2's own KEEP_IN_BAG behavior, never worse than doing
    // nothing.
}

bool EchoesRackAdapter::IsEnabled() const
{
    return EchoesConfig::instance()->bridgeEnabled && EchoesConfig::instance()->rackEnabled;
}

EchoesBotAction::Result EchoesRackAdapter::Store(EchoesAdapterContext const& ctx, std::string const& idempotencyToken)
{
    EchoesBotAction::Request req;
    req.actionType = EchoesBotAction::ActionType::RACK_STORE;
    req.itemEntry = ctx.item->GetTemplate()->ItemId;
    req.idempotencyToken = idempotencyToken;
    req.dryRun = false;

    EchoesBotAction::Result result;
    if (!EchoesActionBridge::instance()->ExecuteBotAction(ctx.player, req, result))
    {
        result.resultCode = EchoesBotAction::ResultCode::BRIDGE_UNAVAILABLE;
        return result;
    }

    if (result.resultCode == EchoesBotAction::ResultCode::SUCCESS)
        ++storesSucceeded;
    else
        ++rejections;

    return result;
}

EchoesBotAction::Result EchoesRackAdapter::Retrieve(EchoesAdapterContext const& ctx, std::string const& idempotencyToken)
{
    EchoesBotAction::Request req;
    req.actionType = EchoesBotAction::ActionType::RACK_RETRIEVE;
    req.itemEntry = ctx.item->GetTemplate()->ItemId;
    req.idempotencyToken = idempotencyToken;
    req.dryRun = false;

    EchoesBotAction::Result result;
    if (!EchoesActionBridge::instance()->ExecuteBotAction(ctx.player, req, result))
    {
        result.resultCode = EchoesBotAction::ResultCode::BRIDGE_UNAVAILABLE;
        return result;
    }

    if (result.resultCode == EchoesBotAction::ResultCode::SUCCESS)
        ++retrievesSucceeded;
    else
        ++rejections;

    return result;
}
