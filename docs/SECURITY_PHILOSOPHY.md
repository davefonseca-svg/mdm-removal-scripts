# Security Philosophy

**Iru, Inc. · mdm-removal-scripts · 2026-08-10**

---

## Purpose

This document records the security design, threat model, safety model, and per-script security reviews for the `mdm-removal-scripts` repository.

It is a living engineering document — not an AI instruction file. It tells humans why these standards exist, what risks the repository is designed to mitigate, and what each script's safety posture actually is.

---

## Central Philosophy

> A privileged script should prove that an action is safe before performing it, perform the smallest necessary change, fail safely when uncertain, and verify the result afterward.

Scripts in this repository may run as root or Administrator and modify managed endpoints. A bug is not an inconvenience — it may leave devices unmanaged, in broken state, or cleaned more aggressively than intended. The repository is therefore designed around the following priorities:

1. Safe failure over silent continuation
2. Exact targeting over broad sweeps
3. Verified outcomes over assumed success
4. Minimal blast radius over convenience
5. Operator visibility over brevity

---

## Core Principles

### Protect customer and production information

No customer-specific, company-internal, or production-specific data belongs in this repository — in source code, comments, changelogs, commits, documentation, or any other artifact. Changelogs preserve engineering lessons by citing dates and generic findings; they do not preserve customer provenance.

### Minimize blast radius

Every state-changing operation targets the smallest possible set. Discovery-based sweeps stay broad enough to catch drift across deployments; they do not narrow to a single tenant's artifact list. Exact hardcoded identifiers anchor only the known-critical items, not the entire sweep.

### Detect before modifying

The execution lifecycle is always: **Detect → Validate → Execute → Verify**. Phase 1 (assessment) runs in both dry-run and live mode. Every item is logged `FOUND` before any action is taken on it. No item is acted on without being found first.

### Fail safely

Unknown state is not permission to proceed. Scripts stop rather than guess when:

- No matching target is found where one is required
- More than one unexpected target is found
- The operating system is unsupported
- Input is malformed or ambiguous
- Validation fails
- Privilege is absent

### Least privilege

Detection and validation do not require elevation. Privileged operations are narrowly scoped. Security controls — TLS validation, code-signature verification, PowerShell security policy, endpoint protection — are never weakened merely to make a script succeed.

### Idempotency

Scripts are safe to run repeatedly in any mode on any device state. An already-clean device is not treated as a failure. Devices converge to clean; nothing already removed is affected by a re-run.

### Verify outcomes

A successful command exit does not automatically mean the desired state exists. After every meaningful state change, the script re-reads the relevant state to confirm the result. Items that survive removal attempts are logged `FAILED` and counted toward `PARTIAL`, never silently claimed as `REMOVED`.

### Treat external input as untrusted

Arguments, environment variables, file paths, registry values, plist values, process output, and command results are all untrusted until validated. Validation prefers allowlists. Ambiguous or malformed input is rejected rather than guessed at.

### Preserve endpoint security

These scripts operate in security-sensitive environments. Removing an MDM agent or delivery layer does not license weakening other controls. SentinelOne and equivalent EDR/AV tooling are explicitly out of scope. Enrollment state is inspected read-only; modification is out of scope.

### Engineer for recoverability

Destructive actions that are irreversible or that affect shared state are flag-gated off by default. The operator must explicitly enable them after confirming the preconditions (e.g., another local admin exists before deleting the managed account). The `PARTIAL` verdict and exit code 1 are designed to surface incomplete cleanup for targeted follow-up, not to guess at recovery.

---

## Threat Model

The repository is designed to make the following failure modes difficult, visible, testable, and reviewable. It does not claim perfect security — it claims deliberate engineering against the known risks.

### Accidental operator error

An operator runs the wrong script version, on the wrong fleet, or with a flag enabled before confirming preconditions (e.g., deleting the only local admin account).

**Mitigations:** Dry-run default. Runtime banner prints script version and mode. Phase 1 assessment reports state before Phase 2 acts. Flag-gated destructive items require explicit enablement with inline warnings. Summary verdict reads bottom-up for fast triage.

### Programming mistakes

Code logic removes more than intended: overly broad glob, unvalidated variable, misquoted path, skipped error check, ignored nonzero exit code.

**Mitigations:** Contract C3/C4 enforced in every helper function. Post-deletion verification for every item. `FAILED` on survival. Verification workflow (syntax check, logic smoke test, clean template test, field dry run) before claiming any fix. No unconditional success logging. `rm -- "$target"` form prevents path/flag confusion.

### Unexpected endpoint state

The device has a partial install, stale artifacts from multiple Rippling versions, an extra local account, a damaged service record, a held file lock, or both old and new MDM agents present simultaneously.

