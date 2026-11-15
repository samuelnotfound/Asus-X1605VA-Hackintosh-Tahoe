# X1605VA Settings — 1.0.1

**Boot regression:** 1.0.0 froze before login on the X1605VA. Keep a working
EFI available. Version 1.0.1 removes the added settings discovery/reads from
startup and periodic polling, and restores the original AsusSMC identifier.
It is a recovery candidate; a successful boot has not yet been verified.

A separate macOS preference pane for the ASUS Vivobook X1605VA, BIOS 305.
It follows MyASUS Device Settings grouping and profile names using native
AppKit controls. It contains only fan/thermal settings and keyboard backlight.

## Power & Performance

- **Fan Profile:** Performance, Standard, or Whisper, with the active firmware
  profile selected when readback is available.
- **System Fan:** live RPM, “Stopped · 0 RPM,” or “Unavailable.”
- **Fan control:** Automatic or Full Speed. This reflects the last acknowledged
  request in the driver session, not independently measured firmware mode.

Selecting a profile first returns the fan to Automatic, then applies the
profile under one administrator authorization. A profile affects thermal/power
policy as well as cooling; it is not a fixed RPM setting. There is no arbitrary
RPM slider, curve editor, or invented minimum/maximum speed.

## Input Device Settings

- **Keyboard Backlight:** one continuous 0–100% slider.
- Physical keyboard control retains its existing four steps.
- Slider updates stay local while dragging and coalesce firmware requests.
  The pane requests readback while selected; added firmware reads never run
  automatically during driver startup or ordinary fan polling.

No microphone, screen-brightness, trackpad, or keyboard remapping controls are
included. Accessibility and Input Monitoring permission are not requested.
There is no login agent or automatic settings restore. Opening the pane reads
state without changing fan/backlight settings. Keyboard control uses the existing percentage-backlight ACPI methods,
not CoreBrightness, raw EC offsets, or the old helper application.

## Build from source

On the X1605VA with macOS and Command Line Tools installed:

```sh
git clone https://github.com/samuelnotfound/Asus-X1605VA-Hackintosh-Tahoe.git
cd Asus-X1605VA-Hackintosh-Tahoe
bash Projects/ASUS/X1605VASettings/build.sh
bash Projects/ASUS/X1605VASettings/test.sh
```

Output: `Projects/ASUS/X1605VASettings/build/X1605VA Settings.prefPane`.
The build is ad-hoc signed locally. It does not install or open the pane.
Double-click that bundle to ask macOS to install it in PreferencePanes, then
open it from System Settings. System Settings hosting on Tahoe still needs a
user test; loading in a test host does not establish that integration.
The local build does not require downloaded prebuilt apps or a DMG.

The pane follows Apple's [PreferencePanes interface](https://developer.apple.com/documentation/preferencepanes).
Section names and profile presentation follow [MyASUS Device Settings](https://www.asus.com/support/faq/1045651/).

## Driver setup

Requires **X1605VA AsusSMC fork 1.0.1**, control API 1. The older 1.4.2 test
kext has fan monitoring/control but lacks this pane's profile/backlight API,
so controls remain disabled with that version.

Build the driver from pinned upstream source plus the included source patch:

```sh
bash Projects/ASUS/X1605VASettings/build-driver.sh
```

Output: `Projects/ASUS/X1605VASettings/build/AsusSMC.kext`.
The patch retains upstream MIT licensing. For a separate local checkout,
`ASUSSMC_SOURCE=/absolute/path/to/AsusSMC` uses that source instead; its
`VERSION` must match the settings release.

For a deliberate test boot, replace the existing AsusSMC bundle in the test EFI
instead of adding a second copy. Keep Lilu and VirtualSMC before it. Preserve
the working configuration and keyboard patches. `-x1605vafan` enables
monitoring/backlight; `-x1605vafancontrol` additionally permits fan settings.
Build scripts never change EFI or boot arguments. Avoid overlapping fan/ALS
keys from SMCSuperIO or SMCLightSensor in the test configuration.

Keyboard control requires `GKPC` and `SKPC` on the EC device, already supplied
by `EFI/OC/ACPI/SSDT-KBLU.aml` or the combined Assistant SSDT. No additional
SSDT or microphone-LED driver is needed by this pane.

Administrator fan changes use the bundled narrow command utility through the
macOS authorization dialog. No password is stored. Keyboard changes are
limited to the local console user or administrator by the driver.

## Versioning and development

The first release was 1.0.0; the current recovery candidate is **1.0.1**.
`VERSION` supplies the pane and bundled utility
versions. `Driver/Upstream.json` pins the matching driver release and upstream
commit. The fork has a matching `VERSION` and retains the upstream
`com.hieplpvip.AsusSMC` identifier for replacement compatibility. The 1.0.0
identifier change has been reverted. Control API 1 is independent of release numbering. There
is no separately versioned installer/helper product.

The driver changes live in a separate AsusSMC checkout. Until its GitHub fork
is available, this patch makes the complete release reproducible from
upstream. `Tools/export-driver.sh` exports the changes without modifying that
checkout. See `docs/DEVELOPMENT-CONTINUATION.md` at the repository root.

## Validation

Checks cover signatures, versions, command boundaries, signed/unsigned IDs,
pane loading, unavailable/old drivers, profile selection and backlight
readback. Offscreen light/dark previews are saved in `build/previews`.
Driver tests cover RPM scaling, stopped fans, unsupported replies, encoding
overflow and Vivobook profile values.

The preceding fan-only driver verified live RPM and physical Auto/Full Speed behavior
on X1605VA BIOS 305. The new pane, keyboard requests, profile readback and
System Settings integration need testing on the matching 1.0.1 driver.
Fixture tests do not establish successful boot, hardware writes, or sleep/wake
behavior. A boot-path regression check prevents new settings discovery/queries
from being reintroduced into startup or the periodic callback.

## Credits and license

Original settings code: samuelnotfound, MIT License; see `LICENSE` here.
AsusSMC retains its upstream MIT license and copyright notices.
[YogaSMC](https://github.com/zhen-zen/YogaSMC) informed the pane/driver
separation; no Lenovo EC addresses or fan-control code are used.
