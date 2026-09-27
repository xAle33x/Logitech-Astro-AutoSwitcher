<#
.SYNOPSIS
Logitech / Astro Auto-Audio Switcher - v2.3

Automatically switches the Windows default playback (and optionally recording) device
when a wireless Logitech / Astro device is placed on or removed from its charging base.

.DESCRIPTION
DETECTION LOGIC (verified against G HUB, September 2026 build):
 - The "battery/<device>/percentage" block contains "isCharging": true ONLY while the
   device is charging on its base. When the device is removed, the field is simply ABSENT
   ("false" is never written).
   => field present = ON BASE ; field absent = IN USE
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
 - NEW: battery key auto-discovery from settings.db (supports any G HUB wireless device).
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

CHANGES IN v2.1 (responsiveness):
 - FIX: the 700 ms time-based debounce DISCARDED events instead of deferring them. G HUB
   writes the WAL in bursts, so the very event carrying the state change was often the one
   thrown away, and the switch had to wait for the next poll tick (up to PollSeconds).
   Evaluations are now coalesced: an event that arrives while one is running sets a flag
   and is re-run immediately afterwards. Nothing is ever dropped.
 - CHANGE: default PollSeconds lowered from 3 to 1. The timer is only a safety net; the
   FileSystemWatcher is the fast path.

CHANGES IN v2.2:
 - FIX: when G HUB was not running, settings.db still held the previous session's blocks.
   Those have no "isCharging" field and were read as a genuine IN USE, so the switcher
   forced the headset endpoint at logon no matter where the device really was. Blocks
   older than MaxSampleAgeMinutes (default 10) are now reported as "state unknown" and
   nothing is switched. Set MaxSampleAgeMinutes to 0 in the config to disable the check.
 - FIX: the initial state is no longer assumed. LastKnownState stays unset until a fresh
   sample arrives, so a late-starting G HUB no longer leaves the switcher stuck.
 - NEW: -Install / -Uninstall register and remove the logon task from within the script,
   and -Menu shows an interactive menu. The separate .bat helpers are no longer needed.

CHANGES IN v2.3:
 - CHANGE: no longer presented as A50-specific. Any wireless device G HUB reports a
   battery key for can be monitored; wording and file names are now generic.
   The old A50-AutoSwitch.config.json and the old task name are still picked up
   automatically, so existing installations keep working.
 - FIX: stopping the switcher (or the diagnostics) with CTRL+C no longer kills the whole
   console. CTRL+C is read as input, the watcher shuts down cleanly and the menu returns.

.PARAMETER Install
Register the hidden scheduled task that starts the switcher at logon, then exit.

.PARAMETER Uninstall
Remove the scheduled task, then exit.

.PARAMETER Menu
Show the interactive menu (setup, run, enable/disable autostart, diagnostics).

.PARAMETER Setup
Force the interactive configuration wizard, overwriting any existing configuration.

.PARAMETER DebugState
Print every battery block found, the winning one and the resulting state, then exit
without registering any watcher or changing the default audio devices.

.PARAMETER ListDevices
Print all playback and recording devices as Windows reports them, then exit.

.PARAMETER ConfigPath
Override the location of the configuration file.
Defaults to 'GHUB-AutoSwitch.config.json' next to the script.

.NOTES
Requires the AudioDeviceCmdlets module (installed automatically for the current user).
Tested on Windows PowerShell 5.1 and PowerShell 7.

TIP: power on your device and take it OFF the base before running the wizard, so that
every endpoint is visible to Windows and can be picked from the list.

.EXAMPLE
    .\AutoSwitch.ps1
    First run: starts the setup wizard, then starts the switcher.

.EXAMPLE
    .\AutoSwitch.ps1 -Setup
    Reconfigure devices from scratch.

.EXAMPLE
    .\AutoSwitch.ps1 -DebugState
    Dock and undock the device, re-running each time, to confirm detection works.

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
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Menu,
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
    $ConfigPath = Join-Path $root "GHUB-AutoSwitch.config.json"
    # Installations made before v2.3 used an A50-specific name. Keep using it if it is
    # the only one present, so upgrading does not silently discard existing settings.
    if (-not (Test-Path $ConfigPath)) {
        $legacy = Join-Path $root "A50-AutoSwitch.config.json"
        if (Test-Path $legacy) { $ConfigPath = $legacy }
    }
}

$global:LastStamp      = $null
$global:LastKnownState = $null
$global:Evaluating     = $false
$global:Pending        = $false
$global:StaleWarned    = $false

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

