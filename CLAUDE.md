# mdm-removal-scripts

**Security classification: privileged endpoint tooling.**
Scripts here may run as root or Administrator and modify MDM enrollment state, system services, processes, files, directories, profiles, registry entries, LaunchDaemons, LaunchAgents, scheduled tasks, packages, system extensions, or other privileged system state.
Treat every script in this repository as security/deployment tooling, not a convenience script.

Post-migration MDM removal/cleanup scripts (Iru SE tooling). Every script here must
conform to @MDM_Removal_Script_Standard.md — read it before writing or modifying any
script. The contract (C1–C12) is non-negotiable; code bends to the contract, not the
other way around.

## Repository layout

- `macos/<vendor>/`, `windows/<vendor>/` — one folder per incumbent MDM per OS.
  Each vendor folder is a self-contained unit: script + README (.md and .pdf) +
  Operational Overview PDF, ALL carrying the same version.
- `templates/` — contract-compliant skeletons. New scripts START from the template
  for their language; never copy-paste an existing vendor script into a new one
  (that is how the Chef-block bug family happens).
- Vendor-delegated payloads (e.g., JumpCloud's own uninstaller): wrap, pin
  (upstream URL + commit + date in the harness header), never fork or edit.

## Engineering priority order

When decisions must be made, prioritize in this order:

1. Safety
2. Correctness
3. Protection of customer and production data
4. Deterministic behavior
5. Recoverability
6. Maintainability
7. Compatibility
8. Observability
9. Performance
10. Convenience

Never trade away the first four to make implementation easier.

## Execution lifecycle

Every privileged operation must follow this lifecycle:

**Detect → Validate → Execute → Verify**

Unknown or ambiguous state must cause the script to fail safely — not to broaden the operation or proceed anyway.

- 0 matches: safe no-op or appropriate error
- 1 match: validate and proceed
- >1 unexpected matches: stop, do not guess

## Script conventions

macOS (zsh):
- snake_case variables; full binary paths (/bin/rm, /usr/bin/pgrep, ...)
- logging() writes to stdout AND the unified log; 2-space indent
- Editable defaults block at top with hard separator; comments brief (1–2 lines/block)

Windows (PowerShell):
- `#Requires -Version 5.1` at the top of every script
- `$script:version` variable for version (used in the runtime banner; never hardcoded as a string literal)
- `$script_id` constant included in every log line format
- lower_case_with_underscores naming (deliberately overrides Verb-Noun convention)
- TLS 1.2 forced when any network call is made: `[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12`
- PSScriptAnalyzer suppression via `[Diagnostics.CodeAnalysis.SuppressMessageAttribute]` for intentional deviations — narrow, documented
- 4-space indent; 80-character line limit
- Config placeholder validation must catch YOUR_* values

## Shell safety requirements (macOS)

- Always quote variable expansions: `"${variable}"` not `$variable`
- Use `rm -- "$target"` form for all path deletions (prevents flag interpretation)
- Process sweeps must use the PID-snapshot pattern: snapshot with `${(f)"$(pgrep ...)"}`, re-verify each PID with `ps`, exclude own PID and script name. The pipeline-grep pattern (`pgrep | grep -qv "^$$\$"`) self-matches — do not use it
- No `eval`
- No `curl | bash` or equivalent remote execution
- No `-k` / insecure TLS bypass

## PowerShell safety requirements

- Use `-LiteralPath` instead of `-Path` whenever the input should be treated literally
- Quote arguments to native commands: `sc.exe delete "$name"` not `sc.exe delete $name`
- No `Invoke-Expression`
- `try/catch` around operations where a terminating error would leave state inconsistent
- Do not silently swallow exceptions; empty catch blocks are not permitted
- For operations with broad impact, use `SupportsShouldProcess` / `$PSCmdlet.ShouldProcess()` where practical

## Hard rules (learned the expensive way)

1. NO unconditional success logging. Every removal re-checks reality (re-read the
   value, re-test the path, re-query the service) before logging REMOVED; survivors
   log FAILED and count toward PARTIAL. A success line that prints regardless of
   outcome is a false claim in code form.
2. Dry-run/live must produce IDENTICAL found counts (no double Log-Find).
3. Process sweeps must not self-match the script (PID-snapshot + ps re-verification;
   the pipeline-grep pattern self-matches — see macOS shell safety requirements above).
4. Conditional summary lines only print when their condition occurred this run
   (e.g., "process was killed" requires an actual kill).
5. NO customer data anywhere: no tenant IDs, blueprint GUIDs, enrollment codes,
   hostnames, usernames, or account names — in code, comments, changelogs, or docs.
   Changelogs cite dates and generic findings only ("Field dry run 2026-07-14 showed ...").
6. Docs never claim a more specific version than the shipped script. Any script
   version bump updates the README (.md AND .pdf) and Overview in the same change,
   or nothing ships. README version-history section is mandatory.
7. Versioning is semver (contract C12): patch = bug fix, minor = new artifact
   coverage/flags, major = contract-visible change. VERSION variable + header
   changelog + runtime banner all updated together.
8. Wildcard sweeps stay broad (discovery catches drift); exact names anchor only
   the known-critical items. Do not narrow a sweep to a single tenant's artifact
   list — one tenant's dry run is not the universe.

## Security hard rules (non-negotiable)

- **Least privilege.** Elevation only for operations that require it. Do not weaken permissions, ACLs, or security controls to make a script work.
- **No weakening security controls.** Never disable TLS validation, endpoint protection, code-signature verification, or PowerShell security protections to make a script succeed. If a legitimate solution requires weakening a control, surface the security impact explicitly before implementing.
- **Exact targeting before destruction.** Validate before acting. Never broaden a deletion because the expected target was not found.
- **No invented commands or APIs.** Verify commands, flags, registry paths, and plist keys before using them. If uncertain, say so. Do not invent platform behavior.
- **Fail safely.** When state is ambiguous, stop — do not interpret uncertainty as permission to proceed.
- **Sensitive data stays out of logs.** Never log UPNs, email addresses, enrollment URLs, tenant identifiers, or authentication material. Log existence and generic type; not content.
- **No secrets, credentials, or production-derived values** anywhere in code, comments, changelogs, or docs.

## Static analysis

**macOS (zsh):** ShellCheck does not support zsh. The gate is:
```bash
zsh -n <script.sh>          # syntax validation
```
Plus the logic smoke tests in the verification workflow below (failure path → FAILED → exit 1).

**Windows (PowerShell):**
```powershell
Invoke-ScriptAnalyzer -Path windows\ -Recurse
```

Do not suppress PSScriptAnalyzer findings merely to pass analysis. When suppression is genuinely necessary, use `[Diagnostics.CodeAnalysis.SuppressMessageAttribute]`, narrow it to the specific rule and file location, and document why the code is safe.

## Verification workflow (before any commit claiming a fix)

1. Syntax: `zsh -n <script>` for macOS; PowerShell AST parse for Windows.
2. Logic smoke test: simulate the failure path and prove it lands in failed_items /
   $Failed and drives exit 1.
3. Raw template must run CLEAN (0 found / exit 0) on a machine without the product.
4. Mark fixes as "parser-validated, not field-run" until a real device dry-run →
   live pass confirms; the README version history records field-verification dates.

## Before every commit

Review the entire diff for:

- Customer data (tenant IDs, GUIDs, enrollment codes, hostnames, usernames, email addresses)
- Secrets, credentials, or tokens
- Debug output or temporary test artifacts
- Unsafe recursive deletion
- Wildcard matching narrowed to one tenant's artifacts
- Command injection or unsafe shell expansion
- Unconditional success logging
- Unhandled failures or ignored exit codes
- Invented commands, flags, or API behavior

## Tone for docs

READMEs are operator docs (exact variables, verdict→action table, FAQ).
Overviews are approver docs (no paths, no commands — scope, controls, verdicts).
Never ship an Overview with a script but without its README.

## Key documents

- [`MDM_Removal_Script_Standard.md`](MDM_Removal_Script_Standard.md) — Operator contract (C1–C12)
- [`SECURITY_PHILOSOPHY.md`](SECURITY_PHILOSOPHY.md) — Security design, threat model, per-script security reviews
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — Contributor workflow, testing, review expectations
- [`SECURITY.md`](SECURITY.md) — Vulnerability reporting
