#!/usr/bin/env python3
"""Simulation copy of NextZ80 (misc/opl3/nextz80*.v) for iverilog.

The decoder assigns don't care values (x) that are fine for synthesis but
propagate in simulation (e.g. WE = 6'b010x00): x bits in the right hand side
of assignments become 0, casex labels are left as they are.  The register
RAM and SP / R / TH get an initial value.

  python3 mk_sim_copy.py <out dir>
"""
import glob, os, re, sys

out = sys.argv[1] if len(sys.argv) > 1 else 'nz'
os.makedirs(out, exist_ok=True)
src = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../opl3')

def fix(m):
    return re.sub(r"(\d+'b)([01xX_]+)",
                  lambda k: k.group(1) + k.group(2).replace('x', '0').replace('X', '0'),
                  m.group(0))

for f in glob.glob(os.path.join(src, 'nextz80*.v')):
    s = open(f).read()
    s = re.sub(r"(?<![=!<>])=\s*[^;]*;", fix, s)
    s = re.sub(r"<=\s*[^;]*;", fix, s)
    if 'nextz80reg' in f:
        a = '   reg [7:0]data[15:0];'
        s = s.replace(a, a + '\n   integer ii; initial for (ii=0; ii<16; ii=ii+1) data[ii]=0;')
        s = s.replace('   reg [15:0]sp;', '   reg [15:0]sp=0;')
        s = s.replace('   reg [7:0]r;', '   reg [7:0]r=0;')
        s = s.replace('   reg [7:0]th;', '   reg [7:0]th=0;')
    open(os.path.join(out, os.path.basename(f)), 'w').write(s)
