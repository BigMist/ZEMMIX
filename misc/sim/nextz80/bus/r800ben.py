"""R800BEN.COM generator + R800 cycle model (openMSX R800.hh / CPUCore.cc rules).

Builds a MSX-DOS program that times small loops with the S1990 system timer
(E6h reset, E6h/E7h read, 3.911us = 28 R800 cycles per tick) and prints
measured vs expected ticks.  The expected values come from running the very
same binary in a Z80 emulator with an R800 cycle model.
"""
import sys
sys.path.insert(0, 'pylib')
import z80

# ---------------------------------------------------------------- assembler
class Asm:
    def __init__(self, org=0x100):
        self.org = org
        self.code = bytearray()
        self.labels = {}
        self.fix = []       # (pos, label, kind)

    @property
    def pc(self):
        return self.org + len(self.code)

    def b(self, *x):
        self.code.extend(x)

    def lab(self, n):
        self.labels[n] = self.pc

    def w(self, l):          # 16-bit absolute reference
        self.fix.append((len(self.code), l, 'w'))
        self.b(0, 0)

    def rel(self, op, l):    # JR/DJNZ
        self.b(op)
        self.fix.append((len(self.code), l, 'r'))
        self.b(0)

    def align(self, a=256, fill=0x00):
        while self.pc % a:
            self.b(fill)

    def call(self, l):
        self.b(0xCD)
        self.w(l)

    def jp(self, l):
        self.b(0xC3)
        self.w(l)

    def resolve(self):
        for pos, l, k in self.fix:
            a = self.labels[l]
            if k == 'w':
                self.code[pos] = a & 255
                self.code[pos + 1] = a >> 8
            else:
                d = a - (self.org + pos + 1)
                assert -128 <= d <= 127, (l, d)
                self.code[pos] = d & 255
        return bytes(self.code)


