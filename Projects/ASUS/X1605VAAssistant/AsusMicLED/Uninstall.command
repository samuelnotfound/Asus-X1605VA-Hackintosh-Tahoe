#!/bin/zsh
# Uninstall micled-agent (LaunchAgent + binary).
# Kext and SSDT live on the EFI partition — remove those in OpenCore manually.
set -eu

if (( EUID == 0 )); then
  print -u2 'Run as your normal user, not with sudo.'
  exit 1
fi

label='com.x1605va.micled'
domain="gui/$(id -u)"
agent="$HOME/Library/LaunchAgents/${label}.plist"
bin='/usr/local/bin/micled-agent'

if [[ -e "$agent" || -L "$agent" ]]; then
  if [[ -L "$agent" ]]; then
    print -u2 "Refusing to remove symlink: $agent"
    exit 1
  fi
  got=$(plutil -extract Label raw -o - "$agent" 2>/dev/null || true)
  if [[ "$got" != "$label" ]]; then
    print -u2 "Unexpected LaunchAgent label ($got); left untouched."
    exit 1
  fi
  rm -f -- "$agent"
  print "Removed $agent"
fi

if launchctl print "$domain/$label" >/dev/null 2>&1; then
  launchctl bootout "$domain/$label" >/dev/null 2>&1 || true
  print "Stopped $label"
fi

if [[ -f "$bin" ]]; then
  if strings "$bin" 2>/dev/null | grep -q 'micled-agent'; then
    if [[ -w "$bin" ]]; then
      rm -f -- "$bin"
      print "Removed $bin"
    else
      print "Binary $bin is not writable; remove with: sudo rm '$bin'"
    fi
  else
    print "Left $bin (does not look like micled-agent)"
  fi
fi

print ''
print 'micled-agent removed.'
print 'Still on disk until you edit EFI:'
print '  EFI/OC/Kexts/AsusMicLED.kext'
print '  EFI/OC/ACPI/SSDT-AsusMicLED.aml'
