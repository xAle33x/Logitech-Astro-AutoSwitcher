## Logitech / Astro Auto-Audio Switcher

A lightweight, event-driven PowerShell script that automatically switches Windows default audio output when you dock or undock your Logitech headset (specifically built and tested with the Astro A50 Gen5).

> **⚠️ September 2026 — Important update (v2.0)**
> A recent G HUB update changed how the charging state is stored. **Scripts from v1.x no longer detect undocking and will appear to "stop working".** If your switcher stopped reacting, update to v2.0. See [What changed in v2.0](#v20-update-g-hub-compatibility-fix) below.

### Features
- **Zero-Click Switch:** Automatically routes audio to your speakers when the headset is charging, and instantly back to the headset when lifted.
- **Event-Driven:** Uses System.IO.FileSystemWatcher to sit at ~0% CPU usage in the background until G HUB physically writes to its database, plus a lightweight safety poll so a missed filesystem event can never leave the script stuck.
- **WAL-Aware:** Reads both settings.db and settings.db-wal and picks the entry with the most recent timestamp, so stale SQLite write-ahead-log pages can't cause a wrong switch.
- **Conflict-Free:** Uses balanced-brace JSON block isolation to prevent false audio switches if you plug in another Logitech device to charge (like a G502 Lightspeed mouse).
- **Late-Binding Device IDs:** Audio device IDs are resolved at switch time, not at startup, so it works correctly even though the headset disappears from Windows when powered off.
- **Auto-Setup:** Automatically installs the required AudioDeviceCmdlets module for the current user on its first run.

### Prerequisites
- Windows OS
- Logitech G HUB software (Note: Not compatible with the legacy Astro Command Center)
- Windows PowerShell
- If this is your first time ever running a PowerShell module installation, a prompt might ask you to install the 'NuGet provider'. Simply press Y and hit Enter to allow it.

### Dependencies

This script relies on the [AudioDeviceCmdlets](https://github.com/frgnca/AudioDeviceCmdlets) module created by _frgnca_ to interact with Windows sound settings.
**Note on Auto-Installation:** If you do not already have this module, the script is designed to automatically download and install it from the official Microsoft PowerShell Gallery for the _Current User_ (no admin rights required) during its very first run.

### Troubleshooting

**Script closes immediately or shows a red error?** Windows protects your PC by blocking scripts downloaded from the internet by default. To fix this, follow these steps:
- **Unblock the downloaded file:** Right-click the AutoSwitch.ps1 file, select **Properties**, check the **Unblock** box at the bottom of the _General_ tab, and click **OK**. _(Alternatively, run Unblock-File -Path .\AutoSwitch.ps1 in PowerShell)._
- **Enable local script execution:** If the script still doesn't run, your system might have PowerShell scripts completely disabled.
Open PowerShell as Administrator, paste this command: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser, press Y to confirm, and try running the script again.

**Script runs but never switches (or only switches one way)?** This is almost always a G HUB format change. Run the included [Diagnose-GHUB.ps1](https://github.com/xAle33x/Logitech-Astro-AutoSwitcher/blob/main/Diagnose-GHUB.ps1) helper **twice** — once with the headset on the base, once with it removed — and compare the two outputs. It prints every battery key found, the full JSON block behind each one, and which fields actually change between docked and undocked.

**Startup line says `Stato iniziale: SCONOSCIUTO` / `Initial state: UNKNOWN`?** The script could not find a readable battery block. Either your battery key differs (see [Adapting for Other Logitech Headsets](#adapting-for-other-logitech-headsets)) or G HUB no longer persists the state to disk.

### Quick Setup
- Download the AutoSwitch.ps1 script from this repository.
- Open the file in a text editor (like Notepad or PowerShell ISE).
- Under the USER CONFIGURATION section, change $global:SpeakerName to match a portion of your speaker's name as it appears in Windows (e.g., "Realtek", "Creative", or "Soundbar").
- Save the file.
- Right-click the script and select **Run with PowerShell**.
**Note: This will open a PowerShell window. You must leave this window open (you can minimize it) for the switcher to work. If you close it, the script stops. For a fully invisible experience, use the Task Scheduler method below.**

On startup the script prints the detected state and the timestamp of the database entry it used, for example:

```
[-] Initial state: UNDOCKED (in use)  [entry from 2026-09-19 13:21:45 UTC]
[!] A50 Auto-Switcher v2.0 started. CTRL+C to stop.
[15:22:34] >>> DOCKED: audio -> Creative Stage SE
[15:22:42] >>> UNDOCKED: audio -> A50 Voice
```

If that timestamp is old or the state is wrong, you're reading a stale entry — see Troubleshooting.

### Run Invisibly on Startup (Task Scheduler)

To make this script run silently in the background every time you turn on your PC:
- Open **Task Scheduler** in Windows and click **Create Task**.
- **General tab:** Name the task (e.g., "Astro AutoSwitch") and check _Run only when user is logged on_.
- **Triggers tab:** Click _New_ and choose Begin the task: _At log on_.
- **Actions tab:** Click _New_ and choose Action: _Start a program_.
- Set **Program/script** to: powershell.exe
- Set **Add arguments** to: -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File "C:\Your\Path\Here\AutoSwitch.ps1" (Make sure to update the path to wherever you saved the script).

### Adapting for Other Logitech Headsets

TESTING NEEDED: This script defaults to the Astro A50. If you use a different wireless Logitech headset (e.g., G Pro X Wireless, G935), you must update the battery identifier string using the [Diagnose-GHUB.ps1](https://github.com/xAle33x/Logitech-Astro-AutoSwitcher/blob/main/Diagnose-GHUB.ps1) helper script included in this repository, or manually:

- Press Win + R, paste %LocalAppData%\LGHUB and press Enter.
- Open the settings.db file using a text editor like Notepad++.
- Press Ctrl + F and search for "battery/" — **not** for "isCharging". Since the G HUB update, the isCharging field only exists while the device is charging, so searching for it while your headset is off the base finds nothing.
- You will see one key per wireless device, e.g. "battery/a50/percentage" and "battery/g502wireless/percentage". Pick the one matching your headset.
- Open the PowerShell script and replace $global:BatteryKey = "battery/a50/percentage" with your specific key.

> **Tip:** do this comparison with the headset **on the base**, so the charging field is present and you can confirm you picked the right device.

### V2.0 Update: G HUB Compatibility Fix

A G HUB update in September 2026 changed the shape of the battery block. Previously the script could rely on reading an explicit true/false flag. Now:

- When the headset is **on the base**, the block is `{ "isCharging": true, "percentage": 95, "time": "..." }`
- When the headset is **removed**, the field is simply gone: `{ "percentage": 95, "time": "..." }`

G HUB **no longer writes `"isCharging": false`** — the *absence* of the field is the undocked signal. Any v1.x script waiting for a false value will never match it, so it detects docking but never undocking (or stops switching entirely).

v2.0 also fixes a subtler, pre-existing reliability bug: settings.db-wal is a SQLite write-ahead log containing historical pages, and its entries are **not** in chronological order. Taking "the last textual match" could return a stale state. v2.0 now collects every matching block from both settings.db and settings.db-wal, parses the ISO 8601 `time` field of each, and uses the most recent one.

Additional changes in this release:
- Balanced-brace JSON parsing replaces the old non-greedy regex, which broke on nested objects.
- Audio device IDs are resolved at switch time rather than cached at startup, fixing failures caused by the headset disappearing from Windows while powered off.
- A configurable safety poll (default 3s, with debouncing) complements the FileSystemWatcher.
- A missing audio device is now logged instead of terminating the script.

### V1.1 Update: Dual-Switch (Audio & Microphone)

The script supports switching both Playback (Speakers) and Recording (Microphone) devices simultaneously!
If you use a dedicated external microphone (like a Blue Yeti or QuadCast) alongside your headset, you can enable this feature:
- Open the script and find the \[RECORDING / MICROPHONE INPUT\] section.
- Change $global:SwitchMicrophone = $false to $true.
- Update $global:ExternalMicName with the name of your standalone microphone.
- Update $global:HeadsetMicName with your headset's mic name (defaults to "A50 Mic").
The script will now seamlessly route both your audio output and your microphone input when you dock or undock your headset. If you only care about audio output, leave it set to $false and it will ignore your microphones completely.

### License

Copyright (c) 2026 xAle33x (Bojo).
This software is provided under a Personal Use Non-Commercial License. You may use, copy, and modify this script strictly for personal purposes. Any commercial use, including redistribution, integration into commercial software, or use for providing commercial services, is strictly prohibited without the express prior written permission of the author.
