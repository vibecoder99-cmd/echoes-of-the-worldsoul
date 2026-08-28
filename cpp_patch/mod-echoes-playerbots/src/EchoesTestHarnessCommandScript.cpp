// E2j9a - Deterministic Playerbot Test Harness.
//
// Purpose (per the E2j9a implementation authorization): replace the unsafe "escalate random bot
// population and hope the desired character gets picked" testing pattern - proven unreliable this
// project (E2j8/E2j9/E2j11 checkpoints all lost significant time to it, root-caused in the
// Complete Playerbots Architecture, Lifecycle, and Echoes Compatibility Audit,
// env/backups/playerbots-complete-audit/20260731T060000+0000/reports/) - with a narrow,
// administrator-only, exact-character login/logout/status surface built directly on Playerbots'
// own existing, stable, public API:
//   PlayerbotHolder::AddPlayerBot(ObjectGuid guid, uint32 masterAccountId = 0)
//   PlayerbotHolder::LogoutPlayerBot(ObjectGuid guid)
//   PlayerbotHolder::GetPlayerBot(ObjectGuid guid) const
// (all declared in the public header modules/mod-playerbots/src/Bot/PlayerbotMgr.h, implemented
// in PlayerbotMgr.cpp - `RandomPlayerbotMgr : public PlayerbotHolder`, accessed via the existing
// global singleton `sRandomPlayerbotMgr`, exactly as `rndbot`/`playerbots debug` commands already
// do in modules/mod-playerbots/src/Script/PlayerbotCommandScript.cpp - this file follows that
// exact same ChatCommandTable/CommandScript registration convention, not a new one.
//
// This is test infrastructure, not new gameplay behavior - it does not add, remove, or modify any
// Echoes gameplay effect, category, or economy path. It only makes existing Playerbots login
// machinery reachable by exact character identity instead of only by random-pool chance.

#include "EchoesConfig.h"
#include "Chat.h"
#include "ObjectMgr.h"
#include "Player.h"
#ifdef MOD_PLAYERBOTS
#include "Playerbots.h"
#include "PlayerbotMgr.h"
#include "RandomPlayerbotMgr.h"
#endif
#include "ScriptMgr.h"
#include "World.h"
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <string>

// E2j14 Workstream B: this file's entire purpose (per the header comment above) is a console
// command surface built directly on mod-playerbots' own PlayerbotHolder::AddPlayerBot/
// LogoutPlayerBot/GetPlayerBot API and the GET_PLAYERBOT_AI macro - every command handler below
// uses one or both. When MOD_PLAYERBOTS is undefined there is no bot login/logout machinery to
// drive at all, so the whole substantive body of this translation unit is guarded out (a
// whole-file-skip pattern, not a per-line stub) - AddSC_EchoesTestHarnessCommandScript() itself
// stays defined unconditionally at the bottom (with an empty, "register nothing" body in the
// guarded-out case) because mod_echoes_playerbots_loader.cpp calls it unconditionally.
#ifdef MOD_PLAYERBOTS

using namespace Acore::ChatCommands;

namespace
{
    std::string Trim(char const* args)
    {
        std::string token = args ? args : "";
        token.erase(0, token.find_first_not_of(" \t"));
        if (!token.empty())
            token.erase(token.find_last_not_of(" \t") + 1);
        return token;
    }

    // Resolves either a decimal character GUID or an exact character name to an ObjectGuid.
    // Name resolution uses AzerothCore's own sCharacterCache - the same authoritative source
    // every other name->guid lookup in this core uses, never a bespoke query. Returns an empty
    // (zero) ObjectGuid on failure - callers must check IsEmpty() before use, never assume success.
    ObjectGuid ResolveCharacterGuid(std::string const& token)
    {
        // Try as a plain decimal low-GUID first (matches how every prior E2j-phase diagnostic in
        // this project has referred to characters, e.g. "guid=1284").
        bool allDigits = !token.empty() && std::all_of(token.begin(), token.end(), ::isdigit);
        if (allDigits)
        {
            uint32 lowGuid = static_cast<uint32>(std::strtoul(token.c_str(), nullptr, 10));
            ObjectGuid candidate = ObjectGuid::Create<HighGuid::Player>(lowGuid);
            if (lowGuid != 0 && sCharacterCache->GetCharacterAccountIdByGuid(candidate) != 0)
                return candidate;
            return ObjectGuid::Empty;
        }

        // Fall back to exact name resolution - GetCharacterGuidByName is exact-match by design
        // (AzerothCore's own character name uniqueness constraint means this is never ambiguous).
        return sCharacterCache->GetCharacterGuidByName(token);
    }
}

class echoes_test_harness_commandscript : public CommandScript
{
public:
    echoes_test_harness_commandscript() : CommandScript("echoes_test_harness_commandscript") {}

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable echoesBotCommandTable = {
            {"login", HandleEchoesBotLogin, SEC_ADMINISTRATOR, Console::Yes},
            {"logout", HandleEchoesBotLogout, SEC_ADMINISTRATOR, Console::Yes},
            {"status", HandleEchoesBotStatus, SEC_ADMINISTRATOR, Console::Yes},
        };

        static ChatCommandTable echoesCommandTable = {
            {"bot", echoesBotCommandTable},
        };

        static ChatCommandTable commandTable = {
            {"echoes", echoesCommandTable},
        };

