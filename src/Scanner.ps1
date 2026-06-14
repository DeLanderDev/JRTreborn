# Scanner.ps1 - Detection engine for adware, PUPs, and junkware

$script:DetectedItems = [System.Collections.Generic.List[hashtable]]::new()

function Get-DetectedItems { return $script:DetectedItems }

function Clear-DetectedItems { $script:DetectedItems.Clear() }

function Invoke-FullScan {
    param([hashtable]$Database)

    Clear-DetectedItems

    Write-LogEntry -Category 'INFO' -Message "Starting full system scan..."
    Write-Host ""

    Invoke-ProcessScan  -ProcessList $Database.Processes
    Invoke-ServiceScan  -ServiceList $Database.Services
    Invoke-TaskScan     -TaskList $Database.Tasks
    Invoke-ProgramScan  -ProgramList         $Database.Programs `
                        -PublisherList       $Database.ProgramPublishers `
                        -HeuristicList       $Database.ProgramHeuristics `
                        -HeuristicAllowlist  $Database.ProgramAllowlist `
                        -AppxList            $Database.ProgramAppx
    Invoke-RegistryScan -RegistryList $Database.Registry
    Invoke-FileScan     -FileList $Database.Files
    Invoke-BrowserScan  -BrowserData $Database.Browsers
    Invoke-PolicyScan   -PolicyData $Database.Policies

    Write-Host ""
    Write-LogEntry -Category 'INFO' -Message "Scan complete. $($script:DetectedItems.Count) item(s) found."

    return $script:DetectedItems
}

# ─── Process Scanner ─────────────────────────────────────────────────────────

function Invoke-ProcessScan {
    param([array]$ProcessList)

    Write-LogEntry -Category 'INFO' -Message "Scanning running processes..."

    $runningProcesses = Get-Process | Select-Object -ExpandProperty Name

    foreach ($entry in $ProcessList) {
        $procName = [System.IO.Path]::GetFileNameWithoutExtension($entry.name)
        $match = $runningProcesses | Where-Object { $_ -ieq $procName }
        if ($match) {
            Write-LogEntry -Category 'FOUND' -Message "Process: $($entry.name)" -Detail $entry.description
            $script:DetectedItems.Add(@{
                Type        = 'Process'
                Name        = $entry.name
                Description = $entry.description
                Data        = $entry.name
            })
        }
    }
}

# ─── Service Scanner ─────────────────────────────────────────────────────────

function Invoke-ServiceScan {
    param([array]$ServiceList)

    Write-LogEntry -Category 'INFO' -Message "Scanning Windows services..."

    foreach ($entry in $ServiceList) {
        $svc = Get-Service -Name $entry.name -ErrorAction SilentlyContinue
        if ($null -eq $svc -and $entry.display) {
            # Try matching by display name
            $svc = Get-Service | Where-Object { $_.DisplayName -ieq $entry.display } | Select-Object -First 1
        }
        if ($svc) {
            Write-LogEntry -Category 'FOUND' -Message "Service: $($svc.DisplayName) [$($svc.Name)]" -Detail $entry.description
            $script:DetectedItems.Add(@{
                Type        = 'Service'
                Name        = $entry.name
                DisplayName = $svc.DisplayName
                Description = $entry.description
                Data        = $svc.Name
            })
        }
    }
}

# ─── Scheduled Task Scanner ──────────────────────────────────────────────────

function Invoke-TaskScan {
    param([array]$TaskList)

    Write-LogEntry -Category 'INFO' -Message "Scanning scheduled tasks..."

    try {
        $allTasks = Get-ScheduledTask -ErrorAction Stop
    } catch {
        Write-LogEntry -Category 'WARNING' -Message "Could not enumerate scheduled tasks: $($_.Exception.Message)"
        return
    }

    foreach ($entry in $TaskList) {
        $found = $allTasks | Where-Object {
            $_.TaskName -ieq $entry.name -or
            $_.TaskName -like "*$($entry.name)*"
        }
        foreach ($task in $found) {
            Write-LogEntry -Category 'FOUND' -Message "Scheduled Task: $($task.TaskName)" -Detail $entry.description
            $script:DetectedItems.Add(@{
                Type        = 'Task'
                Name        = $task.TaskName
                TaskPath    = $task.TaskPath
                Description = $entry.description
                Data        = $task
            })
        }
    }
}

