#!/usr/bin/env bash
# Compila el Image de sapphire. Uso: ci/build.sh <base|bakasu>
set -euo pipefail
VARIANT="$1"
KREL_EXPECTED="5.15.194-g3a2cfe72b3b0"   # versión del kernel instalado (uname -r)
CLANG_COMMIT=70a12c4fe88940ab2b0e6d763492dffa2f07e15a
SUSFS_COMMIT=c1d1da42b74771944207ec45aaceff9c57e84985    # simonpunk/susfs4ksu gki-android13-5.15
BAKASU_COMMIT=7b65bde0710b5e7c6f755545cb15a4abd417f3a8   # Baka-SU/BakaSU main
ROOT="$PWD"
WORK="${RUNNER_TEMP:-/tmp}"
OUT="$ROOT/out"
DIST="$ROOT/dist/$VARIANT"
mkdir -p "$DIST"

# Toolchain: clang r547379 de AOSP (el mismo que TARGET_KERNEL_CLANG_VERSION)
if [ ! -x "$WORK/clang/bin/clang" ]; then
  mkdir -p "$WORK/clang"
  curl -fsSL "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/$CLANG_COMMIT/clang-r547379.tar.gz" \
    | tar -xz -C "$WORK/clang"
fi
export PATH="$WORK/clang/bin:$PATH"
clang --version | head -1

if [ "$VARIANT" = bakasu ]; then
  # 1) susfs, parte de kernel
  git clone -q https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android13-5.15 "$WORK/susfs"
  git -C "$WORK/susfs" checkout -q "$SUSFS_COMMIT"
  cp "$WORK/susfs/kernel_patches/fs/susfs.c" fs/
  cp "$WORK/susfs/kernel_patches/include/linux/susfs.h" "$WORK/susfs/kernel_patches/include/linux/susfs_def.h" include/linux/
  if ! patch -p1 -N --no-backup-if-mismatch -r - < "$WORK/susfs/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch" | tee "$DIST/susfs-patch.log"; then
    echo "::error::el parche de susfs no aplica limpio"; grep -nE "FAILED|rej|offset|fuzz" "$DIST/susfs-patch.log" || true; exit 1
  fi
  grep -nE "offset|fuzz" "$DIST/susfs-patch.log" || true
  # 2) BakaSU
  git clone -q https://github.com/Baka-SU/BakaSU.git KernelSU
  git -C KernelSU checkout -q "$BAKASU_COMMIT"
  ln -sfn ../KernelSU/kernel drivers/kernelsu
  grep -q kernelsu drivers/Makefile || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> drivers/Makefile
  grep -q 'drivers/kernelsu/Kconfig' drivers/Kconfig || sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig
fi

MAKE=(make -j"$(nproc)" O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1
      CROSS_COMPILE=aarch64-linux-gnu- BOARD_PLATFORM=bengal
      KCFLAGS="-D__ANDROID_COMMON_KERNEL__ -Wno-error=strict-prototypes -Wno-error=implicit-int -Wno-error=enum-conversion -Wno-error=shift-count-overflow -Wno-error=constant-conversion"
      LOCALVERSION=-g3a2cfe72b3b0)

"${MAKE[@]}" vendor/sapphire_defconfig
scripts/config --file "$OUT/.config" -d LOCALVERSION_AUTO --set-str LOCALVERSION ""
if [ "$VARIANT" = bakasu ]; then
  scripts/config --file "$OUT/.config" -e KSU -d KSU_DEBUG \
    -d KSU_TRACEPOINT_HOOK -d KSU_MANUAL_HOOK -e KSU_SUSFS \
    -e KSU_SUSFS_SUS_PATH -e KSU_SUSFS_SUS_MOUNT -e KSU_SUSFS_SUS_KSTAT \
    -e KSU_SUSFS_SPOOF_UNAME -e KSU_SUSFS_ENABLE_LOG -e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
    -e KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG -e KSU_SUSFS_OPEN_REDIRECT -e KSU_SUSFS_SUS_MAP
fi
"${MAKE[@]}" olddefconfig
grep -E '^(# )?CONFIG_(KSU|LOCALVERSION)' "$OUT/.config" || true
if [ "$VARIANT" = bakasu ]; then
  for c in KSU KSU_SUSFS; do grep -q "^CONFIG_$c=y" "$OUT/.config" || { echo "::error::CONFIG_$c no quedó en y"; exit 1; }; done
fi

"${MAKE[@]}" Image 2>&1 | tee "$DIST/build.log" | grep -E "warning: |error: |KernelSU|SUSFS|BakaSU|^-- " || true
[ "${PIPESTATUS[0]}" -eq 0 ] || { tail -50 "$DIST/build.log"; exit 1; }

KREL=$(cat "$OUT/include/config/kernel.release")
echo "kernel.release = $KREL"
[ "$KREL" = "$KREL_EXPECTED" ] || { echo "::error::kernel.release $KREL != $KREL_EXPECTED"; exit 1; }

cp "$OUT/arch/arm64/boot/Image" "$OUT/.config" "$OUT/vmlinux.symvers" "$OUT/System.map" "$DIST/"
strings "$OUT/arch/arm64/boot/Image" | grep -m1 "Linux version" > "$DIST/version.txt"
sha256sum "$DIST"/Image | tee "$DIST/Image.sha256"
