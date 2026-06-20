-- ============================================================
-- Echoes of the Worldsoul -- Boss Flash Message Database
-- Maps creature entry IDs to Dark Souls style flash messages
-- Format: [creatureId] = { title, subtitle }
-- Single-element tables { title } are shown without subtitle.
-- All strings ASCII only. No non-ASCII characters.
-- ============================================================

AP = AP or {}

AP.BossFlashMessages = {

    -- --------------------------------------------------------
    -- WOTLK: UTGARDE COMPLEX (Utgarde Keep + Utgarde Pinnacle)
    -- --------------------------------------------------------
    -- Utgarde Keep (map 574)
    [23953] = { "PRINCE KELESETH UNMADE",          "The vampire prince fades to shadow." },
    [24201] = { "SKARVALD AND DALRONN BROKEN",      "Flesh and bone both yield." },
    [23954] = { "INGVAR THE PLUNDERER FALLS",       "UTGARDE KEEP IS YOURS." },
    -- Utgarde Pinnacle (map 575)
    [26668] = { "SVALA SORROWGRAVE FREED",          "The Val'kyr's dark pact is severed." },
    [26687] = { "GORTOK PALEHOOF TOPPLED",          "The ancient magnataur is silenced." },
    [26693] = { "SKADI THE RUTHLESS GROUNDED",      "The proto-dragon rider falls." },
    [26861] = { "KING YMIRON DETHRONED",            "THE VRYKUL KING'S REIGN ENDS." },

    -- --------------------------------------------------------
    -- WOTLK: ICECROWN CITADEL
    -- --------------------------------------------------------
    [36612] = { "LORD MARROWGAR SILENCED",        "His bones return to Azeroth." },
    [36855] = { "LADY DEATHWHISPER UNMADE",       "Her whispers fade into silence." },
    [37813] = { "DEATHBRINGER SAURFANG FELLED",   "The blood stops flowing." },
    [36627] = { "ROTFACE DISSOLVED",              "The plague dies with him." },
    [36626] = { "FESTERGUT PURGED",               "The rot cannot claim you." },
    [36678] = { "PROFESSOR PUTRICIDE ENDED",      "His experiments conclude." },
    [37970] = { "THE BLOOD PRINCES FALL",         "Their dynasty ends here." },
    [37972] = { "THE BLOOD PRINCES FALL",         "Their dynasty ends here." },
    [37973] = { "THE BLOOD PRINCES FALL",         "Their dynasty ends here." },
    [37955] = { "BLOOD-QUEEN LANA'THEL SLAIN",   "The bloodline is broken." },
    [36789] = { "VALITHRIA DREAMWALKER FREED",    "A dragon breathes again." },
    [36853] = { "SINDRAGOSA SHATTERED",           "The Frost Queen's reign ends." },
    [36597] = { "THE LICH KING HAS FALLEN",       "DEATH ITSELF YIELDS TO YOU." },

    -- --------------------------------------------------------
    -- WOTLK: ULDUAR
    -- --------------------------------------------------------
    [33113] = { "FLAME LEVIATHAN DESTROYED",      "The titan's guardian is silenced." },
    [32930] = { "IGNIS THE FURNACE MASTER FALLS", "The forge grows cold." },
    [33186] = { "RAZORSCALE BROUGHT LOW",         "The skies are yours." },
    [33293] = { "XT-002 DECONSTRUCTOR UNDONE",    "The toy maker weeps no more." },
    [32867] = { "THE ASSEMBLY OF IRON BROKEN",    "The iron will bends." },
    [32865] = { "KOLOGARN TOPPLED",               "The great eye closes." },
    [33515] = { "AURIAYA SILENCED",               "The Keeper's vigil ends." },
    [32845] = { "HODIR STILLED",                  "The frost was not enough." },
    [32906] = { "THORIM HUMBLED",                 "The storm breaks." },
    [32814] = { "FREYA OVERCOME",                 "Nature itself yields." },
    [33350] = { "MIMIRON DISMANTLED",             "The machine falls quiet." },
    [33271] = { "GENERAL VEZAX SHATTERED",        "The general's corruption ends." },
    [33288] = { "YOGG-SARON IMPRISONED",          "THE OLD GOD'S DREAM ENDS." },
    [32871] = { "ALGALON THE OBSERVER SILENCED",  "THE STARS BEAR WITNESS." },

    -- --------------------------------------------------------
    -- WOTLK: NAXXRAMAS
    -- --------------------------------------------------------
    [15956] = { "ANUB'REKHAN FALLS",              "The crypt lord returns to dust." },
    [15953] = { "GRAND WIDOW FAERLINA SLAIN",     "Her followers scatter." },
    [15952] = { "MAEXXNA DESTROYED",              "The web unravels." },
    [15954] = { "NOTH THE PLAGUEBRINGER ENDED",   "The plague is checked." },
    [15936] = { "HEIGAN THE UNCLEAN PURGED",      "The dance is over." },
    [16011] = { "LOATHEB SLAIN",                  "The spores settle." },
    [16061] = { "INSTRUCTOR RAZUVIOUS FALLS",     "The lesson ends." },
    [16060] = { "GOTHIK THE HARVESTER REAPED",    "The harvester is harvested." },
    [16064] = { "THE FOUR HORSEMEN BROKEN",       "The riders fall." },
    [15931] = { "PATCHWERK DISMANTLED",           "The butcher bleeds out." },
    [15932] = { "GROBBULUS DISSOLVED",            "The slime recedes." },
    [15933] = { "GLUTH FELLED",                   "The dog of war is down." },
    [15928] = { "THADDIUS COLLAPSED",             "The charge dissipates." },
    [15989] = { "SAPPHIRON SHATTERED",            "The frost wyrm falls silent." },
    [15990] = { "KEL'THUZAD UNBOUND",             "NAXXRAMAS FALLS SILENT." },

    -- --------------------------------------------------------
    -- WOTLK: TRIAL OF THE CRUSADER
    -- --------------------------------------------------------
    [34796] = { "THE BEASTS OF NORTHREND SLAIN",  "The wilds are yours." },
    [34780] = { "LORD JARAXXUS BANISHED",         "The demon returns to the Nether." },
    [34496] = { "THE VAL'KYR TWINS FALL",         "Light and shadow yield to you." },
    [34497] = { "THE VAL'KYR TWINS FALL",         "Light and shadow yield to you." },
    [34564] = { "ANUB'ARAK DESTROYED",            "THE BETRAYER OF NATIONS IS NO MORE." },

    -- --------------------------------------------------------
    -- WOTLK: ONYXIA'S LAIR
    -- --------------------------------------------------------
    [10184] = { "ONYXIA SLAIN",                   "The brood mother falls." },

    -- --------------------------------------------------------
    -- WOTLK: EYE OF ETERNITY
    -- --------------------------------------------------------
    [28859] = { "MALYGOS UNBOUND",                "THE SPELL-WEAVER'S REIGN ENDS." },

    -- --------------------------------------------------------
    -- WOTLK: OBSIDIAN SANCTUM
    -- --------------------------------------------------------
    [28860] = { "SARTHARION FELLED",              "The obsidian fire is extinguished." },

    -- --------------------------------------------------------
    -- WOTLK: VAULT OF ARCHAVON
    -- --------------------------------------------------------
    [31125] = { "ARCHAVON TOPPLED",               "The vault is yours." },
    [33993] = { "EMALON UNCHAINED",               "The storm giant falls." },
    [35013] = { "KORALON EXTINGUISHED",           "The fire is yours to claim." },
    [38433] = { "TORAVON FROZEN",                 "The frost is silenced." },

    -- --------------------------------------------------------
    -- WOTLK: RUBY SANCTUM
    -- --------------------------------------------------------
    [39863] = { "HALION BROKEN",                  "THE TWILIGHT DESTROYER IS NO MORE." },

    -- --------------------------------------------------------
    -- TBC: KARAZHAN
    -- --------------------------------------------------------
    [15550] = { "ATTUMEN THE HUNTSMAN FALLS",     "The stables grow quiet." },
    [15687] = { "MOROES OVERCOME",                "The steward serves no more." },
    [16457] = { "THE MAIDEN OF VIRTUE SILENCED",  "Judgment has been rendered." },
    [17521] = { "THE BIG BAD WOLF SLAIN",         "The story ends." },
    [17533] = { "ROMULO AND JULIANNE ENDED",      "The tragedy concludes." },
    [15691] = { "THE CURATOR DISMANTLED",         "The archive falls silent." },
    [15688] = { "TERESTIAN ILLHOOF BANISHED",     "The demon's pact is broken." },
    [16524] = { "THE SHADE OF ARAN DISPERSED",    "The mage's spell ends." },
    [15689] = { "NETHERSPITE BOUND",              "The portal is sealed." },
    [15690] = { "PRINCE MALCHEZAAR SLAIN",        "KARAZHAN IS YOURS." },
    [17225] = { "NIGHTBANE BROUGHT LOW",          "The undead dragon is silenced." },

    -- --------------------------------------------------------
    -- TBC: GRUUL'S LAIR
    -- --------------------------------------------------------
    [18831] = { "HIGH KING MAULGAR FELLED",       "The ogre council breaks." },
    [19044] = { "GRUUL THE DRAGONKILLER SLAIN",   "THE DRAGONKILLER IS SLAIN." },

    -- --------------------------------------------------------
    -- TBC: MAGTHERIDON'S LAIR
    -- --------------------------------------------------------
    [17257] = { "MAGTHERIDON IMPRISONED",         "THE PIT LORD YIELDS TO YOU." },

    -- --------------------------------------------------------
    -- TBC: SERPENTSHRINE CAVERN
    -- --------------------------------------------------------
    [21216] = { "HYDROSS THE UNSTABLE PURIFIED",  "The tainted water stills." },
    [21217] = { "THE LURKER BELOW FELLED",        "The depths are yours." },
    [21215] = { "LEOTHERAS THE BLIND ENDED",      "The demon within is silenced." },
    [21213] = { "MOROGRIM TIDEWALKER TOPPLED",    "The tide giant falls." },
    [21214] = { "FATHOM-LORD KARATHRESS SLAIN",   "The naga fleet is broken." },
    [21212] = { "LADY VASHJ DESTROYED",           "THE SEA WITCH IS NO MORE." },

    -- --------------------------------------------------------
    -- TBC: THE EYE (TEMPEST KEEP)
    -- --------------------------------------------------------
    [19514] = { "AL'AR EXTINGUISHED",             "The phoenix's fire dies." },
    [19516] = { "VOID REAVER DISMANTLED",         "The machine falls silent." },
    [19622] = { "KAEL'THAS SUNSTRIDER BROKEN",   "THE SUN KING'S REIGN ENDS." },
    -- High Astromancer Solarian: verify entry ID before adding

    -- --------------------------------------------------------
    -- TBC: MOUNT HYJAL
    -- --------------------------------------------------------
    [17767] = { "RAGE WINTERCHILL ENDED",         "The frost retreats." },
    [17808] = { "ANETHERON BANISHED",             "The undead dreadlord falls." },
    [17888] = { "KAZ'ROGAL FALLS",               "The chaos lord is silenced." },
    [17842] = { "AZGALOR SLAIN",                  "The pit lord yields." },
    [17968] = { "ARCHIMONDE DESTROYED",           "THE DEFILER IS NO MORE." },

    -- --------------------------------------------------------
    -- TBC: BLACK TEMPLE
    -- --------------------------------------------------------
    [22887] = { "HIGH WARLORD NAJ'ENTUS FALLS",  "The naga warlord is silenced." },
    [22898] = { "SUPREMUS TOPPLED",              "The demon colossus falls." },
    [22841] = { "THE SHADE OF AKAMA FREED",      "Akama's soul is restored." },
    [22871] = { "TERON GOREFIEND ENDED",         "The death knight rests at last." },
    [22948] = { "GURTOGG BLOODBOIL SLAIN",       "The blood stops." },
    [23420] = { "THE RELIQUARY OF SOULS BROKEN", "The imprisoned spirits are freed." },
    [22947] = { "MOTHER SHAHRAZ FALLS",          "The eredar priestess is silenced." },
    [22949] = { "THE ILLIDARI COUNCIL BROKEN",   "The council is no more." },
    [22950] = { "THE ILLIDARI COUNCIL BROKEN",   "The council is no more." },
    [22951] = { "THE ILLIDARI COUNCIL BROKEN",   "The council is no more." },
    [22952] = { "THE ILLIDARI COUNCIL BROKEN",   "The council is no more." },
    [22917] = { "ILLIDAN STORMRAGE DEFEATED",    "YOU ARE NOT PREPARED -- BUT YOU PREVAILED." },

    -- --------------------------------------------------------
    -- TBC: SUNWELL PLATEAU
    -- --------------------------------------------------------
    [24850] = { "KALECGOS FREED",                "The dragon's torment ends." },
    [24882] = { "BRUTALLUS FALLS",               "The demon's rampage is over." },
    [25038] = { "FELMYST BROKEN",                "The plague wyrm is silenced." },
    [25165] = { "THE EREDAR TWINS SLAIN",        "Eredar sorcery yields to you." },
    [25166] = { "THE EREDAR TWINS SLAIN",        "Eredar sorcery yields to you." },
    [25741] = { "M'URU UNBOUND",                 "THE VOID WITHDRAWS." },
    [25315] = { "KIL'JAEDEN REPELLED",           "THE DECEIVER RETREATS INTO THE VOID." },

    -- --------------------------------------------------------
    -- VANILLA: MOLTEN CORE
    -- --------------------------------------------------------
    [12118] = { "LUCIFRON SILENCED",             "The core grows quieter." },
    [11982] = { "MAGMADAR SLAIN",                "The fire hound is felled." },
    [12259] = { "GEHENNAS PURGED",               "The flames fade." },
    [12057] = { "GARR DISMANTLED",               "The guardian falls." },
    [12056] = { "BARON GEDDON ENDED",            "The infernal colossus is still." },
    [12264] = { "SHAZZRAH UNBOUND",              "The arcane lord is no more." },
    [11988] = { "GOLEMAGG THE INCINERATOR FALLS","The lava retreats." },
    [12098] = { "SULFURON HARBINGER SLAIN",      "The flamewaker herald is silenced." },
    [12018] = { "MAJORDOMO EXECUTUS SURRENDERS", "He begs for mercy." },
    [11502] = { "RAGNAROS SUBDUED",              "THE FIRELORD YIELDS TO MORTAL WILL." },

    -- --------------------------------------------------------
    -- VANILLA: BLACKWING LAIR
    -- --------------------------------------------------------
    [12435] = { "RAZORGORE THE UNTAMED FALLS",   "The eggs are secured." },
    [13020] = { "VAELASTRASZ FREED",             "The dragon's corruption ends." },
    [12017] = { "BROODLORD LASHLAYER SLAIN",     "The lair's guardian falls." },
    [11983] = { "FIREMAW FELLED",                "The chromatic dragon is silenced." },
    [14601] = { "EBONROC DESTROYED",             "The shadow dragon falls." },
    [11981] = { "FLAMEGOR ENDED",                "The chromatic fire dies." },
    [14020] = { "CHROMAGGUS BROKEN",             "The time-twisted dragon yields." },
    [11583] = { "NEFARIAN SLAIN",                "THE BLACK DRAGON'S LEGACY ENDS." },

    -- --------------------------------------------------------
    -- VANILLA: ZUL'GURUB
    -- --------------------------------------------------------
    [14517] = { "HIGH PRIESTESS JEKLIK FALLS",   "The bat loa is silenced." },
    [14507] = { "HIGH PRIEST VENOXIS PURGED",    "The serpent loa retreats." },
    [14510] = { "HIGH PRIESTESS MAR'LI SLAIN",   "The spider loa is no more." },
    [14509] = { "HIGH PRIEST THEKAL FELLED",     "The tiger loa yields." },
    [14515] = { "HIGH PRIESTESS ARLOKK ENDED",   "The panther loa falls." },
    [11382] = { "BLOODLORD MANDOKIR DEFEATED",   "The blood troll chieftain falls." },
    [11380] = { "JIN'DO THE HEXXER UNBOUND",     "The hexxer's power breaks." },
    [15114] = { "GAHZ'RANKA SLAIN",             "The sea beast retreats to the deep." },
    [14834] = { "HAKKAR THE SOULFLAYER DEFEATED","THE SOULFLAYER'S CORRUPTION ENDS." },

    -- --------------------------------------------------------
    -- VANILLA: RUINS OF AHN'QIRAJ (AQ20)
    -- --------------------------------------------------------
    [15348] = { "KURINNAXX SLAIN" },
    [15341] = { "GENERAL RAJAXX FALLS",          "The army of the qiraji breaks." },
    [15340] = { "MOAM DISMANTLED" },
    [15370] = { "BURU THE GORGER FELLED" },
    [15369] = { "AYAMISS THE HUNTER SILENCED" },
    [15339] = { "OSSIRIAN THE UNSCARRED DEFEATED","THE UNSCARRED FALLS." },

    -- --------------------------------------------------------
    -- VANILLA: AHN'QIRAJ (AQ40)
    -- --------------------------------------------------------
    [15263] = { "THE PROPHET SKERAM SILENCED",   "The qiraji prophet is no more." },
    [15516] = { "BATTLEGUARD SARTURA FALLS",     "The qiraji guard breaks." },
    [15510] = { "FANKRISS THE UNYIELDING SLAIN", "The swarm retreats." },
    [15509] = { "PRINCESS HUHURAN PURGED",       "The wasp queen is felled." },
    [15299] = { "VISCIDUS SHATTERED",            "The ooze hardens no more." },
    [15543] = { "PRINCESS YAUJ SLAIN",           "The bug trio falls." },
    [15544] = { "VEM SLAIN",                     "The bug trio falls." },
    [15571] = { "MAWS SLAIN",                    "The bug trio falls." },
    [15276] = { "THE TWIN EMPERORS BROKEN",      "Vek'lor and Vek'nilash yield." },
    [15275] = { "THE TWIN EMPERORS BROKEN",      "Vek'lor and Vek'nilash yield." },
    [15517] = { "OURO BURIED",                   "The sandworm returns to the earth." },
    [15727] = { "C'THUN WOUNDED",                "THE OLD GOD STIRS BUT CANNOT RISE." },

    -- --------------------------------------------------------
    -- VANILLA: WORLD BOSSES
    -- --------------------------------------------------------
    [6109]  = { "AZUREGOS FALLS",                "The blue dragon concedes." },
    [12397] = { "LORD KAZZAK SLAIN",             "THE DOOM LORD'S MARCH IS HALTED." },
    [14889] = { "EMERISS CLEANSED",              "The nightmare fades." },
    [14888] = { "LETHON DEFEATED",               "The dream dragon is silenced." },
    [14890] = { "TAERAR UNBOUND",                "The shattered dragon falls." },
    [14887] = { "YSONDRE FREED",                 "The dream defender yields." },

    -- --------------------------------------------------------
    -- GENERIC FALLBACKS by boss rank
    -- --------------------------------------------------------
    ["dungeon_boss"]  = { "A CHAMPION HAS FALLEN",  "The Worldsoul stirs." },
    ["dungeon_final"] = { "THE DUNGEON FALLS",       "Its final guardian is no more." },
    ["raid_boss"]     = { "A LEGEND ENDS HERE",      "Your power grows immeasurable." },
    ["world_boss"]    = { "THE WORLD SHAKES",        "Even the mighty yield to you." },
}

