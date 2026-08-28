# Copyright (C) 2025-2026 vibecoder99
# Licensed under the GNU General Public License v3.0 or later.
# See LICENSE for the full text.
"""`echoes install` -- fresh install / re-run-safe install of Echoes Core,
optional Playerbots integration, optional Client Companion, optional
patch-E.MPQ.

Component model (per the E2j16 release-gate resolution):
  CORE REQUIRED     -- Lua scripts, mod-echoes-stats, SQL package.
                       (mod-ale is an external prerequisite, checked not installed.)
  PLAYERBOTS OPTIONAL -- mod-echoes-playerbots, only copied if the caller
                       opts in AND mod-playerbots is detected. Never
                       enabled (EchoesPlayerbots.Enable) without an
                       explicit, positive compatibility decision by the
                       caller -- this module never auto-enables it.
  CLIENT RECOMMENDED -- Client Companion AddOn + patch-E.MPQ, only if a
                       client_root is supplied.

patch-E.MPQ (not the old patch-4.MPQ) is Echoes' reserved client-patch
slot -- see mpq_conflict.py's module docstring for the full rationale,
load-support evidence, and DBC merge-conflict caveat. If a prior
Echoes-owned patch-4.MPQ is detected (positively, by payload fingerprint,
never by filename alone), legacy_migration.py moves it forward
automatically as part of this same install; an unrelated patch-4.MPQ is
left completely untouched.
"""

import datetime
import os
import shutil

from . import backup, config, discovery, hashing, legacy_migration, legacy_retirement, manifest as manifest_mod
from . import mpq_build, mpq_conflict, prereq, sql_runner


