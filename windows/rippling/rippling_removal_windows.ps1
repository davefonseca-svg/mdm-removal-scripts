################################################################################################
# Rippling Removal for Windows  |  Iru, Inc.  |  v1.4.1
################################################################################################
#
#   Removes leftover Rippling components from Windows devices after they migrate to Iru.
#   Deploy from Iru as a Custom Script. Runs elevated (SYSTEM).
#
################################################################################################
# HOW TO RUN THIS SCRIPT
################################################################################################
#
#   TWO modes, ONE setting ($DryRun, under "Editable defaults" below):
#
#     $DryRun = $true   (DEFAULT)  ->  DRY RUN. Scans and reports only. Changes nothing.
#     $DryRun = $false             ->  LIVE.    Same scan, then removes what it finds.
#
#   RECOMMENDED WORKFLOW:
#
#     STEP 1  Push this script as-is from the Iru console to ONE test device.
#             It ships in dry-run mode, so it changes nothing.
#
#     STEP 2  Read the SUMMARY block at the bottom of the output in the Iru console:
#               "CLEAN"            -> nothing left to remove. If a restart is pending,
#                                     restart.
#               "DRY RUN complete" -> the FOUND lines are what a live run would remove.
#
#     STEP 3  If the Rippling app is NOT installed and a restart is pending, restart and
#             run the dry run again first - queued deletions often clear on their own.
#             If the app IS still installed, a restart will not help; go to Step 4.
#
#     STEP 4  Decide on the two optional settings below, set $DryRun = $false, and
#             push again.
#
#     STEP 5  Confirm the summary says "CLEANED", then roll out to your remaining
#             devices. Safe to re-run in either mode.
#
#   OPTIONAL SETTINGS (both off by default):
#     $RemoveRipplingAdmin -> removes the Rippling local admin account, only if its
#                             safety checks pass (see section 2i).
#     $RemoveChocolatey    -> removes Chocolatey, which Rippling used to install apps.
#                             Leave off unless nothing else depends on it.
#
################################################################################################
#
#   LOGGING: output goes to the Iru console and to a timestamped log file in
#   C:\ProgramData\Iru\MDMMigration\Logs\. Read the output from the bottom up.
#
#   EXIT CODES (shown in Iru):
#     0 = clean, dry run complete, or cleaned  |  1 = something could not be removed
#
#   REMOVAL ORDER: scheduled tasks first - Rippling's repair task could otherwise restore
#   the service or processes mid-cleanup. Then service -> processes -> uninstaller -> files.
#
#   NOT touched, on purpose:
#     - MDM enrollments (HKLM\SOFTWARE\Microsoft\Enrollments). Iru's own enrollment is
#       stored here too, so the script only reads it.
#     - SentinelOne, even if Rippling delivered it. Removing a security agent is a
#       separate decision.
#
################################################################################################

# Script version (used in the log banner below)
$Version = "1.4.1"

# ---------------------------------------------------------------------------------
# Editable defaults
# ---------------------------------------------------------------------------------
$DryRun              = $true    # The mode setting - see "HOW TO RUN THIS SCRIPT" above.
                                # $true = report only. $false = remove.

$RemoveRipplingAdmin = $false   # $true = remove the RipplingAdmin local account and its
                                # profile, only if its safety checks pass (see section 2i).
                                # The script blocks removal if no other enabled local admin
                                # exists. Run a dry run with this on to see the result first.

$RemoveChocolatey    = $false   # $true = remove Chocolatey, which Rippling used to install
                                # apps. Others may rely on it; apps it installed are no longer
                                # managed by it, and portable tools in its folder are removed.

$UserToRemove        = "RipplingAdmin"  # Change only if your Rippling setup used a
                                        # different account name.

$ErrorActionPreference = "Continue"

# ---------------------------------------------------------------------------------
# Logging - output goes to the Iru console and the log file. Counts feed the SUMMARY.
# ---------------------------------------------------------------------------------
$LogDir  = "C:\ProgramData\Iru\MDMMigration\Logs"
$LogFile = Join-Path $LogDir ("rippling_removal_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$script:Found   = New-Object System.Collections.Generic.List[string]
$script:Removed = New-Object System.Collections.Generic.List[string]
$script:Failed  = New-Object System.Collections.Generic.List[string]

function Write-Log {
    param([string]$Level, [string]$Message)
    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"), $Level, $Message
    Write-Output $line
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}
function Log-Info { param([string]$m) Write-Log "INFO" $m }
function Log-Warn { param([string]$m) Write-Log "WARN" $m }
function Log-Find { param([string]$m) $script:Found.Add($m);   Write-Log "FOUND" $m }
function Log-Done { param([string]$m) $script:Removed.Add($m); Write-Log "REMOVED" $m }
function Log-Fail { param([string]$m) $script:Failed.Add($m);  Write-Log "FAILED" $m }

function Remove-PathSafe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Log-Find "Folder: $Path"
    if ($DryRun) { return }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Path) { Log-Fail "Folder still present (locked? restart may release it): $Path" }
    else { Log-Done "Folder: $Path" }
}