**Mitigations:** Discovery-based sweeps (not fixed lists) catch variant artifact names and locations. Idempotency means re-runs on any state converge safely. `PARTIAL` verdict + exit 1 surfaces individual failures. Phase 1 assessment explicitly reports whether the new-platform agent is present, whether enrollment remnants exist, and whether a restart is pending.

### Command and path injection

Unsafe string interpolation of filenames, environment variables, registry values, or process output into constructed commands.

**Mitigations:** Shell scripts quote all variable expansions. `rm -- "$target"` form. No `eval`. No `Invoke-Expression`. PowerShell uses `-LiteralPath` for path operations where input could contain wildcards. Arguments to native commands are quoted. Process matching uses `pgrep` with PID snapshot, not shell string interpolation into `kill`.

### Sensitive information leakage

Customer-identifying data (UPNs, tenant IDs, enrollment URLs, hostnames, account names) enters the repository or appears in script output consumed by Iru's management infrastructure.

**Mitigations:** Hard rule 5 in `CLAUDE.md`. No customer-specific values in code, comments, changelogs, or docs. Per-commit diff review. The enrollment inspection block in `rippling_removal_windows.ps1` logs enrollment key presence — **see Known Limitations for an open finding on verbatim UPN/URL logging**.

### Supply-chain risk

Dependencies, third-party scripts, remote downloads, or GitHub Actions introduce unreviewed or malicious code.

**Mitigations:** No third-party dependencies in existing scripts (standard OS utilities only). No `curl | bash` patterns. No external downloads at runtime. Vendor-delegated payloads are wrapped (not forked), pinned with upstream URL + version + date, and diffed before each new deployment wave. No GitHub Actions CI yet — see Repository Enforcement Plan.

### AI-assisted development mistakes

Generated code invents commands, flags, registry paths, or platform behavior that does not exist, or produces logic that appears correct but has subtle privilege or targeting issues.

**Mitigations:** `CLAUDE.md` explicitly prohibits invented commands, APIs, and platform behavior. All generated code receives the same review as human-written code. The verification workflow (syntax, logic smoke test, field dry run) must run before any change is claimed as fixed. Uncertainty must be declared; it must not be hidden.

---

## Standards Alignment

The repository's engineering practices are informed by the following standards and frameworks. This does not imply formal certification or compliance:

- **NIST Secure Software Development Framework (SSDF)** — secure design, protected code, well-tested software
- **OpenSSF security practices** — vulnerability disclosure, dependency management, static analysis, CI integration
- **SLSA supply-chain framework** — build integrity, dependency pinning, provenance
- **GitHub secure development controls** — branch protection, secret scanning, push protection, required status checks
- **PSScriptAnalyzer and PowerShell best practices** — approved verbs, explicit error handling, `-LiteralPath`
- **zsh and POSIX shell scripting practices** — quoting, expansion safety, error handling. Note: ShellCheck does not support zsh; the macOS syntax gate is `zsh -n` plus the logic smoke tests in the operator contract's verification workflow.

---

## Script Security Reviews

### `rippling_removal_macos.sh`

#### Purpose

Removes leftover Rippling MDM agent artifacts from macOS devices after migration to Iru. Targets per-user LaunchAgents, system LaunchDaemons, running processes, files and directories, package receipts, Munki delivery components, Chef delivery components, and optionally the RipplingAdmin local account.

#### Privilege Level

root (deployed via Iru custom script mechanism, runs as root)

#### System State Modified

- LaunchAgent plists: `/Library/LaunchAgents/com.rippling.*.plist` and per-user equivalents
- LaunchDaemon plists: `/Library/LaunchDaemons/com.rippling.*.plist`
- Running processes matching "rippling" by name/full command line
- Files and directories: `/opt/rippling`, `/opt/rippling-readonly`, `/usr/local/rippling`, `/Applications/Rippling.app`, `/Applications/RipplingMDM.app`, `/Library/Application Support/Rippling`, per-user `~/Library/Application Support/*rippling*`
- Munki: LaunchDaemons/LaunchAgents (`com.googlecode.munki.*`), `/Applications/Managed Software Center.app`, `/Applications/Utilities/Managed Software Update.app`, `/Library/Managed Installs`, `/Library/Preferences/ManagedInstalls.plist`, `/usr/local/munki`, `/etc/paths.d/munki`, package receipts matching `com.googlecode.munki`
- Chef: LaunchDaemons (`com.getchef.*`, `com.chef.*`), `/opt/chef-workstation`, `/opt/inspec`, package receipts matching `com\.(get)?chef\.`
- Login window text (`/Library/Preferences/com.apple.loginwindow` `LoginwindowText`)
- Optional (flag-gated, default off): local admin account `RipplingAdmin` + home directory

