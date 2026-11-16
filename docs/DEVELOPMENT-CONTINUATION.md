# ASUS Control continuation — 2026-11-15

Public repository `samuelnotfound/Asus-X1605VA-Hackintosh-Tahoe`.
Project `Projects/ASUS/AsusControl`, pane/CLI/agent1.1.7. Keep software names
broad. Only X1605VA BIOS305 wiring is currently profiled. Do not publish private
diagnostics, identities, raw ACPI tables, ignored backups or transcripts.

## Current user decisions

- One transparent native SwiftUI grouped scrolling form; no tabs/dashboard.
- Keep three large fan-profile cards and use the user's Windows description
  text: Dynamic Performance maximizes cooling for demanding tasks, Standard
  dynamically selects fan speed for everyday tasks, Whisper minimizes noise.
- Remove duplicate inner ASUS Control heading and Current function-key mode row.
- Full Speed separate switch, disabled/gray without AC. Active profile remains
  explicit/legible independently of whether a profile is available to select.
- No profile-switching UI, custom AC/battery rules or Low Power Mode override.
- Latest correction: preserve Performance selection, use Standard when off AC
  or at<=40%, restore Performance when eligible AC returns. Earlier answer to
  keep Standard was superseded. Selecting another card replaces the preference.
- Keep Battery Care/24h full charge, touchpad confirmation, Fn mode, keyboard
  idle timeout. No requested-limit row, brightness slider, microphone or remaps.
- Keep AsusSMC upstream version unchanged; no required boot arguments.
- No desktop control, installation, kext loading or live EFI edits authorized.

## What changed in1.1.4 (including unpublished1.1.3 work)

Foreground changed-family commands and background policies share a file lock.
Healthy agents receive SIGUSR1; power changes wake a live CFRunLoop. Driver
requests wake the existing workloop timer. No ACPI in property handlers.
Errors are isolated by family; Fn failure cannot stop thermal/battery actions.

Bug: all-policy execution decomposed into ThermalIntent, then applied the same
foreground ineligibility guard. It rejected the automatic Standard fallback.
The guard is now foreground-only. Failed thermal/charge requests get one new
attempt when their effective target, power source or driver session changes;
unchanged failures remain stopped. Legacy failure context migrates once.

Charging-intent dedup now includes boot/driver identity and power source. It
also checks the driver's request cache. Resend once after reload/reconnect or
24h expiry, not every tick. Internal battery's explicit power-source state is
preferred over the aggregate provider; never infer AC from IsCharging.

UI root/hosting background is transparent, grouped Form scroll background
hidden, cards use translucent fills. Offscreen fixtures cover widths480/660/900
and light/dark/material-colored hosts. Real Settings hosting remains user-test.

## 1.1.5 Fn and documentation update

Card titles are exactly Performance, Standard, Whisper, keeping the descriptions.
README now explains firmware RPM regulation versus userspace profile selection,
load/heat response, Full Speed override and unknown ASUS thermal curves.

Fn software bugs: a matching DSTS mirror was adopted without any command; Fn
intent/failure persisted across driver sessions; three rapid readbacks could
fail before firmware state updated; a later matching readback never cleared
the stopped family or the foreground error banner.

Deliberate Fn selections now force one command. Fn intent includes driver
session and desired mode; background reconciliation adopts a prior confirmed
request quietly but sends once in a new session. Up to10 readbacks with100ms
gaps observe the accepted command, without resending. A pending accepted
request can be adopted later only for the exact session/mode. Explicit reselect
retries; an unchanged failure is not rewritten on every tick. Pane policy error
clears when that revision later applies. Fake-driver tests cover each path.

Live read-only inspection before the update: loaded driver still custom1.1.2,
agent1.1.4. Saved hotkeys=true, DSTS hotkeys=false, Fn failed. That establishes
an acknowledged mismatch, not its underlying EC cause. Do not promise the
userspace fix physically solves the laptop's Fn behavior. No firmware writes,
service registration, installation or EFI changes were performed in this turn.
User has not yet tested Fn+Esc. G-Helper uses the same WMI0x00100023 route plus
an unrelated USB keyboard fallback; do not copy USB reports to this PS/2 device.
The extended1.4.1 driver from1.1.4 remains unchanged and optional for this pane
update; no reboot/kext replacement is required to test1.1.5 with custom API2.

