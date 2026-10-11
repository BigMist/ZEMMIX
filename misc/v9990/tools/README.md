# V9990 test tools (MSX-DOS 2 / Nextor)

Tests for the V9990 (GFX9000) of ZEMMIX (`v9990/`, VRAM in the 2nd SDRAM
of the SiDi128), written while chasing V9990 bugs (ZEMMIX-1os, ZEMMIX-gfn).
The sources assemble with [pasmo](https://pasmo.speccy.org/)
(`pasmo V99TEST.ASM V99TEST.COM`).  They are in the root of the ZEMMIX disk
image; on openMSX (`-ext gfx9000`) every test passes.

| Tool | What it checks | Expected |
|---|---|---|
| `V99TEST` | the whole 512 KB VRAM written and read back through P#0, pass after pass, display on / off, pattern inverted; errors per data bit (SDRAM DQ) | 0 errors |
| `V99RDBK` | the VRAM access pattern of the Ghosts'n Goblins decompressor: R#3-R#5, read P#0, write P#0, copies from 1 to 1024 bytes back, in mode B1 (bytes N and N+1 in different SDRAM words) | read-back 0, verify 0 |
| `V99RDBP` | the same in mode P1 (bytes N and N+1 in the same SDRAM word and cache line) | read-back 0, verify 0 |
| `V99CMD` | LMMV in P1 with write masks (the clear of tile 0 of layer B of GNG): five cases of DX and WM | as listed in the source |
| `V99DUMP` | saves the 512 KB VRAM to `V99VRAM.BIN` (P1 order, as the openMSX `physical VRAM`); the VRAM survives a reset, so a game screen can be dumped | `Done.` |
| `V99PLAY` | replays the port writes of a program captured in openMSX (`V99GNG.DAT`, made by `mkplay.py` from the trace), then `V99DUMP` to compare with openMSX | the screen / VRAM of openMSX |
| `V99MODE` | the bitmap modes B1, B3, B7, B0, B2, B4 one after the other (a key for the next), each with its name at the top left: a white grid every 8 pixels, left half alternate columns (blue), right half alternate lines (red) | every column and line there (B7 / B4 need the full-res video chain and a monitor that takes ~1150 pixels a line) |