Explicitly NOT modified: MDM enrollment profiles (read-only inspection via `profiles list`).

#### Target Identification

| Category | Method |
|---|---|
| File paths (known) | Exact hardcoded paths with `[[ -e "$target" ]]` guard |
| LaunchAgents/Daemons | zsh glob with `(N)` qualifier: `com.rippling.*.plist` |
| Per-user app support | Discovery glob `*/Library/Application Support/*(N)`, case-insensitive substring match `*rippling*` |
| Processes | `pgrep -if "rippling"` (full command, case-insensitive), PID re-verified via `ps`, own PID and script name excluded |
| Package receipts | `pkgutil --pkgs \| grep -i "rippling"` (case-insensitive substring) |
| Munki launch items | Exact glob: `com.googlecode.munki.*` |
| Chef launch items | Exact glob: `com.getchef.*`, `com.chef.*` |
| Chef receipts | Case-insensitive regex: `com\.(get)?chef\.` |
| Login window text | `defaults read` if value is non-empty |

#### Safety Controls

- Dry-run default (`DRY_RUN="true"`)
- FOUND logged before any action (C3)
- Post-deletion verification for every removal (C4)
- FAILED logged when item survives removal attempt
- LaunchAgents unloaded from active session before deletion
- LaunchDaemons booted out before deletion
- Processes: SIGTERM → wait 1s → SIGKILL; FAILED if still running
- Enrollment profiles: read-only inspection, never modified
- Flag-gated account deletion with explicit operator warning
- PID-snapshot process self-exclusion in Phase 2c
- Exit 1 on any FAILED item in live mode

#### Idempotency

**Yes.** All checks are existence-guarded. Re-running on a clean device produces CLEAN + exit 0. Re-running after a partial live run finds only what remains.

#### Failure Behavior

| Scenario | Behavior |
|---|---|
| Target absent | Silently skipped (`-e` check returns false, loop finds nothing) |
| Removal fails | FAILED logged, counted in failed_items |
| Process won't die | SIGTERM + SIGKILL; if still alive: FAILED logged |
| LaunchItem removal fails | Path re-checked; FAILED if present |
| Live run with any FAILEDs | exit 1 |
| Dry-run mode | exit 0 regardless of found count |
| Privilege failure | rm/launchctl nonzero; re-check detects survival; FAILED logged |
| Unsupported OS | No explicit check; some calls may fail; FAILED captures individual items |

#### Post-Execution Verification

All operations in `remove_path_safe`, `remove_launch_item_safe`, and `forget_receipt_safe` verify the result after acting. Process kills re-check via `kill -0`. Login window text is re-read after `defaults write`. Package receipt removal verified via `pkgutil --forget` exit status.

#### Data Handling

No customer-specific identifiers present in code or comments. Device hostname logged at startup (`/bin/hostname -s`) — operational context, not customer-identifying. Login window text content is logged verbatim when found (content belongs to the device, not to source control; acceptable per C3 but noted).

#### Dependencies

All standard macOS system utilities: `/bin/zsh`, `/bin/date`, `/bin/echo`, `/usr/bin/logger`, `/bin/rm`, `/bin/launchctl`, `/usr/bin/pgrep`, `/bin/ps`, `/bin/kill`, `/usr/bin/id`, `/bin/hostname`, `/usr/sbin/scutil`, `/usr/bin/profiles`, `/usr/sbin/pkgutil`, `/usr/bin/dscl`, `/usr/bin/defaults`, `/usr/bin/grep`, `/usr/bin/awk`. No third-party dependencies.

#### Supported Platforms

macOS (requires zsh). Minimum version not explicitly validated; field-verified against the Rippling agent version current as of 2026-07-14. Behavior on macOS versions outside the field-verified range: unknown.

#### Security Review Status

**Reviewed — Improvements Recommended**

Verification state: parser-validated (`zsh -n`) and logic-smoke-tested as of v2.0.3; field-run as of 2026-07-14 against v2.0.0/v2.0.2. Fixes in v2.0.3 are parser-validated but not yet field-run. See README version history for field-verification dates.

#### Known Limitations