def _repo_root():
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def _now_iso():
    # Filesystem-safe timestamp (no colons) -- matches this project's own
    # established env/backups/<phase>/<timestamp>/ convention
    # (e.g. 20260715T184148-0700) and, unlike a literal ISO-8601 string,
    # works as a directory-name component on Windows as well as Linux/WSL.
    # Microsecond precision (not just seconds): two install() calls that
    # both need to back up the same component (e.g. two Playerbots-config
    # installs run back-to-back) can otherwise land on the identical
    # second and collide on the identical backup directory name --
    # shutil.copytree refuses to write into an already-existing directory,
    # so the second call's backup step raises FileExistsError. Caught by
    # this installer's own test suite running two installs in quick
    # succession.
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")


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
        confirm_playerbots_compatible=False,
    ):
        self.azerothcore_root = azerothcore_root
        self.mysql_args = mysql_args
        self.characters_database = characters_database
        self.world_database = world_database
        self.client_root = client_root
        self.vanilla_dbc_path = vanilla_dbc_path
        self.enable_playerbots_integration = enable_playerbots_integration
        # A separate, explicit flag from enable_playerbots_integration
        # (which only copies the module) -- this one actually flips
        # EchoesPlayerbots.Enable=1. Must never be inferred from
        # mod-playerbots merely being present; it exists so an operator
        # (or a documented upgrade step, once they've verified
        # compatibility themselves) can make that decision deliberately.
        # This installer never sets it to True on its own.
        self.confirm_playerbots_compatible = confirm_playerbots_compatible
        # No force-overwrite option: patch-E.MPQ collisions with a
        # non-Echoes-owned file are always blocked in the ordinary path --
        # see mpq_conflict.py.


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

    def checkpoint():
        # Saved after every major step, not just once at the end -- if a
        # later step raises (e.g. the SQL step hits a bad connection),
        # the manifest still accurately reflects every component that
        # DID get copied, so verify()/repair() have something real to
        # work from instead of "no manifest, nothing installed" while
        # files actually sit on disk.
        manifest_mod.save(opts.azerothcore_root, m, timestamp)

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

    # Retire historical Echoes-owned Lua files that a real prior public
    # release may have installed (e.g. ap_gm_aether.lua from v1.6.0-rc1)
    # but current source no longer ships. Positive-identity-gated -- see
    # legacy_retirement.py. Runs on every install/upgrade call, not just
    # a dedicated "upgrade" path, since a fresh install target is never
    # going to match these signatures anyway.
    retired_lua, unproven_lua = legacy_retirement.retire_legacy_lua(
        lua_dst, backups_root, timestamp, m
    )
    m["legacy_retirement"] = m.get("legacy_retirement", {})
    m["legacy_retirement"]["lua"] = {"retired": retired_lua, "left_unproven": unproven_lua}
    m["components"]["core_lua"]["files"] = hashing.sha256_tree(lua_dst)
    checkpoint()

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
    checkpoint()

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
            # A caller who has independently confirmed compatibility (e.g.
            # checked the running schema version themselves) may pass
            # confirm_playerbots_compatible=True to flip the switch on in
            # the same install call. Absent that explicit confirmation,
            # the module is copied but left disabled -- never inferred
            # from mere presence of mod-playerbots.
            enable_value = "1" if opts.confirm_playerbots_compatible else "0"
            config.materialize(
                os.path.join(pb_dst, "conf", "mod_echoes_playerbots.conf.dist"),
                os.path.join(opts.azerothcore_root, "etc", "modules", "mod_echoes_playerbots.conf"),
                overrides={"EchoesPlayerbots.Enable": enable_value},
            )
            m["config_ownership"]["mod_echoes_playerbots.conf"] = "installer-managed"
            m["components"]["mod_echoes_playerbots"] = {
                "enabled": True,
                "files": hashing.sha256_tree(pb_dst),
                "installed_at": timestamp,
            }
            if opts.confirm_playerbots_compatible:
                m["playerbots_integration"] = {
                    "detected_present": True,
                    "compatibility_confirmed": True,
                    "enabled": True,
                    "reason": "module installed and enabled -- operator explicitly "
                              "confirmed compatibility via confirm_playerbots_compatible",
                }
            else:
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

    # Retire historical Echoes-owned module directories (e.g. the
    # v1.6.0-rc1-era modules/mod-attunement-plus/) -- positive-identity
    # gated, and only after this same operation confirms every declared
    # replacement module is installed. See legacy_retirement.py.
    modules_root = os.path.join(opts.azerothcore_root, "modules")
    retired_modules, unresolved_modules = legacy_retirement.retire_legacy_modules(
        modules_root, backups_root, timestamp, m,
        currently_installed_components=list(m["components"].keys()),
    )
    m["legacy_retirement"]["modules"] = {
        "retired": retired_modules,
        "left_unresolved": [{"name": n, "reason": r} for n, r in unresolved_modules],
    }
    checkpoint()

    # --- CORE: SQL ---
    applied_schema = sql_runner.apply_schema_package(opts.mysql_args, opts.characters_database)
    applied_world = sql_runner.apply_world_items(opts.mysql_args, opts.world_database)
    m["sql"] = {
        "schema_files_applied": applied_schema,
        "world_files_applied": applied_world,
        "applied_at": timestamp,
    }
    checkpoint()

    # --- RECOMMENDED: Client Companion + patch-E.MPQ ---
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
        checkpoint()

        # patch-E.MPQ (Echoes' reserved slot -- see mpq_conflict.py)
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

        existing_patch_e = client_info["existing_patch_e_mpq"]
        existing_sha = hashing.sha256_file(existing_patch_e) if existing_patch_e else None
        recorded_sha = m.get("patch_mpq", {}).get("sha256")
        resolution = mpq_conflict.resolve(existing_sha, recorded_sha)

        if resolution == mpq_conflict.MpqConflictResolution.EXISTING_IS_THIRD_PARTY_BLOCKED:
            raise RuntimeError(
                f"{existing_patch_e} already exists and is not recorded as an "
                "Echoes-generated file -- namespace collision. Echoes does not "
                "overwrite a patch-E.MPQ it doesn't already own; there is no "
                "--force option in the ordinary install path. Resolve the "
                "collision manually (rename or remove the conflicting file) "
                "before retrying, or install without --client-root to skip "
                "client patch installation."
            )

        if existing_patch_e:
            b = backup.backup_path(existing_patch_e, backups_root, timestamp, "patch-e-mpq")
            if b:
                manifest_mod.record_backup(m, timestamp, "patch-e-mpq", b, existing_patch_e)

        build_result = mpq_build.build(vanilla_bytes, os.path.join(backups_root, "mpq-build", timestamp))
        final_mpq_path = os.path.join(opts.client_root, "Data", "patch-E.MPQ")
        shutil.copy2(build_result["mpq_path"], final_mpq_path)

        m["patch_mpq"] = {
            "generated": True,
            "path": final_mpq_path,
            "sha256": hashing.sha256_file(final_mpq_path),
            "internal_files": build_result["internal_files"],
            "vanilla_dbc_sha256": build_result["vanilla_dbc_sha256"],
            "vanilla_dbc_provenance": vanilla_source,
        }

        # One-time legacy patch-4.MPQ migration -- only acts if the existing
        # file is positively proven Echoes' own prior output; otherwise a
        # complete no-op, and any unrelated patch-4.MPQ is never touched.
        migration_result = legacy_migration.migrate(
            opts.client_root, backups_root, timestamp, m["patch_mpq"]
        )
        m["legacy_patch4_migration"] = migration_result
        if migration_result.get("backup_path"):
            manifest_mod.record_backup(
                m, timestamp, "legacy-patch-4-mpq",
                migration_result["backup_path"],
                os.path.join(opts.client_root, "Data", "patch-4.MPQ"),
            )

    checkpoint()
    return m
