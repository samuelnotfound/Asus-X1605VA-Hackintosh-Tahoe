#!/bin/bash
# Build and install the latest published X1605VA Assistant app.
set -euo pipefail

repo="https://github.com/samuelnotfound/Asus-X1605VA-Hackintosh.git"
releases="https://api.github.com/repos/samuelnotfound/Asus-X1605VA-Hackintosh/releases?per_page=30"
bundle_id="com.samuelnotfound.X1605VAAssistant.Agent"
app_name="X1605VA Assistant.app"
app="/Applications/$app_name"
process_pattern='^/Applications/X1605VA Assistant[.]app/Contents/MacOS/X1605VAAssistant( |$)'

fail() { printf '%s\n' "$*" >&2; exit 1; }
plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }
rename_bundle() {
    /usr/bin/python3 -c 'import os, sys; os.rename(sys.argv[1], sys.argv[2])' "$1" "$2"
}

[[ "$(/usr/bin/uname -s)" == Darwin && "$(/usr/bin/uname -m)" == x86_64 ]] ||
    fail "X1605VA Assistant needs Intel macOS."
[[ "$(/usr/bin/id -u)" != 0 ]] || fail "Run this command as your regular macOS user."
if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
    /usr/bin/xcode-select --install || true
    fail "Finish installing Apple’s Command Line Tools, then paste this command again."
fi

installed_version=""
if [[ -e "$app" || -L "$app" ]]; then
    [[ -d "$app" && ! -L "$app" ]] || fail "The Applications path is occupied by another item."
    [[ "$(plist_value "$app" CFBundleIdentifier)" == "$bundle_id" ]] ||
        fail "The Applications path is occupied by another app."
    installed_version="$(plist_value "$app" CFBundleShortVersionString)"
fi

# The project's published builds are prereleases. Filter by product and
# release tag, and pin the source checkout to the release's exact commit.
release=$(
    /usr/bin/curl --proto '=https' -fsSL --retry 2 --connect-timeout 15 --max-time 60 "$releases" |
        /usr/bin/python3 -c '
import json, re, sys

def version(value):
    return tuple(map(int, value.split(".")))

candidates = []
for release in json.load(sys.stdin):
    tag = release["tag_name"]
    match = re.fullmatch(r"x1605va-assistant-v([0-9]+\.[0-9]+\.[0-9]+)", tag)
    commit = release.get("target_commitish", "")
    if match and not release["draft"] and re.fullmatch(r"[0-9a-f]{40}", commit):
        candidates.append((version(match[1]), match[1], tag, commit))
if not candidates:
    sys.exit("No published X1605VA Assistant source release was found.")
latest, release_version, tag, commit = max(candidates)
installed = sys.argv[1]
if installed and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", installed) and version(installed) >= latest:
    print("current")
else:
    print(release_version, tag, commit)
' "$installed_version"
)
if [[ "$release" == current ]]; then
    printf 'X1605VA Assistant %s is already up to date.\n' "$installed_version"
    exit 0
fi
read -r version tag commit <<< "$release"

