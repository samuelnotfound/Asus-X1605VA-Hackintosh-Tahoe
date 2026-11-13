#!/bin/bash
# AsusMicLED — build kext, agent, SSDT
set -euo pipefail
cd "$(dirname "$0")"

KERNEL_SDK="${MAC_KERNEL_SDK:-$PWD/Vendor/MacKernelSDK}"
IASL_BIN="${IASL:-iasl}"

if [[ ! -f "$KERNEL_SDK/Headers/IOKit/IOService.h" || ! -f "$KERNEL_SDK/Library/x86_64/libkmod.a" ]]; then
  echo "Set MAC_KERNEL_SDK to a MacKernelSDK checkout." >&2
  exit 1
fi
command -v "$IASL_BIN" >/dev/null || { echo "Set IASL to the iasl executable." >&2; exit 1; }

rm -rf build
mkdir -p build/obj build/AsusMicLED.kext/Contents/MacOS build/ACPI build/EFI/OC/{Kexts,ACPI}

# --- kext ---
FLAGS=(-arch x86_64 -mmacosx-version-min=11.0 -mkernel -nostdinc -fno-builtin -fno-common
  -fno-stack-protector -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT
  -isystem "$(xcrun clang -print-resource-dir)/include" -I"$KERNEL_SDK/Headers"
  -Os -Wall -Wextra -Werror -Wno-unused-parameter)

xcrun clang++ "${FLAGS[@]}" -fapple-kext -std=gnu++14 -nostdinc++ -fno-exceptions -fno-rtti \
  -fno-use-cxa-atexit -fno-threadsafe-statics \
  -c Driver/AsusMicLED.cpp -o build/obj/AsusMicLED.o
xcrun clang "${FLAGS[@]}" -c Driver/kmod_info.c -o build/obj/kmod_info.o
xcrun clang++ -arch x86_64 -mmacosx-version-min=11.0 -nostdlib -Xlinker -kext -Xlinker -export_dynamic \
  build/obj/AsusMicLED.o build/obj/kmod_info.o -L"$KERNEL_SDK/Library/x86_64" -lkmod \
  -o build/AsusMicLED.kext/Contents/MacOS/AsusMicLED
cp Driver/Info.plist build/AsusMicLED.kext/Contents/Info.plist

# --- agent ---
xcrun clang -arch x86_64 -mmacosx-version-min=11.0 -O2 -fobjc-arc \
  -Wall -Wextra -Werror \
  -framework Cocoa -framework CoreAudio -framework CoreFoundation -framework IOKit \
  -o build/micled-agent Agent/micled-agent.m Agent/mic-mute.c

# --- ledctl (optional CLI) ---
xcrun clang -arch x86_64 -mmacosx-version-min=11.0 -O2 -Wall -Wextra -Werror \
  Agent/ledctl.c -framework IOKit -framework CoreFoundation -o build/ledctl

# --- SSDT ---
"$IASL_BIN" -p build/ACPI/SSDT-AsusMicLED ACPI/SSDT-AsusMicLED.dsl

# --- package for OpenCore ---
ditto build/AsusMicLED.kext build/EFI/OC/Kexts/AsusMicLED.kext
cp build/ACPI/SSDT-AsusMicLED.aml build/EFI/OC/ACPI/
cp ACPI/SSDT-AsusMicLED.dsl build/EFI/

# --- sign ad-hoc ---
for item in build/AsusMicLED.kext build/micled-agent build/ledctl; do
  codesign --force --sign - "$item"
  codesign --verify --strict "$item"
done
plutil -lint build/AsusMicLED.kext/Contents/Info.plist

{
  echo "AsusMicLED 1.0.0"
  echo "Bundle: com.samuelnotfound.AsusMicLED"
  echo "MacKernelSDK: $(git -C "$KERNEL_SDK" rev-parse HEAD 2>/dev/null || echo unknown)"
  xcrun clang --version | head -n 1
} > build/BUILD-INFO.txt

echo "Built:"
echo "  $PWD/build/AsusMicLED.kext"
echo "  $PWD/build/micled-agent"
echo "  $PWD/build/ledctl"
echo "  $PWD/build/EFI/  (copy Kexts + ACPI into your OC folder)"
