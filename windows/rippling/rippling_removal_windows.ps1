################################################################################################
# Rippling Removal for Windows  |  Iru, Inc.  |  v1.3
################################################################################################
#
#   Windows equivalent of Iru's macOS "rippling_removal.sh". Deploy FROM IRU as a
#   custom script AFTER a device has migrated. Runs elevated (SYSTEM/Administrator).
#
#   v1.3 - corrected from the first field dry run (2026-07-13), which verified the
#   Windows agent's real footprint:
#     service "rippling-daemon" [Rippling agent service]
#     tasks   "\Rippling-Rescuer" (watchdog), "\rippling-start-agent-Rippling Tray",
#             "\rippling-update-daemon"
#     account "RipplingAdmin" (yes, it exists on Windows - profile at C:\Users\ripplingadmin)
#     Iru's own Windows agent service: "UEMAgent"
#
################################################################################################
# HOW TO RUN THIS SCRIPT
################################################################################################
#
#   This script has exactly TWO modes, controlled by ONE variable ($DryRun, in the
#   "Editable defaults" section right below this header):
#
#     $DryRun = $true   (DEFAULT)  ->  DRY RUN. Scans and REPORTS only. Changes NOTHING.
#     $DryRun = $false             ->  LIVE.    Same scan, but actually removes findings.
#
#   RECOMMENDED WORKFLOW (first time on any fleet):
#
#     STEP 1  Push this script AS-IS from the Iru console to ONE test device.
#             (It ships in dry-run mode - safe to run anywhere, changes nothing.)
#
#     STEP 2  Read the script output in the Iru console, bottom-up. The final
#             SUMMARY block gives a one-line RESULT verdict:
#               "CLEAN"            -> migration already removed everything; done.
#                                     (If a restart is pending, just restart.)
#               "DRY RUN complete" -> review the FOUND lines above the summary.
#                                     Those are what a live run would remove.
#
#     STEP 3  If the assessment says the Rippling app is NOT installed and only a
#             restart is pending: restart and re-push the dry run FIRST - queued
#             deletions often clear on their own. (If the app IS still installed,
#             a restart will NOT help; proceed to Step 4.)
#
#     STEP 4  Decide the two flags below ($RemoveRipplingAdmin especially - read
#             its warning), set $DryRun = $false, and push again.
#
#     STEP 5  Confirm the summary says "CLEANED", then roll out to remaining
#             devices (live mode is safe to re-run; the script is idempotent).
#
#   OPTIONAL TOGGLES (work the same in either mode):
#     $RemoveRipplingAdmin -> default $false. DELETES A LOCAL ADMIN ACCOUNT. Read
#                             the warning at its definition before enabling.
#     $RemoveChocolatey    -> default $false. Rippling used Chocolatey for app
#                             installs; leave $false unless you have confirmed
#                             nothing else depends on it.
#
################################################################################################
#
#   LOGGING: every line goes to stdout (captured by the Iru console script results) AND
#   to a timestamped file at C:\ProgramData\Iru\MDMMigration\Logs\ for deep detail.
#   Read the console output bottom-up: the last block is the verdict.
#
#   EXIT CODES (visible in Iru):
#     0 = clean, or dry run completed  |  1 = leftovers could not be removed (see log)
#
#   REMOVAL ORDER (deliberate): scheduled tasks FIRST - "Rippling-Rescuer" appears to
#   be a watchdog/repair task, so it must die before we touch the service or processes,
#   or it may restore them mid-cleanup. Then service -> processes -> uninstaller -> files.
#
#   NOT touched, on purpose:
#     - HKLM\SOFTWARE\Microsoft\Enrollments (Iru's own MDM enrollment lives there;
#       read-only inspection only)
#     - SentinelOne (if delivered via Rippling, removing an EDR is a separate decision)
#
################################################################################################

# Script version
# VERSION="1.3.1"
# 1.3.1 - Autostart Run-key and Uninstall registry-key removals now verify deletion and
#         report FAILED when the entry survives (were unconditional REMOVED, which could
#         yield a false CLEANED); Chocolatey folder no longer double-counted in FOUND
#         (Remove-PathSafe owns the find/verify; dry-run and live counts now match).

# ---------------------------------------------------------------------------------
# Editable defaults
# ---------------------------------------------------------------------------------
$DryRun              = $true    # THE mode switch - see "HOW TO RUN THIS SCRIPT" above.
                                # $true = report only (safe anywhere). $false = actually remove.

$RemoveRipplingAdmin = $false   # !! WARNING !! The Windows agent DOES create a local admin
                                # account "RipplingAdmin" (field-verified). On some fleets it
                                # is the ONLY local admin - deleting it could leave no local
                                # admin on the device (Iru LAPS is not yet available). Before
                                # setting $true, confirm that another local
                                # admin account exists on these devices.

$RemoveChocolatey    = $false   # Rippling's Windows app-management layer (its munki).
                                # Devs may use choco personally; removal orphans choco apps.

$UserToRemove        = "RipplingAdmin"  # Field-verified name. Change only if your Rippling
                                        # tenant used a different account name.

