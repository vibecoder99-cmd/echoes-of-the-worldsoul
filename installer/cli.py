#!/usr/bin/env python3
# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""Echoes of the Worldsoul installer CLI.

Command surface: install, verify, upgrade, repair, uninstall, client-package.
This file is the ONLY entry point either wrapper (installer/bin/echoes.sh,
installer/bin/echoes.ps1) invokes -- neither wrapper duplicates any
argument-parsing or decision logic found here.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from core import client_package, discovery, install, prereq, repair, uninstall, upgrade, verify


def _mysql_args(args):
    out = ["-u", args.mysql_user, "-h", args.mysql_host, "-P", str(args.mysql_port)]
    if args.mysql_password:
        out += [f"-p{args.mysql_password}"]
    return out


def _install_opts(args):
    return install.InstallOptions(
        azerothcore_root=args.azerothcore_root,
        mysql_args=_mysql_args(args),
        characters_database=args.characters_database,
        world_database=args.world_database,
        client_root=args.client_root,
        vanilla_dbc_path=args.vanilla_dbc_path,
        enable_playerbots_integration=args.with_playerbots,
        confirm_playerbots_compatible=args.confirm_playerbots_compatible,
        lua_root=args.lua_root,
        config_root=args.config_root,
    )


def cmd_install(args):
    m = install.install(_install_opts(args))
    print(json.dumps(m, indent=2))
    return 0


def cmd_verify(args):
    mysql_args = _mysql_args(args) if args.characters_database else None
    checks = verify.verify(args.azerothcore_root, mysql_args, args.characters_database)
    worst = verify.PASS
    for c in checks:
        print(repr(c))
        if c.status == verify.FAIL:
            worst = verify.FAIL
        elif c.status == verify.WARN and worst != verify.FAIL:
            worst = verify.WARN
    print(f"\nOverall: {worst}")
    return 0 if worst != verify.FAIL else 1


def cmd_discover(args):
    if args.azerothcore_root:
        info = discovery.describe_azerothcore_root(args.azerothcore_root)
        print("AzerothCore root:", json.dumps(info, indent=2))
        ale = prereq.check_mod_ale(args.azerothcore_root)
        print(repr(ale), ale.remediation or "")
        if info["looks_like_split_dml_layout"]:
            print(
                "\nDetected split DML-style runtime layout (modules/ at this "
                "root, but lua_scripts/ and etc/modules/ live under env/dist/ "
                "instead of directly here).\n"
                "Suggested:\n"
                f"  --azerothcore-root {args.azerothcore_root}\n"
                f"  --lua-root {info['suggested_lua_root']}\n"
                f"  --config-root {info['suggested_config_root']}\n"
                "This is a suggestion only -- pass the explicit flags yourself "
                "to act on it; nothing here changes anything."
            )
    if args.client_root:
        print("Client root:", json.dumps(discovery.describe_client_root(args.client_root), indent=2))
    return 0


def cmd_client_package(args):
    result = client_package.build(args.output_dir, args.vanilla_dbc_path)
    print(json.dumps({k: v for k, v in result.items() if k != "addon_files"}, indent=2))
    print(f"({len(result['addon_files'])} AddOn files packaged)")
    return 0


def cmd_upgrade(args):
    result = upgrade.upgrade(_install_opts(args), args.target_version)
    print(json.dumps(
        {k: v for k, v in result.items() if k != "manifest"},
        indent=2,
    ))
    return 0


def cmd_repair(args):
    report = repair.repair(args.azerothcore_root, restore_mismatched=args.restore_mismatched)
    print(json.dumps(report.as_dict(), indent=2))
    return 0


def cmd_uninstall(args):
    report = uninstall.uninstall(args.azerothcore_root)
    print(json.dumps({
        "removed": report.removed,
        "skipped_hash_mismatch": report.skipped_hash_mismatch,
        "skipped_unsafe": report.skipped_unsafe,
        "skipped_missing": report.skipped_missing,
        "database_action": report.database_action,
    }, indent=2))
    return 0


