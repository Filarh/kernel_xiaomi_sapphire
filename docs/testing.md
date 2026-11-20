# Testing

## Verified on a device

Device: Redmi Note 13 4G (`sapphire`), Lunaris 3.13 (2026-11-16 build, kernel 5.15.194-g3a2cfe72b3b0), slot `_a`, OrangeFox recovery.

### Installing the `bakasu-ds` zip

Recovery log of the install:

```
Módulos de vendor compilados para: 5.15.194-g3a2cfe72b3b0
Módulos con referencia en el CI: kernels verificados (CRC + layout)
  kmicheck: 592 módulos, 30927 símbolos comprobados, 0 incompatibles
Instalando kernel 5.15.194-g3a2cfe72b3b0
...
Repack to boot image: [/tmp/anykernel/boot-new.img]
Done!
```

`vendor_dlkm_a` and `system_dlkm_a` mount read-only from `/dev/block/mapper/` in OrangeFox, and the arm64 `kmicheck` runs there.

### After boot

| Check | Result |
|---|---|
| `uname -r` | `5.15.194-g3a2cfe72b3b0`, built by CI |
| `/proc/config.gz` | `SYSVIPC`, `POSIX_MQUEUE`, `IPC_NS`, `PID_NS`, `USER_NS`, `DEVTMPFS`, `KSU`, `KSU_SUSFS` = y |
| `dmesg` "disagrees about version" / "Unknown symbol" | 0 |
| Loaded modules | 316 (229 from `modules.load` of `vendor_dlkm`/`system_dlkm`, the rest from the `vendor_boot` ramdisk) |
| Taint | `C`, `O`, `E` (staging, out-of-tree, unsigned modules); no `W` |
| KernelSU | `v4.2.0-rc3-7b65bde0`, work mode Built-in; root granted to `adb shell` from the manager |
| Wi-Fi | enabled and working |

One `Call trace` appears at boot: `sysfs: cannot create duplicate filename '/kernel/dload'` from `qcom_dload_mode` probing twice. `/sys/kernel/dload` exists with `dload_mode` and `emmc_dload`. Whether the same message appears with the original Lunaris kernel is not verified.

### Droidspaces kernel features

[`ci/tests/ds-syscalls.c`](../ci/tests/ds-syscalls.c), static arm64 build, run as root:

| Test | Result |
|---|---|
| SysV shared memory: `shmget` 1 MiB, `shmat`, write | OK |
| SysV semaphores: `semget`, `semop` | OK |
| SysV message queues: `msgget`, `msgsnd`, `msgrcv` | OK |
| POSIX message queues: `mq_open`, `mq_send`; `mount -t mqueue` | OK |
| `unshare` of user, IPC, PID, UTS, net and mount namespaces | OK; the first process in the new PID namespace is PID 1 |
| `mount -t devtmpfs` | OK (181 nodes) |
| `/proc/sys/kernel/{shmmax,msgmax,sem}` | present |

Run as the unprivileged `shell` user, the SysV and mqueue calls return `EACCES` (SELinux policy), not `ENOSYS`.

To repeat:

```sh
zig cc -O2 -static -target aarch64-linux-musl -o ds-syscalls ci/tests/ds-syscalls.c
adb push ds-syscalls /data/local/tmp/
adb shell su -c /data/local/tmp/ds-syscalls
```

## Not tested yet

- Running Droidspaces containers (systemd as PID 1, PostgreSQL, Docker/Podman, NAT/NAT66, macvlan, NixOS).
- Camera, audio, Bluetooth and fingerprint after the kernel change, and long-running use.
- The zip on ROMs that use the Xiaomi stock modules (checked offline only).
- Install from Android (kernel-flasher apps), where the `vendor_boot` ramdisk symbols come from `/proc/kallsyms`.

## Signs of a broken kernel

`disagrees about version of symbol` or `Unknown symbol` in `dmesg`, oops/panics, spontaneous reboots, or vendor hardware (display, Wi-Fi, audio, camera) not coming up. Restore the previous `boot` image if any of these appear.
