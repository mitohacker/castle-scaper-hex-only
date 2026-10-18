"""Townscaper's corner-key space, from the rules read in townscaper-re/notes/wfc_modules.md (sections 1.3, 4.1, 3.2).

A cell (qube) has 8 corner values: v0..v3 the bottom ring, v4..v7 the top ring (ring order = the square's corners).
Values: colour 0..14, 15 ground, 16 any, 17 below the world, 18 air.
Key = markHiddenCornersAmbiguous (a corner becomes ANY unless it, or one of its three cube-edge neighbours, is air)
      then indexMaterials (colours renamed in order of first appearance v0..v7; 15..18 stay).
Orientations of a module: 4 quarter turns about the vertical x optional mirror = 8 (never tipped, never upside down).
"""
import itertools, sys

AIR, ANY, BELOW, GROUND = 18, 16, 17, 15


def nbrs(i):
    r, k = divmod(i, 4)           # ring 0 bottom / 1 top
    base = 4 * r
    return [base + (k + 1) % 4, base + (k - 1) % 4, i ^ 4]


def key_of(vals):
    hid = []
    for i, v in enumerate(vals):
        if v == AIR or any(vals[j] == AIR for j in nbrs(i)):
            hid.append(v)
        else:
            hid.append(ANY)
    ren = {}
    out = []
    for v in hid:
        if v < 15:
            if v not in ren:
                ren[v] = len(ren)
            out.append(ren[v])
        else:
            out.append(v)
    return tuple(out)


def partitions(n):
    """restricted growth strings of length n (colour equality patterns)."""
    def rec(prefix, mx):
        if len(prefix) == n:
            yield tuple(prefix)
            return
        for c in range(mx + 2):
            yield from rec(prefix + [c], max(mx, c))
    yield from rec([], -1)


def assignments(bottom_states, top_states):
    """bottom_states / top_states: 'colour' (air or any colour class), 'ground' (ground or air), 'below' (always 17)."""
    def ring(kind):
        if kind == 'below':
            yield (BELOW,) * 4
        elif kind == 'ground':
            for m in itertools.product([GROUND, AIR], repeat=4):
                yield m
        else:
            pass
    # generate colour rings jointly because colour classes are shared between rings
    b_opts = list(ring(bottom_states)) if bottom_states != 'colour' else None
    t_opts = list(ring(top_states)) if top_states != 'colour' else None
    if b_opts is not None and t_opts is not None:
        for b in b_opts:
            for t in t_opts:
                yield b + t
    elif b_opts is not None:                      # bottom fixed kind, top colours
        for b in b_opts:
            for mask in itertools.product([0, 1], repeat=4):
                filled = [i for i, m in enumerate(mask) if m]
                for part in partitions(len(filled)):
                    t = [AIR] * 4
                    for idx, c in zip(filled, part):
                        t[idx] = c
                    yield b + tuple(t)
    else:                                         # both rings colours
        for mask in itertools.product([0, 1], repeat=8):
            filled = [i for i, m in enumerate(mask) if m]
            for part in partitions(len(filled)):
                v = [AIR] * 8
                for idx, c in zip(filled, part):
                    v[idx] = c
                yield tuple(v)


def perm_orients():
    perms = []
    for mirror in (False, True):
        for r in range(4):
            p = []
            for i in range(8):
                ring, k = divmod(i, 4)
                k2 = (-k if mirror else k) % 4
                k2 = (k2 + r) % 4
                p.append(4 * ring + k2)
            perms.append(p)
    return perms


ORI = perm_orients()


def apply(vals, p):
    out = [None] * 8
    for i, j in enumerate(p):
        out[j] = vals[i]
    return tuple(out)


def renorm(vals):
    ren = {}
    out = []
    for v in vals:
        if v < 15:
            if v not in ren:
                ren[v] = len(ren)
            out.append(ren[v])
        else:
            out.append(v)
    return tuple(out)


def orbit_count(keys):
    seen = set()
    n = 0
    for k in keys:
        if k in seen:
            continue
        n += 1
        for p in ORI:
            seen.add(renorm(apply(k, p)))
    return n


def shape_orbits(keys):
    """orbits of the visible FILLED/AIR/GROUND pattern only (colour equality ignored)."""
    def shape(k):
        return tuple(0 if v == AIR else (15 if v in (GROUND, BELOW) else 1) for v in k)
    shapes = set(shape(k) for k in keys)
    seen = set()
    n = 0
    for s in shapes:
        if s in seen:
            continue
        n += 1
        for p in ORI:
            seen.add(apply(s, p))
    return n


def report(name, bottom, top):
    keys = set()
    nomod = 0
    raw = 0
    for a in assignments(bottom, top):
        raw += 1
        k = key_of(a)
        if all(v == ANY for v in k) or all(v == AIR for v in k):
            nomod += 1
            continue
        keys.add(k)
    print("%-34s raw assignments %6d | module keys %5d | no module (empty/interior) %4d | orbits under the 8 orientations %5d | shape-only orbits %3d" % (
        name, raw, len(keys), nomod, orbit_count(keys), shape_orbits(keys)))
    return keys


def compute():
    """The numbers of the viewer: per layer kind the raw assignments, module keys, interior/empty cells, orbits and shape orbits, and the
    keys by number of distinct visible colours."""
    out = {'layers': []}
    union = set()
    for name, bottom, top in (('Ground cell', 'below', 'ground'), ('First storey', 'ground', 'colour'), ('Upper storeys', 'colour', 'colour')):
        keys = set()
        nomod = 0
        raw = 0
        for a in assignments(bottom, top):
            raw += 1
            k = key_of(a)
            if all(v == ANY for v in k) or all(v == AIR for v in k):
                nomod += 1
                continue
            keys.add(k)
        union |= keys
        by = {}
        for k in keys:
            n = len(set(v for v in k if v < 15))
            by[n] = by.get(n, 0) + 1
        out['layers'].append({'name': name, 'raw': raw, 'keys': len(keys), 'nomod': nomod, 'orbits': orbit_count(keys), 'shapes': shape_orbits(keys),
                              'by_colours': {str(n): c for n, c in sorted(by.items())}})
    out['total_keys'] = len(union)                     # a key can occur in more than one kind of cell: the sum of the layers is 4,815, the distinct keys 4,764
    out['total_orbits'] = orbit_count(union)
    out['sum_of_layers'] = sum(l['keys'] for l in out['layers'])
    return out


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--json':
        import json
        print(json.dumps(compute()))
        sys.exit(0)
    k0 = report('layer 0 (sea / ground cell)', 'below', 'ground')
    k1 = report('layer 1 (first storey)', 'ground', 'colour')
    k2 = report('layer 2+ (upper storeys)', 'colour', 'colour')
    # keys that need more than one colour class (a colour seam)
    def ncol(k):
        return len(set(v for v in k if v < 15))
    for name, ks in (('layer 1', k1), ('layer 2+', k2)):
        by = {}
        for k in ks:
            by[ncol(k)] = by.get(ncol(k), 0) + 1
        print(name, 'keys by number of distinct visible colours:', dict(sorted(by.items())))
    tot = len(k0) + len(k1) + len(k2)
    print('total module keys over the three layer kinds:', tot)
