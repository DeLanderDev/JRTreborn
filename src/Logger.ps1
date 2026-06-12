# Logger.ps1 - Scan/removal logging and HTML report generation

$script:LogEntries = [System.Collections.Generic.List[hashtable]]::new()
$script:ScanStartTime = $null
$script:LogFilePath = $null

function Initialize-Logger {
    param([string]$OutputDir)

    $script:ScanStartTime = Get-Date
    $timestamp = $script:ScanStartTime.ToString('yyyy-MM-dd_HH-mm-ss')
    $script:LogFilePath = Join-Path $OutputDir "JRTreborn_$timestamp.log"
    $script:LogEntries.Clear()

    Write-LogEntry -Category "INFO" -Message "JRTreborn scan started at $($script:ScanStartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-LogEntry -Category "INFO" -Message "OS: $([System.Environment]::OSVersion.VersionString)"
    Write-LogEntry -Category "INFO" -Message "User: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
}

function Write-LogEntry {
    param(
        [ValidateSet('INFO','FOUND','REMOVED','SKIPPED','WARNING','ERROR')]
        [string]$Category,
        [string]$Message,
        [string]$Detail = ''
    )

    $entry = @{
        Time     = (Get-Date).ToString('HH:mm:ss')
        Category = $Category
        Message  = $Message
        Detail   = $Detail
    }
    $script:LogEntries.Add($entry)

    $color = switch ($Category) {
        'FOUND'   { 'Yellow' }
        'REMOVED' { 'Green' }
        'WARNING' { 'DarkYellow' }
        'ERROR'   { 'Red' }
        'SKIPPED' { 'DarkGray' }
        default   { 'Gray' }
    }

    $prefix = "[$($entry.Time)] [$Category]"
    Write-Host "$prefix $Message" -ForegroundColor $color
    if ($Detail) {
        Write-Host "         $Detail" -ForegroundColor DarkGray
    }
}

