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
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror Tests/session-test.m Source/PolicySession.m Source/Policy.m \
  -framework Foundation -o build/session-test
build/session-test
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror Tests/environment-test.m Source/DeviceEnvironment.m \
  -framework Foundation -framework IOKit -framework CoreGraphics -o build/environment-test
build/environment-test
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror Tests/pane-test.m \
  -framework Cocoa -framework PreferencePanes -o build/pane-test
build/pane-test "$PWD/build/ASUS Control.prefPane" "$PWD/build/previews"
python3 - <<'PYVERSION'
import pathlib,plistlib,subprocess
version=pathlib.Path('VERSION').read_text().strip()
bundle=pathlib.Path('build/ASUS Control.prefPane/Contents')
info=plistlib.loads((bundle/'Info.plist').read_bytes())
assert info['CFBundleShortVersionString']==version and info['CFBundleVersion']==version
for name in ['asusctl','asuscontrol-agent']:
    assert subprocess.check_output([str(bundle/'Helpers'/name),'--version'],text=True).strip()==version
print('PASS: pane, CLI and login helper share VERSION.')
PYVERSION
if "build/ASUS Control.prefPane/Contents/Helpers/asusctl" keyboard 101 >/dev/null 2>&1; then exit 1; fi
echo 'PASS: bundle version and invalid CLI input. No firmware writes performed.'

for command in charge-80 charge-100; do
  if "build/ASUS Control.prefPane/Contents/Helpers/asusctl" device "$command" >/dev/null 2>&1; then exit 1;
  else test "$?" = 2; fi
done
echo 'PASS: retired charging commands exit as invalid before contacting a driver.'