<# Returns $true (on base) / $false (in use) / $null (undetermined).
   Sorted by Time, then Rank (WAL beats DB), then Offset (latest written page).

   FRESHNESS GUARD: settings.db keeps the blocks of the PREVIOUS session even when
   G HUB is not running. Those blocks have no "isCharging" field, which the caller
   would otherwise read as a perfectly legitimate IN USE - so the switcher would
   force the headset endpoint at logon regardless of where the device actually is.
   A block older than MaxSampleAgeMinutes is therefore treated as "state unknown"
   ($null) and the caller leaves the audio devices alone. #>
function global:Get-ChargingState {
    $samples = Get-BatterySamples
    if (-not $samples -or $samples.Count -eq 0) { $global:LastStamp = $null; return $null }
    $winner = $samples | Sort-Object Time, Rank, Offset | Select-Object -Last 1
    $global:LastStamp = $winner.Time

    if ($global:MaxSampleAgeMinutes -gt 0) {
        $ageMin = ([DateTime]::UtcNow - $winner.Time).TotalMinutes
        if ($ageMin -gt $global:MaxSampleAgeMinutes) {
            if (-not $global:StaleWarned) {
                $t = Get-Date -Format "HH:mm:ss"
                Write-Host ("[$t] [!] Newest G HUB block is {0:N0} min old (limit {1}). State unknown - not switching." -f $ageMin, $global:MaxSampleAgeMinutes) -ForegroundColor DarkYellow
                Write-Host "        Is G HUB running? Audio devices are left untouched until fresh data appears." -ForegroundColor DarkGray
                $global:StaleWarned = $true
            }
            return $null
        }
        if ($global:StaleWarned) {
            $t = Get-Date -Format "HH:mm:ss"
            Write-Host "[$t] [+] Fresh G HUB data again - tracking resumed." -ForegroundColor DarkGray
            $global:StaleWarned = $false
        }
    }
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
    <# Coalesce bursts instead of debouncing them.
       G HUB writes the WAL in several chunks, so the watcher fires 3-4 times in a
       row. The previous time-based debounce DISCARDED those events, and the one
       carrying the actual state change was usually among them - the switch then
       had to wait for the next poll tick. Here an event that arrives while an
       evaluation is in flight only raises a flag, and the loop runs again as soon
       as the current pass ends. Nothing is dropped, nothing is delayed.

       A $null state (no data, or data too old to be trusted) is a no-op on purpose:
       LastKnownState keeps its previous value - $null at startup - so the first real
       switch only happens once G HUB provides a fresh sample. #>
    if ($global:Evaluating) { $global:Pending = $true; return }
    $global:Evaluating = $true
    try {
        do {
            $global:Pending = $false
            $docked = Get-ChargingState
            if ($null -ne $docked -and $docked -ne $global:LastKnownState) {
                if ($docked) { Switch-To $global:SpeakerName $global:ExternalMicName "ON BASE" "Yellow" }
                else         { Switch-To $global:HeadsetName $global:HeadsetMicName "IN USE"  "Green"  }
                $global:LastKnownState = $docked
            }
        } while ($global:Pending)
    } finally { $global:Evaluating = $false }
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
        Write-Host "      Make sure G HUB is running and the device is powered on." -ForegroundColor DarkGray
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
    Write-Host "   G HUB Auto-Switcher - configuration wizard" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "TIP: power on your device and take it OFF the base first," -ForegroundColor DarkGray
    Write-Host "     so every endpoint is visible in the lists below." -ForegroundColor DarkGray

    $speaker = Select-AudioDeviceInteractive -Type "Playback" `
        -Prompt "1/5 - Playback device to use while the headset is ON THE BASE (e.g. desktop speakers):"
    $headset = Select-AudioDeviceInteractive -Type "Playback" `
        -Prompt "2/5 - Playback device to use while the headset is IN USE (the headset itself):"

    Write-Host ""
    $micAns = Read-Host "3/5 - Switch the microphone as well? [Y/n]"
    $switchMic = -not ($micAns -match '^(n|no)$')

    $extMic = $null; $hsMic = $null
    if ($switchMic) {
        $extMic = Select-AudioDeviceInteractive -Type "Recording" `
            -Prompt "4/5 - Recording device to use while the headset is ON THE BASE:"
        $hsMic  = Select-AudioDeviceInteractive -Type "Recording" `
            -Prompt "5/5 - Recording device to use while the headset is IN USE (headset mic):"
    } else {
        Write-Host "  Skipping microphone configuration." -ForegroundColor DarkGray
    }

    $batteryKey = Select-BatteryKeyInteractive

    $cfg = [ordered]@{
        Version          = 6
        Created          = (Get-Date).ToString('o')
        SpeakerName      = $speaker
        HeadsetName      = $headset
        SwitchMicrophone = $switchMic
        ExternalMicName  = $extMic
        HeadsetMicName   = $hsMic
        BatteryKey       = $batteryKey
        PollSeconds      = 1
        # Blocks older than this are treated as "state unknown" instead of IN USE.
        # Set to 0 to disable the check and always trust the newest block.
        MaxSampleAgeMinutes = 10
    }

    Write-Host ""
    Write-Host "--- Summary ---" -ForegroundColor Cyan
    Write-Host ("  ON BASE -> playback : {0}" -f $speaker) -ForegroundColor Yellow
    Write-Host ("  IN USE  -> playback : {0}" -f $headset) -ForegroundColor Green
    if ($switchMic) {
        Write-Host ("  ON BASE -> mic      : {0}" -f $extMic) -ForegroundColor Yellow
        Write-Host ("  IN USE  -> mic      : {0}" -f $hsMic) -ForegroundColor Green
    } else {
        Write-Host "  Microphone switching : disabled" -ForegroundColor DarkGray
    }
    Write-Host ("  G HUB key           : {0}" -f $batteryKey) -ForegroundColor Gray
    Write-Host ""

    $confirm = Read-Host "Save this configuration? [Y/n]"
    if ($confirm -match '^(n|no)$') {
        Write-Host "[-] Aborted. Nothing was saved." -ForegroundColor Red
        return $null
    }

    try {
        $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8 -ErrorAction Stop
        Write-Host "[+] Configuration saved to: $Path" -ForegroundColor Green
    } catch {
        Write-Host "[-] Could not write the configuration file: $($_.Exception.Message)" -ForegroundColor Red
        return $null
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
        return $null
    }
}