-- ============================================================
-- AP.GetBossFlash
-- Looks up a flash message for a creature entry.
-- Returns the specific message, or a fallback based on context.
-- Returns nil for dungeon non-final bosses not in the table
-- (no flash shown for generic dungeon bosses).
-- ============================================================
function AP.GetBossFlash(creatureEntry, isBossRaid, isBossDungeonFinal)
    local flash = AP.BossFlashMessages[creatureEntry]
    if flash then return flash end
    if isBossRaid then
        return AP.BossFlashMessages["raid_boss"]
    elseif isBossDungeonFinal then
        return AP.BossFlashMessages["dungeon_final"]
    end
    return nil
end

-- ============================================================
-- ATTUNEMENT MILESTONE FLASHES (by attuned item count)
-- ============================================================
AP.AttunementFlashes = {
    [10]   = { "THE FIRST ECHO AWAKENS",          "Your journey has begun in earnest." },
    [25]   = { "AZEROTH REMEMBERS YOUR DEEDS",    "The Worldsoul takes note." },
    [50]   = { "THE WORLDSOUL TAKES NOTICE",      "You are more than you were." },
    [100]  = { "YOU ARE BEYOND WHAT YOU WERE",    "The echoes cannot be silenced." },
    [250]  = { "LEGENDS ARE MADE OF SUCH THINGS", "Few have walked this path." },
    [500]  = { "THE ECHOES CANNOT BE SILENCED",   "Azeroth itself bends to your will." },
    [1000] = { "A NEW FORCE WALKS AZEROTH",       "THE WORLDSOUL RESONATES WITH YOUR NAME." },
    [2000] = { "DEMIGOD",                         "YOU HAVE BECOME SOMETHING ETERNAL." },
}

-- ============================================================
-- CRUCIBLE INVESTMENT MILESTONE FLASHES (by total Essence invested)
-- Keys must align with AP.Visage.SecondaryTiers in ap_visage.lua
-- ============================================================
AP.CrucibleFlashes = {
    [100000]  = { "THE CRUCIBLE ACCEPTS YOUR OFFERING", "Your essence takes root." },
    [250000]  = { "THE FORGE GROWS HOT",                "Your investment bears weight." },
    [500000]  = { "YOUR POWER DEFIES UNDERSTANDING",    "Mortals cannot fathom what you are becoming." },
    [1000000] = { "THE WORLDSOUL ECHOES WITHIN YOU",    "You are the living proof of Azeroth's legacy." },
    [2000000] = { "THE CRUCIBLE IS YOURS",              "NOTHING IN AZEROTH CAN MATCH YOUR RESOLVE." },
}

print("[EotW] Boss flash message database loaded.")
