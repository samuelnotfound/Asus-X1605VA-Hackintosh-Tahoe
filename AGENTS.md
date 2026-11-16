# Current development

Read `docs/DEVELOPMENT-CONTINUATION.md` before changing this repository.

- This is the current public Tahoe repository. Never copy private diagnostics,
  credentials, identity values, EFI backups or chat transcripts here.
- Active settings project: `Projects/ASUS/AsusControl`, version is in VERSION,
  displayed as ASUS Control. Keep it separate from deprecated Assistant code.
- Use broad software names; board names belong in explicit hardware profiles
  and compatibility notes. Only X1605VA BIOS 305 is currently profiled.
- Use native SwiftUI Form with grouped rows, leading labels and trailing
  controls, following the macOS Appearance/Desktop & Dock references. Avoid
  duplicate fan controls; fit the host size and use one scrolling form. Restore
  three large Performance/Standard/Whisper cards. One pane, no tabs, dashboard,
  profile-switching menu, per-source profile pickers or Low Power Mode rules. The
  former AutoPerformanceOnAC switch is removed and its saved flag ignored.
  Performance requires AC and>40%; return to Standard on restart, AC loss or
  below40%, retiring the saved selection. Never restore it just on reconnect.
  No requested
  charging-limit row. No brightness slider, microphone or screen brightness.
- Current scope: fan monitoring/modes,
  direct profiles, touchpad, Fn mode and backlight idle timeout. Preserve physical four-step keyboard-light cycling.
- Pane, utility and optional login agent share VERSION. Keep AsusSMC's
  upstream version1.4.1 unchanged. Added settings are API2 / feature revision4.
  Cached DSDT wiring detection replaces boot-argument requirements; no model
  detection based on spoofed SMBIOS. No new firmware discovery at boot.
- Latest fan policy follows the user's Windows behavior: manual Performance,
  >40% to activate, already active may stay at40%, below40% returns to Standard.
  Restart detection uses BootSessionID and FanBootSessionID; the opted-in agent
  persists Standard before executing policies. Explicit new manual selections
  initialize the boot marker and are not reset during the same boot.
- Use identical16pt native spinners for changed controls and card lower-right.
  No Applying settings banner. Clear indicators after completion/failure; retain
  actual errors. Preserve native grouping and the existing card design.
- No duplicate content title or current-Fn-mode row. Keep one Fn selector.
  Card titles are exactly Performance, Standard, Whisper; preserve descriptions.
- Deliberate Fn selections send once despite a matching firmware mirror.
  For reliable interfaces, poll with a bounded delay and adopt late confirmation.
  The known BIOS305 Fn mirror is unreliable: record FnAcceptedIntent and result
  accepted after acknowledgement, without pretending physical verification or
  automatically rewriting it. Preserve real rejection/timeout errors. Migrate
  only exact accepted legacy readback mismatches, without a new write.
  Fn intents/failures are scoped to driver session and desired mode. Do not
  equate the Fn acknowledgement or firmware mirror with physical key behavior.
- Known X1605VA BIOS305 Fn mapping is inverted: firmware0 printed /1 F1–F12.
  Normalize both readback and commands. New driver advertises
  FnLockSemanticsVersion=1; compatibility mapping for old API2 drivers is scoped
  to the exact hardware label and skipped for normalized drivers.
- Separate Touchpad and Function keys into their own grouped sections and
  footers. Touchpad recovery hints use the last accepted mode on this profile,
  reliable readback elsewhere: F6 printed, Fn+F6 F1–F12. Keep inline/error hints
  consistent and preserve the firmware mirror separately in diagnostics.
- Battery Care/24h full charging are removed. Drop legacy preferences and
  charging intents/errors; no app, CLI or agent charging writes. Retain legacy
  kernel endpoints for older clients without exposing them as current features.
- Keep READMEs concise and user-facing: features, requirements, build/install,
  removal and links. Put implementation details in the developer guide. No
  reported/tested-by narratives or repeated app release numbers. VERSION is the
  pane/CLI/helper source of truth; upstream AsusSMC version remains unchanged.
- Loading indicators belong on the trailing/right side of switches and menus;
  fan-card indicators remain lower-right. Requirement note starts with
  “Performance mode requires:”.
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
