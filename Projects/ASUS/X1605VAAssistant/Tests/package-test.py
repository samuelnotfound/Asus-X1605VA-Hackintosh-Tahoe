"""Validate the names OpenCore and the app will actually load after the rename."""
import plistlib
from pathlib import Path
root = Path(__file__).resolve().parents[1]
build = root / 'build'
kexts = list((build / 'EFI/OC/Kexts').glob('*.kext'))
assert [p.name for p in kexts] == ['X1605VAAssistant.kext'], kexts
info = plistlib.loads((kexts[0] / 'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.samuelnotfound.X1605VAAssistant'
assert info['CFBundleExecutable'] == 'X1605VAAssistant'
assert (kexts[0] / 'Contents/MacOS' / info['CFBundleExecutable']).is_file()
personality = info['IOKitPersonalities']['X1605VAAssistant']
assert personality['IOClass'] == 'X1605VAAssistant'
assert personality['IONameMatch'] == 'ASUSF901'  # existing ACPI endpoint identity
app = plistlib.loads((build / 'X1605VA Assistant.app/Contents/Info.plist').read_bytes())
assert app['CFBundleIdentifier'] == 'com.samuelnotfound.X1605VAAssistant.Agent'
assert app['CFBundleExecutable'] == 'X1605VAAssistant'
assert (build / 'X1605VA Assistant.app/Contents/MacOS/X1605VAAssistant').is_file()
assert not (build / 'X1605VA Assistant.app/Contents/MacOS/asusmicled').exists()
assert app['CFBundleVersion'] == info['CFBundleVersion'] == '0.9.13'
table = 'SSDT-X1605VA-Assistant'
acpi = build / 'EFI/OC/ACPI'
assert sorted(p.name for p in acpi.glob('*.aml')) == [table + '.aml']
aml = (acpi / (table + '.aml')).read_bytes()
assert aml[:4] == b'SSDT' and int.from_bytes(aml[4:8], 'little') == len(aml) and sum(aml) % 256 == 0
for name in (b'BKOS', b'F9LR', b'FNHK', b'_Q16', b'_Q18', b'TTPD'):
    assert name in aml, name
assert (build / 'EFI' / (table + '.dsl')).read_bytes() == (root / 'ACPI' / (table + '.dsl')).read_bytes()
repo_oc = root.parents[2] / 'EFI/OC'
old_tables = {
    'SSDT-ASUS-KEYS.aml', 'SSDT-ASUS-F9-LED.aml',
    'SSDT-ASUS-MIC-RELAY.aml', 'SSDT-X1605VA-F12.aml',
}
for profile in ('mediatek', 'realtek'):
    config = plistlib.loads((repo_oc / f'config-{profile}.plist').read_bytes())
    entries = config['ACPI']['Add']
    paths = [entry['Path'] for entry in entries]
    assert not old_tables.intersection(paths), profile
    assert paths.count(table + '.aml') == 1, profile
    assert table + '.aml' in [entry['Path'] for entry in entries if entry['Enabled']], profile
    for entry in entries:
        if entry['Enabled']:
            assert (repo_oc / 'ACPI' / entry['Path']).is_file(), (profile, entry['Path'])
print('Bundle executables, versions, combined ACPI payload and both OpenCore profiles passed.')
