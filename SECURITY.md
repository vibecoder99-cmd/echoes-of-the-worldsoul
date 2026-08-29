# Security Policy

Echoes of the Worldsoul is a small open-source project without a formal
security team. Reports are handled by the maintainer on a best-effort
basis.

## Reporting a Vulnerability

Please report security-relevant issues privately rather than as a public
GitHub Issue, using GitHub's
[private vulnerability reporting](https://github.com/vibecoder99-cmd/echoes-of-the-worldsoul/security/advisories/new)
feature if enabled, or by opening a minimal public Issue that avoids
including exploit details and asking for a private channel.

Examples of what belongs here rather than a normal bug report:

- Credential exposure (e.g. database passwords appearing in logs, error
  output, or installer command lines)
- Installer path-traversal or unsafe file-deletion behavior
- Uninstall or repair behavior that could destroy data outside what's
  documented as owned by Echoes
- Unsafe handling of a malicious or malformed install manifest, MPQ
  archive, or client package
- Any way for a client-side AddOn interaction to cause unintended
  server-side effects beyond documented gameplay actions

## What to Include

- The affected component/file
- Steps to reproduce, ideally against a disposable test environment
- The actual vs. expected behavior
- Do not include real credentials, even redacted examples that resemble
  a real deployment's format

## Scope

This covers Echoes' own code (Lua, C++ modules, installer, client AddOn,
SQL). It does not cover AzerothCore, Eluna/`mod-ale`, Playerbots, or your
WoW client itself — report those to their respective projects.