# ─── Installed Programs Scanner ──────────────────────────────────────────────

# Registry keys flagged during the current program scan (dedup across routes)
$script:FlaggedProgramKeys = $null
# Registry keys for trusted-vendor apps that must never be flagged (allowlist)
$script:ProgramAllowKeys = $null

function Add-ProgramDetection {
    param(
        [pscustomobject]$Hit,
        [string]$RuleName,
        [string]$Severity = 'Known',
        [string]$Detail
    )

    if ($script:FlaggedProgramKeys.Contains($Hit.Key)) { return }
    # Global safeguard: never flag apps published by a trusted/allowlisted vendor,
    # even via a 'Known' signature — prevents auto-removing legitimate software.
    if ($script:ProgramAllowKeys -and $script:ProgramAllowKeys.Contains($Hit.Key)) { return }
    [void]$script:FlaggedProgramKeys.Add($Hit.Key)

    $cat = if ($Severity -eq 'Suspected') { 'SUSPECT' } else { 'FOUND' }
    Write-LogEntry -Category $cat -Message "Program: $($Hit.DisplayName)" -Detail "$RuleName | Publisher: $($Hit.Publisher)"
    $script:DetectedItems.Add(@{
        Type        = 'Program'
        Name        = $Hit.DisplayName
        Description = $Detail
        Severity    = $Severity
        Data        = $Hit
    })
}

