#!/bin/zsh

################################################################################################
# Rippling Removal for macOS  |  Iru, Inc.  |  v2.0
################################################################################################
#
#   Verbose rewrite of the 2021 rippling_removal.sh (same job, observable behavior).
#   Deploy FROM IRU as a custom script AFTER a device has migrated. Runs as root.
#
#   WHY v2.0 EXISTS - gaps in the original, all observed in the field:
#     - Never killed running processes: deleting Rippling.app leaves the already-
#       running tray process alive, so the menu bar icon persists until logout.
#     - Only unloaded SYSTEM LaunchDaemons; the tray is a per-user LaunchAgent,
#       so it stayed loaded in the user's session even after its plist was deleted.
#     - Receipts loop tested receipt IDs as file paths ([[ -e com.googlecode... ]]),
#       which never matches - pkgutil --forget never actually ran.
#     - remove_rippling forgot the CHEF receipt (copy-paste) instead of Rippling's.
#     - Logged loudly about what it could NOT find, silently removed the rest.
#
################################################################################################
# HOW TO RUN THIS SCRIPT
################################################################################################
#
#   TWO modes, ONE variable (in "Editable defaults" below):
#
#     DRY_RUN="true"   (DEFAULT)  ->  DRY RUN. Scans and REPORTS only. Changes NOTHING.
#     DRY_RUN="false"             ->  LIVE.    Same scan, actually removes findings.
#
#   WORKFLOW: push as-is to one test Mac -> read the SUMMARY block bottom-up in the
#   Iru console -> if the FOUND lines look right, set DRY_RUN="false" and re-push ->
#   confirm "CLEANED" -> roll out. Live mode is idempotent; safe to re-run anywhere.
#
#   OPTIONAL TOGGLE:
#     REMOVE_RIPPLING_ADMIN -> default "false". DELETES A LOCAL ADMIN ACCOUNT.
#                              Confirm another local admin exists before enabling.
#
#   NOT touched, on purpose: MDM enrollment profiles (migration/re-enrollment owns
#   those; inspected read-only here).
#
################################################################################################

# Script version
VERSION="2.0.4"
# 2.0.4 - Added dangling Chef CLI symlink cleanup in /usr/local/bin (section 2g-1);
#         matches by link target (/opt/chef-workstation, /opt/inspec), dry-run aware,
#         deletion verified. No other behavior changed.
# 2.0.3 - Phase 1d no longer self-matches this script (field live run 2026-07-14 warned
#         "processes RUNNING" with none present); 2c kill sweep uses PID snapshot + ps
#         re-verification; the menu-bar closing line now prints only when a process was
#         actually killed this run.
# 2.0.2 - Field dry run 2026-07-14 (v2.0.0) showed the Rippling install
#         root at /usr/local/rippling and per-user data at ~/Library/Application Support/
#         rippling-tray - neither was in the removal list, so a live run would have
#         reported CLEANED with the tray app bundle still on disk. Added /usr/local/rippling
#         to the Phase 1 check and file sweep; per-user Application Support sweep is now
#         discovery-based (*rippling*, case-insensitive) instead of exact-name.
# 2.0.1 - Chef launch-item removal now verifies deletion (was unconditional REMOVED);
#         Chef launch-item glob corrected to com.getchef/com.chef (was com.googlecode.chef,
#         a Munki copy-paste that matched nothing); login-window reset now read-back verified.

################################################################################################
# Editable defaults
################################################################################################

DRY_RUN="true"                  # THE mode switch. "true" = report only. "false" = remove.
REMOVE_RIPPLING_ADMIN="false"   # !! Deletes the RipplingAdmin local account + home dir.
                                # Confirm another local admin exists before enabling.
USER_TO_REMOVE="RipplingAdmin"  # Change only if your Rippling tenant used another name.

################################################################################################
# Logging - stdout (Iru console) + Unified Log. Counters feed the final SUMMARY.
################################################################################################

typeset -a found_items
typeset -a removed_items
typeset -a failed_items

