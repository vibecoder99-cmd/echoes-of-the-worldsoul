-- Copyright (C) 2025-2026 vibecoder99
-- Licensed under the GNU General Public License v3. See LICENSE.
-- ============================================================
-- ap01_runtime.lua
-- Echoes of the Worldsoul — Runtime Dispatch Hub (stubs)
--
-- Declares AP.RT with safe no-op stubs for every runtime
-- function. ap02_runtime_eluna.lua overwrites these with real
-- Eluna implementations.
--
-- If ap02 fails to load, callers receive nil/false/0/"" rather
-- than a Lua error. This makes all AP.RT calls unconditionally
-- safe to call from any phase of migration.
-- ============================================================

AP    = AP    or {}
AP.RT = AP.RT or {}

-- Player identity
AP.RT.GetGUID         = function(player)          return nil   end
AP.RT.GetAccountId    = function(player)          return nil   end
AP.RT.GetLevel        = function(player)          return 0     end
AP.RT.GetName         = function(player)          return ""    end
AP.RT.GetClass        = function(player)          return 0     end

-- Player world state
AP.RT.GetMap          = function(player)          return nil   end
AP.RT.GetMapId        = function(player)          return 0     end
AP.RT.GetZoneId       = function(player)          return 0     end
AP.RT.GetGroup        = function(player)          return nil   end
AP.RT.IsInWorld       = function(player)          return false end
AP.RT.GetGroupMembersCount = function(group)      return 0     end
AP.RT.IsMapInstance   = function(map)             return nil   end
AP.RT.IsMapRaid       = function(map)             return nil   end

-- Event object access
AP.RT.GetQuestId      = function(quest)           return 0     end
AP.RT.GetSpellEntry   = function(spell)           return 0     end
AP.RT.GetCreatureEntry= function(creature)        return 0     end
AP.RT.GetCreatureLevel= function(creature)        return 0     end
AP.RT.GetAchievementId= function(achievement)     return 0     end

-- Player item access
AP.RT.GetEquippedItem = function(player, slot)    return nil   end
AP.RT.GetItemEntry    = function(item)            return 0     end
AP.RT.GetItemLevel    = function(item)            return 0     end
AP.RT.GetItemGUIDLow  = function(item)            return 0     end
AP.RT.GetItemGUID     = function(item)            return nil   end
AP.RT.GetItemQuality  = function(item)            return 0     end
AP.RT.GetItemByEntry= function(player, entry)  return nil   end
AP.RT.GetItemCount  = function(player, entry, checkBank) return 0 end
AP.RT.TryGetItemCount = function(player, entry, checkBank) return false, nil end
AP.RT.GetItemByPos  = function(player, bag, slot) return nil   end
AP.RT.GetItemUInt32Value = function(item, field)  return 0     end
AP.RT.SetItemUInt32Value = function(item, field, value) return false end
AP.RT.SaveItemToDB    = function(item)            return false end
AP.RT.RemoveItemObject= function(item)            return false end

-- Player actions
AP.RT.SetSpeed        = function(player, moveType, rate, forced) return false end
AP.RT.IsMounted       = function(player)          return false end
AP.RT.IsInFlight      = function(player)          return false end
AP.RT.RemoveItem      = function(player, entry, count) return false end
AP.RT.AddItem         = function(player, entry, count) return false end
AP.RT.SavePlayerToDB  = function(player, logout, saveImmediately) return false end
AP.RT.GetCoinage      = function(player) return 0 end
AP.RT.SetCoinage      = function(player, amount) return false end
AP.RT.ModifyMoney     = function(player, amount) return false end
AP.RT.GetHealth       = function(unit) return 0 end
AP.RT.GetMaxHealth    = function(unit) return 0 end
AP.RT.SetHealth       = function(unit, amount) return false end
AP.RT.ModifyHealth    = function(unit, amount) return false end
AP.RT.InBattleground  = function(player) return false end
AP.RT.GetBattlegroundId = function(player) return 0 end
AP.RT.GetTeam         = function(player) return 0 end

-- GM check (three-stage fallback in ap02)
AP.RT.IsGM            = function(player, minLvl)  return false end

-- Communication
AP.RT.SendMessage     = function(player, msg)                  end

-- Auras / cooldowns
AP.RT.AddAura         = function(player, spellId) return false end
AP.RT.RemoveAura      = function(player, spellId) return false end
AP.RT.HasSpellCooldown= function(player, spellId) return false end
AP.RT.HasCooldown     = AP.RT.HasSpellCooldown
AP.RT.GetCooldownDelay= function(player, spellId) return 0     end
AP.RT.ResetCooldown   = function(player, spellId)              end

-- Global lookups
AP.RT.GetPlayerByGUID = function(guid)            return nil   end
AP.RT.GetPlayerByName = function(name)            return nil   end
AP.RT.GetPlayersInWorld = function()                return {}    end

-- Timer / event registration
AP.RT.CreateTimer     = function(fn, ms, reps)                 end
AP.RT.RegisterEvent   = function(etype, id, fn) return false end
AP.RT.RegisterStartup = function(fn) return false end
AP.RT.RegisterItemEvent = function(entry, id, fn) return false end
AP.RT.RegisterBGEvent = function(id, fn) return false end
AP.RT.RegisterPlayerGossipEvent = function(menuId, id, fn) return false end

print("[Echoes] ap01_runtime loaded (no-op stubs; waiting for ap02_runtime_eluna)")
