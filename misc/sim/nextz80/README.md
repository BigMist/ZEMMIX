# NextZ80 as the R800 (research, ZEMMIX epic R800)

NextZ80 (Nicolae Dumitrache, OpenCores 2011, LGPL 2.1, the CPU of the old
software OPL3, `misc/opl3/nextz80*.v`) is not cycle exact to the Z80: one
synchronous bus access per clock, data read in the same clock, about one
clock per opcode byte plus one per memory / I/O access.  That is close to
the R800 timing model, so with a regulator that only holds it (`WAIT`) it can
match the R800 exactly, where the T80s (4 clk21m per M1 against 3 for an
R800 cycle) is late on short instructions.

## Measured (iverilog, `nz_tb.v` + `prog.asm`) against openMSX R800.hh

Clocks between opcode fetches; R800 cycles with the static page break (P=1),
without the address dependent ones.

| Instruction | NextZ80 | R800 |
|---|---|---|
| NOP, LD r,r, ADD A,r, INC r, EX DE,HL | 1 | 1 |
| LD r,n, BIT n,r, NEG | 2 | 2 |
| LD rr,nn / LD IX,nn | 3 / 4 | 3 / 4 |
| LD A,(HL), LD (HL),A | 2 | 3 |
| LD A,(nn), LD (nn),A | 4 | 5 |
| INC (HL) / SET n,(HL) | 3 / 4 | 6 / 7 |
| PUSH / POP | 3 / 3 | 5 / 4 |
| JP / JR / DJNZ taken | 3 / 2 / 2 | 4 / 3 / 3 |
| CALL / RET | 5 / 3 | 6 / 4 |
| LDI / LDIR per byte | 5 / ~3.5 | 6 / 6 |
| LD A,(IX+d), LD (IX+d),A | 4 | 6 |
| OUT (n),A, IN A,(n) | 3 | 9 |
| **ADD HL,rr / ADC HL,rr / ADD IX,rr** | **2 / 3 / 3** | **1 / 2 / 2** |
| MULUB / MULUW | - | 14 / 36 |

At the same clock NextZ80 is equal or early except the three 16-bit adds; at
10.74 MHz (clk21m / 2) it is early everywhere, and `misc/r800_timing.vhd`
(openMSX rules: page breaks, ROM / slot waits, I/O, refresh, VDP 62 cycles)
can hold it to the exact R800 time.

## Status (the core is `misc/r800/r800_*.v`, module `R800`)

- R800 instructions and behaviour (openMSX CPUCore.cc `IS_R800`): MULUB /
  MULUW, SLL (CB 30-37) as SLA, DD / FD CB d 30-37 (flags only), DD / FD
  before an opcode without IX / IY is a NOP of two bytes, X / Y flags never
  from the result, CPL / CCF / BIT flags.  Block repeats fetch the
  instruction again on every iteration (M1 per iteration, for the regulator).
  Tests in `misc/sim/r800` (Verilator): `multest`, `blktest`, `iotest`,
  `pfxtest`; zexall CRCs compared with openMSX R800 by `zexcmp.py`.
- Simulation: NextZ80 used `mux_rdor` in its `always @*` before computing it;
  an event driven simulator (nvc, iverilog) kept the old value (wrong address
  of a JP while held by `WAIT`).  Fixed in `r800_reg.v`.
- Bus: `misc/r800/r800_bus.vhd` gives the core a T80s like bus (T2 until
  `WAIT_n`, then T3, the data taken at the end of T3) for `emsx_top` and
  `misc/r800_timing.vhd`; model in `bus/tb_dn.vhd` (R800BEN).
- R800BEN (`bus/tb_dn.vhd`, system timer ticks, measured / openMSX): NOP
  2874 / 2828, LD A,(HL) 1520 / 1513, LD (HL),A 1522 / 1513, PUSH / POP
  1CF9 / 1CDE, CALL / RET 0FEF / 0FE0, LDIR 247F / 2476, MULUB / W 2A28 /
  2A1B, IN A,(n) 1A58 / 1A4B: all within 0.7 % (T80s: NOP 2F14, LDIR 27A8).
- nvc also ignores the initial values of `reg` declarations (`initial`
  blocks now) and propagated the ALU `x` defaults (now 0, as Verilator).
- To do: LD A,I / LD A,R do not hold interrupts on the R800; integration in
  `emsx_top` (U01_R8) and test on the board.

## Run

    python3 mk_sim_copy.py nz
    pasmo prog.asm prog.bin
    python3 -c "d=open('prog.bin','rb').read();open('prog.hex','w').write('\n'.join('%02x'%b for b in d))"
    iverilog -g2012 -o nz_tb nz_tb.v nz/nextz80*.v && vvp -n nz_tb
