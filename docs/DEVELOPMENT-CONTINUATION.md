# ASUS Control continuation — 2026-11-15

Public repository `samuelnotfound/Asus-X1605VA-Hackintosh-Tahoe`.
Project `Projects/ASUS/AsusControl`, pane/CLI/agent1.1.4. Keep software names
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

## Driver source and build

Separate AsusSMC checkout, branch
`asus-control-1.x`; pinned upstream `c15d2f297c86b65a3cb866cc2bcece595c136417`.
No published GitHub fork exists; do not claim one. Full diff is exported as
`Driver/AsusSMC-device-settings.patch` and applied by build-driver.sh in isolation.
Upstream MIT notices, identifier `com.hieplpvip.AsusSMC`, service and filename
remain. Both MODULE_VERSION and CURRENT_PROJECT_VERSION stay upstream1.4.1.
Settings API2 / feature revision3 identify added features, independently of
ASUS Control1.1.4. MacKernelSDK/Lilu/VirtualSMC dependencies are pinned.

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

Fn0x00100023 accepts exactDSTS10000/10001. DEVS0 normal/1 hotkeys returns1 even
when its nested EC mailbox operation does not establish physical success. User
reports intermittent behavior. Added diagnostics FnLockRaw, RequestedHotkeys and
WriteAcknowledged do not fix this protocol. Session command from this sandbox
was denied0xe00002e2, before any write; do not bypass that restriction. Physical
Fn behavior still needs investigation/testing through the normal user session.

Tests use pure policy/fake driver and offscreen windows, never live writes.
Compilation/fixtures do not prove boot, charging, fan acoustics, sleep/wake or
physical input behavior. Keep source publication separate from live deployment.
