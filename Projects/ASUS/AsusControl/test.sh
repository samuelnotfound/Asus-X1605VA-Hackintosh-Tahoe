#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/previews
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror Tests/client-test.m Source/DeviceClient.m \
  -framework Foundation -framework IOKit -o build/client-test
build/client-test
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror Tests/policy-test.m Source/Policy.m \
  -framework Foundation -o build/policy-test
build/policy-test
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror Tests/pane-test.m \
  -framework Cocoa -framework PreferencePanes -o build/pane-test
build/pane-test "$PWD/build/ASUS Control.prefPane" "$PWD/build/previews"
test "$("build/ASUS Control.prefPane/Contents/Helpers/asusctl" --version)" = "$(cat VERSION)"
if "build/ASUS Control.prefPane/Contents/Helpers/asusctl" keyboard 101 >/dev/null 2>&1; then exit 1; fi
echo 'PASS: bundle version and invalid CLI input. No firmware writes performed.'
