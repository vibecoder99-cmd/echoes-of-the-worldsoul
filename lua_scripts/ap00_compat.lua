-- Copyright (C) 2025-2026 vibecoder99
-- Licensed under the GNU General Public License v3. See LICENSE.
-- ============================================================
-- ap00_compat.lua
-- Echoes of the Worldsoul — Deployment Profile Detection
--
-- Loads FIRST among all Echoes scripts (ap0N_ prefix sorts
-- before ap_ alphabetically: '0' ASCII 48 < '_' ASCII 95).
--
-- Responsibilities:
--   - Declare AP.Profile
--   - Detect runtime environment at load time (partial)
--   - AP.Compat.Apply() finalizes profile after ap_core.lua loads
--
-- Phase A: native-eluna is the only active profile.
--          DML detection deferred to Apply() when AP.Config exists.
-- ============================================================

AP         = AP         or {}

-- ── AP.Warn bootstrap (dependency-free) ──────────────────────
-- ap_auralab.lua calls AP.Warn(...) at its own top-level load.
-- "ap_auralab" sorts alphabetically before "ap_core" (the file
-- that normally defines AP.Warn), so AP.Warn must already exist
-- by the time this file finishes loading. AP.Warn's real
-- implementation is a dependency-free print wrapper, so it is
-- safe to bootstrap the identical behavior here; ap_core.lua's
-- own unconditional `function AP.Warn(msg) ... end` later simply
-- re-assigns the same implementation (idempotent, no behavior
-- change, no duplicate output).
AP.Warn = AP.Warn or function(msg)
    print("[AP] WARN: " .. tostring(msg))
end

AP.Profile = AP.Profile or {
    name  = "unknown",
    eluna = false,
    ale   = false,
    startupEventId = nil,
}

AP.Compat          = AP.Compat          or {}
AP.Compat.Profiles = AP.Compat.Profiles or {
    NATIVE_ELUNA  = "native-eluna",
    UNKNOWN_ELUNA = "unknown-eluna",
    ALE           = "ale",
}

-- ── DETECT (load-time, partial) ──────────────────────────────
-- Called immediately below. Sets AP.Profile.eluna and a provisional name.
-- AP.RT.RegisterStartup later records ALE support from the accepted factual
-- lifecycle event rather than a deployment-brand flag.

function AP.Compat.Detect()
    if type(RegisterServerEvent) ~= "function" then
        AP.Profile.name  = "unknown"
        AP.Profile.eluna = false
        print("[Echoes] WARN ap00_compat: Eluna not detected. AP.RT will remain as no-op stubs.")
        return
    end
    AP.Profile.eluna = true
    AP.Profile.name  = AP.Compat.Profiles.NATIVE_ELUNA
end

-- ── APPLY (called from ap_core.lua startup hook) ─────────────
-- Retained as a compatibility no-op for older callers. Factual capability
-- state is finalized by AP.RT.RegisterStartup.

function AP.Compat.Apply() end

-- Run load-time detection immediately.
AP.Compat.Detect()

print(string.format("[Echoes] ap00_compat loaded | profile=%s | eluna=%s",
    AP.Profile.name, tostring(AP.Profile.eluna)))
