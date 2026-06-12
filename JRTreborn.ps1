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

    [string]$OutputDir = '',

    [string]$DatabasePath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Constants ───────────────────────────────────────────────────────────────

$JRT_VERSION  = '1.0.0'
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

    $args = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Scan)            { $args += ' -Scan' }
    elseif ($Remove)      { $args += ' -Remove' }
    elseif ($DryRun)      { $args += ' -DryRun' }
    if ($NoRestorePoint)  { $args += ' -NoRestorePoint' }
    if ($OutputDir)       { $args += " -OutputDir `"$OutputDir`"" }

    Start-Process powershell -ArgumentList $args -Verb RunAs
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

    return switch ($choice) {
        '1' { 'Scan' }
        '2' { 'Remove' }
        '3' { 'DryRun' }
        'Q' { 'Quit' }
        default { 'Unknown' }
    }
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

Write-Host ""
Write-Host "  ── RESULTS ──────────────────────────────────────────────────" -ForegroundColor DarkCyan
Write-Host ""

if ($detected.Count -eq 0) {
    Write-Host "  [✓] No junkware detected. Your system appears clean!" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "  Found $($detected.Count) item(s):" -ForegroundColor Yellow
    Write-Host ""
    $grouped = $detected | Group-Object -Property Type
    foreach ($group in $grouped) {
        Write-Host "    $($group.Name) ($($group.Count)):" -ForegroundColor DarkYellow
        foreach ($item in $group.Group) {
            Write-Host "      • $($item.Name)" -ForegroundColor Gray
        }
    }
    Write-Host ""
}

# Remove if requested
$summary = @{ Found = $detected.Count; Removed = 0; Errors = 0 }

if ($detected.Count -gt 0 -and ($mode -eq 'Remove' -or $mode -eq 'DryRun')) {

    $isDryRun = ($mode -eq 'DryRun')

    if (-not $isDryRun) {
        # Interactive mode confirmation
        if ($PSCmdlet.ParameterSetName -eq 'Interactive') {
            if (-not (Confirm-Removal -Count $detected.Count)) {
                Write-Host ""
                Write-Host "  Removal cancelled. No changes were made." -ForegroundColor DarkGray
                Write-Host ""
                $mode = 'Scan'
            }
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
        $summary = Invoke-RemoveAll -DetectedItems $detected -DryRun:$isDryRun
        $summary.Found = $detected.Count
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