logging() {
  # $1: level  $2: message
  local level="$1"
  local message="$2"
  local timestamp
  timestamp="$(/bin/date +"%Y-%m-%dT%H:%M:%S")"
  /bin/echo "${timestamp} [${level}] ${message}"
  /usr/bin/logger "[rippling_removal] [${level}] ${message}"
}

log_info()  { logging "INFO" "$1"; }
log_warn()  { logging "WARN" "$1"; }
log_find()  { found_items+=("$1");   logging "FOUND" "$1"; }
log_done()  { removed_items+=("$1"); logging "REMOVED" "$1"; }
log_fail()  { failed_items+=("$1");  logging "FAILED" "$1"; }

remove_path_safe() {
  # $1: path to remove (FOUND first, honors DRY_RUN, verifies deletion)
  local target="$1"
  if [[ ! -e "$target" ]]; then
    return 0
  fi
  log_find "Path: ${target}"
  if [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi
  /bin/rm -Rf "$target"
  if [[ -e "$target" ]]; then
    log_fail "Path still present: ${target}"
  else
    log_done "Path: ${target}"
  fi
}

get_console_user() {
  printf '%s' "show State:/Users/ConsoleUser" | /usr/sbin/scutil |
    /usr/bin/awk '/Name :/ && ! /loginwindow/ {print $3}'
}

log_info "================================================================"
log_info "Rippling removal v${VERSION} | DryRun=${DRY_RUN} | Host=$(/bin/hostname -s)"
log_info "================================================================"

################################################################################################
# PHASE 1 - MIGRATION STATE ASSESSMENT (read-only)
################################################################################################
log_info "--- PHASE 1: migration state assessment ---"

# 1a. Iru agent present? (agent binary path is unchanged post-rebrand)
if [[ -e "/usr/local/bin/kandji" ]]; then
  log_info "Iru agent: PRESENT (/usr/local/bin/kandji)"
else
  log_warn "Iru agent: NOT DETECTED. If this script is not running FROM Iru, verify enrollment before cleaning up."
fi

# 1b. Rippling MDM enrollment remnants? (READ-ONLY - never modified here)
if /usr/bin/profiles list 2>/dev/null | /usr/bin/grep -qi "rippling"; then
  log_warn "Rippling configuration profiles still present - migration/re-enrollment should have removed these. NOT touching them here."
else
  log_info "Rippling MDM profiles: NONE (migration did its job)"
fi

# 1c. Rippling app bundles still on disk?
if [[ -e "/Applications/Rippling.app" || -e "/Applications/RipplingMDM.app" || -e "/opt/rippling" || -e "/usr/local/rippling" ]]; then
  log_info "Rippling app/files: STILL ON DISK"
else
  log_info "Rippling app/files: not found on disk"
fi

# 1d. Rippling processes RUNNING? (the menu bar ghost - files can be deleted while
#     the process lives on in memory until logout; the 2021 script never killed these)
#     PIDs are re-verified via ps so this script (whose own path contains "rippling")
#     never counts itself - field live run 2026-07-14 showed a false RUNNING warning
#     from exactly that self-match.
console_user="$(get_console_user)"
rippling_running="false"
for pid in ${(f)"$(/usr/bin/pgrep -if "rippling" 2>/dev/null)"}; do
  [[ -z "$pid" || "$pid" == "$$" ]] && continue
  pcmd="$(/bin/ps -p "$pid" -o command= 2>/dev/null)"
  [[ -z "$pcmd" ]] && continue
  [[ "${pcmd:l}" == *"rippling_removal"* ]] && continue
  rippling_running="true"
  break
done
if [[ "$rippling_running" == "true" ]]; then
  log_warn "Rippling processes RUNNING - this is why the menu bar icon persists even after files are deleted."
else
  log_info "Rippling processes: none running"
fi

################################################################################################
# PHASE 2 - LEFTOVER SWEEP (honors DRY_RUN; every finding logged as FOUND first)
# ORDER: unload agents/daemons -> kill processes -> delete files -> forget receipts.
################################################################################################
log_info "--- PHASE 2: leftover sweep ---"

# 2a. Per-user LaunchAgents - unload from the console user's session, then delete.
#     (The tray icon lives here. The 2021 script deleted the plist but never
#     unloaded it, leaving the agent registered in the running session.)
console_uid=""
if [[ -n "$console_user" ]]; then
  console_uid="$(/usr/bin/id -u "$console_user" 2>/dev/null)"
fi
for agent_plist in /Library/LaunchAgents/com.rippling.*.plist(N) /Users/*/Library/LaunchAgents/com.rippling.*.plist(N); do
  log_find "LaunchAgent: ${agent_plist}"
  if [[ "$DRY_RUN" == "false" ]]; then
    if [[ -n "$console_uid" ]]; then
      /bin/launchctl bootout "gui/${console_uid}" "$agent_plist" 2>/dev/null
    fi
    /bin/rm -f "$agent_plist"
    if [[ -e "$agent_plist" ]]; then
      log_fail "LaunchAgent still present: ${agent_plist}"
    else
      log_done "LaunchAgent: ${agent_plist}"
    fi
  fi
done

# 2b. System LaunchDaemons - bootout (modern launchctl), then delete
for daemon_plist in /Library/LaunchDaemons/com.rippling.*.plist(N); do
  log_find "LaunchDaemon: ${daemon_plist}"
  if [[ "$DRY_RUN" == "false" ]]; then
    /bin/launchctl bootout system "$daemon_plist" 2>/dev/null
    /bin/rm -f "$daemon_plist"
    if [[ -e "$daemon_plist" ]]; then
      log_fail "LaunchDaemon still present: ${daemon_plist}"
    else
      log_done "LaunchDaemon: ${daemon_plist}"
    fi
  fi
done

# 2c. Kill running Rippling processes (excluding this script and its own tooling).
#     PIDs snapshotted first, each re-verified via ps - no pipeline stage carrying the
#     search pattern in its argv exists concurrently with pgrep to self-match.
for pid in ${(f)"$(/usr/bin/pgrep -if "rippling" 2>/dev/null)"}; do
  [[ -z "$pid" || "$pid" == "$$" ]] && continue
  pcmd="$(/bin/ps -p "$pid" -o command= 2>/dev/null)"
  [[ -z "$pcmd" ]] && continue
  [[ "${pcmd:l}" == *"rippling_removal"* ]] && continue
  pname="$(/bin/ps -p "$pid" -o comm= 2>/dev/null)"
  log_find "Process: ${pname:-unknown} (PID ${pid})"
  if [[ "$DRY_RUN" == "false" ]]; then
    /bin/kill -TERM "$pid" 2>/dev/null
    /bin/sleep 1
    if /bin/kill -0 "$pid" 2>/dev/null; then
      /bin/kill -KILL "$pid" 2>/dev/null
    fi
    if /bin/kill -0 "$pid" 2>/dev/null; then
      log_fail "Process would not die: ${pname} (PID ${pid})"
    else
      log_done "Process killed: ${pname} (PID ${pid})"
    fi
  fi
done

# 2d. Rippling files and folders
remove_path_safe "/opt/rippling"
remove_path_safe "/opt/rippling-readonly"
remove_path_safe "/usr/local/rippling"
remove_path_safe "/Applications/Rippling.app"
remove_path_safe "/Applications/RipplingMDM.app"
remove_path_safe "/Library/Application Support/Rippling"
for user_home in /Users/*(N/); do
  # Discovery-based per-user sweep: catches "Rippling", "rippling-tray", and case
  # variants (field dry run 2026-07-14 showed ~/Library/Application Support/rippling-tray,
  # which an exact "Rippling" match missed).
  for support_dir in "${user_home}/Library/Application Support"/*(N); do
    if [[ "${support_dir:t:l}" == *rippling* ]]; then
      remove_path_safe "$support_dir"
    fi
  done
done

# 2e. Package receipts - discovery-based, and actually functional (the 2021 script
#     tested receipt IDs as file paths, so --forget never ran)
for receipt in $(/usr/sbin/pkgutil --pkgs 2>/dev/null | /usr/bin/grep -i "rippling"); do
  log_find "Package receipt: ${receipt}"
  if [[ "$DRY_RUN" == "false" ]]; then
    if /usr/sbin/pkgutil --forget "$receipt" >/dev/null 2>&1; then
      log_done "Package receipt: ${receipt}"
    else
      log_fail "Package receipt: ${receipt}"
    fi
  fi
done

# 2f. Munki (Rippling's app-delivery layer on macOS, when deployed) - agents,
#     daemons, files, receipts. Discovery-based rather than a hardcoded list.
for munki_plist in /Library/LaunchDaemons/com.googlecode.munki.*.plist(N) /Library/LaunchAgents/com.googlecode.munki.*.plist(N); do
  log_find "Munki launch item: ${munki_plist}"
  if [[ "$DRY_RUN" == "false" ]]; then
    /bin/launchctl bootout system "$munki_plist" 2>/dev/null
    /bin/rm -f "$munki_plist"
    if [[ -e "$munki_plist" ]]; then
      log_fail "Munki launch item still present: ${munki_plist}"
    else
      log_done "Munki launch item: ${munki_plist}"
    fi
  fi
done
remove_path_safe "/Applications/Managed Software Center.app"
remove_path_safe "/Applications/Utilities/Managed Software Update.app"
remove_path_safe "/Library/Managed Installs"
remove_path_safe "/Library/Preferences/ManagedInstalls.plist"
remove_path_safe "/usr/local/munki"
remove_path_safe "/etc/paths.d/munki"
for receipt in $(/usr/sbin/pkgutil --pkgs 2>/dev/null | /usr/bin/grep -i "com.googlecode.munki"); do
  log_find "Munki receipt: ${receipt}"
  if [[ "$DRY_RUN" == "false" ]]; then
    if /usr/sbin/pkgutil --forget "$receipt" >/dev/null 2>&1; then
      log_done "Munki receipt: ${receipt}"
    else
      log_fail "Munki receipt: ${receipt}"
    fi
  fi
done

# 2g. Chef (part of Rippling's legacy macOS stack, when deployed)
for chef_plist in /Library/LaunchDaemons/com.getchef.*.plist(N) /Library/LaunchDaemons/com.chef.*.plist(N); do
  log_find "Chef launch item: ${chef_plist}"
  if [[ "$DRY_RUN" == "false" ]]; then
    /bin/launchctl bootout system "$chef_plist" 2>/dev/null
    /bin/rm -f "$chef_plist"
    if [[ -e "$chef_plist" ]]; then
      log_fail "Chef launch item still present: ${chef_plist}"
    else
      log_done "Chef launch item: ${chef_plist}"
    fi
  fi
done
remove_path_safe "/opt/chef-workstation"
remove_path_safe "/opt/inspec"

# 2g-1. Chef CLI symlinks in /usr/local/bin (Chef Workstation drops chef/knife/
#     inspec shortcuts here that point back into /opt/chef-workstation or /opt/inspec).
#     The folders above are removed, but these shortcuts are otherwise left dangling.
#     Matched by where the link POINTS, not by name - so a dry run and a live run
#     report the same items (in dry run the folders still exist; we match either way).
for cli_link in /usr/local/bin/*(N@); do
  link_target="$(/usr/bin/readlink "$cli_link" 2>/dev/null)"
  if [[ "$link_target" == */opt/chef-workstation/* || "$link_target" == */opt/inspec/* ]]; then
    log_find "Chef symlink: ${cli_link} -> ${link_target}"
    if [[ "$DRY_RUN" == "false" ]]; then
      /bin/rm -f "$cli_link"
      if [[ -L "$cli_link" ]]; then
        log_fail "Chef symlink still present: ${cli_link}"
      else
        log_done "Chef symlink: ${cli_link}"
      fi
    fi
  fi
done

for receipt in $(/usr/sbin/pkgutil --pkgs 2>/dev/null | /usr/bin/grep -iE "com\.(get)?chef\."); do
  log_find "Chef receipt: ${receipt}"
  if [[ "$DRY_RUN" == "false" ]]; then
    if /usr/sbin/pkgutil --forget "$receipt" >/dev/null 2>&1; then
      log_done "Chef receipt: ${receipt}"
    else
      log_fail "Chef receipt: ${receipt}"
    fi
  fi
done

# 2h. Login window text set by Rippling (reset only if one is actually set)
current_lw_text="$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow LoginwindowText 2>/dev/null)"
if [[ -n "$current_lw_text" ]]; then
  log_find "Login window text: '${current_lw_text}'"
  if [[ "$DRY_RUN" == "false" ]]; then
    /usr/bin/defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText ""
    post_lw_text="$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow LoginwindowText 2>/dev/null)"
    if [[ -n "$post_lw_text" ]]; then
      log_fail "Login window text still set: '${post_lw_text}'"
    else
      log_done "Login window text reset"
    fi
  fi
fi

# 2i. Local admin account - flag-gated (may be the only local admin on the device)
if /usr/bin/dscl . -read "/Users/${USER_TO_REMOVE}" >/dev/null 2>&1; then
  if [[ "$REMOVE_RIPPLING_ADMIN" == "true" ]]; then
    log_find "Local account: ${USER_TO_REMOVE}"
    if [[ "$DRY_RUN" == "false" ]]; then
      /bin/rm -Rf "/Users/${USER_TO_REMOVE}"
      /usr/bin/dscl . -delete "/Users/${USER_TO_REMOVE}"
      if /usr/bin/dscl . -read "/Users/${USER_TO_REMOVE}" >/dev/null 2>&1; then
        log_fail "Account: ${USER_TO_REMOVE}"
      else
        log_done "Account + home dir: ${USER_TO_REMOVE}"
      fi
    fi
  else
    log_warn "Local account '${USER_TO_REMOVE}' present but LEFT IN PLACE (REMOVE_RIPPLING_ADMIN=false). Confirm another local admin exists before enabling removal."
  fi
else
  log_info "Local account '${USER_TO_REMOVE}': not present"
fi

################################################################################################
# PHASE 3 - SUMMARY (read the Iru console output bottom-up; this block is the verdict)
################################################################################################
log_info "================================================================"
log_info "SUMMARY"
if [[ "$DRY_RUN" == "true" ]]; then
  log_info "  Mode:               DRY RUN - nothing was changed"
else
  log_info "  Mode:               LIVE"
fi
log_info "  Leftovers found:    ${#found_items[@]}"
log_info "  Removed:            ${#removed_items[@]}"
log_info "  Failed to remove:   ${#failed_items[@]}"

if [[ ${#found_items[@]} -eq 0 ]]; then
  log_info "RESULT: CLEAN. No Rippling stack artifacts remain on this Mac."
elif [[ "$DRY_RUN" == "true" ]]; then
  log_info "RESULT: DRY RUN complete. Review FOUND lines above; if they look right, set DRY_RUN=\"false\" and re-push."
elif [[ ${#failed_items[@]} -gt 0 ]]; then
  log_warn "RESULT: PARTIAL. ${#failed_items[@]} item(s) could not be removed - see FAILED lines. Re-run after a restart."
else
  log_info "RESULT: CLEANED. ${#removed_items[@]} leftover(s) removed."
  if [[ "${removed_items[*]}" == *"Process killed"* ]]; then
    log_info "        If a menu bar icon lingers, it dies at next logout/restart - the process was killed and nothing remains to relaunch it."
  fi
fi
log_info "================================================================"

if [[ "$DRY_RUN" == "false" && ${#failed_items[@]} -gt 0 ]]; then
  exit 1
fi
exit 0
