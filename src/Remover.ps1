# Remover.ps1 - Removal engine for detected adware, PUPs, and junkware

function Invoke-RemoveAll {
    param(
        [System.Collections.Generic.List[hashtable]]$DetectedItems,
        [switch]$DryRun
    )

    $summary = @{ Found = $DetectedItems.Count; Removed = 0; Errors = 0; Skipped = 0 }

    if ($DryRun) {
        Write-LogEntry -Category 'INFO' -Message "Dry run mode — no changes will be made."
    }

    Write-LogEntry -Category 'INFO' -Message "Beginning removal of $($DetectedItems.Count) detected item(s)..."
    Write-Host ""

    # Order matters: kill processes first, then stop services, then remove everything else
    $order = @('Process', 'Service', 'Task', 'Program', 'RegistryKey', 'RegistryValue',
                'Folder', 'File', 'StartupFile', 'BrowserHijack', 'BrowserExtension', 'IEBho',
                'PolicyExtension', 'PolicyOverride')

    foreach ($type in $order) {
        $items = $DetectedItems | Where-Object { $_.Type -eq $type }
        foreach ($item in $items) {
            $result = Remove-Item_Safe -Item $item -DryRun:$DryRun
            if ($result -eq 'removed') { $summary.Removed++ }
            elseif ($result -eq 'error') { $summary.Errors++ }
            else { $summary.Skipped++ }
        }
    }

    Write-Host ""
    Write-LogEntry -Category 'INFO' -Message "Removal complete. Removed: $($summary.Removed) | Errors: $($summary.Errors) | Skipped: $($summary.Skipped)"
    return $summary
}

function Remove-Item_Safe {
    param([hashtable]$Item, [switch]$DryRun)

    try {
        switch ($Item.Type) {
            'Process'          { return Remove-JunkProcess   -Item $Item -DryRun:$DryRun }
            'Service'          { return Remove-JunkService   -Item $Item -DryRun:$DryRun }
            'Task'             { return Remove-JunkTask      -Item $Item -DryRun:$DryRun }
            'Program'          { return Remove-JunkProgram   -Item $Item -DryRun:$DryRun }
            'RegistryKey'      { return Remove-RegKey        -Item $Item -DryRun:$DryRun }
            'RegistryValue'    { return Remove-RegValue      -Item $Item -DryRun:$DryRun }
            'Folder'           { return Remove-JunkFolder    -Item $Item -DryRun:$DryRun }
            'File'             { return Remove-JunkFile      -Item $Item -DryRun:$DryRun }
            'StartupFile'      { return Remove-JunkFile      -Item $Item -DryRun:$DryRun }
            'BrowserHijack'    { return Reset-BrowserHijack  -Item $Item -DryRun:$DryRun }
            'BrowserExtension' { return Remove-BrowserExt    -Item $Item -DryRun:$DryRun }
            'IEBho'            { return Remove-RegKey        -Item @{ Data = @{ path = $Item.Data; action = 'remove_key' }; Name = $Item.Name } -DryRun:$DryRun }
            'PolicyExtension'  { return Remove-PolicyExtension -Item $Item -DryRun:$DryRun }
            'PolicyOverride'   { return Remove-PolicyValue    -Item $Item -DryRun:$DryRun }
        }
    } catch {
        Write-LogEntry -Category 'ERROR' -Message "Failed to remove [$($Item.Type)] $($Item.Name): $($_.Exception.Message)"
        return 'error'
    }
    return 'skipped'
}

# ─── Process Removal ─────────────────────────────────────────────────────────

function Remove-JunkProcess {
    param([hashtable]$Item, [switch]$DryRun)

    $procName = [System.IO.Path]::GetFileNameWithoutExtension($Item.Data)
    $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue

    if (-not $procs) { return 'skipped' }

    if ($DryRun) {
        Write-LogEntry -Category 'INFO' -Message "[DryRun] Would kill process: $procName"
        return 'skipped'
    }

    try {
        $procs | Stop-Process -Force -ErrorAction Stop
        Write-LogEntry -Category 'REMOVED' -Message "Killed process: $procName"
        return 'removed'
    } catch {
        Write-LogEntry -Category 'ERROR' -Message "Could not kill process $procName`: $($_.Exception.Message)"
        return 'error'
    }
}

# ─── Service Removal ─────────────────────────────────────────────────────────

