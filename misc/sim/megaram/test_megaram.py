"""The collection modes of megaram.vhd: MEGALOAD /C loading, then what the
menus of the cartridges do to start a game (openMSX KonamiUltimateCollection
and Yamanooto); ASCII16-X (Grauw's specification, openMSX RomAscii16X)."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, FallingEdge

MEM = {}


def pat(b, i):
    return (b * 7 + i * 13 + (b >> 8)) & 0xFF


async def ram_model(dut):
    """The SDRAM: 23-bit address (ramadr22 & ramadr), data back the same clock."""
    while True:
        await FallingEdge(dut.clk21m)
        if int(dut.ramreq.value):
            a = (int(dut.ramadr22.value) << 22) | int(dut.ramadr.value)
            if int(dut.ramwrt.value):
                MEM[a] = int(dut.ramdbo.value)
            dut.ramdbi.value = MEM.get(a, 0xEE)


class Bus:
    def __init__(self, dut):
        self.dut = dut
        self.ramacc = 0

    async def acc(self, adr, wrt, val=0):
        d = self.dut
        await FallingEdge(d.clk21m)
        d.adr.value = adr
        d.wrt.value = wrt
        d.dbo.value = val
        d.req.value = 1
        ram = 0
        for _ in range(4):
            await RisingEdge(d.clk21m)
            await ReadOnly()
            ram |= int(d.ramreq.value)
            data = d.dbi.value
        await FallingEdge(d.clk21m)
        d.req.value = 0
        self.ramacc = ram
        return int(data) if data.is_resolvable else None

    async def wr(self, adr, val):
        await self.acc(adr, 1, val)

    async def rd(self, adr):
        return await self.acc(adr, 0)


async def setup(dut, kuc, yam, a16x=0):
    cocotb.start_soon(Clock(dut.clk21m, 10, "ns").start())
    cocotb.start_soon(ram_model(dut))
    dut.kuc.value = kuc
    dut.yam.value = yam
    dut.a16x.value = a16x
    dut.mapsel.value = 0b10          # slot 1: SCC+ (mapsel(0) = 0)
    dut.xmr_ena.value = 0
    dut.clkena.value = 1
    dut.req.value = 0
    dut.wrt.value = 0
    dut.adr.value = 0
    dut.dbo.value = 0
    dut.ramdbi.value = 0
    dut.reset.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk21m)
    dut.reset.value = 0
    await RisingEdge(dut.clk21m)
    return Bus(dut)


BLOCKS = [0, 1, 2, 0xFF, 0x100, 0x150, 0x155, 0x300, 0x382, 0x3FF]


@cocotb.test()
async def kuc(dut):
    MEM.clear()
    b = await setup(dut, 1, 0)
    # MEGALOAD kwblk: 7FFF = A21-A20, 7FFE = 0, 5000 = bank, 7FFF |= 13h, data, 7FFF
    for blk in BLOCKS:
        hi = (blk >> 8) << 6
        await b.wr(0x7FFF, hi)
        await b.wr(0x7FFE, 0)
        await b.wr(0x5000, blk & 0xFF)
        await b.wr(0x7FFF, hi | 0x13)
        for i in range(4):
            await b.wr(0x4000 + i, pat(blk, i))
        await b.wr(0x5000, 0x77)                 # raw: a data byte, not the bank register
        await b.wr(0x7FFF, hi)                   # back: register, not RAM
        assert not b.ramacc, "7FFFh with raw write on went to the RAM"
    for blk in BLOCKS:
        for i in range(4):
            assert MEM.get(blk * 0x2000 + i) == pat(blk, i), f"block {blk:x} byte {i}"
        assert MEM.get(blk * 0x2000 + 0x1000) == 0x77
    # read back: bank 0 + offset
    await b.wr(0x7FFF, 0)
    await b.wr(0x7FFE, 1)
    await b.wr(0x5000, 0)
    assert await b.rd(0x4000) == pat(1, 0), "offset"
    # the launcher: SCC game at block 150h: A21-A20 = 1, offset 50h, registers off
    await b.wr(0x7FFE, 0x50)
    await b.wr(0x7FFF, 0x40 | 0x04)
    await b.wr(0x5000, 0)
    await b.wr(0x7000, 5)
    assert await b.rd(0x4000) == pat(0x150, 0), "SCC game bank 0"
    assert await b.rd(0x6001) == pat(0x155, 1), "SCC game bank 1 (7000h)"
    await b.wr(0x7FFE, 0x00)                     # registers are off now
    assert await b.rd(0x4000) == pat(0x150, 0), "7FFEh written with registers off"
    await b.wr(0x9000, 0x3F)                     # SCC on
    await b.rd(0x9800)
    assert not b.ramacc, "9800h with bank 2 = 3Fh is not the SCC"
    dut._log.info("KUC: loading, offset, A21-A20, SCC game, SCC: ok")


@cocotb.test()
async def kuc_konami(dut):
    MEM.clear()
    for blk in (0x10, 0x13, 0x17, 0x20):
        MEM[blk * 0x2000] = blk
    b = await setup(dut, 1, 0)
    await b.wr(0x7FFE, 0x10)
    await b.wr(0x7FFF, 0x24)                     # Konami, registers off
    await b.wr(0x8000, 3)                        # bank 2
    assert await b.rd(0x8000) == 0x13
    await b.wr(0x4800, 7)                        # 4000-4FFFh: not a register
    await b.wr(0x5000, 7)                        # 5000-57FFh: bank 0
    assert await b.rd(0x4000) == 0x17
    await b.wr(0xA000, 0x10)
    assert await b.rd(0xA000) == 0x20
    dut._log.info("KUC Konami mode: ok")


@cocotb.test()
async def yamanooto(dut):
    MEM.clear()
    b = await setup(dut, 0, 1)
    # MEGALOAD ywblk: ENAR 1, CFGR (blk & 3) << 4, OFFR blk >> 2, 5000 = 0, ENAR 91h, data, ENAR 1
    for blk in BLOCKS:
        await b.wr(0x7FFF, 1)
        await b.wr(0x7FFD, (blk & 3) << 4)
        await b.wr(0x7FFE, blk >> 2)
        await b.wr(0x5000, 0)
        await b.wr(0x7FFF, 0x91)
        for i in range(4):
            await b.wr(0x4000 + i, pat(blk, i))
        await b.wr(0x7FFF, 1)
        assert not b.ramacc, "ENAR with raw write on went to the RAM"
    for blk in BLOCKS:
        for i in range(4):
            assert MEM.get(blk * 0x2000 + i) == pat(blk, i), f"block {blk:x} byte {i}"
    # registers read back with REGEN
    await b.wr(0x7FFE, 0x12)
    assert await b.rd(0x7FFE) == 0x12
    assert (await b.rd(0x7FFD)) & 0x80
    # Konami 4 game at block 380h: offset E0h; banks 1-3 from 6000h / 8000h / A000h
    await b.wr(0x7FFE, 0xE0)
    await b.wr(0x7FFD, 0x08)                     # K4
    await b.wr(0x7FFF, 0)                        # registers off (in K4 this write is bank 1 too)
    await b.wr(0x6000, 2)
    assert await b.rd(0x6000) == pat(0x382, 0), "K4 bank 1"
    await b.wr(0x5000, 9)                        # bank 0 not switchable in K4
    assert await b.rd(0x4000) == pat(0x3FF, 0), "K4 bank 0 kept (the last block loaded)"
    await b.wr(0x8000, 0x1F)                     # 380h + 1Fh = 39Fh
    a = 0x39F * 0x2000
    MEM[a] = 0x5C
    assert await b.rd(0x8000) == 0x5C, "K4 bank 2"
    # SCC mode: bank 2 = 3Fh (raw) -> SCC at 9800h even with an offset
    await b.wr(0x7FFF, 1)
    await b.wr(0x7FFD, 0)
    await b.wr(0x7FFE, 1)
    await b.wr(0x9000, 0x3F)
    await b.rd(0x9800)
    assert not b.ramacc, "SCC by the raw bank value"
    await b.rd(0x9000)
    assert b.ramacc
    dut._log.info("Yamanooto: loading, registers, K4, SCC: ok")


@cocotb.test()
async def konami_mode(dut):
    """MegaSCC+ (no collection): MEGALOAD /4, 7FFEh bit 5 = Konami 4, kept
    through a reset, cleared by a write of 7FFEh."""
    MEM.clear()
    b = await setup(dut, 0, 0)
    for blk in range(8):                         # as MEGALOAD: 7FFE=0, 5000=blk, 7FFE=10h, data
        await b.wr(0x7FFE, 0)
        await b.wr(0x5000, blk)
        await b.wr(0x7FFE, 0x10)
        await b.wr(0x4000, 0x40 + blk)
    await b.wr(0x7FFE, 0)
    for blk in range(8):
        assert MEM.get(blk * 0x2000) == 0x40 + blk
    await b.wr(0x5000, 0)                        # banks as at power on, then Konami
    await b.wr(0x7000, 1)
    await b.wr(0x9000, 2)
    await b.wr(0xB000, 3)
    await b.wr(0x7FFE, 0x20)
    await b.wr(0x6000, 5)
    assert await b.rd(0x6000) == 0x45, "Konami bank 1 from 6000h"
    await b.wr(0xA000, 7)
    assert await b.rd(0xA000) == 0x47, "Konami bank 3 from A000h"
    await b.wr(0x5000, 6)
    assert await b.rd(0x4000) == 0x40, "bank 0 fixed"
    dut.reset.value = 1                          # a reset: banks 0-3, still Konami
    for _ in range(3):
        await RisingEdge(dut.clk21m)
    dut.reset.value = 0
    await b.wr(0x8000, 4)
    assert await b.rd(0x8000) == 0x44, "Konami mode lost by a reset"
    await b.wr(0x7FFE, 0)                        # a loader: back to SCC
    await b.wr(0x7000, 6)
    assert await b.rd(0x6000) == 0x46, "SCC bank 1 from 7000h"
    dut._log.info("MegaSCC+ Konami mode: ok")


async def flash_cmd(b, seq):
    for adr, val in seq:
        await b.wr(adr, val)


async def poll(b, adr, want, tries=4000):
    for _ in range(tries):
        if await b.rd(adr) == want:
            return True
    return False


@cocotb.test()
async def kuc_flash(dut):
    """Pampas & Selene style: sector erase + DQ7 polling, program, a reset."""
    MEM.clear()
    for blk in range(0x80, 0x89):                # sector 10h (banks 80-87h) and the next
        for i in (0, 0x123, 0x124, 0x1FFF):
            MEM[blk * 0x2000 + i] = 0x11
    for blk in (2, 3):                           # first 64 kB: 8 kB sectors
        MEM[blk * 0x2000] = 0x22
    b = await setup(dut, 1, 0)
    await b.wr(0x7FFF, 0x10)                     # flash writes on, Konami SCC
    await b.wr(0x9000, 0x80)                     # 8000h = bank 80h
    await b.wr(0xB000, 0x88)                     # A000h = bank 88h (next sector)
    unlock = [(0x4AAA, 0xAA), (0x4555, 0x55)]
    await flash_cmd(b, unlock + [(0x4AAA, 0x80)] + unlock + [(0x8000, 0x30)])
    assert await poll(b, 0x8000, 0xFF), "erase never done"
    assert await b.rd(0x8123) == 0xFF and await b.rd(0x9FFF) == 0xFF, "sector not erased"
    assert await b.rd(0xA000) == 0x11, "the next sector changed"
    await flash_cmd(b, unlock + [(0x4AAA, 0xA0), (0x8123, 0x5A)])
    assert await poll(b, 0x8123, 0x5A, 10), "program: DQ7 polling"
    assert MEM.get(0x80 * 0x2000 + 0x123) == 0x5A, "programmed byte not in the RAM"
    assert await b.rd(0x8124) == 0xFF, "a neighbour of the programmed byte"
    dut.reset.value = 1
    for _ in range(3):
        await RisingEdge(dut.clk21m)
    dut.reset.value = 0
    await b.wr(0x9000, 0x80)
    assert await b.rd(0x8123) == 0x5A and await b.rd(0x8124) == 0xFF, "lost by a reset"
    # 8 kB sector in the first 64 kB: bank 2 only
    await b.wr(0x7FFF, 0x10)
    await b.wr(0x9000, 0x02)
    await b.wr(0xB000, 0x03)
    await flash_cmd(b, unlock + [(0x4AAA, 0x80)] + unlock + [(0x8000, 0x30)])
    assert await poll(b, 0x8000, 0xFF), "8 kB erase never done"
    assert await b.rd(0xA000) == 0x22, "8 kB erase took the next 8 kB"
    await b.wr(0x9000, 0x80)                     # the old sector is not tracked now: RAM as it is
    assert await b.rd(0x8123) == 0x5A
    dut._log.info("KUC flash: erase, DQ7 polling, program, reset, 8 kB sectors: ok")


@cocotb.test()
async def kuc_dac(dut):
    MEM.clear()
    b = await setup(dut, 1, 0)
    await b.wr(0x7FFF, 0x2E)                     # plain ROM as the launcher: DAC on
    await b.wr(0x4000, 0xC0)
    assert int(dut.KucDac.value) == 0xC0
    await b.wr(0x4010, 0x11)                     # A4 = 1: not the DAC
    assert int(dut.KucDac.value) == 0xC0
    dut._log.info("KUC DAC: ok")


A16_BANKS = [0, 1, 0x7F, 0x80, 0xAF, 0xC0, 0xFF, 0x100, 0x1A5, 0x1FF]


def a16(b, off):
    return b * 0x4000 + off


@cocotb.test()
async def ascii16x(dut):
    """ASCII16-X: the ZEMMIX raw write (A11) for MEGALOAD, then a game: banks
    0 at reset, 6000h / 7000h and the mirrors in the four pages, A8 as bank
    bit 8, the page mirrors at 0000h / C000h."""
    MEM.clear()
    b = await setup(dut, 0, 0, 1)
    # loading: 7800h + (bank >> 8) * 100h = bank & FFh (page 2 raw), data, 7000h = 0
    for bk in A16_BANKS:
        await b.wr(0x7800 | ((bk >> 8) << 8), bk & 0xFF)
        assert not b.ramacc, "the raw register write went to the RAM"
        for off in (0x0000, 0x1FFF, 0x2000, 0x3000, 0x3FFF):   # 2000-3FFFh: the RAM, not a register
            await b.wr(0x8000 + off, pat(bk, off))
            assert b.ramacc, f"raw write {0x8000 + off:04x} not to the RAM"
        await b.wr(0x7000, 0)
        assert not b.ramacc
    for bk in A16_BANKS:
        for off in (0x0000, 0x1FFF, 0x2000, 0x3000, 0x3FFF):
            assert MEM.get(a16(bk, off)) == pat(bk, off), f"bank {bk:x} offset {off:x}"
    await b.wr(0x8000, 0x99)                     # not raw any more
    assert not b.ramacc, "a write to 8000h after the load went to the RAM"
    # a reset: both pages bank 0
    dut.reset.value = 1
    for _ in range(3):
        await RisingEdge(dut.clk21m)
    dut.reset.value = 0
    assert await b.rd(0x4000) == pat(0, 0) and await b.rd(0x8000) == pat(0, 0), "banks 0 at reset"
    # the game: 7000h page 2, 6000h page 1
    await b.wr(0x7000, 0xAF)
    assert await b.rd(0x8000) == pat(0xAF, 0) and await b.rd(0xBFFF) == pat(0xAF, 0x3FFF)
    assert await b.rd(0x0000) == pat(0xAF, 0), "page 2 mirror at 0000h"
    await b.wr(0x60FF, 0xC0)
    assert await b.rd(0x4000) == pat(0xC0, 0) and await b.rd(0xE000) == pat(0xC0, 0x2000), "page 1, mirror C000h"
    # A8: bank bit 8; A9-A10 ignored
    await b.wr(0x7100, 0xA5)
    assert await b.rd(0x9FFF) == pat(0x1A5, 0x1FFF), "bank 1A5h (A8)"
    await b.wr(0x7600, 0x7F)
    assert await b.rd(0x8000) == pat(0x7F, 0), "A9-A10 ignored"
    # register mirrors: 2000h / A000h / E000h page 1, 3000h / B000h / F000h page 2
    for adr, page, bk in ((0x2000, 1, 0x80), (0xA0FF, 1, 0xFF), (0xE000, 1, 0x01),
                          (0x30FF, 2, 0x100), (0xB000, 2, 0xC0), (0xF7FF, 2, 0x1FF)):
        await b.wr(adr | ((bk >> 8) << 8), bk & 0xFF)
        assert not b.ramacc
        rd = 0x4000 if page == 1 else 0x8000
        assert await b.rd(rd) == pat(bk, 0), f"register at {adr:04x}: page {page} bank {bk:x}"
    # a write with A13 = 0 does nothing
    await b.wr(0x9000, 0x12)
    assert not b.ramacc
    assert await b.rd(0x8000) == pat(0x1FF, 0)
    # raw page 2: its own register range is RAM too, the bank stays
    await b.wr(0x7801, 0x80)
    await b.wr(0xB000, 0x55)
    assert b.ramacc and MEM.get(a16(0x80, 0x3000)) == 0x55, "raw B000h to the RAM"
    assert await b.rd(0x8000) == pat(0x80, 0), "raw B000h changed the bank"
    await b.wr(0x7000, 0x80)
    await b.wr(0xB000, 0x01)
    assert not b.ramacc and await b.rd(0x8000) == pat(1, 0), "B000h a register again"
    # the BIOS slot expander test (FFFFh, A11-A9 = 111): a bank, not raw
    await b.wr(0xFFFF, 0xA5)
    assert not b.ramacc
    await b.wr(0x8000, 0x00)
    assert not b.ramacc, "FFFFh made page 2 raw"
    assert await b.rd(0x8000) == pat(0x1A5, 0), "FFFFh: bank 1A5h"
    dut._log.info("ASCII16-X: raw loading, reset, registers, mirrors, A8: ok")
