<#
.SYNOPSIS
Logitech / Astro A50 Auto-Audio Switcher - v2

Automatically switches the Windows default playback (and optionally recording) device
when the Astro A50 headset is placed on or removed from its base station.

.DESCRIPTION
DETECTION LOGIC (verified against G HUB, September 2026 build):
 - The "battery/<device>/percentage" block contains "isCharging": true ONLY while the
   headset is docked on the base. When the headset is removed, the field is simply ABSENT
   ("false" is never written).
   => field present = DOCKED ; field absent = UNDOCKED
 - settings.db-wal holds historical SQLite pages, so byte offsets are NOT in chronological
   order. All occurrences are collected from both settings.db and settings.db-wal, and the
   one with the most recent "time" field wins.

FIRST RUN:
 On first launch the script starts an interactive setup wizard: it lists your playback and
 recording devices, lists the battery keys G HUB exposes, and saves your choices to
 a JSON file next to the script. No manual editing of the source is required.
 Re-run with -Setup at any time to reconfigure.

CHANGES IN v2 (vs v1):
 - NEW: interactive first-run wizard (-Setup) with numbered device pickers.
 - NEW: configuration stored in an external JSON file; the script itself is never modified.
 - NEW: battery key auto-discovery from settings.db (supports non-A50 wireless devices).
 - NEW: -ListDevices helper.
 - Devices are stored by full name and matched exactly first, then by substring, so two
   endpoints of the same headset ("Voice" / "Game") can no longer be confused.
 - FIX: [DateTime]::TryParse with [ref] on an untyped variable fails on Windows
   PowerShell 5.1 (MethodCountCouldNotFindBest). Replaced with a dedicated parser.
 - FIX: G HUB writes "time" in TWO formats (ISO 8601 and Unix epoch). Both are now handled.
 - FIX: culture-invariant parsing (ISO parsing could misbehave on non-English locales).
 - FIX: $Matches was clobbered by a subsequent -match inside the same loop iteration.
 - FIX: deterministic tie-break when several blocks share the same timestamp.
 - NEW: -DebugState switch to inspect what is being read without changing any audio device.

.PARAMETER Setup
Force the interactive configuration wizard, overwriting any existing configuration.

.PARAMETER DebugState
Print every battery block found, the winning one and the resulting state, then exit
without registering any watcher or changing the default audio devices.

.PARAMETER ListDevices
Print all playback and recording devices as Windows reports them, then exit.

.PARAMETER ConfigPath
Override the location of the configuration file.
Defaults to 'A50-AutoSwitch.config.json' next to the script.

.NOTES
Requires the AudioDeviceCmdlets module (installed automatically for the current user).
Tested on Windows PowerShell 5.1 and PowerShell 7.

TIP: power on your headset and take it OFF the base before running the wizard, so that
every endpoint is visible to Windows and can be picked from the list.

.EXAMPLE
    .\Astro-A50-AutoSwitch-v5.ps1
    First run: starts the setup wizard, then starts the switcher.

.EXAMPLE
    .\Astro-A50-AutoSwitch-v5.ps1 -Setup
    Reconfigure devices from scratch.

.EXAMPLE
    .\Astro-A50-AutoSwitch-v5.ps1 -DebugState
    Dock and undock the headset, re-running each time, to confirm detection works.

.LICENSE
Copyright (c) 2026 xAle33x - PERSONAL USE NON-COMMERCIAL LICENSE
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to use, copy, modify, and merge the Software, strictly for personal,
non-commercial purposes, subject to the following conditions:
1. COMMERCIAL USE IS STRICTLY PROHIBITED.
2. For any commercial purpose you must contact the author to negotiate a separate commercial license.
3. The above copyright notice and this permission notice shall be included in all copies.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
#>

[CmdletBinding()]
param(
    [switch]$Setup,
    [switch]$DebugState,
    [switch]$ListDevices,
    [string]$ConfigPath
)

# ---------------------------------------------------------------- prerequisites
if (-not (Get-Module -ListAvailable -Name AudioDeviceCmdlets)) {
    Write-Host "[!] Module 'AudioDeviceCmdlets' not found. Installing for current user..." -ForegroundColor Yellow
    try {
        Install-Module -Name AudioDeviceCmdlets -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    } catch {
        Write-Host "[-] Installation failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    Install it manually, then run this script again." -ForegroundColor DarkGray
        Exit 1
    }
}
Import-Module AudioDeviceCmdlets -ErrorAction SilentlyContinue