# Loads the config into the globals used by the worker functions.
# Returns $true on success, $false if the configuration is missing or incomplete.
function Initialize-Configuration {
    param([switch]$ForceSetup)

    if ($ForceSetup -or -not (Test-Path $ConfigPath)) {
        if (-not $ForceSetup) { Write-Host "[i] No configuration found - starting first-run setup." -ForegroundColor Yellow }
        $cfg = Invoke-SetupWizard -Path $ConfigPath
    } else {
        $cfg = Import-Configuration -Path $ConfigPath
    }
    if ($null -eq $cfg) { return $false }

    $global:SpeakerName      = $cfg.SpeakerName
    $global:HeadsetName      = $cfg.HeadsetName
    $global:SwitchMicrophone = [bool]$cfg.SwitchMicrophone
    $global:ExternalMicName  = $cfg.ExternalMicName
    $global:HeadsetMicName   = $cfg.HeadsetMicName
    $global:BatteryKey       = $cfg.BatteryKey
    $global:PollSeconds      = if ($cfg.PollSeconds) { [int]$cfg.PollSeconds } else { 1 }
    # $null (key missing in an older config) must fall back to the default, but an
    # explicit 0 means "disabled" and has to survive.
    $global:MaxSampleAgeMinutes = if ($null -ne $cfg.MaxSampleAgeMinutes) { [int]$cfg.MaxSampleAgeMinutes } else { 10 }

    if ([string]::IsNullOrWhiteSpace($global:SpeakerName) -or [string]::IsNullOrWhiteSpace($global:HeadsetName)) {
        Write-Host "[-] Configuration is incomplete. Re-run the setup to rebuild it." -ForegroundColor Red
        return $false
    }
    return $true
}

# ---------------------------------------------------------------- diagnostics
function Invoke-Diagnostics {
    Write-Host "`n=== SAMPLES FOUND FOR '$global:BatteryKey' ===" -ForegroundColor Cyan
    $s = Get-BatterySamples
    if (-not $s -or $s.Count -eq 0) {
        Write-Host "[!] No valid block found." -ForegroundColor Red
        return
    }
    $s | Sort-Object Time, Rank, Offset |
        Format-Table @{L='File';E={$_.File}}, @{L='Offset';E={$_.Offset}},
                     @{L='Time (UTC)';E={$_.Time.ToString('yyyy-MM-dd HH:mm:ss')}},
                     @{L='Charging';E={$_.IsCharging}} -AutoSize
    $w = $s | Sort-Object Time, Rank, Offset | Select-Object -Last 1
    $ageMin = ([DateTime]::UtcNow - $w.Time).TotalMinutes
    Write-Host "WINNER : $($w.File) @ $($w.Offset) | $($w.Time.ToString('u'))" -ForegroundColor Yellow
    Write-Host "BLOCK  : $($w.Block)" -ForegroundColor DarkGray
    Write-Host ("AGE    : {0:N1} min (limit {1})" -f $ageMin, $global:MaxSampleAgeMinutes) -ForegroundColor DarkGray
    Write-Host "STATE  : $(if ($w.IsCharging) {'ON BASE (charging)'} else {'IN USE'})" -ForegroundColor Green
}

