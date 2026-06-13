#Requires -Version 5.1
<#
.SYNOPSIS
    Merges all JRTreborn source files and database into a single standalone .ps1

.DESCRIPTION
    Reads src/*.ps1 files and all database/*.json files, embeds the database
    as compressed base64 strings, and writes a self-contained script to
    dist/JRTreborn-standalone.ps1 that requires no external files.

.PARAMETER OutputPath
    Path for the merged output file. Defaults to dist/JRTreborn-standalone.ps1
#>
param(
    [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
if (-not $OutputPath) {
    $OutputPath = Join-Path $root 'dist\JRTreborn-standalone.ps1'
}

$distDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}

Write-Host "  Building standalone script..." -ForegroundColor Cyan
Write-Host "  Root:   $root"
Write-Host "  Output: $OutputPath"
Write-Host ""

# ─── Helper: compress + base64 encode a string ────────────────────────────────

function ConvertTo-CompressedBase64 {
    param([string]$Text)
    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $ms     = [System.IO.MemoryStream]::new()
    $gz     = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionMode]::Compress)
    $gz.Write($bytes, 0, $bytes.Length)
    $gz.Close()
    return [Convert]::ToBase64String($ms.ToArray())
}

# ─── Load source files ────────────────────────────────────────────────────────

$srcOrder = @('Logger.ps1', 'RestorePoint.ps1', 'Scanner.ps1', 'Remover.ps1')
$srcDir   = Join-Path $root 'src'
$srcBlocks = foreach ($file in $srcOrder) {
    $path = Join-Path $srcDir $file
    Write-Host "  Loading src: $file"
    Get-Content -Path $path -Raw
}

# ─── Load and embed database files ───────────────────────────────────────────

$dbDir   = Join-Path $root 'database'
$dbFiles = @('programs.json','registry.json','files.json','processes.json',
             'services.json','tasks.json','browsers.json','policies.json')

$dbEmbedLines = @()
$dbEmbedLines += '# ─── Embedded database (compressed base64) ──────────────────────────────────'
$dbEmbedLines += '$script:EmbeddedDb = @{'

foreach ($file in $dbFiles) {
    $path = Join-Path $dbDir $file
    if (-not (Test-Path $path)) {
        Write-Host "  WARNING: Missing DB file: $file" -ForegroundColor Yellow
        continue
    }
    $json   = Get-Content -Path $path -Raw
    $b64    = ConvertTo-CompressedBase64 -Text $json
    $key    = [System.IO.Path]::GetFileNameWithoutExtension($file)
    Write-Host "  Embedding: $file ($([math]::Round($json.Length/1KB,1)) KB raw -> $([math]::Round($b64.Length/1KB,1)) KB b64)"
    $dbEmbedLines += "    '$key' = '$b64'"
}
$dbEmbedLines += '}'

# ─── Replacement Import-Database that reads from embedded strings ─────────────

$importDbReplacement = @'
# ─── Embedded database loader ─────────────────────────────────────────────────

function ConvertFrom-CompressedBase64 {
    param([string]$B64)
    $compressed = [Convert]::FromBase64String($B64)
    $ms  = [System.IO.MemoryStream]::new($compressed)
    $gz  = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionMode]::Decompress)
    $out = [System.IO.MemoryStream]::new()
    $gz.CopyTo($out)
    return [System.Text.Encoding]::UTF8.GetString($out.ToArray())
}

function Import-Database {
    param([string]$DbPath)

    $db = @{}

    $keyMap = @{
        programs  = 'Programs'
        registry  = 'Registry'
        files     = 'Files'
        processes = 'Processes'
        services  = 'Services'
        tasks     = 'Tasks'
        browsers  = 'Browsers'
        policies  = 'Policies'
    }

    foreach ($rawKey in $script:EmbeddedDb.Keys) {
        $dbKey = $keyMap[$rawKey]
        if (-not $dbKey) { continue }

        try {
            $json   = ConvertFrom-CompressedBase64 -B64 $script:EmbeddedDb[$rawKey]
            $parsed = $json | ConvertFrom-Json
            $db[$dbKey] = switch ($dbKey) {
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
        } catch {
            Write-Host "  [!] Failed to load embedded DB '$rawKey': $_" -ForegroundColor Red
        }
    }

    return $db
}
'@

# ─── Load main script and strip module loading + Import-Database definition ───

$mainScript = Get-Content -Path (Join-Path $root 'JRTreborn.ps1') -Raw

# Remove the dot-source lines (src modules are inlined below)
$mainScript = $mainScript -replace '(?m)^\. \(Join-Path \$srcPath.*?\)\r?\n', ''
$mainScript = $mainScript -replace '(?m)^\$srcPath.*?\r?\n', ''

# Remove the existing Import-Database function block (replaced with embedded version)
$mainScript = $mainScript -replace '(?s)# ─── Database loader.*?^}(\r?\n)', ''

# Remove the $dbVersionFile / $dbVersion lines that read from the filesystem
$mainScript = $mainScript -replace '(?m)^\$dbVersionFile.*?\r?\n', ''
$mainScript = $mainScript -replace '(?m)^\$dbVersion.*?\r?\n', "Write-Host `"  Database: embedded (standalone build)`" -ForegroundColor DarkGray`n"

# ─── Assemble the final merged script ────────────────────────────────────────

$banner = @"
#Requires -Version 5.1
# ============================================================================
#  JRTreborn - Junkware Removal Tool Reborn  (standalone build)
#  Generated by build/Merge-Script.ps1
#  Do not edit this file directly — edit the sources in src/ and database/
# ============================================================================
"@

$parts = @()
$parts += $banner
$parts += ''
$parts += $dbEmbedLines -join "`n"
$parts += ''
$parts += '# ─── Source modules (inlined) ─────────────────────────────────────────────────'
$parts += ''
$parts += $srcBlocks -join "`n`n"
$parts += ''
$parts += $importDbReplacement
$parts += ''
$parts += '# ─── Main script ─────────────────────────────────────────────────────────────'
$parts += ''
$parts += $mainScript

$merged = $parts -join "`n"
$merged | Set-Content -Path $OutputPath -Encoding UTF8 -Force

$sizeKB = [math]::Round((Get-Item $OutputPath).Length / 1KB, 1)
Write-Host ""
Write-Host "  Done! Standalone script: $OutputPath ($sizeKB KB)" -ForegroundColor Green