$global:GhubDir = "$env:LocalAppData\LGHUB"
if (-not (Test-Path $global:GhubDir)) {
    Write-Host "[-] LGHUB folder not found. Is G HUB installed?" -ForegroundColor Red
    Exit 1
}

if (-not $ConfigPath) {
    $root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $ConfigPath = Join-Path $root "A50-AutoSwitch.config.json"
}

$global:LastStamp      = $null
$global:LastKnownState = $null
$global:LastEval       = [DateTime]::MinValue

# ---------------------------------------------------------------- G HUB reading
function global:Read-RawFile {
    param($Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        # ReadWrite sharing is required: G HUB keeps these files open.
        $f = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $r = New-Object System.IO.BinaryReader($f)
        $b = $r.ReadBytes($f.Length); $r.Close(); $f.Close()
        return [System.Text.Encoding]::UTF8.GetString($b)
    } catch { return $null }
}

# Extracts the brace-balanced JSON object that follows a given position.
function global:Get-JsonBlock {
    param($Raw, $From)
    $open = $Raw.IndexOf('{', $From)
    if ($open -lt 0) { return $null }
    $depth = 0
    $max = [Math]::Min($Raw.Length, $open + 2000)
    for ($i = $open; $i -lt $max; $i++) {
        if ($Raw[$i] -eq '{') { $depth++ }
        elseif ($Raw[$i] -eq '}') { $depth--; if ($depth -eq 0) { return $Raw.Substring($open, $i-$open+1) } }
    }
    return $null
}

<# Converts G HUB timestamps: ISO 8601 ("2026-09-19T13:03:48Z") or Unix epoch in
   seconds or milliseconds ("1789807057"). Returns UTC DateTime, or $null.
   Replaces [DateTime]::TryParse, which on PS 5.1 rejects [ref] on an untyped
   variable and would fail on epoch values anyway. #>
function global:Convert-GhubTime {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    if ($Value -match '^\d{9,13}$') {
        $n = [int64]$Value
        if ($n -gt 99999999999) { $n = [math]::Floor($n / 1000) }   # milliseconds
        try { return [DateTimeOffset]::FromUnixTimeSeconds($n).UtcDateTime } catch { return $null }
    }
    try {
        return [datetime]::Parse(
            $Value,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal
        )
    } catch { return $null }
}

# Lists every "battery/<device>/percentage" key G HUB currently exposes.
function global:Get-AvailableBatteryKeys {
    $keys = @()
    foreach ($n in @("settings.db", "settings.db-wal")) {
        $raw = Read-RawFile (Join-Path $global:GhubDir $n)
        if (-not $raw) { continue }
        $keys += [regex]::Matches($raw, '"(battery/[^"]+/percentage)"') | ForEach-Object { $_.Groups[1].Value }
    }
    return ($keys | Select-Object -Unique | Sort-Object)
}

<# Collects every occurrence of the battery key from settings.db and settings.db-wal.
   Returns objects shaped as {File, Rank, Offset, Time, IsCharging, Block}. #>
function global:Get-BatterySamples {
    param([string]$Key = $global:BatteryKey)
    $samples = @()
    $rank = 0
    foreach ($n in @("settings.db", "settings.db-wal")) {
        $rank++
        $raw = Read-RawFile (Join-Path $global:GhubDir $n)
        if (-not $raw) { continue }
        foreach ($m in [regex]::Matches($raw, '"' + [regex]::Escape($Key) + '"')) {
            $block = Get-JsonBlock $raw $m.Index
            if (-not $block) { continue }

            # Capture into locals immediately: any later -match resets the automatic $Matches.
            $timeMatch = [regex]::Match($block, '"time"\s*:\s*"?([^",}]+)"?')
            if (-not $timeMatch.Success) { continue }
            $ts = Convert-GhubTime $timeMatch.Groups[1].Value
            if ($null -eq $ts) { continue }

            $samples += [PSCustomObject]@{
                File       = $n
                Rank       = $rank
                Offset     = $m.Index
                Time       = $ts
                IsCharging = [bool]([regex]::IsMatch($block, '"isCharging"\s*:\s*true'))
                Block      = ($block -replace '\s+', ' ')
            }
        }
    }
    return $samples
}

<# Returns $true (docked) / $false (undocked) / $null (undetermined).
   Sorted by Time, then Rank (WAL beats DB), then Offset (latest written page). #>
function global:Get-ChargingState {
    $samples = Get-BatterySamples
    if (-not $samples -or $samples.Count -eq 0) { $global:LastStamp = $null; return $null }
    $winner = $samples | Sort-Object Time, Rank, Offset | Select-Object -Last 1
    $global:LastStamp = $winner.Time
    return $winner.IsCharging
}

