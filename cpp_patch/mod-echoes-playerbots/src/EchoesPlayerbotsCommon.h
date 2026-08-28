/*
 * mod-echoes-playerbots
 * Optional, fail-dormant Layer 1 (Awareness) integration between the Echoes
 * of the Worldsoul Lua package and mod-playerbots.
 *
 * This module never modifies mod-playerbots or AzerothCore core source.
 * It observes standard, unmodified AzerothCore PlayerScript/WorldScript
 * hooks and, only when both Playerbots and a compatible Echoes runtime are
 * confirmed present, applies one conservative rule: do not let a Playerbot
 * discard or replace meaningfully attuned equipped gear for a merely
 * marginal upgrade. See env/backups/e2i1/.../reports/e2i1-closure-report.md
 * for the full design this module implements.
 *
 * Licensed under the GNU General Public License v2, for compatibility with
 * mod-playerbots (GPLv2) which this module optionally interoperates with.
 * See LICENSE.md.
 */

#ifndef MODULE_ECHOES_PLAYERBOTS_COMMON_H
#define MODULE_ECHOES_PLAYERBOTS_COMMON_H

#include "Common.h"

#define ECHOES_PB_MODULE_STRING "mod-echoes-playerbots"

#endif
