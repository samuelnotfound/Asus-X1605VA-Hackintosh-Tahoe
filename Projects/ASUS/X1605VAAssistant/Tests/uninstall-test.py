"""Exercise the real script in an isolated fake home, with launchctl mocked."""
import os
import plistlib
from pathlib import Path
import subprocess
import tempfile

label = 'com.samuelnotfound.X1605VAAssistant.Agent'
script = Path(__file__).resolve().parents[1] / 'Uninstall.command'
with tempfile.TemporaryDirectory(prefix='fn-uninstall-test-') as folder:
    home = Path(folder)
    tools = home / 'bin'
    tools.mkdir()
    launchctl = tools / 'launchctl'
    launchctl.write_text('#!/bin/sh\nif [ "$1" = print ]; then exit 0; fi\nif [ -e "$HOME/Applications/X1605VA Assistant.app" ] || [ -e "$HOME/Library/LaunchAgents/com.samuelnotfound.X1605VAAssistant.Agent.plist" ]; then exit 9; fi\nprintf stopped > "$HOME/bootout-checked"\n')  # no live launchd calls
    rm = tools / 'rm'
    rm.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$HOME/remove-order"\nexec /bin/rm "$@"\n')
    rm.chmod(0o755)
    launchctl.chmod(0o755)
    tcc = tools / 'tccutil'
    tcc.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$HOME/permission-resets"\nexit 0\n')
    tcc.chmod(0o755)
    env = dict(os.environ, HOME=str(home), PATH=str(tools) + ':' + os.environ['PATH'])
    # Run an isolated copy of the exact uninstall script, replacing only its
    # fixed global app path; never exercise deletion in the real /Applications.
    source = script.read_text()
    install_line = "app='/Applications/X1605VA Assistant.app'"
    assert source.count(install_line) == 1
    fixture = home / 'Uninstall.command'
    isolated = source.replace(install_line, 'app="$HOME/Applications/X1605VA Assistant.app"').replace('"/Applications/X1605VA Fn Helper.app"', '"$HOME/Applications/X1605VA Fn Helper.app"')
    assert '"/Applications/' not in isolated and "='/Applications/" not in isolated
    isolated = isolated.replace("/usr/bin/tccutil", str(tcc))
    fixture.write_text(isolated)
    app = home / 'Applications/X1605VA Assistant.app'
    app.joinpath('Contents').mkdir(parents=True)
    info = app / 'Contents/Info.plist'
    info.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'com.example.Unrelated'}))
    result = subprocess.run(['/bin/zsh', str(fixture)], env=env, capture_output=True)
    assert result.returncode != 0 and app.exists(), 'Unrelated app must survive'
    info.write_bytes(plistlib.dumps({'CFBundleIdentifier': label}))
    agents = home / 'Library/LaunchAgents'
    agents.mkdir(parents=True)
    job = agents / (label + '.plist')
    job.write_bytes(plistlib.dumps({'Label': label}))
    efi = home / 'EFI/OC/config.plist'
    efi.parent.mkdir(parents=True)
    efi.write_text('untouched')
    unrelated = home / 'keep.txt'
    unrelated.write_text('untouched')
    result = subprocess.run(['/bin/zsh', str(fixture)], env=env, capture_output=True)
    assert result.returncode == 0, result.stderr.decode()
    assert not app.exists() and not job.exists()
    resets = (home / 'permission-resets').read_text()
    assert 'reset Accessibility ' + label in resets and 'reset ListenEvent ' + label in resets
    order = (home / 'remove-order').read_text().splitlines()
    assert str(job) in order[0], order
    assert (home / 'bootout-checked').exists()
    assert efi.read_text() == 'untouched' and unrelated.exists()
    # Reset refusal must not strand the app; report it explicitly after cleanup.
    app.joinpath('Contents').mkdir(parents=True)
    info.write_bytes(plistlib.dumps({'CFBundleIdentifier': label}))
    job.write_bytes(plistlib.dumps({'Label': label}))
    tcc.write_text('#!/bin/sh\nexit 1\n')
    result = subprocess.run(['/bin/zsh', str(fixture)], env=env, capture_output=True)
    assert result.returncode == 0 and b'PERMISSION_RESET_WARNING' in result.stdout
    assert not app.exists() and not job.exists()
print('Uninstall removes only matching app/login files in a fake home; unrelated bundle and EFI survive.')
