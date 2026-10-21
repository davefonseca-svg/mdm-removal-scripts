#!/bin/zsh

################################################################################################
# Rippling Removal for macOS  |  Iru, Inc.  |  v2.0.6
################################################################################################
#
#   Removes leftover Rippling components from Macs after they migrate to Iru.
#   Deploy from Iru as a Custom Script. Runs as root.
#
#   Originally created by Matt Wilson (v1.x, 09/28/2021 - 08/19/2025).
#   v2.0 rewrite by Dave Fonseca.
#
################################################################################################
# CHANGELOG
################################################################################################
#
#   v2.0.6 - Ground-up rewrite of v1.2.2.
#            - Fixes the Rippling menu-bar icon persisting after cleanup: LaunchAgents are
#              now unloaded from the signed-in user's session (gui/<uid>) instead of the
#              system domain, and any still-running Rippling processes are stopped.
#            - Adds DRY_RUN mode (default "true" = report only, changes nothing).
#            - Adds timestamped logging (Iru console + unified log) and a SUMMARY block.
#            - Verifies every removal and reports anything that survived.
#            - Discovers Rippling, Munki, and Chef package receipts by pattern.
#            - Fixes Chef symlink cleanup (v1.2.2 pattern never matched).
#            - Rippling admin account removal is now opt-in (REMOVE_RIPPLING_ADMIN) and
#              blocked if the account is signed in, is the last local admin, or is the
#              only admin holding a Secure Token (protects FileVault unlock).
#            - Reports, but never modifies, MDM enrollment and configuration profiles.
#
################################################################################################
# HOW TO RUN THIS SCRIPT
################################################################################################
#
#   TWO modes, ONE setting (under "Editable defaults" below):
#
#     DRY_RUN="true"   (DEFAULT)  ->  DRY RUN. Scans and reports only. Changes nothing.
#     DRY_RUN="false"             ->  LIVE.    Same scan, then removes what it finds.
#
#   WORKFLOW: push as-is to one test Mac -> read the SUMMARY block at the bottom of the
#   output in the Iru console -> if the FOUND lines look right, set DRY_RUN="false" and
#   push again -> confirm "CLEANED" -> roll out. Safe to re-run in either mode.
#
#   OPTIONAL SETTING:
#     REMOVE_RIPPLING_ADMIN -> default "false". Removes the Rippling local admin account,
#                              only if its safety checks pass (see section 2i). Run a dry
#                              run with it on first to see whether removal is allowed.
#
#   NOT touched, on purpose: MDM enrollment and configuration profiles. They are
#   reported only; your migration process handles them.
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
#
################################################################################################

# Script version
VERSION="2.0.6"

################################################################################################
# Editable defaults
################################################################################################

DRY_RUN="true"                  # The mode setting. "true" = report only. "false" = remove.
REMOVE_RIPPLING_ADMIN="false"   # "true" = remove the Rippling admin account and its home
                                # folder, if its safety checks pass (see section 2i).
USER_TO_REMOVE="RipplingAdmin"  # Change only if your Rippling setup used a different name.

################################################################################################
# Logging - output goes to the Iru console and the macOS unified log. Counts feed the SUMMARY.
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
  # $1: path to remove. Logs FOUND first, follows DRY_RUN, and verifies the deletion.
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

# 1a. Is the Iru agent installed? (The agent is installed at /usr/local/bin/kandji.)
if [[ -e "/usr/local/bin/kandji" ]]; then
  log_info "Iru agent: PRESENT (/usr/local/bin/kandji)"
else
  log_warn "Iru agent: NOT DETECTED. If this script is not running FROM Iru, verify enrollment before cleaning up."
fi

# 1b. Any Rippling configuration profiles left? (Reported only - never modified.)
if /usr/bin/profiles list 2>/dev/null | /usr/bin/grep -qi "rippling"; then
  log_warn "Rippling configuration profiles still present - migration/re-enrollment should have removed these. NOT touching them here."
else
  log_info "Rippling MDM profiles: NONE (migration did its job)"
fi

# 1c. Is the Rippling app still on disk?
if [[ -e "/Applications/Rippling.app" || -e "/Applications/RipplingMDM.app" || -e "/opt/rippling" || -e "/usr/local/rippling" ]]; then
  log_info "Rippling app/files: STILL ON DISK"
else
  log_info "Rippling app/files: not found on disk"
fi

