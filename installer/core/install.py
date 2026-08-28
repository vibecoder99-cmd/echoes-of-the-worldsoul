# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""`echoes install` -- fresh install / re-run-safe install of Echoes Core,
optional Playerbots integration, optional Client Companion, optional
Patch-4.MPQ.

Component model (per the E2j16 release-gate resolution):
  CORE REQUIRED     -- Lua scripts, mod-echoes-stats, SQL package.
                       (mod-ale is an external prerequisite, checked not installed.)
  PLAYERBOTS OPTIONAL -- mod-echoes-playerbots, only copied if the caller
                       opts in AND mod-playerbots is detected. Never
                       enabled (EchoesPlayerbots.Enable) without an
                       explicit, positive compatibility decision by the
                       caller -- this module never auto-enables it.
  CLIENT RECOMMENDED -- Client Companion AddOn + Patch-4.MPQ, only if a
                       client_root is supplied.
"""

import datetime
import os
import shutil

from . import backup, config, discovery, hashing, manifest as manifest_mod
from . import mpq_build, mpq_conflict, prereq, sql_runner


def _repo_root():
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def _now_iso():
    # Filesystem-safe timestamp (no colons) -- matches this project's own
    # established env/backups/<phase>/<timestamp>/ convention
    # (e.g. 20260715T184148-0700) and, unlike a literal ISO-8601 string,
    # works as a directory-name component on Windows as well as Linux/WSL.
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


class InstallOptions:
    def __init__(
        self,
        azerothcore_root,
        mysql_args,
        characters_database,
        world_database,
        client_root=None,
        vanilla_dbc_path=None,
        enable_playerbots_integration=False,
        force_mpq_overwrite=False,
    ):
        self.azerothcore_root = azerothcore_root
        self.mysql_args = mysql_args
        self.characters_database = characters_database
        self.world_database = world_database
        self.client_root = client_root
        self.vanilla_dbc_path = vanilla_dbc_path
        self.enable_playerbots_integration = enable_playerbots_integration
        self.force_mpq_overwrite = force_mpq_overwrite


def install(opts):
    """Returns the final manifest dict. Raises on any step that should
    stop the install rather than silently continuing (per the standing
    instruction: 'core installation should fail visibly rather than
    appear successful with missing gameplay effects')."""
    timestamp = _now_iso()
    repo_root = _repo_root()

    ac_info = discovery.describe_azerothcore_root(opts.azerothcore_root)
    if not ac_info["has_modules_dir"]:
        raise RuntimeError(
            f"{opts.azerothcore_root} does not look like an AzerothCore root "
            "(no modules/ directory found). Refusing to guess -- pass the "
            "correct --azerothcore-root."
        )

    ale = prereq.check_mod_ale(opts.azerothcore_root)
    if not ale.present:
        raise RuntimeError(ale.remediation)

    m = manifest_mod.load(opts.azerothcore_root) or manifest_mod.default_manifest()
    m["azerothcore_root"] = opts.azerothcore_root
    m["installed_at"] = m["installed_at"] or timestamp

    backups_root = os.path.join(opts.azerothcore_root, "echoes-installer-backups")

    # --- CORE: Lua scripts ---
    lua_src = os.path.join(repo_root, "lua_scripts")
    lua_dst = os.path.join(opts.azerothcore_root, "lua_scripts")
    if os.path.isdir(lua_dst):
        b = backup.backup_tree(lua_dst, backups_root, timestamp, "lua_scripts")
        if b:
            manifest_mod.record_backup(m, timestamp, "lua_scripts", b, lua_dst)
    os.makedirs(lua_dst, exist_ok=True)
    for name in os.listdir(lua_src):
        shutil.copy2(os.path.join(lua_src, name), os.path.join(lua_dst, name))
    m["components"]["core_lua"] = {
        "enabled": True,
        "files": hashing.sha256_tree(lua_dst),
        "installed_at": timestamp,
    }

    # --- CORE: mod-echoes-stats ---
    stats_src = os.path.join(repo_root, "cpp_patch", "mod-echoes-stats")
    stats_dst = os.path.join(opts.azerothcore_root, "modules", "mod-echoes-stats")
    if os.path.isdir(stats_dst):
        b = backup.backup_tree(stats_dst, backups_root, timestamp, "mod-echoes-stats")
        if b:
            manifest_mod.record_backup(m, timestamp, "mod-echoes-stats", b, stats_dst)
        shutil.rmtree(stats_dst)
    shutil.copytree(stats_src, stats_dst)
    conf_result = config.materialize(
        os.path.join(stats_dst, "conf", "mod_echoes_stats.conf.dist"),
        os.path.join(opts.azerothcore_root, "etc", "modules", "mod_echoes_stats.conf"),
        overrides={"EchoesStats.Enable": "1"},
    )
    m["config_ownership"]["mod_echoes_stats.conf"] = "installer-managed"
    m["components"]["mod_echoes_stats"] = {
        "enabled": True,
        "files": hashing.sha256_tree(stats_dst),
        "installed_at": timestamp,
        "config_action": conf_result["action"],
    }

    # --- OPTIONAL: Playerbots integration ---
    if opts.enable_playerbots_integration:
        if not ac_info["has_mod_playerbots"]:
            m["playerbots_integration"] = {
                "detected_present": False,
                "compatibility_confirmed": False,
                "enabled": False,
                "reason": "mod-playerbots not present; integration skipped, core install unaffected",
            }
        else:
            pb_src = os.path.join(repo_root, "cpp_patch", "mod-echoes-playerbots")
            pb_dst = os.path.join(opts.azerothcore_root, "modules", "mod-echoes-playerbots")
            if os.path.isdir(pb_dst):
                b = backup.backup_tree(pb_dst, backups_root, timestamp, "mod-echoes-playerbots")
                if b:
                    manifest_mod.record_backup(m, timestamp, "mod-echoes-playerbots", b, pb_dst)
                shutil.rmtree(pb_dst)
            shutil.copytree(pb_src, pb_dst)
            # Compatibility is proven by the schema version prefix match at
            # RUNTIME (EchoesPresence.cpp), not by this installer -- this
            # installer copies the module and leaves it DISABLED by
            # default. Auto-enabling requires the caller to have already
            # confirmed compatibility (opts.enable_playerbots_integration
            # is the caller's explicit opt-in, not proof of compatibility)
            # -- so this installer copies the module but does NOT flip
            # EchoesPlayerbots.Enable on its own. See Part B of the
            # governing checkpoint: never auto-enable without a positive
            # compatibility decision.
            config.materialize(
                os.path.join(pb_dst, "conf", "mod_echoes_playerbots.conf.dist"),
                os.path.join(opts.azerothcore_root, "etc", "modules", "mod_echoes_playerbots.conf"),
                overrides={"EchoesPlayerbots.Enable": "0"},
            )
            m["config_ownership"]["mod_echoes_playerbots.conf"] = "installer-managed"
            m["components"]["mod_echoes_playerbots"] = {
                "enabled": True,
                "files": hashing.sha256_tree(pb_dst),
                "installed_at": timestamp,
            }
            m["playerbots_integration"] = {
                "detected_present": True,
                "compatibility_confirmed": False,
                "enabled": False,
                "reason": "module installed; EchoesPlayerbots.Enable left at 0 -- "
                          "operator must confirm compatibility and enable explicitly",
            }
    else:
        m["playerbots_integration"] = {
            "detected_present": ac_info["has_mod_playerbots"],
            "compatibility_confirmed": False,
            "enabled": False,
            "reason": "Playerbots integration not requested for this install",
        }

    # --- CORE: SQL ---
    applied_schema = sql_runner.apply_schema_package(opts.mysql_args, opts.characters_database)
    applied_world = sql_runner.apply_world_items(opts.mysql_args, opts.world_database)
    m["sql"] = {
        "schema_files_applied": applied_schema,
        "world_files_applied": applied_world,
        "applied_at": timestamp,
    }

    # --- RECOMMENDED: Client Companion + Patch-4.MPQ ---
    if opts.client_root:
        client_info = discovery.describe_client_root(opts.client_root)
        if not client_info["looks_like_compatible_335a_client"]:
            raise RuntimeError(
                f"{opts.client_root} does not look like a compatible 3.3.5a client "
                "(missing Wow.exe or Data/common.MPQ). Refusing to guess -- pass "
                "the correct --client-root, or omit it to skip client install."
            )

        addon_src = os.path.join(repo_root, "client_addon", "EchoesOfTheWorldsoulBridge")
        addon_dst = os.path.join(opts.client_root, "Interface", "AddOns", "EchoesOfTheWorldsoulBridge")
        if os.path.isdir(addon_dst):
            b = backup.backup_tree(addon_dst, backups_root, timestamp, "client_companion")
            if b:
                manifest_mod.record_backup(m, timestamp, "client_companion", b, addon_dst)
            shutil.rmtree(addon_dst)
        shutil.copytree(addon_src, addon_dst)
        m["client_root"] = opts.client_root
        m["components"]["client_companion"] = {
            "enabled": True,
            "files": hashing.sha256_tree(addon_dst),
            "installed_at": timestamp,
        }

        # Patch-4.MPQ
        vanilla_bytes = None
        vanilla_source = None
        if opts.vanilla_dbc_path:
            with open(opts.vanilla_dbc_path, "rb") as f:
                vanilla_bytes = f.read()
            vanilla_source = f"user-supplied: {opts.vanilla_dbc_path}"
        else:
            vanilla_bytes, archive_name, err = mpq_build.try_extract_vanilla_item_dbc(opts.client_root)
            if vanilla_bytes is None:
                raise RuntimeError(
                    "Could not automatically extract a vanilla Item.dbc from "
                    f"{opts.client_root}'s own stock archives ({err}). Supply one "
                    "explicitly with --vanilla-dbc-path."
                )
            vanilla_source = f"extracted from client's {archive_name}"

        existing_patch4 = client_info["existing_patch4_mpq"]
        existing_sha = hashing.sha256_file(existing_patch4) if existing_patch4 else None
        recorded_sha = m.get("patch_mpq", {}).get("sha256")
        resolution = mpq_conflict.resolve(existing_sha, recorded_sha, opts.force_mpq_overwrite)

        if resolution == mpq_conflict.MpqConflictResolution.EXISTING_IS_THIRD_PARTY_BLOCKED:
            raise RuntimeError(
                f"{existing_patch4} already exists and is not recorded as an "
                "Echoes-generated file. Refusing to overwrite silently -- pass "
                "--force-mpq-overwrite to replace it (it will be backed up first), "
                "or install without --client-root and package the MPQ separately "
                "under an alternate patch-<letter>.MPQ name."
            )

        if existing_patch4:
            b = backup.backup_path(existing_patch4, backups_root, timestamp, "patch-4-mpq")
            if b:
                manifest_mod.record_backup(m, timestamp, "patch-4-mpq", b, existing_patch4)

        build_result = mpq_build.build(vanilla_bytes, os.path.join(backups_root, "mpq-build", timestamp))
        final_mpq_path = os.path.join(opts.client_root, "Data", "patch-4.MPQ")
        shutil.copy2(build_result["mpq_path"], final_mpq_path)

        m["patch_mpq"] = {
            "generated": True,
            "path": final_mpq_path,
            "sha256": hashing.sha256_file(final_mpq_path),
            "internal_files": build_result["internal_files"],
            "vanilla_dbc_sha256": build_result["vanilla_dbc_sha256"],
            "vanilla_dbc_provenance": vanilla_source,
        }

    manifest_mod.save(opts.azerothcore_root, m, timestamp)
    return m