function Invoke-ProgramScan {
    param(
        [array]$ProgramList,
        [array]$PublisherList,
        [array]$HeuristicList,
        [array]$HeuristicAllowlist,
        [array]$AppxList
    )

    Write-LogEntry -Category 'INFO' -Message "Scanning installed programs..."

    $script:FlaggedProgramKeys = [System.Collections.Generic.HashSet[string]]::new()

    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    $installedApps = @(foreach ($path in $uninstallPaths) {
        if (Test-Path $path) {
            Get-ChildItem -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
                $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                if ($props.DisplayName) {
                    [pscustomobject]@{
                        Key           = $_.PSChildName
                        DisplayName   = $props.DisplayName
                        Publisher     = $props.Publisher
                        UninstallStr  = $props.UninstallString
                        QuietUninstall= $props.QuietUninstallString
                        InstallPath   = $props.InstallLocation
                        RegPath       = $_.PSPath
                    }
                }
            }
        }
    })

    # Pre-compute the trusted-vendor allowlist (by publisher) so every route honors it
    $script:ProgramAllowKeys = [System.Collections.Generic.HashSet[string]]::new()
    if ($HeuristicAllowlist) {
        foreach ($app in $installedApps) {
            if (-not $app.Publisher) { continue }
            foreach ($alw in $HeuristicAllowlist) {
                if ($app.Publisher -like "*$alw*") { [void]$script:ProgramAllowKeys.Add($app.Key); break }
            }
        }
    }

    # ── Route 1: known programs by DisplayName (and install path for distinctive names) ──
    foreach ($entry in $ProgramList) {
        foreach ($matchPattern in $entry.match) {
            $hits = $installedApps | Where-Object {
                $_.DisplayName -like "*$matchPattern*" -or
                ($matchPattern.Length -ge 5 -and $_.InstallPath -and $_.InstallPath -like "*$matchPattern*")
            }
            foreach ($hit in $hits) {
                Add-ProgramDetection -Hit $hit -RuleName $entry.name -Severity 'Known' -Detail $entry.name
            }
        }
    }

    # ── Route A: known-bad publisher (one rule covers an entire vendor) ──
    if ($PublisherList) {
        foreach ($pub in $PublisherList) {
            if (-not $pub.publisher) { continue }
            $hits = $installedApps | Where-Object { $_.Publisher -and $_.Publisher -like "*$($pub.publisher)*" }
            foreach ($hit in $hits) {
                Add-ProgramDetection -Hit $hit -RuleName $pub.name -Severity 'Known' -Detail "$($pub.name) [publisher: $($hit.Publisher)]"
            }
        }
    }

    # ── Route D/E: heuristic 'Suspected' tier — catches novel PUPs by pattern ──
    if ($HeuristicList) {
        foreach ($app in $installedApps) {
            if ($script:FlaggedProgramKeys.Contains($app.Key)) { continue }

            # Allowlist trusted vendors so legitimate software is never flagged
            $allowed = $false
            if ($HeuristicAllowlist) {
                foreach ($alw in $HeuristicAllowlist) {
                    if (($app.Publisher   -and $app.Publisher   -like "*$alw*") -or
                        ($app.DisplayName -and $app.DisplayName -like "*$alw*")) {
                        $allowed = $true; break
                    }
                }
            }
            if ($allowed) { continue }

            foreach ($h in $HeuristicList) {
                if (-not $h.pattern) { continue }
                $field  = if ($h.field) { $h.field } else { 'displayname' }
                $target = if ($field -eq 'publisher') { $app.Publisher } else { $app.DisplayName }
                if ($target -and $target -like "*$($h.pattern)*") {
                    $reason = "Suspected PUP — $($h.reason)"
                    # Route E: best-effort Authenticode signature enrichment
                    try {
                        if ($app.InstallPath -and (Test-Path $app.InstallPath)) {
                            $exe = Get-ChildItem -Path $app.InstallPath -Filter '*.exe' -ErrorAction SilentlyContinue |
                                   Select-Object -First 1
                            if ($exe) {
                                $sig = Get-AuthenticodeSignature -FilePath $exe.FullName -ErrorAction SilentlyContinue
                                if ($sig -and $sig.Status -ne 'Valid') {
                                    $reason += ' [unsigned/untrusted binary]'
                                }
                            }
                        }
                    } catch { }
                    Add-ProgramDetection -Hit $app -RuleName "Heuristic: $($h.pattern)" -Severity 'Suspected' -Detail $reason
                    break
                }
            }
        }
    }

    # ── Route C: Appx/MSIX Store bloatware (Suspected — never auto-removed) ──
    if ($AppxList -and (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        try {
            $pkgs = Get-AppxPackage -ErrorAction SilentlyContinue
            foreach ($pkg in $pkgs) {
                foreach ($pat in $AppxList) {
                    if (-not $pat.match) { continue }
                    if ($pkg.Name -like $pat.match) {
                        Write-LogEntry -Category 'SUSPECT' -Message "Appx package: $($pkg.Name)" -Detail $pat.name
                        $script:DetectedItems.Add(@{
                            Type        = 'AppxPackage'
                            Name        = $pkg.Name
                            Description = "Suspected Store bloatware — $($pat.name)"
                            Severity    = 'Suspected'
                            Data        = @{ PackageFullName = $pkg.PackageFullName; Name = $pkg.Name }
                        })
                        break
                    }
                }
            }
        } catch {
            Write-LogEntry -Category 'WARNING' -Message "Appx enumeration failed: $($_.Exception.Message)"
        }
    }
}

# ─── Registry Scanner ────────────────────────────────────────────────────────

function Invoke-RegistryScan {
    param([array]$RegistryList)

    Write-LogEntry -Category 'INFO' -Message "Scanning registry..."

    foreach ($entry in $RegistryList) {
        try {
            if ($entry.action -eq 'remove_key') {
                if (Test-Path $entry.path) {
                    Write-LogEntry -Category 'FOUND' -Message "Registry Key: $($entry.path)" -Detail $entry.name
                    $script:DetectedItems.Add(@{
                        Type        = 'RegistryKey'
                        Name        = $entry.name
                        Description = $entry.name
                        Data        = $entry
                    })
                }
            } elseif ($entry.action -eq 'remove_value') {
                if (Test-Path $entry.path) {
                    $val = Get-ItemProperty -Path $entry.path -Name $entry.value -ErrorAction SilentlyContinue
                    if ($null -ne $val) {
                        Write-LogEntry -Category 'FOUND' -Message "Registry Value: $($entry.path)\$($entry.value)" -Detail $entry.name
                        $script:DetectedItems.Add(@{
                            Type        = 'RegistryValue'
                            Name        = $entry.name
                            Description = $entry.name
                            Data        = $entry
                        })
                    }
                }
            }
        } catch {
            Write-LogEntry -Category 'WARNING' -Message "Registry scan error for $($entry.name): $($_.Exception.Message)"
        }
    }
}

