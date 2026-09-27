# Logitech / Astro Auto-Audio Switcher

Automatically switches your Windows default audio device when you put a wireless Logitech or Astro device on its charging base, and switches back when you pick it up.

---

## TL;DR

**What it does:** headset on the base → sound goes to your speakers. Headset off the base → sound goes back to the headset. Optionally the microphone follows too.

**What you need:** Windows, G HUB installed and running, and your device paired.

**How to use it:**

1. Download the repository as a ZIP (green **Code** button → *Download ZIP*).
2. Right-click the ZIP → **Properties** → tick **Unblock** → **OK**, *then* extract it.
3. Turn your device on and **take it off the base**.
4. Double-click **`AutoSwitch.bat`** and follow the menu.

```
==================================================
   Logitech / Astro Auto-Switcher
==================================================
  Configuration : not done yet
  Autostart     : disabled

  [1] Set up now (start here)
  [2] Start automatically at logon
  [3] Stop starting automatically
  [4] Reconfigure devices
  [5] Test detection (dock/undock diagnostics)
  [6] Quit
```

Pick **[1]** and answer the questions — the wizard lists your real device names, you just choose numbers. Then pick **[2]** so it starts by itself at every logon, silently and with no window.

That's the whole thing. No admin rights, no execution-policy changes, no editing the script.

---

## Features

- **Zero-click switching** — audio follows the device on and off the base, in about a second.
- **Guided menu** — setup, autostart and diagnostics all in one place; nothing to do in the right order.
- **Interactive wizard** — numbered pickers for playback devices, recording devices and the G HUB battery key. No source editing, no guessing device names.
- **Truly silent autostart** — a hidden logon task under your own user account. No console window, no taskbar button, no flash.
- **External configuration** — settings live in a JSON file next to the script. The script never rewrites itself, so it stays git-friendly.
- **Event-driven** — a `FileSystemWatcher` keeps it at ~0% CPU until G HUB writes to its database, with a 1-second safety poll so a missed event can't leave it stuck.
- **WAL-aware** — reads both `settings.db` and `settings.db-wal` and picks the entry with the most recent timestamp, so stale SQLite pages can't cause a wrong switch.
- **Stale-data guard** — if G HUB isn't running, its leftover data is ignored instead of being mistaken for "device in use".
- **Conflict-free** — balanced-brace JSON isolation prevents false switches when another Logitech device is charging (e.g. a G502 Lightspeed).
- **Late-binding device IDs** — resolved at switch time, so it works even though wireless endpoints disappear from Windows when powered off.
- **Auto-setup** — installs the required `AudioDeviceCmdlets` module for the current user on first run.

## What's in the repository

| File | Purpose |
| --- | --- |
| `AutoSwitch.bat` | Double-click launcher — **start here** |
| `AutoSwitch.ps1` | The switcher itself (everything lives here) |
| `Diagnose-GHUB.ps1` | Extra diagnostic helper, only needed if detection breaks |
| `GHUB-AutoSwitch.config.json` | Created on first run — your settings |

> **Upgrading from an older version?** `Start-AutoSwitch.bat` and `Install-Autostart.bat` are gone — everything moved into the menu. Delete them. Your existing `A50-AutoSwitch.config.json` is still picked up automatically, and enabling autostart from the menu replaces the old scheduled task.

## Prerequisites

- Windows
- Logitech G HUB (**not** compatible with the legacy Astro Command Center)
- Windows PowerShell 5.1 or PowerShell 7
- On the very first module installation, Windows may prompt for the **NuGet provider** — press <kbd>Y</kbd> and <kbd>Enter</kbd>.

### Dependencies

