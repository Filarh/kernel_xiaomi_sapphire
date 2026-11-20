#!/usr/bin/env python3
"""rom-ref: referencia de compatibilidad de una ROM, para ci/romcheck.py.
  <rel>.kmi          'crc<TAB>símbolo' que los módulos piden a vmlinux (sin los que exportan ellos)
  <rel>.layout.json  layout (tamaño y miembros) de cada struct/union del vmlinux de la ROM que
                     algún módulo referencia en su BTF, con la lista de módulos que la usan
<rel> sale de la cadena 'Linux version' del kernel de la ROM.
Uso: rom-ref.py <kernel Image de la ROM> <dir salida> DIR_MODULOS..."""
import json, os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import btflib

def sections(data):
    shoff, = struct.unpack_from('<Q', data, 0x28)
    se, sn, si = struct.unpack_from('<HHH', data, 0x3a)
    hs = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * se) for i in range(sn)]
    so = hs[si][4]
    return {data[so + h[0]: data.index(b'\0', so + h[0])].decode(): data[h[4]: h[4] + h[5]] for h in hs}

image, outdir, dirs = sys.argv[1], sys.argv[2], sys.argv[3:]
img = open(image, 'rb').read()
i = img.find(b'Linux version 5'); rel = img[i:i + 80].split(b' ')[2].decode()
base_types, base_strs = btflib.load_base(image)
nbase = max(base_types)
lay = btflib.layouts(base_types)
need = {}; exported = set(); usos = {}; n = 0
for d in dirs:
    for r, _, fs in os.walk(d):
        for f in sorted(fs):
            if not f.endswith('.ko'): continue
            data = open(os.path.join(r, f), 'rb').read(); s = sections(data); n += 1
            exported |= {e.decode() for e in s.get('__ksymtab_strings', b'').split(b'\0') if e}
            v = s.get('__versions', b'')
            for o in range(0, len(v), 64):
                crc = struct.unpack_from('<Q', v, o)[0] & 0xffffffff
                name = v[o + 8: o + 64].split(b'\0')[0].decode()
                if need.setdefault(name, crc) != crc: sys.exit(f'CRC inconsistente entre módulos: {name}')
            if '.BTF' not in s: sys.exit(f'{f} sin BTF: no se puede generar la referencia de layout')
            mtypes, _ = btflib.parse(s['.BTF'], 0, nbase + 1, base_strs)
            pila = [x for t in mtypes.values() for x in t['refs']]; vistos = set()
            while pila:
                x = pila.pop()
                if x in vistos or x == 0: continue
                vistos.add(x)
                if x in mtypes: pila.extend(mtypes[x]['refs']); continue
                t = base_types.get(x)
                if not t: continue
                if t['kind'] in ('struct', 'union'):
                    if t['name']: usos.setdefault(f"{t['kind']} {t['name']}", set()).add(f)
                    else: pila.extend(t['refs'])
                else: pila.extend(t['refs'])
os.makedirs(outdir, exist_ok=True)
with open(os.path.join(outdir, rel + '.kmi'), 'w') as fh:
    for name in sorted(set(need) - exported): fh.write(f'0x{need[name]:08x}\t{name}\n')
out = {}
for k, mods in sorted(usos.items()):
    kind, name = k.split(' ', 1)
    out[k] = {'layouts': sorted([[sz, [list(m) for m in ms]] for sz, ms in lay[(kind, name)]]), 'modulos': sorted(mods)}
json.dump({'release': rel, 'modulos': n, 'estructuras': out}, open(os.path.join(outdir, rel + '.layout.json'), 'w'), indent=0, sort_keys=True)
print(f'{rel}: {n} módulos, {len(set(need) - exported)} símbolos de vmlinux, {len(out)} estructuras usadas por módulos')
