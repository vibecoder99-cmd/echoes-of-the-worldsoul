AP = AP or {}
AP.Tutorial = AP.Tutorial or {}
AP.Codex    = AP.Codex    or {}

-- ============================================================
-- TUTORIAL SYSTEM
-- ============================================================

AP.Tutorial.Messages = {
    first_login               = "|cff9966ff[Worldsoul]|r You stand at the threshold of something ancient. Kill enemies. Equip their remnants. Let time do the rest. Type |cffffff00#ap|r to open your progress panel.",
    first_essence             = "|cff9966ff[Worldsoul]|r Essence flows from every battle. Enough of it, and you may reshape yourself. Check your progress with |cffffff00#ap check|r.",
    half_attuned              = "|cff9966ff[Worldsoul]|r An echo grows louder. Keep this item equipped — its resonance is building.",
    first_attune              = "|cff9966ff[Worldsoul]|r The item's echo is yours forever. Even if you replace it, its power endures. Open |cffffff00#ap|r to see what you have absorbed.",
    first_hundred_essence     = "|cff9966ff[Worldsoul]|r A hundred drops of Essence gathered. Enough to begin shaping your power. Visit The Crucible in your |cffffff00#ap|r menu.",
    five_attuned              = "|cff9966ff[Worldsoul]|r Five echoes claimed. The Worldsoul stirs. At ten, your Visage begins to take shape.",
    twenty_five_attuned       = "|cff9966ff[Worldsoul]|r Twenty-five echoes. The Ethereal Visage awakens for those who reach this far.",
    first_boss                = "|cff9966ff[Worldsoul]|r A legend ends. Boss kills carry far more Essence than common prey. Seek the powerful.",
    first_discovery           = "|cff9966ff[Worldsoul]|r New lands, new Essence. The Worldsoul rewards those who wander.",
    first_achievement_essence = "|cff9966ff[Worldsoul]|r Achievements echo too. Every milestone you have earned contributes to your power.",
    first_exalted             = "|cff9966ff[Worldsoul]|r Exalted — and the Worldsoul noticed. Faction bonds carry Essence of their own.",
    first_resonant_drop       = nil,
    first_conquest            = nil,
    first_crucible            = "|cff9966ff[Worldsoul]|r Essence committed. The Crucible does not return what is given — only amplifies it. Invest wisely.",
    first_rack_attune         = "|cff9966ff[Worldsoul]|r An echo matures, even at a distance. The Rack's bond is slower — a fifth the pace — but no less real.",
    first_rack_expand         = "|cff9966ff[Worldsoul]|r The Rack holds more than you think. Push its limits with Essence, or with Residue once the Forge has given it to you.",
    first_dissolution         = "|cff9966ff[Worldsoul]|r The item is gone. Its absorbed power remains yours forever. The Residue you have earned endures with it.",
    first_pvp_essence         = "|cff9966ff[Worldsoul]|r PvP victory echoes through the Worldsoul. Honorable kills and Battleground wins carry Essence of their own.",
    first_visage              = "|cff9966ff[Worldsoul]|r Ten echoes claimed. Your Visage stirs. Open |cffffff00#ap|r to choose your form.",
    first_visage_open         = "|cff9966ff[Worldsoul]|r This is the shape of your legend. The rest is yours to shape.",
    first_rate                = "|cff9966ff[Worldsoul]|r Your rate is your own to set. Higher rates mean faster growth. The Worldsoul makes no judgements.",
}

function AP.Tutorial.Trigger(player, key, customMsg)
    local ok, err = pcall(function()
        local accountId     = player:GetAccountId()
        local milestoneType = "tutorial_" .. key

        local check = CharDBQuery(string.format(
            "SELECT 1 FROM ap_aether_milestones WHERE account_id = %d AND milestone_type = '%s' AND milestone_id = 1 LIMIT 1",
            accountId, milestoneType
        ))
        if check then return end

        CharDBExecute(string.format(
            "INSERT IGNORE INTO ap_aether_milestones (account_id, milestone_type, milestone_id) VALUES (%d, '%s', 1)",
            accountId, milestoneType
        ))
        CharDBExecute("COMMIT")

        local msg = customMsg or AP.Tutorial.Messages[key]
        if msg then
            player:SendBroadcastMessage(msg)
        end
    end)
    if not ok then
        print("[EotW Tutorial] ERROR: " .. tostring(err))
    end
end

