#Requires -Version 5.1
<#
.SYNOPSIS
    JRTreborn - Junkware Removal Tool Reborn

.DESCRIPTION
    Open source, lightweight, portable tool for removing adware, junkware,
    and bloatware from Windows 10 and Windows 11 systems.

.PARAMETER Scan
    Scan only — detect threats without removing anything.

.PARAMETER Remove
    Scan and remove all detected items (requires admin, creates restore point).

.PARAMETER DryRun
    Scan and show what would be removed, but make no changes.

.PARAMETER NoRestorePoint
    Skip creating a system restore point before removal (not recommended).

.PARAMETER OutputDir
    Directory where log files will be saved. Defaults to Desktop.

.PARAMETER DatabasePath
    Path to a custom database directory. Defaults to .\database relative to script.

.EXAMPLE
    .\JRTreborn.ps1 -Scan
    .\JRTreborn.ps1 -Remove
    .\JRTreborn.ps1 -DryRun
#>

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'Scan')]
    [switch]$Scan,

    [Parameter(ParameterSetName = 'Remove')]
    [switch]$Remove,

    [Parameter(ParameterSetName = 'DryRun')]
    [switch]$DryRun,

    [switch]$NoRestorePoint,

    [switch]$IncludeSuspected,

    [string]$OutputDir = '',

    [string]$DatabasePath = ''
)

# StrictMode 1.0 (not Latest): the scanner and remover deliberately read optional
# properties off dynamic objects (registry items, parsed JSON, COM results) that are
# frequently absent. Under -Version Latest, reading a missing property is a TERMINATING
# error, which crashed the tool mid-scan. 1.0 still catches uninitialized variables.
Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# ─── Constants ───────────────────────────────────────────────────────────────

$JRT_VERSION  = '1.2.2'
$JRT_REPO     = 'https://github.com/delanderdev/jrtreborn'
$SCRIPT_ROOT  = $PSScriptRoot

# ─── Output directory ────────────────────────────────────────────────────────

