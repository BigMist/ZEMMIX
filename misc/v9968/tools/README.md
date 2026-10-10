# VDP test tools (MSX-DOS 2 / Nextor)

Regression tests for the ZEMMIX VDP (the V9968 of HRA!, `v9968/`), written
while chasing VDP bugs (ZEMMIX-f7c).  Each one is a small `.COM`; the
sources assemble with [pasmo](https://pasmo.speccy.org/):

```bash
pasmo VDPTEST.ASM VDPTEST.COM
pasmo --equ DISPON=1 VDPTEST.ASM VDPTESTD.COM
pasmo --equ DISPON=1 --equ FASTHMMC=1 VDPTEST.ASM VDPTESTF.COM
pasmo VDPDISP.ASM VDPDISP.COM       # and VDPHAM, VDPHAM2, VDPSPR, VDPTP, VDPIL, VDPDUMP
```

The `.COM` files are in the root of the ZEMMIX disk image.  On a correct
V9938 / V9958 (openMSX) every test passes.

| Tool | What it checks | Expected |
|---|---|---|
| `VDPTEST` | VRAM 128 KB with R#14; address set, then R#14, then data (the pointer stays); SCREEN 5 commands on page 1 / page 0: HMMV, HMMC through 9Bh (R#17 = ACh), HMMM, LMMM TIMP, PSET; read back through 98h | all `OK` |
| `VDPTESTD` | the same with the display and the sprites on (as games draw) | all `OK` |
| `VDPTESTF` | as `VDPTESTD`, HMMC bytes through 9Bh back to back (no pause, no TR polling) | all `OK` |
| `VDPDISP` | the four SCREEN 5 pages with distinct patterns (bars, bands, chessboard, frame), then R#23 0..255 | each page shows only its pattern |
| `VDPHAM` | page 0 shown while the VDP is hammered: R#1 rewrites, status reads, the address / R#14 / data / R#6 sequence of Zanac EX, palette writes | the vertical bars stay |
| `VDPHAM2` | R#13 = 3Eh / 00h and an R#23 sweep 30h..FFh, 00h (Zanac EX intro) | the vertical bars stay |
| `VDPSPR` | sprite mode 2 tables at FE00h / FC00h / B000h, sprite 0 Y = D8h (end of list), R#6 16h / 17h each frame | no sprite, only the bars |
| `VDPTP` | page 0 all colour 0 (TP = 0, R#7 = 0, palette 0 blue), page 1 bands | plain blue inside a white frame |
| `VDPIL` | R#9 interlace: 424-line SCREEN 5 picture over pages 0 / 1 (IL + EO), then IL only and no interlace | red / green line pairs with green right below red, smooth 45 degree diagonals, no jumping |
| `VDPDUMP` | saves the 128 KB of VRAM to `VRAM.BIN` (to compare with an openMSX dump) | `........ OK` |

openMSX checks run in Docker on the build host (headless, muted): see the
`openmsx-silent` beads memory.