Log-Info "================================================================"
Log-Info "Rippling removal v$Version | DryRun=$DryRun | Host=$env:COMPUTERNAME"
Log-Info "Full log: $LogFile"
Log-Info "================================================================"

################################################################################################
# PHASE 1 - MIGRATION STATE ASSESSMENT (read-only)
################################################################################################
Log-Info "--- PHASE 1: migration state assessment ---"

# 1a. Is the Iru agent installed? Checks for the Iru agent service ("UEMAgent"), or any
#     service named "iru" or "kandji" as a whole word. Some Iru components still use the
#     Kandji name, which is expected.
$iruSvc = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -eq "UEMAgent" -or
    $_.Name -match "(?i)\b(iru|kandji)\b" -or
    $_.DisplayName -match "(?i)\b(iru|kandji)\b"
}
if ($iruSvc) {
    Log-Info ("Iru agent: PRESENT ({0})" -f (($iruSvc | ForEach-Object { $_.Name }) -join ", "))
} else {
    Log-Warn "Iru agent: NOT DETECTED via services. If this script isn't running FROM Iru, verify enrollment before cleaning up."
}

# 1b. Any Rippling MDM enrollment left? (Reported only - never modified.)
$ripplingEnrollment = $false
$enrollRoot = "HKLM:\SOFTWARE\Microsoft\Enrollments"
if (Test-Path $enrollRoot) {
    foreach ($k in (Get-ChildItem $enrollRoot -ErrorAction SilentlyContinue)) {
        $p = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
        $blob = "$($p.UPN) $($p.ProviderID) $($p.DiscoveryServiceFullURL)"
        if ($blob -match "rippling") {
            Log-Warn "Rippling MDM enrollment remnant: $($k.PSChildName) [$blob] - NOT touching it here; flag to Iru support if it persists after restart."
            $ripplingEnrollment = $true
        }
    }
}
if (-not $ripplingEnrollment) { Log-Info "Rippling MDM enrollment: NONE (migration script did its job)" }

# 1c. Is the Rippling app still installed?
$appPresent = Test-Path "C:\Program Files\Rippling\App\Rippling.exe"
if ($appPresent) { Log-Warn "Rippling app: STILL INSTALLED - the migration's uninstall step did not run or failed. A restart will NOT fix this; a live run of this script (or the official uninstaller) is required." }
else             { Log-Info "Rippling app: not installed (migration script's uninstall ran)" }

# 1d. Is a restart pending? (Uninstalls often queue locked files for deletion at the next restart.)
$pendingReboot = $false
$rebootSignals = @()
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
    $pendingReboot = $true; $rebootSignals += "CBS RebootPending"
}
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
    $pendingReboot = $true; $rebootSignals += "WindowsUpdate RebootRequired"
}
$pfro = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
if ($pfro) {
    $pendingReboot = $true; $rebootSignals += "PendingFileRenameOperations ($(@($pfro).Count) entries)"
    if (($pfro -join " ") -match "rippling") {
        Log-Info "Pending file deletions include Rippling paths - a restart will flush those particular items."
    }
}
if ($pendingReboot) { Log-Warn ("Restart pending: YES ({0})" -f ($rebootSignals -join "; ")) }
else                { Log-Info "Restart pending: no" }

################################################################################################
# PHASE 2 - LEFTOVER SWEEP (follows $DryRun; every finding is logged as FOUND first)
# ORDER: repair task first -> service -> processes -> uninstaller -> files, so nothing
# can restore itself mid-cleanup.
################################################################################################
Log-Info "--- PHASE 2: leftover sweep ---"

