#!/usr/bin/env python3
"""romcheck: ¿este kernel sirve para cada ROM registrada en ci/roms?
Regla GKI: un kernel sirve para una ROM si es del mismo código o MÁS NUEVO dentro de la misma
rama (5.15), y además:
  1) cada símbolo que piden sus módulos tiene el mismo CRC en vmlinux.symvers (CONFIG_MODVERSIONS);
  2) cada struct/union que usan sus módulos conserva tamaño y offsets; la única diferencia admitida
     es ocupar un hueco ANDROID_KABI_RESERVE(n) que la ROM tiene libre (lo que hace ANDROID_KABI_USE),
     porque los módulos de la ROM no leen ese hueco.
Un kernel más viejo que la ROM no se admite: sus módulos pueden usar huecos que ese kernel no rellena.
Uso: romcheck.py Image vmlinux.symvers DIR_ROMS   -> imprime la matriz y escribe 'roms-ok' al lado del Image
Sale 1 si el kernel no sirve para la ROM de su mismo código cuando está registrada."""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import btflib

def ver(rel): return tuple(int(x) for x in re.match(r'(\d+)\.(\d+)\.(\d+)', rel).groups())

image, symvers_p, roms = sys.argv[1:4]
img = open(image, 'rb').read(); i = img.find(b'Linux version 5'); krel = img[i:i + 80].split(b' ')[2].decode()
symvers = {}
for l in open(symvers_p):
    p = l.rstrip('\n').split('\t')
    if len(p) >= 2: symvers[p[1]] = int(p[0], 16)
types, _ = btflib.load_base(image)
lay = btflib.layouts(types)

def layout_ok(ref_layouts, new_layouts):
    """True si cada layout de la ROM tiene un layout igual en el kernel, o uno que solo se diferencia
    en miembros android_kabi_reservedN sustituidos en el mismo offset (ANDROID_KABI_USE)."""
    for rsz, rms in ref_layouts:
        ok = False
        for nsz, nms in new_layouts:
            if nsz != rsz: continue
            nms = [tuple(m[:2]) + (m[2],) for m in nms]; rms_t = [tuple(m) for m in rms]
            if nms == rms_t: ok = True; break
            if len(nms) != len(rms_t): continue
            if all(a == b or (a[0].startswith('android_kabi_reserved') and a[1] == b[1]) for a, b in zip(rms_t, nms)):
                ok = True; break
        if not ok: return False
    return True

ok_roms = []; propia_falla = False
for f in sorted(os.listdir(roms)):
    if not f.endswith('.layout.json'): continue
    ref = json.load(open(os.path.join(roms, f))); rrel = ref['release']
    motivos = []
    if ver(krel)[:2] != ver(rrel)[:2]: motivos.append('otra rama')
    elif ver(krel) < ver(rrel): motivos.append('kernel más viejo que la ROM')
    crc_mal = []
    for l in open(os.path.join(roms, rrel + '.kmi')):
        c, s = l.split(); c = int(c, 16)
        if symvers.get(s) != c: crc_mal.append(s)
    if crc_mal: motivos.append(f'{len(crc_mal)} CRC distintos ({", ".join(crc_mal[:4])})')
    lay_mal = []
    for k, v in ref['estructuras'].items():
        kind, name = k.split(' ', 1)
        nl = [[sz, [list(m) for m in ms]] for sz, ms in lay.get((kind, name), set())]
        if not nl or not layout_ok(v['layouts'], nl): lay_mal.append(f"{k} ({len(v['modulos'])} módulos: {', '.join(v['modulos'][:3])})")
    if lay_mal: motivos.append(f'{len(lay_mal)} estructuras con otro layout: ' + '; '.join(lay_mal[:6]))
    estado = 'OK' if not motivos else 'NO'
    print(f'{krel} en ROM {rrel}: {estado}' + ('' if not motivos else ' — ' + ' | '.join(motivos)))
    if not motivos: ok_roms.append(rrel)
    elif rrel == krel: propia_falla = True
with open(os.path.join(os.path.dirname(image), 'roms-ok'), 'w') as fh:
    fh.write(''.join(r + '\n' for r in ok_roms))
sys.exit(1 if propia_falla else 0)