        return commandTable;
    }

    // .echoes bot login <guid|name>
    // Logs in exactly one named/GUID'd character via the existing Playerbots exact-login API.
    // Never touches random-bot population targets or the random-selection shuffle.
    // Uses the char const* args signature (not a typed-argument overload) - matching the exact,
    // already-proven convention every other command in this codebase's own
    // PlayerbotCommandScript.cpp uses, rather than introducing an unverified handler style.
    static bool HandleEchoesBotLogin(ChatHandler* handler, char const* args)
    {
        std::string token = Trim(args);
        if (token.empty())
        {
            handler->PSendSysMessage("Usage: .echoes bot login <guid|name>");
            return true;
        }

        if (!EchoesConfig::instance()->testHarnessEnabled)
        {
            handler->PSendSysMessage("Echoes test harness is disabled (EchoesPlayerbots.TestHarness.Enable=0).");
            return true;
        }

        if (sWorld->IsShuttingDown())
        {
            handler->PSendSysMessage("Refused: worldserver shutdown in progress.");
            return true;
        }

        ObjectGuid guid = ResolveCharacterGuid(token);
        if (guid.IsEmpty())
        {
            handler->PSendSysMessage("Refused: '{}' did not resolve to an existing character.", token);
            return true;
        }

        // "Bot-eligible" here just means a real account row was found - AddPlayerBot's own
        // IsInWorld()/session guards are the real safety net against hijacking a live human
        // session; this is only a friendlier up-front error message.
        uint32 accountId = sCharacterCache->GetCharacterAccountIdByGuid(guid);
        if (accountId == 0)
        {
            handler->PSendSysMessage("Refused: could not resolve an account for this character.");
            return true;
        }

        // Already-online check, reported explicitly rather than silently no-op'd, so an
        // administrator always gets an unambiguous answer about what the command actually did.
        if (Player* already = sRandomPlayerbotMgr.GetPlayerBot(guid))
        {
            handler->PSendSysMessage("'{}' (guid {}) is already online.", already->GetName(), guid.GetCounter());
            return true;
        }

        // masterAccountId=0 - treated as a random-bot-style addition by AddPlayerBot's own logic
        // (isRndbot = !masterAccountId), which is the unconditionally-allowed path, matching this
        // harness's own purpose exactly: deterministic addition of a bot character, not
        // master-controlled party-bot summoning.
        sRandomPlayerbotMgr.AddPlayerBot(guid, 0);

        LOG_INFO("module", "[EchoesTestHarness] login requested by administrator, guid={} token='{}'",
            guid.GetCounter(), token);
        handler->PSendSysMessage("Login requested for guid {} ('{}'). Use '.echoes bot status {}' to confirm "
            "readiness (login is deferred/asynchronous - it will not be immediate).",
            guid.GetCounter(), token, token);
        return true;
    }

    // .echoes bot logout <guid|name>
    // Logs out exactly one named/GUID'd character. Never affects any other online bot.
    static bool HandleEchoesBotLogout(ChatHandler* handler, char const* args)
    {
        std::string token = Trim(args);
        if (token.empty())
        {
            handler->PSendSysMessage("Usage: .echoes bot logout <guid|name>");
            return true;
        }

        if (!EchoesConfig::instance()->testHarnessEnabled)
        {
            handler->PSendSysMessage("Echoes test harness is disabled (EchoesPlayerbots.TestHarness.Enable=0).");
            return true;
        }

        ObjectGuid guid = ResolveCharacterGuid(token);
        if (guid.IsEmpty())
        {
            handler->PSendSysMessage("Refused: '{}' did not resolve to an existing character.", token);
            return true;
        }

        if (!sRandomPlayerbotMgr.GetPlayerBot(guid))
        {
            handler->PSendSysMessage("'{}' (guid {}) is already offline - nothing to do.", token, guid.GetCounter());
            return true;
        }

        sRandomPlayerbotMgr.LogoutPlayerBot(guid);
        LOG_INFO("module", "[EchoesTestHarness] logout requested by administrator, guid={} token='{}'",
            guid.GetCounter(), token);
        handler->PSendSysMessage("Logout requested for guid {} ('{}').", guid.GetCounter(), token);
        return true;
    }

    // .echoes bot status <guid|name>
    // Read-only. Reports online/offline and, if online, whether the Playerbots AI object has
    // attached yet - the exact readiness signal E2j1 Stage 10 already established as the correct
    // one (GET_PLAYERBOT_AI reads false for the first ~1500ms after login by design).
    static bool HandleEchoesBotStatus(ChatHandler* handler, char const* args)
    {
        std::string token = Trim(args);
        if (token.empty())
        {
            handler->PSendSysMessage("Usage: .echoes bot status <guid|name>");
            return true;
        }

        ObjectGuid guid = ResolveCharacterGuid(token);
        if (guid.IsEmpty())
        {
            handler->PSendSysMessage("'{}' did not resolve to an existing character.", token);
            return true;
        }

        Player* bot = sRandomPlayerbotMgr.GetPlayerBot(guid);
        if (!bot)
        {
            handler->PSendSysMessage("guid {} ('{}'): offline.", guid.GetCounter(), token);
            return true;
        }

        bool aiAttached = GET_PLAYERBOT_AI(bot) != nullptr;
        handler->PSendSysMessage("guid {} ('{}'): online, AI attached={}, map={}.",
            guid.GetCounter(), bot->GetName(), aiAttached ? "yes" : "no", bot->GetMapId());
        return true;
    }
};

void AddSC_EchoesTestHarnessCommandScript()
{
    new echoes_test_harness_commandscript();
}

#else // !MOD_PLAYERBOTS

// Playerbots is absent - there is no bot login/logout machinery for this harness to drive, so
// register nothing. This is the correct "feature does not exist" behavior, not a stub of any
// real command logic - no ChatCommandTable is ever built or registered in this configuration.
void AddSC_EchoesTestHarnessCommandScript()
{
}

#endif // MOD_PLAYERBOTS
