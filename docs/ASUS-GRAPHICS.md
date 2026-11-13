## Patch guide

Use the ASUS guide for first-time setup and the parent project’s guide for graphics updates. The upstream patch reference targets **Tahoe 26.7.1, build 25G241**. [ASUS install guide](INSTALL.md#install-or-update-the-macos-graphics-patches) · [Upstream graphics updates](https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe/blob/main/docs/INSTALL.md#updating-an-existing-install) · [Kernel patches](KERNEL-PATCHES.md) · [Metal reference](METAL.md)

## Preserved settings

- GPU path: `PciRoot(0x0)/Pci(0x2,0x0)`.
- `device-id` bytes: `499a0000` (Tiger Lake spoof `0x9A49`).
- `AAPL,ig-platform-id` bytes: `0000499a`.
- NootedGreen, Lilu and WhateverGreen remain enabled; WhateverXe stays disabled.
- `ngreen-eu=80 ngreen-l3=6` is preserved, following the parent's 80-EU guidance.
- Existing `-ngreentglwithgfx`, `-allow3d`, `-disablegfxfirmware`, `-ngreenv189`, `-ngreenkeepefi`, `-ngreenxefix`, `-ngreenfixbootmode`, `ngreen-dmc=adlp`, `ngreenSched=4`, `ngreenV142=3` and `gfxrst=1` remain unchanged.
- `NVRAM > Delete` already includes `boot-args` for GUID `7C436110-AB2A-4BBB-A880-FE41995C9F82`, matching the parent's reused-NVRAM procedure.

The imported NootedGreen binary is the supplied working baseline. Its source revision has not been established; its config comment does not prove provenance. Retained parent source may be newer. A rebuild is not necessarily a byte-identical replacement.