function AP.Tutorial.CheckLoginTriggers(player)
    local ok, err = pcall(function()
        local guid      = player:GetGUIDLow()
        local accountId = player:GetAccountId()

        -- Delay the first_login whisper so it lands after the player fully loads in
        CreateLuaEvent(function()
            local p = GetPlayerByGUID(guid)
            if p then
                AP.Tutorial.Trigger(p, "first_login")
            end
        end, 8000, 1)

        -- first_hundred_essence: check ap_mastery for 100+ Essence
        local essenceRow = CharDBQuery(string.format(
            "SELECT `aether` FROM `ap_mastery` WHERE `guid` = %d LIMIT 1",
            guid
        ))
        if essenceRow and (tonumber(tostring(essenceRow:GetUInt32(0))) or 0) >= 100 then
            AP.Tutorial.Trigger(player, "first_hundred_essence")
        end

        -- first_attune: check ap_item_attune for at least one fully attuned item
        local attuneRow = CharDBQuery(string.format(
            "SELECT 1 FROM `ap_item_attune` WHERE `guid` = %d AND `attuned` = 1 LIMIT 1",
            guid
        ))
        if attuneRow then
            AP.Tutorial.Trigger(player, "first_attune")
        end
    end)
    if not ok then
        print("[EotW Tutorial] ERROR (CheckLoginTriggers): " .. tostring(err))
    end
end

RegisterPlayerEvent(3, function(event, player)
    AP.Tutorial.CheckLoginTriggers(player)
end)

-- ============================================================
-- CODEX SYSTEM
-- Sender range: 220 (index), 221-231 (topics), 232 (back to main)
-- ============================================================

AP.Codex.Topics = {
    {
        title = "Getting Started",
        icon  = 8,
        pages = {
            "Echoes of the Worldsoul is a progression system that grows with you as you play.",
            "Equip items and fight. Each battle attunes the items you wear, permanently binding their power to your soul.",
            "Even when you replace gear, the echoes of past items remain, adding to your baseline strength.",
            "Open your progress panel at any time with: |cffffff00#ap|r",
            "Use |cffffff00#ap check|r for a quick summary of your current Essence, attunement count, and absorption.",
        },
    },
    {
        title = "What Are Echoes?",
        icon  = 6,
        pages = {
            "Echoes are attuned items — gear you have fully bound to yourself through use in combat.",
            "Each equipped item gains attunement progress as you earn XP from kills, quests, and exploration.",
            "When progress reaches the cap, the item is fully attuned. Its stats are copied into a permanent snapshot.",
            "The snapshot persists account-wide, even after the item is vendored, disenchanted, or replaced.",
            "Your absorbed stats (STR, AGI, STA, INT, SPI) grow with each new echo claimed.",
        },
    },
    {
        title = "Earning Essence",
        icon  = 7,
        pages = {
            "Essence is the currency of the Worldsoul. It fuels Mastery ranks, Talents, and Crucible investment.",
            "Sources: creature kills (25 base for normals, 75 for elites), boss kills (750+), quest completion, zone discovery, achievements, reputation milestones, and profession skill-ups.",
            "Boss Essence scales with creature level. Raid bosses grant significantly more than dungeon bosses.",
            "The Aether Surge sink in The Crucible permanently increases all Essence gains by up to 50%.",
            "Track your Essence at any time with |cffffff00#ap check|r.",
        },
    },
    {
        title = "The Crucible",
        icon  = 0,
        pages = {
            "The Crucible is a permanent investment system. Essence committed here is never returned.",
            "18 categories span damage, survival, and utility. Each follows a diminishing returns curve — early investment is most efficient.",
            "Examples: Life Leech (heal on kill), Fortitude (bonus HP), Aether Surge (more Essence), Movement Speed (run faster).",
            "Open The Crucible from your |cffffff00#ap|r menu. Invest in categories that match your playstyle.",
            "Crucible investment also unlocks Secondary Visage aura tiers at 100k, 250k, 500k, 1M, and 2M total invested.",
        },
    },
    {
        title = "Visage",
        icon  = 4,
        pages = {
            "Visage is the cosmetic ascension system. As your echoes grow, your appearance reflects your power.",
            "Primary Visage is driven by attuned item count. At 10 echoes, Tier 1 awakens. At 250, Tier 5.",
            "Secondary Visage is driven by Crucible investment. At 100,000 invested, Tier 1 awakens.",
            "Five themes: Worldsoul (default), Ethereal (25 echoes), Verdant (50), Void (100), Infernal (250).",
            "Open |cffffff00#ap|r and select Visage to toggle auras, switch themes, and control flash notifications.",
        },
    },
    {
        title = "Resonant Drops",
        icon  = 1,
        pages = {
            "When you loot an item you have already fully attuned, you receive a Worldsoul Echo Fragment instead.",
            "The fragment contains the echo of the item — right-click it to receive Essence and gold.",
            "Higher quality items yield more: Legendary 300 Essence + 20g, Epic 100 Essence + 8g, Rare 40 Essence + 3g.",
            "Legacy Surge: the fourth or later duplicate of the same item triggers 3x Essence and 1.5x gold.",
            "Enchanters may disenchant the fragment. It can also be vendored. The choice is yours.",
        },
    },
    {
        title = "Dungeon Mastery",
        icon  = 8,
        pages = {
            "When you kill the final boss of a dungeon for the first time, that dungeon is conquered.",
            "Conquered status is permanent and account-wide. The Worldsoul remembers your mastery.",
            "While inside a conquered dungeon, you run 8% faster. Familiarity is its own power.",
            "The speed bonus stacks with any Movement Speed investment in The Crucible.",
            "The bonus is automatically removed when you leave the dungeon.",
        },
    },
    {
        title = "Attunement Rack",
        icon  = 6,
        pages = {
            "The Attunement Rack stores up to 20 items (starting at 3 slots) that accrue attunement at 20% the normal rate.",
            "Items stay physically in your bags or bank. Their bond to the Rack is tracked by the Worldsoul. Add items with: |cffffff00#ap rack <itemEntry>|r",
            "Expand slot capacity with Essence (up to 10 slots) or Worldsoul Residue (up to 20). Open the Rack from |cffffff00#ap|r to expand.",
            "Two items with the same name may carry different histories and attune separately. Use |cffffff00#apfind <name>|r to distinguish them.",
            "When a Rack item fully attunes, you will be notified. Visit the Legacy Forge to dissolve items you no longer need.",
        },
    },
    {
        title = "Legacy Forge",
        icon  = 7,
        pages = {
            "The Legacy Forge lets you dissolve fully-attuned items you no longer need into Essence, gold, and Worldsoul Residue.",
            "Your absorbed power from the item is never lost — the echo snapshot persists permanently and your absorbed stats are unchanged.",
            "Each item entry can only be dissolved once per account. Re-acquiring the same item afterward will not yield further rewards, but its legacy remains yours.",
            "Rewards scale with item quality. Legendary yields 6,000 Essence + 50g + 50 Residue. Common yields 150 Essence + 50s + 1 Residue.",
            "Worldsoul Residue can expand your Attunement Rack (13/16/20 slots) or be catalyzed into Essence via the Crucible Catalyst.",
        },
    },
    {
        title = "PvP Progression",
        icon  = 7,
        pages = {
            "The Worldsoul witnesses every battle. Honorable kills and Battleground victories earn Essence alongside normal gains.",
            "Each honorable kill grants 15 Essence. Winning a Battleground grants 200 Essence; a loss still earns 75.",
            "PvP gear attunes identically to PvE gear — equip it, fight, and its echo will be yours permanently.",
            "Rack your PvP gear in the Attunement Rack to accrue attunement at 20% rate even while wearing other items.",
            "More will come. The Worldsoul acknowledges every measure of valor.",
        },
    },
    {
        title = "Tips & Commands",
        icon  = 0,
        pages = {
            "|cffffff00#ap|r            — Open the main progress panel",
            "|cffffff00#ap check|r      — Quick status: Essence, mastery, attuned count",
            "|cffffff00#ap sinks|r      — Show current Crucible investments",
            "|cffffff00#ap rack <id>|r  — Add item to Attunement Rack",
            "|cffffff00#ap rate|r xp / aether / boss <0.1-20> — Set personal gain rates",
            "|cffffff00#apfind|r        — List quests in this zone with unattuned rewards",
        },
    },
}

