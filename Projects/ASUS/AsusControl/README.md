# ASUS Control 1.1.4

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

The extended driver wakes its existing workloop for accepted requests. Firmware
response and physical fan acceleration still take time. Accepted writes are not
repeated while waiting for confirmation. Failures are isolated by control, so a
Fn-mode error cannot stop fan or charging policies.

When Performance is selected, the login agent uses Standard on battery or at
40% charge or below. It preserves your selection and restores Performance on AC
with more than40% charge. Selecting Standard or Whisper cancels that preference.
The cards show the cached active profile, separately from whether a card can be
selected. Full Speed is disabled without AC. This is userspace policy; firmware
regulates fan speed within the chosen profile using its own thermal policy.

Battery Care resends its request once after a driver session or power-source
change and after its24h deadline. Cached intents from a previous boot cannot
suppress that request. The numerical limit cannot be independently read back:
firmware acknowledgement does not prove charging stopped. Charging above80%
was reported and still requires physical retesting; no speculative EC writes
or undocumented limit encodings have been introduced.

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

Existing custom API2 drivers remain compatible with the updated pane. Quit
System Settings, replace the installed pane, then reopen Settings. An already
opted-in agent upgrades when the new pane opens. The build does not install it.

## Driver requirements

Use one `AsusSMC.kext`, keeping the upstream **1.4.1** version and
`com.hieplpvip.AsusSMC` identifier, with Lilu and VirtualSMC loaded first.
ASUS Control1.1.4 and AsusSMC1.4.1 are separate projects with separate versions;
`AsusControlAPIVersion=2` and feature revision3 identify the added interfaces.

The extended driver recognizes the supported DSDT wiring from cached table
bytes. **No fan/settings boot arguments are required.** Recognition is currently
limited to the known X1605VA BIOS305 wiring; other firmware requires validation.
Old boot arguments may be removed when using this new build. They can still be
required by an older custom kext. No SSDT change is needed. Added hardware work
is queued on the existing workloop, never performed by the property handler.
Added settings discovery/queries do not run at startup or passive polling.

Replacing a kext is a separate recoverable-EFI test; do not add a duplicate copy.
The earlier boot stall was unrelated to AsusSMC, as the user clarified.

Backlight timeout needs the existing GKPC/SKPC percentage-backlight interface.
Touchpad control requires supported VoodooI2C and ATKD IANE notification support.
No new SSDT is installed. Charging limits are driver-acknowledged requests;
this firmware cannot independently report the numerical charging limit.

Source is provided as `Driver/AsusSMC-device-settings.patch` against the pinned upstream
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
cross-process serialization, charger fallback/restoration, charge-session refresh,
power-source parsing, readback mismatches, deadlines, restrictions,
idle restore, one-pane layout and host resizing. Tests use a fake driver and
offscreen windows; they never change real firmware or register a service.
Live latency and the updated pane still need user testing. Earlier code verified
physical Auto/Full Speed and RPM; profile acoustics and sleep/wake remain under
test. [YogaSMC](https://github.com/zhen-zen/YogaSMC) informed pane/driver
separation; no Lenovo EC addresses or fan-control code are used.
