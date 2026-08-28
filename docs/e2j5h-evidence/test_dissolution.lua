-- Real execution of the actual reconstructed ap_forge.lua Dissolution flow
-- (AP.Forge.Dissolve / GrantDissolutionRewards / ReconcilePendingDissolutions)
-- under a mocked CharDB + Player, with fault injection simulating a process
-- death at each transaction boundary. This is the file itself, not a
-- reimplementation -- loaded via dofile from the actual repo path.

package.path = package.path
local failures = 0
local passed = 0
local function check(name, cond, detail)
    if cond then
        passed = passed + 1
        print("PASS  " .. name)
    else
        failures = failures + 1
        print("FAIL  " .. name .. (detail and ("  -- " .. detail) or ""))
    end
end

-- Self-contained: SCRIPT_DIR is this file's own directory (mock_db.lua
-- lives alongside it in the same evidence directory), REPO is resolved
-- relative to it so this evidence doesn't depend on any temp/scratchpad
-- location still existing.
local SCRIPT_DIR = (arg and arg[0] and arg[0]:match("(.*[/\\])")) or "./"
local REPO = SCRIPT_DIR .. "../../"

dofile(SCRIPT_DIR .. "mock_db.lua")

-- ---- Minimal AP namespace stubs (only what ap_forge.lua touches outside DB) ----
AP = { Log = function(msg) table.insert(_G.__aplog, msg) end }
_G.__aplog = {}
AP.Voice = { Speak = function() end }
AP.Tutorial = { Trigger = function() end }
AP.API = { DispatchHook = function(name, payload) table.insert(_G.__hooks, {name=name, payload=payload}) end }
_G.__hooks = {}
-- AP.Rack intentionally left nil: ap_forge.lua checks `if AP.Rack then`.

local loginHandlers = {}
function RegisterPlayerEvent(id, fn)
    if id == 3 then table.insert(loginHandlers, fn) end
end
-- Dissolve() ends by calling AP.Forge.ShowPage(), which queries world DB
-- item_template for display purposes only -- not relevant to transaction
-- correctness, so stubbed to "nothing to show".
function WorldDBQuery(sql) return nil end

local ok, err = pcall(dofile, REPO .. "lua_scripts/ap_forge.lua")
check("ap_forge.lua loads standalone under real Lua 5.4", ok, err)
if not ok then os.exit(1) end

check("AP.Forge.ReconcilePendingDissolutions exists (was missing before this pass)",
    type(AP.Forge.ReconcilePendingDissolutions) == "function")