# 1d. Are Rippling processes still running? A process can keep running (and keep its
#     menu-bar icon) after its files are deleted. Each match is re-checked with ps so
#     this script, whose own name contains "rippling", never counts itself.
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
# PHASE 2 - LEFTOVER SWEEP (follows DRY_RUN; every finding is logged as FOUND first)
# ORDER: unload agents/daemons -> stop processes -> delete files -> forget receipts,
# so nothing can relaunch mid-cleanup.
################################################################################################
log_info "--- PHASE 2: leftover sweep ---"

# 2a. Rippling LaunchAgents - unloaded from the signed-in user's session, then deleted.
#     The Rippling menu-bar app runs from here.
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

# 2b. Rippling LaunchDaemons - unloaded from the system, then deleted.
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

# 2c. Stop any Rippling processes still running (this script is excluded).
#     Each match is re-checked with ps before it is stopped.
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

# 2d. Rippling files and folders.
remove_path_safe "/opt/rippling"
remove_path_safe "/opt/rippling-readonly"
remove_path_safe "/usr/local/rippling"
remove_path_safe "/Applications/Rippling.app"
remove_path_safe "/Applications/RipplingMDM.app"
remove_path_safe "/Library/Application Support/Rippling"
for user_home in /Users/*(N/); do
  # Every user's Application Support folders whose names contain "rippling" (any case),
  # e.g. "Rippling" and "rippling-tray".
  for support_dir in "${user_home}/Library/Application Support"/*(N); do
    if [[ "${support_dir:t:l}" == *rippling* ]]; then
      remove_path_safe "$support_dir"
    fi
  done
done

# 2e. Package receipts - every installer receipt whose ID contains "rippling".
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

# 2f. Munki, which Rippling used to deliver software - launch items, files, and
#     receipts, where present. If you use Munki independently of Rippling, remove this
#     section before running live.
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

# 2g. Chef, which Rippling used on some Macs - launch items, files, and receipts, where
#     present. If you use Chef independently of Rippling, remove this section (and 2g-1)
#     before running live.
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

# 2g-1. Chef command shortcuts in /usr/local/bin. Chef Workstation creates shortcuts here
#     that point into /opt/chef-workstation or /opt/inspec. They are matched by where they
#     point, not by name, so a dry run and a live run report the same items.
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

# 2h. Custom login-window text - cleared only if some is set.
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

# 2i. Rippling local admin account - only if REMOVE_RIPPLING_ADMIN="true".
#     Safety checks run in both modes, so a dry run shows whether removal would be allowed.
#     Removal is blocked if the account is signed in, if no other local admin exists, or if
#     it is the only admin with a Secure Token (on a FileVault-encrypted Mac, that account
#     may be the only one able to unlock the disk). The account is deleted with Apple's
#     sysadminctl tool. Its home folder is read from the account record and removed only
#     after the account is confirmed gone, and only if it still belongs to that account.
account_blocked="false"
integer account_failures=0   # account-related FAILED lines, so the summary can explain them
if /usr/bin/dscl . -read "/Users/${USER_TO_REMOVE}" >/dev/null 2>&1; then
  if [[ "$REMOVE_RIPPLING_ADMIN" == "true" ]]; then
    log_find "Local account: ${USER_TO_REMOVE}"
    # Home folder path, read from the account record (handles spaces in the path).
    acct_home="$(/usr/bin/dscl . -read "/Users/${USER_TO_REMOVE}" NFSHomeDirectory 2>/dev/null |
      /usr/bin/sed -e 's/^NFSHomeDirectory://' | /usr/bin/tr -d '\n' |
      /usr/bin/sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    acct_uid="$(/usr/bin/dscl . -read "/Users/${USER_TO_REMOVE}" UniqueID 2>/dev/null | /usr/bin/awk '{print $2}')"
    block_reason=""

    # Check 1: the account must not be signed in.
    if /usr/bin/who | /usr/bin/awk '{print $1}' | /usr/bin/grep -qix "$USER_TO_REMOVE"; then
      block_reason="account is currently logged in"
    fi

    # Check 2: at least one other local admin account must exist.
    if [[ -z "$block_reason" ]]; then
      other_admins=0
      for u in ${(f)"$(/usr/bin/dscl . -list /Users UniqueID | /usr/bin/awk '$2 >= 500 {print $1}')"}; do
        [[ "${u:l}" == "${USER_TO_REMOVE:l}" ]] && continue
        /usr/sbin/dseditgroup -o checkmember -m "$u" admin 2>/dev/null | /usr/bin/grep -q "^yes" || continue
        (( other_admins++ ))
      done
      if (( other_admins == 0 )); then
        block_reason="no other local admin account exists on this Mac - create one first"
      fi
    fi

    # Check 3: if this account has a Secure Token, another admin with one must exist.
    if [[ -z "$block_reason" ]] && \
       /usr/sbin/sysadminctl -secureTokenStatus "$USER_TO_REMOVE" 2>&1 | /usr/bin/grep -q "ENABLED"; then
      other_token_admins=0
      for u in ${(f)"$(/usr/bin/dscl . -list /Users UniqueID | /usr/bin/awk '$2 >= 500 {print $1}')"}; do
        [[ "${u:l}" == "${USER_TO_REMOVE:l}" ]] && continue
        /usr/sbin/sysadminctl -secureTokenStatus "$u" 2>&1 | /usr/bin/grep -q "ENABLED" || continue
        /usr/sbin/dseditgroup -o checkmember -m "$u" admin 2>/dev/null | /usr/bin/grep -q "^yes" || continue
        (( other_token_admins++ ))
      done
      if (( other_token_admins == 0 )); then
        block_reason="it is the only admin with a Secure Token (FileVault unlock / volume owner) - create another admin with a Secure Token first"
      else
        log_info "Account '${USER_TO_REMOVE}' holds a Secure Token; ${other_token_admins} other Secure Token admin(s) present - safe to remove."
      fi
    fi

    if [[ -n "$block_reason" ]]; then
      account_blocked="true"
      if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Account '${USER_TO_REMOVE}' would be BLOCKED in a live run: ${block_reason}."
      else
        (( account_failures++ ))
        log_fail "Account '${USER_TO_REMOVE}' NOT removed: ${block_reason}. Nothing was changed."
      fi
    elif [[ "$DRY_RUN" == "true" ]]; then
      log_info "Account '${USER_TO_REMOVE}' passed preflight - a live run would remove it and its home dir (${acct_home:-unknown})."
    else
      del_output="$(/usr/sbin/sysadminctl -deleteUser "$USER_TO_REMOVE" 2>&1)"
      if /usr/bin/dscl . -read "/Users/${USER_TO_REMOVE}" >/dev/null 2>&1; then
        (( account_failures++ ))
        log_fail "Account: ${USER_TO_REMOVE} (sysadminctl: ${del_output//$'\n'/ })"
      else
        # The account is gone. Remove its home folder only if sysadminctl left it behind,
        # it is under /Users, and it is still owned by the deleted account, so a folder
        # belonging to anyone else is never removed.
        if [[ "$acct_home" == /Users/?* && "$acct_home" != "/Users/Shared" && -e "$acct_home" && -n "$acct_uid" ]]; then
          home_owner="$(/usr/bin/stat -f '%u' "$acct_home" 2>/dev/null)"
          if [[ "$home_owner" == "$acct_uid" ]]; then
            /bin/rm -Rf "$acct_home"
          else
            log_warn "Home dir ${acct_home} not removed: owned by UID ${home_owner:-unknown}, not ${acct_uid}."
          fi
        fi
        if [[ -n "$acct_home" && -e "$acct_home" ]]; then
          (( account_failures++ ))
          log_fail "Account removed but home dir still present: ${acct_home}"
        else
          log_done "Account + home dir: ${USER_TO_REMOVE}"
        fi
      fi
    fi
  else
    log_warn "Local account '${USER_TO_REMOVE}' present but LEFT IN PLACE (REMOVE_RIPPLING_ADMIN=false). Confirm another local admin exists before enabling removal."
  fi
else
  log_info "Local account '${USER_TO_REMOVE}': not present"
fi

################################################################################################
# PHASE 3 - SUMMARY (read the output from the bottom up; this block is the result)
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
  log_warn "RESULT: PARTIAL. ${#failed_items[@]} item(s) could not be removed - see FAILED lines."
  if [[ "$account_blocked" == "true" ]]; then
    log_warn "        Account NOT removed: fix the reason in its FAILED line first - a restart will not change it."
  elif (( account_failures > 0 )); then
    log_warn "        Account removal did not complete: see its FAILED line for the reason, then re-run."
  fi
  if (( ${#failed_items[@]} > account_failures )); then
    log_warn "        Other items: restart the Mac and re-run this script."
  fi
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