$ErrorActionPreference = "Continue"

# ---------------------------------------------------------------------------------
# Logging - stdout (Iru console) + file. Counters feed the final SUMMARY.
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
Log-Info "Rippling removal v1.3.1 | DryRun=$DryRun | Host=$env:COMPUTERNAME"
Log-Info "Full log: $LogFile"
Log-Info "================================================================"

################################################################################################
# PHASE 1 - MIGRATION STATE ASSESSMENT (read-only)
################################################################################################
Log-Info "--- PHASE 1: migration state assessment ---"

# 1a. Is the Iru agent on this device? Primary check: the field-verified service name
#     "UEMAgent". Fallback: word-bounded iru/kandji match ("kandji" kept on purpose -
#     post-rebrand infrastructure still uses legacy Kandji identifiers, e.g. device
#     domains *.web-api.kandji.io. Word boundaries prevent the v1.2 false positive
#     where "AntivIRUs" matched "iru" and reported Defender as the Iru agent.)
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

# 1b. Any Rippling MDM enrollment remnants? (READ-ONLY - never modified here)
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

# 1c. Rippling app still installed?
$appPresent = Test-Path "C:\Program Files\Rippling\App\Rippling.exe"
if ($appPresent) { Log-Warn "Rippling app: STILL INSTALLED - the migration's uninstall step did not run or failed. A restart will NOT fix this; a live run of this script (or the official uninstaller) is required." }
else             { Log-Info "Rippling app: not installed (migration script's uninstall ran)" }

# 1d. Pending reboot? (uninstalls queue locked files for deletion at next restart)
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
# PHASE 2 - LEFTOVER SWEEP (honors DryRun; every finding logged as FOUND first)
# ORDER MATTERS in live mode: watchdog tasks -> service -> processes -> uninstaller -> files.
################################################################################################
Log-Info "--- PHASE 2: leftover sweep ---"

# 2a. Scheduled tasks FIRST. Field-verified names: \Rippling-Rescuer (watchdog/repair),
#     \rippling-start-agent-Rippling Tray, \rippling-update-daemon. The Rescuer must be
#     removed before the service/processes are touched or it may restore them.
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

# 2b. Service (field-verified: "rippling-daemon" [Rippling agent service])
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

# 2c. Processes (field-observed: multiple "Rippling Tray" instances, one per session)
foreach ($p in (Get-Process | Where-Object { $_.Name -like "*rippling*" })) {
    Log-Find "Process: $($p.Name) (PID $($p.Id))"
    if (-not $DryRun) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) { Log-Fail "Process would not die: $($p.Name) (PID $($p.Id))" }
        else { Log-Done "Process killed: $($p.Name) (PID $($p.Id))" }
    }
}

# 2d. Official uninstaller (now that nothing can respawn or hold repair state)
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

# 2e. Autostart Run-key entries (field-verified: HKLM ...\Run\"Rippling Tray")
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

# 2f. Leftover folders (field-verified: Program Files\Rippling, ProgramData\Rippling,
#     per-user AppData "Rippling", "rippling-updater", "rippling-tray")
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

# 2g. Uninstall registry keys (= pkgutil --forget; scoped to Uninstall keys ONLY)
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

# 2h. Chocolatey (Rippling's Windows app-management layer) - flag-gated
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

# 2i. Local admin account (field-verified to exist on Windows) - flag-gated because
#     it may be the only local admin on the device. See warning at $RemoveRipplingAdmin.
$acct = Get-LocalUser -Name $UserToRemove -ErrorAction SilentlyContinue
if ($acct) {
    if ($RemoveRipplingAdmin) {
        Log-Find "Local account: $UserToRemove"
        if (-not $DryRun) {
            $sid = $acct.SID.Value
            Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
                Where-Object { $_.SID -eq $sid } |
                Remove-CimInstance -ErrorAction SilentlyContinue
            Remove-LocalUser -Name $UserToRemove -ErrorAction SilentlyContinue
            if (Get-LocalUser -Name $UserToRemove -ErrorAction SilentlyContinue) { Log-Fail "Account: $UserToRemove" }
            else { Log-Done "Account + profile: $UserToRemove" }
        }
    } else {
        Log-Warn "Local account '$UserToRemove' present but LEFT IN PLACE (RemoveRipplingAdmin=`$false). Confirm another local admin exists on this fleet before enabling removal."
    }
} else {
    Log-Info "Local account '$UserToRemove': not present"
}

################################################################################################
# PHASE 3 - SUMMARY (this is the block to read in the Iru console)
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
    Log-Warn "RESULT: PARTIAL. $($script:Failed.Count) item(s) could not be removed - likely file locks. Restart the device and re-run this script."
}
else {
    Log-Info "RESULT: CLEANED. $($script:Removed.Count) leftover(s) removed."
    Log-Info "        Recommend a restart to flush any queued deletions."
}
Log-Info ("Full detail: {0}" -f $LogFile)
Log-Info "================================================================"

if (-not $DryRun -and $script:Failed.Count -gt 0) { exit 1 }
exit 0
