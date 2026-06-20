-- ============================================================
-- ap_worldsoul_voice.lua -- Echoes of the Worldsoul
-- Escalating flavor-text responses for exploit guard points.
-- Undertale-style: repeated attempts get progressively pointed
-- responses instead of the same line every time.
--
-- This is purely cosmetic/flavor. It does not change any guard
-- logic, validation, or security behavior -- it only changes what
-- message is shown when a guard already blocks something.
-- ============================================================

AP = AP or {}
AP.Voice = AP.Voice or {}

-- Session-only escalation counters. Not persisted to DB -- flavor
-- text does not need to survive a relog. Keyed by "guid_triggerKey".
AP.Voice.Counters = AP.Voice.Counters or {}

-- ============================================================
-- MESSAGE TABLES
-- Each trigger key maps to an ordered list of messages.
-- The Nth attempt (1-indexed) shows messages[N], clamped to the
-- last entry once the list is exhausted (it does not loop or go
-- silent -- the last line is the steady state, which reads as the
-- Worldsoul settling into a final, resigned/amused tone).
-- ============================================================
AP.Voice.Messages = {

    -- ap_dissolved_items guard -- item already dissolved once
    already_dissolved = {
        "This echo has already been claimed. Did you think I wouldn't notice?",
        "I told you already. This one is spent.",
        "Again? Your persistence is admirable. Your results will not change.",
        "I am older than patience itself. You will tire before I do.",
    },

    -- Attempting to dissolve a currently-equipped item
    dissolve_equipped = {
        "I am not so easily fooled. Unequip what you wish to release.",
        "Wearing it does not hide it from me.",
        "We've done this. Take it off first.",
    },

    -- Fix 6 guard -- attempting to dissolve a non-attuned copy via
    -- a stale confirmation page
    dissolve_not_attuned = {
        "That echo was never yours to claim. This one hasn't earned its rest.",
        "You traded the wrong copy. I know the difference, even if you don't.",
    },

    -- Rack: item entry doesn't exist in item_template
    rack_unknown_entry = {
        "That is not a thing that exists. Nice try.",
        "Still not real. I would know.",
        "You're testing me now. I find it endearing.",
    },

    -- Rack: valid item, but player doesn't possess it
    rack_not_possessed = {
        "You do not carry this. The Rack remembers what hands have actually held.",
        "Claiming what you don't possess is a fine try. Possess it first.",
        "I felt nothing from you and this item. There is no bond to track.",
    },

    -- Rack: item name contained characters that broke formatting
    -- (defensive fallback even though gsub escaping should prevent
    -- this from ever actually triggering)
    rack_malformed_name = {
        "Even the Worldsoul stumbles on a name like that. Try again.",
    },

    -- Generic catch-all for any future guard without dedicated lines
    generic = {
        "Clever. But I have existed since before Azeroth had a name.",
        "You are persistent. I respect that. The answer remains no.",
        "At this point I am simply curious how far you intend to take this.",
    },
}

-- ============================================================
-- The Invest() gap acknowledgment -- deliberately NOT escalating,
-- NOT smug. This is the one accepted-risk failure mode that is
-- never the player's fault. Single message, sympathetic tone.
-- Not currently wired to any live detection (no code path notices
-- this in real time today) -- reserved for future use if a
-- reconciliation/integrity check is ever built for ap_mastery vs
-- ap_aether_sinks mismatches, similar in spirit to the Residue
-- reconciliation hook built for the AddItem persistence gap.
-- ============================================================
AP.Voice.InvestGapMessage =
    "The Worldsoul faltered for a moment. Some essence was lost "..
    "between intention and offering. This is rare, and it was not "..
    "your doing."

-- ============================================================
-- CORE FUNCTION
-- Call this from any guard point instead of a hardcoded
-- SendBroadcastMessage string. Handles escalation automatically.
-- ============================================================

function AP.Voice.Speak(player, triggerKey)
    local ok, err = pcall(function()
        local guid = player:GetGUIDLow()
        local key  = guid .. "_" .. triggerKey

        local count = (AP.Voice.Counters[key] or 0) + 1
        AP.Voice.Counters[key] = count

        local messages = AP.Voice.Messages[triggerKey] or AP.Voice.Messages.generic
        local index     = math.min(count, #messages)
        local line      = messages[index]

        player:SendBroadcastMessage(
            "|cff9966ff[Worldsoul]|r " .. line
        )
    end)
    if not ok then
        print("[EotW Voice] ERROR in AP.Voice.Speak: " .. tostring(err))
    end
end

-- ============================================================
-- RESET FUNCTION
-- Call when a player successfully completes the action a trigger
-- was guarding against (e.g. successfully dissolves a different
-- valid item after hitting already_dissolved once). Optional --
-- not calling this just means escalation continues climbing across
-- unrelated successful actions too, which is also a fine, simpler
-- behavior. Provided for cases where a cleaner reset feels better.
-- ============================================================

function AP.Voice.Reset(player, triggerKey)
    local guid = player:GetGUIDLow()
    local key  = guid .. "_" .. triggerKey
    AP.Voice.Counters[key] = nil
end

print("[EotW] Worldsoul Voice flavor-text system loaded. " ..
    "Trigger keys: " .. (function()
        local keys = {}
        for k in pairs(AP.Voice.Messages) do keys[#keys+1] = k end
        return table.concat(keys, ", ")
    end)())