def build(expected):
    a = Asm()
    tests = [('NOP      ', 't_nop'), ('LD A,(HL)', 't_ldr'), ('LD (HL),A', 't_ldw'),
             ('PUSH/POP ', 't_push'), ('CALL/RET ', 't_call'), ('LDIR 8K  ', 't_ldir'),
             ('MULUB/W  ', 't_mul'), ('IN A,(n) ', 't_in')]
    # ---- main
    a.lab('main')
    for i, (name, lab) in enumerate(tests):
        a.b(0x21); a.w(f'name{i}')         # LD HL,name
        a.call('pstr')
        a.call(lab)                         # HL = ticks
        a.call('phl')
        a.b(0x21); a.w('sep'); a.call('pstr')
        a.b(0x21, expected[i] & 255, expected[i] >> 8)
        a.call('phl')
        a.b(0x21); a.w('crlf'); a.call('pstr')
    a.b(0xC9)
    # ---- strings ($-terminated is avoided: use 0-terminated + own printer)
    for i, (name, lab) in enumerate(tests):
        a.lab(f'name{i}'); a.b(*name.encode(), *b' meas=', 0)
    a.lab('sep'); a.b(*b' exp=', 0)
    a.lab('crlf'); a.b(13, 10, 0)
    # pstr: print 0-terminated string at HL
    a.lab('pstr')
    a.lab('pstr_l')
    a.b(0x7E, 0xB7, 0xC8)                   # LD A,(HL) / OR A / RET Z
    a.b(0xE5, 0x5F, 0x0E, 0x02, 0xCD, 0x05, 0x00, 0xE1, 0x23)   # PUSH HL/LD E,A/LD C,2/CALL 5/POP HL/INC HL
    a.rel(0x18, 'pstr_l')
    # phl: print HL hex
    a.lab('phl')
    a.b(0x7C); a.call('phex'); a.b(0x7D)
    a.lab('phex')
    a.b(0xF5, 0x1F, 0x1F, 0x1F, 0x1F); a.call('nib'); a.b(0xF1)
    a.lab('nib')
    a.b(0xE5, 0xE6, 0x0F, 0xC6, 0x90, 0x27, 0xCE, 0x40, 0x27, 0x5F, 0x0E, 0x02, 0xCD, 0x05, 0x00, 0xE1, 0xC9)

    def start():            # DI ; XOR A ; OUT (E6h),A   (timer reset)
        a.b(0xF3, 0xAF, 0xD3, 0xE6)

    def stop():             # read timer into HL (E7,E6,E7 until stable) ; EI ; RET
        a.lab(f'rd{len(a.code)}')
        l = f'rd{len(a.code) - 0}'
        a.labels[l] = a.pc
        a.b(0xDB, 0xE7, 0x67, 0xDB, 0xE6, 0x6F, 0xDB, 0xE7, 0xBC)   # IN A,(E7)/LD H,A/IN A,(E6)/LD L,A/IN A,(E7)/CP H
        a.rel(0x20, l)
        a.b(0xFB, 0xC9)

    # ---- 1: NOP x120, 256x8
    a.align(); a.lab('t_nop'); start()
    a.b(0x0E, 8)
    a.align(); a.lab('nop_o'); a.b(0x06, 0)
    a.lab('nop_i'); a.b(*([0x00] * 120)); a.rel(0x10, 'nop_i')
    a.b(0x0D); a.rel(0x20, 'nop_o')
    stop()
    # ---- 2: LD A,(HL) x64, 256x2
    a.align(); a.lab('t_ldr'); start()
    a.b(0x21, 0x00, 0x90, 0x0E, 2)
    a.align(); a.lab('ldr_o'); a.b(0x06, 0)
    a.lab('ldr_i'); a.b(*([0x7E] * 64)); a.rel(0x10, 'ldr_i')
    a.b(0x0D); a.rel(0x20, 'ldr_o')
    stop()
    # ---- 3: LD (HL),A x64, 256x2
    a.align(); a.lab('t_ldw'); start()
    a.b(0x21, 0x00, 0x90, 0x0E, 2)
    a.align(); a.lab('ldw_o'); a.b(0x06, 0)
    a.lab('ldw_i'); a.b(*([0x77] * 64)); a.rel(0x10, 'ldw_i')
    a.b(0x0D); a.rel(0x20, 'ldw_o')
    stop()
    # ---- 4: PUSH HL/POP HL x32, 256x2
    a.align(); a.lab('t_push'); start()
    a.b(0x0E, 2)
    a.align(); a.lab('push_o'); a.b(0x06, 0)
    a.lab('push_i'); a.b(*([0xE5, 0xE1] * 32)); a.rel(0x10, 'push_i')
    a.b(0x0D); a.rel(0x20, 'push_o')
    stop()
    # ---- 5: CALL sub / RET x16, 256x2   (sub in another page)
    a.align(); a.lab('t_call'); start()
    a.b(0x0E, 2)
    a.align(); a.lab('call_o'); a.b(0x06, 0)
    a.lab('call_i')
    for _ in range(16):
        a.call('sub_ret')
    a.rel(0x10, 'call_i')
    a.b(0x0D); a.rel(0x20, 'call_o')
    stop()
    a.align(); a.lab('sub_ret'); a.b(0xC9)
    # ---- 6: LDIR 8KB 8000h->A000h, x4
    a.align(); a.lab('t_ldir'); start()
    a.b(0x3E, 4)
    a.lab('ldir_o')
    a.b(0x21, 0x00, 0x80, 0x11, 0x00, 0xA0, 0x01, 0x00, 0x20, 0xED, 0xB0)
    a.b(0x3D); a.rel(0x20, 'ldir_o')
    stop()
    # ---- 7: MULUB A,B x16 + MULUW HL,BC x8, 256x2
    a.align(); a.lab('t_mul'); start()
    a.b(0x0E, 2)
    a.align(); a.lab('mul_o'); a.b(0x06, 0)
    a.lab('mul_i'); a.b(*([0xED, 0xC1] * 16), *([0xED, 0xC3] * 8)); a.rel(0x10, 'mul_i')
    a.b(0x0D); a.rel(0x20, 'mul_o')
    stop()
    # ---- 8: IN A,(0A8h) x32, 256x2
    a.align(); a.lab('t_in'); start()
    a.b(0x0E, 2)
    a.align(); a.lab('in_o'); a.b(0x06, 0)
    a.lab('in_i'); a.b(*([0xDB, 0xA8] * 32)); a.rel(0x10, 'in_i')
    a.b(0x0D); a.rel(0x20, 'in_o')
    stop()
    return a.resolve(), a.labels