def build_parser():
    p = argparse.ArgumentParser(
        prog="echoes",
        description=(
            "Echoes of the Worldsoul installer -- manages the server-side "
            "install for an existing AzerothCore checkout. See INSTALL.md "
            "for the full walkthrough, or PLAYER_SETUP.md if you're joining "
            "someone else's server rather than running your own."
        ),
    )
    sub = p.add_subparsers(dest="command", required=True, metavar="command")

    def add_common_ac(sp):
        sp.add_argument(
            "--azerothcore-root", required=True,
            help="Path to your existing AzerothCore source checkout (the "
                 "directory containing modules/, not a fresh empty folder -- "
                 "this installer layers Echoes onto AzerothCore, it does not "
                 "set AzerothCore up).",
        )

    def add_common_mysql(sp):
        sp.add_argument("--mysql-user", default="root", help="MySQL/MariaDB user with CREATE TABLE/INSERT privileges on the databases below.")
        sp.add_argument("--mysql-password", default="", help="Password for --mysql-user. Leave unset if your MySQL user has no password.")
        sp.add_argument("--mysql-host", default="127.0.0.1", help="MySQL/MariaDB host. Defaults to localhost.")
        sp.add_argument("--mysql-port", type=int, default=3306, help="MySQL/MariaDB port. Defaults to 3306.")
        sp.add_argument("--characters-database", default="acore_characters", help="Name of your existing AzerothCore characters database.")
        sp.add_argument("--world-database", default="acore_world", help="Name of your existing AzerothCore world database.")

    def add_install_like(sp):
        add_common_ac(sp)
        add_common_mysql(sp)
        sp.add_argument(
            "--lua-root", default=None,
            help="Root containing the live lua_scripts/ directory, if different "
                 "from --azerothcore-root (e.g. a Docker/DML-style deployment's "
                 "env/dist/ runtime distribution root). Defaults to "
                 "--azerothcore-root, which is correct for a traditional "
                 "bare-metal AzerothCore checkout where modules/, lua_scripts/, "
                 "and etc/ all live together. Run 'echoes discover' first if "
                 "unsure -- it flags this split-layout case automatically.",
        )
        sp.add_argument(
            "--config-root", default=None,
            help="Root containing the live etc/modules/ directory, if different "
                 "from --azerothcore-root. Same split-Docker-layout rationale as "
                 "--lua-root; defaults to --azerothcore-root.",
        )
        sp.add_argument(
            "--client-root", default=None,
            help="Path to a clean, compatible WoW 3.3.5a (build 12340) client "
                 "install. Optional -- omit it to install the server side only "
                 "and handle client-patch packaging later.",
        )
        sp.add_argument(
            "--vanilla-dbc-path", default=None,
            help="Path to a manually-extracted, unmodified DBFilesClient\\Item.dbc. "
                 "Only needed if automatic extraction from --client-root fails "
                 "(a known limitation with some client archive formats -- see "
                 "the Fresh-Client Item.dbc Note in README.md).",
        )
        sp.add_argument(
            "--with-playerbots", action="store_true",
            help="Also copy the optional mod-echoes-playerbots module. Safe even "
                 "if you don't run Playerbots -- it compiles to a no-op without "
                 "it. Does not by itself enable the integration; see "
                 "--confirm-playerbots-compatible.",
        )
        sp.add_argument(
            "--confirm-playerbots-compatible", action="store_true",
            help="Explicitly confirm you have verified Playerbots compatibility "
                 "yourself; only then does this flip EchoesPlayerbots.Enable=1. "
                 "Never inferred from mod-playerbots merely being present.",
        )
        # No --force-mpq-overwrite: a patch-E.MPQ collision with a
        # non-Echoes-owned file is always blocked in the ordinary install
        # path -- see installer/core/mpq_conflict.py.

    sp = sub.add_parser(
        "install",
        help="Fresh install: copy the C++ modules, apply SQL, deploy Lua "
             "scripts, and (if --client-root is given) build patch-E.MPQ.",
    )
    add_install_like(sp)
    sp.set_defaults(func=cmd_install)

    sp = sub.add_parser(
        "verify",
        help="Check an existing install against its recorded manifest -- "
             "confirms nothing installer-managed is missing or modified.",
    )
    add_common_ac(sp)
    sp.add_argument("--mysql-user", default="root", help="MySQL/MariaDB user (only needed if --characters-database is set).")
    sp.add_argument("--mysql-password", default="", help="Password for --mysql-user.")
    sp.add_argument("--mysql-host", default="127.0.0.1", help="MySQL/MariaDB host. Defaults to localhost.")
    sp.add_argument("--mysql-port", type=int, default=3306, help="MySQL/MariaDB port. Defaults to 3306.")
    sp.add_argument(
        "--characters-database", default=None,
        help="Also check the characters database's schema version. Omit to "
             "verify installed files only, without a database connection.",
    )
    sp.set_defaults(func=cmd_verify)

    sp = sub.add_parser(
        "discover",
        help="Inspect an AzerothCore checkout and/or WoW client and report "
             "what the installer sees -- run this first if you're unsure "
             "what flags to use, especially for Docker/DML-style layouts.",
    )
    sp.add_argument("--azerothcore-root", default=None, help="AzerothCore checkout to inspect.")
    sp.add_argument("--client-root", default=None, help="WoW client install to inspect.")
    sp.set_defaults(func=cmd_discover)

    sp = sub.add_parser(
        "client-package",
        help="Build the small AddOn + patch-E.MPQ bundle to hand to players "
             "-- run this after install/upgrade, once you have a built "
             "patch-E.MPQ to package.",
    )
    sp.add_argument("--output-dir", required=True, help="Directory to write the player-ready package into.")
    sp.add_argument(
        "--vanilla-dbc-path", default=None,
        help="Path to a manually-extracted, unmodified Item.dbc, if you don't "
             "already have a built patch-E.MPQ to package from an install.",
    )
    sp.set_defaults(func=cmd_client_package)

    sp = sub.add_parser(
        "upgrade",
        help="Update an existing installer-managed install (or adopt a "
             "pre-installer legacy install) to a newer Echoes package.",
    )
    add_install_like(sp)
    sp.add_argument("--target-version", required=True, help="Version string to record as installed, e.g. 2.1.0.")
    sp.set_defaults(func=cmd_upgrade)

    sp = sub.add_parser(
        "repair",
        help="Restore any installer-owned file that's missing (always) or "
             "modified (with --restore-mismatched) from the current package.",
    )
    add_common_ac(sp)
    sp.add_argument(
        "--restore-mismatched", action="store_true",
        help="Also overwrite files whose hash differs from the manifest's "
             "recorded value, not just missing ones. Off by default -- a "
             "changed file may be intentional operator customization.",
    )
    sp.set_defaults(func=cmd_repair)

    sp = sub.add_parser(
        "uninstall",
        help="Remove Echoes-owned files. Database tables are always retained.",
    )
    add_common_ac(sp)
    sp.set_defaults(func=cmd_uninstall)

    return p


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
