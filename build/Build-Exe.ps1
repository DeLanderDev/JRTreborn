#Requires -Version 5.1
<#
.SYNOPSIS
    Builds JRTreborn.exe from the standalone merged script using ps2exe.

.DESCRIPTION
    1. Runs Merge-Script.ps1 to produce dist/JRTreborn-standalone.ps1
    2. Installs ps2exe if not already available
    3. Compiles the merged script to dist/JRTreborn.exe with:
         - RequireAdmin manifest (auto UAC elevation)
         - Version info from version.txt or hardcoded fallback
         - No visible PowerShell console window wrapper (uses built-in console)

.PARAMETER Version
    Version string for the exe metadata (e.g. "1.1.0"). Defaults to reading
    from ../version.txt or falling back to "1.0.0".

.PARAMETER SkipMerge
    Skip running Merge-Script.ps1 (use existing dist/JRTreborn-standalone.ps1).
#>
param(
    [string]$Version   = '',
    [switch]$SkipMerge
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root      = Split-Path $PSScriptRoot -Parent
$distDir   = Join-Path $root 'dist'
$mergedPs1 = Join-Path $distDir 'JRTreborn-standalone.ps1'
$outputExe = Join-Path $distDir 'JRTreborn.exe'

# ─── Resolve version ──────────────────────────────────────────────────────────

if (-not $Version) {
    $versionFile = Join-Path $root 'version.txt'
    if (Test-Path $versionFile) {
        $Version = (Get-Content $versionFile -Raw).Trim()
    } else {
        $Version = '1.1.0'
    }
}
Write-Host "  Building JRTreborn v$Version" -ForegroundColor Cyan
Write-Host ""

# ─── Step 1: Merge ────────────────────────────────────────────────────────────

if (-not $SkipMerge) {
    Write-Host "  [1/3] Merging source files..." -ForegroundColor White
    & (Join-Path $PSScriptRoot 'Merge-Script.ps1') -OutputPath $mergedPs1
    Write-Host ""
} else {
    Write-Host "  [1/3] Skipping merge (using existing $mergedPs1)" -ForegroundColor DarkGray
    if (-not (Test-Path $mergedPs1)) {
        Write-Host "  [!] Merged script not found. Run without -SkipMerge first." -ForegroundColor Red
        exit 1
    }
}

# ─── Step 2: Ensure ps2exe is available ───────────────────────────────────────

Write-Host "  [2/3] Checking for ps2exe..." -ForegroundColor White

if (-not (Get-Command 'Invoke-PS2EXE' -ErrorAction SilentlyContinue)) {
    Write-Host "  Installing ps2exe module (requires internet)..." -ForegroundColor DarkGray
    try {
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Import-Module ps2exe -ErrorAction Stop
    } catch {
        Write-Host ""
        Write-Host "  [!] Could not install ps2exe: $_" -ForegroundColor Red
        Write-Host "  Run: Install-Module ps2exe -Scope CurrentUser" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "  ps2exe found." -ForegroundColor DarkGray
}

# ─── Step 3: Compile ──────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  [3/3] Compiling to exe..." -ForegroundColor White
Write-Host ""

# Parse version into 4-part format for exe metadata
$vParts   = ($Version -replace '[^0-9\.]', '') -split '\.'
while ($vParts.Count -lt 4) { $vParts += '0' }
$versionFull = ($vParts[0..3] -join '.')

$iconPath = Join-Path $PSScriptRoot 'icon.ico'
$iconArg  = if (Test-Path $iconPath) { $iconPath } else { $null }

$ps2exeParams = @{
    InputFile       = $mergedPs1
    OutputFile      = $outputExe
    requireAdmin    = $true
    title           = 'JRTreborn'
    description     = 'Junkware Removal Tool Reborn — Open Source Adware & PUP Remover'
    company         = 'JRTreborn Open Source Project'
    product         = 'JRTreborn'
    copyright       = "Open Source (MIT) $(Get-Date -Format yyyy)"
    version         = $versionFull
    noError         = $false
    noConsole       = $false
}

if ($iconArg) {
    $ps2exeParams['iconFile'] = $iconArg
}

try {
    Invoke-PS2EXE @ps2exeParams
} catch {
    Write-Host ""
    Write-Host "  [!] ps2exe compilation failed: $_" -ForegroundColor Red
    exit 1
}

# ─── Summary ──────────────────────────────────────────────────────────────────

if (Test-Path $outputExe) {
    $sizeMB = [math]::Round((Get-Item $outputExe).Length / 1MB, 2)
    Write-Host ""
    Write-Host "  ✓ Build complete!" -ForegroundColor Green
    Write-Host "    Output: $outputExe ($sizeMB MB)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  The exe will:" -ForegroundColor White
    Write-Host "    • Auto-request UAC elevation on launch" -ForegroundColor DarkGray
    Write-Host "    • Run on any Windows 10/11 machine (no install needed)" -ForegroundColor DarkGray
    Write-Host "    • Show the full interactive JRTreborn TUI" -ForegroundColor DarkGray
    Write-Host "    • Contain all detection database signatures embedded" -ForegroundColor DarkGray
    Write-Host ""
} else {
    Write-Host "  [!] exe not found after compilation — check ps2exe output above." -ForegroundColor Red
    exit 1
}
