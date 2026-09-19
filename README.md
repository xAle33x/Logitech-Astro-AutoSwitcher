## Logitech / Astro Auto-Audio Switcher

A lightweight, event-driven PowerShell script that automatically switches the Windows default audio device when you dock or undock your Logitech headset (built and tested with the Astro A50 Gen5).

**⚠️ September 2026 — Important update (v2.0)**
A recent G HUB update changed how the charging state is stored. **Scripts from v1.x no longer detect undocking and will appear to "stop working".** If your switcher stopped reacting, update to v2.0. See [What changed in v2.0](#v20-update-g-hub-compatibility-fix--setup-wizard) below.

**No more editing the script, no more execution policy.** Since v2.0 you just double-click a launcher, and an interactive wizard lists your actual devices and saves your choices to a separate config file.

### Features
- **Zero-Click Switch** — routes audio to your speakers when the headset is charging, and instantly back to the headset when you lift it.
- **Double-Click to Run** — `Start-AutoSwitch.bat` launches the script without requiring any execution-policy change or administrator rights.
- **Interactive First-Run Setup** — numbered pickers for playback devices, recording devices and the G HUB battery key. No source editing, no guessing device names.
- **One-Click Autostart** — `Install-Autostart.bat` registers a hidden logon task under your own user account.
- **External Configuration** — settings live in `A50-AutoSwitch.config.json` next to the script. The script never rewrites itself, so it stays git-friendly and signature-safe.
- **Event-Driven** — uses `System.IO.FileSystemWatcher` to sit at ~0% CPU until G HUB writes to its database, plus a lightweight safety poll so a missed filesystem event can never leave the script stuck.
- **WAL-Aware** — reads both `settings.db` and `settings.db-wal` and picks the entry with the most recent timestamp, so stale SQLite write-ahead-log pages can't cause a wrong switch.
- **Conflict-Free** — balanced-brace JSON isolation prevents false switches when another Logitech device is charging (e.g. a G502 Lightspeed).
- **Late-Binding Device IDs** — resolved at switch time, not at startup, so it works even though the headset disappears from Windows when powered off.
- **Auto-Setup** — installs the required AudioDeviceCmdlets module for the current user on first run.

### What's in the repository

| File | Purpose |
|------|---------|
| `AutoSwitch.ps1` | The switcher itself |
| `Start-AutoSwitch.bat` | Double-click launcher — **start here** |
| `Install-Autostart.bat` | Enables or removes the hidden logon task |
| `Diagnose-GHUB.ps1` | Diagnostic helper, only needed if detection breaks |
| `A50-AutoSwitch.config.json` | Created on first run — your settings |

### Prerequisites
- Windows
- Logitech G HUB (**not** compatible with the legacy Astro Command Center)
- Windows PowerShell 5.1 or PowerShell 7
- On the very first module installation, Windows may prompt for the **NuGet provider** — press `Y` and Enter.

#### Dependencies

This script relies on the [AudioDeviceCmdlets](https://github.com/frgnca/AudioDeviceCmdlets) module by _frgnca_ to interact with Windows sound settings.
**Auto-installation:** if the module is missing, the script downloads and installs it from the official PowerShell Gallery for the _Current User_ — no admin rights required.

### Quick Setup

**No PowerShell knowledge required.** You do not need to change your execution policy or run anything as administrator.

1. Download the repository as a ZIP (green **Code** button → _Download ZIP_).
2. **Right-click the ZIP → Properties → tick `Unblock` → OK**, _then_ extract it. This one step clears the "downloaded from the internet" mark from every file inside — doing it on the ZIP saves you from doing it on each file afterwards.
3. Turn on your headset and **take it off the base**, so every audio endpoint is visible to Windows.
4. Double-click **`Start-AutoSwitch.bat`**.

That's it. The launcher runs the script with `-ExecutionPolicy Bypass`, which applies to that single process and needs no admin rights, so the usual *"running scripts is disabled on this system"* error can't happen.

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

Answer the questions, confirm the summary, and the switcher starts. Your choices are saved to `A50-AutoSwitch.config.json` next to the script.

**Leave the window open** (minimised is fine). Closing it stops the switcher. To have it start silently at every logon, see below.

### Run Invisibly on Startup

Double-click **`Install-Autostart.bat`** and pick option `1`. It registers a hidden scheduled task under your own user account — no admin rights, no console window, no flash at logon. Run it again and pick `2` to remove the autostart.

**Complete the wizard first.** A hidden task cannot display prompts, so the configuration must already exist. The installer checks for it and warns you if it's missing.

To stop the switcher while it's running hidden, end `powershell.exe` in Task Manager.

<details>
<summary><b>Manual Task Scheduler setup</b> (only if you prefer doing it by hand)</summary>

1. Open **Task Scheduler** → **Create Task**.
2. **General:** name it (e.g. "Astro AutoSwitch"), tick _Run only when user is logged on_, and tick **Hidden**.
3. **Triggers:** _New_ → Begin the task: _At log on_.
4. **Actions:** _New_ → Action: _Start a program_.
   - **Program/script:** `powershell.exe`
   - **Add arguments:** `-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "C:\Your\Path\Here\AutoSwitch.ps1"`

Some Windows builds still show a brief console flash with this method, because Task Scheduler creates the console host *before* PowerShell applies `-WindowStyle`. If that bothers you, use this instead, which passes the hidden flag at process creation:

```
-WindowStyle Hidden -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File ""C:\Your\Path\Here\AutoSwitch.ps1""'"
```

Trade-off: the outer process exits immediately after spawning the real one, so Task Scheduler reports the task as finished and can no longer stop the script for you.

**Don't** select _Run whether user is logged on or not_ — that runs in a non-interactive session, where changing the per-user default audio device is not expected to work.
</details>

### Advanced: running the script directly

The `.bat` files are only convenience wrappers. If you're comfortable with PowerShell, call the script directly:

```powershell
.\AutoSwitch.ps1              # run (wizard on first launch)
.\AutoSwitch.ps1 -Setup       # reconfigure
.\AutoSwitch.ps1 -DebugState  # inspect detection without changing audio
.\AutoSwitch.ps1 -ListDevices # list audio devices
```

| Parameter | What it does |
|-----------|--------------|
| _(none)_ | Runs the wizard if no config exists, then starts the switcher |
| `-Setup` | Re-runs the wizard and overwrites the existing configuration |
| `-DebugState` | Dumps every battery block found, the winning one and the resulting state, then exits **without touching your audio devices** |
| `-ListDevices` | Prints all playback and recording devices as Windows reports them, then exits |
| `-ConfigPath <path>` | Uses a config file somewhere other than next to the script |

If you get *"running scripts is disabled on this system"*, either use the launcher or run once:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

#### Configuration file

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

### Troubleshooting

**Nothing happens when I double-click the `.bat`, or a security warning appears.**
Windows marks files downloaded from the internet. Right-click the `.bat` → **Properties** → tick **Unblock** → **OK**. Unblocking the ZIP *before* extracting avoids this entirely.

**"Running scripts is disabled on this system" even when using the launcher.**
This means execution policy is enforced by Group Policy (`MachinePolicy` or `UserPolicy`), which `-ExecutionPolicy Bypass` cannot override. Run `Get-ExecutionPolicy -List` to confirm. On a work or school machine, your IT administrator controls this.

**Script runs but never switches (or only switches one way).**
Run `.\AutoSwitch.ps1 -DebugState` **twice** — once with the headset on the base, once with it removed — and compare. It prints every block found, its timestamp, and which one won. If the `Charging` column doesn't flip between the two runs, the detection is the problem, not the audio switching.

For a deeper look, the [Diagnose-GHUB.ps1](https://github.com/xAle33x/Logitech-Astro-AutoSwitcher/blob/main/Diagnose-GHUB.ps1) helper dumps every battery key G HUB exposes, the full JSON behind each, and which fields change between docked and undocked.

**Startup line says `Initial state: UNKNOWN`.**
The script found no readable battery block. Either the wrong key was selected during setup (re-run with `-Setup`) or G HUB no longer persists the state to disk.

**A device is missing from the wizard's list.**
Wireless endpoints vanish from Windows when powered off. Turn the headset on and take it off the base, or pick `m` and type a name fragment manually.

**Wrong headset endpoint gets selected.**
The A50 exposes two playback endpoints, _Voice_ and _Game_. Re-run `-Setup` and pick the other one.

**My antivirus flagged the script.**
It reads a file inside `%LocalAppData%\LGHUB` and changes the default audio device — nothing else. No network access, no registry writes, no system files. It ships as readable source precisely so you can verify that before running it.

### Adapting for Other Logitech Devices

**TESTING NEEDED.** The script is built around the Astro A50, but nothing is hard-coded to it. If you use a different wireless Logitech headset (G Pro X Wireless, G935, …), just pick your device's key from the wizard's list — it enumerates every `battery/<device>/percentage` key G HUB currently exposes:

```
Which G HUB device should be monitored for charge state?
  [ 1] battery/a50/percentage
  [ 2] battery/g502wireless/percentage
```

**Tip:** run the wizard with the device **on its charger**, so the charging field is present, and confirm the choice with `-DebugState`.

To inspect the raw data manually instead: press `Win + R`, paste `%LocalAppData%\LGHUB`, open `settings.db` in a text editor, and search for `"battery/"` — **not** for `isCharging`. Since the G HUB update that field only exists while the device is charging, so searching for it with the headset off the base finds nothing.

Whether the same absent-field convention holds for non-A50 devices is unconfirmed — reports welcome via issues.

### V2.0 Update: G HUB Compatibility Fix + Setup Wizard

A G HUB update in September 2026 changed the shape of the battery block. Previously the script could rely on an explicit true/false flag. Now:

- Headset **on the base:** `{ "isCharging": true, "percentage": 95, "time": "..." }`
- Headset **removed:** `{ "percentage": 95, "time": "..." }`

G HUB **no longer writes `"isCharging": false`** — the _absence_ of the field is the undocked signal. Any v1.x script waiting for a false value never matches it, so it detects docking but never undocking (or stops switching entirely).

#### Reliability fixes
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

#### Usability
- Double-click launcher — no execution-policy change needed.
- One-click hidden autostart installer.
- Interactive first-run wizard with numbered device pickers.
- Battery key auto-discovery from `settings.db`.
- External JSON configuration — the script itself is never modified.
- New `-DebugState`, `-ListDevices` and `-ConfigPath` options.

### V1.1 Update: Dual-Switch (Audio & Microphone)

The script switches both Playback (speakers) and Recording (microphone) devices simultaneously. If you use a dedicated external microphone (Blue Yeti, QuadCast, …) alongside your headset, answer `Y` at step 3 of the wizard and pick both microphones.

In v1.x this required editing `$global:SwitchMicrophone` by hand; the wizard now handles it. Answer `n` to ignore microphones completely and switch playback only.

### Disclaimer & Limitations

I wrote this script primarily for my personal setup.

- **Use case:** PC gaming and general audio listening. It runs flawlessly for those, but hasn't been exhaustively tested across complex studio configurations or multiple audio routing software.
- **Windows only:** designed and tested exclusively on Windows. I don't use my headset with consoles, so I can't guarantee behaviour if your base station is set up in a dual-environment or console mode.

Use it freely, but your mileage may vary depending on your specific hardware and software environment.

### License

Copyright (c) 2026 xAle33x (Bojo).

This software is provided under a **Personal Use Non-Commercial License**. You may use, copy, and modify this script strictly for personal purposes. Any commercial use — including redistribution, integration into commercial software, or use for providing commercial services — is strictly prohibited without the express prior written permission of the author.
