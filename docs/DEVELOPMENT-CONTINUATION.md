# ASUS Control continuation — 2026-11-14

Continue in `samuelnotfound/Asus-X1605VA-Hackintosh-Tahoe` (public).
Active source: `Projects/ASUS/AsusControl`, **ASUS Control 1.1.0**.
The former `X1605VASettings` project has been renamed, not duplicated.
Deprecated Assistant and the board-specific touchpad UEFI driver are separate;
this task did not rename those unrelated projects or the hardware EFI repo.
Never publish raw diagnostics, private identity values, reference documents,
chat transcripts, or ignored build/recovery files.

## User intent and implementation

Preserve the existing MyASUS-style pane design. The supplied document is a
feature reference only. Remove the keyboard brightness slider; keep physical
four-step backlight cycling. Adapt pane width with Auto Layout, vertical
scrolling and compact card stacking. Product/code/build names are now broad:
ASUS Control, AsusControlPane, asusctl, asuscontrol-agent.

1.1.0 adds battery care80/100, temporary100 for24h, split AC/battery profiles,
Low Power Mode→Whisper sync, VoodooI2C touchpad lock, Fn primary mode,
keyboard-backlight timeout and public-API system dashboard. No microphone or
screen brightness. No CPU temperature/voltage/frequency fabrication, RAM purge
or Windows power setting is implied.

Automatic policies use a per-user LaunchAgent only after a feature is enabled.
Settings/helper/state live in `~/Library/Application Support/AsusControl`;
LaunchAgent label `com.samuelnotfound.AsusControl.Agent`. Agent polls at5s,
uses explicit requests, deduplicates policy intents, and stops retrying rejected
firmware requests for that configuration. Accepted requests are never retried.
If a24h deadline expires while logged out/off, restore80 at next agent session.
CLI `asusctl service remove` clears policies and removes the LaunchAgent.
Builds/tests never register it. See project README for paths and limitations.

## Driver source and names

Separate local AsusSMC checkout, branch `asus-control-1.x`, based on upstream
`hieplpvip/AsusSMC` commit `c15d2f297c86b65a3cb866cc2bcece595c136417`.
The requested GitHub fork could not be created: connector has no fork operation,
local Git no authentication, browser signed out. User chose local build.
Do not claim `samuelnotfound/AsusSMC` exists or is published until verified.
Complete source is exported as `Driver/AsusSMC-1.1.0.patch`; build-driver.sh
applies it in an isolated checkout, so that fork is not a prerequisite.

Keep bundle `AsusSMC.kext`, service AsusSMC and upstream identifier
`com.hieplpvip.AsusSMC`. New API properties use AsusControl prefix; legacy
X1605VA aliases remain compatibility-only. API2 adds bounded DeviceCommand
1..11 with local-console/admin privilege and explicit settings opt-in.
Original fan commands remain administrator-only. All command families share a
single atomic workloop queue with separate completion properties.

Generic boot setup: `-asusctrl asusctrlprofile=x1605va305 -asusctrlsettings`.
Optional `-asusctrlfan` for legacy root fan commands; old fan flags accepted.
Only hardware profile is **X1605VA BIOS305**; addresses and restrictions live
in `AsusSMC/Models/X1605VA305.hpp`. Broader naming is not compatibility evidence.
No new SSDT: keyboard timeout needs existing GKPC/SKPC interface; touchpad uses
IANE(0x6B) and typed VoodooI2C Boolean state queries.

## Firmware facts

Fan DSTS0x00110013: presence + low16×100RPM; reject FFFFFFFE/FFFFFFFF and fpe2
overflow, stopped0 valid. DEVS0 Auto/1 Full only. Thermal0x00110019:
Standard0/Whisper1/Performance2. No supported ROG profile/custom curve endpoints
or calibrated min/max query. Earlier fan-only code physically verified RPM and
Auto/Full (observed~5700–5800RPM, not manufacturer limits). Profiles were acked,
not comparatively tested under matched loads.

Battery0x00120057 DSTS reports support flags, not numeric limit. DEVS80/100
only; requested limit is an acknowledgement cache. Do not guess the special
0x80 firmware encoding. Fn0x00100023 accepts exact10000/10001 status;
DEVS0 normal/1 hotkeys. Profile policy uses AC+>40% battery for Performance
and AC for Full. Dashboard uses public macOS data; uptime replaces Windows
startup timing. YogaSMC informed pane/driver separation only; no Lenovo EC code.

## Boot regression and recovery (preserve)

1.0.0 froze in verbose boot before login. Its attachment is an older
WindowServer watchdog report at15:21 after~1800s uptime, predating that build;
it neither identifies the fault nor proves a graphics/AsusSMC panic.
1.0.1 removed added keyboard discovery and settings queries from startup and
periodic polling, restoring the original identifier. 1.1.0 retains that boundary
and suppresses upstream's automatic80% battery write for the selected profile.
New settings run only on explicit queued userspace requests after login.
No physical boot fix is established by structural tests.

Previous approved recovery restored SYSTEM's AsusSMC.kext byte-for-byte from
working OPENCORE stock1.4.1. Both configs and OPENCORE were unchanged. Backups
are ignored under `AsusControl/build/Recovery/Boot-recovery-20261114`.
Running driver is stock1.4.1, so hardware controls in the candidate pane are
expected to be unavailable. Do not automatically install the candidate.
No live EFI or loaded driver was changed during1.1.0 development.

## Validation / next hardware step

Local build checks pane/utility/agent universal binaries and matching Intel
kext, signatures, versions, protocol sentinels/bounds, startup contract,
policy deadlines/transitions/idle restore, capability gating and offscreen
640/480/900px layouts in light/dark. Tests use fixtures and never write hardware
or start a service. GitHub Actions repeats source builds; no prebuilt app/DMG
installation flow is added.

Next: arrange a deliberate recoverable test boot with matching driver and pane
closed. Establish boot before explicitly querying settings, then test each
capability independently before opting into background policies. Physical
battery/Fn/touchpad/timeout behavior, System Settings hosting and sleep/wake
remain unverified. Do not present build success as hardware validation.
