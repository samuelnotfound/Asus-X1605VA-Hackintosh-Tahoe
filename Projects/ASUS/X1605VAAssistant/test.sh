#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/tests
xcrun clang -Wall -Wextra -Werror Tests/mic-volume-test.c -framework CoreAudio -framework CoreFoundation -o build/tests/mic-volume-test
build/tests/mic-volume-test
xcrun clang -fobjc-arc -Wall -Wextra -Werror Tests/login-job-test.m Agent/app-setup.m -framework Cocoa -o build/tests/login-job-test
build/tests/login-job-test
xcrun clang -fblocks -Wall -Wextra -Werror -Wno-unused-parameter Tests/key-access-test.c -framework ApplicationServices -framework IOKit -framework CoreAudio -framework CoreFoundation -framework Carbon -o build/tests/key-access-test
build/tests/key-access-test
xcrun clang -fobjc-arc -Wall -Wextra -Werror Tests/menu-test.m -framework Cocoa -framework QuartzCore -framework CoreImage -framework IOKit -o build/tests/menu-test
build/tests/menu-test
xcrun clang++ -std=c++14 -Wall -Wextra -Werror Tests/trackpad-test.cpp -o build/tests/trackpad-test
build/tests/trackpad-test
python3 Tests/uninstall-test.py
xcrun clang -fobjc-arc -Wall -Wextra -Werror Tests/lifecycle-test.m -framework Cocoa -o build/tests/lifecycle-test
build/tests/lifecycle-test

xcrun clang -fobjc-arc -Wall -Wextra -Werror Tests/uninstaller-launch-test.m -framework Cocoa -framework CoreServices -o build/tests/uninstaller-launch-test
build/tests/uninstaller-launch-test