# 2a. Rippling scheduled tasks, removed first. These include \Rippling-Rescuer (a repair
#     task that could otherwise restore the service or processes),
#     \rippling-start-agent-Rippling Tray, and \rippling-update-daemon.
foreach ($t in (Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.TaskName -like "*rippling*" -or $_.TaskPath -like "*rippling*" })) {
    Log-Find "Scheduled task: $($t.TaskPath)$($t.TaskName)"
    if (-not $DryRun) {
        Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
        if (Get-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue) {
            Log-Fail "Scheduled task still registered: $($t.TaskName)"
        } else { Log-Done "Scheduled task: $($t.TaskName)" }
    }
}

# 2b. The Rippling agent service ("rippling-daemon") - stopped, then deleted.
foreach ($svc in (Get-CimInstance Win32_Service | Where-Object {
    $_.Name -like "*rippling*" -or $_.DisplayName -like "*rippling*" })) {
    Log-Find "Service: $($svc.Name) [$($svc.DisplayName)]"
    if (-not $DryRun) {
        Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
        & sc.exe delete $svc.Name | Out-Null
        if (Get-Service -Name $svc.Name -ErrorAction SilentlyContinue) { Log-Fail "Service still registered: $($svc.Name)" }
        else { Log-Done "Service: $($svc.Name)" }
    }
}

# 2c. Rippling processes still running, such as the tray app (one per signed-in user).
foreach ($p in (Get-Process | Where-Object { $_.Name -like "*rippling*" })) {
    Log-Find "Process: $($p.Name) (PID $($p.Id))"
    if (-not $DryRun) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) { Log-Fail "Process would not die: $($p.Name) (PID $($p.Id))" }
        else { Log-Done "Process killed: $($p.Name) (PID $($p.Id))" }
    }
}

# 2d. Rippling's official uninstaller, run silently if still present.
$uninstaller = "C:\Program Files\Rippling\App\Uninstall Rippling.exe"
if (Test-Path -LiteralPath $uninstaller) {
    Log-Find "Official uninstaller present: $uninstaller"
    if (-not $DryRun) {
        Log-Info "Running: `"$uninstaller`" /allusers /S"
        $p = Start-Process -FilePath $uninstaller -ArgumentList "/allusers","/S" -Wait -PassThru
        if ($p.ExitCode -eq 0) { Log-Done "Official uninstaller completed (exit 0)" }
        else { Log-Fail "Official uninstaller exit code: $($p.ExitCode)" }
        Start-Sleep -Seconds 10
    }
}

# 2e. Rippling startup (Run) entries - for the device, and for each user whose profile
#     is currently loaded (usually the signed-in users).
$runKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
)
$null = New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -ErrorAction SilentlyContinue
$runKeys += (Get-ChildItem "HKU:\" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match "S-1-5-21" -and $_.Name -notmatch "_Classes$" } |
    ForEach-Object { "$($_.PSPath)\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" })
foreach ($rk in $runKeys) {
    if (-not (Test-Path $rk)) { continue }
    foreach ($name in (Get-Item $rk | Select-Object -ExpandProperty Property)) {
        $val = (Get-ItemProperty -Path $rk -Name $name -ErrorAction SilentlyContinue).$name
        if ($name -like "*rippling*" -or "$val" -like "*rippling*") {
            Log-Find "Autostart: $rk\$name"
            if (-not $DryRun) {
                Remove-ItemProperty -Path $rk -Name $name -ErrorAction SilentlyContinue
                $still = Get-ItemProperty -Path $rk -Name $name -ErrorAction SilentlyContinue
                if ($null -ne $still) { Log-Fail "Autostart still present: $rk\$name" }
                else { Log-Done "Autostart: $name" }
            }
        }
    }
}

# 2f. Rippling folders - Program Files, ProgramData, and each user's AppData folders whose
#     names contain "rippling" (e.g. "Rippling", "rippling-updater", "rippling-tray").
foreach ($path in @("C:\Program Files\Rippling", "C:\Program Files (x86)\Rippling", "$env:ProgramData\Rippling")) {
    Remove-PathSafe -Path $path
}
foreach ($profileDir in (Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue)) {
    foreach ($appData in @("AppData\Local", "AppData\Roaming")) {
        $base = Join-Path $profileDir.FullName $appData
        if (-not (Test-Path $base)) { continue }
        Get-ChildItem $base -Directory -Filter "*rippling*" -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-PathSafe -Path $_.FullName }
    }
}

# 2g. Rippling's entries in the installed-programs list (Uninstall registry keys only).
foreach ($root in @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")) {
    foreach ($k in (Get-ChildItem $root -ErrorAction SilentlyContinue | Where-Object {
        ($_ | Get-ItemProperty -ErrorAction SilentlyContinue).DisplayName -like "*rippling*" })) {
        Log-Find "Uninstall registry key: $($k.PSChildName)"
        if (-not $DryRun) {
            Remove-Item -Path $k.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -Path $k.PSPath) { Log-Fail "Uninstall registry key still present: $($k.PSChildName)" }
            else { Log-Done "Registry key: $($k.PSChildName)" }
        }
    }
}

# 2h. Chocolatey - only if $RemoveChocolatey = $true.
$chocoDir = "$env:ProgramData\chocolatey"
if (Test-Path $chocoDir) {
    if ($RemoveChocolatey) {
        Remove-PathSafe -Path $chocoDir
        if (-not $DryRun) {
            [Environment]::SetEnvironmentVariable("ChocolateyInstall", $null, "Machine")
            [Environment]::SetEnvironmentVariable("ChocolateyLastPathUpdate", $null, "Machine")
        }
    } else {
        Log-Info "Chocolatey present, left in place (RemoveChocolatey=`$false). Rippling used it for app installs; removal is a deliberate, separate decision."
    }
}