# ─── File System Scanner ─────────────────────────────────────────────────────

function Invoke-FileScan {
    param([hashtable]$FileList)

    Write-LogEntry -Category 'INFO' -Message "Scanning file system..."

    $envMap = @{
        '{ProgramFiles}'        = $env:ProgramFiles
        '{ProgramFiles(x86)}'   = ${env:ProgramFiles(x86)}
        '{AppData}'             = $env:APPDATA
        '{LocalAppData}'        = $env:LOCALAPPDATA
        '{ProgramData}'         = $env:ProgramData
        '{CommonProgramFiles}'  = $env:CommonProgramFiles
        '{Windows}'             = $env:SystemRoot
        '{Temp}'                = $env:TEMP
    }

    # Scan folders
    foreach ($entry in $FileList.folders) {
        $expandedPath = $entry.path
        foreach ($key in $envMap.Keys) {
            if ($expandedPath -like "*$key*") {
                $expandedPath = $expandedPath.Replace($key, $envMap[$key])
            }
        }

        if ($expandedPath -and (Test-Path $expandedPath -PathType Container)) {
            Write-LogEntry -Category 'FOUND' -Message "Folder: $expandedPath" -Detail $entry.name
            $script:DetectedItems.Add(@{
                Type        = 'Folder'
                Name        = $entry.name
                Description = $entry.name
                Data        = $expandedPath
            })
        }
    }

    # Scan individual files
    foreach ($entry in $FileList.files) {
        $expandedPath = $entry.path
        foreach ($key in $envMap.Keys) {
            if ($expandedPath -like "*$key*") {
                $expandedPath = $expandedPath.Replace($key, $envMap[$key])
            }
        }

        if ($expandedPath -and (Test-Path $expandedPath -PathType Leaf)) {
            Write-LogEntry -Category 'FOUND' -Message "File: $expandedPath" -Detail $entry.name
            $script:DetectedItems.Add(@{
                Type        = 'File'
                Name        = $entry.name
                Description = $entry.name
                Data        = $expandedPath
            })
        }
    }

    # Scan startup folders
    $startupPaths = @(
        [System.Environment]::GetFolderPath('Startup'),
        [System.Environment]::GetFolderPath('CommonStartup')
    )
    foreach ($startupDir in $startupPaths) {
        if (-not (Test-Path $startupDir)) { continue }
        foreach ($pattern in $FileList.startup_folders) {
            $hits = Get-ChildItem -Path $startupDir -Filter $pattern.match_pattern -ErrorAction SilentlyContinue
            foreach ($hit in $hits) {
                Write-LogEntry -Category 'FOUND' -Message "Startup item: $($hit.FullName)" -Detail $pattern.name
                $script:DetectedItems.Add(@{
                    Type        = 'StartupFile'
                    Name        = $pattern.name
                    Description = $pattern.name
                    Data        = $hit.FullName
                })
            }
        }
    }
}

# ─── Browser Hijack Scanner ──────────────────────────────────────────────────

