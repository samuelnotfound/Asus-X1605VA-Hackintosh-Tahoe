#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 1 ]]; then echo 'Usage: bash Tools/export-driver.sh /path/to/AsusSMC' >&2; exit 2; fi
SOURCE_DIR="$1"
test "$(cat VERSION)" = "$(cat "$SOURCE_DIR/VERSION")"
# New source files must be staged so git diff includes them.
git -C "$SOURCE_DIR" diff c15d2f297c86b65a3cb866cc2bcece595c136417 -- \
  .gitignore AsusSMC/AsusSMC.cpp AsusSMC/AsusSMC.hpp AsusSMC/X1605VAProtocol.hpp \
  AsusSMC.xcodeproj/project.pbxproj VERSION X1605VA.md build-x1605va.sh Tests/protocol.cpp \
  > "Driver/AsusSMC-$(cat VERSION).patch"
echo 'Exported fork changes against the pinned upstream commit.'