# 2i. Rippling local admin account - only if $RemoveRipplingAdmin = $true.
#     Safety checks run in both modes, so a dry run shows whether removal would be allowed.
#     If a check can't confirm something, removal is blocked. Removal is blocked if the
#     account is signed in, or if no other enabled LOCAL admin account exists (Entra ID and
#     domain admins don't count toward this). The account is deleted first and confirmed
#     gone; only then is its profile removed, so a failed delete changes nothing else.
function Get-OtherEnabledLocalAdminCount {
    # Returns the number of enabled LOCAL user accounts (other than $ExcludeSid) in the
    # local Administrators group, or -1 if the group can't be read. Reads the group through
    # ADSI, which works on Entra-joined devices, and finds it by its built-in SID
    # (S-1-5-32-544) so it works in any Windows language.
    param([string]$ExcludeSid)
    try {
        $adminSid  = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
        $groupName = $adminSid.Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
        $group     = [ADSI]"WinNT://$env:COMPUTERNAME/$groupName,group"
        $memberSids = @()
        foreach ($m in @($group.psbase.Invoke("Members"))) {
            try {
                $bytes = $m.GetType().InvokeMember("objectSid", "GetProperty", $null, $m, $null)
                $memberSids += (New-Object System.Security.Principal.SecurityIdentifier($bytes, 0)).Value
            } catch { }   # a member that can't be resolved is skipped, never counted
        }
        $count = 0
        foreach ($u in @(Get-LocalUser -ErrorAction Stop)) {
            if (-not $u.Enabled) { continue }
            if ($u.SID.Value -eq $ExcludeSid) { continue }
            if ($memberSids -contains $u.SID.Value) { $count++ }
        }
        return [int]$count
    } catch {
        return [int]-1
    }
}

