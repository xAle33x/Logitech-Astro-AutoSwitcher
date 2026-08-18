<#
.SYNOPSIS
Logitech / Astro Auto-Audio Switcher (Event-Driven)

.LICENSE
Copyright (c) 2026 xAle33x (Bojo)

PERSONAL USE NON-COMMERCIAL LICENSE
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to use, copy, modify, and merge the Software, strictly for personal, non-commercial purposes, subject to the following conditions:

1. COMMERCIAL USE IS STRICTLY PROHIBITED. You may not use, publish, distribute, sublicense, and/or sell copies of the Software, nor use the Software to provide commercial services, without the express prior written permission of the author.
2. If you wish to use this Software for any commercial purpose, you must contact the author to negotiate a separate commercial license.
3. The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
#>

# =========================================================
# Logitech/Astro Auto-Audio Switcher (Event-Driven)
# =========================================================

# --- PREREQUISITES: Audio module verification and installation ---
if (-not (Get-Module -ListAvailable -Name AudioDeviceCmdlets)) {
    Write-Host "[!] 'AudioDeviceCmdlets' module missing. Installing for current user..." -ForegroundColor Yellow
    Install-Module -Name AudioDeviceCmdlets -Scope CurrentUser -Force -AllowClobber
}
Import-Module AudioDeviceCmdlets -ErrorAction SilentlyContinue

# --- USER CONFIGURATION ---
$global:SpeakerName = "YOUR_SPEAKER_NAME"      # (e.g. "Realtek", "Creative", "Soundbar")
$global:HeadsetName = "A50 Game"               # (e.g. "A50 Game", "PRO X Wireless")
$global:BatteryKey  = "battery/a50/percentage" # Change this if you don't have an Astro A50. See README for instructions.
# --------------------------------------------------

$global:GhubDir = "$env:LocalAppData\LGHUB"
$global:DbFile  = "settings.db"
$global:WalFile = "settings.db-wal"

function global:Get-GhubLiveState {
    param($Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        $file = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = New-Object System.IO.BinaryReader($file)
        $bytes = $reader.ReadBytes($file.Length)
        $reader.Close(); $file.Close()
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch { return $null }
}

function global:Get-DeviceIdByName {
    param($SearchName)
    $Device = Get-AudioDevice -List | Where-Object { $_.Name -like "*$SearchName*" } | Select-Object -First 1
    if ($null -eq $Device) {
        Write-Host "[!] ERROR: Cannot find audio device containing name: $SearchName" -ForegroundColor Red
        return $null
    }
    return $Device.ID
}

$global:SpeakerID = Get-DeviceIdByName $global:SpeakerName
$global:HeadsetID = Get-DeviceIdByName $global:HeadsetName
$global:LastKnownState = $null

if ($null -eq $global:SpeakerID -or $null -eq $global:HeadsetID) {
    Write-Host "[-] Could not resolve hardware IDs. Please check your device names." -ForegroundColor Red
    Exit
}

# --- EVENT ENGINE ---
$Action = {
    $RawData = Get-GhubLiveState (Join-Path $global:GhubDir $global:WalFile)
    
    if ($null -eq $RawData -or $RawData -notmatch [regex]::Escape($global:BatteryKey)) {
        $RawData = Get-GhubLiveState (Join-Path $global:GhubDir $global:DbFile)
    }

    if ($null -ne $RawData) {
        $SearchString = '"' + $global:BatteryKey + '"'
        $KeyIndex = $RawData.LastIndexOf($SearchString)
        
        if ($KeyIndex -gt -1) {
            $Fragment = $RawData.Substring($KeyIndex, [Math]::Min(300, $RawData.Length - $KeyIndex))
            $RegexPattern = '(?s)' + [regex]::Escape($SearchString) + '[^\{]*\{(.*?)\}'
            
            # Isolate JSON block to prevent conflicts (e.g., charging a G502 mouse)
            if ($Fragment -match $RegexPattern) {
                $DeviceBlock = $Matches[1]
                $IsCharging = $DeviceBlock -match '"isCharging"\s*:\s*true'

                if ($IsCharging -ne $global:LastKnownState) {
                    $Time = Get-Date -Format "HH:mm:ss"
                    $CurrentAudio = Get-AudioDevice -Playback
                    
                    try {
                        if ($IsCharging) {
                            if ($CurrentAudio.ID -ne $global:SpeakerID) {
                                Set-AudioDevice -ID $global:SpeakerID | Out-Null
                                Write-Host "[$Time] >>> HEADSET DOCKED: Switching to $($global:SpeakerName)" -ForegroundColor Yellow
                            }
                        } else {
                            if ($CurrentAudio.ID -ne $global:HeadsetID) {
                                Set-AudioDevice -ID $global:HeadsetID | Out-Null
                                Write-Host "[$Time] >>> HEADSET UNDOCKED: Switching to $($global:HeadsetName)" -ForegroundColor Green
                            }
                        }
                        $global:LastKnownState = $IsCharging
                    } catch {
                        Write-Host "[!] Switch error: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }
        }
    }
}

Unregister-Event -SourceIdentifier "GhubDbWatcher" -ErrorAction SilentlyContinue

$Watcher = New-Object System.IO.FileSystemWatcher
$Watcher.Path = $global:GhubDir
$Watcher.Filter = "settings.db*" 
$Watcher.IncludeSubdirectories = $false
$Watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size

Register-ObjectEvent -InputObject $Watcher -EventName "Changed" -SourceIdentifier "GhubDbWatcher" -Action $Action | Out-Null

Write-Host "[!] Logitech Auto-Switcher (Event-Driven) Started." -ForegroundColor Cyan
Write-Host "[-] Listening for docking events... CPU usage is 0%." -ForegroundColor DarkGray
Write-Host "[-] Press CTRL+C to stop." -ForegroundColor DarkGray

while ($true) {
    Wait-Event -Timeout 10
}