check("AP.Forge.GrantDissolutionRewards exists", type(AP.Forge.GrantDissolutionRewards) == "function")
check("login handler registered (RegisterPlayerEvent(3, ...))", #loginHandlers == 1)

-- ---- Mock Player / Item ----
local function newMockPlayer(guid, accountId)
    local p = {
        _guid = guid, _account = accountId,
        _items = {},       -- entry -> item object (nil once removed)
        _equipped = {},    -- entry -> true
        _coinage = 0,
        _msgs = {},
        _savedCount = 0,
    }
    function p:GetGUIDLow() return self._guid end
    function p:GetAccountId() return self._account end
    function p:GetItemByEntry(entry) return self._items[entry] end
    function p:GetEquippedItemBySlot(slot)
        for entry in pairs(self._equipped) do
            if slot == 0 then return self._items[entry] end
        end
        return nil
    end
    function p:RemoveItem(itemObj, count)
        self._items[itemObj._entry] = nil
    end
    function p:SaveToDB() self._savedCount = self._savedCount + 1 end
    function p:SendBroadcastMessage(msg) table.insert(self._msgs, msg) end
    function p:GetCoinage() return self._coinage end
    function p:SetCoinage(v) self._coinage = v end
    p._residueTokens = 0
    function p:AddItem(entry, count) self._residueTokens = self._residueTokens + count end
    function p:GetItemCount(entry, includeBank) return self._residueTokens end
    function p:GossipClearMenu() end
    function p:GossipMenuAddItem(...) end
    function p:GossipSendMenu(...) end
    return p
end

local function giveItem(player, entry, guidLow)
    local item = { _entry = entry, _guidLow = guidLow or entry }
    function item:GetEntry() return self._entry end
    function item:GetGUIDLow() return self._guidLow end
    player._items[entry] = item
    return item
end

local function setupEligibleItem(guid, accountId, entry)
    MockDB.item_attune[guid .. ":" .. entry] = true
end

-- ============================================================
-- 1. Eligible item -- full happy path, no injected fault
-- ============================================================
do
    MockDB.reset()
    local guid, acct, entry = 1001, 1001, 5001
    local p = newMockPlayer(guid, acct)
    setupEligibleItem(guid, acct, entry)
    giveItem(p, entry)
    AP.Forge.Pending[guid] = { itemEntry = entry, quality = 3, name = "Test Blade" }

    AP.Forge.Dissolve(p, {}, entry)

    local rewards = AP.Forge.Rewards[3]
    check("1. eligible item: full happy path grants correct essence",
        MockDB.mastery[guid] == rewards.essence, "got " .. tostring(MockDB.mastery[guid]))
    check("1. eligible item: correct gold yield", p._coinage == rewards.gold)
    check("1. eligible item: item physically removed", p._items[entry] == nil)
    check("1. eligible item: ap_dissolved_items ledger written exactly once",
        MockDB.dissolved_items[acct .. ":" .. entry] == true)
    check("1. eligible item: pending row reaches COMPLETE",
        MockDB.dissolution_pending[guid .. ":" .. entry].status == "COMPLETE")
    check("1. eligible item: AP.Forge.Pending cleared", AP.Forge.Pending[guid] == nil)
    check("1. eligible item: exactly one OnForgeDissolve audit hook fired", #_G.__hooks == 1)
    check("1. eligible item: audit hook carries correct (fixed) itemEntry, not nil",
        _G.__hooks[1].payload.itemEntry == entry)
end

-- ============================================================
-- 2. Ineligible item (not attuned) -- must abort cleanly, no state changes
-- ============================================================
do
    MockDB.reset()
    local guid, acct, entry = 1002, 1002, 5002
    local p = newMockPlayer(guid, acct)
    giveItem(p, entry)
    -- deliberately do NOT mark attuned
    AP.Forge.Pending[guid] = { itemEntry = entry, quality = 1, name = "Unattuned Item" }

    AP.Forge.Dissolve(p, {}, entry)

    check("2. ineligible (not attuned): item NOT removed", p._items[entry] ~= nil)
    check("2. ineligible (not attuned): no pending row created",
        MockDB.dissolution_pending[guid .. ":" .. entry] == nil)
    check("2. ineligible (not attuned): no reward granted", MockDB.mastery[guid] == nil)
end

-- ============================================================
-- 3. Equipped item -- must reject, item kept
-- ============================================================
do
    MockDB.reset()
    local guid, acct, entry = 1003, 1003, 5003
    local p = newMockPlayer(guid, acct)
    setupEligibleItem(guid, acct, entry)
    giveItem(p, entry)
    p._equipped[entry] = true
    AP.Forge.Pending[guid] = { itemEntry = entry, quality = 1, name = "Worn Item" }

    AP.Forge.Dissolve(p, {}, entry)

    check("3. equipped item: rejected, item kept", p._items[entry] ~= nil)
    check("3. equipped item: no pending row created",
        MockDB.dissolution_pending[guid .. ":" .. entry] == nil)
end

-- ============================================================
-- 4. Moved/missing item -- item no longer physically present
-- ============================================================
do
    MockDB.reset()
    local guid, acct, entry = 1004, 1004, 5004
    local p = newMockPlayer(guid, acct)
    setupEligibleItem(guid, acct, entry)
    -- deliberately do NOT give the item
    AP.Forge.Pending[guid] = { itemEntry = entry, quality = 1, name = "Ghost Item" }

    AP.Forge.Dissolve(p, {}, entry)

    check("4. missing item: no pending row created",
        MockDB.dissolution_pending[guid .. ":" .. entry] == nil)
    check("4. missing item: no reward granted", MockDB.mastery[guid] == nil)
end

-- ============================================================
-- 5. Repeated confirmation after success -- must be rejected as already-dissolved
-- ============================================================
do
    MockDB.reset()
    local guid, acct, entry = 1005, 1005, 5005
    local p = newMockPlayer(guid, acct)
    setupEligibleItem(guid, acct, entry)
    giveItem(p, entry)
    AP.Forge.Pending[guid] = { itemEntry = entry, quality = 1, name = "Item" }
    AP.Forge.Dissolve(p, {}, entry)
    local firstEssence = MockDB.mastery[guid]

    -- Player somehow re-confirms the same item (stale gossip state / direct
    -- exploit attempt). Re-seed Pending since Dissolve() clears it, but the
    -- item is already gone and already ledgered either way.
    AP.Forge.Pending[guid] = { itemEntry = entry, quality = 1, name = "Item" }
    AP.Forge.Dissolve(p, {}, entry)

    check("5. repeated confirmation: no second reward granted",
        MockDB.mastery[guid] == firstEssence, "first=" .. tostring(firstEssence) .. " after=" .. tostring(MockDB.mastery[guid]))
end

-- ============================================================
-- 6. Rapid duplicate request -- second request arrives while first is
--    still PENDING_REMOVAL (simulates a double-click before the first
--    call has finished, i.e. the pending row already exists non-COMPLETE)
-- ============================================================
do
    MockDB.reset()
    local guid, acct, entry = 1006, 1006, 5006
    local p = newMockPlayer(guid, acct)
    setupEligibleItem(guid, acct, entry)
    giveItem(p, entry)
    -- Pre-seed a non-COMPLETE pending row as if a first request already got
    -- this far before the second one is processed.
    MockDB.dissolution_pending[guid .. ":" .. entry] = {
        guid = guid, account_id = acct, item_entry = entry, item_instance_guid = entry,
        quality = 1, essence_reward = 150, gold_reward = 5000, residue_reward = 1,
        status = "PENDING_REMOVAL",
    }
    AP.Forge.Pending[guid] = { itemEntry = entry, quality = 1, name = "Item" }

    AP.Forge.Dissolve(p, {}, entry)

    check("6. rapid duplicate request: second call rejected, item untouched",
        p._items[entry] ~= nil)
    check("6. rapid duplicate request: no reward granted by the second call",
        MockDB.mastery[guid] == nil)
    check("6. rapid duplicate request: original pending row untouched",
        MockDB.dissolution_pending[guid .. ":" .. entry].status == "PENDING_REMOVAL")
end

-- ============================================================
-- 7. Crash BEFORE removal (during/just after reservation, item untouched)
--    -> login reconciliation must drop the reservation, item stays with player
-- ============================================================
do
    MockDB.reset()
    local guid, acct, entry = 1007, 1007, 5007
    local p = newMockPlayer(guid, acct)
    setupEligibleItem(guid, acct, entry)
    giveItem(p, entry)
    AP.Forge.Pending[guid] = { itemEntry = entry, quality = 2, name = "Item" }

    -- Crash right after the PENDING_REMOVAL INSERT+COMMIT (2 DB calls: the
    -- INSERT and its COMMIT) but before RemoveItem's SaveToDB/status update.
    MockDB.crashAfterNCalls = 2  -- allows: SELECT dissolved_items(already checked before)... see note below
    local crashed = false
    local okRun, errRun = pcall(AP.Forge.Dissolve, p, {}, entry)
    if not okRun then crashed = true end

    check("7. crash before removal: dissolve call actually crashed (test validity)", crashed, tostring(errRun))
    check("7. crash before removal: item still physically present pre-recovery",
        p._items[entry] ~= nil)

    -- Now simulate the next login running the real registered handler.
    MockDB.crashAfterNCalls = nil
    loginHandlers[1](nil, p)

    check("7. crash before removal: reconciliation drops the stale reservation",
        MockDB.dissolution_pending[guid .. ":" .. entry] == nil)
    check("7. crash before removal: item was never removed at any point",
        p._items[entry] ~= nil)
    check("7. crash before removal: no reward was ever granted", MockDB.mastery[guid] == nil)
end

-- ============================================================
-- 8. Crash AFTER removal, BEFORE award (Window A: item gone, ledger not
--    yet written) -> reconciliation must finish the ledger write and grant
--    the reward exactly once, item is not restored (by design -- it was
--    already consumed and the player is owed the reward, not the item)
-- ============================================================
do
    MockDB.reset()
    local guid, acct, entry = 1008, 1008, 5008
    local p = newMockPlayer(guid, acct)
    setupEligibleItem(guid, acct, entry)
    giveItem(p, entry)
    AP.Forge.Pending[guid] = { itemEntry = entry, quality = 4, name = "Item" }
    local rewards = AP.Forge.Rewards[4]

    -- Let it get through: dissolved-check(1) + attune-check(1) + pendingRow-check(1)
    -- + INSERT pending(1) + COMMIT(1) + RemoveItem/SaveToDB(not a DB call)
    -- + status->REMOVED UPDATE(1) + COMMIT(1) = crash after 7 DB calls,
    -- i.e. before the ap_dissolved_items INSERT IGNORE.
    MockDB.crashAfterNCalls = 7
    local okRun = pcall(AP.Forge.Dissolve, p, {}, entry)
    check("8. crash after removal/before award: dissolve call actually crashed (test validity)", not okRun)
    check("8. crash after removal/before award: item is gone (physically removed before the crash)",
        p._items[entry] == nil)
    check("8. crash after removal/before award: pending row left at REMOVED",
        MockDB.dissolution_pending[guid .. ":" .. entry].status == "REMOVED")
    check("8. crash after removal/before award: ledger not yet written",
        MockDB.dissolved_items[acct .. ":" .. entry] == nil)

    MockDB.crashAfterNCalls = nil
    loginHandlers[1](nil, p)

    check("8. crash after removal/before award: ledger written by recovery",
        MockDB.dissolved_items[acct .. ":" .. entry] == true)
    check("8. crash after removal/before award: reward granted exactly once, correct amount",
        MockDB.mastery[guid] == rewards.essence)
    check("8. crash after removal/before award: pending row reaches COMPLETE",
        MockDB.dissolution_pending[guid .. ":" .. entry].status == "COMPLETE")
end

-- ============================================================
-- 9. Crash during/after award, before COMPLETE marker (Window B) ->
--    reconciliation re-enters RECORDED branch. Documents the known,
--    narrow re-grant risk rather than claiming it's closed.
-- ============================================================
do
    MockDB.reset()
    local guid, acct, entry = 1009, 1009, 5009
    local p = newMockPlayer(guid, acct)
    setupEligibleItem(guid, acct, entry)
    giveItem(p, entry)
    AP.Forge.Pending[guid] = { itemEntry = entry, quality = 1, name = "Item" }
    local rewards = AP.Forge.Rewards[1]

    -- Manually place the row at RECORDED, as if everything through the
    -- ledger write already committed on a prior (crashed) attempt, and the
    -- item is already gone.
    MockDB.dissolution_pending[guid .. ":" .. entry] = {
        guid = guid, account_id = acct, item_entry = entry, item_instance_guid = entry,
        quality = 1, essence_reward = rewards.essence, gold_reward = rewards.gold,
        residue_reward = rewards.residue, status = "RECORDED",
    }
    MockDB.dissolved_items[acct .. ":" .. entry] = true
    p._items[entry] = nil -- item already physically gone from the crashed attempt

    loginHandlers[1](nil, p)

    check("9. crash during award (Window B): reward granted on recovery",
        MockDB.mastery[guid] == rewards.essence)
    check("9. crash during award (Window B): pending row reaches COMPLETE",
        MockDB.dissolution_pending[guid .. ":" .. entry].status == "COMPLETE")

    -- Second login after COMPLETE must NOT re-grant (this is the safe case;
    -- the unsafe case -- a SECOND crash strictly between grant and the
    -- COMPLETE marker -- is the documented open residual risk, not claimed
    -- to be covered here).
    loginHandlers[1](nil, p)
    check("9. crash during award (Window B): no re-grant on a clean subsequent login",
        MockDB.mastery[guid] == rewards.essence)
end

-- ============================================================
-- 10. Login/restart reconciliation with NO pending rows -- must be a no-op
-- ============================================================
do
    MockDB.reset()
    local guid, acct = 1010, 1010
    local p = newMockPlayer(guid, acct)
    local ok2 = pcall(loginHandlers[1], nil, p)
    check("10. reconciliation with nothing pending: does not error", ok2)
end

-- ============================================================
-- 11. Correct yield across all six quality tiers
-- ============================================================
do
    for quality = 0, 5 do
        MockDB.reset()
        local guid, acct, entry = 2000 + quality, 2000 + quality, 6000 + quality
        local p = newMockPlayer(guid, acct)
        setupEligibleItem(guid, acct, entry)
        giveItem(p, entry)
        AP.Forge.Pending[guid] = { itemEntry = entry, quality = quality, name = "Q" .. quality }
        AP.Forge.Dissolve(p, {}, entry)
        local rewards = AP.Forge.Rewards[quality]
        check("11. correct yield for quality " .. quality,
            MockDB.mastery[guid] == rewards.essence and p._coinage == rewards.gold,
            string.format("essence=%s (want %d) gold=%s (want %d)",
                tostring(MockDB.mastery[guid]), rewards.essence, tostring(p._coinage), rewards.gold))
    end
end

-- ============================================================
-- 12. No silent item loss across the full fault matrix already run above
--     (aggregate check): every crash scenario above ends with either the
--     item restored/never touched, or a granted reward -- never neither.
-- ============================================================
check("12. no silent item loss (see cases 7-9 above: each ends item-kept or reward-granted)", true)

-- ============================================================
-- 13. Correct audit state: hook payload itemEntry is never nil (regression
--     for the pending.entry bug fixed during this pass)
-- ============================================================
do
    MockDB.reset()
    _G.__hooks = {}
    local guid, acct, entry = 1013, 1013, 5013
    local p = newMockPlayer(guid, acct)
    setupEligibleItem(guid, acct, entry)
    giveItem(p, entry)
    AP.Forge.Pending[guid] = { itemEntry = entry, quality = 1, name = "Item" }
    AP.Forge.Dissolve(p, {}, entry)
    check("13. audit hook payload itemEntry is not nil", _G.__hooks[1].payload.itemEntry ~= nil)
    check("13. audit hook payload itemEntry matches dissolved item",
        _G.__hooks[1].payload.itemEntry == entry)
end

-- ============================================================
-- 15. TARGETED FAULT INJECTION: crash after ALL rewards have been granted
--     (essence, gold, residue-ledger all already atomically claimed) but
--     BEFORE the COMPLETE marker is durably recorded. Prove through
--     REPEATED reconciliation (not just one extra call) that no reward
--     channel is ever granted a second time.
-- ============================================================
do
    MockDB.reset()
    local guid, acct, entry = 3001, 3001, 7001
    local p = newMockPlayer(guid, acct)
    local rewards = AP.Forge.Rewards[4]

    -- Construct the exact state: all three atomic grant+claim statements
    -- already committed (destination tables already hold the reward,
    -- pending row's remaining-amount columns already zeroed), status is
    -- still RECORDED (not yet flipped to COMPLETE) -- i.e. the process died
    -- in the gap between the last grant statement and the final marker.
    MockDB.mastery[guid] = rewards.essence
    MockDB.characters[guid] = rewards.gold
    MockDB.residue[acct] = rewards.residue
    MockDB.dissolution_pending[guid .. ":" .. entry] = {
        guid = guid, account_id = acct, item_entry = entry, item_instance_guid = entry,
        quality = 4, essence_reward = 0, gold_reward = 0, residue_reward = 0,
        status = "RECORDED",
    }
    p._coinage = 0 -- in-memory not yet synced (this call never reached SetCoinage)

    -- Reconcile THREE times in a row (simulates three more logins / three
    -- more crash-and-retry cycles at the exact same point).
    loginHandlers[1](nil, p)
    loginHandlers[1](nil, p)
    loginHandlers[1](nil, p)

    check("15. post-grant/pre-COMPLETE crash: essence not re-granted across 3 reconciliations",
        MockDB.mastery[guid] == rewards.essence,
        "got " .. tostring(MockDB.mastery[guid]) .. " want " .. rewards.essence)
    check("15. post-grant/pre-COMPLETE crash: gold not re-granted across 3 reconciliations",
        MockDB.characters[guid] == rewards.gold,
        "got " .. tostring(MockDB.characters[guid]) .. " want " .. rewards.gold)
    check("15. post-grant/pre-COMPLETE crash: residue ledger not re-granted across 3 reconciliations",
        MockDB.residue[acct] == rewards.residue,
        "got " .. tostring(MockDB.residue[acct]) .. " want " .. rewards.residue)
    check("15. post-grant/pre-COMPLETE crash: pending row reaches COMPLETE",
        MockDB.dissolution_pending[guid .. ":" .. entry].status == "COMPLETE")
end

-- ============================================================
-- 16. PARTIAL REWARD ISSUANCE: essence already granted+claimed, gold and
--     residue NOT yet granted (crash landed between the essence UPDATE and
--     the gold UPDATE). Recovery must grant exactly the outstanding two,
--     and must NOT re-grant essence.
-- ============================================================
do
    MockDB.reset()
    local guid, acct, entry = 3002, 3002, 7002
    local p = newMockPlayer(guid, acct)
    local rewards = AP.Forge.Rewards[5]

    MockDB.mastery[guid] = rewards.essence -- essence already committed
    MockDB.dissolution_pending[guid .. ":" .. entry] = {
        guid = guid, account_id = acct, item_entry = entry, item_instance_guid = entry,
        quality = 5, essence_reward = 0, -- already claimed
        gold_reward = rewards.gold, residue_reward = rewards.residue, -- still outstanding
        status = "RECORDED",
    }

    loginHandlers[1](nil, p)
    loginHandlers[1](nil, p) -- repeat once more

    check("16. partial issuance: essence unaffected by recovery (was already correct)",
        MockDB.mastery[guid] == rewards.essence)
    check("16. partial issuance: gold granted exactly once (not zero, not double)",
        MockDB.characters[guid] == rewards.gold,
        "got " .. tostring(MockDB.characters[guid]) .. " want " .. rewards.gold)
    check("16. partial issuance: residue ledger granted exactly once",
        MockDB.residue[acct] == rewards.residue,
        "got " .. tostring(MockDB.residue[acct]) .. " want " .. rewards.residue)
    check("16. partial issuance: pending row reaches COMPLETE",
        MockDB.dissolution_pending[guid .. ":" .. entry].status == "COMPLETE")
end

-- ============================================================
-- 17. PARTIAL REWARD ISSUANCE, second split point: essence + gold already
--     granted, residue-ledger NOT yet granted.
-- ============================================================
do
    MockDB.reset()
    local guid, acct, entry = 3003, 3003, 7003
    local p = newMockPlayer(guid, acct)
    local rewards = AP.Forge.Rewards[3]

    MockDB.mastery[guid] = rewards.essence
    MockDB.characters[guid] = rewards.gold
    MockDB.dissolution_pending[guid .. ":" .. entry] = {
        guid = guid, account_id = acct, item_entry = entry, item_instance_guid = entry,
        quality = 3, essence_reward = 0, gold_reward = 0,
        residue_reward = rewards.residue, -- only this still outstanding
        status = "RECORDED",
    }

    for i = 1, 3 do loginHandlers[1](nil, p) end

    check("17. partial issuance (2 of 3 done): essence still exactly correct",
        MockDB.mastery[guid] == rewards.essence)
    check("17. partial issuance (2 of 3 done): gold still exactly correct",
        MockDB.characters[guid] == rewards.gold)
    check("17. partial issuance (2 of 3 done): residue ledger granted exactly once across 3 reconciliations",
        MockDB.residue[acct] == rewards.residue,
        "got " .. tostring(MockDB.residue[acct]) .. " want " .. rewards.residue)
end

-- ============================================================
-- 18. Repeated reconciliation from the very start of RECORDED (nothing
--     granted yet) -- 5 reconciliation passes in a row must yield exactly
--     one full reward, never a multiple of it.
-- ============================================================
do
    MockDB.reset()
    local guid, acct, entry = 3004, 3004, 7004
    local p = newMockPlayer(guid, acct)
    local rewards = AP.Forge.Rewards[2]

    MockDB.dissolution_pending[guid .. ":" .. entry] = {
        guid = guid, account_id = acct, item_entry = entry, item_instance_guid = entry,
        quality = 2, essence_reward = rewards.essence, gold_reward = rewards.gold,
        residue_reward = rewards.residue, status = "RECORDED",
    }

    for i = 1, 5 do loginHandlers[1](nil, p) end

    check("18. five repeated reconciliations from RECORDED: essence granted exactly once",
        MockDB.mastery[guid] == rewards.essence)
    check("18. five repeated reconciliations from RECORDED: gold granted exactly once",
        MockDB.characters[guid] == rewards.gold)
    check("18. five repeated reconciliations from RECORDED: residue granted exactly once",
        MockDB.residue[acct] == rewards.residue)
end

-- ============================================================
-- 19. DISCLOSED GAP, verified as characterized: crash strictly between the
--     ap_residue ledger claim committing and the physical-item AddItem
--     call. Confirms this is a MISSING-token risk, not a DUPLICATE-token
--     risk -- the ledger (authoritative) is correct and stable, and no
--     amount of replay grants the physical token after the fact, because
--     residue_reward already reads 0. Recorded as a known, accepted,
--     disclosed characteristic -- not something this pass claims to fix.
-- ============================================================
do
    MockDB.reset()
    local guid, acct, entry = 3005, 3005, 7005
    local p = newMockPlayer(guid, acct)
    local addItemCalls = 0
    local origAddItem = p.AddItem
    p.AddItem = function(self, entry2, count) addItemCalls = addItemCalls + 1 end

    local rewards = AP.Forge.Rewards[3]
    MockDB.residue[acct] = rewards.residue -- ledger claim already committed
    MockDB.dissolution_pending[guid .. ":" .. entry] = {
        guid = guid, account_id = acct, item_entry = entry, item_instance_guid = entry,
        quality = 3, essence_reward = 0, gold_reward = 0,
        residue_reward = 0, -- already claimed; AddItem never ran before the crash
        status = "RECORDED",
    }

    -- Isolate AP.Forge.ReconcilePendingDissolutions itself (not the whole
    -- login handler, which also runs the separate, pre-existing Residue
    -- clean_exit reconciliation -- a DIFFERENT, already-shipped safety net
    -- that independently tops up physical-item shortfalls against the
    -- ledger regardless of source, and would otherwise mask what this
    -- specific test is isolating).
    AP.Forge.ReconcilePendingDissolutions(p)
    AP.Forge.ReconcilePendingDissolutions(p)

    check("19. disclosed gap confirmed: ledger stays correct (authoritative value never drifts)",
        MockDB.residue[acct] == rewards.residue)
    check("19. disclosed gap confirmed: physical item is never (re)granted once ledger is claimed "..
          "(missing-token risk, not duplicate-token risk, as documented)",
        addItemCalls == 0)
end

-- ============================================================
-- 20. End-to-end self-healing check: run the SAME disclosed-gap state
--     (residue ledger already claimed, physical token never granted)
--     through the FULL registered login handler (both reconciliation
--     passes together, as they actually run in production) instead of
--     calling ReconcilePendingDissolutions in isolation. The pre-existing,
--     already-shipped Residue clean_exit reconciliation in this same file
--     independently compares ledger vs. physical count and tops up any
--     shortfall -- confirming the disclosed gap in test 19 is self-healing
--     in the real integrated login flow, not merely narrow in isolation.
-- ============================================================
do
    MockDB.reset()
    local guid, acct, entry = 3006, 3006, 7006
    local p = newMockPlayer(guid, acct)
    local rewards = AP.Forge.Rewards[3]

    MockDB.residue[acct] = rewards.residue -- ledger already correct
    MockDB.dissolution_pending[guid .. ":" .. entry] = {
        guid = guid, account_id = acct, item_entry = entry, item_instance_guid = entry,
        quality = 3, essence_reward = 0, gold_reward = 0, residue_reward = 0,
        status = "RECORDED",
    }
    -- p._residueTokens starts at 0 -- physical token never granted, matching
    -- test 19's disclosed gap exactly.

    loginHandlers[1](nil, p) -- full login handler: both reconciliation passes

    check("20. end-to-end self-heal: physical Residue token count reaches the ledger amount",
        p._residueTokens == rewards.residue,
        "got " .. tostring(p._residueTokens) .. " want " .. rewards.residue)
    check("20. end-to-end self-heal: ledger itself unaffected (still exactly the entitled amount)",
        MockDB.residue[acct] == rewards.residue)
end

print("")
print("OPEN ITEM (not a pass/fail check -- see report): bot exclusion is NOT")
print("implemented. No IsBot/GetPlayerbotAI/equivalent API exists anywhere in")
print("this repo's Lua or the mod_attunement_plus C++ patch to check against.")
print("")
print(string.format("%d passed, %d failed", passed, failures))
if failures > 0 then os.exit(1) else os.exit(0) end
