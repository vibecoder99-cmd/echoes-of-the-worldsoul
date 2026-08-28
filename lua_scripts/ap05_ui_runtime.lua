-- Copyright (C) 2025-2026 vibecoder99
-- Licensed under the GNU General Public License v3. See LICENSE.
-- ============================================================
-- ap05_ui_runtime.lua
-- Echoes of the Worldsoul — UI Gossip Wrappers
--
-- Adds AP.UI.* primitive wrappers for the four gossip calls.
-- Page content and menu logic remain in ap_ui.lua.
--
-- IMPORTANT: Uses AP.UI = AP.UI or {} — never replaces the
-- existing table. ap_ui.lua (which loads after this file) adds
-- its page functions to the same AP.UI table; they coexist.
--
-- ap_ui.lua currently uses local gossip functions (GossipReset,
-- GossipAdd, GossipSend). Phase B migration will replace those
-- locals with calls to AP.UI.*. Until then, this file is
-- additive only — no existing behavior is changed.
--
-- Gossip pattern note:
--   player:GossipSendMenu(npcText, player, sender)
--   The player object is passed as the NPC argument. This is the
--   confirmed working non-NPC gossip pattern for this Eluna build.
-- ============================================================

AP    = AP    or {}
AP.UI = AP.UI or {}   -- safe: preserves any fields set by ap_ui.lua if loaded first

-- ── PRIMITIVE GOSSIP WRAPPERS ────────────────────────────────

-- Clears all items from the player's gossip menu.
function AP.UI.ClearMenu(player)
    if not player then return end
    if AP.Cap and not AP.Cap.Check("GossipClearMenu") then return end
    pcall(function() player:GossipClearMenu() end)
end

-- Adds one item to the gossip menu.
-- icon:   gossip icon index (0 = no icon, 6 = gear, 7 = dot, etc.)
-- text:   display label
-- sender: page-level routing ID (matched by RegisterPlayerGossipEvent)
-- intid:  action ID within this sender's handler
function AP.UI.AddItem(player, icon, text, sender, intid, code, popup, money)
    if not player then return end
    if AP.Cap and not AP.Cap.Check("GossipMenuAddItem") then return end
    pcall(function()
        player:GossipMenuAddItem(icon or 0, text or "", sender or 0, intid or 0, code, popup, money)
    end)
end

-- Displays the gossip menu to the player.
-- npcText: NPC text ID (use 1 for generic; controls the body text shown)
-- sender:  menu routing ID; must match the sender used by GossipMenuAddItem
--          and the ID passed to RegisterPlayerGossipEvent.
function AP.UI.SendMenu(player, npcText, npc, sender)
    if not player then return end
    if AP.Cap and not AP.Cap.Check("GossipSendMenu") then return end
    if sender == nil and type(npc) == "number" then
        sender = npc
        npc = player
    end
    pcall(function()
        player:GossipSendMenu(npcText or 1, npc or player, sender or 0)
    end)
end

-- Dismisses the gossip menu.
function AP.UI.CloseMenu(player)
    if not player then return end
    pcall(function() player:GossipComplete() end)
end

print("[Echoes] ap05_ui_runtime loaded (AP.UI.ClearMenu/AddItem/SendMenu/CloseMenu available)")
