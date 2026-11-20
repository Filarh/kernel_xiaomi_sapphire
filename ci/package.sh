#!/usr/bin/env bash
# Empaqueta dist/<variante> en un zip AnyKernel3. Uso: ci/package.sh <variante>
set -euo pipefail
VARIANT="$1"
AK3_SHA=41f04bdb4ee30a44e429c2c1131d5e8bb32b15f1   # osm0sis/AnyKernel3, 27 oct 2026
ROOT="$PWD"; DIST="$ROOT/dist/$VARIANT"; WORK="${RUNNER_TEMP:-/tmp}/ak3"
rm -rf "$WORK"; git clone -q https://github.com/osm0sis/AnyKernel3.git "$WORK"
git -C "$WORK" checkout -q "$AK3_SHA"
rm -rf "$WORK"/.git "$WORK"/.github "$WORK"/README.md "$WORK"/modules "$WORK"/patch "$WORK"/ramdisk
KREL=$(cat "$DIST/kernel.release")
MAJMIN=$(echo "$KREL" | cut -d. -f1,2)
BAKASU=$(grep -m1 -o 'BakaSU version name: .*' "$DIST/build.log" | cut -d' ' -f4)
SUSFS=$(grep -m1 -o 'SUSFS_VERSION: .*' "$DIST/build.log" | cut -d' ' -f2)
sed -e "s|@KERNEL_STRING@|sapphire $KREL + BakaSU $BAKASU + susfs $SUSFS|" -e "s|@KERNEL_MAJMIN@|$MAJMIN|" \
  "$ROOT/ci/anykernel/anykernel.sh" > "$WORK/anykernel.sh"
cp "$DIST/Image" "$DIST/vmlinux.symvers" "$WORK/"
aarch64-linux-gnu-gcc -O2 -static -Wall -o "$WORK/tools/kmicheck" "$ROOT/ci/kmicheck.c"
aarch64-linux-gnu-strip "$WORK/tools/kmicheck"
NAME="sapphire-$KREL-bakasu-$BAKASU-susfs-$SUSFS-AnyKernel3.zip"
(cd "$WORK" && zip -qr9 "$DIST/$NAME" . -x '.*')
sha256sum "$DIST/$NAME" | tee "$DIST/$NAME.sha256"