function AP.Codex.ShowIndex(player, npc)
    player:GossipClearMenu()
    player:GossipMenuAddItem(0, "|cff9966ffWorldsoul Codex|r — Knowledge of the Echoes", 220, 0)
    for i, topic in ipairs(AP.Codex.Topics) do
        player:GossipMenuAddItem(topic.icon, topic.title, 220 + i, 0)
    end
    player:GossipMenuAddItem(1, "<< Back to Main Menu", 232, 0)
    player:GossipSendMenu(1, player, 220)
end

function AP.Codex.ShowTopic(player, npc, topicIndex)
    local topic = AP.Codex.Topics[topicIndex]
    if not topic then return end

    player:GossipClearMenu()
    for _, line in ipairs(topic.pages) do
        player:GossipMenuAddItem(0, line, 220 + topicIndex, 0)
    end
    player:GossipMenuAddItem(1, "<< Back to Codex", 220, 0)
    player:GossipSendMenu(1, player, 220 + topicIndex)
end

-- Called from ap_ui.lua HandleGossipSelect when sender is in range 220-232.
-- sender==220: index (or Back button from a topic page routed here)
-- sender==221-231: topic page; clicking any item on it re-renders the same topic
-- sender==232: Back to Main Menu from the index page
function AP.Codex.OnSelect(player, npc, sender, intid)
    if sender == 220 then
        AP.Codex.ShowIndex(player, npc)
    elseif sender >= 221 and sender <= 231 then
        AP.Codex.ShowTopic(player, npc, sender - 220)
    elseif sender == 232 then
        if AP.OpenUI then AP.OpenUI(player) end
    end
end

print("[EotW] Guided Awakening tutorial system loaded.")
print("[EotW] Worldsoul Codex loaded. " .. #AP.Codex.Topics .. " topics available.")