if (-not $OutputDir) {
    $OutputDir = [System.Environment]::GetFolderPath('Desktop')
    if (-not (Test-Path $OutputDir)) {
        $OutputDir = $env:TEMP
    }
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# ─── Diagnostic logging + fatal-error trap ───────────────────────────────────
# Records a full session transcript and, on any unhandled terminating error,
# writes a detailed crash report to a file and keeps the window open so the
# error can be read and reported. Essential for the .exe build, whose window
# would otherwise close instantly on a crash.

$script:JRT_Stamp        = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:JRT_ErrorLog     = Join-Path $OutputDir ("JRTreborn_ERROR_{0}.log" -f $script:JRT_Stamp)
$script:JRT_Transcript   = Join-Path $OutputDir ("JRTreborn_session_{0}.log" -f $script:JRT_Stamp)
$script:JRT_TranscriptOn = $false
try {
    Start-Transcript -Path $script:JRT_Transcript -Force -ErrorAction Stop | Out-Null
    $script:JRT_TranscriptOn = $true
} catch { }

trap {
    $e = $_
    $report = @"
==================== JRTreborn FATAL ERROR ====================
Time     : $(Get-Date)
Version  : $JRT_VERSION
Message  : $($e.Exception.Message)
Type     : $($e.Exception.GetType().FullName)
Category : $($e.CategoryInfo.Category)
Location : $($e.InvocationInfo.ScriptName):$($e.InvocationInfo.ScriptLineNumber)
Command  : $($e.InvocationInfo.MyCommand)
Line     : $(($e.InvocationInfo.Line).Trim())
--- Script stack trace ---
$($e.ScriptStackTrace)
===============================================================
"@
    try { $report | Out-File -FilePath $script:JRT_ErrorLog -Encoding UTF8 -Force } catch { }
    Write-Host ""
    Write-Host $report -ForegroundColor Red
    Write-Host "  A crash report was saved to:" -ForegroundColor Yellow
    Write-Host "    $script:JRT_ErrorLog" -ForegroundColor Yellow
    Write-Host "  Please send that file to the developer so the issue can be fixed." -ForegroundColor Yellow
    Write-Host ""
    if ($script:JRT_TranscriptOn) { try { Stop-Transcript | Out-Null } catch { } }
    try { Read-Host "  Press Enter to close" | Out-Null } catch { }
    exit 1
}

# ─── Load modules ────────────────────────────────────────────────────────────

$srcPath = Join-Path $SCRIPT_ROOT 'src'
. (Join-Path $srcPath 'Logger.ps1')
. (Join-Path $srcPath 'RestorePoint.ps1')
. (Join-Path $srcPath 'Scanner.ps1')
. (Join-Path $srcPath 'Remover.ps1')

# ─── Banner ──────────────────────────────────────────────────────────────────

function Show-Banner {
    $w = 70
    $line  = '=' * $w
    $title = 'JRTreborn v{0} - Junkware Removal Tool Reborn' -f $JRT_VERSION
    $sub   = 'Open Source | Free | No Ads | Windows 10/11'
    $pad   = [math]::Max(0, [math]::Floor(($w - $title.Length) / 2))

    Clear-Host
    Write-Host $line                                         -ForegroundColor Cyan
    Write-Host (' ' * $pad + $title)                         -ForegroundColor Cyan
    Write-Host (' ' * [math]::Floor(($w - $sub.Length) / 2) + $sub) -ForegroundColor DarkCyan
    Write-Host $line                                         -ForegroundColor Cyan
    Write-Host ""
}

# ─── Admin check ─────────────────────────────────────────────────────────────

function Test-AdminPrivilege {
    $identity  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-Elevation {
    Write-Host "  [!] This tool requires administrator privileges." -ForegroundColor Yellow
    Write-Host "  [!] Relaunching as administrator..." -ForegroundColor Yellow
    Write-Host ""

    $elevArgs = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Scan)            { $elevArgs += ' -Scan' }
    elseif ($Remove)      { $elevArgs += ' -Remove' }
    elseif ($DryRun)      { $elevArgs += ' -DryRun' }
    if ($NoRestorePoint)   { $elevArgs += ' -NoRestorePoint' }
    if ($IncludeSuspected) { $elevArgs += ' -IncludeSuspected' }
    if ($OutputDir)        { $elevArgs += " -OutputDir `"$($OutputDir -replace '"', '\"')`"" }

    Start-Process powershell -ArgumentList $elevArgs -Verb RunAs
    exit
}

# ─── Database loader ─────────────────────────────────────────────────────────

function Import-Database {
    param([string]$DbPath)

    if (-not $DbPath) {
        $DbPath = Join-Path $SCRIPT_ROOT 'database'
    }

    if (-not (Test-Path $DbPath)) {
        Write-Host "  [!] Database directory not found: $DbPath" -ForegroundColor Red
        exit 1
    }

    $db = @{}

    $files = @{
        Programs  = 'programs.json'
        Registry  = 'registry.json'
        Files     = 'files.json'
        Processes = 'processes.json'
        Services  = 'services.json'
        Tasks     = 'tasks.json'
        Browsers  = 'browsers.json'
        Policies  = 'policies.json'
    }

    foreach ($key in $files.Keys) {
        $filePath = Join-Path $DbPath $files[$key]
        if (Test-Path $filePath) {
            try {
                $parsed = Get-Content -Path $filePath -Raw | ConvertFrom-Json
                # Unwrap the top-level array property
                $db[$key] = switch ($key) {
                    'Programs'  { $parsed.programs }
                    'Registry'  { $parsed.keys }
                    'Files'     { $parsed }
                    'Processes' { $parsed.processes }
                    'Services'  { $parsed.services }
                    'Tasks'     { $parsed.tasks }
                    'Browsers'  { @{
                        homepage_hijackers   = $parsed.homepage_hijackers
                        chrome_extension_ids = $parsed.chrome_extension_ids
                        firefox_extension_ids= $parsed.firefox_extension_ids
                        ie_bho_clsids        = $parsed.ie_bho_clsids
                    }}
                    'Policies'  { $parsed }
                }

                # Programs file carries extra detection lists beyond the main array
                if ($key -eq 'Programs') {
                    $db['ProgramPublishers'] = $parsed.publishers
                    $db['ProgramHeuristics'] = $parsed.heuristics
                    $db['ProgramAllowlist']  = $parsed.heuristic_allowlist
                    $db['ProgramAppx']       = $parsed.appx_bloatware
                }
            } catch {
                Write-Host "  [!] Failed to load database file '$($files[$key])': $_" -ForegroundColor Red
            }
        } else {
            Write-Host "  [!] Database file missing: $filePath" -ForegroundColor Yellow
        }
    }

    return $db
}

# ─── Interactive menu ────────────────────────────────────────────────────────

function Show-InteractiveMenu {
    Write-Host "  What would you like to do?" -ForegroundColor White
    Write-Host ""
    Write-Host "    [1]  Scan only (detect threats, no changes)"          -ForegroundColor Cyan
    Write-Host "    [2]  Scan and Remove (recommended)"                    -ForegroundColor Green
    Write-Host "    [3]  Dry Run (show what would be removed)"             -ForegroundColor DarkCyan
    Write-Host "    [Q]  Quit"                                             -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Enter choice: " -ForegroundColor White -NoNewline

    $choice = (Read-Host).Trim().ToUpper()
    Write-Host ""

    $result = switch ($choice) {
        '1' { 'Scan' }
        '2' { 'Remove' }
        '3' { 'DryRun' }
        'Q' { 'Quit' }
        default { 'Unknown' }
    }
    return $result
}

function Confirm-Removal {
    param([int]$Count)

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "  ║  $Count item(s) detected. Ready to remove?                    " -ForegroundColor Yellow -NoNewline
    Write-Host "║" -ForegroundColor Yellow
    Write-Host "  ║  A system restore point will be created first.           ║" -ForegroundColor Yellow
    Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Proceed with removal? [Y/N]: " -ForegroundColor White -NoNewline
    $confirm = (Read-Host).Trim().ToUpper()
    return $confirm -eq 'Y'
}

function Confirm-Suspected {
    param([int]$Count)

    Write-Host ""
    Write-Host "  $Count suspected item(s) were flagged by heuristics." -ForegroundColor Magenta
    Write-Host "  These MAY include legitimate software — review the list above carefully." -ForegroundColor Magenta
    Write-Host "  Remove the suspected items too? [y/N]: " -ForegroundColor White -NoNewline
    $confirm = (Read-Host).Trim().ToUpper()
    return $confirm -eq 'Y'
}

# ─── Main ────────────────────────────────────────────────────────────────────

Show-Banner

# Elevation
if (-not (Test-AdminPrivilege)) {
    Request-Elevation
}

# Initialize logger
Initialize-Logger -OutputDir $OutputDir

# Load database
Write-Host "  Loading signature database..." -ForegroundColor DarkGray
$db = Import-Database -DbPath $DatabasePath
$dbVersionFile = Join-Path (if ($DatabasePath) { $DatabasePath } else { Join-Path $SCRIPT_ROOT 'database' }) 'programs.json'
$dbVersion = ((Get-Content $dbVersionFile -Raw | ConvertFrom-Json).updated)
Write-Host "  Database version: $dbVersion" -ForegroundColor DarkGray
Write-Host ""

# Determine mode
$mode = $PSCmdlet.ParameterSetName
if ($mode -eq 'Interactive') {
    do {
        $mode = Show-InteractiveMenu
        if ($mode -eq 'Unknown') {
            Write-Host "  [!] Invalid choice. Please try again." -ForegroundColor Yellow
        }
    } while ($mode -eq 'Unknown')

    if ($mode -eq 'Quit') {
        Write-Host "  Exiting JRTreborn. Goodbye!" -ForegroundColor DarkGray
        exit 0
    }
}

# Run scan
Write-Host ""
Write-Host "  ── SCAN ─────────────────────────────────────────────────────" -ForegroundColor DarkCyan
Write-Host ""

$detected = Invoke-FullScan -Database $db

# Split detections by confidence. Items without a Severity are treated as Known.
$knownItems     = @($detected | Where-Object { -not $_.Severity -or $_.Severity -eq 'Known' })
$suspectedItems = @($detected | Where-Object { $_.Severity -eq 'Suspected' })

Write-Host ""
Write-Host "  ── RESULTS ──────────────────────────────────────────────────" -ForegroundColor DarkCyan
Write-Host ""

if ($detected.Count -eq 0) {
    Write-Host "  [✓] No junkware detected. Your system appears clean!" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "  Found $($detected.Count) item(s): $($knownItems.Count) known, $($suspectedItems.Count) suspected" -ForegroundColor Yellow
    Write-Host ""

    if ($knownItems.Count -gt 0) {
        foreach ($group in ($knownItems | Group-Object -Property Type)) {
            Write-Host "    $($group.Name) ($($group.Count)):" -ForegroundColor DarkYellow
            foreach ($item in $group.Group) {
                Write-Host "      • $($item.Name)" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }

    if ($suspectedItems.Count -gt 0) {
        Write-Host "    SUSPECTED ($($suspectedItems.Count)) — heuristic matches, may include legitimate software:" -ForegroundColor Magenta
        foreach ($item in $suspectedItems) {
            Write-Host "      • $($item.Name)" -ForegroundColor Gray -NoNewline
            Write-Host "  — $($item.Description)" -ForegroundColor DarkGray
        }
        Write-Host ""
        Write-Host "    These are NOT removed unless you explicitly confirm." -ForegroundColor DarkMagenta
        Write-Host ""
    }
}

# Remove if requested
$summary = @{ Found = $detected.Count; Removed = 0; Errors = 0; Skipped = 0; Suspected = $suspectedItems.Count }
$includeSuspected = [bool]$IncludeSuspected

if ($detected.Count -gt 0 -and ($mode -eq 'Remove' -or $mode -eq 'DryRun')) {

    $isDryRun = ($mode -eq 'DryRun')

    if (-not $isDryRun -and $PSCmdlet.ParameterSetName -eq 'Interactive') {
        # Confirm known removals first; suspected items get a separate opt-in.
        $proceed = $true
        if ($knownItems.Count -gt 0) {
            $proceed = Confirm-Removal -Count $knownItems.Count
        }
        if ($proceed -and $suspectedItems.Count -gt 0) {
            $includeSuspected = Confirm-Suspected -Count $suspectedItems.Count
        }
        if (-not $proceed) {
            Write-Host ""
            Write-Host "  Removal cancelled. No changes were made." -ForegroundColor DarkGray
            Write-Host ""
            $mode = 'Scan'
        }
    }

    if ($mode -eq 'Remove' -or $isDryRun) {
        if (-not $isDryRun -and -not $NoRestorePoint) {
            Write-Host ""
            Write-Host "  ── RESTORE POINT ────────────────────────────────────────────" -ForegroundColor DarkCyan
            Write-Host ""
            New-SafetyRestorePoint
        }

        Write-Host ""
        Write-Host "  ── REMOVAL ──────────────────────────────────────────────────" -ForegroundColor DarkCyan
        Write-Host ""
        $summary = Invoke-RemoveAll -DetectedItems $detected -DryRun:$isDryRun -IncludeSuspected:$includeSuspected
        $summary.Found = $detected.Count
        $summary.Suspected = $suspectedItems.Count
    }
}

# Export report
Write-Host ""
Write-Host "  ── REPORT ───────────────────────────────────────────────────" -ForegroundColor DarkCyan
Write-Host ""

$reportPaths = Export-Report -OutputDir $OutputDir -ScanSummary $summary

Write-Host "  Report saved to:" -ForegroundColor White
Write-Host "    Log:  $($reportPaths.Log)"  -ForegroundColor Cyan
Write-Host "    HTML: $($reportPaths.Html)" -ForegroundColor Cyan
Write-Host ""

# Final summary
$line = '─' * 60
Write-Host "  $line" -ForegroundColor DarkGray
Write-Host ("  {0,-30} {1,5}" -f "Items found:",   $summary.Found)   -ForegroundColor White
if ($summary.ContainsKey('Suspected') -and $summary.Suspected -gt 0) {
    Write-Host ("  {0,-30} {1,5}" -f "Items suspected:", $summary.Suspected) -ForegroundColor Magenta
}
Write-Host ("  {0,-30} {1,5}" -f "Items removed:",  $summary.Removed) -ForegroundColor Green
if ($summary.Errors -gt 0) {
    Write-Host ("  {0,-30} {1,5}" -f "Errors:", $summary.Errors) -ForegroundColor Red
}
Write-Host "  $line" -ForegroundColor DarkGray
Write-Host ""

if ($summary.Removed -gt 0) {
    Write-Host "  [!] A system reboot is recommended to complete cleanup." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "  Thank you for using JRTreborn." -ForegroundColor DarkCyan
Write-Host "  $JRT_REPO" -ForegroundColor DarkGray
Write-Host ""

# Open HTML report if items were found
if ($detected.Count -gt 0 -and (Test-Path $reportPaths.Html)) {
    try {
        Start-Process $reportPaths.Html -ErrorAction SilentlyContinue
    } catch { }
}

# ─── Graceful close ──────────────────────────────────────────────────────────
if ($script:JRT_TranscriptOn) { try { Stop-Transcript | Out-Null } catch { } }
# Keep the window open after an interactive run so results stay visible (the .exe
# launches its own console window that would otherwise vanish on completion).
if ($PSCmdlet.ParameterSetName -eq 'Interactive') {
    try { Read-Host "  Press Enter to close" | Out-Null } catch { }
}
