#!/usr/bin/env bash
# Empaqueta uno o varios dist/<build> en un solo zip AnyKernel3. Uso: ci/package.sh SALIDA DIR...
set -euo pipefail
AK3_SHA=41f04bdb4ee30a44e429c2c1131d5e8bb32b15f1   # osm0sis/AnyKernel3, 27 oct 2026
OUTDIR="$1"; shift
ROOT="$PWD"; WORK="${RUNNER_TEMP:-/tmp}/ak3"
rm -rf "$WORK"; git clone -q https://github.com/osm0sis/AnyKernel3.git "$WORK"
git -C "$WORK" checkout -q "$AK3_SHA"
rm -rf "$WORK"/.git "$WORK"/.github "$WORK"/README.md "$WORK"/modules "$WORK"/patch "$WORK"/ramdisk
mkdir -p "$WORK/kernels" "$OUTDIR"
LISTOS=()
for d in "$@"; do
  [ -f "$d/Image" ] && [ -f "$d/kernel.release" ] || { echo "::warning::$d sin Image (build fallido), no entra en el zip"; continue; }
  LISTOS+=("$d")
  krel=$(cat "$d/kernel.release")
  mkdir -p "$WORK/kernels/$krel"
  cp "$d/Image" "$d/vmlinux.symvers" "$d/roms-ok" "$WORK/kernels/$krel/"
  echo "$krel" >> "$WORK/kernels/lista"
done
[ ${#LISTOS[@]} -gt 0 ] || { echo "::error::ningún build terminó"; exit 1; }
sort -V -r -o "$WORK/kernels/lista" "$WORK/kernels/lista"
# ROM con referencia en ci/roms: para ellas solo valen kernels que pasaron ci/romcheck.py
ls "$ROOT/ci/roms" | sed -n 's/\.layout\.json$//p' | sort -V > "$WORK/kernels/roms-registradas"
MAJMIN=$(cut -d. -f1,2 "$WORK/kernels/lista" | sort -u)
[ "$(echo "$MAJMIN" | wc -l)" -eq 1 ] || { echo "::error::kernels de distintas ramas: $MAJMIN"; exit 1; }
BAKASU=$(grep -h -m1 -o 'BakaSU version name: .*' "${LISTOS[0]}/build.log" | cut -d' ' -f4)
SUSFS=$(grep -h -m1 -o 'SUSFS_VERSION: .*' "${LISTOS[0]}/build.log" | cut -d' ' -f2)
KLIST=$(paste -sd, "$WORK/kernels/lista")
DS=""; grep -q "^CONFIG_SYSVIPC=y" "${LISTOS[0]}/config.txt" && DS=" + Droidspaces"
sed -e "s|@KERNEL_STRING@|sapphire BakaSU $BAKASU + susfs $SUSFS$DS ($KLIST)|" -e "s|@KERNEL_MAJMIN@|$MAJMIN|" \
  "$ROOT/ci/anykernel/anykernel.sh" > "$WORK/anykernel.sh"
aarch64-linux-gnu-gcc -O2 -static -Wall -o "$WORK/tools/kmicheck" "$ROOT/ci/kmicheck.c"
aarch64-linux-gnu-strip "$WORK/tools/kmicheck"
EXTRA=""; grep -q "^CONFIG_SYSVIPC=y" "${LISTOS[0]}/config.txt" && EXTRA="-droidspaces"
NAME="sapphire-bakasu-$BAKASU-susfs-$SUSFS$EXTRA-AnyKernel3.zip"
(cd "$WORK" && zip -qr9 "$OUTDIR/$NAME" . -x '.*')
cat "$WORK/kernels/lista"
(cd "$OUTDIR" && sha256sum "$NAME" | tee "$NAME.sha256")
for d in "${LISTOS[@]}"; do cat "$d/romcheck.txt"; done | tee "$OUTDIR/compatibilidad.txt"
