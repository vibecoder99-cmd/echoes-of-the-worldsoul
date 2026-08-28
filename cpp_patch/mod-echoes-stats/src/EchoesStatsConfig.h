#ifndef MODULE_ECHOES_STATS_CONFIG_H
#define MODULE_ECHOES_STATS_CONFIG_H

// E2j3: separate, standalone module - not part of mod-echoes-playerbots (see the phase's
// explicit architectural rule that general Echoes stat logic must not live in the Playerbots
// integration module). Applies to humans and bots identically; has no Playerbots dependency.
struct EchoesStatsConfig
{
    // Master switch. Default OFF - opt-in, matching every other Echoes module's convention.
    bool enabled = false;

    // ap_core.lua's authoritative constants, reproduced exactly (see EchoesStatsCalculator.h's
    // header comment for the source citation). Kept as config, not hardcoded literals, so a
    // future Lua-side tuning change can be mirrored here without a code change - but the
    // DEFAULT values below are not independently chosen, they are copied from ap_core.lua.
    double masteryBaseAbsorb = 0.05;
    double masteryMaxAbsorb = 0.80;
    double masteryDecayK = 0.038;

    static EchoesStatsConfig* instance()
    {
        static EchoesStatsConfig cfg;
        return &cfg;
    }

    void Load();
};

#endif
