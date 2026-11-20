#!/usr/bin/env bash
# Añade a ci/kernels.txt el commit de kernel de una ROM (zip con payload.bin o boot.img suelto).
# Necesita payload-dumper-go si se le da un zip. Uso: ci/registrar-rom.sh <rom.zip|boot.img>
set -euo pipefail
src="$1"; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
case "$src" in
  *.zip) payload-dumper-go -p boot -o "$tmp" "$src" >/dev/null; boot="$tmp/boot.img";;
  *) boot="$src";;
esac
linea=$(LC_ALL=C grep -a -o -m1 'Linux version [0-9][^ ]*' "$boot" | head -1)
krel=${linea#Linux version }
corto=${krel##*-g}
[ ${#corto} -ge 7 ] || { echo "no se encontró -g<commit> en '$krel'"; exit 1; }
sha=$(gh api "repos/The-Angel-Place-Sapphire/kernel_xiaomi_sapphire/commits/$corto" --jq .sha)
if grep -q "^$sha" ci/kernels.txt; then echo "ya estaba: $sha ($krel)"; exit 0; fi
echo "$sha  # $krel, $(basename "$src")" >> ci/kernels.txt
echo "añadido: $sha ($krel)"
