--
-- megaram.vhd
--   Mega-ROM emulation, SCC+/ASC8K(16Mbits), ASC16K(32Mbits)
--   Revision 3.01
--
-- Copyright (c) 2006 Kazuhiro Tsujikawa (ESE Artists' factory)
-- All rights reserved.
--
-- Redistribution and use of this source code or any derivative works, are
-- permitted provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice,
--    this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
-- 3. Redistributions may not be sold, nor may they be used in a commercial
--    product or activity without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
-- "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
-- TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
-- CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
-- EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
-- PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
-- OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
-- WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
-- OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
-- ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--

--
--  modified by t.hara / KdL
--

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_unsigned.all;

entity megaram is
    port(
        clk21m      : in    std_logic;
        reset       : in    std_logic;
        clkena      : in    std_logic;
        req         : in    std_logic;
        ack         : out   std_logic;
        wrt         : in    std_logic;
        adr         : in    std_logic_vector(15 downto 0);
        dbi         : out   std_logic_vector( 7 downto 0);
        dbo         : in    std_logic_vector( 7 downto 0);

        ramreq      : out   std_logic;
        ramwrt      : out   std_logic;
        ramadr      : out   std_logic_vector(21 downto 0);
        ramdbi      : in    std_logic_vector( 7 downto 0);
        ramdbo      : out   std_logic_vector( 7 downto 0);

        mapsel      : in    std_logic_vector( 1 downto 0);      -- "-0":SCC+, "01":ASC8K, "11":ASC16K

        wavl        : out   std_logic_vector(14 downto 0);
        wavr        : out   std_logic_vector(14 downto 0);

        -- Extended MegaROM Reading                             -- Added by KdL, 2024/Feb/03rd
        xmr_ena     : in    std_logic;

        -- ZEMMIX: Konami Ultimate Collection mapper (SCC+ mode only), 8 MB
        kuc         : in    std_logic := '0';
        ramadr22    : out   std_logic;
        -- ZEMMIX: Yamanooto mapper (Konami Neo-Ultimate Collection), 8 MB
        yam         : in    std_logic := '0';
        colnew      : in    std_logic := '0'                -- a new image loaded: no erased sector
    );
end megaram;

architecture rtl of megaram is

    component scc_wave
        port(
            clk21m  : in    std_logic;
            reset   : in    std_logic;
            clkena  : in    std_logic;
            req     : in    std_logic;
            ack     : out   std_logic;
            wrt     : in    std_logic;
            adr     : in    std_logic_vector( 7 downto 0);
            dbi     : out   std_logic_vector( 7 downto 0);
            dbo     : in    std_logic_vector( 7 downto 0);
            wave    : out   std_logic_vector(14 downto 0)
        );
    end component;

    signal SccSel       : std_logic_vector( 1 downto 0);
    signal Dec1FFE      : std_logic;
    signal DecSccA      : std_logic;
    signal DecSccB      : std_logic;

    signal WavCpy       : std_logic;
    -- ZEMMIX: the ch.D > ch.E copy with its own address / data, and the cpu
    -- held off meanwhile (with the R800 the next access came during the copy:
    -- merged with it, it read stale data, and the copy took the bus as it was)
    signal CpyPend      : std_logic;
    signal CpyGap       : std_logic;
    signal CpyAdr       : std_logic_vector( 4 downto 0);
    signal CpyDat       : std_logic_vector( 7 downto 0);
    signal WavWrt       : std_logic;
    signal WavDbo       : std_logic_vector( 7 downto 0);
    signal WavReq       : std_logic;
    signal WavAck       : std_logic;
    signal WavAdr       : std_logic_vector( 7 downto 0);
    signal WavDbi       : std_logic_vector( 7 downto 0);

    signal SccBankL     : std_logic;
    signal SccBankH     : std_logic;
    signal SccBank0     : std_logic_vector( 7 downto 0);
    signal SccBank1     : std_logic_vector( 7 downto 0);
    signal SccBank2     : std_logic_vector( 7 downto 0);
    signal SccBank3     : std_logic_vector( 7 downto 0);
    signal SccModeA     : std_logic_vector( 7 downto 0);
    signal SccModeB     : std_logic_vector( 7 downto 0);

    signal SccAmp       : std_logic_vector(14 downto 0);

    -- ZEMMIX: Konami mapper without SCC (Konami 4: 4000-5FFFh bank 0, bank
    -- registers 6000-7FFFh, 8000-9FFFh, A000-BFFFh), bit 5 of the 7FFEh
    -- register (as the mapper bit of Konami Ultimate Collection).  Not
    -- cleared by a reset, so a game loaded by MEGALOAD survives one; a
    -- loader writes 7FFEh (bit 4, RAM writable) and so clears it.
    signal KonMode      : std_logic := '0';

    -- ZEMMIX: Konami Ultimate Collection (Manuel Pazos), as openMSX
    -- KonamiUltimateCollection.cc.  8 MB: A21-A20 from the mapper register,
    -- then bank + offset (8 bits), then the 8 kB.
    --   7FFEh offset; 7FFFh mapper register: 7-6 A21-A20, 5 Konami (1) or
    --   Konami SCC (0) bank registers, 4 flash write, 3 bank 0 fixed (Konami)
    --   and DAC, 2 registers 7FFE-7FFFh off (until a reset), 1 bank
    --   switching off, 0 (ZEMMIX) with bit 4: writes go to the RAM as they
    --   are (the loader; the flash commands are not emulated yet)
    --   SCC (bank 2 = 3Fh) / SCC+ (BFFEh, bank 3 bit 7) in both modes.
    signal KucReg       : std_logic_vector( 7 downto 0);
    signal KucOfs       : std_logic_vector( 7 downto 0);
    signal KucBank      : std_logic_vector( 7 downto 0);
    signal KucSel       : std_logic_vector( 1 downto 0);
    signal KucScc       : std_logic;

    -- ZEMMIX: Yamanooto (The SCC Alliance), as openMSX Yamanooto.cc.
    --   7FFFh ENAR (always written): 0 REGEN (7FFC-7FFEh and reading them),
    --     4 WREN (writes to the flash, not the mapper), 7 (ZEMMIX) with
    --     WREN: writes go to the RAM as they are (the loader)
    --   7FFEh OFFR: offset (x4), added to a bank when it is written
    --   7FFDh CFGR: 0 MDIS (no bank switching), 2 ROMDIS (reads FFh),
    --     3 K4 (Konami 4: 6000h / 8000h / A000h, no SCC), 5-4 offset low
    --   banks of 10 bits (8 MB); the SCC goes by the value written (raw)
    signal YamEna       : std_logic_vector( 7 downto 0);
    signal YamOfs       : std_logic_vector( 7 downto 0);
    signal YamCfg       : std_logic_vector( 7 downto 0);
    signal YBank0       : std_logic_vector( 9 downto 0);
    signal YBank1       : std_logic_vector( 9 downto 0);
    signal YBank2       : std_logic_vector( 9 downto 0);
    signal YBank3       : std_logic_vector( 9 downto 0);
    signal YamOff       : std_logic_vector( 9 downto 0);
    signal YamNew       : std_logic_vector( 9 downto 0);
    signal YamReg       : std_logic;
    signal YamRd        : std_logic;
    signal YamScc       : std_logic;
    signal YamSel       : std_logic_vector( 1 downto 0);
    signal YamDbi       : std_logic_vector( 7 downto 0);
    signal ColBank      : std_logic_vector( 9 downto 0);

    -- ZEMMIX: the KUC DAC (Majutsushi, Synthesizer): 7FFFh bit 3, writes to
    -- 4000-5FFFh with A4 = 0, 8 bits unsigned, mixed with the SCC
    signal KucDac       : std_logic_vector( 7 downto 0) := X"80";
    signal DacWav       : std_logic_vector(14 downto 0);

    -- ZEMMIX: the flash of KUC / Yamanooto (both 8 x 8 kB + 127 x 64 kB),
    -- enough for the saves of games (Pampas & Selene): the AMD commands
    -- (AAh to AAAh, 55h to 555h; A0h program; 80h AAh 55h 30h sector erase;
    -- F0h reset), the state moving at the END of an access (a RAM access
    -- never changes its path).  Program: the write goes to the RAM.  Sector
    -- erase: one 64 kB sector at a time has a bitmap (8 kB of block RAM) of
    -- its programmed bytes, the others read FFh; filling it takes 8192 clocks
    -- (the sector reads 00h meanwhile: DQ7 polling waits).  Kept through a
    -- reset.  Flash writes: KUC 7FFFh bit 4 (bit 0 = 0), Yamanooto ENAR WREN.
    type bitmap_t is array (0 to 8191) of std_logic_vector(7 downto 0);
    signal FlMap        : bitmap_t;
    signal FlMapA       : std_logic_vector(12 downto 0);       -- read: the access as it goes
    signal FlMapWA      : std_logic_vector(12 downto 0);       -- write: erase counter / latched access
    signal FlEraW       : std_logic;
    signal FlEraD       : std_logic_vector( 7 downto 0);
    signal FlMapQ       : std_logic_vector( 7 downto 0);
    signal FlMapD       : std_logic_vector( 7 downto 0);
    signal FlMapW       : std_logic;
    signal FlSt         : std_logic_vector( 2 downto 0) := "000";
    signal FlWe         : std_logic;
    signal FlProg       : std_logic;
    signal FlReqD       : std_logic := '0';
    signal FlAcc        : std_logic := '0';                    -- the access latched below is a flash write
    signal FlLAdr       : std_logic_vector(12 downto 0);       -- latched: bank + address in the 8 kB
    signal FlLBank      : std_logic_vector( 9 downto 0);
    signal FlLDbo       : std_logic_vector( 7 downto 0);
    signal TrkV         : std_logic := '0';
    signal TrkSec       : std_logic_vector( 6 downto 0) := (others => '0');
    signal FlBusy       : std_logic := '0';
    signal FlNew        : std_logic := '0';
    signal FlSmall      : std_logic := '0';
    signal FlSub        : std_logic_vector( 2 downto 0) := "000";
    signal FlCnt        : std_logic_vector(12 downto 0) := (others => '0');
    signal InTrk        : std_logic;
    signal FlFF         : std_logic;

begin

    ----------------------------------------------------------------
    -- SCC access decoder
    ----------------------------------------------------------------
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            CpyPend <= '0';
            CpyGap  <= '0';
            WavCpy  <= '0';
        elsif( clk21m'event and clk21m = '1' )then
            -- SCC wave memory copy (ch.D > ch.E): a write to 9860-987Fh is
            -- written again to ch.E once its own access is over, then one clock
            -- without request so that the next cpu access is a new one
            if( WavReq = '1' and WavAck = '1' )then
                if( WavCpy = '1' )then
                    WavCpy  <= '0';
                    CpyGap  <= '1';
                elsif( wrt = '1' and adr(7 downto 5) = "011" and DecSccA = '1' )then
                    CpyPend <= '1';
                    CpyAdr  <= adr(4 downto 0);
                    CpyDat  <= dbo;
                end if;
            elsif( CpyPend = '1' and WavAck = '0' )then
                CpyPend <= '0';
                WavCpy  <= '1';
            elsif( CpyGap = '1' and WavAck = '0' )then
                CpyGap  <= '0';
            end if;
        end if;
    end process;

    -- SCC acknowledge (not for the cpu while the copy is pending)
    ack     <=  req     when( SccSel = "00" )else
                '0'     when( CpyPend = '1' or WavCpy = '1' or CpyGap = '1' )else
                WavAck;

    -- RAM request
    RamReq  <=  req     when( SccSel = "01" )else
                '0';
    RamWrt  <=  wrt;

    -- [R/W] 2048 KB bank indexing $00~$FF = SCC+
    -- [R/W] 1024 KB bank indexing $00~$7F = ASC8K(L)
    -- [R/-] 1024 KB bank indexing $80~$FF = ASC8K(H)
    -- [R/W] 2048 KB bank indexing $00~$7F = ASC16K(L)
    -- [R/-] 2048 KB bank indexing $80~$FF = ASC16K(H)

    -- Extended RAM address
    ramadr22            <=  ColBank(9);
    RamAdr(21)          <=  ColBank(8)  when( kuc = '1' or yam = '1' )else
                            '0'         when( mapsel /= "11" )else
                            '0'         when( xmr_ena = '0' )else
                            '0'         when( (SccBank0(7) = '1' or SccBank2(7) = '1' or SccBank3(7) = '1') and wrt = '1' )else
                            SccBank0(7) when( adr(14) = '1' )else
                            SccBank2(7); -- ( adr(14) = '0' );

    RamAdr(20)          <=  ColBank(7)  when( kuc = '1' or yam = '1' )else
                            '0'         when( xmr_ena = '0' and mapsel = "01" )else
                            '0'         when( (SccBank0(7) = '1' or SccBank2(7) = '1' or SccBank3(7) = '1') and wrt = '1' and mapsel = "01" )else
                            SccBankL    when( adr(14) = '1' and mapsel = "11" )else
                            SccBankH    when( adr(14) = '0' and mapsel = "11" )else
                            SccBank0(7) when( adr(14 downto 13) = "10" )else
                            SccBank1(7) when( adr(14 downto 13) = "11" )else
                            SccBank2(7) when( adr(14 downto 13) = "00" )else
                            SccBank3(7); -- ( adr(14 downto 13) = "01" );

    -- Standard RAM address (MSB was fixed to '0' in 6000-7FFFh of the original module)
    RamAdr(19)          <=  -- SccModeA(6) when( adr(14 downto 13) /= "11" and mapsel(0) = '0' )else
                            -- '0'         when(                               mapsel(0) = '0' )else
                            ColBank(6)  when( kuc = '1' or yam = '1' )else
                            SccBank0(6) when( adr(14 downto 13) = "10" )else
                            SccBank1(6) when( adr(14 downto 13) = "11" )else
                            SccBank2(6) when( adr(14 downto 13) = "00" )else
                            SccBank3(6); -- ( adr(14 downto 13) = "01" );

    RamAdr(18 downto 0) <=  ColBank(5 downto 0) & adr(12 downto 0) when( kuc = '1' or yam = '1' )else
                            SccBank0(5 downto 0) & adr(12 downto 0) when( adr(14 downto 13) = "10" )else
                            SccBank1(5 downto 0) & adr(12 downto 0) when( adr(14 downto 13) = "11" )else
                            SccBank2(5 downto 0) & adr(12 downto 0) when( adr(14 downto 13) = "00" )else
                            SccBank3(5 downto 0) & adr(12 downto 0); -- ( adr(14 downto 13) = "01" );

    -- Mapped I/O port access on 9800-98FFh / B800-B8FFh ... Wave memory
    WavReq  <= '1'  when( WavCpy = '1' )else
               '0'  when( CpyPend = '1' or CpyGap = '1' )else
               req  when( SccSel(1) = '1' )else
               '0';
    WavWrt  <= '1'  when( WavCpy = '1' )else wrt;
    WavDbo  <= CpyDat when( WavCpy = '1' )else dbo;

    -- exchange B8A0-B8BF <> 9880-989F (wave_ch.E) / B8C0-B8DF <> 98E0-98FF (mode register)
    WavAdr  <=  "100" & CpyAdr              when( WavCpy = '1' )else
                (adr(7 downto 0) xor X"20") when( (adr(13) = '0' and adr(7)  = '1') )else
                adr(7 downto 0);

    -- SCC data bus control
    RamDbo  <=  dbo;
    -- an erased byte of the tracked sector (not programmed since): FFh
    FlFF    <=  '1' when( (kuc = '1' or yam = '1') and InTrk = '1' and wrt = '0' and
                          FlMapQ(conv_integer(adr(2 downto 0))) = '0' )else '0';
    dbi     <=  YamDbi  when( yam = '1' and YamRd = '1' )else
                X"00"   when( SccSel = "01" and wrt = '0' and InTrk = '1' and FlBusy = '1' )else
                X"FF"   when( SccSel = "01" and FlFF = '1' )else
                RamDbi  when( SccSel = "01" )else
                WavDbi  when( SccSel = "10" )else
                (others => '1');

    -- KUC: the bank of this page + offset, its decoder
    KucBank <=  (SccBank0 + KucOfs) when( adr(14 downto 13) = "10" )else
                (SccBank1 + KucOfs) when( adr(14 downto 13) = "11" )else
                (SccBank2 + KucOfs) when( adr(14 downto 13) = "00" )else
                (SccBank3 + KucOfs);
    KucScc  <=  '1' when( adr(8) = '0' and SccModeB(4) = '0' and
                          ((SccModeB(5) = '0' and SccBank2(5 downto 0) = "111111" and
                            adr(15 downto 11) = "10011" and adr(10 downto 1) /= "1111111111") or
                           (SccModeB(5) = '1' and SccBank3(7) = '1' and
                            adr(15 downto 11) = "10111" and adr(10 downto 1) /= "1111111111")) )else '0';
    -- a raw write never hits a register (7FFE-7FFFh / BFFE-BFFFh): a write
    -- that changed the mapper in the middle of its own RAM access hung the bus
    KucSel  <=  "10" when( KucScc = '1' )else
                "01" when( (adr(15 downto 14) = "01" or adr(15 downto 14) = "10") and
                           (wrt = '0' or FlProg = '1' or (KucReg(4) = '1' and KucReg(0) = '1' and Dec1FFE = '0')) )else
                "00";

    -- flash writes on, and the write that programs a byte
    FlWe    <=  '1' when( (kuc = '1' and KucReg(4) = '1' and KucReg(0) = '0') or
                          (yam = '1' and YamEna(4) = '1' and YamEna(7) = '0') )else '0';
    FlProg  <=  '1' when( FlWe = '1' and FlSt = "011" and wrt = '1' and
                          (adr(15 downto 14) = "01" or adr(15 downto 14) = "10") and
                          not (yam = '1' and YamReg = '1') and
                          not (kuc = '1' and Dec1FFE = '1' and adr(15 downto 13) = "011") )else '0';
    InTrk   <=  '1' when( TrkV = '1' and ColBank(9 downto 3) = TrkSec )else '0';

    -- Yamanooto decoder
    YamOff  <=  YamOfs & YamCfg(5 downto 4);
    YamNew  <=  ("00" & dbo) + YamOff;
    YamReg  <=  '1' when( adr(15 downto 2) = "01111111111111" )else '0';     -- 7FFC-7FFFh
    YamRd   <=  '1' when( YamReg = '1' and wrt = '0' and YamEna(0) = '1' )else '0';
    YamScc  <=  '1' when( YamCfg(3) = '0' and
                          ((SccModeB(5) = '0' and SccBank2(5 downto 0) = "111111" and adr(15 downto 11) = "10011") or
                           (SccModeB(5) = '1' and SccBank3(7) = '1' and
                            adr(15 downto 11) = "10111" and adr(10 downto 1) /= "1111111111")) )else '0';
    YamSel  <=  "00" when( YamRd = '1' )else
                "10" when( YamScc = '1' and (wrt = '0' or YamEna(4) = '0') )else
                "01" when( (adr(15 downto 14) = "01" or adr(15 downto 14) = "10") and
                           ((wrt = '0' and YamCfg(2) = '0') or FlProg = '1' or
                            (wrt = '1' and YamEna(4) = '1' and YamEna(7) = '1' and YamReg = '0')) )else
                "00";
    YamDbi  <=  X"FF"            when( adr(1 downto 0) = "00" )else       -- FPGA: not there
                YamCfg or X"80"  when( adr(1 downto 0) = "01" )else       -- not busy
                YamOfs           when( adr(1 downto 0) = "10" )else
                YamEna;

    -- the 8 kB bank of this page in the 8 MB (KUC / Yamanooto)
    ColBank <=  KucReg(7 downto 6) & KucBank when( kuc = '1' )else
                YBank0 when( adr(14 downto 13) = "10" )else
                YBank1 when( adr(14 downto 13) = "11" )else
                YBank2 when( adr(14 downto 13) = "00" )else
                YBank3;

    -- SCC address decoder
    SccSel  <=  KucSel when( kuc = '1' )else
                YamSel when( yam = '1' )else
            "10" when   -- memory access (scc_wave)
                        (adr(8) = '0' and SccModeB(4) = '0' and mapsel(0) = '0' and
                        (DecSccA = '1' or DecSccB = '1')) else
            "01" when   -- memory access (MEGA-ROM)
                        -- 4000-7FFFh(R/-, ASC8K/16K)
                        (adr(15 downto 14) = "01"  and mapsel(0) = '1' and                     wrt = '0') or
                        -- 8000-BFFFh(R/-, ASC8K/16K)
                        (adr(15 downto 14) = "10"  and mapsel(0) = '1' and                     wrt = '0') or
                        -- 4000-5FFFh(R/W, ASC8K/16K)
                        (adr(15 downto 13) = "010" and mapsel(0) = '1' and SccBank0(7) = '1'            ) or
                        -- 8000-9FFFh(R/W, ASC8K/16K)
                        (adr(15 downto 13) = "100" and mapsel(0) = '1' and SccBank2(7) = '1'            ) or
                        -- A000-BFFFh(R/W, ASC8K/16K)
                        (adr(15 downto 13) = "101" and mapsel(0) = '1' and SccBank3(7) = '1'            ) or
                        -- 4000-5FFFh(R/-, SCC)
                        (adr(15 downto 13) = "010" and SccModeA(6) = '0' and                   wrt = '0') or
                        -- 6000-7FFFh(R/-, SCC)
                        (adr(15 downto 13) = "011" and                                         wrt = '0') or
                        -- 8000-9FFFh(R/-, SCC)
                        (adr(15 downto 13) = "100" and                       DecSccA = '0' and wrt = '0') or
                        -- A000-BFFFh(R/-, SCC)
                        (adr(15 downto 13) = "101" and SccModeA(6) = '0' and DecSccB = '0' and wrt = '0') or
                        -- 4000-5FFFh(R/W) ESCC-RAM
                        (adr(15 downto 13) = "010" and SccModeA(4) = '1') or
                        -- 6000-7FFDh(R/W) ESCC-RAM
                        (adr(15 downto 13) = "011" and SccModeA(4) = '1' and Dec1FFE /= '1') or
                        -- 4000-7FFFh(R/W) SNATCHER
                        (adr(15 downto 14) = "01"  and SccModeB(4) = '1') or
                        -- 8000-9FFFh(R/W) SNATCHER
                        (adr(15 downto 13) = "100" and SccModeB(4) = '1') or
                        -- A000-BFFDh(R/W) SNATCHER
                        (adr(15 downto 13) = "101" and SccModeB(4) = '1' and Dec1FFE /= '1')                 else
            "00";       -- MEGA-ROM bank register access

    -- Mapped I/O port access on 7FFE-7FFFh / BFFE-BFFFh ... Write protect / SPC mode register
    Dec1FFE <= '1' when( adr(12 downto 1) = "111111111111" )else '0';
    -- Mapped I/O port access on 9800-9FFFh ... Wave memory
    DecSccA <= '1' when( adr(15 downto 11) = "10011" and SccModeB(5) = '0' and SccBank2(5 downto 0) = "111111" )else '0';
    -- Mapped I/O port access on B800-BFFFh ... Wave memory
    DecSccB <= '1' when( adr(15 downto 11) = "10111" and SccModeB(5) = '1' and SccBank3(7) = '1' )else '0';

    ----------------------------------------------------------------
    -- SCC bank register
    ----------------------------------------------------------------
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            SccBankL    <= '0';
            SccBankH    <= '0';
            SccBank0    <= X"00";
            SccBank1    <= X"01";
            SccBank2    <= X"02";
            SccBank3    <= X"03";
            SccModeA    <= (others => '0');
            SccModeB    <= (others => '0');
            KucReg      <= (others => '0');
            KucOfs      <= (others => '0');
            YamEna      <= (others => '0');
            YamOfs      <= (others => '0');
            YamCfg      <= (others => '0');
            YBank0      <= "00" & X"00";
            YBank1      <= "00" & X"01";
            YBank2      <= "00" & X"02";
            YBank3      <= "00" & X"03";
        elsif( clk21m'event and clk21m = '1' )then
            if( yam = '1' )then

                -- Yamanooto: not on a raw RAM write
                if (req = '1' and wrt = '1' and YamSel /= "01" and
                        (adr(15 downto 14) = "01" or adr(15 downto 14) = "10")) then
                    if (YamReg = '1' and adr(1 downto 0) = "11") then
                        YamEna <= dbo;
                    elsif (YamReg = '1' and YamEna(0) = '1') then
                        if (adr(1 downto 0) = "10") then
                            YamOfs <= dbo;
                        elsif (adr(1 downto 0) = "01") then
                            YamCfg <= dbo;
                        end if;
                    end if;
                    if (YamEna(4) = '0' and YamCfg(0) = '0') then
                        if (YamCfg(3) = '1') then
                            -- Konami 4: 6000-BFFFh (bank 0 keeps its value)
                            case adr(14 downto 13) is
                                when "11"   => YBank1 <= YamNew; SccBank1 <= dbo;
                                when "00"   => YBank2 <= YamNew; SccBank2 <= dbo;
                                when "01"   => YBank3 <= YamNew; SccBank3 <= dbo;
                                when others => null;
                            end case;
                        elsif (adr(12 downto 11) = "10") then
                            -- Konami SCC: 5000h, 7000h, 9000h, B000h
                            case adr(14 downto 13) is
                                when "10"   => YBank0 <= YamNew; SccBank0 <= dbo;
                                when "11"   => YBank1 <= YamNew; SccBank1 <= dbo;
                                when "00"   => YBank2 <= YamNew; SccBank2 <= dbo;
                                when others => YBank3 <= YamNew; SccBank3 <= dbo;
                            end case;
                        end if;
                    end if;
                    if (YamEna(4) = '0' and YamCfg(3) = '0' and adr(15 downto 1) = "101111111111111") then
                        SccModeB <= dbo;            -- SCC mode register BFFE-BFFFh
                    end if;
                end if;

            elsif( kuc = '1' )then

                -- KUC: one write can hit several regions (not the SCC)
                if (req = '1' and wrt = '1' and KucSel = "00" and
                        (adr(15 downto 14) = "01" or adr(15 downto 14) = "10")) then
                    if (KucReg(3) = '1' and adr(15 downto 13) = "010" and adr(4) = '0') then
                        KucDac <= dbo;          -- DAC (Majutsushi, Synthesizer)
                    end if;
                    if (KucReg(2) = '0' and adr(15 downto 1) = "011111111111111") then
                        if (adr(0) = '1') then
                            KucReg <= dbo;
                        else
                            KucOfs <= dbo;
                        end if;
                    end if;
                    if (KucReg(1) = '0') then
                        if (KucReg(5) = '0') then
                            -- Konami SCC: 5000-57FFh, 7000-77FFh, 9000-97FFh, B000-B7FFh
                            if (adr(12 downto 11) = "10") then
                                case adr(14 downto 13) is
                                    when "10"   => SccBank0 <= dbo;
                                    when "11"   => SccBank1 <= dbo;
                                    when "00"   => SccBank2 <= dbo;
                                    when others => SccBank3 <= dbo;
                                end case;
                            end if;
                        else
                            -- Konami: 5000-57FFh (unless bit 3), 6000-BFFFh
                            case adr(14 downto 13) is
                                when "10"   =>
                                    if (KucReg(3) = '0' and adr(12 downto 11) = "10") then
                                        SccBank0 <= dbo;
                                    end if;
                                when "11"   => SccBank1 <= dbo;
                                when "00"   => SccBank2 <= dbo;
                                when others => SccBank3 <= dbo;
                            end case;
                        end if;
                        -- SCC mode register BFFE-BFFFh
                        if (adr(15 downto 1) = "101111111111111") then
                            SccModeB <= dbo;
                        end if;
                    end if;
                end if;

            elsif( mapsel(0) = '0' and KonMode = '1' )then

                -- Konami: 6000-7FFFh (not 7FFE-7FFFh), 8000-9FFFh, A000-BFFFh
                if (req = '1' and SccSel = "00" and wrt = '1' and adr(15 downto 13) = "011" and
                        Dec1FFE = '0' and SccModeA(6) = '0' and SccModeA(4) = '0' and SccModeB(4) = '0') then
                    SccBank1 <= dbo;
                end if;
                if (req = '1' and SccSel = "00" and wrt = '1' and adr(15 downto 13) = "100" and
                        SccModeB(4) = '0') then
                    SccBank2 <= dbo;
                end if;
                if (req = '1' and SccSel = "00" and wrt = '1' and adr(15 downto 13) = "101" and
                        SccModeA(6) = '0' and SccModeA(4) = '0' and SccModeB(4) = '0') then
                    SccBank3 <= dbo;
                end if;
                -- Mapped I/O port access on 7FFE-7FFFh ... Register write
                if (req = '1' and SccSel = "00" and wrt = '1' and adr(15 downto 13) = "011" and
                        Dec1FFE = '1' and SccModeB(5 downto 4) = "00") then
                    SccModeA <= dbo;
                end if;

            elsif( mapsel(0) = '0' )then

                -- Mapped I/O port access on 5000-57FFh ... Bank register write
                if (req = '1' and SccSel = "00" and wrt = '1' and adr(15 downto 11) = "01010" and
                        SccModeA(6) = '0' and SccModeA(4) = '0' and SccModeB(4) = '0') then
                    SccBank0 <= dbo;
                end if;
                -- Mapped I/O port access on 7000-77FFh ... Bank register write
                if (req = '1' and SccSel = "00" and wrt = '1' and adr(15 downto 11) = "01110" and
                        SccModeA(6) = '0' and SccModeA(4) = '0' and SccModeB(4) = '0') then
                    SccBank1 <= dbo;
                end if;
                -- Mapped I/O port access on 9000-97FFh ... Bank register write
                if (req = '1' and SccSel = "00" and wrt = '1' and adr(15 downto 11) = "10010" and
                        SccModeB(4) = '0') then
                    SccBank2 <= dbo;
                end if;
                -- Mapped I/O port access on B000-B7FFh ... Bank register write
                if (req = '1' and SccSel = "00" and wrt = '1' and adr(15 downto 11) = "10110" and
                        SccModeA(6) = '0' and SccModeA(4) = '0' and SccModeB(4) = '0') then
                    SccBank3 <= dbo;
                end if;
                -- Mapped I/O port access on 7FFE-7FFFh ... Register write
                if (req = '1' and SccSel = "00" and wrt = '1' and adr(15 downto 13) = "011" and
                        Dec1FFE = '1' and SccModeB(5 downto 4) = "00") then
                    SccModeA <= dbo;
                end if;
                -- Mapped I/O port access on BFFE-BFFFh ... Register write
                if (req = '1' and SccSel = "00" and wrt = '1' and adr(15 downto 13) = "101" and
                        Dec1FFE = '1' and SccModeA(6) = '0' and SccModeA(4) = '0') then
                    SccModeB <= dbo;
                end if;

            else

                -- Mapped I/O port access on 6000-6FFFh ... Bank register write
                if (req = '1' and SccSel = "00" and wrt = '1' and adr(15 downto 12) = "0110") then
                    -- ASC8K / 6000-67FFh
                    if (mapsel(1) = '0' and adr(11) = '0') then
                        SccBank0 <= dbo;
                    -- ASC8K / 6800-6FFFh
                    elsif (mapsel(1) = '0' and adr(11) = '1') then
                        SccBank1 <= dbo;
                    -- ASC16K / 6000-67FFh
                    elsif (adr(11) = '0') then
                        SccBankL <= dbo(6);
                        SccBank0 <= dbo(7) & dbo(5 downto 0) & "0";
                        SccBank1 <= dbo(7) & dbo(5 downto 0) & "1";
                    end if;
                end if;

                -- Mapped I/O port access on 7000-7FFFh ... Bank register write
                if (req = '1' and SccSel = "00" and wrt = '1' and adr(15 downto 12) = "0111") then
                    -- ASC8K / 7000-77FFh
                    if (mapsel(1) = '0' and adr(11) = '0') then
                        SccBank2 <= dbo;
                    -- ASC8K / 7800-7FFFh
                    elsif (mapsel(1) = '0' and adr(11) = '1') then
                        SccBank3 <= dbo;
                    -- ASC16K / 7000-77FFh
                    elsif (adr(11) = '0') then
                        SccBankH <= dbo(6);
                        SccBank2 <= dbo(7) & dbo(5 downto 0) & "0";
                        SccBank3 <= dbo(7) & dbo(5 downto 0) & "1";
                    end if;
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- ZEMMIX: the flash of KUC / Yamanooto
    ----------------------------------------------------------------
    -- bitmap: a byte for 8 flash bytes.  Read at the address of the access,
    -- written by the erase (counter) or for a programmed byte (latched)
    FlMapA  <=  ColBank(2 downto 0) & adr(12 downto 3);
    FlMapWA <=  FlCnt when( FlBusy = '1' )else FlLBank(2 downto 0) & FlLAdr(12 downto 3);
    FlEraW  <=  '1' when( FlBusy = '1' and (FlSmall = '0' or FlCnt(12 downto 10) = FlSub or FlNew = '1') )else '0';
    FlEraD  <=  X"00" when( FlSmall = '0' or FlCnt(12 downto 10) = FlSub )else X"FF";
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            if( FlEraW = '1' )then
                FlMap(conv_integer(FlMapWA)) <= FlEraD;
            elsif( FlMapW = '1' )then
                FlMap(conv_integer(FlMapWA)) <= FlMapD;
            end if;
            FlMapQ <= FlMap(conv_integer(FlMapA));
        end if;
    end process;

    process( clk21m )
        variable bm : std_logic_vector(7 downto 0);
    begin
        if( clk21m'event and clk21m = '1' )then
            FlReqD <= req;
            FlMapW <= '0';
            if( colnew = '1' )then
                TrkV <= '0';
            end if;
            if( kuc = '0' and yam = '0' )then
                FlSt   <= "000";
                FlBusy <= '0';
                FlAcc  <= '0';
            elsif( FlBusy = '1' )then
                -- erase: the erased range 0, the rest of a newly tracked sector 1
                FlCnt <= FlCnt + 1;
                if( FlCnt = "1111111111111" )then
                    FlBusy <= '0';
                end if;
            elsif( req = '1' and FlReqD = '0' )then
                -- start of an access: latch it
                FlLAdr  <= adr(12 downto 0);
                FlLBank <= ColBank;
                FlLDbo  <= dbo;
                FlAcc   <= FlWe and wrt and (adr(15) xor adr(14)) and
                           not (yam and YamReg) and not (kuc and Dec1FFE and not adr(15) and adr(14) and adr(13));
            elsif( req = '0' and FlReqD = '1' and FlAcc = '1' )then
                -- end of a flash write: the command sequence
                FlAcc <= '0';
                case FlSt is
                    when "000" =>
                        if( FlLDbo = X"AA" and FlLAdr(11 downto 1) = "10101010101" )then FlSt <= "001"; end if;
                    when "001" =>
                        if( FlLDbo = X"55" and FlLAdr(11 downto 1) = "01010101010" )then FlSt <= "010"; else FlSt <= "000"; end if;
                    when "010" =>
                        if( FlLDbo = X"A0" and FlLAdr(11 downto 1) = "10101010101" )then FlSt <= "011";
                        elsif( FlLDbo = X"80" and FlLAdr(11 downto 1) = "10101010101" )then FlSt <= "100";
                        else FlSt <= "000"; end if;
                    when "011" =>
                        -- programmed (the RAM got it): mark the byte if its sector is tracked
                        FlSt <= "000";
                        if( TrkV = '1' and FlLBank(9 downto 3) = TrkSec )then
                            bm := FlMapQ;
                            bm(conv_integer(FlLAdr(2 downto 0))) := '1';
                            FlMapD <= bm;
                            FlMapW <= '1';
                        end if;
                    when "100" =>
                        if( FlLDbo = X"AA" and FlLAdr(11 downto 1) = "10101010101" )then FlSt <= "101"; else FlSt <= "000"; end if;
                    when "101" =>
                        if( FlLDbo = X"55" and FlLAdr(11 downto 1) = "01010101010" )then FlSt <= "110"; else FlSt <= "000"; end if;
                    when "110" =>
                        FlSt <= "000";
                        if( FlLDbo = X"30" )then
                            -- sector erase: 8 kB in the first 64 kB, else 64 kB
                            if( TrkV = '0' or FlLBank(9 downto 3) /= TrkSec )then
                                FlNew <= '1';
                            else
                                FlNew <= '0';
                            end if;
                            TrkV    <= '1';
                            TrkSec  <= FlLBank(9 downto 3);
                            if( FlLBank(9 downto 3) = "0000000" )then FlSmall <= '1'; else FlSmall <= '0'; end if;
                            FlSub   <= FlLBank(2 downto 0);
                            FlCnt   <= (others => '0');
                            FlBusy  <= '1';
                        end if;
                    when others =>
                        FlSt <= "000";
                end case;
                if( FlLDbo = X"F0" )then
                    FlSt <= "000";
                end if;
            elsif( req = '0' and FlReqD = '1' )then
                FlAcc <= '0';
            end if;
        end if;
    end process;

    -- Konami mode bit: 7FFEh bit 5, kept through a reset
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            if (kuc = '0' and yam = '0' and mapsel(0) = '0' and req = '1' and SccSel = "00" and wrt = '1' and
                    adr(15 downto 13) = "011" and Dec1FFE = '1' and SccModeB(5 downto 4) = "00") then
                KonMode <= dbo(5);
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Connect components
    ----------------------------------------------------------------
    SccCh : scc_wave
    port map(
        clk21m  => clk21m       ,
        reset   => reset        ,
        clkena  => clkena       ,
        req     => WavReq       ,
        ack     => WavAck       ,
        wrt     => WavWrt       ,
        adr     => WavAdr       ,
        dbi     => WavDbi       ,
        dbo     => WavDbo       ,
        wave    => SccAmp
    );

    ----------------------------------------------------------------
    -- Wave output (L / R)
    ----------------------------------------------------------------
    DacWav <= (not KucDac(7)) & (not KucDac(7)) & (not KucDac(7)) & KucDac(6 downto 0) & "00000";
    wavl <= SccAmp + DacWav when( kuc = '1' )else SccAmp;
    wavr <= SccAmp + DacWav when( kuc = '1' )else SccAmp;

end rtl;
