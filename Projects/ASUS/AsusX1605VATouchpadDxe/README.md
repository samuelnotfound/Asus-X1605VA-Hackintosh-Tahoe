# ASUS X1605VA UEFI Touchpad (Beta)

This x64 UEFI boot driver gives the OpenCore picker pointer input from the
built-in ELAN `04f3:3284` touchpad. It matches the firmware's I²C child for
`ASUE1306` and exposes relative movement and physical button reports through
UEFI Simple Pointer.

> **Beta:** The bundled driver worked in OpenCanopy on the tested X1605VA,
> but it is not guaranteed to work on other firmware revisions.

## Build

Build with Zig 0.14.1 from this directory:

```sh
zig build-exe AsusX1605VATouchpadDxe.zig -target x86_64-uefi-msvc --subsystem efi_boot_service_driver -O ReleaseSafe -femit-bin=AsusX1605VATouchpadDxe-Beta.efi
```

## OpenCore setup

On the tested X1605VA, `LoadEarly = true` was required for automatic input in
OpenCanopy. OpenCore 1.0.8's `ocvalidate` flags this setting for the custom
driver, so review the warning before using it.

1. Copy `AsusX1605VATouchpadDxe-Beta.efi` to `EFI/OC/Drivers/`.
2. Add the driver to `UEFI > Drivers` in `config.plist`.
3. Boot directly into the picker and verify cursor movement and physical clicks.