function Invoke-BrowserScan {
    param([hashtable]$BrowserData)

    Write-LogEntry -Category 'INFO' -Message "Scanning browsers for hijacks..."

    # Chrome/Chromium-based browsers
    $chromeProfiles = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data",
        "$env:LOCALAPPDATA\Chromium\User Data"
    )

    foreach ($profileBase in $chromeProfiles) {
        if (-not (Test-Path $profileBase)) { continue }

        $browserName = switch -Wildcard ($profileBase) {
            '*Chrome*'   { 'Google Chrome' }
            '*Edge*'     { 'Microsoft Edge' }
            '*Brave*'    { 'Brave Browser' }
            '*Chromium*' { 'Chromium' }
            default      { 'Unknown Browser' }
        }

        # Find all profiles (Default, Profile 1, Profile 2, etc.)
        $profileDirs = @('Default') + (Get-ChildItem -Path $profileBase -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'Profile *' } |
            Select-Object -ExpandProperty Name)

        foreach ($profileDir in $profileDirs) {
            $prefsPath = Join-Path $profileBase "$profileDir\Preferences"
            if (-not (Test-Path $prefsPath)) { continue }

            try {
                $prefs = Get-Content -Path $prefsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

                # Check homepage
                $homepage = $prefs.homepage
                $startupPages = $prefs.session.startup_urls
                $ntp = $prefs.browser.show_home_button

                $allUrls = @()
                if ($homepage) { $allUrls += $homepage }
                if ($startupPages) { $allUrls += $startupPages }

                foreach ($url in $allUrls) {
                    foreach ($hijacker in $BrowserData.homepage_hijackers) {
                        if ($url -like "*$hijacker*") {
                            Write-LogEntry -Category 'FOUND' -Message "$browserName hijacked homepage: $url" -Detail "Profile: $profileDir | Hijacker: $hijacker"
                            $script:DetectedItems.Add(@{
                                Type        = 'BrowserHijack'
                                Name        = "Homepage hijack ($hijacker)"
                                Description = "Browser: $browserName | Profile: $profileDir"
                                Data        = @{
                                    Browser   = $browserName
                                    Profile   = $profileDir
                                    PrefsPath = $prefsPath
                                    Url       = $url
                                    Hijacker  = $hijacker
                                }
                            })
                            break
                        }
                    }
                }

                # Check extensions
                $extPath = Join-Path $profileBase "$profileDir\Extensions"
                if (Test-Path $extPath) {
                    $installedExtIds = Get-ChildItem -Path $extPath -Directory -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty Name

                    foreach ($extEntry in $BrowserData.chrome_extension_ids) {
                        if ($installedExtIds -contains $extEntry.id) {
                            Write-LogEntry -Category 'FOUND' -Message "$browserName extension: $($extEntry.name) [$($extEntry.id)]" -Detail "Profile: $profileDir"
                            $script:DetectedItems.Add(@{
                                Type        = 'BrowserExtension'
                                Name        = $extEntry.name
                                Description = "Browser: $browserName | Profile: $profileDir"
                                Data        = @{
                                    Browser  = $browserName
                                    Profile  = $profileDir
                                    ExtPath  = Join-Path $extPath $extEntry.id
                                    ExtId    = $extEntry.id
                                }
                            })
                        }
                    }
                }

            } catch {
                Write-LogEntry -Category 'WARNING' -Message "Could not read $browserName preferences ($profileDir): $($_.Exception.Message)"
            }
        }
    }

    # Firefox
    $firefoxProfilesBase = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $firefoxProfilesBase) {
        $ffProfiles = Get-ChildItem -Path $firefoxProfilesBase -Directory -ErrorAction SilentlyContinue

        foreach ($ffProfile in $ffProfiles) {
            # Check search/home prefs via user.js or prefs.js
            $prefsJs = Join-Path $ffProfile.FullName 'prefs.js'
            if (Test-Path $prefsJs) {
                $prefsContent = Get-Content $prefsJs -ErrorAction SilentlyContinue
                $homePref = $prefsContent | Where-Object { $_ -like '*browser.startup.homepage*' }

                foreach ($pref in $homePref) {
                    foreach ($hijacker in $BrowserData.homepage_hijackers) {
                        if ($pref -like "*$hijacker*") {
                            Write-LogEntry -Category 'FOUND' -Message "Firefox hijacked homepage in profile: $($ffProfile.Name)" -Detail "Hijacker: $hijacker"
                            $script:DetectedItems.Add(@{
                                Type        = 'BrowserHijack'
                                Name        = "Firefox homepage hijack ($hijacker)"
                                Description = "Firefox profile: $($ffProfile.Name)"
                                Data        = @{
                                    Browser   = 'Firefox'
                                    Profile   = $ffProfile.FullName
                                    PrefsPath = $prefsJs
                                    Hijacker  = $hijacker
                                }
                            })
                            break
                        }
                    }
                }
            }

            # Check Firefox extensions
            $extDir = Join-Path $ffProfile.FullName 'extensions'
            if (Test-Path $extDir) {
                foreach ($extEntry in $BrowserData.firefox_extension_ids) {
                    $extXpi = Join-Path $extDir "$($extEntry.id).xpi"
                    $extFolder = Join-Path $extDir $extEntry.id
                    if ((Test-Path $extXpi) -or (Test-Path $extFolder)) {
                        Write-LogEntry -Category 'FOUND' -Message "Firefox extension: $($extEntry.name) [$($extEntry.id)]" -Detail "Profile: $($ffProfile.Name)"
                        $script:DetectedItems.Add(@{
                            Type        = 'BrowserExtension'
                            Name        = $extEntry.name
                            Description = "Firefox | Profile: $($ffProfile.Name)"
                            Data        = @{
                                Browser  = 'Firefox'
                                Profile  = $ffProfile.FullName
                                ExtId    = $extEntry.id
                                ExtPath  = if (Test-Path $extXpi) { $extXpi } else { $extFolder }
                            }
                        })
                    }
                }
            }
        }
    }

    # Internet Explorer / Legacy Edge BHOs (registry-based)
    $bhoPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects'
    if (Test-Path $bhoPath) {
        $installedBhos = Get-ChildItem -Path $bhoPath -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty PSChildName

        foreach ($bhoEntry in $BrowserData.ie_bho_clsids) {
            if ($installedBhos -contains $bhoEntry.clsid) {
                Write-LogEntry -Category 'FOUND' -Message "IE/Edge BHO: $($bhoEntry.name) [$($bhoEntry.clsid)]"
                $script:DetectedItems.Add(@{
                    Type        = 'IEBho'
                    Name        = $bhoEntry.name
                    Description = "Internet Explorer BHO"
                    Data        = "$bhoPath\$($bhoEntry.clsid)"
                })
            }
        }
    }
}