# ---------------------------------------------------------------- audio helpers
# Resolved at switch time on purpose: wireless endpoints disappear when powered off.
# Exact name first, substring as fallback, so "A50 Voice" never matches "A50 Game".
function global:Get-DeviceIdByName {
    param($SearchName, $Type)
    if ([string]::IsNullOrWhiteSpace($SearchName)) { return $null }
    $all = Get-AudioDevice -List | Where-Object { $_.Type -like "*$Type*" }
    $d = $all | Where-Object { $_.Name -eq $SearchName } | Select-Object -First 1
    if ($null -eq $d) { $d = $all | Where-Object { $_.Name -like "*$SearchName*" } | Select-Object -First 1 }
    if ($null -eq $d) { return $null }
    return $d.ID
}

function global:Switch-To {
    param($PlaybackName, $MicName, $Label, $Color)
    $t = Get-Date -Format "HH:mm:ss"
    try {
        $p = Get-DeviceIdByName $PlaybackName "Playback"
        if ($null -eq $p) { Write-Host "[$t] [!] Playback device '$PlaybackName' not available." -ForegroundColor Red }
        elseif ((Get-AudioDevice -Playback).ID -ne $p) {
            Set-AudioDevice -ID $p | Out-Null
            Write-Host "[$t] >>> ${Label}: playback -> $PlaybackName" -ForegroundColor $Color
        }
        if ($global:SwitchMicrophone -and $MicName) {
            $m = Get-DeviceIdByName $MicName "Recording"
            if ($null -eq $m) { Write-Host "[$t] [!] Recording device '$MicName' not available." -ForegroundColor Red }
            elseif ((Get-AudioDevice -Recording).ID -ne $m) {
                Set-AudioDevice -ID $m | Out-Null
                Write-Host "[$t] >>> ${Label}: microphone -> $MicName" -ForegroundColor $Color
            }
        }
    } catch { Write-Host "[$t] [!] Error: $($_.Exception.Message)" -ForegroundColor Red }
}

function global:Evaluate-State {
    # Debounce: G HUB writes to the WAL in bursts.
    if (((Get-Date) - $global:LastEval).TotalMilliseconds -lt 700) { return }
    $global:LastEval = Get-Date
    $docked = Get-ChargingState
    if ($null -eq $docked) { return }
    if ($docked -eq $global:LastKnownState) { return }
    if ($docked) { Switch-To $global:SpeakerName $global:ExternalMicName "DOCKED"   "Yellow" }
    else         { Switch-To $global:HeadsetName $global:HeadsetMicName "UNDOCKED" "Green"  }
    $global:LastKnownState = $docked
}

# ---------------------------------------------------------------- setup wizard
function Show-DeviceTable {
    param([string]$Type)
    $devs = @(Get-AudioDevice -List | Where-Object { $_.Type -like "*$Type*" })
    for ($i = 0; $i -lt $devs.Count; $i++) {
        $flag = if ($devs[$i].Default) { " (current default)" } else { "" }
        Write-Host ("  [{0,2}] {1}{2}" -f ($i+1), $devs[$i].Name, $flag) -ForegroundColor Gray
    }
    return $devs
}

function Select-AudioDeviceInteractive {
    param([string]$Type, [string]$Prompt)
    Write-Host ""
    Write-Host $Prompt -ForegroundColor Cyan
    $devs = Show-DeviceTable -Type $Type
    if ($devs.Count -eq 0) {
        Write-Host "  [!] No $Type devices found." -ForegroundColor Red
        return $null
    }
    Write-Host "  [ m] type a name fragment manually (use this if the device is currently off)" -ForegroundColor DarkGray
    while ($true) {
        $ans = Read-Host "Selection"
        if ($ans -eq 'm') {
            $manual = Read-Host "Name fragment"
            if (-not [string]::IsNullOrWhiteSpace($manual)) { return $manual.Trim() }
            continue
        }
        $n = 0
        if ([int]::TryParse($ans, [ref]$n) -and $n -ge 1 -and $n -le $devs.Count) {
            return $devs[$n-1].Name
        }
        Write-Host "  Invalid selection, try again." -ForegroundColor Red
    }
}

