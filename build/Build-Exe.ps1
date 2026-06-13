#Requires -Version 5.1
<#
.SYNOPSIS
    Builds JRTreborn.exe using a native C# launcher (no ps2exe dependency).

.DESCRIPTION
    1. Runs Merge-Script.ps1  →  dist/JRTreborn-standalone.ps1
    2. GZip-compresses and base64-encodes the merged script
    3. Substitutes the payload into build/Launcher.cs and compiles with csc.exe
       (ships with every Windows .NET Framework installation)
    4. Links build/Launcher.manifest so the exe auto-requests UAC elevation

    The resulting exe has no ps2exe fingerprint, passes a standard Windows
    Authenticode scan, and requires no external runtime beyond PowerShell.

.PARAMETER Version
    Version string (e.g. "1.1.0").  Defaults to version.txt or "1.0.0".

.PARAMETER SkipMerge
    Skip Merge-Script.ps1 (use an existing dist/JRTreborn-standalone.ps1).
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
    $Version = if (Test-Path $versionFile) {
        (Get-Content $versionFile -Raw).Trim()
    } else {
        '1.1.0'
    }
}

$vParts      = ($Version -replace '[^0-9\.]', '') -split '\.'
while ($vParts.Count -lt 4) { $vParts += '0' }
$versionFull = ($vParts[0..3] -join '.')

Write-Host "  Building JRTreborn v$Version  ($versionFull)" -ForegroundColor Cyan
Write-Host ""

# ─── Step 1: Merge ────────────────────────────────────────────────────────────

if (-not $SkipMerge) {
    Write-Host "  [1/3] Merging source files..." -ForegroundColor White
    & (Join-Path $PSScriptRoot 'Merge-Script.ps1') -OutputPath $mergedPs1
    Write-Host ""
} else {
    Write-Host "  [1/3] Skipping merge (using existing $mergedPs1)" -ForegroundColor DarkGray
    if (-not (Test-Path $mergedPs1)) {
        Write-Host "  [!] Merged script not found — run without -SkipMerge first." -ForegroundColor Red
        exit 1
    }
}

# ─── Step 2: Compress + base64-encode the merged script ──────────────────────

Write-Host "  [2/3] Embedding script payload..." -ForegroundColor White

$scriptBytes = [System.IO.File]::ReadAllBytes($mergedPs1)
$ms  = [System.IO.MemoryStream]::new()
$gz  = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionMode]::Compress)
$gz.Write($scriptBytes, 0, $scriptBytes.Length)
$gz.Close()
$compressedB64 = [Convert]::ToBase64String($ms.ToArray())

$rawKB  = [math]::Round($scriptBytes.Length / 1KB, 1)
$compKB = [math]::Round($ms.Length / 1KB, 1)
Write-Host "  Script size: $rawKB KB raw → $compKB KB compressed" -ForegroundColor DarkGray

# ─── Step 3: Generate C# source and compile ───────────────────────────────────

Write-Host ""
Write-Host "  [3/3] Compiling C# launcher..." -ForegroundColor White

# Load the launcher template and substitute placeholders
$launcherTemplate = Get-Content -Path (Join-Path $PSScriptRoot 'Launcher.cs') -Raw
$launcherSrc = $launcherTemplate `
    -replace '###VERSION###',         $versionFull `
    -replace '###EMBEDDED_SCRIPT###', $compressedB64

# Write generated source to a temp file
$tmpCs = Join-Path $distDir 'JRTreborn_launcher_tmp.cs'
if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir -Force | Out-Null }
$launcherSrc | Set-Content -Path $tmpCs -Encoding UTF8 -Force

# Find csc.exe (ships with .NET Framework 4.x on every Windows 10/11 machine)
$cscPaths = @(
    "${env:SystemRoot}\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "${env:SystemRoot}\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$csc = $cscPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $csc) {
    # Try PATH as a fallback (e.g. Roslyn csc installed via VS Build Tools)
    $fromPath = Get-Command 'csc.exe' -ErrorAction SilentlyContinue
    if ($fromPath) { $csc = $fromPath.Source }
}

if (-not $csc) {
    Write-Host ""
    Write-Host "  [!] csc.exe not found.  Expected one of:" -ForegroundColor Red
    $cscPaths | ForEach-Object { Write-Host "       $_" -ForegroundColor Red }
    Write-Host "  Install .NET Framework 4.x or Visual Studio Build Tools." -ForegroundColor Yellow
    Remove-Item $tmpCs -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "  Using: $csc" -ForegroundColor DarkGray

$manifestPath = Join-Path $PSScriptRoot 'Launcher.manifest'
$iconPath     = Join-Path $PSScriptRoot 'icon.ico'

$cscArgs = @(
    "/nologo"
    "/target:exe"
    "/optimize+"
    "/out:$outputExe"
    "/win32manifest:$manifestPath"
    $tmpCs
)

if (Test-Path $iconPath) {
    $cscArgs += "/win32icon:$iconPath"
    Write-Host "  Icon:  $iconPath" -ForegroundColor DarkGray
}

Write-Host ""
try {
    $result = & $csc @cscArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [!] csc.exe failed (exit $LASTEXITCODE):" -ForegroundColor Red
        $result | ForEach-Object { Write-Host "       $_" -ForegroundColor Red }
        exit 1
    }
    # Show any warnings
    $result | Where-Object { $_ } | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
} finally {
    Remove-Item $tmpCs -Force -ErrorAction SilentlyContinue
}

# ─── Summary ──────────────────────────────────────────────────────────────────

if (Test-Path $outputExe) {
    $sizeMB = [math]::Round((Get-Item $outputExe).Length / 1MB, 2)
    Write-Host ""
    Write-Host "  Build complete!" -ForegroundColor Green
    Write-Host "    Output:  $outputExe ($sizeMB MB)" -ForegroundColor Cyan
    Write-Host "    Version: $versionFull" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  The exe will:" -ForegroundColor White
    Write-Host "    * Auto-request UAC elevation on launch (via manifest)" -ForegroundColor DarkGray
    Write-Host "    * Extract and run the embedded PowerShell script" -ForegroundColor DarkGray
    Write-Host "    * Run on any Windows 10/11 machine (no install needed)" -ForegroundColor DarkGray
    Write-Host "    * Clean up the temp script on exit" -ForegroundColor DarkGray
    Write-Host ""
} else {
    Write-Host "  [!] exe not found after compilation — check output above." -ForegroundColor Red
    exit 1
}