1. **Phase 1d process check uses pipeline-grep pattern** — Phase 1d (assessment) uses `pgrep -if "rippling" | grep -qv "^$$\$"` which can self-match when the script's own path contains "rippling". Phase 2c (kill sweep) was corrected in v2.0.3 using the PID-snapshot + ps re-verification pattern; Phase 1d was not updated. This causes a false "processes RUNNING" warning during assessment on devices where no Rippling processes are running. It does not affect actual removal behavior (Phase 2c has the correct pattern), but misleads operators during assessment.
2. **C11 not implemented** — No file or directory backup before deletion. Documented in the operator contract as an accepted gap.
3. **`rm -Rf` without `--`** — `remove_path_safe` uses `/bin/rm -Rf "$target"` without the `--` argument separator. All targets are either hardcoded paths or glob-expanded filesystem results, so the risk of a path beginning with `-` is minimal in practice. The `--` form is the documented best practice for privileged tooling.
4. **No explicit macOS version validation** — The script does not check `sw_vers` or equivalent before executing. Behavior on future or legacy macOS versions is not guaranteed.
5. **DRY_RUN not strictly validated** — Any value other than `"true"` or `"false"` is treated as live mode. A typo (e.g., `DRY_RUN="True"`) silently enables live mode.
6. **Account deletion ordering** — Home directory deleted with `rm -Rf` before `dscl . -delete`. If `rm` succeeds but `dscl` partially fails, the directory is gone but the account record may persist in a broken state. `sysadminctl -deleteUser` handles both atomically but requires a different privilege model.

#### Recommended Improvements

1. Update Phase 1d to use the PID-snapshot + ps re-verification pattern already present in Phase 2c.
2. Add `--` to the rm call in `remove_path_safe`: `/bin/rm -Rf -- "$target"`.
3. Add `DRY_RUN` validation: reject values that are not exactly `"true"` or `"false"`.
4. Add a minimum macOS version check (warn and optionally exit on unsupported versions).
5. Consider using `sysadminctl -deleteUser "$USER_TO_REMOVE" -secure` for account removal to handle both directory record and home atomically.

---

### `rippling_removal_windows.ps1`

#### Purpose

Removes leftover Rippling MDM agent artifacts from Windows devices after migration to Iru. Targets scheduled tasks, the Windows service, running processes, the official uninstaller, autostart Run registry values, files and directories, and Uninstall registry keys. Optional flag-gated removal of Chocolatey and the RipplingAdmin local account.

#### Privilege Level

Administrator / SYSTEM (deployed via Iru custom script mechanism, runs as SYSTEM)

#### System State Modified

- Scheduled tasks matching `*rippling*` in TaskName or TaskPath (including `Rippling-Rescuer` watchdog)
- Windows service matching `*rippling*` in Name or DisplayName (field-verified: `rippling-daemon`)
- Running processes matching `*rippling*` in Name (field-verified: `Rippling Tray`, multiple instances)
- External executable: `"C:\Program Files\Rippling\App\Uninstall Rippling.exe" /allusers /S` (if present)
- HKLM autostart Run values: `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run`, `HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run`
- Per-user autostart Run values: all SIDs matching `S-1-5-21` (domain/local, excluding _Classes)
- Files and directories: `C:\Program Files\Rippling`, `C:\Program Files (x86)\Rippling`, `C:\ProgramData\Rippling`, per-user `AppData\Local\*rippling*` and `AppData\Roaming\*rippling*`
- Registry Uninstall keys under `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall` and WOW6432Node equivalent, where DisplayName matches `*rippling*`
- Optional (flag-gated, default off): `C:\ProgramData\chocolatey` + ChocolateyInstall and ChocolateyLastPathUpdate Machine environment variables
- Optional (flag-gated, default off): local admin account `RipplingAdmin` + Win32_UserProfile

Explicitly NOT modified: `HKLM:\SOFTWARE\Microsoft\Enrollments` (read-only inspection only). SentinelOne (out of scope by design).

#### Target Identification

| Category | Method |
|---|---|
| Scheduled tasks | `Get-ScheduledTask` filtered by `TaskName -like "*rippling*"` or `TaskPath -like "*rippling*"` |
| Services | `Get-CimInstance Win32_Service` where `Name -like "*rippling*"` or `DisplayName -like "*rippling*"` |
| Processes | `Get-Process` where `Name -like "*rippling*"` |
| Official uninstaller | Exact path: `"C:\Program Files\Rippling\App\Uninstall Rippling.exe"`, checked with `-LiteralPath` |
| Autostart values | Run key value name `*rippling*` or value data `*rippling*` (case-insensitive) |
| Folders | Exact hardcoded paths + `Get-ChildItem -Filter "*rippling*"` on per-user AppData |
| Uninstall registry keys | DisplayName `-like "*rippling*"` under Uninstall hives |
| Enrollment inspection | String `"rippling"` in concatenation of UPN + ProviderID + DiscoveryServiceFullURL |

#### Safety Controls

