# Current development

Read `docs/DEVELOPMENT-CONTINUATION.md` before changing this repository.

- This is the current public Tahoe repository. Never copy private diagnostics,
  credentials, identity values, EFI backups or chat transcripts here.
- Active settings project: `Projects/ASUS/AsusControl`, version 1.1.1,
  displayed as ASUS Control. Keep it separate from deprecated Assistant code.
- Use broad software names; board names belong in explicit hardware profiles
  and compatibility notes. Only X1605VA BIOS 305 is currently profiled.
- Use native SwiftUI Form with grouped rows, leading labels and trailing
  controls, following the macOS Appearance/Desktop & Dock references. Avoid
  duplicate fan controls; fit the host size and use one scrolling form. No keyboard brightness slider, microphone or screen brightness.
- Current scope: fan monitoring/modes, battery care/24h full charge, AC/battery
  profiles, Low Power Mode sync, touchpad, Fn mode, backlight idle timeout and
  system dashboard. Preserve physical four-step keyboard-light cycling.
- Keep pane, utility, optional login agent and driver release versions aligned
  through VERSION. API 2 permits the existing 1.1.0 driver with the 1.1.1 pane.
  Device control API numbering is independent.
- Keep the original AsusSMC identity/license. Export driver source changes from
  its separate checkout against pinned upstream; don't require a published fork.
- Queue hardware operations on the driver workloop. Property handlers only
  validate/enqueue. Added settings discovery/queries never run in start() or
  periodic polling. No new automatic firmware writes before login.
- Timed/source policies are opt-in per-user login-agent features. No event tap,
  Accessibility gate, root daemon or arbitrary firmware/register API.
- Never equate compilation, fixtures or acknowledgement with verified boot,
  System Settings hosting, charging, fan or input behavior.
- Preserve user changes and working EFI. Source/build publication does not
  authorize installing/loading a kext or changing live EFI.
- Keep continuation notes concise and current across operating systems.
