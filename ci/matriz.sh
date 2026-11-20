#!/usr/bin/env bash
# Lista de commits a compilar: ci/kernels.txt + punta de lineage-23.2 de Angel.
# Escribe en $GITHUB_OUTPUT: bases (JSON) y clave (hash de commits + scripts de CI).
set -euo pipefail
UPSTREAM=https://github.com/The-Angel-Place-Sapphire/kernel_xiaomi_sapphire
RAMA=lineage-23.2
punta=$(git ls-remote "$UPSTREAM" "refs/heads/$RAMA" | cut -f1)
[ -n "$punta" ] || { echo "::error::no se pudo leer la punta de $RAMA"; exit 1; }
bases=$( (grep -oE '^[0-9a-f]{40}' ci/kernels.txt; echo "$punta") | awk '!v[$0]++')
echo "Commits a compilar:"; echo "$bases"
json=$(echo "$bases" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')
clave=$( (echo "$bases"; cat ci/*.sh ci/*.py ci/*.c ci/anykernel/* .github/workflows/*.yml) | sha256sum | cut -c1-16)
echo "bases=$json" >> "$GITHUB_OUTPUT"
echo "clave=$clave" >> "$GITHUB_OUTPUT"
