/*
 * mod-echoes-playerbots module loader.
 * Auto-discovered by modules/CMakeLists.txt (GetModuleSourceList): any
 * directory under modules/ containing a src/ subdirectory is picked up
 * automatically, with zero changes to any existing CMake file. The
 * generated static ModulesLoader.cpp calls
 * Add<directory-name-with-dashes-as-underscores>Scripts(), which for this
 * module's directory name "mod-echoes-playerbots" is exactly the function
 * below - confirmed against the existing mod-learn-spells / mod-aoe-loot
 * modules' own loader files during E2i2 Stage 2/3.
 */

void AddSC_EchoesPlayerbotsAwareness();
void AddSC_EchoesTestHarnessCommandScript();

void Addmod_echoes_playerbotsScripts()
{
    AddSC_EchoesPlayerbotsAwareness();
    AddSC_EchoesTestHarnessCommandScript();
}