- Dry-run default (`$DryRun = $true`)
- FOUND logged before any action
- Post-deletion verification for every removal
- FAILED logged when item survives
- Explicit ordering: scheduled tasks (incl. watchdog) before service before processes before uninstaller before files
- Enrollment registry: read-only access; explicit comment documents non-modification
- Flag-gated Chocolatey and account removal with operator warnings
- `-LiteralPath` used in `Remove-PathSafe`
- `HKU:` PSDrive mounted for per-user registry access, scoped to `S-1-5-21` SIDs excluding `_Classes`
- Exit 1 on any FAILED item in live mode

#### Idempotency

**Yes.** All checks are guarded by `Test-Path`, `Get-CimInstance`, `Get-ScheduledTask`, `Get-Process`, and `Get-ItemProperty` existence tests. Re-running on a clean device produces CLEAN + exit 0.

#### Failure Behavior

| Scenario | Behavior |
|---|---|
| Target absent | Skipped (existence check returns nothing) |
| Removal fails | FAILED logged, counted in $Failed |
| Service won't stop/delete | `sc.exe delete` + `Get-Service` re-check; FAILED if still present |
| Process won't stop | `Stop-Process -Force` + `Get-Process -Id` re-check; FAILED if alive |
| Uninstaller nonzero exit | FAILED logged; file/folder cleanup continues |
| Registry key survives | `Test-Path` re-check; FAILED if still present |
| Live run with any FAILEDs | exit 1 |
| Dry-run mode | exit 0 regardless of found count |
| Unsupported OS | No explicit check; cmdlets may fail; individual items captured as FAILED |

#### Post-Execution Verification

All operations verify result after acting: `Get-ScheduledTask` re-check, `Get-Service` re-check, `Get-Process -Id` re-check, `Test-Path -LiteralPath` re-check for folders, `Get-ItemProperty` re-check for Run values, `Test-Path` re-check for Uninstall keys.

#### Data Handling

No customer-specific identifiers hardcoded in code or comments. Device hostname (`$env:COMPUTERNAME`) logged at startup — operational context.

**Open finding:** The enrollment inspection block (Phase 1b, lines 167–175) constructs `$blob = "$($p.UPN) $($p.ProviderID) $($p.DiscoveryServiceFullURL)"` and logs it verbatim if the string matches "rippling". The UPN field typically contains a user email address; the DiscoveryServiceFullURL contains the tenant's MDM discovery endpoint. Both are customer-identifying values. If a Rippling enrollment remnant is found, these values appear in stdout (captured by the Iru management console) and in the on-disk log file. See Recommended Improvements.

#### Dependencies

PowerShell built-in cmdlets: `Get-CimInstance`, `Get-ScheduledTask`, `Unregister-ScheduledTask`, `Stop-Service`, `Get-Service`, `Stop-Process`, `Get-Process`, `Get-LocalUser`, `Remove-LocalUser`, `Get-ChildItem`, `Remove-Item`, `Get-Item`, `Get-ItemProperty`, `Remove-ItemProperty`, `New-PSDrive`, `Start-Process`, `New-Item`, `Add-Content`, `Join-Path`. Native: `sc.exe`. CIM class: `Win32_Service`, `Win32_UserProfile`. No third-party modules.

#### Supported Platforms

Windows 10 and Windows Server 2016 or later (required for `Get-LocalUser`/`Remove-LocalUser`). PowerShell 5.1 or later assumed but not enforced via `#Requires`. Field-verified against Rippling agent footprint from dry run on 2026-07-13.

#### Security Review Status

**Reviewed — Improvements Recommended**

Verification state: parser-validated and logic-smoke-tested as of v1.3.1; field-run as of 2026-07-13 against v1.3. Fixes in v1.3.1 are parser-validated but not yet field-run. See README version history for field-verification dates.

The enrollment UPN/URL logging finding is the most significant. All others are convention gaps or low-severity hardening items.

#### Known Limitations

