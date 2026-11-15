# ASUS Control 1.1.0

A native macOS preference pane for ASUS device settings, with a matching
AsusSMC extension. The software name is independent of the laptop model;
firmware wiring and restrictions belong in explicit hardware profiles.
The current profile is **ASUS X1605VA, BIOS 305**. Other models are not yet
validated, even if they expose similar ASUS WMI interfaces.

The existing MyASUS-style profile cards and native AppKit controls are retained.
The pane now scrolls vertically and adapts to the System Settings content width.
There is no keyboard-brightness slider, microphone control, or screen-brightness
control in this project. Physical keyboard-light cycling remains unchanged.

## Settings

| Section | Features |
| --- | --- |
| Power & Performance | Performance, Standard and Whisper; live fan RPM; Auto/Full Speed; separate AC and battery profiles; optional synchronization with macOS Low Power Mode. |
| Battery Care | Request an 80% charging limit, or allow 100%; Instant Full-Charge Mode allows 100% for 24 hours before requesting 80% again. |
| Input Devices | Built-in touchpad enable/disable with inline confirmation; hotkeys or F1–F12 mode; keyboard-backlight inactivity timeout on both power sources or battery only. |
| System Status | CPU utilization, memory use, battery percentage/health, startup-disk capacity, fan/profile and uptime; shortcuts to Activity Monitor and Storage Settings. |

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

The driver source is exported as `Driver/AsusSMC-1.1.0.patch` against the pinned
upstream commit in `Driver/Upstream.json`. `build-driver.sh` applies it in an
isolated checkout. An already-published fork is not required. Regenerate the
patch from the separate AsusSMC checkout with:

```sh
bash Tools/export-driver.sh /path/to/AsusSMC
```

## Driver setup

**1.1.0 is an unverified hardware-test candidate.** The earlier 1.0.0 driver
froze before login. Later source removes the added keyboard discovery and
settings queries from startup and periodic polling, and restores the upstream
bundle identifier. Compilation and fixture tests do not establish a boot fix.
Keep the working recovery EFI when arranging a deliberate test boot.

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

The agent applies configured policies after login and samples every five
seconds. Requests use the driver's serial workloop queue. A firmware timeout
stops further automatic requests for that configuration; changing a setting or
starting a new session allows another attempt. Busy submissions can wait for
the queue, but accepted requests are never automatically resubmitted.

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

The pane, utility, agent and matching driver share SemVer **1.1.0**, sourced
from `VERSION`. Device control API **2** is an independent compatibility number;
legacy API 1 property names remain for existing tools. New board support should
add an explicit profile under `AsusSMC/Models/` and validate each endpoint and
capability before exposing controls.

Local tests cover policy deadlines, power transitions, restrictions, idle
restore, protocol bounds, old-driver gating, three pane tabs, responsive widths,
signatures and the startup boundary. UI previews use fixtures and offscreen
windows. Tests do not change hardware or register the agent.

Earlier fan-only patches verified RPM and physical Auto/Full Speed on the target
laptop; thermal profiles received firmware acknowledgements. New battery,
Fn-mode, touchpad, timeout and hosting behavior still need hardware validation.
Sleep remains unresolved. No Lenovo EC addresses or fan-control code are used;
[YogaSMC](https://github.com/zhen-zen/YogaSMC) informed the separation between
the pane and driver. Upstream AsusSMC licensing and notices are preserved.
