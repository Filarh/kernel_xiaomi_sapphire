#!/usr/bin/env bash
# Registra una ROM: añade su commit de kernel a ci/kernels.txt y genera su referencia de
# compatibilidad en ci/roms (CRC que piden sus módulos y layout de las estructuras que usan).
# Necesita payload-dumper-go, fsck.erofs (erofs-utils), lz4, cpio y python3.
# Uso: ci/registrar-rom.sh <rom.zip>
set -euo pipefail
CI="$(cd "$(dirname "$0")" && pwd)"
src="$1"; tmp=$(mktemp -d); trap 'rm -rf "${tmp:?}"' EXIT
payload-dumper-go -p boot,vendor_boot,vendor_dlkm,system_dlkm -o "$tmp/img" "$src" >/dev/null
for p in vendor_dlkm system_dlkm; do mkdir -p "$tmp/$p"; fsck.erofs --extract="$tmp/$p" "$tmp/img/$p.img" >/dev/null; done
python3 - "$tmp" <<'PY'
import struct, sys, os
t = sys.argv[1]
def unpack(img, out):
    d = open(img, 'rb').read()
    if d[:8] == b'ANDROID!':          # boot v3/v4: kernel tras la cabecera de 4096
        ks, = struct.unpack_from('<I', d, 8); open(out, 'wb').write(d[4096:4096 + ks])
    elif d[:8] == b'VNDRBOOT':        # vendor_boot v4: ramdisk tras cabecera y página
        page, = struct.unpack_from('<I', d, 12); rs, = struct.unpack_from('<I', d, 24)
        hdr = 2128; off = (hdr + page - 1) // page * page
        open(out, 'wb').write(d[off: off + rs])
unpack(f'{t}/img/boot.img', f'{t}/kernel')
unpack(f'{t}/img/vendor_boot.img', f'{t}/vramdisk.lz4')
PY
mkdir -p "$tmp/vramdisk"; (cd "$tmp/vramdisk" && lz4 -dc ../vramdisk.lz4 | cpio -idmu 2>/dev/null)
krel=$(LC_ALL=C grep -a -o -m1 'Linux version 5[^ ]*' "$tmp/kernel" | cut -d' ' -f3)
corto=${krel##*-g}
sha=$(gh api "repos/The-Angel-Place-Sapphire/kernel_xiaomi_sapphire/commits/$corto" --jq .sha)
grep -q "^$sha" "$CI/kernels.txt" || echo "$sha  # $krel, $(basename "$src")" >> "$CI/kernels.txt"
python3 -I "$CI/rom-ref.py" "$tmp/kernel" "$CI/roms" "$tmp/vendor_dlkm" "$tmp/system_dlkm" "$tmp/vramdisk"
echo "registrada: $krel ($sha)"