function Remove-JunkService {
    param([hashtable]$Item, [switch]$DryRun)

    $svcName = $Item.Data

    if ($DryRun) {
        Write-LogEntry -Category 'INFO' -Message "[DryRun] Would stop and delete service: $svcName"
        return 'skipped'
    }

    try {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        }

        # Use sc.exe to delete — more reliable than Remove-Service on older OS
        $result = & sc.exe delete $svcName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-LogEntry -Category 'REMOVED' -Message "Deleted service: $svcName ($($Item.DisplayName))"
            return 'removed'
        } else {
            Write-LogEntry -Category 'WARNING' -Message "sc.exe returned non-zero for service '$svcName': $result"
            return 'error'
        }
    } catch {
        Write-LogEntry -Category 'ERROR' -Message "Could not remove service $svcName`: $($_.Exception.Message)"
        return 'error'
    }
}

# ─── Scheduled Task Removal ──────────────────────────────────────────────────

function Remove-JunkTask {
    param([hashtable]$Item, [switch]$DryRun)

    $task = $Item.Data

    if ($DryRun) {
        Write-LogEntry -Category 'INFO' -Message "[DryRun] Would delete scheduled task: $($task.TaskName)"
        return 'skipped'
    }

    try {
        Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
        Write-LogEntry -Category 'REMOVED' -Message "Deleted scheduled task: $($task.TaskName)"
        return 'removed'
    } catch {
        Write-LogEntry -Category 'ERROR' -Message "Could not delete task '$($task.TaskName)': $($_.Exception.Message)"
        return 'error'
    }
}

# ─── Program Uninstall ───────────────────────────────────────────────────────