## 1.1.6 confirmed Fn inversion and dynamic touchpad hint

User first reported switching failed, then confirmed it works but in reverse.
They compared the SAME F7 key: Printed hotkeys required Fn+F7 for the printed
light action; F1–F12 used F7 alone. This establishes inverted physical semantics
on this firmware, unlike the earlier ambiguous comparison using different keys.
Firmware DEVS0/DSTS10000 therefore means printed actions; DEVS1/DSTS10001 means
ordinary F1–F12. Do not globally invert every ASUS model.

Driver hardware profile now has fnLockInverted=true; both parameter and readback
are converted. Upstream module version stays1.4.1, API2, feature revision4.
FnLockSemanticsVersion=1 advertises normalized command3/4 and FnLockHotkeys.
Client compatibility swaps only3/4 and inverts Fn status for the exact known
hardware label when that marker is absent. A normalized driver is never inverted
again. This lets the new pane work with the running custom1.1.2 kext; no EFI
replacement or reboot required for this test. Fn intent includes semantics1 to
invalidate successes/failures interpreted under the old naming.

Touchpad inline confirmation, footer and failure recovery hint follow active
normalized readback: F6 for printed hotkeys, Fn+F6 for ordinary F1–F12. Unknown
mode gets a generic touchpad-key hint. No UI redesign or additional mode row.

Screenshot also showed the3s lock-busy warning. Subsequent live read-only state
showed matching saved/applied revisions and no failures; user confirmed switching
worked. Lock contention was not established as the cause of inversion and was
not changed. lsof showed the pane host with the lock file open, not proof that
it held a stuck flock. ps was denied; no bypass attempted. No live writes,
installation, agent restart, keyboard interception or EFI modification performed.
New mapping still requires a physical test using the updated pane.

## 1.1.7 acknowledgement, recovery hints and automatic Performance

User confirms physical Fn switching works with1.1.6 but its readback warning
persists. Read-only snapshot: accepted pending F1–F12 request, old successful
hotkeys intent, DSTS mirror still reports hotkeys after client normalization.
Do not infer physical mode from this stale mirror or keep rewriting the keys.

Client marks FnLockReadbackReliable=false only on the known profile unless a
future driver explicitly supplies true. Known-profile Fn writes record accepted
intent/verification, not verified FnIntent. State result is accepted, not applied;
no permanent mismatch banner. Actual rejections/timeouts remain errors. Exact
same-session legacy Fn pending/readback-only failures migrate without a new
command, preserving unrelated errors. Normal strict readback remains for other
interfaces. Pane/agent both use the same classification. Native driver unchanged.

FnSelectedHotkeys/FnSelectionSource are UI-only annotations: last accepted mode
on this profile, reliable readback otherwise. Do not overwrite FnLockHotkeys.
F1–F12 now immediately produces the correct Fn+F6 recovery hint despite stale
mirror state. Touchpad and Function keys are separate groups, each with its own
footer; inline confirmation and touchpad failure text use the same selection.
Unknown mode gets a generic hint. No duplicate mode/status row is reintroduced.

New user-requested AutoPerformanceOnAC toggle defaults off. Enabling opts into
fan management with ManualProfile=Standard and uses Performance on AC above40%,
Standard on battery/<=40%. Turning off leaves Standard. Manual card or Full Speed
selection disables auto mode and applies that choice immediately. Existing
manual Performance fallback/restoration is preserved. No per-source menu/LPM
rules. This is post-login agent policy, not a firmware RPM algorithm change.

No installation, live service edits, firmware writes or EFI changes during this
work. Test the updated pane; no kext replacement or reboot is required.

## Pending charging-inhibit request

User asks for AlDente-like behavior: stop charging at80% while continuing to
use the adapter, without forced battery discharge. Existing80/100 request still
has no verified physical enforcement. No charging-inhibit implementation added
in1.1.7. Do not claim Battery Care fixed or equate a request cache with charging.

