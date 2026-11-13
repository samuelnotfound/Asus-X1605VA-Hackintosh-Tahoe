#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
resources="$1"
mkdir -p "$resources" build/icon
if [[ "${2:-}" != --artwork-only ]] && xcrun --find actool >/dev/null 2>&1; then
  xcrun actool Icon/FnKey.icon Icon/MenuColors.xcassets --compile "$resources" --platform macosx \
    --minimum-deployment-target 11.0 --app-icon FnKey --accent-color Graphite \
    --output-partial-info-plist build/icon/partial.plist
  test -f "$resources/Assets.car"
else
  echo 'Rendering the current icon from source artwork.'
  xcrun clang -fobjc-arc -Wall -Wextra -Werror Icon/render-fallback.m -framework Cocoa -o build/icon/render
  rm -rf build/icon/FnKey.iconset
  build/icon/render Icon/Artwork.svg build/icon/FnKey.iconset
  python3 - "$resources/FnKey.icns" <<'ICONPY'
import struct, sys
from pathlib import Path
chunks = []
for kind, file in [('icp4','icon_16x16.png'), ('icp5','icon_32x32.png'),
                   ('icp6','icon_32x32@2x.png'), ('ic07','icon_128x128.png'),
                   ('ic08','icon_256x256.png'), ('ic09','icon_512x512.png'),
                   ('ic10','icon_512x512@2x.png')]:
    png = (Path('build/icon/FnKey.iconset') / file).read_bytes()
    chunks.append(kind.encode() + struct.pack('>I', len(png) + 8) + png)
payload = b''.join(chunks)
Path(sys.argv[1]).write_bytes(b'icns' + struct.pack('>I', len(payload) + 8) + payload)
ICONPY
  xcrun clang -fobjc-arc -Wall -Wextra -Werror Icon/check-icon.m -framework Cocoa -o build/icon/check-icon
  build/icon/check-icon "$resources/FnKey.icns"
fi