# ------------------------------------------------------------- R800 model
class R800Model:
    """Cycle model for the instructions used above (RAM, extra delay 0)."""

    def __init__(self, mem):
        self.mem = mem
        self.cyc = 0
        self.last_page = -1
        self.last_refresh = 0
        self.prev_call = False
        self.timer_base = 0
        self.active = False

    def fetch(self, addr):
        p = (addr & 0xFFFF) >> 8
        if p != self.last_page:
            self.cyc += 1
        self.last_page = p

    def even(self, off):
        if (self.cyc + off) & 1:
            self.cyc += 1

    def ticks(self):
        return ((self.cyc - self.timer_base) // 28) & 0xFFFF

    def step(self, m):
        """account the instruction at m.pc (before it executes)"""
        pc = m.pc
        mem = self.mem
        op = mem[pc]
        # refresh every 210 cycles: 25 cycles, page break
        while self.cyc - self.last_refresh >= 210:
            self.last_refresh += 210
            self.even(0)
            self.cyc += 25
            self.last_page = -1
        start = self.cyc
        pop_ret = False
        call = False
        self.fetch(pc)
        if op in (0x00, 0xAF, 0xB7, 0xFB, 0x0D, 0x3D, 0x05, 0x23, 0x2B, 0x3C, 0x67, 0x6F, 0xBC, 0x5F):
            self.cyc += 1
        elif op == 0xF3:                                   # DI
            self.cyc += 2
        elif op in (0x3E, 0x06, 0x0E, 0xFE, 0xE6, 0xC6, 0xCE):   # 2-byte immediates
            self.fetch(pc + 1); self.cyc += 2
        elif op in (0x21, 0x01, 0x11, 0x31):               # LD rr,nn
            self.fetch(pc + 1); self.cyc += 3
        elif op in (0x7E, 0x77):                           # LD A,(HL) / LD (HL),A
            self.cyc += 3; self.last_page = -1
        elif op in (0x10, 0x18, 0x20, 0x28, 0x30, 0x38):   # DJNZ / JR (cc)
            self.fetch(pc + 1)
            f = m.f
            taken = {0x10: m.b != 1, 0x18: True, 0x20: not (f & 0x40), 0x28: bool(f & 0x40),
                     0x30: not (f & 1), 0x38: bool(f & 1)}[op]
            if taken:
                if ((pc + 2) & 0xFF) == 0:
                    self.last_page = -1
                self.cyc += 3
            else:
                self.cyc += 2
        elif op == 0xCD:                                   # CALL nn
            self.fetch(pc + 1); self.cyc += 6; self.last_page = -1; call = True
        elif op == 0xC9:                                   # RET
            self.cyc += 4; self.last_page = -1; pop_ret = True
        elif op == 0xE5:                                   # PUSH HL
            self.cyc += 5; self.last_page = -1
        elif op == 0xE1:                                   # POP HL
            self.cyc += 4; self.last_page = -1; pop_ret = True
        elif op in (0xD3, 0xDB):                           # OUT (n),A / IN A,(n)
            self.fetch(pc + 1)
            self.even(3)
            if op == 0xD3 and mem[pc + 1] == 0xE6:         # timer reset happens at the I/O cycle
                self.timer_base = self.cyc + 3
                self.active = True
            self.cyc += 9
        elif op == 0xED:
            op2 = mem[pc + 1]
            self.fetch(pc + 1)
            if op2 == 0xB0:                                # LDIR (per iteration)
                self.cyc += 6; self.last_page = -1
            elif op2 in (0xC1, 0xC9, 0xD1, 0xD9):
                self.cyc += 14
            elif op2 in (0xC3, 0xF3):
                self.cyc += 36
            else:
                raise ValueError(f'ED {op2:02X} at {pc:04X}')
        else:
            raise ValueError(f'opcode {op:02X} at {pc:04X}')
        if self.prev_call and not pop_ret:
            self.cyc += 1
        self.prev_call = call
        return start


def run_model(code, labels):
    mem = bytearray(65536)
    mem[0x100:0x100 + len(code)] = code
    mem[0] = 0x76
    mem[5] = 0xC9
    model = R800Model(mem)
    m = z80.Z80Machine()
    m.set_memory_block(0, bytes(mem))
    out = []
    inst = {'pending': 0}

    def inp(port):
        p = port & 255
        if p in (0xE6, 0xE7):
            # the read happens 3 cycles into IN A,(n)
            t = ((model.cyc_at_io - model.timer_base) // 28) & 0xFFFF
            return t & 255 if p == 0xE6 else t >> 8
        return 0xFF
    m.set_input_callback(inp)
    m.set_output_callback(lambda port, val: None)
    m.sp = 0xEFFE
    m.set_memory_block(0xEFFE, b'\0\0')
    m.pc = labels['main']
    steps = 0
    while m.pc != 0 and steps < 50_000_000:
        steps += 1
        pc = m.pc
        if pc == 5:
            if m.c == 2:
                out.append(chr(m.e))
        # only the timed region is modeled, everything else is free
        op = mem[pc]
        timed = model.active
        if op == 0xF3:                     # DI starts a test
            model.cyc = 0; model.last_page = -1; model.last_refresh = 0
            model.prev_call = False; model.active = True; timed = True
        if timed:
            st = model.step(m)
            if op == 0xDB:
                model.cyc_at_io = st + 3 + (1 if (st + 3) & 1 else 0)
                # recompute io point exactly: fetches already done in step
                model.cyc_at_io = model.cyc - 9 + 3
            if op == 0xFB:
                model.active = False
        # MULU are NOPs in the Z80 emulator: harmless for timing
        m.ticks_to_stop = 1
        m.run()
        # keep emulator memory in sync for self-reads (stack writes)
        if mem[pc] in (0xE5, 0xCD, 0x77) or (mem[pc] == 0xED):
            pass
    return ''.join(out)


if __name__ == '__main__':
    code, labels = build([0] * 8)
    txt = run_model(code, labels)
    exp = []
    for line in txt.strip().split('\r\n'):
        exp.append(int(line.split('meas=')[1][:4], 16))
    code, labels = build(exp)
    txt2 = run_model(code, labels)
    open('R800BEN.COM', 'wb').write(code)
    print(txt2)
    print(len(code), 'bytes')
