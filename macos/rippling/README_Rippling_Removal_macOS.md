# Rippling Removal for macOS

**rippling_removal_macos.sh · v2.0.3 · Iru, Inc.**

Removes leftover Rippling components from Mac devices after they have migrated to Iru. A verbose rewrite of Iru's 2021 rippling_removal.sh — same job, same observable behavior, with the gaps from the original closed.

**Ships safe by default.** As delivered, the script runs in dry-run mode — it scans, reports, and changes nothing. You must edit one line to make it act.

## Quick start

| STEP | WHAT TO DO |
|---|---|
| 1. Dry run | Push the script as-is from the Iru console (Custom Script library item, runs as root) to one test Mac. |
| 2. Read the verdict | Open the script output in the Iru console and read the SUMMARY block at the bottom. |
| 3. Go live | If the FOUND lines look right, change `DRY_RUN="true"` → `"false"` and push again. |
| 4. Log out / restart | If a Rippling menu-bar icon is still visible, log out or restart to clear it — the process was already stopped. |
| 5. Roll out | Push live mode to the remaining devices. Safe to re-run anywhere. |

## The two modes

One variable controls everything (top of the script, under **Editable defaults**):

```
DRY_RUN="true"    # DRY RUN (default) — scan and report only. Changes NOTHING.
DRY_RUN="false"   # LIVE — same scan, actually removes what it finds.
```

There are no other modes. Dry run and live produce identical scans, so a dry-run report is an exact preview of what live mode will do.

## What it does — three phases

### Phase 1 · Assessment (read-only, runs in both modes)

Answers: "did the migration actually complete on this device?"

- Is the Iru agent present? (checks for `/usr/local/bin/kandji`)
- Any Rippling MDM enrollment remnants? (inspected only — never modified)
- Is the Rippling app still on disk? (`Rippling.app`, `RipplingMDM.app`, `/opt/rippling`, `/usr/local/rippling`)
- Are any Rippling processes running? (the reason a menu-bar icon can persist after files are gone)

### Phase 2 · Sweep (honors the mode switch)

In this order — the order is deliberate, see Safety below:

1. **Per-user LaunchAgents** — unloaded from the signed-in user's session, then removed
2. **System LaunchDaemons** — booted out, then removed
3. **Processes** — any running Rippling process (this script excludes itself)
4. **Files & folders** — `/opt/rippling`, `/usr/local/rippling`, the app bundles, and every user's Application Support folders matching Rippling (e.g., `Rippling`, `rippling-tray`)
5. **Package receipts** — every pkgutil receipt matching Rippling
6. **Munki** — launch items, Managed Software Center, managed-install files, and receipts, where deployed
7. **Chef** — launch items, `chef-workstation` / `inspec`, and receipts, where deployed
8. **Login-window text** — reset only if Rippling had set one

### Phase 3 · Summary

Counts (found / removed / failed) plus a one-line RESULT verdict. This is the block to read in the Iru console — read the output bottom-up.

## Reading the RESULT line

| VERDICT | MEANING | YOUR MOVE |
|---|---|---|
| CLEAN | Migration already removed everything. | Nothing to do. |
| DRY RUN complete | Report only; FOUND lines = what live mode would remove. | Review, then flip `DRY_RUN`. |
| CLEANED | Live run removed everything it found. | Log out / restart if a menu-bar icon lingers. |
| PARTIAL | Some items couldn't be removed. | Restart, then re-run the script. |

Output goes to two places: the Iru console (standard output) and the macOS unified log (tagged `[rippling_removal]`, viewable with `log show` or Console.app). The script does not write its own log file.

Exit codes: `0` = clean, dry run complete, or cleaned · `1` = live run with failed removals.

## Optional flag (default: off)

| FLAG | DEFAULT | WHAT ENABLING IT DOES | BEFORE YOU ENABLE IT |
|---|---|---|---|
| `REMOVE_RIPPLING_ADMIN` | `"false"` | Deletes the RipplingAdmin local admin account + its home directory. | Confirm another local admin exists on the device. On some fleets it's the only local admin. Left off, the script just logs a warning. |

The account name is set by `USER_TO_REMOVE="RipplingAdmin"` — change it only if your Rippling tenant used a different name. The flag works the same in either mode and can be handled later as a follow-up; nothing forces the decision on day one.

> **Note on Munki and Chef.** Unlike the Windows script's Chocolatey flag, Munki and Chef removal on macOS is part of the standard sweep, not a separate toggle — they are removed when present because they were part of Rippling's delivery stack. If your environment uses Munki or Chef independently of Rippling, scope those sections out before running live.

## Safety design

- **Dry-run by default** — first contact with any machine is an audit, not an action.
- **Enrollment is inspected, never touched.** Rippling's MDM configuration profiles are read with `profiles list` for reporting only; the script never removes a profile. Migration and re-enrollment own that.
- **Relaunch-safe ordering.** Launch agents and daemons are unloaded before their processes are killed and their files deleted, so launchd can't relaunch a component mid-cleanup.
- **Every removal is verified.** After deleting a path, the script re-checks that it's gone and reports FAILED if it isn't, so the summary reflects reality.
- **Idempotent.** Re-running in any mode, on any device state, is safe — devices converge to clean.
- **Out of scope, on purpose:** MDM enrollment profiles (above) and the local admin account (unless you enable the flag).

## FAQ

**The dry run found a bunch of items — is that bad?** It means the migration's app-removal step didn't fully complete on that device (the MDM handoff can still be fine). That's exactly what this script is for. Flip to live mode.

**The Rippling menu-bar icon is still there right after a live run — did it fail?** No. If the summary says CLEANED and shows a "Process killed" line, the process was stopped and its files removed; the icon you're seeing is the last frame of a stopped process. It clears at the next logout or restart, and nothing remains on the device to bring it back. (The summary's menu-bar note only appears on runs where a process was actually killed.)

**Can I run it twice?** Yes — any mode, any order, any number of times.

**Why do I see "kandji" in the agent detection?** Deliberate, not a branding miss: the agent binary path is unchanged post-rebrand, so the agent check looks for `/usr/local/bin/kandji`. Explained in a comment at that line.

## Version history

- **2.0.3** — Phase 1 process check no longer self-matches the script itself (a field live run showed a false "processes RUNNING" warning); process kill sweep hardened the same way; the menu-bar note in the summary now prints only when a process was actually killed that run.
- **2.0.2** — Field dry run (2026-07-14) revealed the Rippling install root at `/usr/local/rippling` and per-user data at `~/Library/Application Support/rippling-tray`; both added to the assessment and sweep. Per-user Application Support matching is now discovery-based rather than exact-name.
- **2.0.1** — Chef launch-item removal now verifies deletion; Chef launch-item matching corrected to Chef's actual namespaces (`com.getchef` / `com.chef`); login-window reset read-back verified.
- **2.0.0** — Verbose rewrite of the 2021 script: dry-run mode, phased structure, verified removals, verdicts, exit codes.
