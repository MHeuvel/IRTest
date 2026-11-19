#!/usr/bin/env python3
"""Generate Sources/FlipperDB.txt from a Flipper-IRDB checkout (CC0).

usage: python3 tools/make_flipperdb.py <path to Flipper-IRDB-main> [output file]

File format: "#F|category|brand|model" starts a remote, then one line per key: name|protocol|address|command
  protocol codes: S Samsung32, N NEC, X NECext, N4 NEC42, N4X NEC42ext, R12/R15/R20 SIRC, 5 RC5, 5X RC5X,
                  6 RC6, K Kaseikyo, RC RCA, P Pioneer (address and command in hex, trailing zero bytes removed)
  protocol code H = raw recording already converted to the chip signal: name|H|<hex of the chip signal>|
Raw recordings are converted with the same method as ChipEncoder.encode in IRConvert.swift (pulse pairs merged
with 100 us tolerance, at most 13 pairs, at most 244 bytes)."""
import os, sys

CODES = {'Samsung32': 'S', 'NEC': 'N', 'NECext': 'X', 'NEC42': 'N4', 'NEC42ext': 'N4X', 'SIRC': 'R12',
         'SIRC15': 'R15', 'SIRC20': 'R20', 'RC5': '5', 'RC5X': '5X', 'RC6': '6',
         'Kaseikyo': 'K', 'RCA': 'RC', 'Pioneer': 'P'}
MAX_PAIRS = 13
MAX_US = 131070


def encode(freq, durs, tol=100):
    durs = [min(max(int(x), 1), MAX_US) for x in durs]
    if len(durs) < 2:
        raise ValueError('short')
    if len(durs) % 2:
        spaces = [durs[i] for i in range(1, len(durs), 2) if durs[i] <= 3000]
        durs.append(max(spaces) if spaces else 1000)
    items = [(durs[i], durs[i + 1]) for i in range(0, len(durs), 2)]

    def cluster(vals, rel):
        cs = []
        for v in sorted(set(vals)):
            for c in cs:
                if abs(v - c[0]) <= max(int(rel * c[0]), tol):
                    c[1].append(v)
                    break
            else:
                cs.append([v, [v]])
        return {v: sum(c[1]) // len(c[1]) for c in cs for v in c[1]}

    def build(rel):
        mm = cluster([m for m, _ in items], rel)
        ss = cluster([s for _, s in items], rel)
        pairs, syms = [], []
        for m, s in items:
            pr = (mm[m] // 2 * 2, ss[s] // 2 * 2)
            if pr not in pairs:
                pairs.append(pr)
            syms.append(pairs.index(pr))
        return pairs, syms

    pairs, syms = build(0.0)
    rel = 0.05
    while len(pairs) > 16 and rel <= 0.6:
        pairs, syms = build(rel)
        rel += 0.05
    if len(pairs) > 16 or len(syms) > 255:
        raise ValueError('too big')
    carrier = max(1, min(255, round(8_000_000 / max(freq, 1))))
    body = [0, carrier, len(pairs)]
    for m, s in pairs:
        m = min(max(m // 2, 1), 65535)
        s = min(max(s // 2, 1), 65535)
        body += [m >> 8, m & 255, s >> 8, s & 255]
    body.append(len(syms))
    if len(syms) % 2:
        syms = syms + [0]
    body += [syms[i] << 4 | syms[i + 1] for i in range(0, len(syms), 2)]
    sig = [0, 0, len(body)] + body
    if len(sig) > 244:
        raise ValueError('too long')
    return sig


def hexs(v):
    b = v.split()
    while len(b) > 1 and b[-1] == '00':
        b.pop()
    return ''.join(b)


def place(rel):
    cat = rel[0]
    if cat == '_Converted_':
        if len(rel) < 3:
            return None
        src = rel[1]
        if src == 'IR_Plus' and len(rel) >= 5:
            return ('Converted: IR Plus', rel[3], '/'.join(rel[4:-1] + [rel[-1][:-3]]))
        if len(rel) >= 4:
            return ('Converted: ' + src.replace('_', ' '), rel[2], '/'.join(rel[3:-1] + [rel[-1][:-3]]))
        return ('Converted: ' + src.replace('_', ' '), '-', rel[-1][:-3])
    if len(rel) > 2:
        return (cat.replace('_', ' '), rel[1], '/'.join(rel[2:-1] + [rel[-1][:-3]]))
    return (cat.replace('_', ' '), '-', rel[-1][:-3])


def main():
    root = sys.argv[1]
    out_path = sys.argv[2] if len(sys.argv) > 2 else 'Sources/FlipperDB.txt'
    entries = []
    stats = {'parsed': 0, 'raw': 0, 'raw_skipped': 0, 'other_skipped': 0}
    for r, _, fs in os.walk(root):
        for f in fs:
            if not f.endswith('.ir'):
                continue
            rel = os.path.relpath(os.path.join(r, f), root).split(os.sep)
            if rel[0].startswith('.'):
                continue
            pl = place(rel)
            if not pl:
                continue
            try:
                t = open(os.path.join(r, f), encoding='utf-8', errors='replace').read()
            except OSError:
                continue
            keys, cur = [], {}
            for line in t.splitlines() + ['name: ']:
                line = line.strip()
                if line.startswith('#') or not line or ':' not in line:
                    continue
                k, v = line.split(':', 1)
                k, v = k.strip().lower(), v.strip()
                if k == 'name':
                    name = cur.get('name')
                    if name:
                        nm = name.replace('|', '/')
                        typ = cur.get('type', '').lower()
                        if typ == 'parsed' and cur.get('protocol') in CODES and 'address' in cur and 'command' in cur:
                            keys.append('%s|%s|%s|%s' % (nm, CODES[cur['protocol']], hexs(cur['address']), hexs(cur['command'])))
                            stats['parsed'] += 1
                        elif typ == 'raw' and 'data' in cur:
                            try:
                                sig = encode(int(cur.get('frequency', '38000')), [int(x) for x in cur['data'].split()])
                                if sig[5] <= MAX_PAIRS:
                                    keys.append('%s|H|%s|' % (nm, ''.join('%02X' % b for b in sig)))
                                    stats['raw'] += 1
                                else:
                                    stats['raw_skipped'] += 1
                            except (ValueError, IndexError):
                                stats['raw_skipped'] += 1
                        else:
                            stats['other_skipped'] += 1
                    cur = {'name': v}
                elif k == 'data' and 'data' in cur:
                    cur['data'] += ' ' + v
                else:
                    cur[k] = v
            if keys:
                entries.append((pl, keys))
    entries.sort(key=lambda e: (e[0][0].lower(), e[0][1].lower(), e[0][2].lower()))
    lines = []
    for (cat, brand, model), keys in entries:
        lines.append('#F|%s|%s|%s' % (cat.replace('|', '/'), brand.replace('|', '/'), model.replace('|', '/')))
        lines += keys
    with open(out_path, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(lines) + '\n')
    print('remotes', len(entries), stats, 'size MB', round(os.path.getsize(out_path) / 1e6, 1))


if __name__ == '__main__':
    main()