# ─── Browser Group Policy Scanner ───────────────────────────────────────────

function Invoke-PolicyScan {
    param([PSCustomObject]$PolicyData)

    if ($null -eq $PolicyData) { return }

    Write-LogEntry -Category 'INFO' -Message "Scanning browser group policies for hijacks..."

    $knownBadIds = $PolicyData.known_malicious_force_install_ids

    # Check force-install extension keys for known-bad extension IDs
    foreach ($keyEntry in $PolicyData.force_install_extension_keys) {
        if (-not (Test-Path $keyEntry.path)) { continue }

        try {
            $values = Get-ItemProperty -Path $keyEntry.path -ErrorAction Stop
            foreach ($prop in $values.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }) {
                $extValue = $prop.Value
                # Force-install values are like "extid;update_url"
                $extId = ($extValue -split ';')[0].Trim()
                if ($knownBadIds -contains $extId) {
                    Write-LogEntry -Category 'FOUND' -Message "Policy force-install of known-bad extension: $extId" -Detail "$($keyEntry.path)\$($prop.Name)"
                    $script:DetectedItems.Add(@{
                        Type        = 'PolicyExtension'
                        Name        = "Force-installed extension: $extId"
                        Description = $keyEntry.description
                        Data        = @{
                            RegPath    = $keyEntry.path
                            ValueName  = $prop.Name
                            ExtId      = $extId
                        }
                    })
                }
            }
        } catch {
            Write-LogEntry -Category 'WARNING' -Message "Could not read policy key $($keyEntry.path): $($_.Exception.Message)"
        }
    }

    # Check homepage/search override policy values
    foreach ($policyEntry in $PolicyData.suspicious_policy_values) {
        if (-not (Test-Path $policyEntry.path)) { continue }

        try {
            $val = Get-ItemProperty -Path $policyEntry.path -Name $policyEntry.value -ErrorAction SilentlyContinue
            if ($null -ne $val) {
                $valData = $val.($policyEntry.value)
                Write-LogEntry -Category 'FOUND' -Message "Browser policy override: $($policyEntry.name) = $valData" -Detail $policyEntry.description
                $script:DetectedItems.Add(@{
                    Type        = 'PolicyOverride'
                    Name        = $policyEntry.name
                    Description = $policyEntry.description
                    Data        = @{
                        RegPath   = $policyEntry.path
                        ValueName = $policyEntry.value
                        Value     = $valData
                    }
                })
            }
        } catch {
            Write-LogEntry -Category 'WARNING' -Message "Could not check policy value $($policyEntry.path)\$($policyEntry.value): $($_.Exception.Message)"
        }
    }
}
