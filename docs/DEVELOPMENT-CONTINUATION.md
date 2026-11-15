# ASUS Control continuation — 2026-11-14

Continue in `samuelnotfound/Asus-X1605VA-Hackintosh-Tahoe` (public).
Active source: `Projects/ASUS/AsusControl`, **ASUS Control 1.1.1**.
The former `X1605VASettings` project has been renamed, not duplicated.
Deprecated Assistant and the board-specific touchpad UEFI driver are separate;
this task did not rename those unrelated projects or the hardware EFI repo.
Never publish raw diagnostics, private identity values, reference documents,
chat transcripts, or ignored build/recovery files.

## User intent and implementation

Latest user request supersedes the older card design: use native SwiftUI
Form(.grouped), matching macOS Appearance/Desktop & Dock alignment and grouping.
Remove overlapping fan controls. Keep one profile-switching policy and show
only relevant profile choices. No keyboard brightness slider; keep physical
four-step backlight cycling. The NSHostingView adopts its container on attach
and autoresizes; the Form owns scrolling. Product/code/build names are now broad:
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
Complete source is exported as `Driver/AsusSMC-1.1.1.patch`; build-driver.sh
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

## Boot history correction and current hardware evidence

The user explicitly corrected the earlier diagnosis: the boot stall was NOT
caused by AsusSMC. Do not continue attributing it to the kext or describe these
builds as a proven boot-regression fix. Earlier diagnostics did not establish
that fault either. The current running driver is confirmed AsusSMC1.1.0, API2,
with live RPM and thermal-profile cache. The user confirms physical Auto/Full
Speed works. 1.1.1 changes the userspace UI/policies; kext behavior is unchanged
apart from version metadata. Existing1.1.0 API2 works with the1.1.1 pane.

Previous approved recovery restored SYSTEM from stock OPENCORE1.4.1 while the
cause was uncertain. Preserve that historical fact and ignored backups, but it
is no longer the current running-driver state. No EFI or loaded driver was
changed in1.1.1 development. No new SSDT is needed.

## Saved profile problem and1.1.1 fix

Read-only inspection found the1.1.0 agent alive and updating its state, while
ThermalIntent described a different requested profile from cached firmware
readback. The old pane also kept Saved/Waiting indefinitely. This does not
prove the firmware profile endpoint fails; Auto/Full is a separate command.

1.1.1 records an applied policy only after readback confirms it. Policy drift
is detected. A failed/mismatched operation halts that revision and presents
Try Again. Configuration changes get a UUID revision and kickstart the service,
so a loaded-but-exited job or outdated agent cannot silently swallow work.
The pane upgrades an already opted-in agent when opened. Tests use injected
send/read callbacks and never install/start an agent or issue live writes.

Manual now means one chosen profile, persisted by the agent. Source mode
shows only AC/battery choices; Low Power Mode mode shows one normal profile
with Whisper override; combined mode retains both. Full Speed is a fourth
profile-menu choice that sets the separate override; Performance remains an
automatically regulated firmware thermal policy. No duplicate cards, separate
fan-mode popup, or two competing policy switches remain.

## Validation / next hardware step

Local build checks pane/utility/agent universal binaries and matching Intel
kext, signatures, versions, protocol sentinels/bounds, startup contract,
policy deadlines/transitions/idle restore, capability gating and offscreen
480/660/900px layouts at900px height in light/dark. Tests use fixtures and never write hardware
or start a service. GitHub Actions repeats source builds; no prebuilt app/DMG
installation flow is added.

Next: install only the updated pane and reopen System Settings. The existing
1.1.0 driver is compatible. Verify full-height hosting, native grouped rows,
profile readback after applying and AC/battery/LPM transitions. Remaining
battery/Fn/touchpad/timeout behavior and sleep/wake still need user validation.
Do not present fixture/build success as physical validation.
