# ASUS Control continuation — 2026-11-14

Active public repository: `samuelnotfound/Asus-X1605VA-Hackintosh-Tahoe`.
Project `Projects/ASUS/AsusControl`, release1.1.2. Keep software names broad;
only the X1605VA BIOS305 firmware profile is currently validated. Do not publish
raw diagnostics, reference documents, user identities or ignored build backups.

## Latest user requirements (supersede earlier layouts)

- One scrolling pane for all controls. No Power/Input tabs or System Status.
- Restore the three large Performance, Standard and Whisper cards.
- Full Speed is a separate switch. Native SwiftUI grouped rows around cards.
- Remove profile switching entirely: no four-way mode menu, AC/battery profile
  rules, or Low Power Mode override. Retired saved rules are discarded on read.
- Remove the Requested charging limit row. Keep Battery Care and24h full charge.
- Keep touchpad confirmation, Fn-mode selection and keyboard idle timeout.
- No microphone or screen/keyboard-brightness slider. Physical four-step
  keyboard light cycling stays unchanged. Deprecated Assistant is separate.

## Latency fix

The user confirmed controls eventually applied in1.1.1, but they were far too
slow. That version restarted the helper and processed a whole policy batch for
each click. Driver1.1.0 also only serviced its queue on the1s sensor timer.

1.1.2 sends only the changed control from the pane directly. Pane and agent use
one file lock per transaction. Confirmed state is shared so the agent does not
resend foreground changes. Healthy agents are signaled; only old/exited jobs
restart. The agent services a live runloop/power notifications instead of
sleeping its main thread indefinitely. Errors stop that revision and stay
visible. Acknowledgement alone does not confirm profile/Fn/light state.

The1.1.2 kext schedules its existing workloop timer immediately for accepted
requests. No ACPI is evaluated by the property handler; no extra startup
queries or discovery were added. Passive sensor polling remains1s. The old
1.1.0 API2 driver remains compatible, but retains its request polling delay.
The new matching kext is needed to test the fastest command dispatch.

Do not claim live latency has been measured from fixture tests. Source tests
verify isolated foreground requests, no duplicate writes, serialization and
readback mismatch behavior. GUI tests use offscreen windows only. No live
service or firmware was changed during development.

## Driver and hardware facts

Separate AsusSMC checkout, branch `asus-control-1.x`, pinned upstream
`c15d2f297c86b65a3cb866cc2bcece595c136417`. A GitHub fork could not be created;
user chose local development. Do not claim it is published. Complete changes
are exported as `Driver/AsusSMC-1.1.2.patch`; build-driver.sh applies in isolation.
Keep upstream MIT notices, identifier `com.hieplpvip.AsusSMC`, service AsusSMC
and AsusSMC.kext filename. Control API2; legacy aliases and fan commands remain.

Boot arguments: `-asusctrl asusctrlprofile=x1605va305 -asusctrlsettings`.
Optional `-asusctrlfan` enables older administrator-only fan commands. Existing
GKPC/SKPC ACPI is needed for keyboard timeout; VoodooI2C/IANE(0x6B) for touchpad.
No new SSDT. All writes/readback are explicit requests on the existing workloop.

FanDSTS0x00110013: presence + low16×100RPM, reject FFFFFFFE/FFFFFFFF and fpe2
overflow. DEVS0 Auto/1 Full. Thermal0x00110019: Standard0/Whisper1/Performance2.
Performance regulates RPM automatically; Full Speed is an override. No custom
curve, arbitrary RPM target or calibrated manufacturer min/max query.
Current UI restrictions: Performance on AC+>40% battery; Full Speed on AC.
Explicit requests that are ineligible report the restriction.

Battery0x00120057 accepts80/100; DSTS reports support, not numerical limit.
24h timer is userspace and resumes next running login if deadline passes while
off/logged out. Fn0x00100023 accepts exact10000/10001; DEVS0 normal/1 hotkeys.
No Lenovo EC code from YogaSMC; it informed pane/driver separation only.

## Existing evidence and next test

The user corrected the prior boot-stall attribution: it was unrelated to
AsusSMC. Do not call it a kext-caused regression. Running driver during1.1.2
work was1.1.0, with live RPM/thermal cache and working physical Auto/Full Speed.
Fn changes eventually reached confirmed readback. Earlier approved recovery
restored SYSTEM from stock OPENCORE1.4.1 while the cause was uncertain;
that is history, not the current driver state. Preserve ignored recovery files.

Next: close System Settings and replace the pane, then test direct Fn/profile
changes. To test wake-on-request, deliberately replace the existing kext with
matching1.1.2 using the recoverable test EFI. No duplicated AsusSMC entry or
boot-argument/SSDT change is required. Do not install it automatically.
Physical latency, profile acoustics, remaining controls and sleep/wake still
need user validation. Source publication/builds never authorize live EFI edits.
