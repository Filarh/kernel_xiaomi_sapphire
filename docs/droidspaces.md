# Droidspaces on a GKI 5.15 kernel

[Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) runs full Linux distributions as containers on the phone's own kernel, each with its own init (systemd, OpenRC…). It needs kernel features that stock GKI kernels leave out. On a GKI device some of those features change core structures, so turning them on naively breaks the vendor modules and the phone bootloops. This page records what is safe on sapphire and why.

## The kABI problem

`CONFIG_SYSVIPC` adds `struct sysv_sem sysvsem` (8 bytes) and `struct sysv_shm sysvshm` (16 bytes) in the middle of `struct task_struct`. Measured on these trees, enabling it without a patch grows `task_struct` from 4 608 to 4 672 bytes, moves `android_vendor_data1` (used by the WALT scheduler module) from offset 2880 to 2904, and changes 1 745 of the 2 622 CRCs the ROM modules import. None of the 340 `vendor_dlkm` modules would load.

Droidspaces ships patches that move those fields into the `ANDROID_KABI_RESERVE` padding at the end of `task_struct`. `001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch` does:

```c
#ifdef CONFIG_SYSVIPC
	ANDROID_KABI_USE(6, struct sysv_sem sysvsem);
	_ANDROID_KABI_REPLACE(ANDROID_KABI_RESERVE(7); ANDROID_KABI_RESERVE(8), struct sysv_shm sysvshm);
#else
	...
```

## Which slot patch

| Patch | Slots | 5.15.194 (`3a2cfe72`) | 5.15.220 (`097cabf8`) | 5.15.223 (`9860b31b`) |
|---|---|---|---|---|
| `1_2_3` | 1, 2, 3 | applies | **slot 1 already used by ACK** (`user_dumpable`) | **slot 1 already used by ACK** |
| `3_4_5` | 3, 4, 5 | applies | applies | applies |
| `6_7_8` | 6, 7, 8 | applies | applies | applies |

`6_7_8` is used. Slots 6–8 of `task_struct` (offsets 3488–3511) are `android_kabi_reserved*` in both registered ROMs, and nothing in Angel's tree, the external modules, BakaSU `7b65bde0` or susfs v2.4.0 uses them. Older susfs releases (v1.5.3) write `android_kabi_reserved8`; with those, `3_4_5` would be the choice.

The `002` patch (POSIX mqueue padding) is only for kernels 5.10 and older and is not applied. The `non-GKI` patches are for 4.x kernels and must not be applied to a GKI tree.

## Options

Droidspaces' own documentation for GKI kernels says to enable its list and "do not turn on anything beyond them". The build enables that list (required + recommended) plus `TMPFS_POSIX_ACL` and `TMPFS_XATTR`, which were measured to be neutral. With the patch and all of these, CI measures 0 CRC changes and 0 layout changes in the structures used by modules, on all three commits and for both registered ROMs.

Options that only add code (no field in a structure exported to modules): `PID_NS`, `USER_NS`, `IPC_NS`, `POSIX_MQUEUE`, `DEVTMPFS`, `MACVLAN`, `IP_SET*`, `TMPFS_*` and the `XT_*` matches/targets in the list.

### Options that break the vendor modules

Measured one at a time on 5.15.223, against the 2 622 symbols and 340 modules of the ROM:

| Option | CRCs changed | Modules rejected | Cause |
|---|---|---|---|
| `CGROUP_DEVICE` | 961, incl. `module_layout` | 340 | `css_set` 424→448 bytes, cgroup subsystem ids shift (`freezer_cgrp_id` 5→6) |
| `CGROUP_PIDS` | 961, incl. `module_layout` | 340 | `css_set` 424→448 bytes |
| `BRIDGE_NETFILTER` | 291 | 262 | new `SKB_EXT_BRIDGE_NF` shifts `SKB_EXT_SEC_PATH` 0→1 |
| `NF_TABLES` | 269 | 262 | `struct net` 3904→3968 bytes |
| `CFS_BANDWIDTH` | 31 | 17, incl. `sched-walt`, `msm_drm`, `dwc3-msm` | `struct rq` 4544→4608 bytes |

Some vendor modules read these offsets directly: WALT uses the `android_vendor_data1` areas of `task_struct`, `rq` and `task_group`; Xiaomi's millet module reads `css_set.dfl_cgrp`.

## A build that bootloops

A community workflow (`OneeePu/kernel-sapphire-builder`, release `build-2`, KernelSU-Next + Droidspaces) produced `5.15.220-g097cabf8b0a9-dirty`. Compared with Angel's 5.15.220 built from the same commit, 6 563 of its 15 577 exported symbols have a different CRC, `module_layout` included, so the kernel rejects the vendor modules. Causes, from the workflow and its run log:

1. It enables the non-GKI Droidspaces option list, including `CGROUP_DEVICE` and `BRIDGE_NETFILTER`.
2. Its defconfig auto-detection (`find | sort | head -n1`) picks `vendor/sapphire_GKI.config` (uppercase `G` sorts before `d`) and prepends `gki_defconfig`, instead of `vendor/sapphire_defconfig`. That also drops `ARCH_BENGAL`, `kvm-arm.mode=protected`, `UNMAP_KERNEL_AT_EL0` and many vendor modules.
3. It applies every Droidspaces patch that passes `git apply --check`, including the non-GKI cgroup patch.
4. It builds with Ubuntu clang 20.1.8 and without Lineage's `KCFLAGS` (lower risk).

The `6_7_8` patch itself was applied correctly; the bootloop comes from the options and the base config.
