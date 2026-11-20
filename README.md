# sapphire kernel: BakaSU + susfs (+ Droidspaces)

Custom kernel builds for the **Redmi Note 13 4G** (`sapphire` / `sapphiren`, Snapdragon 685 / SM6225), built from the open-source msm-5.15 tree published by [The-Angel-Place-Sapphire](https://github.com/The-Angel-Place-Sapphire/kernel_xiaomi_sapphire).

This branch (`ci/bakasu`) contains only the build tooling. The kernel source is fetched from Angel's repository at build time, so every build is the upstream kernel plus the changes listed below and nothing else.

| Variant | What is added on top of Angel's kernel |
|---|---|
| `bakasu` | [BakaSU](https://github.com/Baka-SU/BakaSU) (KernelSU fork) built into the kernel, and [susfs](https://gitlab.com/simonpunk/susfs4ksu) |
| `bakasu-ds` | the above, plus everything [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) needs to run full Linux distributions as containers |

Both variants ship as a single [AnyKernel3](https://github.com/osm0sis/AnyKernel3) zip that carries several kernels and picks the right one for the phone it is flashed on.

> **Status.** The `bakasu-ds` zip has been flashed and booted on a real device (Lunaris 3.13, 2026-11-16 build): no vendor module was rejected, root works, and every Droidspaces kernel feature passes the on-device test in [`ci/tests/ds-syscalls.c`](ci/tests/ds-syscalls.c). Running actual Droidspaces containers on it has not been tested yet. See [docs/testing.md](docs/testing.md).

## Contents

- [Downloads](#downloads)
- [What is in the kernel](#what-is-in-the-kernel)
- [Which ROMs it works on](#which-roms-it-works-on)
- [Installing](#installing)
- [How the build works](#how-the-build-works)
- [Supporting a new ROM](#supporting-a-new-rom)
- [Repository layout](#repository-layout)
- [Further documentation](#further-documentation)
- [Credits and licenses](#credits-and-licenses)

## Downloads

Zips are produced by the [GitHub Actions workflow](../../actions/workflows/sapphire-image.yml) and attached to each run as the `sapphire-bakasu-anykernel3` artifact (kept 30 days):

```
bakasu/sapphire-bakasu-<bakasu>-susfs-<susfs>-AnyKernel3.zip
bakasu/compatibilidad.txt
bakasu-droidspaces/sapphire-bakasu-<bakasu>-susfs-<susfs>-droidspaces-AnyKernel3.zip
bakasu-droidspaces/compatibilidad.txt
```

`compatibilidad.txt` is the compatibility matrix computed for that build (kernel × registered ROM, see below). Each zip also has a `.sha256`.

The workflow runs on every push to `ci/**` and once a day; the daily run only builds when Angel's `lineage-23.2` branch has moved or a ROM was registered.

## What is in the kernel

Every kernel is Angel's tree at a given commit, with his `vendor/sapphire_defconfig`, the same toolchain (AOSP clang r547379, build 13290119) and the same `KCFLAGS` as the Lineage build. The kernel release string is the one Lineage produces (`<version>-g<12-char commit>`). On top of that:

### Root: BakaSU + susfs (both variants)

- **BakaSU** v4.2.0-rc3 (commit `7b65bde0`), built in (`CONFIG_KSU=y`), hook mode *SUSFS inline hook*. It accepts the BakaSU, official KernelSU and KOWSU managers.
- **susfs** v2.4.0 (`gki-android13-5.15` branch, commit `c1d1da42`), with all its features enabled: hiding paths, mounts, kstat and maps; spoofing uname and `/proc/bootconfig`; open redirect; hiding its own symbols from `/proc/kallsyms`; logging.
  - On 5.15.194 two include hunks of the susfs patch do not apply because the CLO tree lacks a `trace/hooks` include used as context; [`ci/susfs-fixup.py`](ci/susfs-fixup.py) inserts those lines. Any other failed hunk stops the build.

### Droidspaces (`bakasu-ds` only)

- The kABI patch `001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch` from Droidspaces, which moves `sysvsem` / `sysvshm` into the reserved slots 6, 7 and 8 of `task_struct`. Those slots are free in every supported tree and in every registered ROM.
- The options Droidspaces lists for GKI kernels, and nothing beyond them:

  | Purpose | Options |
  |---|---|
  | Required | `SYSVIPC` `POSIX_MQUEUE` `IPC_NS` `PID_NS` `DEVTMPFS` `NETFILTER_XT_MATCH_ADDRTYPE` |
  | Recommended | `USER_NS`, NAT66 (`IP6_NF_NAT`, `IP6_NF_TARGET_MASQUERADE`), `MACVLAN`, UFW (`IP_NF_TARGET_REJECT`, `IP6_NF_TARGET_REJECT`, `NETFILTER_XT_TARGET_LOG`, `NETFILTER_XT_MATCH_RECENT`), fail2ban (`IP_SET`, `IP_SET_HASH_IP`, `IP_SET_HASH_NET`, `NETFILTER_XT_SET`) |
  | NixOS | `TMPFS_POSIX_ACL` `TMPFS_XATTR` |

- **Deliberately left out**, because each one changes symbol CRCs or the layout of structures that the vendor modules use, so those modules stop loading (measured on 5.15.223, out of the 2 622 symbols and 340 modules of the ROM):

  | Option | CRCs changed | Modules rejected | Layout change |
  |---|---|---|---|
  | `CGROUP_DEVICE` | 961, incl. `module_layout` | 340 | `css_set` 424→448 bytes |
  | `CGROUP_PIDS` | 961, incl. `module_layout` | 340 | `css_set` 424→448 bytes |
  | `BRIDGE_NETFILTER` | 291 | 262 | new `skb_ext` id |
  | `NF_TABLES` | 269 | 262 | `struct net` 3904→3968 bytes |
  | `CFS_BANDWIDTH` | 31 | 17 (incl. WALT, display, USB) | `struct rq` 4544→4608 bytes |

  These are the options that turn a Droidspaces build into a bootloop; see [docs/droidspaces.md](docs/droidspaces.md).

## Which ROMs it works on

What decides whether a kernel works is not the ROM but the **KMI** (Kernel Module Interface) of the vendor modules installed on the phone (`vendor_dlkm`, `system_dlkm` and the `vendor_boot` ramdisk). Only the kernel image is replaced; the modules stay. Google freezes the KMI per GKI branch (`android13-5.15`), which is why a GKI kernel runs on many ROMs.

A kernel from this repository is accepted for a set of vendor modules when all of these hold:

1. **Same GKI branch, same or newer kernel.** Newer GKI kernels fill reserved ABI slots (`ANDROID_KABI_USE`) that older modules ignore. The reverse is unsafe: modules built for 5.15.220 read `task_struct` and `usb_request` slots that a 5.15.194 kernel leaves empty, even though every CRC matches.
2. **Same CRC for every symbol the modules import** (`CONFIG_MODVERSIONS`, the kernel's own rule in `check_version()` / `same_magic()`; the version string in `vermagic` is ignored when CRCs are present).
3. **Same layout for every structure the modules use**, read from the BTF that the ROM's kernel and each module carry. The only accepted difference is a new member placed entirely inside bytes that were `android_kabi_reservedN` padding in the ROM.

Rules 2 and 3 are checked in CI against every registered ROM; rules 1 and 2 are checked again on the phone at install time. Measured results:

| Kernel | Lunaris 3.13 (2026-11-16) modules, 5.15.194 | Lunaris 3.13 (2026-11-17) modules, 5.15.220 | Xiaomi stock modules (`device_xiaomi_sapphire-kernel`, used by VoltageOS and others) |
|---|---|---|---|
| 5.15.194-g3a2cfe72b3b0 | OK | not used: older than the modules | OK (CRC, 485 modules) |
| 5.15.220-g097cabf8b0a9 | OK | OK | OK (CRC) |
| 5.15.223-g9860b31beb0b | OK | OK | OK (CRC) |

The stock Xiaomi modules carry no BTF, so for them only rules 1 and 2 can be checked. The details and the evidence are in [docs/kmi-compatibility.md](docs/kmi-compatibility.md).

## Installing

Flash the zip from a recovery (tested with OrangeFox) or from a kernel-flasher app. The installer:

1. checks that the device is `sapphire` or `sapphiren`;
2. finds the vendor modules: `/vendor_dlkm` and `/system_dlkm` (mounted read-only from `/dev/block/mapper/*_dlkm<slot>` in recovery), plus `/lib/modules` in recovery or the symbols of already-loaded modules from `/proc/kallsyms` in Android;
3. reads the highest `vermagic` among the modules (`kmicheck -r`);
4. picks a kernel:
   - if those modules are a **registered ROM**, only kernels that CI verified for it (CRC + layout), preferring the one built from the same commit;
   - otherwise, kernels of the same branch that are **not older** than the modules, closest first, accepted only if every CRC matches (`kmicheck`);
5. aborts without touching anything if no kernel qualifies;
6. replaces only the kernel inside the active slot's `boot` image (header v4, no ramdisk). `init_boot`, `vendor_boot`, `dtbo` and the modules are left alone.

The output in the recovery log looks like this:

```
Módulos de vendor compilados para: 5.15.194-g3a2cfe72b3b0
Módulos con referencia en el CI: kernels verificados (CRC + layout)
Probando kernel 5.15.194-g3a2cfe72b3b0...
  kmicheck: 592 módulos, 30927 símbolos comprobados, 0 incompatibles
Instalando kernel 5.15.194-g3a2cfe72b3b0
```

Keep a copy of your current `boot` image before flashing. To manage root, install the BakaSU manager (or the official KernelSU manager). Do not keep Magisk in `init_boot` at the same time.

## How the build works

```
matriz ─┬─ build (commit × variant) ──┬─ package ── zips + compatibilidad.txt
        │  ci/build.sh                │  ci/package.sh
        │   ├─ susfs + BakaSU         │
        │   ├─ Droidspaces (ds only)  │
        │   ├─ make Image             │
        │   └─ ci/romcheck.py ────────┘
        └─ ci/matriz.sh: ci/kernels.txt + tip of lineage-23.2
```

- **`ci/matriz.sh`** lists the commits to build: those in [`ci/kernels.txt`](ci/kernels.txt) (the kernels shipped by known ROMs) plus the current tip of Angel's `lineage-23.2`. It also computes a key from the commits and the CI scripts; the daily run is skipped when a zip for that key already exists.
- **`ci/build.sh <variant>`** builds one kernel. It fails if the susfs patch fails anywhere other than the two known include hunks, if the Droidspaces kABI patch does not apply cleanly, if any requested option does not end up as `=y`, if the release string differs from `<kernelversion>-g<commit>`, or if `ci/romcheck.py` rejects the kernel.
- **`ci/romcheck.py`** compares the new `Image` and `vmlinux.symvers` with every reference in [`ci/roms/`](ci/roms) and writes `roms-ok`. A kernel that is rejected by the ROM built from its own commit, or by every registered ROM, fails the build and never reaches a zip.
- **`ci/package.sh`** builds `kmicheck` for arm64, puts every successful kernel with its `vmlinux.symvers` and `roms-ok` under `kernels/<release>/`, and zips it with AnyKernel3 (pinned commit).

All external inputs are pinned: Angel's commits, clang (`android16-qpr2-release` of `platform/prebuilts/clang/host/linux-x86`), BakaSU, susfs, Droidspaces and AnyKernel3.

## Supporting a new ROM

Nothing is needed for a ROM whose vendor modules use the same KMI: the installer accepts it through rules 1 and 2. Registering the ROM adds the layout check (rule 3) and makes CI build the kernel commit it ships:

```sh
# needs payload-dumper-go, erofs-utils (fsck.erofs), lz4, cpio, python3, gh
ci/registrar-rom.sh /path/to/rom.zip
git add ci/kernels.txt ci/roms && git commit -m "ci: register <rom>" && git push
```

The script extracts `boot`, `vendor_boot`, `vendor_dlkm` and `system_dlkm` from the ROM's `payload.bin`, reads the kernel commit from the `Linux version` string, adds it to `ci/kernels.txt`, and writes `ci/roms/<release>.kmi` (symbols and CRCs the modules import from vmlinux) and `ci/roms/<release>.layout.json` (layout of every structure the modules reference, with the list of modules that use it).

## Repository layout

| Path | Purpose |
|---|---|
| [`.github/workflows/sapphire-image.yml`](.github/workflows/sapphire-image.yml) | matrix, builds, packaging, daily schedule |
| [`ci/build.sh`](ci/build.sh) | builds one kernel (variant `bakasu` or `bakasu-ds`) |
| [`ci/package.sh`](ci/package.sh) | builds the AnyKernel3 zip |
| [`ci/anykernel/anykernel.sh`](ci/anykernel/anykernel.sh) | installer logic (kernel selection) |
| [`ci/kmicheck.c`](ci/kmicheck.c) | CRC checker run on the phone (`-r`: modules' version, `-ge`: version compare, `-x`: extra exported symbols) |
| [`ci/romcheck.py`](ci/romcheck.py), [`ci/btflib.py`](ci/btflib.py) | CI check of CRCs and BTF layout against registered ROMs |
| [`ci/rom-ref.py`](ci/rom-ref.py), [`ci/registrar-rom.sh`](ci/registrar-rom.sh) | build a ROM reference |
| [`ci/btfdiff.py`](ci/btfdiff.py) | diff of every struct/union layout between two kernel images |
| [`ci/kernels.txt`](ci/kernels.txt), [`ci/roms/`](ci/roms) | known ROM kernels and their references |
| [`ci/susfs-fixup.py`](ci/susfs-fixup.py) | applies the two susfs include hunks that do not match on 5.15.194 |
| [`ci/tests/ds-syscalls.c`](ci/tests/ds-syscalls.c) | on-device test of the Droidspaces kernel features |

## Further documentation

- [docs/kmi-compatibility.md](docs/kmi-compatibility.md): how compatibility is decided, with the measurements behind each rule.
- [docs/droidspaces.md](docs/droidspaces.md): the kABI patch, the safe and unsafe options, and why a common community build bootloops.
- [docs/testing.md](docs/testing.md): what has been tested on a device and how to repeat it.

## Credits and licenses

- Kernel source: Linux / Android Common Kernel / Qualcomm CLO, as published by The-Angel-Place-Sapphire (GPL-2.0).
- [BakaSU](https://github.com/Baka-SU/BakaSU): kernel part GPL-2.0-only, rest GPL-3.0-or-later.
- [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) by simonpunk.
- [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) by ravindu644 and contributors (kABI patch by nullptr-t-oss).
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3) by osm0sis.
- The CI scripts in `ci/` are provided under the same terms as the kernel (GPL-2.0).
