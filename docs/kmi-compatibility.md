# KMI compatibility

A zip from this repository replaces only the kernel `Image` inside `boot`. The vendor modules of the ROM (`vendor_dlkm`, `system_dlkm`, `vendor_boot` ramdisk) stay as they are, so the new kernel must offer them exactly the interface they were built against. This page explains how that is checked and what the measurements were.

## What the kernel itself checks

With `CONFIG_MODVERSIONS=y` the kernel loads a module only if, for every symbol listed in the module's `__versions` section, the CRC matches the one exported by the running kernel (`kernel/module.c`, `check_version()`). The CRC covers `module_layout`, which in turn covers `struct module`. The first field of `vermagic` (the release string) is ignored when CRCs are present (`same_magic()` skips up to the first space). That is why a kernel with another release string can load the ROM's modules, and why a build that changes CRCs (wrong defconfig, ABI-breaking options) leaves the phone without display, Wi-Fi or audio.

`CONFIG_MODULE_SIG_PROTECT` is enabled, but the protected-symbol lists in Angel's tree (`android/abi_gki_modules_protected`, `android/abi_gki_modules_exports`) are empty, so a module signed with another build's key is only marked as unsigned (taint `E`). `MODULE_SIG_FORCE` is off.

## Why CRCs are not enough

CRCs are computed by genksyms over type definitions, and the `ANDROID_KABI_*` macros deliberately hide some changes from genksyms so that Google can fill reserved padding without changing CRCs. A CRC match therefore says nothing about who fills that padding.

Measured between Angel's 5.15.194 and 5.15.220 kernels: all 2 622 symbols imported by the ROM modules have the same CRC, yet 5.15.220 uses `ANDROID_KABI_USE(1, …)` in two structures the modules use:

| Structure | Slot 1 in 5.15.220 | Modules of the 2026-11-17 ROM that reference it |
|---|---|---|
| `task_struct` | `user_dumpable` | 26 (binder, WALT helpers, Xiaomi millet, minidump, …) |
| `usb_request` | `struct usb_ep *ep` | 7 (dwc3-msm, gadget functions) |

A 5.15.220 module running on a 5.15.194 kernel would read those slots as zero (for `usb_request.ep`, a NULL pointer). A 5.15.194 module running on a 5.15.220 kernel never reads them. Hence rule 1: the kernel must be the same or newer than the modules, never older.

## The three rules

1. Same GKI branch (`5.15`), kernel version ≥ the highest `vermagic` version among the modules.
2. Every imported symbol has the same CRC (`kmicheck`).
3. Every structure referenced by a module keeps its size and all its members at the same offset with the same type. A member that does not exist in the ROM is accepted only if it lies entirely inside bytes that were `android_kabi_reservedN` members in the ROM, possibly spanning adjacent slots (`_ANDROID_KABI_REPLACE`).

## How rule 3 is measured

Angel's kernels are built with `CONFIG_DEBUG_INFO_BTF=y` and `CONFIG_DEBUG_INFO_BTF_MODULES=y`:

- the `Image` contains the BTF of vmlinux (every struct, union, member, offset);
- every `.ko` contains split BTF on top of the vmlinux BTF of the build it came from.

`ci/rom-ref.py` walks each module's split BTF, collects every vmlinux struct/union it references (directly or through pointers, typedefs, arrays, function prototypes and members of its own types) and stores the ROM's layout of each one. For the two Lunaris ROMs that is 661 structures used by 592 modules. `ci/romcheck.py` then reads the BTF of each newly built `Image` and applies rule 3 to those structures.

Controls used to validate the checker:

- Angel's own `Image` against its own ROM: 0 structures changed.
- BakaSU + susfs kernel against its ROM: 4 structures change (`getdents_callback`, `getdents_callback64`, `compat_getdents_callback`, `compat_readdir_callback`, extended by susfs in `fs/readdir.c`); none is referenced by any module.
- 5.15.194 kernel against the 5.15.220 ROM: rejected (`task_struct`, `usb_request`, see above).
- Shifting `task_struct.thread` by 8 bytes in a copy of the reference: rejected.

## On-device check (`kmicheck`)

The installer cannot rely on CI references for ROMs it has never seen, so it runs `kmicheck` (static arm64 binary, [`ci/kmicheck.c`](../ci/kmicheck.c)) against the modules on the phone:

- `kmicheck -r DIR...` prints the highest release found in `vermagic`.
- `kmicheck -ge A B` compares two releases within a branch.
- `kmicheck [-x EXPORTS] vmlinux.symvers DIR...` checks every `__versions` entry. Symbols that vmlinux does not export must be exported by another module of the set; `-x` adds symbols of modules that are not on disk (the `vendor_boot` ramdisk modules, taken from `/proc/kallsyms` in Android; in recovery they are in `/lib/modules`).

Without `-x`, the Xiaomi stock modules showed 203 unresolved symbols, all exported by `vendor_boot` ramdisk modules; with them included, 0.

## Measurements

| Kernel | Module set | Modules | Symbols checked | Incompatible |
|---|---|---|---|---|
| 5.15.194 (BakaSU) | Lunaris 2026-11-16, all partitions | 592 | 30 927 | 0 |
| 5.15.194 (BakaSU) | Lunaris 2026-11-17, all partitions | 592 | 30 945 | 0 (CRC); rejected by rule 1/3 |
| 5.15.220 (BakaSU) | both Lunaris builds | 592 | 30 927 / 30 945 | 0 |
| 5.15.223 (BakaSU) | both Lunaris builds | 592 | 30 927 / 30 945 | 0 |
| all three | Xiaomi stock (`device_xiaomi_sapphire-kernel`, `vermagic` 5.15.94 and 5.15.194) | 485 | 25 926 | 0 |
| 5.15.194 (BakaSU + Droidspaces) | on the phone, OrangeFox, `/vendor_dlkm` + `/system_dlkm` + `/lib/modules` | 592 | 30 927 | 0 |

The Lunaris builds ship different kernels (5.15.194 and 5.15.220) but their modules import exactly the same 2 622 symbols with the same CRCs.