work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/x1605va-assistant.XXXXXXXX")"
stage=""
install_attempted=0
committed=0
was_running=0
cleanup() {
    local status=$?
    trap - EXIT
    if [[ -n "$stage" ]] && (( !committed )); then
        if (( install_attempted )) && [[ ! -e "$stage/new.app" ]]; then
            rename_bundle "$app" "$stage/failed.app" || true
        fi
        if [[ -d "$stage/previous.app" ]]; then
            if rename_bundle "$stage/previous.app" "$app"; then
                if (( was_running )); then /usr/bin/open "$app" || true; fi
            else
                printf 'The previous app is backed up at %s/previous.app\n' "$stage" >&2
                stage=""
            fi
        fi
    fi
    if [[ -n "$stage" ]]; then /bin/rm -rf "$stage"; fi
    /bin/rm -rf "$work"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Building X1605VA Assistant %s…\n' "$version"
/usr/bin/git clone --quiet --no-checkout --filter=blob:none --depth 1 --branch "$tag" "$repo" "$work/source"
cd "$work/source"
[[ "$(/usr/bin/git rev-parse 'HEAD^{commit}')" == "$commit" ]] ||
    fail "The release tag does not match the published source commit."
project="Projects/ASUS/X1605VAAssistant"
/usr/bin/git sparse-checkout set --cone "$project"
/usr/bin/git checkout --quiet --detach "$commit"
cd "$project"

# Build only the menu-bar app, using the released sources and icon builder.
# The full build script also compiles the firmware payload and needs extra tools.
mkdir -p build/obj "build/$app_name/Contents/"{MacOS,Resources}
flags=(-arch x86_64 -mmacosx-version-min=11.0 -O2 -Wall -Wextra -Werror)
for source in app-setup menu; do
    /usr/bin/xcrun clang "${flags[@]}" -fobjc-arc -c "Agent/$source.m" -o "build/obj/$source.o"
done
for source in X1605VAAssistant mic-mute; do
    /usr/bin/xcrun clang "${flags[@]}" -fblocks -Wno-unused-parameter -c "Agent/$source.c" -o "build/obj/$source.o"
done
built="build/$app_name"
executable="$built/Contents/MacOS/X1605VAAssistant"
/usr/bin/xcrun clang -arch x86_64 -mmacosx-version-min=11.0 build/obj/*.o \
    -framework CoreServices -framework Cocoa -framework QuartzCore -framework CoreImage \
    -framework IOKit -framework CoreAudio -framework CoreFoundation -framework ApplicationServices \
    -framework Carbon -o "$executable"
/bin/bash Icon/build-icon.sh "$built/Contents/Resources"
/bin/cp Agent/App-Info.plist "$built/Contents/Info.plist"
/bin/cp Uninstall.command "$built/Contents/Resources/"
/bin/chmod +x "$built/Contents/Resources/Uninstall.command"
[[ "$(plist_value "$built" CFBundleIdentifier)" == "$bundle_id" &&
   "$(plist_value "$built" CFBundleShortVersionString)" == "$version" ]] ||
    fail "The built app did not match the release."
/usr/bin/codesign --force --sign - "$executable"
/usr/bin/codesign --force --sign - --identifier "$bundle_id" "$built"
/usr/bin/codesign --verify --strict --deep "$built"

stage="$(/usr/bin/mktemp -d /Applications/.x1605va-assistant.XXXXXXXX)" ||
    fail "Your account needs write access to Applications."
/usr/bin/ditto "$built" "$stage/new.app"
/usr/bin/codesign --verify --strict --deep "$stage/new.app"

uid="$(/usr/bin/id -u)"
assistant_running() {
    local result
    if /usr/bin/pgrep -u "$uid" -f "$process_pattern" >/dev/null; then return 0; else result=$?; fi
    [[ "$result" == 1 ]] || fail "Could not check whether the Assistant is running."
    return 1
}
if assistant_running; then
    was_running=1
    /usr/bin/pkill -TERM -u "$uid" -f "$process_pattern" || true
    for attempt in {1..20}; do
        assistant_running || break
        /bin/sleep 0.25
    done
    if assistant_running; then
        fail "The running Assistant did not quit. Close it in Activity Monitor and try again."
    fi
fi

if [[ -e "$app" || -L "$app" ]]; then
    [[ -d "$app" && ! -L "$app" && "$(plist_value "$app" CFBundleIdentifier)" == "$bundle_id" &&
       "$(plist_value "$app" CFBundleShortVersionString)" == "$installed_version" ]] ||
        fail "The Applications copy changed during the build. Run the installer again."
    rename_bundle "$app" "$stage/previous.app"
fi
install_attempted=1
rename_bundle "$stage/new.app" "$app"
/usr/bin/codesign --verify --strict --deep "$app"
/usr/bin/open "$app"
committed=1
printf 'Installed X1605VA Assistant %s. If prompted, approve the Applications copy in Accessibility.\n' "$version"
