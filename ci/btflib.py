#!/usr/bin/env python3
"""btflib: lectura de BTF (vmlinux y split BTF de módulos). Ver ci/rom-ref.py y ci/romcheck.py.
btfmods: ¿algún módulo de la ROM usa una estructura cuyo layout cambia en el kernel nuevo?
Cada .ko lleva BTF dividido (split BTF) sobre el BTF del vmlinux de la ROM. Se recogen las
estructuras/uniones del vmlinux que el módulo referencia (directamente o a través de
punteros, typedefs, const, arrays, prototipos y miembros de sus propios tipos) y se cruzan
con las que cambian de layout (tamaño u offsets/miembros) entre el BTF de la ROM y el nuevo.
Uso: btfmods.py ROM.btf|ROM_Image NUEVO_Image DIR_MODULOS...   (sale 1 si algún módulo está afectado)"""
import os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

KIND = {1:'int',2:'ptr',3:'array',4:'struct',5:'union',6:'enum',7:'fwd',8:'typedef',9:'volatile',
        10:'const',11:'restrict',12:'func',13:'func_proto',14:'var',15:'datasec',16:'float',
        17:'decl_tag',18:'type_tag',19:'enum64'}

def find_btf(data):
    best = None; i = data.find(b'\x9f\xeb\x01\x00')
    while i != -1:
        hl, to, tl, so, sl = struct.unpack_from('<IIIII', data, i + 4)
        if hl == 24 and to == 0 and so == tl and 0 < tl < 64 << 20 and i + hl + so + sl <= len(data):
            if best is None or tl > best[1]: best = (i, tl)
        i = data.find(b'\x9f\xeb\x01\x00', i + 4)
    return best[0]

def parse(blob, off, first_id=1, strs_base=None):
    hl, to, tl, so, sl = struct.unpack_from('<IIIII', blob, off + 4)
    tb = off + hl + to; sb = off + hl + so
    base_len = len(strs_base) if strs_base is not None else 0
    own = blob[sb: sb + sl]
    def s(o):
        if strs_base is not None and o < base_len:
            return strs_base[o: strs_base.index(b'\0', o)].decode()
        o -= base_len
        return own[o: own.index(b'\0', o)].decode()
    types = {}; p = tb; end = tb + tl; tid = first_id
    while p < end:
        name_off, info, st = struct.unpack_from('<III', blob, p); p += 12
        kind = KIND.get((info >> 24) & 0x1f); vlen = info & 0xffff; kflag = info >> 31
        t = {'kind': kind, 'name': s(name_off), 'st': st, 'refs': []}
        if kind in ('ptr', 'typedef', 'volatile', 'const', 'restrict', 'func', 'var', 'type_tag', 'decl_tag'):
            t['refs'].append(st)
        if kind == 'int': p += 4
        elif kind == 'array':
            et, it, n = struct.unpack_from('<III', blob, p); p += 12; t['refs'].append(et)
        elif kind in ('struct', 'union'):
            ms = []
            for _ in range(vlen):
                mn, mt, mo = struct.unpack_from('<III', blob, p); p += 12
                ms.append((s(mn), mt, mo & 0xffffff if kflag else mo)); t['refs'].append(mt)
            t['members'] = ms
        elif kind in ('enum',): p += 8 * vlen
        elif kind == 'enum64': p += 12 * vlen
        elif kind == 'func_proto':
            t['refs'].append(st)
            for _ in range(vlen):
                _, at = struct.unpack_from('<II', blob, p); p += 8; t['refs'].append(at)
        elif kind == 'var': p += 4
        elif kind == 'datasec':
            for _ in range(vlen):
                vt, _, _ = struct.unpack_from('<III', blob, p); p += 12; t['refs'].append(vt)
        elif kind == 'decl_tag': p += 4
        types[tid] = t; tid += 1
    return types, own if strs_base is None else None

def load_base(path):
    d = open(path, 'rb').read(); o = find_btf(d)
    hl, to, tl, so, sl = struct.unpack_from('<IIIII', d, o + 4)
    types, strs = parse(d, o)
    return types, d[o + hl + so: o + hl + so + sl]

def name_of(types, tid, depth=0):
    t = types.get(tid)
    if not t: return 'void'
    if t['kind'] in ('ptr',): return name_of(types, t['st'], depth) + '*'
    if t['kind'] in ('const', 'volatile', 'restrict', 'type_tag') or (t['kind'] == 'typedef' and not t['name']):
        return name_of(types, t['st'], depth)
    if t['kind'] == 'array': return name_of(types, t['refs'][0], depth) + '[]'
    if t['kind'] in ('struct', 'union') and not t['name'] and depth < 2:
        return t['kind'] + '{' + ','.join(f"{m[0]}@{m[2]}" for m in t['members']) + '}'
    return f"{t['kind']} {t['name']}"

def layouts(types):
    out = {}
    for tid, t in types.items():
        if t['kind'] in ('struct', 'union') and t['name']:
            out.setdefault((t['kind'], t['name']), set()).add(
                (t['st'], tuple((m[0], m[2], name_of(types, m[1])) for m in t['members'])))
    return out

