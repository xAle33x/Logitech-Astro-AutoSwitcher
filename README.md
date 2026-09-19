# Logitech / Astro Auto-Audio Switcher

A lightweight, event-driven PowerShell script that automatically switches the Windows default audio device when you dock or undock your Logitech headset (built and tested with the Astro A50 Gen5).

> **⚠️ September 2026 — Important update (v2.0)**
> A recent G HUB update changed how the charging state is stored. **Scripts from v1.x no longer detect undocking and will appear to "stop working".** If your switcher stopped reacting, update to v2.0. See [What changed in v2.0](#v20-update-g-hub-compatibility-fix--setup-wizard) below.

> **No more editing the script.** Since v2.0 the first launch runs an interactive setup wizard that lists your actual devices and saves your choices to a separate config file.

---

## Features

- **Zero-Click Switch** — routes audio to your speakers when the headset is charging, and instantly back to the headset when you lift it.
- **Interactive First-Run Setup** — numbered pickers for playback devices, recording devices and the G HUB battery key. No source editing, no guessing device names.
- **External Configuration** — settings live in `A50-AutoSwitch.config.json` next to the script. The script never rewrites itself, so it stays git-friendly and signature-safe.
- **Event-Driven** — uses `System.IO.FileSystemWatcher` to sit at ~0% CPU until G HUB writes to its database, plus a lightweight safety poll so a missed filesystem event can never leave the script stuck.
- **WAL-Aware** — reads both `settings.db` and `settings.db-wal` and picks the entry with the most recent timestamp, so stale SQLite write-ahead-log pages can't cause a wrong switch.
- **Conflict-Free** — balanced-brace JSON isolation prevents false switches when another Logitech device is charging (e.g. a G502 Lightspeed).
- **Late-Binding Device IDs** — resolved at switch time, not at startup, so it works even though the headset disappears from Windows when powered off.
- **Auto-Setup** — installs the required AudioDeviceCmdlets module for the current user on first run.

---

## Prerequisites

- Windows
- Logitech G HUB (**not** compatible with the legacy Astro Command Center)
- Windows PowerShell 5.1 or PowerShell 7
- On the very first module installation, Windows may prompt for the **NuGet provider** — press `Y` and Enter.

### Dependencies

This script relies on the [AudioDeviceCmdlets](https://github.com/frgnca/AudioDeviceCmdlets) module by *frgnca* to interact with Windows sound settings.

**Auto-installation:** if the module is missing, the script downloads and installs it from the official PowerShell Gallery for the *Current User* — no admin rights required.

---

## Quick Setup

1. Download `AutoSwitch.ps1` from this repository.
2. **Unblock it** — right-click → **Properties** → check **Unblock** → OK. (See [Troubleshooting](#troubleshooting).)
3. Turn on your headset and **take it off the base**, so every audio endpoint is visible to Windows.
4. Right-click the script → **Run with PowerShell**.

On first launch the setup wizard starts automatically:

```
==================================================
   A50 Auto-Switcher - configuration wizard
==================================================

1/5 - Playback device to use while the headset is DOCKED (e.g. desktop speakers):
  [ 1] Headset Earphone (2- A50 Voice)
  [ 2] Speakers (Creative Stage SE) (current default)
  [ 3] Headphones (2- A50 Game)
  [ m] type a name fragment manually (use this if the device is currently off)
Selection:
```

You'll be asked for five things, then for the G HUB device to monitor:

| Step | Question |
|------|----------|
| 1 | Playback device while **docked** (your speakers) |
| 2 | Playback device while **undocked** (the headset) |
| 3 | Switch the microphone too? `[Y/n]` |
| 4 | Recording device while **docked** (desk/virtual mic) |
| 5 | Recording device while **undocked** (headset mic) |
| — | Which `battery/…/percentage` key to monitor |

Answer `n` at step 3 to switch playback only and skip steps 4–5 entirely.

After a summary and confirmation, the configuration is written to `A50-AutoSwitch.config.json` and the switcher starts:

```
[-] Config: C:\Scripts\A50-AutoSwitch.config.json
[-] Initial state: UNDOCKED (in use)  [block dated 2026-09-19 13:21:45 UTC]
[!] A50 Auto-Switcher v2.0 running. Press CTRL+C to stop.
[15:22:34] >>> DOCKED: playback -> Speakers (Creative Stage SE)
[15:22:42] >>> UNDOCKED: playback -> Headset Earphone (2- A50 Voice)
```

If that timestamp is old or the state is wrong, you're reading a stale entry — see [Troubleshooting](#troubleshooting).

> **Leave the PowerShell window open** (minimised is fine) for the switcher to work. Closing it stops the script. For a fully invisible experience, use the [Task Scheduler method](#run-invisibly-on-startup-task-scheduler) below.

### Command-line options

| Parameter | What it does |
|-----------|--------------|
| *(none)* | Runs the wizard if no config exists, then starts the switcher |
| `-Setup` | Re-runs the wizard and overwrites the existing configuration |
| `-DebugState` | Dumps every battery block found, the winning one and the resulting state, then exits **without touching your audio devices** |
| `-ListDevices` | Prints all playback and recording devices as Windows reports them, then exits |
| `-ConfigPath <path>` | Uses a config file somewhere other than next to the script |

### Configuration file

```json
{
  "Version": 5,
  "Created": "2026-09-19T15:30:00.0000000+02:00",
  "SpeakerName": "Speakers (Creative Stage SE)",
  "HeadsetName": "Headset Earphone (2- A50 Voice)",
  "SwitchMicrophone": true,
  "ExternalMicName": "Microphone (Virtual Audio)",
  "HeadsetMicName": "Headset Microphone (2- A50 Mic)",
  "BatteryKey": "battery/a50/percentage",
  "PollSeconds": 3
}
```

Edit it by hand if you prefer — device names are matched **exactly first, then as a substring**, so both a full name and a short fragment work. Delete the file (or run `-Setup`) to start over.

---

## Troubleshooting

**Script closes immediately or shows a red error?**
Windows blocks scripts downloaded from the internet by default.
- **Unblock the file:** right-click `AutoSwitch.ps1` → **Properties** → check **Unblock** on the *General* tab → **OK**. *(Or run `Unblock-File -Path .\AutoSwitch.ps1`.)*
- **Enable local script execution:** open PowerShell as Administrator and run `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`, press `Y`, then try again.

**Script runs but never switches (or only switches one way)?**
Run `.\AutoSwitch.ps1 -DebugState` **twice** — once with the headset on the base, once with it removed — and compare. It prints every block found, its timestamp, and which one won. If the `Charging` column doesn't flip between the two runs, the detection is the problem, not the audio switching.

For a deeper look, the [Diagnose-GHUB.ps1](https://github.com/xAle33x/Logitech-Astro-AutoSwitcher/blob/main/Diagnose-GHUB.ps1) helper dumps every battery key G HUB exposes, the full JSON behind each, and which fields change between docked and undocked.

**Startup line says `Initial state: UNKNOWN`?**
The script found no readable battery block. Either the wrong key was selected during setup (re-run with `-Setup`) or G HUB no longer persists the state to disk.

**A device is missing from the wizard's list?**
Wireless endpoints vanish from Windows when powered off. Turn the headset on and take it off the base, or pick `m` and type a name fragment manually.

**Wrong headset endpoint gets selected?**
The A50 exposes two playback endpoints, *Voice* and *Game*. Re-run `-Setup` and pick the other one.

---

## Run Invisibly on Startup (Task Scheduler)

Complete the wizard at least once **before** setting this up — the scheduled task runs hidden and can't show interactive prompts.

1. Open **Task Scheduler** → **Create Task**.
2. **General:** name it (e.g. "Astro AutoSwitch") and check *Run only when user is logged on*.
3. **Triggers:** *New* → Begin the task: *At log on*.
4. **Actions:** *New* → Action: *Start a program*.
   - **Program/script:** `powershell.exe`
   - **Add arguments:** `-WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File "C:\Your\Path\Here\AutoSwitch.ps1"`

---

## Adapting for Other Logitech Devices

**TESTING NEEDED.** The script is built around the Astro A50, but nothing is hard-coded to it. If you use a different wireless Logitech headset (G Pro X Wireless, G935, …), just pick your device's key from the wizard's list — it enumerates every `battery/<device>/percentage` key G HUB currently exposes:

```
Which G HUB device should be monitored for charge state?
  [ 1] battery/a50/percentage
  [ 2] battery/g502wireless/percentage
```

**Tip:** run the wizard with the device **on its charger**, so the charging field is present and you can confirm the choice with `-DebugState`.

To inspect the raw data manually instead: press `Win + R`, paste `%LocalAppData%\LGHUB`, open `settings.db` in a text editor, and search for `"battery/"` — **not** for `isCharging`. Since the G HUB update that field only exists while the device is charging, so searching for it with the headset off the base finds nothing.

Whether the same absent-field convention holds for non-A50 devices is unconfirmed — reports welcome via issues.

---

## V2.0 Update: G HUB Compatibility Fix + Setup Wizard

A G HUB update in September 2026 changed the shape of the battery block. Previously the script could rely on an explicit true/false flag. Now:

- Headset **on the base:** `{ "isCharging": true, "percentage": 95, "time": "..." }`
- Headset **removed:** `{ "percentage": 95, "time": "..." }`

G HUB **no longer writes `"isCharging": false`** — the *absence* of the field is the undocked signal. Any v1.x script waiting for a false value never matches it, so it detects docking but never undocking (or stops switching entirely).

### Reliability fixes

- **WAL ordering.** `settings.db-wal` is a SQLite write-ahead log containing historical pages, and its entries are **not** in chronological order. Taking "the last textual match" could return a stale state. v2.0 collects every matching block from both files, parses each `time` field, and uses the most recent — with a deterministic tie-break (WAL beats DB, higher offset beats lower) when timestamps are identical.
- **Two timestamp formats.** G HUB writes `time` as both ISO 8601 (`"2026-09-19T13:03:48Z"`) and Unix epoch (`"1789807057"`). Both are now parsed; previously the epoch variant was silently discarded.
- **Culture-invariant parsing.** ISO timestamps could be misparsed on non-English Windows locales.
- **`$Matches` clobbering.** A subsequent `-match` inside the same loop iteration reset the automatic `$Matches` variable, risking values carried over from the previous iteration. Replaced with explicit `[regex]::Match()` captures.
- **PowerShell 5.1 crash.** `[DateTime]::TryParse` with `[ref]` on an untyped variable throws `MethodCountCouldNotFindBest` on Windows PowerShell 5.1. Replaced with a dedicated parser.
- **Balanced-brace JSON parsing** replaces the old non-greedy regex, which broke on nested objects.
- **Late-binding device IDs** — resolved at switch time rather than cached at startup, fixing failures caused by the headset disappearing from Windows while powered off.
- **Exact-then-substring device matching**, so `A50 Voice` can never be confused with `A50 Game`.
- **Configurable safety poll** (default 3s, debounced) complements the FileSystemWatcher.
- **A missing audio device is logged**, not fatal.

### Usability

- Interactive first-run wizard with numbered device pickers.
- Battery key auto-discovery from `settings.db`.
- External JSON configuration — the script itself is never modified.
- New `-DebugState`, `-ListDevices` and `-ConfigPath` options.

---

## V1.1 Update: Dual-Switch (Audio & Microphone)

The script switches both Playback (speakers) and Recording (microphone) devices simultaneously. If you use a dedicated external microphone (Blue Yeti, QuadCast, …) alongside your headset, answer `Y` at step 3 of the wizard and pick both microphones.

In v1.x this required editing `$global:SwitchMicrophone` by hand; the wizard now handles it. Answer `n` to ignore microphones completely and switch playback only.

---

## License

Copyright (c) 2026 xAle33x (Bojo).

This software is provided under a **Personal Use Non-Commercial License**. You may use, copy, and modify this script strictly for personal purposes. Any commercial use — including redistribution, integration into commercial software, or use for providing commercial services — is strictly prohibited without the express prior written permission of the author.