function Export-Report {
    param(
        [string]$OutputDir,
        [hashtable]$ScanSummary
    )

    $endTime = Get-Date
    $duration = $endTime - $script:ScanStartTime

    # Plain text log
    $lines = @()
    $lines += "=" * 70
    $lines += "  JRTreborn - Junkware Removal Tool Reborn"
    $lines += "  Scan completed: $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    $lines += "  Duration: $($duration.ToString('mm\:ss'))"
    $lines += "=" * 70
    $lines += ""

    foreach ($entry in $script:LogEntries) {
        $line = "[$($entry.Time)] [$($entry.Category)] $($entry.Message)"
        if ($entry.Detail) { $line += " | $($entry.Detail)" }
        $lines += $line
    }

    $lines += ""
    $lines += "-" * 70
    $lines += "SUMMARY"
    $lines += "-" * 70
    $lines += "Items found:   $($ScanSummary.Found)"
    $lines += "Items removed: $($ScanSummary.Removed)"
    $lines += "Errors:        $($ScanSummary.Errors)"
    $lines += "-" * 70

    $lines | Out-File -FilePath $script:LogFilePath -Encoding UTF8

    # HTML report
    $htmlPath = [System.IO.Path]::ChangeExtension($script:LogFilePath, '.html')
    $htmlRows = foreach ($entry in $script:LogEntries) {
        $cssClass = switch ($entry.Category) {
            'FOUND'   { 'found' }
            'REMOVED' { 'removed' }
            'WARNING' { 'warning' }
            'ERROR'   { 'error' }
            'SKIPPED' { 'skipped' }
            default   { 'info' }
        }
        $detail = if ($entry.Detail) { "<br><small class='detail'>$([System.Net.WebUtility]::HtmlEncode($entry.Detail))</small>" } else { '' }
        "<tr class='$cssClass'><td class='time'>$($entry.Time)</td><td class='cat'>$($entry.Category)</td><td>$([System.Net.WebUtility]::HtmlEncode($entry.Message))$detail</td></tr>"
    }

    $foundBadge   = "<span class='badge badge-found'>$($ScanSummary.Found) Found</span>"
    $removedBadge = "<span class='badge badge-removed'>$($ScanSummary.Removed) Removed</span>"
    $errorBadge   = "<span class='badge badge-error'>$($ScanSummary.Errors) Errors</span>"

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>JRTreborn Report - $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))</title>
<style>
  :root {
    --bg: #1a1a2e; --surface: #16213e; --surface2: #0f3460;
    --text: #e0e0e0; --text-dim: #888;
    --green: #4ecca3; --yellow: #f5a623; --red: #e94560; --gray: #666;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: var(--bg); color: var(--text); font-family: 'Segoe UI', system-ui, sans-serif; font-size: 14px; }
  header { background: var(--surface2); padding: 24px 32px; border-bottom: 2px solid var(--green); }
  header h1 { color: var(--green); font-size: 22px; font-weight: 700; letter-spacing: 1px; }
  header .meta { color: var(--text-dim); margin-top: 6px; font-size: 13px; }
  .summary { display: flex; gap: 16px; padding: 20px 32px; background: var(--surface); border-bottom: 1px solid #333; }
  .badge { padding: 6px 14px; border-radius: 4px; font-weight: 600; font-size: 13px; }
  .badge-found { background: rgba(245,166,35,0.15); color: var(--yellow); border: 1px solid var(--yellow); }
  .badge-removed { background: rgba(78,204,163,0.15); color: var(--green); border: 1px solid var(--green); }
  .badge-error { background: rgba(233,69,96,0.15); color: var(--red); border: 1px solid var(--red); }
  .log-container { padding: 24px 32px; }
  table { width: 100%; border-collapse: collapse; }
  tr + tr { border-top: 1px solid #1e1e3a; }
  td { padding: 7px 10px; vertical-align: top; }
  td.time { color: var(--text-dim); font-family: monospace; white-space: nowrap; width: 80px; }
  td.cat { font-weight: 700; white-space: nowrap; width: 90px; font-size: 12px; text-transform: uppercase; }
  .detail { color: var(--text-dim); font-size: 12px; }
  .found td { color: var(--yellow); }
  .found td.cat { color: var(--yellow); }
  .removed td { color: var(--green); }
  .removed td.cat { color: var(--green); }
  .warning td { color: #f0a500; }
  .error td { color: var(--red); }
  .skipped td { color: var(--gray); }
  .info td { color: var(--text-dim); }
  tr:hover { background: rgba(255,255,255,0.03); }
  .duration { color: var(--text-dim); font-size: 13px; margin-left: auto; align-self: center; }
  footer { text-align: center; padding: 20px; color: var(--text-dim); font-size: 12px; border-top: 1px solid #333; margin-top: 24px; }
  a { color: var(--green); text-decoration: none; }
</style>
</head>
<body>
<header>
  <h1>JRTreborn &mdash; Junkware Removal Tool Reborn</h1>
  <div class="meta">
    Scan completed: $($endTime.ToString('yyyy-MM-dd HH:mm:ss')) &nbsp;&bull;&nbsp;
    Duration: $($duration.ToString('mm\:ss')) &nbsp;&bull;&nbsp;
    Host: $env:COMPUTERNAME &nbsp;&bull;&nbsp;
    User: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
  </div>
</header>
<div class="summary">
  $foundBadge $removedBadge $errorBadge
  <span class="duration">Duration: $($duration.ToString('mm\:ss'))</span>
</div>
<div class="log-container">
  <table>
    <tbody>
      $($htmlRows -join "`n      ")
    </tbody>
  </table>
</div>
<footer>
  JRTreborn &mdash; Open Source Junkware Removal Tool &mdash;
  <a href="https://github.com/delanderdev/jrtreborn">github.com/delanderdev/jrtreborn</a>
</footer>
</body>
</html>
"@

    $html | Out-File -FilePath $htmlPath -Encoding UTF8

    return @{ Log = $script:LogFilePath; Html = $htmlPath }
}
