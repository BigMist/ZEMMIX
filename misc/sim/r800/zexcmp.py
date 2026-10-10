#!/usr/bin/env python3
"""Compare zexall results: openMSX R800 log (BDOS breakpoint, every string twice,
every printed digit twice) against the R800 core simulation log."""
import re, sys

def ours(path):
    out = []
    for l in open(path, 'rb').read().decode('latin1').replace('\r', '\n').split('\n'):
        m = re.match(r'(\S.*?)\.{2,}\s*(OK|ERROR \*+ crc expected:(\w+) found:(\w+))', l)
        if m:
            out.append((m.group(1), 'OK' if m.group(2) == 'OK' else m.group(4)))
    return out

def openmsx(path):
    out = []
    for l in open(path, 'rb').read().decode('latin1').replace('\r', '\n').split('\n'):
        m = re.match(r'(\S.*?\.{2,})\1\s*(OK|ERROR)', l)
        if not m:
            continue
        name = m.group(1).rstrip('.')
        if m.group(2) == 'OK':
            out.append((name, 'OK'))
        else:
            f = re.search(r'found:\s*found:\s*([0-9a-f]+)', l)
            out.append((name, f.group(1)[::2] if f else '?'))
    return out

o, u = openmsx(sys.argv[1]), ours(sys.argv[2])
same = 0
for (n1, a), (n2, b) in zip(o, u):
    ok = a == b
    same += ok
    print('%-32s openMSX %-9s ours %-9s %s' % (n1[:32], a, b, 'same' if ok else 'DIFF'))
print('%d of %d the same (openMSX has %d tests)' % (same, min(len(o), len(u)), len(o)))