1. **Enrollment data logged verbatim** — UPN (email address) and DiscoveryServiceFullURL (tenant-specific enrollment URL) are logged to stdout and the on-disk log file when a Rippling enrollment remnant is found. These are customer-identifying values. Logging should be scoped to the enrollment key name (a GUID) only.
2. **Missing `#Requires -Version 5.1`** — PowerShell version requirement not enforced; running on PS 4.0 or earlier may produce obscure failures.
3. **No `$script:version` variable** — Version appears as a comment (`# VERSION="1.3.1"`) and as a hardcoded literal in the banner log line (`v1.3.1`). Two places must be updated in sync; they can diverge. Contract C12 / CLAUDE.md convention requires a single variable.
4. **No `$script_id` constant in log format** — CLAUDE.md convention specifies `[timestamp] [level] [script_id]` log prefix with a `$script_id` constant. Current format omits the script ID.
5. **Missing PSScriptAnalyzer suppressions** — Non-Approved-verb functions (`Log-Info`, `Log-Warn`, `Log-Find`, `Log-Done`, `Log-Fail`) lack `SuppressMessageAttribute` declarations per CLAUDE.md convention.
6. **C11 not implemented** — No registry backup before key deletion. Documented in operator contract as accepted gap.
7. **`Remove-Item -Path` on registry keys** — Line 304 uses `-Path $k.PSPath` for a registry key deletion. The standard requires `-LiteralPath` to prevent wildcard interpretation. `PSPath` values from `Get-ChildItem` are correctly formatted, making the practical risk low, but the convention should be followed.
8. **`sc.exe delete` without quoted argument** — Line 228: `& sc.exe delete $svc.Name`. If a service name contained spaces, this would behave unexpectedly. Field-verified service names are single words, but quoting is the robust form: `& sc.exe delete "$($svc.Name)"`.
9. **No explicit Windows version check** — `Get-LocalUser` behavior and availability varies; no OS validation before calling it.
10. **LAPS availability claim in README** — `README_Rippling_Removal_Windows.md` states "Iru LAPS is not yet available" in the `$RemoveRipplingAdmin` flag description. This is a time-sensitive product claim; verify it against current Iru product state before each customer distribution wave. Not a security finding — a documentation maintenance item.

#### Recommended Improvements

1. Replace enrollment data logging with key-name-only logging: log `$k.PSChildName` (a GUID) and drop `$blob` from the log line entirely.
2. Add `#Requires -Version 5.1` as the first non-comment line.
3. Replace `# VERSION="1.3.1"` with `$script:version = "1.3.1"` and reference it in the banner: `"Rippling removal v$($script:version) | ..."`.
4. Add `$script_id = "rippling_removal_windows"` and include in log format: `"{0} [{1}] [{2}] {3}" -f ..., $script_id, $Message`.
5. Add `[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]` with a narrow scope for `Log-*` functions.
6. Change `Remove-Item -Path $k.PSPath` to `Remove-Item -LiteralPath $k.PSPath`.
7. Change `& sc.exe delete $svc.Name` to `& sc.exe delete "$($svc.Name)"`.

---

### `templates/template_removal_macos.sh`

#### Purpose

Contract-compliant skeleton for new macOS MDM removal scripts. Provides the complete scaffolding (mode switch, logging, counters, helper functions, summary verdict, exit codes). Authors fill in Phase 2 artifact lists only; the contract infrastructure must not be modified.

#### Privilege Level

root (same as every instantiated production script)

#### System State Modified

None directly — this is a template, not a deployed script. When instantiated for a specific product, the same categories as production scripts apply.

#### Target Identification

Uses placeholder tokens (`__product__`, `__PRODUCT__`, `__Product__`) throughout. Authors replace these with field-verified identifiers from a real dry run.

#### Safety Controls

- Dry-run default
- `remove_path_safe`: FOUND → DRY_RUN gate → rm → re-check → FOUND or FAILED
- `remove_launch_item_safe`: FOUND → DRY_RUN gate → launchctl bootout → rm → re-check → DONE or FAILED
- `forget_receipt_safe`: FOUND → DRY_RUN gate → pkgutil --forget → exit-status check → DONE or FAILED
- Phase 2c process kill loop uses PID-snapshot + ps re-verification (correct pattern)
- Flag-gated account deletion block with operator warning
- Author checklist in header requiring field verification before customer use
- Summary verdict block and exit codes provided; marked DO NOT MODIFY

#### Idempotency

**Yes** (by design — the scaffold produces idempotent behavior; authors must not break this).

#### Failure Behavior

Template provides: FAILED on path survival, FAILED on LaunchItem survival, FAILED on receipt forget failure, exit 1 on failed_items > 0 in live mode. Individual script behavior depends on author implementation in Phase 2.

#### Post-Execution Verification

All three helper functions verify results after acting. Authors must use these helpers for all Phase 2 removals; direct `rm` or `launchctl` calls without verification break C4.

#### Data Handling

No customer data. Contains `__DATE__`, `__MACOS_VERSION__`, `__AGENT_VERSION__` tokens as documentation placeholders in the field-verification comment — these appear in a comment, not in executable code. Authors must fill these before shipping.

#### Dependencies

Standard macOS system utilities (same as production scripts). No third-party dependencies.

#### Supported Platforms

macOS (requires zsh). Instantiated scripts should add explicit version validation for their minimum supported macOS version.

#### Security Review Status

**Reviewed — Improvements Recommended**

Verification state: template is syntax-validated (`zsh -n`) and smoke-tested (produces CLEAN / exit 0 on a device without the placeholder product). Instantiated scripts must be independently field-verified before customer use — the template's verification state does not transfer to derived scripts.

The Phase 1d self-match bug is the critical finding. It is a known bug that was fixed in the production script's Phase 2c but not propagated back to Phase 1d. Any new script built from this template will inherit the Phase 1d bug.

