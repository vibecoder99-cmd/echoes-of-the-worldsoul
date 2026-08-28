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
        print("AzerothCore root:", json.dumps(discovery.describe_azerothcore_root(args.azerothcore_root), indent=2))
        ale = prereq.check_mod_ale(args.azerothcore_root)
        print(repr(ale), ale.remediation or "")
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
    p = argparse.ArgumentParser(prog="echoes", description="Echoes of the Worldsoul installer")
    sub = p.add_subparsers(dest="command", required=True)

    def add_common_ac(sp):
        sp.add_argument("--azerothcore-root", required=True)

    def add_common_mysql(sp):
        sp.add_argument("--mysql-user", default="root")
        sp.add_argument("--mysql-password", default="")
        sp.add_argument("--mysql-host", default="127.0.0.1")
        sp.add_argument("--mysql-port", type=int, default=3306)
        sp.add_argument("--characters-database", default="acore_characters")
        sp.add_argument("--world-database", default="acore_world")

    def add_install_like(sp):
        add_common_ac(sp)
        add_common_mysql(sp)
        sp.add_argument("--client-root", default=None)
        sp.add_argument("--vanilla-dbc-path", default=None)
        sp.add_argument("--with-playerbots", action="store_true")
        sp.add_argument(
            "--confirm-playerbots-compatible", action="store_true",
            help="Explicitly confirm you have verified Playerbots compatibility "
                 "yourself; only then does this flip EchoesPlayerbots.Enable=1. "
                 "Never inferred from mod-playerbots merely being present.",
        )
        # No --force-mpq-overwrite: a patch-E.MPQ collision with a
        # non-Echoes-owned file is always blocked in the ordinary install
        # path -- see installer/core/mpq_conflict.py.

    sp = sub.add_parser("install")
    add_install_like(sp)
    sp.set_defaults(func=cmd_install)

    sp = sub.add_parser("verify")
    add_common_ac(sp)
    sp.add_argument("--mysql-user", default="root")
    sp.add_argument("--mysql-password", default="")
    sp.add_argument("--mysql-host", default="127.0.0.1")
    sp.add_argument("--mysql-port", type=int, default=3306)
    sp.add_argument("--characters-database", default=None)
    sp.set_defaults(func=cmd_verify)

    sp = sub.add_parser("discover")
    sp.add_argument("--azerothcore-root", default=None)
    sp.add_argument("--client-root", default=None)
    sp.set_defaults(func=cmd_discover)

    sp = sub.add_parser("client-package")
    sp.add_argument("--output-dir", required=True)
    sp.add_argument("--vanilla-dbc-path", default=None)
    sp.set_defaults(func=cmd_client_package)

    sp = sub.add_parser("upgrade")
    add_install_like(sp)
    sp.add_argument("--target-version", required=True)
    sp.set_defaults(func=cmd_upgrade)

    sp = sub.add_parser("repair")
    add_common_ac(sp)
    sp.add_argument(
        "--restore-mismatched", action="store_true",
        help="Also overwrite files whose hash differs from the manifest's "
             "recorded value, not just missing ones. Off by default -- a "
             "changed file may be intentional operator customization.",
    )
    sp.set_defaults(func=cmd_repair)

    sp = sub.add_parser("uninstall")
    add_common_ac(sp)
    sp.set_defaults(func=cmd_uninstall)

    return p


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
