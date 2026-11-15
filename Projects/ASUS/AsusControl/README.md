# ASUS Control 1.1.1

A native macOS preference pane for ASUS device settings, with a matching
AsusSMC extension. The software name is independent of the laptop model;
firmware wiring and restrictions belong in explicit hardware profiles.
The current profile is **ASUS X1605VA, BIOS 305**. Other models are not yet
validated, even if they expose similar ASUS WMI interfaces.

The pane uses SwiftUI’s native grouped Form: leading labels, trailing controls,
system separators and backgrounds, and one scrolling content area. It adopts
the actual host size rather than keeping its initial frame.
There is no keyboard-brightness slider, microphone control, or screen-brightness
control in this project. Physical keyboard-light cycling remains unchanged.

## Settings

| Section | Features |
| --- | --- |
| Power & Performance | One profile menu (Standard, Whisper, Performance or Full Speed), live RPM, and one switching policy: Manual, power source, Low Power Mode, or both. |
| Battery Care | Request an 80% charging limit, or allow 100%; Instant Full-Charge Mode allows 100% for 24 hours before requesting 80% again. |
| Input Devices | Built-in touchpad enable/disable with inline confirmation; hotkeys or F1–F12 mode; keyboard-backlight inactivity timeout on both power sources or battery only. |
| System Status | CPU utilization, memory use, battery percentage, startup-disk capacity, fan/profile and uptime; shortcuts to Activity Monitor and Storage Settings. |

Power Mode Synchronization selects Whisper while macOS Low Power Mode is on,
then uses the configured profile when it is off. It does not change Low Power
Mode itself. The current profile restricts Performance to AC power with more
than 40% battery, and Full Speed to AC power. It does not expose arbitrary fan
RPM, custom curves or calibrated minimum/maximum fan speeds.

Charge-limit status is the **last driver-acknowledged request**, not an independent
measurement: this firmware's battery-limit status method returns capability
flags. CPU temperature, clock and voltage are not invented when unavailable.
Memory use is active + wired + compressed memory, rather than a RAM-cleaning
feature. Uptime is not Windows startup-time measurement.

## Build from source

On macOS with Command Line Tools installed:

```sh
git clone https://github.com/samuelnotfound/Asus-X1605VA-Hackintosh-Tahoe.git
cd Asus-X1605VA-Hackintosh-Tahoe/Projects/ASUS/AsusControl
bash build.sh
bash test.sh
bash build-driver.sh
```

Outputs:

- `build/ASUS Control.prefPane` — universal Intel/Apple Silicon user interface;
  install by opening the pane in Finder after building. Remove the older
  X1605VA Settings pane first if installed, to avoid duplicate preference panes.
- `build/AsusSMC.kext` — matching driver, for Intel Hackintosh systems only.
- `Contents/Helpers/asusctl` inside the pane — status and command utility.
- `Contents/Helpers/asuscontrol-agent` — optional user-session automatic settings.

The build compiles and ad-hoc signs locally. It does not install the pane,
change boot arguments, modify EFI, load a driver, or start the background agent.
GitHub Actions performs the same builds and tests; no prebuilt app download or
DMG installation flow is provided.

The driver source is exported as `Driver/AsusSMC-1.1.1.patch` against the pinned
upstream commit in `Driver/Upstream.json`. `build-driver.sh` applies it in an
isolated checkout. An already-published fork is not required. Regenerate the
patch from the separate AsusSMC checkout with:

```sh
bash Tools/export-driver.sh /path/to/AsusSMC
```

## Driver setup

The user has confirmed that the earlier boot stall was unrelated to AsusSMC.
The 1.1.0 driver boots and reports RPM, and physical Automatic/Full Speed works.
1.1.1 changes the pane and user-session policies; the driver has only a release
version/documentation update. The pane works with the existing **1.1.0 API 2**
driver, so an EFI replacement or reboot is not required for this UI update.
Firmware profile acoustics and the remaining device controls still need testing.

Use one `AsusSMC.kext`, retaining its original `com.hieplpvip.AsusSMC`
identifier. Lilu and VirtualSMC must precede it. Do not add a second copy.
Explicitly select the matching firmware profile with boot arguments:

