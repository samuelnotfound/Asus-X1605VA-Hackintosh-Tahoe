#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/previews
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror Tests/client-test.m Source/DeviceClient.m \
  -framework Foundation -framework IOKit -o build/client-test
build/client-test
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror Tests/pane-test.m \
  -framework Cocoa -framework PreferencePanes -o build/pane-test
build/pane-test "$PWD/build/X1605VA Settings.prefPane" "$PWD/build/previews"
test "$("build/X1605VA Settings.prefPane/Contents/Helpers/x1605vactl" --version)" = "$(cat VERSION)"
if "build/X1605VA Settings.prefPane/Contents/Helpers/x1605vactl" keyboard 101 >/dev/null 2>&1; then exit 1; fi
echo 'PASS: bundle version and invalid CLI input. No firmware writes performed.'