#### Known Limitations

1. **Phase 1d process check uses pipeline-grep pattern (self-match bug)** — Line 193: `if /usr/bin/pgrep -if "__product__" | /usr/bin/grep -qv "^$$\$"; then`. This pattern can self-match when `__product__` is replaced with a name that appears in the script's filename (e.g., a script named `mosyle_removal_macos.sh` where `__product__` is replaced with `mosyle`). The correct pattern — PID snapshot + ps re-verification — is already present in Phase 2c (lines 225–244). The CLAUDE.md hard rules explicitly document this issue ("the pipeline-grep pattern self-matches"). Phase 1d was not updated when Phase 2c was corrected.
2. **`rm -Rf` without `--`** — `remove_path_safe` uses `/bin/rm -Rf "$target"` without the `--` separator. The `--` form is the documented best practice for privileged tooling.
3. **No CI token-validation step** — The template contains `__PRODUCT__`, `__product__`, `__DATE__`, `__MACOS_VERSION__`, `__AGENT_VERSION__` tokens that must be replaced by authors. There is no automated check to catch un-replaced tokens before deployment. A script deployed with placeholder tokens would attempt to match paths like `/Applications/__Product__.app` (safe — non-existent) and report CLEAN, masking the authoring error.
4. **Phase 1c commented out** — The app-presence check in Phase 1c is commented out, requiring authors to uncomment and adapt it. This is intentional (product-specific), but the pattern differs from Phase 1d (which is active but incorrect). Authors may follow the commented-out pattern for Phase 1c and the active (incorrect) pattern for Phase 1d.

#### Recommended Improvements

1. **Critical: update Phase 1d** to use the PID-snapshot pattern from Phase 2c. This prevents every script built from the template from inheriting the self-match bug.
2. Add `--` to the rm call in `remove_path_safe`: `/bin/rm -Rf -- "$target"`.
3. Add a ShellCheck pragma or documented CI instruction for checking un-replaced placeholder tokens (grep for `__[A-Z_]*__` before deployment).
4. Uncomment Phase 1c with a clear FILL-IN comment, making the authoring requirement explicit rather than hidden.

---

### Vendor-delegated script reviews (forward-looking)

When a vendor-delegated script enters this repository (e.g., a JumpCloud uninstaller wrapped in an Iru harness), its security review includes an additional field not applicable to native scripts:

**Payload Provenance**
- Upstream URL
- Pinned version or commit hash
- Retrieval date
- Verification method (manual diff before each deployment wave)

The harness supplies all contract requirements (C1–C4, C7–C9) around the vendor tool. Vendor tool output is treated as an unverified claim — the harness's independent post-run state verification sweep is the real FOUND/REMOVED/FAILED determination. The vendor script is never forked or edited; it is wrapped and pinned.

---

## Security Characteristics Summary

| Script | Platform | Privilege | Destructive | Idempotent | Post-Action Verification | Review Status |
|---|---|---|---|---|---|---|
| `rippling_removal_macos.sh` | macOS | root | Yes | Yes | Yes — all removals | Reviewed — Improvements Recommended |
| `rippling_removal_windows.ps1` | Windows | Administrator/SYSTEM | Yes | Yes | Yes — all removals | Reviewed — Improvements Recommended |
| `templates/template_removal_macos.sh` | macOS | root (when instantiated) | Yes (when instantiated) | Yes (by design) | Yes — all helpers | Reviewed — Improvements Recommended |

---

## Repository Enforcement Plan

### MUST HAVE NOW (this staging repo)

| Control | Status | Notes |
|---|---|---|
| `CLAUDE.md` | Done | Updated with security engineering standards |
| `SECURITY_PHILOSOPHY.md` | Done | This document |
| `SECURITY.md` | Done | Placeholder contact details must be filled in before external distribution |
| `CONTRIBUTING.md` | Done | Trimmed to proportional scope; "FOR ORG REPO" section included |
| `.gitignore` | Done | Created |
| PSScriptAnalyzer config | Not configured | Should be added for consistent Windows script linting |
| Fix template Phase 1d self-match bug | **Pending** | Open finding; should be resolved before next script is built from template |
| Fix enrollment UPN/URL logging in Windows script | **Pending** | Open finding; medium severity |

### PENDING SCRIPT-LEVEL CHANGES

These are proposed but not yet made — require explicit approval:

