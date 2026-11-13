# ASUS Vivobook X1605VA Hackintosh

> **Development snapshot:** this EFI is not ready for installation or daily use.

OpenCore configurations and supporting projects for the ASUS Vivobook X1605VA.
The i5-13500H and i9-13900H variants were tested on **macOS Tahoe 26.7.2**
with **OpenCore 1.0.8**.

## Before you start

This project is hardware-specific. Do not copy its EFI to another laptop
without understanding and adapting its ACPI tables, device paths, SMBIOS, and
kernel extensions. Always keep a known-good recovery EFI.

### BIOS settings

Disable:

- Secure Boot
- Fast Boot
- VMD

### Graphics acceleration

Intel Xe acceleration requires additional macOS graphics patches. Follow the
[graphics installation guide](docs/INSTALL.md) after macOS boots through
OpenCore.

## Hardware status

| Component | Status | Notes |
| :--- | :--- | :--- |
| CPU | ✅ Working | Intel Core i5-13500H (12 cores, 16 threads), or i9-13900H (14 cores, 20 threads). |
| Graphics | ✅ Working with patches | Intel Iris Xe (`8086:a7a0`). Requires the macOS graphics patches described in the [graphics guide](docs/ASUS-GRAPHICS.md). |
| Display | ⚠️ | Internal `CMN1618` panel, 1920 × 1200 at 60 Hz. Native slider is not yet resolved. |
| Wi-Fi | ❌ | Disabled with an SSDT. |
| Bluetooth | ❌ | Disabled with a kernel patch. |
| Audio and microphone | ✅ Working | Realtek ALC256 (`10ec:0256`) using a fork of [AppleALC](https://github.com/samuelnotfound/AppleALC). |
| Trackpad | ✅ Working in macOS | ELAN/ASUS Precision Touchpad (`ASUE1306` / `PNP0C50`) over Intel I²C (`8086:51e9`) using a fork of [VoodooI2C](https://github.com/samuelnotfound/VoodooI2C). Interrupt mode: APIC. |
| Webcam | ✅ Working | USB 2.0 HD UVC webcam (`3277:0036`). |
| Fingerprint reader | ❌ Unsupported | ELAN (`04f3:0c90`, USB). |
| USB controller | ✅ Working | Intel xHCI (`8086:51ed`). |

## Other features

| Feature | Status | Notes |
| :--- | :--- | :--- |
| Screen brightness | ⚠️ Partial | Works with [xe-brilho](https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe/blob/main/docs/INSTALL.md#after-the-first-accelerated-boot); the native brightness slider does not work. |
| Sleep and wake | ❌ Broken | — |
| HDMI | ❌ Broken | Needs upstream fixes. |
| Fan reading and sensors | ❌ Broken | — |

## OpenCore touchpad driver

[AsusX1605VATouchpadDxe](Projects/ASUS/AsusX1605VATouchpadDxe) enables the
built-in touchpad in the OpenCore picker before macOS starts.

## Guides and related projects

- [Installation and update guide](docs/INSTALL.md)
- [Graphics patch guide](docs/ASUS-GRAPHICS.md)
- [AsusX1605VATouchpadDxe](Projects/ASUS/AsusX1605VATouchpadDxe)

## Future plans

- [ ] Improve documentation.
- [ ] **Migrate graphics patches to WhateverXe** once it becomes stable.
- [ ] **Fix remaining hardware features:**
  - [ ] Sleep
  - [ ] Fan reading and control
  - [ ] HDMI
  - [ ] Fn + F9 mute
  - [ ] Other unresolved features

## Credits

- ASUS EFI baseline: [Heitorpoggi's Vivobook project](https://github.com/Heitorpoggi/ASUS-VivoBook-16X-Hackintosh-)
- Reference EFI: [jigyanshu-codes' ASUS-X1504ZA-AlderLake-Hackintosh](https://github.com/jigyanshu-codes/ASUS-X1504ZA-AlderLake-Hackintosh)
- i9-13900H testing: [MrSenaru](https://github.com/MrSenaru)
- OpenCore and bundled kexts, including Lilu, WhateverGreen, VirtualSMC, AppleALC, VoodooPS2, NVMeFix, and RestrictEvents: [Acidanthera and contributors](https://github.com/acidanthera)
- Iris Xe graphics patches and tooling: [JulioNectar's patch guide](https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe/blob/main/docs/INSTALL.md) and [NootedGreen](https://github.com/sgiammori/NootedGreen)
- Bundled VoodooI2C and USBToolBox kexts: [VoodooI2C contributors](https://github.com/VoodooI2C/VoodooI2C) and [USBToolBox contributors](https://github.com/USBToolBox/kext)

Thanks to the authors of all bundled kexts. Additional credits for inherited
patches and tools are listed in the [parent project credits](https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe#credits).

## License and notices

[Repository license](LICENSE) · [Component notices](NOTICE.md)