function Select-BatteryKeyInteractive {
    Write-Host ""
    Write-Host "Which G HUB device should be monitored for charge state?" -ForegroundColor Cyan
    $keys = @(Get-AvailableBatteryKeys)
    if ($keys.Count -eq 0) {
        Write-Host "  [!] No battery keys found in settings.db." -ForegroundColor Red
        Write-Host "      Make sure G HUB is running and the headset is powered on." -ForegroundColor DarkGray
        $manual = Read-Host "Enter the key manually [battery/a50/percentage]"
        if ([string]::IsNullOrWhiteSpace($manual)) { return "battery/a50/percentage" }
        return $manual.Trim()
    }
    for ($i = 0; $i -lt $keys.Count; $i++) {
        Write-Host ("  [{0,2}] {1}" -f ($i+1), $keys[$i]) -ForegroundColor Gray
    }
    while ($true) {
        $ans = Read-Host "Selection"
        $n = 0
        if ([int]::TryParse($ans, [ref]$n) -and $n -ge 1 -and $n -le $keys.Count) { return $keys[$n-1] }
        Write-Host "  Invalid selection, try again." -ForegroundColor Red
    }
}

function Invoke-SetupWizard {
    param([string]$Path)

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "   A50 Auto-Switcher - configuration wizard" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "TIP: power on your headset and take it OFF the base first," -ForegroundColor DarkGray
    Write-Host "     so every endpoint is visible in the lists below." -ForegroundColor DarkGray

    $speaker = Select-AudioDeviceInteractive -Type "Playback" `
        -Prompt "1/5 - Playback device to use while the headset is DOCKED (e.g. desktop speakers):"

    $headset = Select-AudioDeviceInteractive -Type "Playback" `
        -Prompt "2/5 - Playback device to use while the headset is UNDOCKED (the headset itself):"

    Write-Host ""
    $micAns = Read-Host "3/5 - Switch the microphone as well? [Y/n]"
    $switchMic = -not ($micAns -match '^(n|no)$')

    $extMic = $null; $hsMic = $null
    if ($switchMic) {
        $extMic = Select-AudioDeviceInteractive -Type "Recording" `
            -Prompt "4/5 - Recording device to use while the headset is DOCKED:"
        $hsMic  = Select-AudioDeviceInteractive -Type "Recording" `
            -Prompt "5/5 - Recording device to use while the headset is UNDOCKED (headset mic):"
    } else {
        Write-Host "  Skipping microphone configuration." -ForegroundColor DarkGray
    }

    $batteryKey = Select-BatteryKeyInteractive

    $cfg = [ordered]@{
        Version          = 5
        Created          = (Get-Date).ToString('o')
        SpeakerName      = $speaker
        HeadsetName      = $headset
        SwitchMicrophone = $switchMic
        ExternalMicName  = $extMic
        HeadsetMicName   = $hsMic
        BatteryKey       = $batteryKey
        PollSeconds      = 3
    }

    Write-Host ""
    Write-Host "--- Summary ---" -ForegroundColor Cyan
    Write-Host ("  DOCKED   -> playback : {0}" -f $speaker) -ForegroundColor Yellow
    Write-Host ("  UNDOCKED -> playback : {0}" -f $headset) -ForegroundColor Green
    if ($switchMic) {
        Write-Host ("  DOCKED   -> mic      : {0}" -f $extMic) -ForegroundColor Yellow
        Write-Host ("  UNDOCKED -> mic      : {0}" -f $hsMic) -ForegroundColor Green
    } else {
        Write-Host "  Microphone switching : disabled" -ForegroundColor DarkGray
    }
    Write-Host ("  G HUB key            : {0}" -f $batteryKey) -ForegroundColor Gray
    Write-Host ""

    $confirm = Read-Host "Save this configuration? [Y/n]"
    if ($confirm -match '^(n|no)$') {
        Write-Host "[-] Aborted. Nothing was saved." -ForegroundColor Red
        Exit 0
    }

    try {
        $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8 -ErrorAction Stop
        Write-Host "[+] Configuration saved to: $Path" -ForegroundColor Green
        Write-Host "    Run with -Setup to change it later." -ForegroundColor DarkGray
    } catch {
        Write-Host "[-] Could not write the configuration file: $($_.Exception.Message)" -ForegroundColor Red
        Exit 1
    }
    return $cfg
}

