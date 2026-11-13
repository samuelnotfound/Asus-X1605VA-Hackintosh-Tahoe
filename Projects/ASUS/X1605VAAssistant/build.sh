#!/bin/bash
# X1605VA Assistant / X1605VAAssistant
set -euo pipefail
cd "$(dirname "$0")"
KERNEL_SDK="${MAC_KERNEL_SDK:-$PWD/Vendor/MacKernelSDK}"
IASL_BIN="${IASL:-iasl}"
if [[ ! -f "$KERNEL_SDK/Headers/IOKit/IOService.h" || ! -f "$KERNEL_SDK/Library/x86_64/libkmod.a" ]]; then
  echo "Set MAC_KERNEL_SDK to a MacKernelSDK checkout; see README.md." >&2
  exit 1
fi
command -v "$IASL_BIN" >/dev/null || { echo "Set IASL to the iasl executable." >&2; exit 1; }
mkdir -p build/obj build/X1605VAAssistant.kext/Contents/MacOS build/ACPI
FLAGS=(-arch x86_64 -mmacosx-version-min=11.0 -mkernel -nostdinc -fno-builtin -fno-common -fno-stack-protector -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -isystem "$(xcrun clang -print-resource-dir)/include" -I"$KERNEL_SDK/Headers" -Os -Wall -Wextra -Werror -Wno-unused-parameter)
xcrun clang++ "${FLAGS[@]}" -fapple-kext -std=gnu++14 -nostdinc++ -fno-exceptions -fno-rtti -fno-use-cxa-atexit -fno-threadsafe-statics -c Driver/X1605VAAssistant.cpp -o build/obj/X1605VAAssistant.o
xcrun clang "${FLAGS[@]}" -c Driver/kmod_info.c -o build/obj/kmod_info.o
xcrun clang++ -arch x86_64 -mmacosx-version-min=11.0 -nostdlib -Xlinker -kext -Xlinker -export_dynamic build/obj/X1605VAAssistant.o build/obj/kmod_info.o -L"$KERNEL_SDK/Library/x86_64" -lkmod -o build/X1605VAAssistant.kext/Contents/MacOS/X1605VAAssistant
cp Driver/Info.plist build/X1605VAAssistant.kext/Contents/Info.plist
xcrun clang -arch x86_64 -mmacosx-version-min=11.0 -O2 -fobjc-arc -Wall -Wextra -Werror -c Agent/app-setup.m -o build/obj/app-setup.o
xcrun clang -arch x86_64 -mmacosx-version-min=11.0 -O2 -fobjc-arc -Wall -Wextra -Werror -c Agent/menu.m -o build/obj/menu.o
xcrun clang -arch x86_64 -mmacosx-version-min=11.0 -O2 -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -c Agent/X1605VAAssistant.c -o build/obj/agent.o
xcrun clang -arch x86_64 -mmacosx-version-min=11.0 -O2 -Wall -Wextra -Werror -c Agent/mic-mute.c -o build/obj/mic-mute.o
FRAMEWORKS=(-framework CoreServices -framework Cocoa -framework QuartzCore -framework CoreImage -framework IOKit -framework CoreAudio -framework CoreFoundation -framework ApplicationServices -framework Carbon)
OBJECTS=(build/obj/agent.o build/obj/mic-mute.o build/obj/app-setup.o build/obj/menu.o)
xcrun clang -arch x86_64 -mmacosx-version-min=11.0 "${OBJECTS[@]}" "${FRAMEWORKS[@]}" -o build/X1605VAAssistant
xcrun clang -arch x86_64 -mmacosx-version-min=11.0 -O2 -Wall -Wextra -Werror Agent/ledctl.c -framework IOKit -framework CoreFoundation -o build/ledctl
acpi_table="SSDT-X1605VA-Assistant"
"$IASL_BIN" -p "build/ACPI/$acpi_table" "ACPI/$acpi_table.dsl"
{
  echo "X1605VA Assistant 0.9.13; X1605VAAssistant driver 0.9.13"
  echo "Bundle: com.samuelnotfound.X1605VAAssistant"
  echo "MacKernelSDK: $(git -C "$KERNEL_SDK" rev-parse HEAD 2>/dev/null || echo unknown)"
  xcrun clang --version | head -n 1
} > build/BUILD-INFO.txt
cp README.md build/README.md
APP_BUNDLE="build/X1605VA Assistant.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
./Icon/build-icon.sh "$APP_BUNDLE/Contents/Resources"
cp Uninstall.command "$APP_BUNDLE/Contents/Resources/"
cp build/X1605VAAssistant "$APP_BUNDLE/Contents/MacOS/X1605VAAssistant"
cp Agent/App-Info.plist "$APP_BUNDLE/Contents/Info.plist"
chmod +x "$APP_BUNDLE/Contents/Resources/Uninstall.command"
for item in build/X1605VAAssistant.kext build/X1605VAAssistant build/ledctl; do
  codesign --force --sign - "$item"
  codesign --verify --strict "$item"
done
codesign --force --sign - --identifier com.samuelnotfound.X1605VAAssistant.Agent "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"
rm -rf build/EFI
mkdir -p build/EFI/OC/Kexts build/EFI/OC/ACPI
ditto build/X1605VAAssistant.kext build/EFI/OC/Kexts/X1605VAAssistant.kext
cp "build/ACPI/$acpi_table.aml" build/EFI/OC/ACPI/
cp "ACPI/$acpi_table.dsl" build/EFI/
plutil -lint build/X1605VAAssistant.kext/Contents/Info.plist
echo "Built $PWD/$APP_BUNDLE and $PWD/build/EFI."
