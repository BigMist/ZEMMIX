#!/usr/bin/env python3
"""V99PLAY.COM data file from an openMSX trace of the V9990 ports.

The trace has one line per port access of 60h-6Fh, as written by a Tcl
watchpoint in openMSX:
    <time> W <port hex> <value hex>
    <time> R <port hex>
(e.g. debug set_watchpoint write_io {0x60 0x6F} {} wl, with wl printing
"%.7f W %02X %02X").  Reads are not replayed: P#5 polls become a wait for
CE = 0, and every command (R#52) waits for the previous one.  R#9 is
written as 0: no V9990 interrupts under DOS.

Usage: mkplay.py trace.txt V99GNG.DAT
"""
import sys


def main(trace, out_name):
    out = bytearray()
    sel, winc, polled = 0, True, False
    run = bytearray()

    def flush():
        nonlocal run
        while run:
            n = min(len(run), 0xFFFF)
            out.extend(b'\x11' + n.to_bytes(2, 'little') + run[:n])
            run = run[n:]

    for line in open(trace):
        f = line.split()
        rw, port = f[1], int(f[2], 16)
        if rw == 'R':
            if port == 0x65:
                polled = True
            continue
        v = int(f[3], 16)
        if polled or (port == 0x63 and sel == 52):
            flush()
            out.append(0x10)                # wait for CE = 0
            polled = False
        if port == 0x60:
            run.append(v)
            continue
        flush()
        if port == 0x63 and sel == 9:
            v = 0                           # no V9990 interrupts under DOS
        out.extend(bytes([port - 0x60, v]))
        if port == 0x64:
            sel, winc = v & 0x3F, not (v & 0x80)
        elif port == 0x63 and winc:
            sel = (sel + 1) & 63
    flush()
    out.append(0xFF)
    open(out_name, 'wb').write(out)
    print(len(out), 'bytes')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
