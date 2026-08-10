# MDM Removal Script Standard — Operator Contract

**Iru, Inc. · v1.0 · 2026-08-08**

Every MDM removal/cleanup script in this repository behaves identically to the operator, regardless of which incumbent it removes or what language it is written in. The *code* may differ; the *contract* may not.

Scope: post-migration teardown of a former MDM/agent stack (JumpCloud, Rippling, Mosyle, Jamf, …). Out of scope: the migration itself (owned by the migration scripts) and MDM enrollment records (always inspected read-only, never modified).

---

## The Contract

**C1 — One mode switch, dry-run default.**
A single editable variable (`DRY_RUN` / `$DryRun`) controls everything. Ships `true`. First contact with any fleet is an audit, never an action. Dry-run and live perform the identical scan, so a dry-run report is an exact preview — including identical FOUND counts.

**C2 — Three phases, in order.**
*Phase 1 — Assessment (read-only, both modes):* new-platform agent present? Old-MDM enrollment remnants (report only)? Relevant pending state (e.g., queued reboots)?
*Phase 2 — Sweep (honors the mode switch):* the removal work.
*Phase 3 — Summary:* counters and verdict. The last block in the console is always the verdict; output reads bottom-up.

**C3 — FOUND before touched.**
Every item is logged `FOUND` before any action is taken on it. Absent items are skipped silently — no noise for things that aren't there.

**C4 — Every removal verified.**
After acting, re-check reality: re-read the value, re-test the path, re-query the service. Survivors are logged `FAILED` and counted. No unconditional success messages — a success line that prints regardless of outcome is a false claim in code form. Vendor tools' own output ("Successfully deleted…") is treated as an unverified claim; the state check is the verification.

**C5 — Deliberate ordering, documented inline.**
Watchdog/repair mechanisms die first, so nothing resurrects mid-cleanup. Then: services → processes → official uninstaller (if any) → files → records. Each script states its order and *why* in a header comment.

**C6 — Irreversible and shared-dependency actions are flag-gated OFF.**
Local admin accounts, shared tooling the fleet may use independently (Chocolatey, Munki), anything a customer could regret — each behind its own off-by-default flag with a warning comment at the definition. Nothing forces those decisions on day one.

**C7 — Verdicts: exactly four.**
`CLEAN` (nothing found) · `DRY RUN complete` (found, reported, unchanged) · `CLEANED` (found, removed, verified) · `PARTIAL` (something survived — named in the log; restart and re-run).

**C8 — Exit codes.**
`0` = clean, dry run complete, or cleaned. `1` = live run with failed removals. Deployment tooling must be able to detect failure without parsing logs.

**C9 — Logging, dual-sink, self-identifying.**
Every line to stdout (management console) *and* a persistent sink (timestamped file on Windows; unified log on macOS). The runtime banner prints the exact script version — field logs must self-identify their build.

**C10 — Idempotent.**
Any mode, any device state, any number of runs. Devices converge to clean; nothing already removed is affected by a re-run.

**C11 — Back up before destroying, where the platform allows.**
Registry keys exported before deletion (Windows); equivalent where feasible elsewhere. When backup isn't practical, the item should be flag-gated (C6) or trivially restorable.

**C12 — Versioning.**
Semver. Patch = bug fix, minor = new artifact coverage or flags, major = contract-visible behavior change. The version lives in one variable, printed at runtime (C9), with a changelog comment in the header. Docs may state `vX.Y` covering the `X.Y.z` line; docs never claim a more specific version than the shipped script.

---

## Two payload types — both conform

**Native.** Iru-authored; the sweep implements C3/C4 per item inline. *(Examples: rippling_removal_macos.sh v2.0.1, rippling_removal_windows.ps1 v1.3.1.)*

**Vendor-delegated.** The vendor's own removal tool runs as a black-box payload inside an Iru harness that supplies the contract around it: dry-run gating (the payload only executes live), then an independent post-run state verification sweep (services, folders, autostarts, per-user data, platform-specific artifacts) that produces the real counters and verdict. Vendor scripts are *pinned*: record upstream URL, commit/version, and retrieval date in the harness header; diff against upstream before each new deployment wave. *(Example: JumpCloud UninstallWindowsAgent.ps1 — authoritative artifact knowledge, no verification or exit codes of its own.)*

The rule of thumb: vendor tools are the best **what-to-remove**; the harness is the required **how-to-remove-safely**. Never fork vendor artifact knowledge — wrap it.

---

## Operator quick reference (identical for every script)

1. Push as-is (dry run) to one test device.
2. Read the SUMMARY bottom-up; review FOUND lines.
3. Decide any flags (C6), flip the mode switch, re-push.
4. Confirm `CLEANED`; handle `PARTIAL` with restart + re-run.
5. Roll out. Safe to re-run anywhere.

---

## Compliance status

| Script | Type | Version | Contract gaps |
|---|---|---|---|
| rippling_removal_macos.sh | Native | 2.0.1 | C11 (no pre-delete backups) |
| rippling_removal_windows.ps1 | Native | 1.3.1 | C11 (no registry backups) |
| JumpCloud UninstallWindowsAgent.ps1 | Vendor payload | upstream (unpinned) | Needs harness: C1–C4, C7–C9 |
| mosyle_removal_macos.sh | — | planned | — |
| jamf_removal_macos.sh | — | planned | — |

New scripts start from the language template (`template_removal.sh` / `template_removal.ps1`), which pre-builds logging, counters, mode switch, and the summary block — authors fill in Phase 2 only.
