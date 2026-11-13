#!/bin/zsh
set -eu
if (( EUID == 0 )); then
  print -u2 'Run this as your normal user, without sudo.'
  exit 1
fi
label='com.samuelnotfound.X1605VAAssistant.Agent'
legacy_label='com.samuelnotfound.AsusMicLED.Agent'
domain="gui/$(id -u)"
app='/Applications/X1605VA Assistant.app'
matching_app() {
  [[ ! -L "$1" ]] || return 1
  local identity
  identity=$(plutil -extract CFBundleIdentifier raw -o - "$1/Contents/Info.plist" 2>/dev/null) || return 1
  [[ "$identity" == "$label" || "$identity" == "$legacy_label" ]]
}
if [[ -e "$app" || -L "$app" ]]; then
  matching_app "$app" || { print -u2 'A different app occupies the installation path; left untouched.'; exit 1; }
fi
# Delete login files first. Delay bootout until all file cleanup is complete,
# because this script can be a child of the running login app.
for identity in "$label" "$legacy_label"; do
  agent="$HOME/Library/LaunchAgents/$identity.plist"
  if [[ -e "$agent" || -L "$agent" ]]; then
    [[ ! -L "$agent" && "$(plutil -extract Label raw -o - "$agent")" == "$identity" ]] || { print -u2 'Unexpected login entry; left untouched.'; exit 1; }
    rm -f -- "$agent"
  fi
done
# Ask macOS to clear this app's own privacy records before removing its bundle.
# Legacy resets are best effort; a failed current-app reset is reported clearly.
for identity in "$label" "$legacy_label"; do
  for service in Accessibility ListenEvent; do
    if ! /usr/bin/tccutil reset "$service" "$identity" >/dev/null 2>&1; then
      if [[ "$identity" == "$label" ]]; then print 'PERMISSION_RESET_WARNING'; fi
    fi
  done
done
rm -rf -- "$app"
for legacy in "/Applications/X1605VA Fn Helper.app" "$HOME/Library/Application Support/X1605VA Fn Helper/X1605VA Fn Helper.app" "$HOME/Library/Application Support/X1605VA Assistant/X1605VA Assistant.app" "$HOME/Library/Application Support/X1605VA Companion/X1605VA Companion.app" "$HOME/Applications/AsusMicLED.app" "$HOME/Library/Application Support/AsusMicLED/AsusMicLED.app" "$HOME/Library/Application Support/ASUS Companion/ASUS Companion.app"; do
  if [[ -d "$legacy" ]] && matching_app "$legacy"; then rm -rf -- "$legacy"; fi
done
if [[ "${1:-}" == '--self-delete' && "${0:A}" == "${TMPDIR%/}/X1605VA-Assistant-Uninstall-"*.command ]]; then rm -f -- "${0:A}"; fi
print 'Removed X1605VA Assistant and automatic login startup.'
for identity in "$label" "$legacy_label"; do
  if launchctl print "$domain/$identity" >/dev/null 2>&1; then launchctl bootout "$domain/$identity" >/dev/null 2>&1 || true; fi
done