| Change | Target | Priority |
|---|---|---|
| Phase 1d self-match fix (pipeline-grep → PID-snapshot) | `template_removal_macos.sh` and `rippling_removal_macos.sh` | High |
| Enrollment UPN/URL logging → key-GUID-only | `rippling_removal_windows.ps1` line 171 | Medium |
| `#Requires -Version 5.1` | `rippling_removal_windows.ps1` | Medium |
| `$script:version` variable; version in banner | `rippling_removal_windows.ps1` | Medium |
| PSScriptAnalyzer suppressions for Log-* functions | `rippling_removal_windows.ps1` | Medium |
| `-LiteralPath` for registry key deletion | `rippling_removal_windows.ps1` line 304 | Medium |
| `sc.exe delete "$($svc.Name)"` (quoted) | `rippling_removal_windows.ps1` line 228 | Low |
| `rm -Rf -- "$target"` (add `--`) | Both macOS scripts | Low |

### FOR THE ORG REPO

When this repository moves to an organization repo, add:

| Control | Notes |
|---|---|
| GitHub branch protection on `main` | Require PR; no direct push; required status checks |
| GitHub secret scanning + push protection | Catches credentials before they land in history |
| CI job: `zsh -n` on modified `.sh` files | Syntax gate for macOS scripts (ShellCheck does not support zsh) |
| CI job: `Invoke-ScriptAnalyzer` on modified `.ps1` files | Linting gate for Windows scripts |
| `CODEOWNERS` | Review routing |
| Custom secret-scanning patterns | Enrollment-code and tenant-ID formats |
| Automated dry-run smoke test on reference device | Field-verification support |
| Windows PowerShell template | Must start from scratch, not copy the Rippling script |

### OPTIONAL / MATURITY IMPROVEMENTS

| Control | Notes |
|---|---|
| Signed/checksummed release artifacts | If scripts are distributed outside Iru |
| Mosyle, Jamf removal scripts | Planned per compliance table |
| JumpCloud harness | Vendor-delegated payload type; wrap + pin; see Payload Provenance note |

---

## Document Relationships

| Document | Audience | Purpose |
|---|---|---|
| `SECURITY_PHILOSOPHY.md` | Engineers, reviewers, auditors | Security design, threat model, per-script reviews, enforcement plan |
| `CLAUDE.md` | Claude Code sessions | Operational development instructions — concise, everyday reference |
| `MDM_Removal_Script_Standard.md` | Script authors, operators | Operator contract (C1–C12) — non-negotiable behavioral requirements |
| `SECURITY.md` | External reporters | Vulnerability reporting process |
| `CONTRIBUTING.md` | Contributors | Branch workflow, coding standards, testing, review expectations |
| `README.md` | Not yet created | User-facing description and usage summary (planned) |

Cross-reference instead of duplicating. `CLAUDE.md` references this document for detailed security rationale. This document references `MDM_Removal_Script_Standard.md` for the operator contract. `CONTRIBUTING.md` references both.

---

## Maintenance

Update the relevant script section in this document whenever a script is:

- Added to the repository
- Substantially modified
- Given new destructive behavior or additional privileges
- Expanded to another platform
- Changed in how it identifies or verifies targets
- Found to contain a meaningful security issue
- Field-verified for the first time or re-verified after significant change

Trivial formatting or comment-only changes that do not alter documented behavior do not require documentation updates.

---

## Historical Engineering Discoveries

Discoveries from field use, preserved as engineering lessons without customer provenance:

- **2026-07-14** — macOS field dry run revealed the Rippling install root at `/usr/local/rippling` and per-user data at `~/Library/Application Support/rippling-tray`. An exact-name match on "Rippling" would have reported CLEANED while those paths remained on disk. The per-user Application Support sweep was updated to use discovery-based case-insensitive matching.
- **2026-07-14** — The Phase 1d process check using `pgrep | grep -qv "^$$\$"` caused a false "processes RUNNING" warning on a device with no Rippling processes. The script's own path contained "rippling", causing pgrep to match itself. Phase 2c was corrected with the PID-snapshot pattern; Phase 1d was not updated (open finding).
- **2026-07-13** — Windows field dry run verified the actual service name (`rippling-daemon`), task names (`Rippling-Rescuer`, `rippling-start-agent-Rippling Tray`, `rippling-update-daemon`), and the existence of the `RipplingAdmin` local admin account on Windows. Agent detection updated to use word-bounded pattern to prevent false positives where substring matches would incorrectly identify unrelated services.
- **2026-07-13** — Autostart Run-key and Uninstall registry-key removals were previously unconditional REMOVED (no re-verification). This could produce a false CLEANED result if the registry write silently failed. Both now re-verify with `Get-ItemProperty` / `Test-Path`.
- **General** — The copy-paste anti-pattern (using an existing vendor script as the starting point for a new one) was identified as the source of the "Chef receipt used Munki's `com.googlecode.chef` identifier" bug. Templates were established as the mandatory starting point for all new scripts.