```text
-asusctrl asusctrlprofile=x1605va305 -asusctrlsettings
```

`-asusctrlsettings` permits bounded device-setting commands from the local
console user or an administrator. It is required for the additional pane
controls and automatic settings. `-asusctrlfan` separately enables the older
administrator-only fan command interface. Legacy `-x1605vafan` and
`-x1605vafancontrol` remain accepted for existing configurations.

Keyboard timeout needs the existing percentage-backlight `GKPC`/`SKPC` ACPI
interface from `SSDT-KBLU` or the combined Assistant SSDT. Touchpad control
requires a supported VoodooI2C touchpad driver and the existing ATKD `IANE`
notification path. No new SSDT is supplied or installed by this project.
Capabilities that cannot be read stay disabled. Matching a profile name alone
does not confirm physical behavior.

## Automatic settings and removal

Reading System Status does not install a service. Enabling Battery Care,
temporary full charging, separate power-source profiles, power-mode sync,
Fn-mode persistence or a backlight timeout installs a **per-user login agent**.
It uses no Accessibility event tap or root daemon.

Choosing a profile persists it and starts the per-user agent. In Manual mode,
that one chosen profile is applied at login; source-based and Low Power Mode
switching use the same policy owner. The firmware itself varies RPM within
Standard, Whisper and Performance. Full Speed is a separate override, not the
Performance profile.

The agent samples every five seconds. Applying settings writes a new revision
and kickstarts the service, replacing an outdated or exited process. The pane
shows Applying until that revision is acknowledged. The agent confirms the
resulting profile/Fn/light cache before recording an applied intent. Requested
charging limits remain acknowledgement-only because the firmware has no numeric
limit readback. Drift from the selected automatic policy is detected; a failed
or mismatched operation stops writes for that revision and exposes Try Again.
Busy submissions can wait for the queue. An accepted write is not retried as
part of confirming its readback.

Files are consistently named:

```text
~/Library/Application Support/AsusControl/settings.json
~/Library/Application Support/AsusControl/agent-state.json
~/Library/Application Support/AsusControl/asuscontrol-agent
~/Library/LaunchAgents/com.samuelnotfound.AsusControl.Agent.plist
```

Keep the installed pane at the same path. The agent exits and removes its login
entry if that pane is removed. The 24-hour charging deadline is stored on disk:
if macOS is off or the user is logged out when it expires, the 80% request waits
until the next running user session. The firmware retains the last requested
limit meanwhile. Idle timeout may respond within five seconds of its deadline
or resumed activity. It restores the saved light level unless a physical key
has already selected another nonzero level.

Before removing the pane, stop and remove automatic policies with its bundled
utility (adjust the path if installed for all users):

```sh
"$HOME/Library/PreferencePanes/ASUS Control.prefPane/Contents/Helpers/asusctl" service remove
```

This removes the LaunchAgent first and stops it. Settings files and the copied
helper may then be removed by deleting `~/Library/Application Support/AsusControl`.
It does not change EFI or reset a firmware charging limit. To return to 100%
charging, turn Battery Care off and wait for acknowledgement before removal.

## Development and validation

The pane, utility, agent and matching source build share SemVer **1.1.1**, sourced
from `VERSION`. Device control API **2** is an independent compatibility number;
legacy API 1 property names remain for existing tools. New board support should
add an explicit profile under `AsusSMC/Models/` and validate each endpoint and
capability before exposing controls.

Local tests cover policy deadlines, power transitions, restrictions, idle
restore, protocol bounds, old-driver gating, three pane tabs, responsive widths,
signatures and the startup boundary. UI previews use fixtures and offscreen
windows. Tests do not change hardware or register the agent.

Earlier fan-only patches verified RPM and physical Auto/Full Speed on the target
laptop; thermal profiles received firmware acknowledgements. New UI hosting, profile-policy confirmation and other device controls still
need user validation after installing the updated pane.
Sleep remains unresolved. No Lenovo EC addresses or fan-control code are used;
[YogaSMC](https://github.com/zhen-zen/YogaSMC) informed the separation between
the pane and driver. Upstream AsusSMC licensing and notices are preserved.
