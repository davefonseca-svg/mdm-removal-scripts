#!/bin/zsh

################################################################################################
# __PRODUCT__ Removal for macOS  |  Iru, Inc.  |  vX.Y.Z
################################################################################################
#
#   TEMPLATE (template_removal_macos.sh v1.0.0) - implements the MDM Removal Script Standard
#   (Operator Contract v1.0). Authors fill in the FILL-IN blocks in Phase 2 ONLY; the
#   scaffolding (mode switch, logging, counters, verification, summary, exit codes) is the
#   contract and must not be modified.
#
#   Deploy FROM IRU as a custom script AFTER a device has migrated. Runs as root.
#
#   AUTHOR CHECKLIST before first customer use:
#     [ ] Replace every __PRODUCT__ / __product__ token
#     [ ] Fill Phase 2 artifact lists from a REAL dry run on a device that ran the product
#     [ ] Confirm launch-item label prefixes (com.__product__.*) against actual plists
#     [ ] Decide flag-gated items (accounts, shared tooling) - default them OFF
#     [ ] Field-verify: dry run on one device, review FOUND lines, then live on one device
#     [ ] Set VERSION to 1.0.0 and record the field-verification date below
#
#   Field-verified: __DATE__ on __MACOS_VERSION__ against __PRODUCT__ agent __AGENT_VERSION__
#
################################################################################################
# HOW TO RUN THIS SCRIPT  (identical for every script in this repository - Contract C1/C7)
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
#   NOT touched, on purpose (Contract scope): MDM enrollment profiles - migration and
#   re-enrollment own those; they are inspected read-only in Phase 1 and never modified.
#
################################################################################################
# License Information
################################################################################################
# Copyright 2026 Iru, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
# to whom the Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or
# substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
# PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
# FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.
################################################################################################

# Script version (C12: semver; printed at runtime by the banner - field logs self-identify)
VERSION="0.0.0-template"

################################################################################################
# Editable defaults  (C1, C6)
################################################################################################

DRY_RUN="true"                  # THE mode switch. "true" = report only. "false" = remove.

# --- FILL-IN: flag-gated destructive options (C6). One variable per irreversible or
# --- shared-dependency item, default OFF, warning comment at the definition. Delete this
# --- example block if the product creates nothing of the kind.
REMOVE___PRODUCT___ADMIN="false"   # !! Deletes a LOCAL ADMIN ACCOUNT + home dir.
                                   # Confirm another local admin exists before enabling.
USER_TO_REMOVE="__ProductAdmin__"  # Change only if the tenant used another name.

################################################################################################
# Logging - stdout (Iru console) + Unified Log. Counters feed the final SUMMARY.
# (C3, C4, C9 - DO NOT MODIFY)
################################################################################################

typeset -a found_items
typeset -a removed_items
typeset -a failed_items

logging() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp="$(/bin/date +"%Y-%m-%dT%H:%M:%S")"
  /bin/echo "${timestamp} [${level}] ${message}"
  /usr/bin/logger "[__product___removal] [${level}] ${message}"
}

log_info()  { logging "INFO" "$1"; }
log_warn()  { logging "WARN" "$1"; }
log_find()  { found_items+=("$1");   logging "FOUND" "$1"; }
log_done()  { removed_items+=("$1"); logging "REMOVED" "$1"; }
log_fail()  { failed_items+=("$1");  logging "FAILED" "$1"; }

