# Current development

Read `docs/DEVELOPMENT-CONTINUATION.md` before changing this repository.

- This is the current public Tahoe repository. Do not copy private diagnostics,
  credentials, identity values, EFI backups, or chat transcripts here.
- The current settings project is `Projects/ASUS/X1605VASettings`, version 1.0.1.
  Keep it separate from the deprecated X1605VA Assistant.
- Scope: keyboard backlight, live fan RPM, Auto/Full Speed, and the three
  thermal profiles. Do not add microphone or screen-brightness controls.
- Follow MyASUS Device Settings grouping with native AppKit controls. Keep
  physical keyboard backlight cycling at four steps.
- Build versions from VERSION. Keep pane/utility and matching driver release
  versions aligned; control API numbering is separate.
- AsusSMC driver changes are maintained in a separate checkout/fork and exported
  against the pinned upstream commit. Preserve upstream licensing and notices.
- Read cached state in user space; queue hardware writes onto the driver
  workloop. Do not evaluate ACPI from a property handler.
- Do not equate compilation, fixture tests, or acknowledgement with verified
  physical fan/backlight behavior. Keep validation limits explicit.
- Preserve existing user changes and the working boot configuration. Building
  and publishing source do not authorize changing the live EFI or loading a kext.
- Keep continuity notes concise and current when handing off between systems.
