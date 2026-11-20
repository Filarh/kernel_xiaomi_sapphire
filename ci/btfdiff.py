#!/usr/bin/env python3
"""btfdiff: compara el layout (tamaño y offsets de miembros) de las estructuras/uniones
entre dos kernels, leyendo el BTF embebido en el Image (o en un .BTF suelto).
Uso: btfdiff.py Image_ref Image_nuevo [--todo]
Imprime estructuras que existen en ambos y cambian de tamaño o de offsets/miembros."""
import struct, sys

KIND = {1:'int',2:'ptr',3:'array',4:'struct',5:'union',6:'enum',7:'fwd',8:'typedef',9:'volatile',
        10:'const',11:'restrict',12:'func',13:'func_proto',14:'var',15:'datasec',16:'float',
        17:'decl_tag',18:'type_tag',19:'enum64'}

def find_btf(data):
    best = None
    i = data.find(b'\x9f\xeb\x01\x00')
    while i != -1:
        hdr_len, type_off, type_len, str_off, str_len = struct.unpack_from('<IIIII', data, i + 4)
        if hdr_len == 24 and type_off == 0 and str_off == type_len and 0 < type_len < 64 << 20:
            end = i + hdr_len + str_off + str_len
            if end <= len(data) and data[i + hdr_len + str_off] == 0:
                if best is None or type_len > best[1]:
                    best = (i, type_len)
        i = data.find(b'\x9f\xeb\x01\x00', i + 4)
    if best is None:
        sys.exit('no se encontró BTF')
    return best[0]

def parse(path):
    data = open(path, 'rb').read()
    o = find_btf(data)
    hdr_len, type_off, type_len, str_off, str_len = struct.unpack_from('<IIIII', data, o + 4)
    tb = o + hdr_len + type_off; sb = o + hdr_len + str_off
    def s(off): return data[sb + off: data.index(b'\0', sb + off)].decode()
    types = [None]; p = tb; end = tb + type_len
    while p < end:
        name_off, info, size_type = struct.unpack_from('<III', data, p); p += 12
        kind = (info >> 24) & 0x1f; vlen = info & 0xffff; kflag = info >> 31
        t = {'kind': KIND.get(kind, kind), 'name': s(name_off), 'size': size_type, 'members': None}
        if kind == 1: p += 4
        elif kind == 3: t['arr'] = struct.unpack_from('<III', data, p); p += 12
        elif kind in (4, 5):
            ms = []
            for _ in range(vlen):
                mn, mt, moff = struct.unpack_from('<III', data, p); p += 12
                bitoff = moff & 0xffffff if kflag else moff
                ms.append((s(mn), mt, bitoff))
            t['members'] = ms
        elif kind == 6: p += 8 * vlen
        elif kind == 13: p += 8 * vlen
        elif kind == 14: p += 4
        elif kind == 15: p += 12 * vlen
        elif kind == 17: p += 4
        elif kind == 19: p += 12 * vlen
        types.append(t)
    return types

def tname(types, tid, depth=0):
    if tid == 0: return 'void'
    t = types[tid]
    if t['kind'] in ('ptr',): return tname(types, t['size'], depth) + '*'
    if t['kind'] in ('const', 'volatile', 'restrict', 'typedef', 'type_tag') and not t['name']:
        return tname(types, t['size'], depth)
    if t['kind'] == 'array': return tname(types, t['arr'][0], depth) + f"[{t['arr'][2]}]"
    if t['kind'] in ('struct', 'union') and not t['name'] and depth < 2:
        return t['kind'] + '{' + ','.join(f"{m[0]}@{m[2]}" for m in t['members']) + '}'
    return f"{t['kind']} {t['name']}"

def layouts(types):
    out = {}
    for tid, t in enumerate(types):
        if t and t['kind'] in ('struct', 'union') and t['name']:
            lay = (t['size'], tuple((m[0], m[2], tname(types, m[1])) for m in t['members']))
            out.setdefault((t['kind'], t['name']), set()).add(lay)
    return out

a = layouts(parse(sys.argv[1])); b = layouts(parse(sys.argv[2]))
comunes = sorted(set(a) & set(b)); cambian = []
for k in comunes:
    if a[k] != b[k]:
        cambian.append(k)
print(f'estructuras: ref {len(a)}, nuevo {len(b)}, comunes {len(comunes)}, solo nuevo {len(set(b)-set(a))}, solo ref {len(set(a)-set(b))}')
print(f'CAMBIAN DE LAYOUT: {len(cambian)}')
for k in cambian:
    la = sorted(a[k]); lb = sorted(b[k])
    print(f'  {k[0]} {k[1]}: tamaño {[x[0] for x in la]} -> {[x[0] for x in lb]}')
    if len(la) == 1 and len(lb) == 1:
        ma = {m[0]: m for m in la[0][1]}; mb = {m[0]: m for m in lb[0][1]}
        for n in sorted(set(ma) | set(mb), key=lambda n: (mb.get(n) or ma.get(n))[1]):
            if ma.get(n) != mb.get(n):
                print(f'      {n!r}: {ma.get(n)} -> {mb.get(n)}')
