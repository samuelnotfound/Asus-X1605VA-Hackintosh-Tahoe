#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
SETTINGS_VERSION=$(tr -d '\r\n' < VERSION)
[[ "$SETTINGS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid VERSION' >&2; exit 1; }
PANE="$PWD/build/ASUS Control.prefPane"
mkdir -p "$PANE/Contents/MacOS" "$PANE/Contents/Helpers" "$PANE/Contents/Resources" build/Settings.iconset
FLAGS=(-arch x86_64 -arch arm64 -mmacosx-version-min=13.0 -fobjc-arc -O2 -Wall -Wextra -Werror "-DASUS_CONTROL_VERSION=\"$SETTINGS_VERSION\"")
SWIFT_LIB="$(dirname "$(xcrun --find swiftc)")/../lib/swift/macosx"
mkdir -p build/SwiftModuleCache
for ARCH in x86_64 arm64; do
  xcrun swiftc -parse-as-library -emit-object -emit-objc-header \
    -emit-objc-header-path build/AsusControlUI-Swift.h -module-name AsusControlUI \
    -import-objc-header Source/PaneActions.h -target "$ARCH-apple-macos13.0" \
    -module-cache-path "$PWD/build/SwiftModuleCache" -O -warnings-as-errors \
    Source/SettingsView.swift -o "build/SettingsView-$ARCH.o"
  xcrun clang -arch "$ARCH" -mmacosx-version-min=13.0 -fobjc-arc -O2 -Wall -Wextra -Werror \
    "-DASUS_CONTROL_VERSION=\"$SETTINGS_VERSION\"" -Ibuild -ISource -bundle \
    Source/AsusControlPane.m Source/DeviceClient.m Source/Policy.m Source/Preferences.m Source/DeviceEnvironment.m Source/PolicySession.m \
    "build/SettingsView-$ARCH.o" -L"$SWIFT_LIB" -L/usr/lib/swift -Wl,-rpath,/usr/lib/swift \
    -framework SwiftUI -framework Combine -framework Cocoa -framework PreferencePanes -framework IOKit -framework CoreGraphics \
    -o "build/AsusControl-$ARCH"
done
lipo -create build/AsusControl-x86_64 build/AsusControl-arm64 -output "$PANE/Contents/MacOS/AsusControl"
xcrun clang "${FLAGS[@]}" Source/control.m Source/DeviceClient.m Source/Preferences.m Source/Policy.m \
  -framework Foundation -framework IOKit -o "$PANE/Contents/Helpers/asusctl"
xcrun clang "${FLAGS[@]}" Source/agent.m Source/DeviceClient.m Source/Policy.m Source/Preferences.m Source/DeviceEnvironment.m Source/PolicySession.m \
  -framework Foundation -framework IOKit -framework CoreGraphics -o "$PANE/Contents/Helpers/asuscontrol-agent"
python3 - "$SETTINGS_VERSION" "$PANE" <<'PY'
import pathlib, plistlib, sys
version, target = sys.argv[1:]
source = pathlib.Path('Info.plist').read_text().replace('@VERSION@', version)
plistlib.loads(source.encode())
pathlib.Path(target, 'Contents/Info.plist').write_text(source)
PY
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror Tools/icon.m -framework Cocoa -o build/render-icon
build/render-icon build/icon.png
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" build/icon.png --out "build/Settings.iconset/icon_${size}x${size}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" build/icon.png --out "build/Settings.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 - "$PANE/Contents/Resources/Settings.icns" <<'PY'
import pathlib, struct, sys
icons = pathlib.Path('build/Settings.iconset')
chunks = []
for tag, name in [('icp4','16x16'), ('icp5','32x32'), ('icp6','32x32@2x'),
                  ('ic07','128x128'), ('ic08','256x256'), ('ic09','512x512'), ('ic10','512x512@2x')]:
    data = (icons / ('icon_' + name + '.png')).read_bytes()
    chunks.append(tag.encode() + struct.pack('>I', len(data) + 8) + data)
payload = b''.join(chunks)
pathlib.Path(sys.argv[1]).write_bytes(b'icns' + struct.pack('>I', len(payload) + 8) + payload)
PY
codesign --force --sign - --identifier com.samuelnotfound.AsusControl.control "$PANE/Contents/Helpers/asusctl"
codesign --force --sign - --identifier com.samuelnotfound.AsusControl.Agent "$PANE/Contents/Helpers/asuscontrol-agent"
codesign --force --sign - "$PANE"
codesign --verify --deep --strict "$PANE"
plutil -lint "$PANE/Contents/Info.plist"
printf 'Built ASUS Control %s: %s\n' "$SETTINGS_VERSION" "$PANE"
echo 'Nothing was installed, launched, or written to the firmware.'
