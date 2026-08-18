<#
.SYNOPSIS
Logitech / Astro Auto-Audio Switcher (Event-Driven)

.LICENSE
Copyright (c) 2026 xAle33x

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

# --- PREREQUISITI: Verifica e installazione modulo audio ---
if (-not (Get-Module -ListAvailable -Name AudioDeviceCmdlets)) {
    Write-Host "[!] 'AudioDeviceCmdlets' module missing. Installing for current user..." -ForegroundColor Yellow
    Install-Module -Name AudioDeviceCmdlets -Scope CurrentUser -Force -AllowClobber
}
Import-Module AudioDeviceCmdlets -ErrorAction SilentlyContinue

# --- CONFIGURAZIONE UTENTE / USER CONFIGURATION ---
# [PLAYBACK / AUDIO OUTPUT]
$global:SpeakerName = "YOUR_SPEAKER_NAME"      # (e.g. "Realtek", "Creative", "Soundbar")
$global:HeadsetName = "A50 Game"               # (e.g. "A50 Game", "PRO X Wireless")

# [RECORDING / MICROPHONE INPUT] - OPTIONAL
$global:SwitchMicrophone = $false              # Set to $true if you want to switch mics too
$global:ExternalMicName  = "YOUR_MIC_NAME"     # (e.g. "Blue Yeti", "QuadCast")
$global:HeadsetMicName   = "A50 Mic"         # (e.g. "A50 Mic", "PRO X Wireless")

# [SYSTEM]
$global:BatteryKey  = "battery/a50/percentage" # Change this if you don't have an Astro A50.
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

# Modificata per filtrare tra Playback e Recording
function global:Get-DeviceIdByName {
    param($SearchName, $Type)
    $Device = Get-AudioDevice -List | Where-Object { $_.Name -like "*$SearchName*" -and $_.Type -like "*$Type*" } | Select-Object -First 1
    if ($null -eq $Device) {
        Write-Host "[!] ERROR: Cannot find $Type device containing name: $SearchName" -ForegroundColor Red
        return $null
    }
    return $Device.ID
}

# Risoluzione ID Riproduzione
$global:SpeakerID = Get-DeviceIdByName $global:SpeakerName "Playback"
$global:HeadsetID = Get-DeviceIdByName $global:HeadsetName "Playback"

# Risoluzione ID Registrazione (se attivato)
if ($global:SwitchMicrophone) {
    $global:ExternalMicID = Get-DeviceIdByName $global:ExternalMicName "Recording"
    $global:HeadsetMicID  = Get-DeviceIdByName $global:HeadsetMicName "Recording"
    
    # Se fallisce la ricerca dei microfoni, disattiva lo switch per evitare errori
    if ($null -eq $global:ExternalMicID -or $null -eq $global:HeadsetMicID) {
        Write-Host "[-] Microphone Switch disabled due to missing devices." -ForegroundColor Yellow
        $global:SwitchMicrophone = $false
    }
}

$global:LastKnownState = $null

if ($null -eq $global:SpeakerID -or $null -eq $global:HeadsetID) {
    Write-Host "[-] Could not resolve Audio hardware IDs. Please check your playback device names." -ForegroundColor Red
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
            
            if ($Fragment -match $RegexPattern) {
                $DeviceBlock = $Matches[1]
                $IsCharging = $DeviceBlock -match '"isCharging"\s*:\s*true'

                if ($IsCharging -ne $global:LastKnownState) {
                    $Time = Get-Date -Format "HH:mm:ss"
                    
                    # Ottieni stati attuali (per evitare switch inutili)
                    $CurrentAudio = Get-AudioDevice -Playback
                    $CurrentMic = if ($global:SwitchMicrophone) { Get-AudioDevice -Recording } else { $null }
                    
                    try {
                        if ($IsCharging) {
                            # AUDIO DOCKED -> SPEAKERS
                            if ($CurrentAudio.ID -ne $global:SpeakerID) {
                                Set-AudioDevice -ID $global:SpeakerID | Out-Null
                                Write-Host "[$Time] >>> DOCKED: Audio switched to $($global:SpeakerName)" -ForegroundColor Yellow
                            }
                            # MIC DOCKED -> EXTERNAL MIC
                            if ($global:SwitchMicrophone -and $CurrentMic.ID -ne $global:ExternalMicID) {
                                Set-AudioDevice -ID $global:ExternalMicID | Out-Null
                                Write-Host "[$Time] >>> DOCKED: Mic switched to $($global:ExternalMicName)" -ForegroundColor Yellow
                            }
                        } else {
                            # AUDIO UNDOCKED -> HEADSET
                            if ($CurrentAudio.ID -ne $global:HeadsetID) {
                                Set-AudioDevice -ID $global:HeadsetID | Out-Null
                                Write-Host "[$Time] >>> UNDOCKED: Audio switched to $($global:HeadsetName)" -ForegroundColor Green
                            }
                            # MIC UNDOCKED -> HEADSET MIC
                            if ($global:SwitchMicrophone -and $CurrentMic.ID -ne $global:HeadsetMicID) {
                                Set-AudioDevice -ID $global:HeadsetMicID | Out-Null
                                Write-Host "[$Time] >>> UNDOCKED: Mic switched to $($global:HeadsetMicName)" -ForegroundColor Green
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
if ($global:SwitchMicrophone) { Write-Host "[-] Dual-Switch Enabled: Managing both Playback and Recording devices." -ForegroundColor Cyan }
Write-Host "[-] Listening for docking events... CPU usage is 0%." -ForegroundColor DarkGray
Write-Host "[-] Press CTRL+C to stop." -ForegroundColor DarkGray

while ($true) {
    Wait-Event -Timeout 10
}
