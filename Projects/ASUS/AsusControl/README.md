# ASUS Control 1.1.2

ASUS device settings in one macOS preference pane, with native SwiftUI grouped
rows and three large **Performance / Standard / Whisper** profile cards.
**Full Speed** is a separate switch. There are no tabs, System Status dashboard,
profile-switching menu, AC/battery profile rules, Low Power Mode rules, or
requested-charging-limit row. Older saved switching rules are discarded.

The current firmware profile is **ASUS X1605VA BIOS305**. Broad software naming
does not imply other devices are validated. Addresses and restrictions belong
in the driver's explicit hardware profile. AsusSMC keeps its upstream identity.

## Controls

- Fan profile cards, separate Full Speed override, and live RPM.
- Battery Care80% and temporary100% charging for24h.
- Built-in touchpad switch with inline confirmation and Fn+F6 recovery hint.
- Printed-hotkeys or F1–F12 primary behavior.
- Keyboard-backlight inactivity timeout; physical four-step cycling is preserved.

Performance is a firmware thermal policy with automatic RPM regulation; Full
Speed overrides that regulation. Current firmware policy restricts Performance
to AC+more than40% battery and Full Speed to AC. Explicit foreground requests
that cannot be applied report the restriction rather than claiming success.
There are no arbitrary RPM targets or custom curves.

## Applying changes

Foreground clicks execute the **changed control only**, directly through the
driver's queued interface. They do not wait for the agent's next five-second
cycle or restart a healthy agent. A shared transaction lock serializes pane and
agent operations. Readback confirms the result before the UI reports success.
The agent adopts confirmed foreground state without resending it.

The existing1.1.0 driver services requests on a one-second workloop timer.
The matching1.1.2 kext wakes that timer for accepted commands, removing the
extra polling wait. Firmware response and physical fan acceleration still take
time; this is not an instant-RPM guarantee. A firmware
timeout is surfaced as an error and accepted requests are never blindly retried.

The per-user agent restores chosen settings at login and handles charging
deadlines and keyboard idle restoration. It uses a live runloop for power
notifications and wakes on configuration changes. New binaries or exited jobs
are restarted; normal changes only signal the running service. It does not
install an Accessibility event tap or root daemon.

## Build and test

```sh
git clone https://github.com/samuelnotfound/Asus-X1605VA-Hackintosh-Tahoe.git
cd Asus-X1605VA-Hackintosh-Tahoe/Projects/ASUS/AsusControl
bash build.sh
bash test.sh
bash build-driver.sh
```

Requires macOS Command Line Tools. Outputs `build/ASUS Control.prefPane` and
`build/AsusSMC.kext`. The pane contains `asusctl` and `asuscontrol-agent`.
Builds ad-hoc sign locally, verify signatures and never install or launch them,
modify EFI, load a kext or register an agent. GitHub Actions repeats source
builds. No prebuilt app/DMG installation flow is added to the repository.

**Existing AsusSMC1.1.0 API2 is compatible.** For this UI update, quit System
Settings, replace the installed pane, then reopen Settings. No EFI replacement,
SSDT change or reboot is required. An already opted-in agent upgrades when the
new pane is opened. The matching1.1.2 kext is needed to remove the driver queue-polling delay.
Use the recoverable test EFI and replace its existing AsusSMC bundle for that
separate test; do not add a duplicate copy. Boot arguments and ACPI stay the same.
The earlier boot stall was unrelated to AsusSMC, as the user clarified.

## Driver requirements

Use one `AsusSMC.kext`, retaining `com.hieplpvip.AsusSMC`, with Lilu and
VirtualSMC loaded first. For the current profile:

```text
-asusctrl asusctrlprofile=x1605va305 -asusctrlsettings
```

`-asusctrlfan` is optional for legacy administrator-only fan commands. Old
`-x1605vafan`/`-x1605vafancontrol` flags remain compatible. Added hardware work
is queued on the workloop, never performed by the property handler. No added
settings discovery or polling runs at boot.

Backlight timeout needs the existing GKPC/SKPC percentage-backlight interface.
Touchpad control requires supported VoodooI2C and ATKD IANE notification support.
No new SSDT is installed. Charging limits are driver-acknowledged requests;
this firmware cannot independently report the numerical charging limit.

Source is provided as `Driver/AsusSMC-1.1.2.patch` against the pinned upstream
commit in `Driver/Upstream.json`. `build-driver.sh` applies it in isolation.
Regenerate using `bash Tools/export-driver.sh /path/to/AsusSMC`.
No published fork is required; upstream MIT licensing and notices are preserved.

## Background files and removal

```text
~/Library/Application Support/AsusControl/settings.json
~/Library/Application Support/AsusControl/agent-state.json
~/Library/Application Support/AsusControl/asuscontrol-agent
~/Library/Application Support/AsusControl/policy.lock
~/Library/LaunchAgents/com.samuelnotfound.AsusControl.Agent.plist
```

Timed charging restoration waits until the next running user session if macOS
is off or logged out when24h expires. Idle-light changes may take up to five
seconds to respond. Keep the installed pane at the same path; deleting it makes
the agent remove its login entry and exit.

Before deleting the pane, turn Battery Care off and wait for acknowledgement
if you want100% charging. Remove automatic settings with the bundled utility:

```sh
"$HOME/Library/PreferencePanes/ASUS Control.prefPane/Contents/Helpers/asusctl" service remove
```

Adjust the path for an all-users installation. Then remove the pane and, if
wanted, its Application Support folder. No EFI files are removed.

## Validation

Tests cover direct fan/Fn request isolation, no duplicate background writes,
cross-process serialization, readback mismatches, deadlines, restrictions,
idle restore, one-pane layout and host resizing. Tests use a fake driver and
offscreen windows; they never change real firmware or register a service.
Live latency and the updated pane still need user testing. Earlier code verified
physical Auto/Full Speed and RPM; profile acoustics and sleep/wake remain under
test. [YogaSMC](https://github.com/zhen-zen/YogaSMC) informed pane/driver
separation; no Lenovo EC addresses or fan-control code are used.