function Import-Configuration {
    param([string]$Path)
    try {
        return (Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        Write-Host "[-] Configuration file is unreadable or corrupted: $Path" -ForegroundColor Red
        Write-Host "    Delete it or run with -Setup to rebuild it." -ForegroundColor DarkGray
        Exit 1
    }
}

# ---------------------------------------------------------------- entry points
if ($ListDevices) {
    Write-Host "`n=== PLAYBACK ===" -ForegroundColor Cyan
    Get-AudioDevice -List | Where-Object { $_.Type -like "*Playback*" }  | Select-Object Index, Default, Name | Format-Table -AutoSize
    Write-Host "=== RECORDING ===" -ForegroundColor Cyan
    Get-AudioDevice -List | Where-Object { $_.Type -like "*Recording*" } | Select-Object Index, Default, Name | Format-Table -AutoSize
    return
}

if ($Setup -or -not (Test-Path $ConfigPath)) {
    if (-not $Setup) { Write-Host "[i] No configuration found - starting first-run setup." -ForegroundColor Yellow }
    $cfg = Invoke-SetupWizard -Path $ConfigPath
} else {
    $cfg = Import-Configuration -Path $ConfigPath
}

# Promote configuration into the globals used by the worker functions.
$global:SpeakerName      = $cfg.SpeakerName
$global:HeadsetName      = $cfg.HeadsetName
$global:SwitchMicrophone = [bool]$cfg.SwitchMicrophone
$global:ExternalMicName  = $cfg.ExternalMicName
$global:HeadsetMicName   = $cfg.HeadsetMicName
$global:BatteryKey       = $cfg.BatteryKey
$global:PollSeconds      = if ($cfg.PollSeconds) { [int]$cfg.PollSeconds } else { 3 }

if ([string]::IsNullOrWhiteSpace($global:SpeakerName) -or [string]::IsNullOrWhiteSpace($global:HeadsetName)) {
    Write-Host "[-] Configuration is incomplete. Run with -Setup to rebuild it." -ForegroundColor Red
    Exit 1
}

# --- Debug mode: dump everything and exit ---
if ($DebugState) {
    Write-Host "`n=== SAMPLES FOUND FOR '$global:BatteryKey' ===" -ForegroundColor Cyan
    $s = Get-BatterySamples
    if (-not $s -or $s.Count -eq 0) {
        Write-Host "[!] No valid block found." -ForegroundColor Red
    } else {
        $s | Sort-Object Time, Rank, Offset |
            Format-Table @{L='File';E={$_.File}}, @{L='Offset';E={$_.Offset}},
                         @{L='Time (UTC)';E={$_.Time.ToString('yyyy-MM-dd HH:mm:ss')}},
                         @{L='Charging';E={$_.IsCharging}} -AutoSize
        $w = $s | Sort-Object Time, Rank, Offset | Select-Object -Last 1
        Write-Host "WINNER : $($w.File) @ $($w.Offset) | $($w.Time.ToString('u'))" -ForegroundColor Yellow
        Write-Host "BLOCK  : $($w.Block)" -ForegroundColor DarkGray
        Write-Host "STATE  : $(if ($w.IsCharging) {'DOCKED (charging)'} else {'UNDOCKED (in use)'})" -ForegroundColor Green
    }
    return
}

# --- Startup self-test ---
$init = Get-ChargingState
$stampTxt = if ($global:LastStamp) { $global:LastStamp.ToString('yyyy-MM-dd HH:mm:ss') + ' UTC' } else { 'n/a' }
Write-Host "[-] Config: $ConfigPath" -ForegroundColor DarkGray
Write-Host "[-] Initial state: $(if ($null -eq $init) {'UNKNOWN'} elseif ($init) {'DOCKED (charging)'} else {'UNDOCKED (in use)'})  [block dated $stampTxt]" -ForegroundColor DarkGray

Unregister-Event -SourceIdentifier "GhubWatch" -ErrorAction SilentlyContinue
Unregister-Event -SourceIdentifier "GhubPoll"  -ErrorAction SilentlyContinue
$Action = { Evaluate-State }

$W = New-Object System.IO.FileSystemWatcher
$W.Path = $global:GhubDir; $W.Filter = "settings.db*"
$W.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size
$W.EnableRaisingEvents = $true
Register-ObjectEvent -InputObject $W -EventName "Changed" -SourceIdentifier "GhubWatch" -Action $Action | Out-Null

$T = New-Object System.Timers.Timer
$T.Interval = $global:PollSeconds * 1000; $T.AutoReset = $true
Register-ObjectEvent -InputObject $T -EventName "Elapsed" -SourceIdentifier "GhubPoll" -Action $Action | Out-Null
$T.Start()

Write-Host "[!] A50 Auto-Switcher v5 running. Press CTRL+C to stop." -ForegroundColor Cyan
try { while ($true) { Wait-Event -Timeout 10 } }
finally {
    $T.Stop(); $W.EnableRaisingEvents = $false
    Unregister-Event -SourceIdentifier "GhubWatch" -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier "GhubPoll"  -ErrorAction SilentlyContinue
}