$accountBlocked  = $false
$accountFailures = 0      # account-related FAILED lines, so the summary can explain them
$acct = Get-LocalUser -Name $UserToRemove -ErrorAction SilentlyContinue
if ($acct) {
    if ($RemoveRipplingAdmin) {
        Log-Find "Local account: $UserToRemove"
        $sid         = $acct.SID.Value
        $acctProfile = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
                           Where-Object { $_.SID -eq $sid } | Select-Object -First 1
        $profilePath = if ($acctProfile) { $acctProfile.LocalPath } else { $null }
        $blockReason = $null

        # Check 1: the account must not be signed in.
        if ($acctProfile -and $acctProfile.Loaded) {
            $blockReason = "account is currently signed in (profile loaded) - sign it out first"
        }

        # Check 2: at least one other enabled local admin must exist.
        if (-not $blockReason) {
            $otherAdmins = Get-OtherEnabledLocalAdminCount -ExcludeSid $sid
            if ($otherAdmins -lt 0) {
                $blockReason = "could not read the local Administrators group - blocked to be safe"
            } elseif ($otherAdmins -eq 0) {
                $blockReason = "no other enabled local admin account exists on this device - create one first"
            } else {
                Log-Info "Account '$UserToRemove': $otherAdmins other enabled local admin(s) present - safe to remove."
            }
        }

        if ($blockReason) {
            $accountBlocked = $true
            if ($DryRun) { Log-Warn "Account '$UserToRemove' would be BLOCKED in a live run: $blockReason." }
            else         { $accountFailures++; Log-Fail "Account '$UserToRemove' NOT removed: $blockReason. Nothing was changed." }
        }
        elseif ($DryRun) {
            Log-Info "Account '$UserToRemove' passed preflight - a live run would remove it and its profile ($(if ($profilePath) { $profilePath } else { 'no profile on disk' }))."
        }
        else {
            # Step 1: delete the account, keeping any error message.
            $delErr = $null
            try { Remove-LocalUser -Name $UserToRemove -ErrorAction Stop }
            catch { $delErr = $_.Exception.Message }

            if (Get-LocalUser -Name $UserToRemove -ErrorAction SilentlyContinue) {
                $accountFailures++
                Log-Fail "Account: $UserToRemove ($(if ($delErr) { $delErr } else { 'still present after delete' })) - profile left untouched."
            }
            else {
                # Step 2: the account is confirmed gone - now remove its profile.
                $profErr = $null
                $prof = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
                            Where-Object { $_.SID -eq $sid }
                if ($prof) {
                    try { $prof | Remove-CimInstance -ErrorAction Stop }
                    catch { $profErr = $_.Exception.Message }
                }
                $profLeft = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
                                Where-Object { $_.SID -eq $sid }
                if ($profLeft) {
                    $accountFailures++
                    Log-Fail "Account removed but profile still registered: $profilePath$(if ($profErr) { " ($profErr)" })"
                }
                elseif ($profilePath -and (Test-Path -LiteralPath $profilePath)) {
                    $accountFailures++
                    Log-Fail "Account removed but profile folder still on disk (locked? restart may release it): $profilePath"
                }
                else {
                    Log-Done "Account + profile: $UserToRemove"
                }
            }
        }
    } else {
        Log-Warn "Local account '$UserToRemove' present but LEFT IN PLACE (RemoveRipplingAdmin=`$false). Confirm another local admin exists on this fleet before enabling removal."
    }
} else {
    Log-Info "Local account '$UserToRemove': not present"
}

################################################################################################
# PHASE 3 - SUMMARY (read the output from the bottom up; this block is the result)
################################################################################################
Log-Info "================================================================"
Log-Info "SUMMARY"
Log-Info ("  Mode:               {0}" -f ($(if ($DryRun) { "DRY RUN - nothing was changed" } else { "LIVE" })))
Log-Info ("  Leftovers found:    {0}" -f $script:Found.Count)
Log-Info ("  Removed:            {0}" -f $script:Removed.Count)
Log-Info ("  Failed to remove:   {0}" -f $script:Failed.Count)
Log-Info ("  Restart pending:    {0}" -f ($(if ($pendingReboot) { "YES" } else { "no" })))

if ($script:Found.Count -eq 0 -and -not $ripplingEnrollment) {
    Log-Info "RESULT: CLEAN. The migration script already removed Rippling from this device."
    if ($pendingReboot) { Log-Info "        A restart is queued and will flush remaining file deletions." }
}
elseif ($DryRun) {
    Log-Info "RESULT: DRY RUN complete. Review FOUND lines above; if they look right, set `$DryRun = `$false and re-push."
    if ($appPresent) {
        Log-Info "        NOTE: the Rippling app is still fully installed - a live run is needed; restarting alone will NOT remove it."
    }
    elseif ($pendingReboot -and $script:Found.Count -le 2) {
        Log-Info "        NOTE: findings are minimal and a restart is pending - try restarting FIRST; these may clear on their own."
    }
}
elseif ($script:Failed.Count -gt 0) {
    Log-Warn "RESULT: PARTIAL. $($script:Failed.Count) item(s) could not be removed - see FAILED lines."
    if ($accountBlocked) {
        Log-Warn "        Account NOT removed: fix the reason in its FAILED line first - a restart will not change it."
    } elseif ($accountFailures -gt 0) {
        Log-Warn "        Account removal did not complete: see its FAILED line for the reason. A restart may release a locked profile folder; then re-run."
    }
    if ($script:Failed.Count -gt $accountFailures) {
        Log-Warn "        Other items: likely file locks - restart the device and re-run this script."
    }
}
else {
    Log-Info "RESULT: CLEANED. $($script:Removed.Count) leftover(s) removed."
    Log-Info "        Recommend a restart to flush any queued deletions."
}
Log-Info ("Full detail: {0}" -f $LogFile)
Log-Info "================================================================"

if (-not $DryRun -and $script:Failed.Count -gt 0) { exit 1 }
exit 0
