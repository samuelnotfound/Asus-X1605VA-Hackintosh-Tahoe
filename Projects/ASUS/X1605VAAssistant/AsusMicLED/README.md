# AsusMicLED

Minimal Fn+F9 microphone mute support for the **ASUS Vivobook X1605VA** on
macOS.

> **Experimental:** This project is separate from the deprecated
> [X1605VA Assistant](../README.md) and has not been tested.

## Components

| Component | Role |
| :--- | :--- |
| **SSDT-AsusMicLED** | On Fn+F9, toggles the orange mic LED GPIO |
| **AsusMicLED.kext** | Userspace bridge (`GLED` / `SLED`) |
| **micled-agent** | Keeps CoreAudio mute in sync with the LED; menu-bar **Unmute** when muted |

This is not a full menu-bar app. It does not use `CGEventTap` or require
Accessibility permission.

## Requirements

- macOS with Xcode Command Line Tools
- OpenCore
- DSDT rename enabled: **`_Q16` → `XQ16`**
- [MacKernelSDK](https://github.com/acidanthera/MacKernelSDK) to build the kext
- `iasl` to compile the SSDT

## Build from source

```bash
export MAC_KERNEL_SDK=/path/to/MacKernelSDK
export IASL=iasl
./build.sh
```

The build creates:

- `AsusMicLED.kext`
- `micled-agent`
- `ledctl` (optional LED control CLI)
- `EFI/OC/...` OpenCore-ready files

## Install and configure

1. Copy into your EFI:
   - `build/EFI/OC/Kexts/AsusMicLED.kext` → `EFI/OC/Kexts/`
   - `build/EFI/OC/ACPI/SSDT-AsusMicLED.aml` → `EFI/OC/ACPI/`
2. Enable the kext and SSDT in `config.plist`, then reboot.
3. Install the agent:

```bash
sudo cp build/micled-agent /usr/local/bin/
```

Create `~/Library/LaunchAgents/com.x1605va.micled.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.x1605va.micled</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/micled-agent</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>5</integer>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.x1605va.micled.plist
```

Use `launchctl unload` with the same plist path before removing or replacing
the agent.

## Usage and troubleshooting

- **Fn+F9** — toggles mute (LED + CoreAudio)
- **Muted** — red slashed-mic in the menu bar; click → **Unmute**
- **Unmuted** — status item hidden

```bash
micled-agent --debug
micled-agent --invert
ledctl
ledctl 0
ledctl 1
```

Use `--invert` if the LED polarity is reversed. `ledctl` reads the current
state without an argument and forces the LED off or on with `0` or `1`.

## Uninstall

Run **Uninstall.command** in Terminal, then remove these files from the EFI:

- `EFI/OC/Kexts/AsusMicLED.kext`
- `EFI/OC/ACPI/SSDT-AsusMicLED.aml`

## Layout

```
AsusMicLED/
  ACPI/SSDT-AsusMicLED.dsl
  Driver/          # kext sources
  Agent/           # micled-agent.m, mic-mute, ledctl
  build.sh
  Uninstall.command
  README.md
```
