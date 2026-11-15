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
    if actual != config['commit'] or not (source/'VERSION').is_file():
        raise SystemExit('Existing driver source is not the expected patched checkout. Use a fresh build directory.')
if (source/'VERSION').read_text().strip() != config['release']:
    raise SystemExit('The driver release does not match Upstream.json.')
PY
fi
test "$(tr -d '\r\n' < "$SOURCE_DIR/VERSION")" = "$(tr -d '\r\n' < VERSION)"
bash "$SOURCE_DIR/build-x1605va.sh"
ditto "$SOURCE_DIR/build-x1605va/AsusSMC.kext" "$SETTINGS_DIR/build/AsusSMC.kext"
echo "Driver built at $SETTINGS_DIR/build/AsusSMC.kext. Nothing installed."
