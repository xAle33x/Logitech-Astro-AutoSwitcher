# Logitech / Astro Auto-Audio Switcher

A lightweight, event-driven PowerShell script that automatically switches Windows default audio output when you dock or undock your Logitech headset (specifically built and tested with the Astro A50 Gen5).

## Features
* **Zero-Click Switch:** Automatically routes audio to your speakers when the headset is charging, and instantly back to the headset when lifted.
* **Event-Driven:** Uses `System.IO.FileSystemWatcher` to sit at 0% CPU usage in the background until G HUB physically writes to its database.
* **Conflict-Free:** Implements regex block-isolation to prevent false audio switches if you plug in another Logitech device to charge (like a G502 Lightspeed mouse).
* **Auto-Setup:** Automatically installs the required `AudioDeviceCmdlets` module for the current user on its first run.

## Prerequisites
* Windows OS
* Logitech G HUB software (Note: Not compatible with the legacy Astro Command Center)
* Windows PowerShell
* If this is your first time ever running a PowerShell module installation, a prompt might ask you to install the 'NuGet provider'. Simply press Y and hit Enter to allow it.

## Dependencies
This script relies on the [AudioDeviceCmdlets](https://github.com/frgnca/AudioDeviceCmdlets) module created by *frgnca* to interact with Windows sound settings. 

**Note on Auto-Installation:** If you do not already have this module, the script is designed to automatically download and install it from the official Microsoft PowerShell Gallery for the *Current User* (no admin rights required) during its very first run.

## Troubleshooting 
**Script closes immediately or shows a red error?**
Windows protects your PC by blocking scripts downloaded from the internet by default. To fix this, follow these steps:

1. **Unblock the downloaded file:** 
   Right-click the `AutoSwitch.ps1` file, select **Properties**, check the **Unblock** box at the bottom of the *General* tab, and click **OK**.
   *(Alternatively, run `Unblock-File -Path .\AutoSwitch.ps1` in PowerShell).*

2. **Enable local script execution:** 
   If the script still doesn't run, your system might have PowerShell scripts completely disabled. 
   Open PowerShell as Administrator, paste this command: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`, press `Y` to confirm, and try running the script again.

## Quick Setup
1. Download the `AutoSwitch.ps1` script from this repository.
2. Open the file in a text editor (like Notepad or PowerShell ISE).
3. Under the `USER CONFIGURATION` section, change `$global:SpeakerName` to match a portion of your speaker's name as it appears in Windows (e.g., `"Realtek"`, `"Creative"`, or `"Soundbar"`).
4. Save the file.
5. Right-click the script and select **Run with PowerShell**.

**Note: This will open a PowerShell window. You must leave this window open (you can minimize it) for the switcher to work. If you close it, the script stops. For a fully invisible experience, use the Task Scheduler method below.**

## Run Invisibly on Startup (Task Scheduler)
To make this script run silently in the background every time you turn on your PC:
1. Open **Task Scheduler** in Windows and click **Create Task**.
2. **General tab:** Name the task (e.g., "Astro AutoSwitch") and check *Run only when user is logged on*.
3. **Triggers tab:** Click *New* and choose Begin the task: *At log on*.
4. **Actions tab:** Click *New* and choose Action: *Start a program*.
5. Set **Program/script** to: `powershell.exe`
6. Set **Add arguments** to: `-WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File "C:\Your\Path\Here\AutoSwitch.ps1"` (Make sure to update the path to wherever you saved the script).

## Adapting for Other Logitech Headsets
TESTING NEEDED: This script defaults to the Astro A50. If you use a different wireless Logitech headset (e.g., G Pro X Wireless, G935), you must update the battery identifier string following this guide or [BatteryKeyFinder.ps1](https://github.com/xAle33x/Logitech-Astro-AutoSwitcher/blob/main/BatteryKeyFinder.ps1) helper script included in this repository:
1. Press `Win + R`, paste `%LocalAppData%\LGHUB` and press Enter.
2. Open the `settings.db` file using a text editor like Notepad++.
3. Press `Ctrl + F` and search for `"isCharging"`.
4. Look at the lines immediately above the match to find your specific battery key (it usually looks like `"battery/device_1234/percentage"` or `"battery/gprox/percentage"`).
5. Open the PowerShell script and replace `$global:BatteryKey = "battery/a50/percentage"` with your specific key.
   
## V1.1 Update: Dual-Switch (Audio & Microphone)
The script now supports switching both Playback (Speakers) and Recording (Microphone) devices simultaneously! 

If you use a dedicated external microphone (like a Blue Yeti or QuadCast) alongside your headset, you can enable this feature:
1. Open the script and find the `[RECORDING / MICROPHONE INPUT]` section.
2. Change `$global:SwitchMicrophone = $false` to `$true`.
3. Update `$global:ExternalMicName` with the name of your standalone microphone.
4. Update `$global:HeadsetMicName` with your headset's mic name (defaults to `"A50 Mic"`).

The script will now seamlessly route both your audio output and your microphone input when you dock or undock your headset. If you only care about audio output, leave it set to `$false` and it will ignore your microphones completely.

## License
Copyright (c) 2026 xAle33x (Bojo). 

This software is provided under a Personal Use Non-Commercial License. You may use, copy, and modify this script strictly for personal purposes. Any commercial use, including redistribution, integration into commercial software, or use for providing commercial services, is strictly prohibited without the express prior written permission of the author.
