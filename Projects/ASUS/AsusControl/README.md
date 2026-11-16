# ASUS Control 1.1.8

ASUS device settings in one macOS preference pane, with native SwiftUI grouped
rows and three large **Performance / Standard / Whisper** profile cards.
**Full Speed** is a separate switch. There are no tabs, System Status dashboard,
profile-switching menu, per-source profile pickers, Low Power Mode rules, or
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

## How automatic fan speed works

**The laptop firmware controls automatic fan RPM.** ASUS Control selects a
thermal profile through AsusSMC and the laptop's existing ACPI/WMI interface.
It does not watch which macOS apps you open or predict when you will get busy.
As a workload produces heat, the firmware's thermal controller responds to the
hardware's thermal conditions. The exact ASUS sensor inputs, temperature
thresholds and fan curves have not been verified by this project.

| Selection | What controls the fan |
| --- | --- |
| Performance | Firmware automatically regulates RPM with cooling prioritized for demanding tasks. |
| Standard | Firmware automatically regulates RPM for everyday use. |
| Whisper | Firmware uses the quieter thermal profile; it does not promise a fixed RPM or a stopped fan. |
| Full Speed | An explicit override of normal automatic regulation. |

Selecting a profile does not set a particular RPM, and the fan does not have
to accelerate immediately if the laptop is cool. The displayed RPM is a
firmware reading. The project does not provide an arbitrary RPM slider,
custom fan curves or verified manufacturer minimum/maximum speeds.

**Profile selection is separate from firmware RPM regulation.** Performance is
selected manually on AC with more than40% battery. The login agent retires that
selection and requests Standard after a restart, AC disconnection, or a drop
below40%. Reconnecting AC or recharging does not restore Performance; select it
again. An already-active Performance profile may continue at exactly40%, but a
new activation requires more than40%.

The Performance-on-AC switch has been removed, and its retired saved flag is
ignored. Restart reset is performed by the configured post-login agent; this
project does not add a boot-time firmware write or claim Windows modern standby
is equivalent to macOS sleep. Older saved Performance selections reset once
when this policy first initializes. Closing/reopening Settings during the same
boot does not reset a newly selected Performance profile.

Firmware still regulates RPM within the chosen profile. Automatic thermal RPM
regulation does not depend on the pane staying open; policy enforcement needs
the opted-in login agent.

## Function-key switching

The Function keys selector requests Printed hotkeys or F1–F12 primary behavior
through the existing firmware Fn-lock command. It is separate from fan control
and does not add keyboard remapping or an Accessibility event tap.

On the X1605VA BIOS305 profile, the firmware bit/parameter has inverted
semantics: parameter0 selects printed actions; parameter1 selects ordinary
F1–F12. A physical F7 comparison in both modes established that the previous
labels were reversed. The extended driver now converts commands and readback
consistently and advertises `FnLockSemanticsVersion=1` (feature revision4).

The pane also translates Fn commands and cached status for the older custom
API2 driver on this exact hardware profile. You can test this correction by
replacing only the pane, without an EFI change or reboot. The compatibility
conversion is skipped when the driver advertises normalized semantics, so the
inversion is never applied twice or to unrelated ASUS profiles.

Touchpad and Function keys occupy separate grouped sections with their own
instructions. The touchpad recovery hint is **F6** in Printed hotkeys mode and
**Fn+F6** in F1–F12 mode. On this profile it follows the last accepted selection,
so a stale firmware mirror cannot show the opposite shortcut. The inline
confirmation and failure hint use the same source. Unknown mode gets a generic
touchpad-key hint rather than a guessed shortcut.

A deliberate selection sends one command even if the firmware's status mirror
already shows that mode. Saved requests are scoped to mode and driver session.

**This profile's Fn status mirror is unreliable.** The user confirmed the keys
switch physically while the mirror continues reporting the other mode.1.1.7
therefore records `FnAcceptedIntent` / `FnVerification=acknowledged`, rather than
calling a working accepted request a failure or claiming it was independently
verified. Overall state is `accepted`, distinct from `applied`. It does not poll
the stale mirror after every Fn write or resend it in later agent cycles.
Existing accepted readback-mismatch errors are migrated without another write.
Transport errors, command rejection and other control failures remain errors.

Other interfaces retain strict readback unless the driver explicitly declares
it unreliable. A future driver can supply `FnLockReadbackReliable=true` to opt
back into verification if a reliable source is added. The raw normalized mirror
is preserved in diagnostics. Acceptance alone still cannot automatically prove
physical keyboard behavior. The user confirmed switching works with1.1.6;
the updated warning handling and instructions need user testing.

The standard WMI route is also used in
[G-Helper's Fn-lock implementation](https://github.com/seerge/g-helper/blob/main/app/Input/InputDispatcher.cs);
its USB keyboard fallback is not assumed compatible with this PS/2 keyboard.

## Applying changes

Foreground clicks execute the **changed control only**, directly through the
driver's queued interface. They do not wait for the agent's next five-second
cycle or restart a healthy agent. A shared transaction lock serializes pane and
agent operations. Reliable readback confirms the result; the documented Fn
exception records acceptance separately without claiming verification.
The agent adopts confirmed foreground state without resending it.

The extended driver wakes its existing workloop for accepted requests. Firmware
response and physical fan acceleration still take time. Accepted writes are not
repeated while waiting for confirmation. Failures are isolated by control, so a
Fn-mode error cannot stop fan or charging policies.

The cards show the cached active profile separately from availability. Full
Speed is disabled without AC. A click shows one16-point native spinning progress
indicator beside its switch/menu, or at the lower-right of the requested fan
card. Indicators disappear on completion or failure; full-pane startup/retry
uses the same spinner. The “Applying settings…” banner is removed. Errors and
timeout recovery remain visible. Native grouped rows and card layout are kept.

Battery Care resends its request once after a driver session or power-source
change and after its24h deadline. Cached intents from a previous boot cannot
suppress that request. The numerical limit cannot be independently read back:
firmware acknowledgement does not prove charging stopped. Charging above80%
was reported and still requires physical retesting; no speculative EC writes
or undocumented limit encodings have been introduced.

The per-user agent applies saved settings at login, resets a previous
Performance selection to Standard, and handles charging
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
ASUS Control1.1.8 and AsusSMC1.4.1 are separate projects with separate versions;
`AsusControlAPIVersion=2` and feature revision4 identify the added interfaces.

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