This script relies on the [AudioDeviceCmdlets](https://github.com/frgnca/AudioDeviceCmdlets) module by *frgnca* to interact with Windows sound settings. If the module is missing it is installed from the official PowerShell Gallery for the *current user* — no admin rights required.

## Running it in a window

Menu option **[1]** runs the switcher right there in the console so you can watch it work:

```
[-] Initial state: IN USE  [block dated 2026-09-27 14:02:11 UTC]
[!] Auto-Switcher running. Press CTRL+C (or Q) to stop and go back.
[14:03:27] >>> ON BASE: playback -> Speakers (Creative Stage SE)
[14:05:02] >>> IN USE: playback -> Headset Earphone (2- A50 Voice)
```

<kbd>CTRL</kbd>+<kbd>C</kbd> (or <kbd>Q</kbd>) stops it and returns to the menu. Closing the window also stops it — for a switcher that's always there, use autostart instead.

## Running invisibly at logon

Menu option **[2]** registers a hidden scheduled task under your own user account. It starts 30 seconds after logon, giving G HUB time to come up first.

**Complete the setup first** — a hidden task can't display prompts, so the configuration has to exist already. The menu checks this and tells you if it's missing.

To stop it while it's running hidden, end `powershell.exe` in Task Manager. Option **[3]** removes the autostart entirely.

<details>
<summary>Why the task doesn't just use <code>-WindowStyle Hidden</code></summary>

The console is allocated *before* PowerShell honours that flag, and on Windows 11 with **Default terminal application = Windows Terminal** the flag is ignored outright — leaving a window and a taskbar button for the entire session. That's the cause of the "an icon stays in my taskbar" reports.

The task instead runs a short-lived PowerShell that calls `WScript.Shell.Run(..., 0, $false)`, which creates the real process with `SW_HIDE` at creation time and then exits immediately. Nothing is ever drawn.

Trade-off: because the outer process exits right away, Task Scheduler reports the task as finished and can no longer stop the script for you.

</details>

## Advanced: running the script directly

The `.bat` is only a convenience wrapper. If you're comfortable with PowerShell:

```powershell
.\AutoSwitch.ps1              # run (wizard on first launch)
.\AutoSwitch.ps1 -Menu        # the interactive menu
.\AutoSwitch.ps1 -Setup       # reconfigure
.\AutoSwitch.ps1 -Install     # enable autostart
.\AutoSwitch.ps1 -Uninstall   # remove autostart
.\AutoSwitch.ps1 -DebugState  # inspect detection without changing audio
.\AutoSwitch.ps1 -ListDevices # list audio devices
```

| Parameter | What it does |
| --- | --- |
| *(none)* | Runs the wizard if no config exists, then starts the switcher |
| `-Menu` | Shows the interactive menu |
| `-Setup` | Re-runs the wizard and overwrites the existing configuration |
| `-Install` / `-Uninstall` | Registers or removes the hidden logon task |
| `-DebugState` | Dumps every battery block found, the winner and the resulting state, then exits **without touching your audio devices** |
| `-ListDevices` | Prints all playback and recording devices as Windows reports them |
| `-ConfigPath <path>` | Uses a config file somewhere other than next to the script |

If you get *"running scripts is disabled on this system"*, either use the launcher or run once:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Configuration file

```json
{
  "Version": 6,
  "Created": "2026-09-27T15:30:00.0000000+02:00",
  "SpeakerName": "Speakers (Creative Stage SE)",
  "HeadsetName": "Headset Earphone (2- A50 Voice)",
  "SwitchMicrophone": true,
  "ExternalMicName": "Microphone (Virtual Audio)",
  "HeadsetMicName": "Headset Microphone (2- A50 Mic)",
  "BatteryKey": "battery/a50/percentage",
  "PollSeconds": 1,
  "MaxSampleAgeMinutes": 10
}
```

Edit it by hand if you prefer — device names are matched **exactly first, then as a substring**, so both a full name and a short fragment work. Delete the file (or use menu option **[4]**) to start over.

| Key | Meaning |
| --- | --- |
| `PollSeconds` | Safety poll interval. The watcher is the fast path; this only catches missed filesystem events. |
| `MaxSampleAgeMinutes` | How old G HUB's newest entry may be before the state is considered unknown. Set to `0` to trust any data regardless of age. |

## Any G HUB wireless device

Nothing is hard-coded to a specific model. The wizard enumerates every `battery/<device>/percentage` key G HUB currently exposes, and you pick yours:

```
Which G HUB device should be monitored for charge state?
  [ 1] battery/a50/percentage
  [ 2] battery/g502wireless/percentage
```

**Tip:** run the wizard with the device **on its charger**, so the charging field is present, then confirm with menu option **[5]**.

To inspect the raw data manually: press <kbd>Win</kbd>+<kbd>R</kbd>, paste `%LocalAppData%\LGHUB`, open `settings.db` in a text editor and search for `"battery/` — **not** for `isCharging`. Since the September 2026 G HUB update that field only exists while the device is charging, so searching for it with the device off the base finds nothing.

Built and tested with the Astro A50 Gen 5. Whether the same absent-field convention holds for every other model is unconfirmed — **reports welcome via issues.**

## Troubleshooting

**Nothing happens when I double-click the `.bat`, or a security warning appears.**
Windows marks files downloaded from the internet. Right-click the `.bat` → **Properties** → tick **Unblock** → **OK**. Unblocking the ZIP *before* extracting avoids this entirely.

**"Running scripts is disabled on this system" even when using the launcher.**
Execution policy is enforced by Group Policy (`MachinePolicy` or `UserPolicy`), which `-ExecutionPolicy Bypass` cannot override. Run `Get-ExecutionPolicy -List` to confirm. On a work or school machine, your IT administrator controls this.

**It switches, but slowly.**
Detection is event-driven and usually lands within a second. Going *off* the base is inherently slower than going on: G HUB reports charging immediately, but "not charging" is only inferred when it next writes a battery block. Menu option **[5]** shows the age of the newest entry — if it's already seconds old, that's G HUB's latency, not the script's.

**It never switches, or only switches one way.**
Use menu option **[5]** *twice* — once with the device on the base, once with it removed — and compare. It prints every block found, its timestamp and which one won. If the `Charging` column doesn't flip between the two runs, detection is the problem, not the audio switching.

For a deeper look, [`Diagnose-GHUB.ps1`](Diagnose-GHUB.ps1) dumps every battery key G HUB exposes, the full JSON behind each, and which fields change between states.

**It says `Initial state: UNKNOWN` and never switches.**
Either no readable battery block was found — wrong key picked during setup, so reconfigure with option **[4]** — or G HUB isn't running. The script deliberately leaves your audio devices alone until it sees fresh data, rather than guessing.

**It stopped reacting after a long quiet period.**
If G HUB writes nothing for longer than `MaxSampleAgeMinutes`, the state becomes unknown and the switcher waits rather than acting on stale data. It resumes by itself on the next write. Raise the value in the config if your setup goes quiet for long stretches.

**A device is missing from the wizard's list.**
Wireless endpoints vanish from Windows when powered off. Turn the device on and take it off the base, or pick `m` and type a name fragment manually.

**The wrong headset endpoint gets selected.**
Some headsets expose two playback endpoints, *Voice* and *Game*. Reconfigure with option **[4]** and pick the other one.

**My antivirus flagged the script.**
It reads a file inside `%LocalAppData%\LGHUB` and changes the default audio device — nothing else. No network access, no registry writes, no system files. It ships as readable source precisely so you can verify that before running it.

## Version history

### v2.3

- No longer presented as A50-specific: any device G HUB reports a battery key for can be monitored. Existing `A50-AutoSwitch.config.json` files and the old scheduled task are picked up automatically.
- Consolidated into a single script plus one launcher. `Start-AutoSwitch.bat` and `Install-Autostart.bat` were removed — the menu replaces both, and shows at a glance whether setup and autostart are done.
- <kbd>CTRL</kbd>+<kbd>C</kbd> no longer closes the console: the watcher shuts down cleanly and the menu comes back.

### v2.2

- **Stale-data fix.** When G HUB wasn't running, `settings.db` still held the previous session's blocks. Those have no `isCharging` field and were read as a genuine "in use", so the switcher forced the headset endpoint at logon no matter where the device really was. Entries older than `MaxSampleAgeMinutes` are now reported as unknown and nothing is switched.
- **No assumed initial state.** The switcher waits for fresh data instead of guessing, so a late-starting or crashed G HUB no longer leaves it stuck.
- Autostart moved into the script itself (`-Install` / `-Uninstall`).
- **Hidden-window fix.** The logon task now starts PowerShell via `WScript.Shell.Run` with `SW_HIDE`, so no console window or taskbar button appears even on Windows 11 with Windows Terminal as the default terminal.

### v2.1

- **Responsiveness fix.** The 700 ms debounce *discarded* events rather than deferring them. G HUB writes its WAL in bursts, so the event carrying the state change was often the one thrown away, and the switch had to wait for the next poll tick. Evaluations are now coalesced — nothing is dropped.
- Default poll interval lowered from 3s to 1s.

### v2.0 — G HUB compatibility fix + setup wizard

A G HUB update in September 2026 changed the shape of the battery block:

- Device **on the base:** `{ "isCharging": true, "percentage": 95, "time": "..." }`
- Device **removed:** `{ "percentage": 95, "time": "..." }`

G HUB **no longer writes `"isCharging": false`** — the *absence* of the field is the signal. Any v1.x script waiting for a `false` value never matches it, so it detects docking but never undocking.

**Reliability fixes**

- **WAL ordering.** `settings.db-wal` contains historical pages **not** in chronological order, so "the last textual match" could return a stale state. Every matching block from both files is now collected, each `time` parsed, and the most recent used — with a deterministic tie-break when timestamps are identical.
- **Two timestamp formats.** G HUB writes `time` as both ISO 8601 and Unix epoch. Both are now parsed; previously the epoch variant was silently discarded.
- **Culture-invariant parsing.** ISO timestamps could be misparsed on non-English Windows locales.
- **`$Matches` clobbering.** A later `-match` in the same loop iteration reset the automatic `$Matches` variable. Replaced with explicit `[regex]::Match()` captures.
- **PowerShell 5.1 crash.** `[DateTime]::TryParse` with `[ref]` on an untyped variable throws `MethodCountCouldNotFindBest`. Replaced with a dedicated parser.
- **Balanced-brace JSON parsing** replaces the old non-greedy regex, which broke on nested objects.
- **Late-binding device IDs**, fixing failures caused by the device disappearing from Windows while powered off.
- **Exact-then-substring device matching**, so *Voice* can never be confused with *Game*.
- **A missing audio device is logged**, not fatal.

**Usability**

- Double-click launcher — no execution-policy change needed.
- Interactive first-run wizard with numbered device pickers.
- Battery key auto-discovery from `settings.db`.
- External JSON configuration — the script itself is never modified.
- New `-DebugState`, `-ListDevices` and `-ConfigPath` options.

### v1.1 — dual switching (audio & microphone)

Playback and recording devices switch together. If you use a dedicated external microphone (Blue Yeti, QuadCast, …) alongside your headset, answer <kbd>Y</kbd> at step 3 of the wizard and pick both. Answer <kbd>n</kbd> to switch playback only.

## Disclaimer & limitations

I wrote this script primarily for my personal setup.

- **Use case:** PC gaming and general audio listening. It runs flawlessly for those, but hasn't been exhaustively tested across complex studio configurations or multiple audio routing tools.
- **Windows only.** I don't use my headset with consoles, so I can't guarantee behaviour if your base station is set up in a dual-environment or console mode.

Use it freely, but your mileage may vary depending on your hardware and software environment.

## License

Copyright (c) 2026 xAle33x (Bojo).

This software is provided under a **Personal Use Non-Commercial License**. You may use, copy, and modify this script strictly for personal purposes. Any commercial use — including redistribution, integration into commercial software, or use for providing commercial services — is strictly prohibited without the express prior written permission of the author.
