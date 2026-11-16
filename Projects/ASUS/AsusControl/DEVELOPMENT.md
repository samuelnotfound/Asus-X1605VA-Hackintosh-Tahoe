# ASUS Control development

## Version sources

- `VERSION`: pane, CLI and login helper release. `build.sh` uses it for the
  bundle metadata, binaries and displayed app version.
- `Driver/Upstream.json`: pinned AsusSMC revision, upstream module version,
  settings API and feature revision. Keep the upstream identifier and version.
- README titles and links stay version-neutral. Release changes belong in Git history.

The pane uses the bounded device-control API. Compatibility depends on that
interface and its capabilities, rather than matching app/driver version numbers.

## Build and verification

```sh
bash build.sh
bash test.sh
bash build-driver.sh
```

The pane build is universal (Intel and Apple silicon); the Hackintosh driver is
Intel. Command Line Tools are sufficient. Driver dependencies are pinned in
`build-device-settings.sh` inside the exported source patch. Builds use ad-hoc
signatures. Local tests use pure policies, a fake driver and offscreen windows;
they do not validate physical firmware behavior. GitHub Actions repeats the builds. Refresh the README screenshot from
`build/previews/ASUS-Control.png` after layout changes.

## Driver source

`Driver/AsusSMC-device-settings.patch` applies to the upstream commit in
`Driver/Upstream.json`. Regenerate it from the separate driver checkout:

```sh
bash Tools/export-driver.sh /path/to/AsusSMC
```

Keep upstream licensing and `com.hieplpvip.AsusSMC`. Hardware-specific addresses,
polarity and restrictions live in the explicit hardware profile. Driver writes
are queued on its workloop; added settings queries do not run at startup.

## Policies and state

Pane actions and the login helper share a transaction lock. Foreground changes
send the selected control only. Performance resets to Standard after a new boot,
AC loss or low battery; the retired preference is not restored on reconnect.
Fn commands and status are normalized for the known firmware's inverted mapping.
Its stale Fn mirror is kept in diagnostics separately from accepted mode state.

Files live in `~/Library/Application Support/AsusControl`; the launch entry is
`~/Library/LaunchAgents/com.samuelnotfound.AsusControl.Agent.plist`.

Battery Care and temporary full charging are retired. New clients drop old
charging preferences/state and send no charging commands. Legacy kext endpoints
remain for old clients; this release does not expose them as app controls.

Architecture references: [YogaSMC](https://github.com/zhen-zen/YogaSMC) and
[G-Helper](https://github.com/seerge/g-helper). Preserve the independent ASUS
implementation and the licenses of any code actually reused.
