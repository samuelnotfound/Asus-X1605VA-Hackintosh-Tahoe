# X1605VA Tahoe development — 2026-11-14

Continue settings development here, in
`samuelnotfound/Asus-X1605VA-Hackintosh-Tahoe`. It is public. The former private
Hackintosh repository contains earlier fan work; do not copy its raw diagnostics
or conversation into this repository.

## Current scope and release

`Projects/ASUS/X1605VASettings` is a separate preference-pane project. Release
1.0.0 had a boot regression; 1.0.1 is an unverified recovery candidate.
The requested UI follows MyASUS Device Settings: Power & Performance
with Performance/Standard/Whisper cards, live fan RPM and Auto/Full Speed; Input
Device Settings with a keyboard-backlight slider. No microphone, screen
brightness, trackpad, event tap, Accessibility gate, or login service is added.
Keep the deprecated Assistant project separate and preserve existing ACPI.

Pane and bundled command utility derive versions from VERSION. The matching
AsusSMC fork uses 1.0.1 and restores upstream `com.hieplpvip.AsusSMC`, retaining
the service class and bundle filename. The 1.0.0 identity change has been
reverted along with added startup work. Control API 1 is independent of
SemVer. The older installed custom 1.4.2 kext lacks the new status API; the pane
disables its controls and explains the required update with that driver.

## Driver source

The separate AsusSMC checkout is based on hieplpvip/AsusSMC commit
`c15d2f297c86b65a3cb866cc2bcece595c136417`, branch `x1605va-1.x`.
The requested GitHub fork could not be created: the connector has no fork
operation, local Git has no noninteractive authentication, and the browser
fork page requires sign-in. The user chose to continue the local build.
Do not claim `samuelnotfound/AsusSMC` is published until verified.

The complete driver source changes are also provided as
`Driver/AsusSMC-1.0.1.patch` against the pinned upstream commit. Thus the project
builds without an existing GitHub fork. `build-driver.sh` applies the patch in
an isolated build checkout. `Tools/export-driver.sh` regenerates it from the
separate AsusSMC checkout, including staged new source files.

The patches include the three working fan changes: fix VirtualSMC registration
order, poll independently of ALS, use the BIOS 305 WMI RPM path, and queue
root-only fan writes on the workloop. Added in 1.0.0: thermal-profile readback,
keyboard-backlight cached readback and queued writes through GKPC/SKPC,
capability/API properties, protocol tests and a Command Line Tools build script.
In 1.0.1, neither startup nor the periodic callback performs added settings
discovery/queries. These happen only after a local-user settings-refresh
request. The pane requests readback while open; no login agent starts it.
A read timeout stops further refresh requests until pane reselection.
No fan/profile/backlight setting is written automatically at startup.

Fan properties preserve the older fanctl request/completion interface. Keyboard
requests have separate property names, use the same single queue, and require
local console-user or administrator privilege. Arbitrary methods/EC offsets
cannot be submitted. Explicit readback uses SettingsCommand=1 and
SettingsRequestID on the same queue, with separate completion properties.
Fan mode remains Auto/Full Speed, not arbitrary RPM.
Selecting a thermal profile in the pane sends Auto then the profile under one
administrator authorization. Nothing persists or restores settings on login.

## Firmware facts

Target tested: ASUS X1605VA, i5-13500H, BIOS 305.
CPU fan DSTS 0x00110013 returns presence bit plus RPM/100; multiply low16 by100.
Reject 0xFFFFFFFE and 0xFFFFFFFF before presence-bit interpretation.
Vivobook profile endpoint 0x00110019: 0 Standard, 1 Whisper, 2 Performance.
ROG profile 0x00120075 and custom curve endpoints 0x00110024/25 are unsupported
on this firmware. No verified arbitrary-RPM target or nominal min/max query.
Observed fan readings include stopped and approximately 5,700–5,800 RPM at full
speed; these are observations, not calibrated manufacturer bounds.

Keyboard GKPC/SKPC already exist in the percentage-backlight SSDT-KBLU shipped
in this repository or the combined Assistant SSDT. Do not add Lenovo EC
addresses from YogaSMC. No additional SSDT is required by this project.
The original AsusSMC license and notices remain in the fork; settings code has
its own MIT license. YogaSMC is an architectural reference only.

## Boot regression and recovery

The user confirmed 1.0.0 freezes in verbose boot before login. The attachment
is a WindowServer WATCHDOG stackshot at 15:21 after about 1,800 seconds uptime,
preceding the new driver build. It does not identify this boot failure or prove
a particular fault. Do not label it an AsusSMC kernel panic or infer a graphics
cause without matching symbols/evidence.

Read-only inspection found the running AsusSMC is upstream 1.4.1. Mounted
OPENCORE has that original kext and no X1605VA fan flags. SYSTEM contains the
failing com.samuelnotfound.AsusSMC 1.0.0 and both fan flags. Its signature passes
verification and its binary is an x86_64 kext bundle. No volume was modified.
Preserve OPENCORE as the working boot option.

1.0.1 removes keyboard-method discovery from start(), removes added settings
reads from the periodic callback, and restores the original identifier.
This isolates added startup work; it is not a proven root cause or confirmed
boot fix. A structural test guards this boundary. Prior fan-only 1.4.2 source
was also rebuilt under ignored build/Recovery as a local fallback. That rebuilt
binary has not itself been boot-tested. The existing recovery EFI remains the
established boot option.

## Validation and next test

Local builds and tests cover the kext, unsigned/signed IDs, decoder error
sentinels and encoding bounds, pane loading, old-driver gating, profile
selection, keyboard readback, versions and signatures. UI tests use status
fixtures and offscreen views; they do not make firmware writes.
The preceding driver verified live fan RPM and physical Auto/Full Speed on the
laptop. Thermal-profile commands received firmware acknowledgements; profile
acoustics under matched workloads are not established.

The 1.0.1 candidate needs a deliberate test boot, first with the pane closed.
Only after boot is established should post-login settings reads be tested: verify API1,
profile readback, keyboard percentage changes and physical key updates, then
the preference pane in Tahoe System Settings. Offscreen loading does not prove
System Settings hosting or hardware control. Sleep remains unresolved; do not
claim this release fixes it. No live EFI was modified or new kext loaded.

Build instructions are in the project README. GitHub Actions builds the pane
and matching patched driver, but no prebuilt app/DMG download flow is added.