AlDente's published Helper.swift uses AppleSMC CH0B0/2 (and legacy BCLM for
limits). Inspected VirtualSMC/SMCBatteryManager source contains no CH0B/BCLM
backend. Copying that key cannot control the ASUS hardware. Saved DSDT exposes
RSOC0x00120057 -> SRSC -> WEBC(6,2,buffer); its known80/100 calls acknowledge
queueing, not actual enforcement. DSTS reads flags via REBC(5,2), not a verified
numeric threshold. Linux asus-wmi likewise caches its requested threshold.
DSDT SRSC has a special128 -> [80,1] encoding, whose extra flag semantics remain
unknown; do not label it inhibit or write it speculatively. BCHG/CHGS are status
reads, not charge enable setters. No verified immediate ASUS inhibit interface
has been found. No fake SMC charge-control key or arbitrary-register API added.

Latest read-only snapshot was71% on battery, negative current, no AC attached;
it cannot verify behavior while charging past80%. A question is pending whether
AlDente itself has worked on this laptop or was only a behavior reference. No
normal-user firmware command was run from the sandbox, and the earlier denied
write was not retried through another route. Next hardware work needs a proven
ASUS command path and actual charging-current observations, not more UI polish.

## Driver source and build

Separate AsusSMC checkout, branch
`asus-control-1.x`; pinned upstream `c15d2f297c86b65a3cb866cc2bcece595c136417`.
No published GitHub fork exists; do not claim one. Full diff is exported as
`Driver/AsusSMC-device-settings.patch` and applied by build-driver.sh in isolation.
Upstream MIT notices, identifier `com.hieplpvip.AsusSMC`, service and filename
remain. Both MODULE_VERSION and CURRENT_PROJECT_VERSION stay upstream1.4.1.
Settings API2 / feature revision4 identify added features, independently of
ASUS Control1.1.7. MacKernelSDK/Lilu/VirtualSMC dependencies are pinned.

No settings/fan boot arguments required with this new driver. Cached DSDT bytes
match conservative signatures for the known RPM, thermal and Fn wiring, not
spoofed Mac SMBIOS. No added ACPI discovery or queries at startup/passive polling.
Existing GKPC/SKPC ACPI is needed for keyboard timeout; VoodooI2C/IANE(0x6B)
for touchpad. No new SSDT. Older custom API2 drivers remain pane-compatible but
may still need their former boot arguments. Do not remove flags for an old kext.

## Hardware evidence and unresolved issues

User corrected the earlier boot-stall attribution: it was unrelated to AsusSMC.
RPM and Auto/Full Speed physically worked with earlier custom driver builds.
Thermal DSTS/DEVS0x00110019: Standard0, Whisper1, Performance2. Fan0x00110013:
low16*100RPM, DEVS0 Auto/1 Full. Profile firmware regulates speed based on its
internal thermal policy; exact curves/thresholds are unknown. No arbitrary RPM
or manufacturer-calibrated min/max. Userspace implements eligibility fallback.

Battery DEVS0x00120057 accepts80/100. DSTS is capability, not numerical readback.
ChargeLimitRequested is an acknowledgement cache. Saved DSDT SRSC calls WEBC:
WEBC returns1 after queueing EC bytes, without checking eventual charge-limit
enforcement. User confirms charging continued past80%. Context refresh is fixed,
but actual enforcement remains unverified. Do not claim it physically fixed or
guess undocumented0x80 encodings/registers. Test with charger connected over80%.

Fn0x00100023 accepts exactDSTS10000/10001. On this profile, DEVS0 means
printed hotkeys and1 means F1–F12. DEVS returns1 even
when its nested EC mailbox operation does not establish physical success. User
reports intermittent behavior. Added diagnostics FnLockRaw, RequestedHotkeys and
WriteAcknowledged do not fix this protocol. Session command from this sandbox
was denied0xe00002e2, before any write; do not bypass that restriction. Physical
Fn behavior still needs investigation/testing through the normal user session.

Tests use pure policy/fake driver and offscreen windows, never live writes.
Compilation/fixtures do not prove boot, charging, fan acoustics, sleep/wake or
physical input behavior. Keep source publication separate from live deployment.
