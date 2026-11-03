#!/usr/bin/env python3
"""wsdiff.py A.txt B.txt [--all]: difference of two wolsnap.sh snapshots.
Byte-wise for sio_*, cmos_*, fch_biosram; 32-bit words for the rest. Offsets in cmos_0e_ff are CMOS indexes.
Skips known noise by default (PM timer, DMA addresses, counters); --all shows everything."""
import sys, struct

NOISE = {
    'fch_acpi': lambda o: o >= 0x08,                 # 0x08 PM timer, 0x10+ mirror/garbage
    'fch_misc': lambda o: o in (0x78, 0x7c),
    'fch_aoac': lambda o: o in (0x30, 0x34),
    'nicregs': lambda o: o in (0x0c, 0x10, 0x14, 0x20, 0x24, 0x3c, 0x70, 0x74, 0x7c, 0xb0, 0xb8, 0xe4, 0xe8),
    'nic_eri': lambda o: o in (0xec, 0x1e0),
    'nic_ocp': lambda o: o == 0x3c,                  # 0xDC04
    'nic_phy': lambda o: o in (0x04, 0x18),          # BMSR, ANER (latched, clear on read)
    'pci_nic_0a_00_0': lambda o: o == 0x728,
    'sio_ldn_0x15': lambda o: o in (0xe0, 0xe1, 0xe2),
    'sio_ldn_0x14': lambda o: o == 0xe4,
}
# FCH GPIO: the live pin level (bit 16) and the event status bits (28-29) are noise; the configuration counts.
MASK = {'fch_gpio': ~0x30010000 & 0xFFFFFFFF}

def load(p):
    d = {}
    for l in open(p):
        k, _, v = l.rstrip('\n').partition(' ')
        if k in ('nic', 'times'):
            d[k] = v
        elif v:
            try:
                d[k] = bytes.fromhex(v)
            except ValueError:
                pass
    return d

a, b = load(sys.argv[1]), load(sys.argv[2])
show_all = '--all' in sys.argv
for k in a:
    if k in ('nic', 'times'):
        if a[k] != b.get(k):
            print(f'{k}:\n  A {a[k]}\n  B {b.get(k)}')
        continue
    x, y = a[k], b.get(k, b'')
    w = 1 if k.startswith(('sio', 'cmos', 'fch_biosram')) else 4
    base = 0x0e if k.startswith('cmos_0e') else 0
    for o in range(0, min(len(x), len(y)), w):
        p, q = x[o:o + w], y[o:o + w]
        if p == q:
            continue
        if not show_all and k in MASK and w == 4 and \
                (struct.unpack('<I', p)[0] & MASK[k]) == (struct.unpack('<I', q)[0] & MASK[k]):
            continue
        if not show_all and (k in NOISE and NOISE[k](o) or (k.startswith('sio') and o == 0x07)):
            continue
        fx = '<I' if w == 4 else '<B'
        print(f'{k:22s} +0x{o + base:03x}: {struct.unpack(fx, p)[0]:#0{2 + 2 * w}x} -> {struct.unpack(fx, q)[0]:#0{2 + 2 * w}x}')