# C4 in function form: FOUND first, honors DRY_RUN, verifies deletion, FAILED on survival.
remove_path_safe() {
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

# Unload a launch item from the right domain, delete it, verify. (C4, C5)
# $1: plist path   $2: "system" or a console uid for gui/<uid>
remove_launch_item_safe() {
  local plist="$1"
  local domain="$2"
  log_find "Launch item: ${plist}"
  if [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi
  if [[ "$domain" == "system" ]]; then
    /bin/launchctl bootout system "$plist" 2>/dev/null
  elif [[ -n "$domain" ]]; then
    /bin/launchctl bootout "gui/${domain}" "$plist" 2>/dev/null
  fi
  /bin/rm -f "$plist"
  if [[ -e "$plist" ]]; then
    log_fail "Launch item still present: ${plist}"
  else
    log_done "Launch item: ${plist}"
  fi
}

# Forget a pkgutil receipt, verify via pkgutil's own exit status. (C4)
forget_receipt_safe() {
  local receipt="$1"
  log_find "Package receipt: ${receipt}"
  if [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi
  if /usr/sbin/pkgutil --forget "$receipt" >/dev/null 2>&1; then
    log_done "Package receipt: ${receipt}"
  else
    log_fail "Package receipt: ${receipt}"
  fi
}

get_console_user() {
  printf '%s' "show State:/Users/ConsoleUser" | /usr/sbin/scutil |
    /usr/bin/awk '/Name :/ && ! /loginwindow/ {print $3}'
}

log_info "================================================================"
log_info "__PRODUCT__ removal v${VERSION} | DryRun=${DRY_RUN} | Host=$(/bin/hostname -s)"
log_info "================================================================"

################################################################################################
# PHASE 1 - MIGRATION STATE ASSESSMENT (read-only, both modes - C2)
################################################################################################
log_info "--- PHASE 1: migration state assessment ---"

# 1a. Iru agent present? (agent binary path unchanged post-rebrand - deliberate, not a miss)
if [[ -e "/usr/local/bin/kandji" ]]; then
  log_info "Iru agent: PRESENT (/usr/local/bin/kandji)"
else
  log_warn "Iru agent: NOT DETECTED. If this script is not running FROM Iru, verify enrollment before cleaning up."
fi

# 1b. __PRODUCT__ MDM enrollment remnants? (READ-ONLY - never modified here)
if /usr/bin/profiles list 2>/dev/null | /usr/bin/grep -qi "__product__"; then
  log_warn "__PRODUCT__ configuration profiles still present - migration/re-enrollment should have removed these. NOT touching them here."
else
  log_info "__PRODUCT__ MDM profiles: NONE (migration did its job)"
fi

# 1c. --- FILL-IN: is the product's primary footprint still on disk? Report only. ---
# if [[ -e "/Applications/__Product__.app" ]]; then
#   log_info "__PRODUCT__ app/files: STILL ON DISK"
# else
#   log_info "__PRODUCT__ app/files: not found on disk"
# fi

# 1d. Product processes RUNNING? (files can be deleted while a process lives in memory)
console_user="$(get_console_user)"
if /usr/bin/pgrep -if "__product__" | /usr/bin/grep -qv "^$$\$"; then
  log_warn "__PRODUCT__ processes RUNNING - deleting files alone will not clear a resident process."
else
  log_info "__PRODUCT__ processes: none running"
fi

################################################################################################
# PHASE 2 - LEFTOVER SWEEP (honors DRY_RUN; every finding logged FOUND first - C3, C4)
# ORDER (C5 - do not reorder): unload launch items -> kill processes -> delete files ->
# forget receipts -> flag-gated extras. Watchdogs/relaunchers must die before their payloads.
################################################################################################
log_info "--- PHASE 2: leftover sweep ---"

console_uid=""
if [[ -n "$console_user" ]]; then
  console_uid="$(/usr/bin/id -u "$console_user" 2>/dev/null)"
fi

# 2a. Per-user LaunchAgents  --- FILL-IN: label prefix ---
for agent_plist in /Library/LaunchAgents/com.__product__.*.plist(N) /Users/*/Library/LaunchAgents/com.__product__.*.plist(N); do
  remove_launch_item_safe "$agent_plist" "$console_uid"
done

# 2b. System LaunchDaemons  --- FILL-IN: label prefix ---
for daemon_plist in /Library/LaunchDaemons/com.__product__.*.plist(N); do
  remove_launch_item_safe "$daemon_plist" "system"
done

# 2c. Kill running product processes (excluding this script and its own tooling).
#     PIDs are snapshotted first ($(...)), so no pipeline stage carrying the search
#     pattern in its argv exists concurrently with pgrep to self-match; each PID is
#     then re-verified via ps (it may have exited, or be our own subshell).
for pid in ${(f)"$(/usr/bin/pgrep -if "__product__" 2>/dev/null)"}; do
  [[ -z "$pid" || "$pid" == "$$" ]] && continue
  pcmd="$(/bin/ps -p "$pid" -o command= 2>/dev/null)"
  [[ -z "$pcmd" ]] && continue                                 # exited since snapshot
  [[ "${pcmd:l}" == *"__product___removal"* ]] && continue     # our own tooling
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

# 2d. Files and folders  --- FILL-IN: field-verified paths. Sweep EVERY user home, not
# --- just the console user (a login-window run must still clean real users). ---
remove_path_safe "/Applications/__Product__.app"
remove_path_safe "/Library/Application Support/__Product__"
for user_home in /Users/*(N/); do
  remove_path_safe "${user_home}/Library/Application Support/__Product__"
  # Preferences: discovery-based and case-insensitive
  for pref in "${user_home}"/Library/Preferences/*(N); do
    if [[ "${pref:t:l}" == *__product__* ]]; then
      remove_path_safe "$pref"
    fi
  done
done

# 2e. Package receipts - discovery-based
for receipt in $(/usr/sbin/pkgutil --pkgs 2>/dev/null | /usr/bin/grep -i "__product__"); do
  forget_receipt_safe "$receipt"
done

# 2f. --- FILL-IN: product-specific extras (delivery layers, login-window text, etc.).
# --- Use remove_path_safe / remove_launch_item_safe / forget_receipt_safe so C4 holds.
# --- Anything irreversible or shared: flag-gate it (C6) like the account block below. ---

# 2g. Local admin account - flag-gated (C6). Delete block if not applicable.
if /usr/bin/dscl . -read "/Users/${USER_TO_REMOVE}" >/dev/null 2>&1; then
  if [[ "$REMOVE___PRODUCT___ADMIN" == "true" ]]; then
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
    log_warn "Local account '${USER_TO_REMOVE}' present but LEFT IN PLACE (flag=false). Confirm another local admin exists before enabling removal."
  fi
else
  log_info "Local account '${USER_TO_REMOVE}': not present"
fi

################################################################################################
# PHASE 3 - SUMMARY (C7, C8 - DO NOT MODIFY; read the Iru console output bottom-up)
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
  log_info "RESULT: CLEAN. No __PRODUCT__ stack artifacts remain on this Mac."
elif [[ "$DRY_RUN" == "true" ]]; then
  log_info "RESULT: DRY RUN complete. Review FOUND lines above; if they look right, set DRY_RUN=\"false\" and re-push."
elif [[ ${#failed_items[@]} -gt 0 ]]; then
  log_warn "RESULT: PARTIAL. ${#failed_items[@]} item(s) could not be removed - see FAILED lines. Re-run after a restart."
else
  log_info "RESULT: CLEANED. ${#removed_items[@]} leftover(s) removed."
fi
log_info "================================================================"

if [[ "$DRY_RUN" == "false" && ${#failed_items[@]} -gt 0 ]]; then
  exit 1
fi
exit 0
