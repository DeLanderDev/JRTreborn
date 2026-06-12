# RestorePoint.ps1 - Create a system restore point before any removal

function New-SafetyRestorePoint {
    param([string]$Description = 'JRTreborn Pre-Scan Restore Point')

    Write-LogEntry -Category 'INFO' -Message "Creating system restore point..."

    try {
        # Ensure System Restore is enabled on the system drive
        $sysDrive = $env:SystemDrive
        $restoreEnabled = $true

        try {
            $srStatus = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -ErrorAction SilentlyContinue
            if ($srStatus -and $srStatus.RPSessionInterval -eq 0) {
                Enable-ComputerRestore -Drive "$sysDrive\" -ErrorAction SilentlyContinue
            }
        } catch {
            $restoreEnabled = $false
        }

        if (-not $restoreEnabled) {
            Write-LogEntry -Category 'WARNING' -Message "Could not verify System Restore status. Attempting to create restore point anyway."
        }

        # Disable the 24-hour restore point frequency limit temporarily
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $originalThrottle = $null
        try {
            $originalThrottle = (Get-ItemProperty -Path $regPath -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
            Set-ItemProperty -Path $regPath -Name 'SystemRestorePointCreationFrequency' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        } catch { }

        # Create the restore point
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop

        # Restore original throttle value
        try {
            if ($null -ne $originalThrottle) {
                Set-ItemProperty -Path $regPath -Name 'SystemRestorePointCreationFrequency' -Value $originalThrottle -Type DWord -Force -ErrorAction SilentlyContinue
            } else {
                Remove-ItemProperty -Path $regPath -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue
            }
        } catch { }

        Write-LogEntry -Category 'INFO' -Message "System restore point created successfully: '$Description'"
        return $true

    } catch {
        Write-LogEntry -Category 'WARNING' -Message "Failed to create system restore point: $($_.Exception.Message)"
        Write-LogEntry -Category 'WARNING' -Message "Continuing without restore point. You can create one manually before proceeding."
        return $false
    }
}

function Test-RestorePointAvailable {
    try {
        $null = Get-ComputerRestorePoint -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}