function Remove-JunkProgram {
    param([hashtable]$Item, [switch]$DryRun)

    $app = $Item.Data

    if ($DryRun) {
        Write-LogEntry -Category 'INFO' -Message "[DryRun] Would uninstall: $($app.DisplayName)"
        return 'skipped'
    }

    # Prefer quiet/silent uninstall strings
    $uninstallCmd = if ($app.QuietUninstall) { $app.QuietUninstall } else { $app.UninstallStr }

    if (-not $uninstallCmd) {
        Write-LogEntry -Category 'WARNING' -Message "No uninstall string found for: $($app.DisplayName)"
        return 'error'
    }

    try {
        Write-LogEntry -Category 'INFO' -Message "Uninstalling: $($app.DisplayName) ..."

        # Parse the uninstall string — may be quoted path + args, or msiexec, or rundll32
        if ($uninstallCmd -like 'MsiExec*' -or $uninstallCmd -like 'msiexec*') {
            # Extract product code and run silent
            if ($uninstallCmd -match '\{[0-9A-F\-]{36}\}') {
                $productCode = $Matches[0]
                $proc = Start-Process 'msiexec.exe' -ArgumentList "/x $productCode /qn /norestart" -Wait -PassThru -ErrorAction Stop
            } else {
                $proc = Start-Process 'msiexec.exe' -ArgumentList ($uninstallCmd -replace '^msiexec\.exe\s*', '') -Wait -PassThru -ErrorAction Stop
            }
        } elseif ($uninstallCmd -like 'rundll32*') {
            $proc = Start-Process 'rundll32.exe' -ArgumentList ($uninstallCmd -replace '^rundll32\.exe\s*', '') -Wait -PassThru -ErrorAction Stop
        } else {
            # Try to parse quoted path from string
            if ($uninstallCmd -match '^"([^"]+)"\s*(.*)$') {
                $exePath = $Matches[1]
                $args    = $Matches[2]
                # Append silent flags if not present
                if ($args -notmatch '/S|/s|/silent|/quiet|/q') {
                    $args = "$args /S"
                }
                $proc = Start-Process -FilePath $exePath -ArgumentList $args -Wait -PassThru -ErrorAction Stop
            } else {
                $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$uninstallCmd`"" -Wait -PassThru -ErrorAction Stop
            }
        }

        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
            Write-LogEntry -Category 'REMOVED' -Message "Uninstalled: $($app.DisplayName)"
            # Clean up leftover registry key
            Remove-Item -Path $app.RegPath -Recurse -Force -ErrorAction SilentlyContinue
            return 'removed'
        } else {
            Write-LogEntry -Category 'WARNING' -Message "Uninstaller exited with code $($proc.ExitCode) for: $($app.DisplayName)"
            return 'error'
        }
    } catch {
        Write-LogEntry -Category 'ERROR' -Message "Uninstall failed for '$($app.DisplayName)': $($_.Exception.Message)"
        return 'error'
    }
}

# ─── Registry Removal ────────────────────────────────────────────────────────

function Remove-RegKey {
    param([hashtable]$Item, [switch]$DryRun)

    $entry = $Item.Data

    if ($DryRun) {
        Write-LogEntry -Category 'INFO' -Message "[DryRun] Would delete registry key: $($entry.path)"
        return 'skipped'
    }

    try {
        Remove-Item -Path $entry.path -Recurse -Force -ErrorAction Stop
        Write-LogEntry -Category 'REMOVED' -Message "Deleted registry key: $($entry.path)"
        return 'removed'
    } catch {
        Write-LogEntry -Category 'ERROR' -Message "Could not delete registry key '$($entry.path)': $($_.Exception.Message)"
        return 'error'
    }
}

function Remove-RegValue {
    param([hashtable]$Item, [switch]$DryRun)

    $entry = $Item.Data

    if ($DryRun) {
        Write-LogEntry -Category 'INFO' -Message "[DryRun] Would delete registry value: $($entry.path)\$($entry.value)"
        return 'skipped'
    }

    try {
        Remove-ItemProperty -Path $entry.path -Name $entry.value -Force -ErrorAction Stop
        Write-LogEntry -Category 'REMOVED' -Message "Deleted registry value: $($entry.path)\$($entry.value)"
        return 'removed'
    } catch {
        Write-LogEntry -Category 'ERROR' -Message "Could not delete registry value '$($entry.path)\$($entry.value)': $($_.Exception.Message)"
        return 'error'
    }
}

# ─── File/Folder Removal ─────────────────────────────────────────────────────

function Remove-JunkFolder {
    param([hashtable]$Item, [switch]$DryRun)

    $path = $Item.Data

    if ($DryRun) {
        Write-LogEntry -Category 'INFO' -Message "[DryRun] Would delete folder: $path"
        return 'skipped'
    }

    try {
        # Try normal removal first, then take ownership if needed
        Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
        Write-LogEntry -Category 'REMOVED' -Message "Deleted folder: $path"
        return 'removed'
    } catch {
        Write-LogEntry -Category 'WARNING' -Message "Normal delete failed for '$path', trying forced removal..."
        try {
            & takeown /F "$path" /R /D Y 2>&1 | Out-Null
            & icacls "$path" /grant Administrators:F /T 2>&1 | Out-Null
            Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
            Write-LogEntry -Category 'REMOVED' -Message "Deleted folder (forced ownership): $path"
            return 'removed'
        } catch {
            Write-LogEntry -Category 'ERROR' -Message "Could not delete folder '$path': $($_.Exception.Message)"
            return 'error'
        }
    }
}

function Remove-JunkFile {
    param([hashtable]$Item, [switch]$DryRun)

    $path = $Item.Data

    if ($DryRun) {
        Write-LogEntry -Category 'INFO' -Message "[DryRun] Would delete file: $path"
        return 'skipped'
    }

    try {
        Remove-Item -Path $path -Force -ErrorAction Stop
        Write-LogEntry -Category 'REMOVED' -Message "Deleted file: $path"
        return 'removed'
    } catch {
        Write-LogEntry -Category 'ERROR' -Message "Could not delete file '$path': $($_.Exception.Message)"
        return 'error'
    }
}

# ─── Browser Hijack Reset ────────────────────────────────────────────────────

function Reset-BrowserHijack {
    param([hashtable]$Item, [switch]$DryRun)

    $data = $Item.Data

    if ($DryRun) {
        Write-LogEntry -Category 'INFO' -Message "[DryRun] Would reset browser homepage: $($data.Browser) / $($data.Profile)"
        return 'skipped'
    }

    if ($data.Browser -eq 'Firefox') {
        return Reset-FirefoxHijack -Item $Item -DryRun:$DryRun
    }

    # Chromium-based: edit Preferences JSON
    try {
        $prefsPath = $data.PrefsPath
        if (-not (Test-Path $prefsPath)) { return 'skipped' }

        # Refuse to modify preferences while the browser is open — it would just be overwritten
        # and we could race-corrupt the file.
        $browserExe = switch ($data.Browser) {
            'Google Chrome'  { 'chrome' }
            'Microsoft Edge' { 'msedge' }
            'Brave Browser'  { 'brave' }
            default          { 'chrome' }
        }
        if (Get-Process -Name $browserExe -ErrorAction SilentlyContinue) {
            Write-LogEntry -Category 'WARNING' -Message "$($data.Browser) is running. Close it and re-run to reset the homepage for profile: $($data.Profile)"
            return 'skipped'
        }

        $prefs = Get-Content -Path $prefsPath -Raw -ErrorAction Stop | ConvertFrom-Json

        $changed = $false

        if ($prefs.homepage -like "*$($data.Hijacker)*") {
            $prefs.homepage = 'https://www.google.com'
            $changed = $true
        }

        if ($prefs.session.startup_urls) {
            $cleaned = $prefs.session.startup_urls | Where-Object { $_ -notlike "*$($data.Hijacker)*" }
            if ($cleaned.Count -ne $prefs.session.startup_urls.Count) {
                $prefs.session.startup_urls = $cleaned
                $changed = $true
            }
        }

        if ($changed) {
            # Back up before writing — ConvertTo-Json round-trips are lossy on exotic Chrome prefs
            $backupPath = "$prefsPath.jrtbackup"
            Copy-Item -Path $prefsPath -Destination $backupPath -Force -ErrorAction SilentlyContinue

            $prefs | ConvertTo-Json -Depth 20 | Set-Content -Path $prefsPath -Encoding UTF8 -Force -ErrorAction Stop
            Write-LogEntry -Category 'REMOVED' -Message "Reset browser homepage: $($data.Browser) / $($data.Profile) (backup: $backupPath)"
            return 'removed'
        }

        return 'skipped'
    } catch {
        Write-LogEntry -Category 'ERROR' -Message "Could not reset browser hijack for $($data.Browser): $($_.Exception.Message)"
        return 'error'
    }
}

function Reset-FirefoxHijack {
    param([hashtable]$Item, [switch]$DryRun)

    $data = $Item.Data
    $prefsPath = $data.PrefsPath

    if ($DryRun) {
        Write-LogEntry -Category 'INFO' -Message "[DryRun] Would reset Firefox homepage: $($data.Profile)"
        return 'skipped'
    }

    try {
        $lines = Get-Content -Path $prefsPath -ErrorAction Stop
        $cleaned = $lines | Where-Object {
            -not ($_ -like "*browser.startup.homepage*" -and $_ -like "*$($data.Hijacker)*")
        }

        if ($cleaned.Count -ne $lines.Count) {
            $cleaned | Set-Content -Path $prefsPath -Encoding UTF8 -Force -ErrorAction Stop
            Write-LogEntry -Category 'REMOVED' -Message "Reset Firefox homepage: $($data.Profile)"
            return 'removed'
        }
        return 'skipped'
    } catch {
        Write-LogEntry -Category 'ERROR' -Message "Could not reset Firefox homepage: $($_.Exception.Message)"
        return 'error'
    }
}

# ─── Browser Extension Removal ───────────────────────────────────────────────

# ─── Browser Policy Removal ──────────────────────────────────────────────────

function Remove-PolicyExtension {
    param([hashtable]$Item, [switch]$DryRun)

    $data = $Item.Data

    if ($DryRun) {
        Write-LogEntry -Category 'INFO' -Message "[DryRun] Would remove force-install policy for extension: $($data.ExtId)"
        return 'skipped'
    }

    try {
        Remove-ItemProperty -Path $data.RegPath -Name $data.ValueName -Force -ErrorAction Stop
        Write-LogEntry -Category 'REMOVED' -Message "Removed force-install policy for extension: $($data.ExtId)"
        return 'removed'
    } catch {
        Write-LogEntry -Category 'ERROR' -Message "Could not remove policy extension entry '$($data.ExtId)': $($_.Exception.Message)"
        return 'error'
    }
}

function Remove-PolicyValue {
    param([hashtable]$Item, [switch]$DryRun)

    $data = $Item.Data

    if ($DryRun) {
        Write-LogEntry -Category 'INFO' -Message "[DryRun] Would remove browser policy override: $($Item.Name)"
        return 'skipped'
    }

    try {
        Remove-ItemProperty -Path $data.RegPath -Name $data.ValueName -Force -ErrorAction Stop
        Write-LogEntry -Category 'REMOVED' -Message "Removed browser policy override: $($Item.Name)"
        return 'removed'
    } catch {
        Write-LogEntry -Category 'ERROR' -Message "Could not remove policy value '$($Item.Name)': $($_.Exception.Message)"
        return 'error'
    }
}

function Remove-BrowserExt {
    param([hashtable]$Item, [switch]$DryRun)

    $data = $Item.Data

    if ($DryRun) {
        Write-LogEntry -Category 'INFO' -Message "[DryRun] Would remove $($data.Browser) extension: $($Item.Name) [$($data.ExtId)]"
        return 'skipped'
    }

    try {
        if (Test-Path $data.ExtPath) {
            Remove-Item -Path $data.ExtPath -Recurse -Force -ErrorAction Stop
            Write-LogEntry -Category 'REMOVED' -Message "Removed $($data.Browser) extension: $($Item.Name) [$($data.ExtId)]"
            return 'removed'
        }
        return 'skipped'
    } catch {
        Write-LogEntry -Category 'ERROR' -Message "Could not remove extension '$($Item.Name)': $($_.Exception.Message)"
        return 'error'
    }
}
