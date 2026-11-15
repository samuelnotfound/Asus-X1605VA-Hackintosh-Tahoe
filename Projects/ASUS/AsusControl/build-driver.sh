#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
SETTINGS_DIR="$PWD"
SOURCE_REV=$(python3 - <<'PY'
import hashlib, json, pathlib
config = json.loads(pathlib.Path('Driver/Upstream.json').read_text())
print(hashlib.sha256(pathlib.Path('Driver', config['patch']).read_bytes()).hexdigest()[:12])
PY
)
SOURCE_DIR="${ASUSSMC_SOURCE:-$SETTINGS_DIR/build/AsusSMC-$SOURCE_REV}"
mkdir -p build
if [[ -z "${ASUSSMC_SOURCE:-}" ]]; then
  python3 - "$SOURCE_DIR" <<'PY'
import json, pathlib, subprocess, sys
config = json.loads(pathlib.Path('Driver/Upstream.json').read_text())
source = pathlib.Path(sys.argv[1])
if not source.exists():
    subprocess.run(['git','clone','--no-checkout',config['repository'],str(source)],check=True)
    subprocess.run(['git','-C',str(source),'checkout','--detach',config['commit']],check=True)
    patch = str(pathlib.Path('Driver',config['patch']).resolve())
    subprocess.run(['git','-C',str(source),'apply','--check',patch],check=True)
    subprocess.run(['git','-C',str(source),'apply',patch],check=True)
else:
    actual = subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()
    if actual != config['commit']:
        raise SystemExit('Existing driver source is not the expected patched checkout. Use a fresh build directory.')
import re
versions=set(re.findall(r'MODULE_VERSION = ([0-9.]+);',(source/'AsusSMC.xcodeproj/project.pbxproj').read_text()))
if versions != {config['driver_version']}:
    raise SystemExit('The driver must retain the upstream module version.')
PY
fi
bash "$SOURCE_DIR/build-device-settings.sh"
ditto "$SOURCE_DIR/build-device-settings/AsusSMC.kext" "$SETTINGS_DIR/build/AsusSMC.kext"
echo "Driver built at $SETTINGS_DIR/build/AsusSMC.kext. Nothing installed."
