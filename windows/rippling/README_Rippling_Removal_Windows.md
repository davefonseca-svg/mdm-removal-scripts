# Rippling Removal for Windows

**rippling_removal_windows.ps1 · v1.3.1 · Iru, Inc.**

Removes leftover Rippling agent components from Windows devices after they have migrated to Iru. The Windows counterpart of Iru's macOS rippling_removal.sh.

**Ships safe by default.** As delivered, the script runs in dry-run mode — it scans, reports, and changes nothing. You must edit one line to make it act.

## Quick start

| STEP | WHAT TO DO |
|---|---|
| 1. Dry run | Push the script as-is from the Iru console (Custom Script library item, runs as SYSTEM) to one test device. |
| 2. Read the verdict | Open the script output in the Iru console and read the SUMMARY block at the bottom. |
| 3. Go live | If the FOUND lines look right, change `$DryRun = $true` → `$false` and push again. |
| 4. Restart | Restart the device to flush files Windows queued for deletion. |
| 5. Roll out | Push live mode to the remaining devices. Safe to re-run anywhere. |

## The two modes

One variable controls everything (top of the script, under **Editable defaults**):

```
$DryRun = $true    # DRY RUN (default) — scan and report only. Changes NOTHING.
$DryRun = $false   # LIVE — same scan, actually removes what it finds.
```

There are no other modes. Dry run and live produce identical scans, so a dry-run report is an exact preview of what live mode will do.

## What it does — three phases

### Phase 1 · Assessment (read-only, runs in both modes)

Answers: "did the migration actually complete on this device?"

- Is the Iru agent present? (checks for the UEMAgent service)
- Any Rippling MDM enrollment remnants? (inspected only — never modified)
- Is the Rippling app still installed? (if yes: a restart will not fix it)
- Is a restart pending? (uninstalls queue locked files for deletion at reboot)

### Phase 2 · Sweep (honors the mode switch)

In this order — the order is deliberate, see Safety below:

1. **Scheduled tasks** — incl. `Rippling-Rescuer`, the watchdog, killed first
2. **Service** — `rippling-daemon`
3. **Processes** — Rippling Tray instances
4. **Official uninstaller** — `Uninstall Rippling.exe /allusers /S`, if present
5. **Autostart entries** — Run keys (machine + every user hive)
6. **Folders** — `Program Files\Rippling`, `ProgramData\Rippling`, per-user AppData
7. **Registry** — Rippling entries under the Uninstall keys only
8. **Optional, flag-gated** — Chocolatey and the RipplingAdmin account (see flags below)

### Phase 3 · Summary

Counts (found / removed / failed) plus a one-line RESULT verdict. This is the block to read in the Iru console — read the output bottom-up.

## Reading the RESULT line

| VERDICT | MEANING | YOUR MOVE |
|---|---|---|
| CLEAN | Migration already removed everything. | Nothing — restart if one is pending. |
| DRY RUN complete | Report only; FOUND lines = what live mode would remove. | Review, then flip `$DryRun`. |
| CLEANED | Live run removed everything it found. | Restart the device. |
| PARTIAL | Some items couldn't be removed (usually file locks). | Restart, then re-run the script. |

Every line also lands in a timestamped file on the device:
`C:\ProgramData\Iru\MDMMigration\Logs\rippling_removal_<timestamp>.log`

Exit codes: `0` = clean, dry run complete, or cleaned · `1` = live run with failed removals.

## Optional flags (default: off)

| FLAG | DEFAULT | WHAT ENABLING IT DOES | BEFORE YOU ENABLE IT |
|---|---|---|---|
| `$RemoveRipplingAdmin` | `$false` | Deletes the RipplingAdmin local admin account + its profile. | Confirm another local admin exists on the fleet. On some fleets it's the only local admin, and Iru LAPS is not yet available. Left off, the script just logs a warning. |
| `$RemoveChocolatey` | `$false` | Removes Chocolatey (Rippling's app-install layer on Windows). | Confirm nobody uses choco themselves. Removal doesn't uninstall choco-installed apps — they just become unmanaged. |

Both work the same in either mode and can be done later as a follow-up — nothing forces the decision on day one.

## Safety design

- **Dry-run by default** — first contact with any machine is an audit, not an action.
- **Iru's enrollment cannot be harmed.** Iru's MDM enrollment lives in `HKLM\SOFTWARE\Microsoft\Enrollments`; this script never writes there. Registry **key deletion** is scoped exclusively to the Uninstall records; beyond that, the script removes only individual Rippling autostart values and, if the Chocolatey flag is enabled, its environment variables.
- **Watchdog-safe ordering.** `Rippling-Rescuer` (Rippling's repair task) is removed before the service and processes it protects, so nothing resurrects mid-cleanup.
- **Every removal is verified.** After acting, the script re-checks that the item is actually gone — service queried, task re-listed, path re-tested, registry re-read — and reports FAILED if it isn't, so the summary reflects reality.
- **Idempotent.** Re-running in any mode, on any device state, is safe — devices converge to clean.
- **Out of scope, on purpose:** SentinelOne (even if delivered via Rippling) and MDM enrollments. Removing an EDR is a separate, deliberate decision.

## FAQ

**The dry run found 20+ items — is that bad?** It means the migration's app-uninstall step didn't complete on that device (the MDM handoff can still be fine). That's exactly what this script is for. Flip to live mode.

**Phase 1 says "restart pending" — should I just restart instead?** Only if it also says the Rippling app is *not* installed. Then leftovers are often just files queued for deletion, and a restart clears them — the summary will tell you when that shortcut applies. If the app is still installed, restarting does nothing; run live mode.

**Can I run it twice?** Yes — any mode, any order, any number of times.

**Why do I see "kandji" in the agent detection?** Deliberate, not a branding miss: post-rebrand infrastructure still uses legacy Kandji identifiers, so the agent check matches both to avoid false "agent not detected" warnings. Explained in a comment at that line.

## Version history

- **1.3.1** — Autostart Run-key and Uninstall registry-key removals now verify deletion and report FAILED when an entry survives (previously logged REMOVED unconditionally, which could produce a false CLEANED). Chocolatey folder no longer double-counted in FOUND — dry-run and live counts now match.
- **1.3** — Artifact names corrected from the first field dry run (2026-07-13); agent detection uses word-bounded matching to avoid false positives.