# ---------------------------------------------------------------- switcher loop
function Start-Switcher {
    $init = Get-ChargingState
    $stampTxt = if ($global:LastStamp) { $global:LastStamp.ToString('yyyy-MM-dd HH:mm:ss') + ' UTC' } else { 'n/a' }
    Write-Host "[-] Config: $ConfigPath" -ForegroundColor DarkGray
    Write-Host "[-] Initial state: $(if ($null -eq $init) {'UNKNOWN - waiting for fresh G HUB data'} elseif ($init) {'ON BASE (charging)'} else {'IN USE'})  [block dated $stampTxt]" -ForegroundColor DarkGray
    # LastKnownState is deliberately left unset here: the first evaluation then aligns the
    # audio devices to reality instead of waiting for a transition. If the state is UNKNOWN
    # that first evaluation is a no-op, which is exactly what we want.

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

    <# Interactive consoles read CTRL+C as ordinary input instead of letting it raise
       a break. Plain CTRL+C tears down the whole PowerShell session, which closed the
       window and made it impossible to return to the menu. With TreatControlCAsInput
       the key is consumed here, the watcher is disposed cleanly and the caller resumes.
       When the script runs hidden from the scheduled task there is no console at all,
       so the key polling is skipped and the loop simply waits forever. #>
    $interactive = $false
    try { $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected } catch { $interactive = $false }

    $prevCtrlC = $false
    if ($interactive) {
        try { $prevCtrlC = [Console]::TreatControlCAsInput; [Console]::TreatControlCAsInput = $true } catch { $interactive = $false }
    }

    if ($interactive) {
        Write-Host "[!] Auto-Switcher running. Press CTRL+C (or Q) to stop and go back." -ForegroundColor Cyan
    } else {
        Write-Host "[!] Auto-Switcher running." -ForegroundColor Cyan
    }

    try {
        while ($true) {
            if ($interactive -and [Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                $isCtrlC = ($k.Modifiers -band [ConsoleModifiers]::Control) -and ($k.Key -eq [ConsoleKey]::C)
                if ($isCtrlC -or $k.Key -eq [ConsoleKey]::Q -or $k.Key -eq [ConsoleKey]::Escape) {
                    Write-Host "`n[i] Stopping..." -ForegroundColor DarkGray
                    break
                }
            }
            Wait-Event -Timeout 1 | Out-Null
        }
    } finally {
        if ($interactive) { try { [Console]::TreatControlCAsInput = $prevCtrlC } catch { } }
        $T.Stop(); $T.Dispose()
        $W.EnableRaisingEvents = $false; $W.Dispose()
        Unregister-Event -SourceIdentifier "GhubWatch" -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier "GhubPoll"  -ErrorAction SilentlyContinue
        # A fresh run must not inherit the previous state.
        $global:LastKnownState = $null
        $global:StaleWarned    = $false
    }
}

# ---------------------------------------------------------------- autostart
$global:TaskName       = "Logitech GHUB AutoSwitch"
# Registered under a different name before v2.3.
$global:LegacyTaskName = "Astro A50 AutoSwitch"

<# Registers the logon task.

   The task does NOT run powershell.exe -WindowStyle Hidden directly: the console
   is allocated before the flag is honoured, and on Windows 11 with "Default
   terminal application = Windows Terminal" the flag is ignored outright, leaving
   a window and a taskbar button for the whole session. Instead a short-lived
   PowerShell uses WScript.Shell.Run(..., 0, $false), which creates the real
   process with SW_HIDE at creation time, and then exits immediately. #>
function Install-Autostart {
    param([string]$ScriptPath)

    if (-not (Test-Path $ConfigPath)) {
        Write-Host "[!] No configuration yet. Run the setup first - a hidden task cannot show prompts." -ForegroundColor Yellow
        return
    }

    $q     = [char]34
    $inner = "powershell -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "
    $cmd   = "(New-Object -ComObject WScript.Shell).Run('" + $inner + "' + [char]34 + '" + $ScriptPath + "' + [char]34, 0, `$false)"
    $arg   = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command " + $q + $cmd + $q

    try {
        # Drop the pre-v2.3 task, otherwise both would run at logon.
        Unregister-ScheduledTask -TaskName $global:LegacyTaskName -Confirm:$false -ErrorAction SilentlyContinue

        $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
        $t = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        # G HUB needs a moment after logon to populate settings.db.
        $t.Delay = 'PT30S'
        $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
             -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -Hidden -MultipleInstances IgnoreNew
        $p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $global:TaskName -Action $a -Trigger $t -Settings $s -Principal $p -Force | Out-Null
        Write-Host "[+] Autostart enabled - silent, 30s after logon." -ForegroundColor Green
    } catch {
        Write-Host "[-] Could not register the task: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Uninstall-Autostart {
    $removed = $false
    foreach ($name in @($global:TaskName, $global:LegacyTaskName)) {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
            $removed = $true
        }
    }
    if ($removed) { Write-Host "[+] Autostart removed." -ForegroundColor Green }
    else          { Write-Host "[i] No autostart task was registered." -ForegroundColor DarkGray }
}

function Test-AutostartInstalled {
    foreach ($name in @($global:TaskName, $global:LegacyTaskName)) {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------- menu
function Show-Menu {
    param([string]$ScriptPath)

    while ($true) {
        $configured = Test-Path $ConfigPath
        $installed  = Test-AutostartInstalled

        Write-Host ""
        Write-Host "==================================================" -ForegroundColor Cyan
        Write-Host "   Logitech / Astro Auto-Switcher" -ForegroundColor Cyan
        Write-Host "==================================================" -ForegroundColor Cyan
        Write-Host ("  Configuration : {0}" -f $(if ($configured) { "ready" } else { "not done yet" })) -ForegroundColor $(if ($configured) { "Green" } else { "Yellow" })
        Write-Host ("  Autostart     : {0}" -f $(if ($installed)  { "enabled" } else { "disabled" }))   -ForegroundColor $(if ($installed)  { "Green" } else { "DarkGray" })
        Write-Host ""

        if (-not $configured) {
            Write-Host "  [1] Set up now (start here)" -ForegroundColor White
        } else {
            Write-Host "  [1] Run the switcher in this window" -ForegroundColor White
        }
        Write-Host "  [2] Start automatically at logon" -ForegroundColor White
        Write-Host "  [3] Stop starting automatically" -ForegroundColor White
        Write-Host "  [4] Reconfigure devices" -ForegroundColor White
        Write-Host "  [5] Test detection (dock/undock diagnostics)" -ForegroundColor White
        Write-Host "  [6] Quit" -ForegroundColor White
        Write-Host ""

        switch (Read-Host "  Selection") {
            '1' {
                if (Initialize-Configuration) { Start-Switcher }
            }
            '2' {
                if (-not $configured) {
                    Write-Host "[!] Set it up first with option [1]." -ForegroundColor Yellow
                } else {
                    Install-Autostart -ScriptPath $ScriptPath
                    Write-Host "    It will start by itself next logon. Use [1] to run it right now." -ForegroundColor DarkGray
                }
            }
            '3' { Uninstall-Autostart }
            '4' {
                if (Initialize-Configuration -ForceSetup) {
                    Write-Host "[i] Saved. Use [1] to start the switcher." -ForegroundColor DarkGray
                }
            }
            '5' {
                if (Initialize-Configuration) { Invoke-Diagnostics }
                Write-Host ""
                Write-Host "  Press any key to go back to the menu..." -ForegroundColor DarkGray
                [void](Read-Host)
            }
            '6' { return }
            default { Write-Host "  Invalid selection." -ForegroundColor Red }
        }
    }
}

# ---------------------------------------------------------------- entry points
$SelfPath = $PSCommandPath
if (-not $SelfPath) { $SelfPath = Join-Path (Get-Location).Path "AutoSwitch.ps1" }

if ($Install)   { Install-Autostart -ScriptPath $SelfPath; return }
if ($Uninstall) { Uninstall-Autostart; return }

if ($ListDevices) {
    Write-Host "`n=== PLAYBACK ===" -ForegroundColor Cyan
    Get-AudioDevice -List | Where-Object { $_.Type -like "*Playback*" }  | Select-Object Index, Default, Name | Format-Table -AutoSize
    Write-Host "=== RECORDING ===" -ForegroundColor Cyan
    Get-AudioDevice -List | Where-Object { $_.Type -like "*Recording*" } | Select-Object Index, Default, Name | Format-Table -AutoSize
    return
}

if ($Menu) { Show-Menu -ScriptPath $SelfPath; return }

# Direct invocation (this is also how the scheduled task starts the script).
if (-not (Initialize-Configuration -ForceSetup:$Setup)) { Exit 1 }

if ($DebugState) { Invoke-Diagnostics; return }

Start-Switcher
