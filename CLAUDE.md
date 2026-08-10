# mdm-removal-scripts

Post-migration MDM removal/cleanup scripts (Iru SE tooling). Every script here must
conform to @MDM_Removal_Script_Standard.md — read it before writing or modifying any
script. The contract (C1–C12) is non-negotiable; code bends to the contract, not the
other way around.

## Repo layout

- `macos/<vendor>/`, `windows/<vendor>/` — one folder per incumbent MDM per OS.
  Each vendor folder is a self-contained unit: script + README (.md and .pdf) +
  Operational Overview PDF, ALL carrying the same version.
- `templates/` — contract-compliant skeletons. New scripts START from the template
  for their language; never copy-paste an existing vendor script into a new one
  (that is how the Chef-block bug family happens).
- Vendor-delegated payloads (e.g., JumpCloud's own uninstaller): wrap, pin
  (upstream URL + commit + date in the harness header), never fork or edit.

## Script conventions

macOS (zsh):
- snake_case variables; full binary paths (/bin/rm, /usr/bin/pgrep, ...)
- logging() writes to stdout AND the unified log; 2-space indent
- Editable defaults block at top with hard separator; comments brief (1–2 lines/block)

Windows (PowerShell):
- lower_case_with_underscores naming (deliberately overrides Verb-Noun convention)
- #Requires -Version 5.1; TLS 1.2 forced for PS 5.1 compatibility
- logging with [timestamp] [level] [script_id] prefix; $script_id constant in log lines
- PSScriptAnalyzer suppression via [Diagnostics.CodeAnalysis.SuppressMessageAttribute]
- 4-space indent; 80-character line limit
- Config placeholder validation must catch YOUR_* values

## Hard rules (learned the expensive way)

1. NO unconditional success logging. Every removal re-checks reality (re-read the
   value, re-test the path, re-query the service) before logging REMOVED; survivors
   log FAILED and count toward PARTIAL. A success line that prints regardless of
   outcome is a false claim in code form.
2. Dry-run/live must produce IDENTICAL found counts (no double Log-Find).
3. Process sweeps must not self-match the script (PID-snapshot + ps re-verification;
   see template 2c — the pipeline-grep pattern self-matches).
4. Conditional summary lines only print when their condition occurred this run
   (e.g., "process was killed" requires an actual kill).
5. NO customer data anywhere: no tenant IDs, blueprint GUIDs, enrollment codes,
   hostnames, usernames, or account names — in code, comments, changelogs, or docs.
   Changelogs cite dates and findings only ("Field dry run 2026-07-14 showed ...").
6. Docs never claim a more specific version than the shipped script. Any script
   version bump updates the README (.md AND .pdf) and Overview in the same change,
   or nothing ships. README version-history section is mandatory.
7. Versioning is semver (contract C12): patch = bug fix, minor = new artifact
   coverage/flags, major = contract-visible change. VERSION variable + header
   changelog + runtime banner all updated together.
8. Wildcard sweeps stay broad (discovery catches drift); exact names anchor only
   the known-critical items. Do not narrow a sweep to a single tenant's artifact
   list — one tenant's dry run is not the universe.

## Verification workflow (before any commit claiming a fix)

1. Syntax: `zsh -n <script>` for macOS; PowerShell AST parse for Windows.
2. Logic smoke test: simulate the failure path and prove it lands in failed_items /
   $Failed and drives exit 1.
3. Raw template must run CLEAN (0 found / exit 0) on a machine without the product.
4. Mark fixes as "parser-validated, not field-run" until a real device dry-run →
   live pass confirms; the README version history records field-verification dates.

## Tone for docs

READMEs are operator docs (exact variables, verdict→action table, FAQ).
Overviews are approver docs (no paths, no commands — scope, controls, verdicts).
Never ship an Overview with a script but without its README.
