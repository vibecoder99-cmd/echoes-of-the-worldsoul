#include "EchoesStatsConfig.h"
#include "Config.h"

void EchoesStatsConfig::Load()
{
    enabled = sConfigMgr->GetOption<bool>("EchoesStats.Enable", false);
    masteryBaseAbsorb = sConfigMgr->GetOption<float>("EchoesStats.MasteryBaseAbsorb", 0.05f);
    masteryMaxAbsorb = sConfigMgr->GetOption<float>("EchoesStats.MasteryMaxAbsorb", 0.80f);
    masteryDecayK = sConfigMgr->GetOption<float>("EchoesStats.MasteryDecayK", 0.038f);
}
