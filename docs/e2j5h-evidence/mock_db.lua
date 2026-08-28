-- In-memory mock of the CharDBQuery/CharDBExecute surface actually used by
-- AP.Forge.Dissolve / GrantDissolutionRewards / ReconcilePendingDissolutions
-- in ap_forge.lua. Pattern-matches the exact SQL shapes those functions
-- emit (known because we wrote them) rather than implementing a general
-- SQL engine. Used to execute the real ap_forge.lua source under fault
-- injection, since no live MySQL/AzerothCore server exists in this
-- environment.

local M = {}

M.dissolution_pending = {}  -- key "guid:entry" -> row
M.dissolved_items     = {}  -- key "account:entry" -> true
M.item_attune         = {}  -- key "guid:entry" -> true (attuned)
M.mastery             = {}  -- guid -> aether total
M.residue             = {}  -- account -> amount
M.characters          = {}  -- guid -> money (mocks the core `characters` table)
M.calls                = {} -- ordered log of every DB call, for assertions

-- Fault injection: when set to a number N, the Nth remaining DB call
-- (query or execute, combined count) raises an error instead of running,
-- simulating the process dying at that exact point.
M.crashAfterNCalls = nil
local callCounter = 0

local function maybeCrash(label)
    callCounter = callCounter + 1
    table.insert(M.calls, label)
    if M.crashAfterNCalls ~= nil and callCounter > M.crashAfterNCalls then
        error("SIMULATED CRASH after " .. M.crashAfterNCalls .. " DB calls (at: " .. label .. ")")
    end
end

local function mkResult(rows, cols)
    -- rows: array of arrays (row -> col values, 0-indexed access via GetX)
    -- cols: not used beyond documentation; GetString/GetUInt32 index by position
    local idx = 1
    if #rows == 0 then return nil end
    local obj = {}
    function obj:GetString(i) return tostring(rows[idx][i + 1]) end
    function obj:GetUInt32(i) return rows[idx][i + 1] end
    function obj:NextRow()
        idx = idx + 1
        return idx <= #rows
    end
    return obj
end

function CharDBQuery(sql)
    if sql:find("FROM `ap_dissolved_items`") then
        maybeCrash("SELECT ap_dissolved_items")
        local acct  = tonumber(sql:match("account_id`%s*=%s*(%d+)"))
        local entry = tonumber(sql:match("item_entry`%s*=%s*(%d+)"))
        if M.dissolved_items[acct .. ":" .. entry] then
            return mkResult({{1}})
        end
        return nil

    elseif sql:find("FROM `ap_item_attune`") then
        maybeCrash("SELECT ap_item_attune")
        local guid  = tonumber(sql:match("guid`%s*=%s*(%d+)"))
        local entry = tonumber(sql:match("item_entry`%s*=%s*(%d+)"))
        if M.item_attune[guid .. ":" .. entry] then
            return mkResult({{1}})
        end
        return nil

    elseif sql:find("SELECT `status` FROM `ap_dissolution_pending`") then
        maybeCrash("SELECT status ap_dissolution_pending")
        local guid  = tonumber(sql:match("guid`%s*=%s*(%d+)"))
        local entry = tonumber(sql:match("item_entry`%s*=%s*(%d+)"))
        local row = M.dissolution_pending[guid .. ":" .. entry]
        if row then return mkResult({{row.status}}) end
        return nil

    elseif sql:find("SELECT `essence_reward`, `gold_reward`, `residue_reward`") then
        maybeCrash("SELECT remaining reward amounts")
        local guid  = tonumber(sql:match("guid`%s*=%s*(%d+)"))
        local entry = tonumber(sql:match("item_entry`%s*=%s*(%d+)"))
        local row = M.dissolution_pending[guid .. ":" .. entry]
        if row then
            return mkResult({{ row.essence_reward, row.gold_reward, row.residue_reward }})
        end
        return nil

    elseif sql:find("SELECT `item_entry`, `essence_reward`") then
        maybeCrash("SELECT pending-for-reconcile")
        local guid = tonumber(sql:match("guid`%s*=%s*(%d+)"))
        local out = {}
        for _, row in pairs(M.dissolution_pending) do
            if row.guid == guid and row.status ~= "COMPLETE" then
                table.insert(out, { row.item_entry, row.essence_reward, row.gold_reward, row.residue_reward, row.status })
            end
        end
        return mkResult(out)

    elseif sql:find("FROM ap_item_attune a") then
        -- ShowPage's listing JOIN, display-only, irrelevant to transaction
        -- correctness -- always "nothing to list" in these tests.
        maybeCrash("SELECT ShowPage listing JOIN")
        return nil

    elseif sql:find("FROM `ap_residue`") then
        maybeCrash("SELECT ap_residue")
        local acct = tonumber(sql:match("account_id`%s*=%s*(%d+)"))
        local amt = M.residue[acct]
        if amt then return mkResult({{amt}}) end
        return nil

    else
        error("mock_db: unrecognized CharDBQuery shape: " .. sql)
    end
end

