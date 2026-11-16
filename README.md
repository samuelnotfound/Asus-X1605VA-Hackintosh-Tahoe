# ASUS Vivobook X1605VA Hackintosh

OpenCore for the ASUS Vivobook X1605VA on macOS Tahoe, with custom ASUS device
controls and touchpad support in the OpenCore picker.

**Development EFI.** Keep a bootable recovery copy when updating.

## Included projects

- **[ASUS Control](Projects/ASUS/AsusControl)** — fan profiles, live fan speed,
  touchpad control, function-key mode and keyboard-backlight timeout in System Settings.
- **[ASUS Touchpad UEFI driver](Projects/ASUS/AsusX1605VATouchpadDxe)** — use the
  built-in touchpad in the OpenCore picker before macOS starts.

## Hardware support

For the **i5-13500H and i9-13900H** variants. ASUS Control currently targets **BIOS 305**.

| Feature | Support |
| --- | --- |
| CPU, audio, microphone, touchpad, webcam, USB | Working |
| Intel Iris Xe graphics | Requires [graphics patches](docs/ASUS-GRAPHICS.md) |
| Screen brightness | External utility; native slider unavailable |
| Sleep, HDMI | Unavailable |
| Wi-Fi, Bluetooth | Disabled in this configuration |
| Fingerprint reader | Unsupported |

## Get started

1. Disable **Secure Boot**, **Fast Boot** and **VMD** in BIOS.
2. Configure your own SMBIOS identity and keep a recovery EFI.
3. Follow the [installation guide](docs/INSTALL.md) and [graphics guide](docs/ASUS-GRAPHICS.md).
4. Build [ASUS Control](Projects/ASUS/AsusControl#build-and-install) for device settings.

Graphics patches, the preference pane and the EFI are updated separately. Each
project's README contains its build instructions and version source.

[Credits](docs/CREDITS.md) · [License](LICENSE)