function CharDBExecute(sql)
    if sql == "COMMIT" then
        maybeCrash("COMMIT")
        return
    end

    if sql:find("^INSERT INTO `ap_dissolution_pending`") then
        maybeCrash("INSERT ap_dissolution_pending")
        local guid, account, entry, itemInstGuid, quality, essence, gold, residue =
            sql:match("VALUES %((%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)")
        M.dissolution_pending[guid .. ":" .. entry] = {
            guid = tonumber(guid), account_id = tonumber(account), item_entry = tonumber(entry),
            item_instance_guid = tonumber(itemInstGuid), quality = tonumber(quality),
            essence_reward = tonumber(essence), gold_reward = tonumber(gold), residue_reward = tonumber(residue),
            status = "PENDING_REMOVAL",
        }
        return

    elseif sql:find("^DELETE FROM `ap_dissolution_pending`") then
        maybeCrash("DELETE ap_dissolution_pending")
        local guid  = tonumber(sql:match("guid`%s*=%s*(%d+)"))
        local entry = tonumber(sql:match("item_entry`%s*=%s*(%d+)"))
        M.dissolution_pending[guid .. ":" .. entry] = nil
        return

    elseif sql:find("^UPDATE `ap_dissolution_pending` SET `status`") then
        maybeCrash("UPDATE ap_dissolution_pending status")
        local status = sql:match("status`%s*=%s*'(%u+)'")
        local guid   = tonumber(sql:match("guid`%s*=%s*(%d+)"))
        local entry  = tonumber(sql:match("item_entry`%s*=%s*(%d+)"))
        local row = M.dissolution_pending[guid .. ":" .. entry]
        if row then row.status = status end
        return

    elseif sql:find("^INSERT IGNORE INTO `ap_dissolved_items`") then
        maybeCrash("INSERT IGNORE ap_dissolved_items")
        local acct, entry = sql:match("VALUES %((%d+), (%d+)%)")
        local key = acct .. ":" .. entry
        if M.dissolved_items[key] then
            -- INSERT IGNORE semantics: a second insert for the same key is a
            -- silent no-op, never an error and never a second row.
            return
        end
        M.dissolved_items[key] = true
        return

    elseif sql:find("^INSERT IGNORE INTO `ap_mastery`") then
        maybeCrash("INSERT IGNORE ap_mastery (ensure row)")
        local guid = tonumber(sql:match("VALUES %((%d+),0,0%)"))
        if M.mastery[guid] == nil then M.mastery[guid] = 0 end
        return

    elseif sql:find("^INSERT IGNORE INTO `ap_residue`") then
        maybeCrash("INSERT IGNORE ap_residue (ensure row)")
        local acct = tonumber(sql:match("VALUES %((%d+),0%)"))
        if M.residue[acct] == nil then M.residue[acct] = 0 end
        return

    elseif sql:find("^UPDATE `ap_mastery` m JOIN") then
        maybeCrash("ATOMIC essence grant+claim")
        local guid  = tonumber(sql:match("p%.`guid`%s*=%s*(%d+)"))
        local entry = tonumber(sql:match("p%.`item_entry`%s*=%s*(%d+)"))
        local row = M.dissolution_pending[guid .. ":" .. entry]
        if row and row.essence_reward > 0 then
            M.mastery[guid] = (M.mastery[guid] or 0) + row.essence_reward
            row.essence_reward = 0
        end
        return

    elseif sql:find("^UPDATE `characters` c JOIN") then
        maybeCrash("ATOMIC gold grant+claim")
        local guid  = tonumber(sql:match("p%.`guid`%s*=%s*(%d+)"))
        local entry = tonumber(sql:match("p%.`item_entry`%s*=%s*(%d+)"))
        local row = M.dissolution_pending[guid .. ":" .. entry]
        if row and row.gold_reward > 0 then
            M.characters[guid] = (M.characters[guid] or 0) + row.gold_reward
            row.gold_reward = 0
        end
        return

    elseif sql:find("^UPDATE `ap_residue` r JOIN") then
        maybeCrash("ATOMIC residue grant+claim")
        local guid  = tonumber(sql:match("p%.`guid`%s*=%s*(%d+)"))
        local entry = tonumber(sql:match("p%.`item_entry`%s*=%s*(%d+)"))
        local row = M.dissolution_pending[guid .. ":" .. entry]
        if row and row.residue_reward > 0 then
            M.residue[row.account_id] = (M.residue[row.account_id] or 0) + row.residue_reward
            row.residue_reward = 0
        end
        return

    elseif sql:find("^INSERT INTO `ap_mastery`") then
        maybeCrash("INSERT/UPDATE ap_mastery")
        local guid, essence = sql:match("VALUES %((%d+),(%d+),0%)")
        guid = tonumber(guid); essence = tonumber(essence)
        M.mastery[guid] = (M.mastery[guid] or 0) + essence
        return

    elseif sql:find("^INSERT INTO `ap_residue`") then
        maybeCrash("INSERT/UPDATE ap_residue")
        local acct, amount = sql:match("VALUES %((%d+), (%d+)%)")
        acct = tonumber(acct); amount = tonumber(amount)
        M.residue[acct] = (M.residue[acct] or 0) + amount
        return

    else
        error("mock_db: unrecognized CharDBExecute shape: " .. sql)
    end
end

function M.reset()
    M.dissolution_pending = {}
    M.dissolved_items     = {}
    M.item_attune         = {}
    M.mastery             = {}
    M.residue             = {}
    M.characters          = {}
    M.calls                = {}
    M.crashAfterNCalls    = nil
    callCounter = 0
end

_G.MockDB = M
return M
