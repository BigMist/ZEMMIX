--
-- sm_emsx_top.vhd
--   ESE MSX-SYSTEM3 / MSX clone on a Cyclone FPGA (ALTERA)
--   Revision 1.00
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
---------------------------------------------------------------------------------
-- OCM-PLD Pack v3.9.2 by KdL (2024.02.03)
-- MSX2+ Stable Release for SM-X (regular) and SX-2 / MSXtR Experimental
-- Special thanks to t.hara, caro, mygodess & all MRC users (http://www.msx.org)
---------------------------------------------------------------------------------
-- Setup for XTAL 50.00000MHz
---------------------------------------------------------------------------------
--

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_unsigned.all;
	 use ieee.std_logic_arith.ALL;

    use work.vdp_package.all;

entity emsx_top is
    generic(
        use_wifi_g      : boolean   := true;
        use_midi_g      : boolean   := true;
        use_opl3_g      : boolean   := true;
        opl3_fpga_g     : boolean   := false;                           -- OPL3: false = opl3sw (Next186), true = opl3_fpga (Greg Taylor, clk_opl = 50MHz)
        use_opl4_g      : boolean   := false;                           -- OPL4 wave part (MoonSound: FM C4-C7h + wave 7E-7Fh), needs opl3_fpga_g and clk_opl = 50MHz
        use_dualpsg_g   : boolean   := true;
        psg_ym_g        : integer   := 0;                               -- PSG personality: 0 = AY-3-8910, 1 = YM2149
        opl3_clk_g      : integer   := 86000000                         -- clk_opl in Hz
    );
    port(
        -- Clock, Reset ports
        Clk21m          : in    std_logic;                                      -- VDP Clock ... 21.48MHz
		  memclk          : in    std_logic;
		  clk_opl         : in    std_logic;                            -- OPL3 clock (opl3_clk_g Hz)
        pExtClk         : in    std_logic;                                      -- Reserved (for multi FPGAs)
        pCpuClk         : out   std_logic;                                      -- CPU Clock ... 3.58MHz (up to 10.74MHz/21.48MHz)
        reset           : inout std_logic;
        --power_on_reset  : inout std_logic := '0';

        -- MSX cartridge slot ports
        pSltClk         : in    std_logic;                                      -- pCpuClk returns here, for Z80, etc.
        pSltRst_n       : in    std_logic;                                      -- RESET_n  (w/ external pull-up)
        pSltSltsl_n     : inout std_logic;
        pSltSlts2_n     : inout std_logic;
        pSltIorq_n      : inout std_logic;
        pSltRd_n        : inout std_logic;
        pSltWr_n        : inout std_logic;
        pSltAdr         : inout std_logic_vector( 15 downto 0 );
        pSltDat         : inout std_logic_vector(  7 downto 0 );
        pSltBdir_n      : out   std_logic;                                      -- Bus direction (not used in master mode)

        pSltCs1_n       : inout std_logic;
        pSltCs2_n       : inout std_logic;
        pSltCs12_n      : inout std_logic;
        pSltRfsh_n      : inout std_logic;
        pSltWait_n      : inout std_logic;                                      -- WAIT_n   (w/ external pull-up)
        pSltInt_n       : inout std_logic;                                      -- INT_n    (w/ external pull-up)
        pSltM1_n        : inout std_logic;
        pSltMerq_n      : inout std_logic;

        pSltRsv5        : inout std_logic;                                      -- Reserved
        pSltRsv16       : inout std_logic;                                      -- Reserved (w/ external pull-up)
        pSltSw1         : inout std_logic;                                      -- Reserved
        pSltSw2         : inout std_logic;                                      -- Reserved
        BusDir_o        : inout std_logic;

        -- SDRAM ports
        pMemClk         : out   std_logic;                                      -- SDRAM Clock
        pMemCke         : out   std_logic;                                      -- SDRAM Clock enable
        pMemCs_n        : out   std_logic;                                      -- SDRAM Chip select
        pMemRas_n       : out   std_logic;                                      -- SDRAM Row/RAS
        pMemCas_n       : out   std_logic;                                      -- SDRAM /CAS
        pMemWe_n        : out   std_logic;                                      -- SDRAM /WE
        pMemUdq         : out   std_logic;                                      -- SDRAM UDQM
        pMemLdq         : out   std_logic;                                      -- SDRAM LDQM
        pMemBa1         : out   std_logic;                                      -- SDRAM Bank select address 1
        pMemBa0         : out   std_logic;                                      -- SDRAM Bank select address 0
        pMemAdr         : out   std_logic_vector( 12 downto 0 );                -- SDRAM Address
        pMemDat         : inout std_logic_vector( 15 downto 0 );                -- SDRAM Data

        -- PS/2 keyboard ports
        pPs2Clk         : inout std_logic;
        pPs2Dat         : inout std_logic;

        -- 2022/Dec/14th Added by t.hara for ESEPS2MOUSE ----------------------
        -- PS/2 mouse ports
        pPs2Clk_m       : inout std_logic;
        pPs2Dat_m       : inout std_logic;
        -- 2022/Dec/14th Added by t.hara for ESEPS2MOUSE ----------------------

        -- Joystick ports (Port_A, Port_B)
        pJoyA_in        : in    std_logic_vector(  5 downto 0 );
        pJoyA_out       : out   std_logic_vector(  1 downto 0 );
        pStrA           : out   std_logic;
        pJoyB_in        : in    std_logic_vector(  5 downto 0 );
        pJoyB_out       : out   std_logic_vector(  1 downto 0 );
        pStrB           : out   std_logic;

        -- SD/MMC slot ports
        pSd_Ck          : out   std_logic;                                      -- pin 5
        pSd_Cm          : out   std_logic;                                      -- pin 2
        pSd_Dt          : inout std_logic_vector(  3 downto 0 );                -- pin 1(D3), 9(D2), 8(D1), 7(D0)

        -- DIP switch, Lamp ports
        pDip            : in    std_logic_vector(  7 downto 0 );                -- 0=On, 1=Off (default on shipment)
        pLed            : out   std_logic_vector(  7 downto 0 );                -- 0=Off, 1=On (green)
        pLedPwr         : out   std_logic;                                      -- 0=Off, 1=On (red)

        -- Video, Audio ports
        pDac_VR         : inout std_logic_vector(  5 downto 0 );                -- RGB_Red / Svideo_C
        pDac_VG         : inout std_logic_vector(  5 downto 0 );                -- RGB_Grn / Svideo_Y
        pDac_VB         : inout std_logic_vector(  5 downto 0 );                -- RGB_Blu / Composite Video
        --pDac_SL         : out   std_logic_vector(  5 downto 0 ) := "ZZZZZZ";    -- Sound-L
        --pDac_SR         : out   std_logic_vector(  5 downto 0 ) := "ZZZZZZ";    -- Sound-R

        pVideoHS_n      : out   std_logic;                                      -- Csync(RGB15K), HSync(VGA31K)
        pVideoVS_n      : out   std_logic;                                      -- Audio(RGB15K), VSync(VGA31K)

        pVideoClk       : out   std_logic;                                      -- (Reserved)
        pVideoDat       : out   std_logic;                                      -- (Reserved)

        -- Reserved ports (USB)
        pUsbP1          : in    std_logic := 'Z';
        pUsbN1          : out   std_logic := 'Z';
        pUsbP2          : inout std_logic;
        pUsbN2          : inout std_logic;

        -- Reserved ports
        pIopRsv14       : in    std_logic;
        pIopRsv15       : in    std_logic;
        pIopRsv16       : in    std_logic;
        pIopRsv17       : in    std_logic;
        pIopRsv18       : in    std_logic;
        pIopRsv19       : in    std_logic;
        pIopRsv20       : in    std_logic;
        pIopRsv21       : in    std_logic;

        -- Poseidon ports
        clk21m_out      : out   std_logic;
        --clk_hdmi        : out   std_logic;
        esp_rx_o        : out   std_logic := 'Z';
        esp_tx_i        : in    std_logic := 'Z';
        blank_o         : out   std_logic;
        ear_i           : in    std_logic;
        mic_o           : out   std_logic;
        midi_o          : out   std_logic;
		  midi_i          : in    std_logic;
        midi_active_o   : out   std_logic;
        vga_status      : out   std_logic;
        vga_scanlines   : inout std_logic_vector(  1 downto 0 );
		  opl3_l         : out std_logic_vector(15 downto 0 );
		  opl3_r         : out std_logic_vector(15 downto 0 );
		  opl4_l         : out std_logic_vector(15 downto 0 );         -- OPL4 wave (PCM)
		  opl4_r         : out std_logic_vector(15 downto 0 );
		  opll_o         : out std_logic_vector(15 downto 0 );
		  scc1_l         : out std_logic_vector(14 downto 0 );
		  scc1_r         : out std_logic_vector(14 downto 0 );
 		  scc2_l         : out std_logic_vector(14 downto 0 );
		  scc2_r         : out std_logic_vector(14 downto 0 );
		  psg_o          : out std_logic_vector( 15 downto 0 );     -- PSG + PSG2 + key click, unsigned 0..26618
        TrPcm_o        : out std_logic_vector( 7 downto 0 );
		  Vol_o          : out std_logic_vector( 2 downto 0 );      -- MstrVol
		  PsgVol_o       : out std_logic_vector( 2 downto 0 );
		  SccVol_o       : out std_logic_vector( 2 downto 0 );
		  OpllVol_o      : out std_logic_vector( 2 downto 0 );
        btn_scan       : in    std_logic;

        -- ZEMMIX.ROM (YRW801) from data_io index 0, to the OPL4 wave memory
        rom_dl_i       : in    std_logic := '0';
        rom_wr_i       : in    std_logic := '0';
        rom_dat_i      : in    std_logic_vector(  7 downto 0 ) := (others => '0')
    );
end emsx_top;

architecture RTL of emsx_top is

--    -- Clock generator ( Altera specific component )
--    component pll4x
--        port(
--            inclk0  : in    std_logic := '0';   -- 21.48MHz input to PLL    (external I/O pin, from crystal oscillator)
--            c0      : out   std_logic;          -- 21.48MHz output from PLL (internal LEs, for VDP, internal-bus, etc.)
--            c1      : out   std_logic;          -- 85.92MHz output from PLL (internal LEs, for SDRAM)
--            e0      : out   std_logic           -- 85.92MHz output from PLL (external I/O pin, for SDRAM)
--        );
--    end component;

    -- CPU
    component t80a
        port(
            RESET_n     : in    std_logic;
            R800_mode   : in    std_logic;
            CLK_n       : in    std_logic;
            WAIT_n      : in    std_logic;
            INT_n       : in    std_logic;
            NMI_n       : in    std_logic;
            BUSRQ_n     : in    std_logic;
            M1_n        : out   std_logic;
            MREQ_n      : out   std_logic;
            IORQ_n      : out   std_logic;
            RD_n        : out   std_logic;
            WR_n        : out   std_logic;
            RFSH_n      : out   std_logic;
            HALT_n      : out   std_logic;
            BUSAK_n     : out   std_logic;
            A           : out   std_logic_vector( 15 downto 0 );
            D           : inout std_logic_vector(  7 downto 0 )
        );
    end component;

    -- boot loader ROM (initial program loader)
    component iplrom
        port(
            clk     : in    std_logic;
            adr     : in    std_logic_vector( 15 downto 0 );
            dbi     : out   std_logic_vector(  7 downto 0 )
        );
    end component;

    -- MEGA-SD (SD controller)
    component megasd
        port(
            clk21m  : in    std_logic;
            reset   : in    std_logic;
            req     : in    std_logic;
            wrt     : in    std_logic;
            adr     : in    std_logic_vector( 15 downto 0 );
            dbo     : in    std_logic_vector(  7 downto 0 );

            ramreq  : out   std_logic;
            ramwrt  : out   std_logic;
            ramadr  : out   std_logic_vector( 19 downto 0 );

            mmcdbi  : out   std_logic_vector(  7 downto 0 );
            mmcena  : out   std_logic;
            mmcact  : out   std_logic;

            mmc_ck  : out   std_logic;
            mmc_cs  : out   std_logic;
            mmc_di  : out   std_logic;
            mmc_do  : in    std_logic;

            epc_ck  : out   std_logic;
            epc_cs  : out   std_logic;
            epc_oe  : out   std_logic;
            epc_di  : out   std_logic;
            epc_do  : in    std_logic;

            debug   : out   std_logic_vector(  7 downto 0 )
        );
    end component;


    -- ASMI (Altera specific component)
    component cyclone_asmiblock
        port(
            dclkin      : in    std_logic;      -- DCLK
            scein       : in    std_logic;      -- nCSO
            sdoin       : in    std_logic;      -- ASDO
            oe          : in    std_logic;      -- 1=disable(Hi-Z)
            data0out    : out   std_logic       -- DATA0
        );
    end component;


    component mapper
        port(
            clk21m      : in    std_logic;
            reset       : in    std_logic;
            req         : in    std_logic;
            ack         : out   std_logic;
            mem         : in    std_logic;
            wrt         : in    std_logic;
            adr         : in    std_logic_vector( 15 downto 0 );
            dbi         : out   std_logic_vector(  7 downto 0 );
            dbo         : in    std_logic_vector(  7 downto 0 );

            ramreq      : out   std_logic;
            ramwrt      : out   std_logic;
            ramadr      : out   std_logic_vector( 21 downto 0 );
            ramdbi      : in    std_logic_vector(  7 downto 0 );
            ramdbo      : out   std_logic_vector(  7 downto 0 )
        );
    end component;

    component eseps2
        port(
            clk21m      : in     std_logic;
            reset       : in     std_logic;
            clkena      : in     std_logic;

            Kmap        : in     std_logic;

            Caps        : inout  std_logic;
            Kana        : inout  std_logic;
            Paus        : inout  std_logic;
            Scro        : inout  std_logic;
            Reso        : inout  std_logic;

            FKeys       : buffer std_logic_vector(  7 downto 0 );

            pPs2Clk     : inout  std_logic;
            pPs2Dat     : inout  std_logic;

            PpiPortC    : in     std_logic_vector(  7 downto 0 );
            pKeyX       : out    std_logic_vector(  7 downto 0 );

            CmtScro     : inout  std_logic
        );
    end component;

    -- 2022/Dec/14th Added by t.hara for ESEPS2MOUSE -------------
    component eseps2mouse
        port (
            clk21m          : in    std_logic;
            reset           : in    std_logic;
            clkena          : in    std_logic;
            pPs2Clk         : inout std_logic;
            pPs2Dat         : inout std_logic;
            pJoyA_in        : in    std_logic_vector( 5 downto 0 );
            pJoyA_out       : out   std_logic_vector( 1 downto 0 );
            pStrA           : out   std_logic;
            pJoyA_in_m      : out   std_logic_vector( 5 downto 0 );
            pJoyA_out_m     : in    std_logic_vector( 1 downto 0 );
            pStrA_m         : in    std_logic;
            pLed            : in    std_logic_vector( 7 downto 0 );
            pLedPwr         : in    std_logic;
            Slt2Mode        : in    std_logic_vector( 1 downto 0 );
            Slt1Type        : in    std_logic_vector( 1 downto 0 );
            MstrVol         : in    std_logic_vector( 2 downto 0 );
            OpllVol         : in    std_logic_vector( 2 downto 0 );
            PsgVol          : in    std_logic_vector( 2 downto 0 );
            tMegaSD         : in    std_logic;
            tPanaRedir      : in    std_logic;
            SccVol          : in    std_logic_vector( 2 downto 0 );
            VdpSpeedMode    : in    std_logic;
            CustomSpeed     : in    std_logic_vector( 3 downto 0 );
            Af_mask         : in    std_logic;
            V9938_n         : in    std_logic;
            swioKmap        : in    std_logic;
            caps            : in    std_logic;
            kana            : in    std_logic;
            iPsg2_ena       : in    std_logic;
            vga_scanlines   : in    std_logic_vector( 1 downto 0 );
            clksel          : in    std_logic;
            extclk3m        : in    std_logic;
            ntsc_pal_type   : in    std_logic;
            forced_v_mode   : in    std_logic;
            swioCmt         : in    std_logic;
            iSlt1_linear    : in    std_logic;
            iSlt2_linear    : in    std_logic;
            right_inverse   : in    std_logic;
            clksel5m_n      : in    std_logic
        );
    end component;
    -- 2022/Dec/14th Added by t.hara for ESEPS2MOUSE -------------

    component rtc
        port(
            clk21m      : in    std_logic;
            reset       : in    std_logic;
            clkena      : in    std_logic;
            req         : in    std_logic;
            ack         : out   std_logic;
            wrt         : in    std_logic;
            adr         : in    std_logic_vector( 15 downto 0 );
            dbi         : out   std_logic_vector(  7 downto 0 );
            dbo         : in    std_logic_vector(  7 downto 0 )
        );
    end component;

    component kanji
        port(
            clk21m          : in    std_logic;
            reset           : in    std_logic;
            req             : in    std_logic;
            ack             : out   std_logic;
            wrt             : in    std_logic;
            adr             : in    std_logic_vector( 15 downto 0 );
            dbi             : out   std_logic_vector(  7 downto 0 );
            dbo             : in    std_logic_vector(  7 downto 0 );

            ramreq          : out   std_logic;
            ramadr          : out   std_logic_vector( 17 downto 0 );
            ramdbi          : in    std_logic_vector(  7 downto 0 );
            ramdbo          : out   std_logic_vector(  7 downto 0 )
        );
    end component;

    component vdp
        port(
            -- VDP Clock ... 21.477MHz
            clk21m          : in    std_logic;
            reset           : in    std_logic;
            req             : in    std_logic;
            ack             : out   std_logic;
            wrt             : in    std_logic;
            adr             : in    std_logic_vector( 15 downto 0 );
            dbi             : out   std_logic_vector(  7 downto 0 );
            dbo             : in    std_logic_vector(  7 downto 0 );

            int_n           : out   std_logic;

            pRamOe_n        : out   std_logic;
            pRamWe_n        : out   std_logic;
            pRamAdr         : out   std_logic_vector( 16 downto 0 );
            pRamDbi         : in    std_logic_vector( 15 downto 0 );
            pRamDbo         : out   std_logic_vector(  7 downto 0 );

            VdpSpeedMode    : in    std_logic;                          -- for TH9958 VDP core
            RatioMode       : in    std_logic_vector(  2 downto 0 );    -- for TH9958 VDP core
            centerYJK_R25_n : in    std_logic;                          -- for TH9958 VDP core

            -- Video Output
            pVideoR         : out   std_logic_vector(  5 downto 0 );
            pVideoG         : out   std_logic_vector(  5 downto 0 );
            pVideoB         : out   std_logic_vector(  5 downto 0 );

            pVideoHS_n      : out   std_logic;
            pVideoVS_n      : out   std_logic;
            pVideoCS_n      : out   std_logic;

            pVideoDHClk     : out   std_logic;
            pVideoDLClk     : out   std_logic;
            BLANK_o         : out   std_logic;

            -- CXA1645(RGB->NTSC encoder) signals
--          pVideoSC        : out   std_logic;                          -- for V9938 VDP core
--          pVideoSYNC      : out   std_logic;                          -- for V9938 VDP core

            -- Display resolution (0=15kHz, 1=31kHz)
            DispReso        : in    std_logic;

            ntsc_pal_type   : in    std_logic;
            forced_v_mode   : in    std_logic;
            legacy_vga      : in    std_logic;

            VDP_ID          : in    std_logic_vector(  4 downto 0 );
            OFFSET_Y        : in    std_logic_vector(  6 downto 0 );

            wait_n          : out   std_logic;                           -- V9968: VRAM read in progress

            busy            : out   std_logic                           -- V9968: a request is still running
        );
    end component;

    component vencode
        port(
            clk21m      : in    std_logic;
            reset       : in    std_logic;
            videoR      : in    std_logic_vector(  5 downto 0 );
            videoG      : in    std_logic_vector(  5 downto 0 );
            videoB      : in    std_logic_vector(  5 downto 0 );
            videoHS_n   : in    std_logic;
            videoVS_n   : in    std_logic;
            videoY      : out   std_logic_vector(  5 downto 0 );
            videoC      : out   std_logic_vector(  5 downto 0 );
            videoV      : out   std_logic_vector(  5 downto 0 )
        );
    end component;

    component msx_psg
        generic(
            YM          : integer := 0
        );
        port(
            clk21m      : in    std_logic;
            reset       : in    std_logic;
            clkena      : in    std_logic;
            req         : in    std_logic;
            ack         : out   std_logic;
            wrt         : in    std_logic;
            adr         : in    std_logic_vector( 15 downto 0 );
            dbi         : out   std_logic_vector(  7 downto 0 );
            dbo         : in    std_logic_vector(  7 downto 0 );

            joya_in     : in    std_logic_vector(  5 downto 0 );
            joya_out    : out   std_logic_vector(  1 downto 0 );
            stra        : out   std_logic;
            joyb_in     : in    std_logic_vector(  5 downto 0 );
            joyb_out    : out   std_logic_vector(  1 downto 0 );
            strb        : out   std_logic;

            kana        : out   std_logic;
            cmtin       : in    std_logic;
            keymode     : in    std_logic;

            wave        : out   std_logic_vector( 14 downto 0 )
        );
    end component;

    component megaram   -- ESE-MegaSCC+ / ESE-MegaRAM (not a brazilian MegaRAM)
        port(
            clk21m      : in    std_logic;
            reset       : in    std_logic;
            clkena      : in    std_logic;
            req         : in    std_logic;
            ack         : out   std_logic;
            wrt         : in    std_logic;
            adr         : in    std_logic_vector( 15 downto 0 );
            dbi         : out   std_logic_vector(  7 downto 0 );
            dbo         : in    std_logic_vector(  7 downto 0 );

            ramreq      : out   std_logic;
            ramwrt      : out   std_logic;
            ramadr      : out   std_logic_vector( 21 downto 0 );
            ramdbi      : in    std_logic_vector(  7 downto 0 );
            ramdbo      : out   std_logic_vector(  7 downto 0 );

            mapsel      : in    std_logic_vector(  1 downto 0 );        -- "0-":SCC+, "10":ASC8K, "11":ASC16K

            wavl        : out   std_logic_vector( 14 downto 0 );
            wavr        : out   std_logic_vector( 14 downto 0 );

            -- Extended MegaROM Reading, Added by KdL, 2024/Feb/03rd
            xmr_ena     : in    std_logic
        );
    end component;

    component eseopll
        port(
            clk21m      : in    std_logic;
            reset       : in    std_logic;
            clkena      : in    std_logic;
            enawait     : in    std_logic;
            req         : in    std_logic;
            ack         : out   std_logic;
            wrt         : in    std_logic;
            adr         : in    std_logic_vector( 15 downto 0 );
            dbo         : in    std_logic_vector(  7 downto 0 );
            wav         : out   std_logic_vector( 15 downto 0 )
            );
    end component;

    --  system timer (S1990)
    component system_timer
        port(
            clk21m  : in    std_logic;
            reset   : in    std_logic;
            req     : in    std_logic;
            ack     : out   std_logic;
            wrt     : in    std_logic;
            adr     : in    std_logic_vector( 15 downto 0 );
            dbi     : out   std_logic_vector(  7 downto 0 );
            dbo     : in    std_logic_vector(  7 downto 0 )
        );
    end component;

    --  switched I/O ports
    component switched_io_ports
        generic(
            use_wifi_g      : boolean
        );
        port(
            clk21m          : in    std_logic;
            reset           : in    std_logic;
            power_on_reset  : in    std_logic;
            req             : in    std_logic;
            ack             : out   std_logic;
            wrt             : in    std_logic;
            adr             : in    std_logic_vector( 15 downto 0 );
            dbi             : out   std_logic_vector(  7 downto 0 );
            dbo             : in    std_logic_vector(  7 downto 0 );

            io40_n          : inout std_logic_vector(  7 downto 0 );            -- ID Manufacturers/Devices :   $08 (008), $D4 (212=OCM ID, now MSX++ ID), $FF (255=null)
            io41_id212_n    : inout std_logic_vector(  7 downto 0 );            -- $41 ID212 states         :   Smart Commands
            io42_id212      : inout std_logic_vector(  7 downto 0 );            -- $42 ID212 states         :   Virtual DIP-SW states
            io43_id212      : inout std_logic_vector(  7 downto 0 );            -- $43 ID212 states         :   Lock Mask for port $42 functions, CMT and System Reset
            io44_id212      : inout std_logic_vector(  7 downto 0 );            -- $44 ID212 states         :   Lights Mask has the green leds control when Lights Mode is On

            PsgVol          : inout std_logic_vector(  2 downto 0 );            -- PSG Volume
            MstrVol         : inout std_logic_vector(  2 downto 0 );            -- Master Volume
            OpllVol         : inout std_logic_vector(  2 downto 0 );            -- OPLL Volume
            SccVol          : inout std_logic_vector(  2 downto 0 );            -- SCC-I Volume

            CustomSpeed     : inout std_logic_vector(  3 downto 0 );            -- Counter limiter of CPU wait control
            tMegaSD         : inout std_logic;                                  -- Turbo on MegaSD access   :   3.58MHz to 5.37MHz auto selection
            tPanaRedir      : inout std_logic;                                  -- tPana Redirection switch
            VdpSpeedMode    : inout std_logic;                                  -- VDP Speed Mode           :   0=Normal, 1=Fast
            V9938_n         : in    std_logic;                                  -- VDP core installed       :   0=V9938, 1=TH9958
            Mapper_req      : inout std_logic;                                  -- Mapper req               :   Warm Reset is required to complete the request
            Mapper_ack      : out   std_logic;                                  -- Current Mapper state
            MegaSD_req      : inout std_logic;                                  -- MegaSD req               :   Warm Reset is required to complete the request
            MegaSD_ack      : out   std_logic;                                  -- Current MegaSD state

            io41_id008_n    : inout std_logic;                                  -- $41 ID008 BIT-0 state    :   0=5.37MHz, 1=3.58MHz (write_n only)
            swioKmap        : inout std_logic;                                  -- Keyboard layout selector
            CmtScro         : inout std_logic;                                  -- CMT state
            swioCmt         : inout std_logic;                                  -- CMT enabler              :   This toggle is used for the Internal OPL3 on SM-X, SX-2 and SX-E
            LightsMode      : inout std_logic;                                  -- Custom green led states
            Red_sta         : inout std_logic;                                  -- Custom red led state
            LastRst_sta     : inout std_logic;                                  -- Last reset state         :   0=F4 Cold Reset, 1=F4 Warm Reset (MSX2+) / 1=F4 Cold Reset, 0=F4 Warm Reset (MSXtR)
            RstReq_sta      : inout std_logic;                                  -- Reset request state      :   0=No, 1=Yes
            Blink_ena       : inout std_logic;                                  -- MegaSD blink led enabler

            pseudoStereo    : inout std_logic;                                  -- RCA-LEFT(red)=External Audio Card / RCA-RIGHT(white)=Internal Sounds
            extclk3m        : inout std_logic;                                  -- External Clock 3.58MHz   :   0=No, 1=Yes
            ntsc_pal_type   : inout std_logic;                                  -- NTSC/PAL Type            :   0=Forced, 1=Auto
            forced_v_mode   : inout std_logic;                                  -- Forced Video Mode        :   0=60Hz, 1=50Hz

            right_inverse   : inout std_logic;                                  -- Right Inverse Audio      :   0=Off (normal wave), 1=On (inverse wave)
            RatioMode       : inout std_logic_vector(  2 downto 0 );            -- Pixel Ratio 1:1 for LED Display (default is 0) (range 0-7) (60Hz only)
            centerYJK_R25_n : inout std_logic;                                  -- Centering YJK Modes/R25 Mask (0=centered, 1=shifted to the right)
            legacy_sel      : inout std_logic;                                  -- Legacy Output selector   :   0=Assigned to VGA, 1=Assigned to VGA+
            iSlt1_linear    : inout std_logic;                                  -- Internal Slot1 Linear    :   0=Disabled, 1=Enabled
            iSlt2_linear    : inout std_logic;                                  -- Internal Slot2 Linear    :   0=Disabled, 1=Enabled

            btn_scan        : in    std_logic;                                  -- Scanlines button
            vga_scanlines   : inout std_logic_vector(  1 downto 0 );            -- VGA Scanlines None, Light, Medium or Heavy (default is None)
            iPsg2_ena       : inout std_logic;                                  -- Internal PSG2 enabler
            SdrSize         : in    std_logic_vector(  1 downto 0 );            -- SDRAM size ID 0-3
            bios_reload_ack : out   std_logic;                                  -- OCM-BIOS Reloading ack
            Mapper0_req     : inout std_logic;                                  -- Extra-Mapper req         :   Warm Reset is required to complete the request
            Slot0_req       : inout std_logic;                                  -- Slot0 Primary Mode req   :   Warm Reset is required to complete the request

            xmr_ena         : inout std_logic;                                  -- Extended MegaROM Reading :   0=Off (default for compatibility), 1=On
            SdrSizeAux      : in    std_logic_vector(  2 downto 0 );            -- Auxiliary SDRAM size ID 0-7
            OFFSET_Y        : inout std_logic_vector(  6 downto 0 );            -- Vertical Offset ID 16-24

            spMaxSpr        : inout std_logic;                                  -- Sprite Limit             :   0=4/8 (standard), 1=8/8 (enhanced)
            vga_int_field   : inout std_logic;                                  -- VGA Interlace Field      :   0=Single (default), 1=Duplicate
            low_scale_n     : in    std_logic;                                  -- VGA Scanlines variant    :   0=Low-Scale (0%|12%|25%|50%), 1=High-Scale (0%|25%|50%|75%)
            cbios_mode      : inout std_logic;                                  -- C-BIOS Mode              :   0=Off (default), 1=On
            Mapper0_ack     : inout std_logic;                                  -- Current Extra-Mapper state
            Slot0Mode       : inout std_logic;                                  -- Current Slot0 state      :   0=Primary, 1=Expanded
            safe_mode       : inout std_logic;                                  -- Safe Mode                :   0=Off (default), 1=On [Reserved for IPL-ROM]
            portF2_ena      : inout std_logic;                                  -- F2 Device enabler

            ff_dip_req      : in    std_logic_vector(  7 downto 0 );            -- DIP-SW states/reqs
            ff_dip_ack      : inout std_logic_vector(  7 downto 0 );            -- DIP-SW acks

            vram_slot_ids   : inout std_logic_vector(  7 downto 0 );            -- VRAM Slot IDs            :   MSB(4bits)=0-15 for Page 1, LSB(4bits)=0-15 for Page 0
            DefKmap         : inout std_logic;                                  -- Default keyboard layout  :   0=JP, 1=Non-JP (BR, ES, FR, IT, US, ...)

            ff_ldbios_n     : in    std_logic;                                  -- OCM-BIOS loading status
            VDP_ID          : out   std_logic_vector(  4 downto 0 );            -- VDP ID 0 (V9938) or VDP ID 2 (V9958)
            JIS2_ena        : inout std_logic;                                  -- JIS2 enabler             :   0=JIS1 only (BIOS 384 KB), 1=JIS1+JIS2 (BIOS 512 KB)
            portF4_mode     : inout std_logic;                                  -- F4 Device Mode           :   0=Inverted (MSX2+), 1=Normal (MSXtR)

            Scro            : in    std_logic;
            ff_Scro         : in    std_logic;
            Reso            : in    std_logic;
            ff_Reso         : in    std_logic;
            FKeys           : in    std_logic_vector(  7 downto 0 );
            vFKeys          : in    std_logic_vector(  7 downto 0 );
            LevCtrl         : inout std_logic_vector(  2 downto 0 );            -- Volume and high-speed level
            GreenLvEna      : out   std_logic;

            swioRESET_n     : inout std_logic;                                  -- Reset Pulse
            warmRESET       : inout std_logic;                                  -- 0=Cold Reset, 1=Warm Reset
            WarmMSXlogo     : inout std_logic;                                  -- Show MSX logo with Warm Reset
            full_reset_comb : in    std_logic;                                  -- Full Reset combination
            cold_reset_comb : in    std_logic                                   -- Cold Reset combination
        );
    end component;

    component tr_pcm                                                            -- 2019/11/29 t.hara added
        port(
            clk21m          : in    std_logic;
            reset           : in    std_logic;
            req             : in    std_logic;
            ack             : out   std_logic;
            wrt             : in    std_logic;
            adr             : in    std_logic;
            dbi             : out   std_logic_vector(  7 downto 0 );
            dbo             : in    std_logic_vector(  7 downto 0 );
            wave_in         : in    std_logic_vector(  7 downto 0 );
            wave_out        : out   std_logic_vector(  7 downto 0 )
        );
    end component;

    component opl3 is
        generic(
            OPLCLK          : integer := 64000000                               -- opl_clk in Hz
        );
        port(
            clk             : in    std_logic;
            clk_opl         : in    std_logic;
            rst_n           : in    std_logic;
            irq_n           : out   std_logic;

            addr            : in    std_logic_vector(  1 downto 0 );
            dout            : out   std_logic_vector(  7 downto 0 );
            din             : in    std_logic_vector(  7 downto 0 );
            we              : in    std_logic;
            mono            : in    std_logic;

            sample_l        : out   std_logic_vector( 15 downto 0 );
            sample_r        : out   std_logic_vector( 15 downto 0 )
         );
    end component;

    component opl4_wave is
        port(
            clk_bus         : in    std_logic;
            reset_bus       : in    std_logic;
            bus_cs          : in    std_logic;
            bus_a           : in    std_logic_vector(  2 downto 0 );
            bus_di          : in    std_logic_vector(  7 downto 0 );
            bus_rd_n        : in    std_logic;
            bus_wr_n        : in    std_logic;
            bus_do          : out   std_logic_vector(  7 downto 0 );
            bus_status      : out   std_logic_vector(  1 downto 0 );
            bus_wait_n      : out   std_logic;
            mem_req_t       : out   std_logic;
            mem_done_t      : in    std_logic;
            mem_we          : out   std_logic;
            mem_adr         : out   std_logic_vector( 21 downto 0 );
            mem_wdat        : out   std_logic_vector(  7 downto 0 );
            mem_rdat        : in    std_logic_vector( 15 downto 0 );
            pcm_l           : out   std_logic_vector( 15 downto 0 );
            pcm_r           : out   std_logic_vector( 15 downto 0 );
            clk_eng         : in    std_logic
        );
    end component;

    component opl3fpga_msx is
        generic(
            OPLCLK          : integer := 50000000                               -- opl_clk in Hz
        );
        port(
            clk             : in    std_logic;
            clk_opl         : in    std_logic;
            rst_n           : in    std_logic;
            irq_n           : out   std_logic;

            addr            : in    std_logic_vector(  1 downto 0 );
            dout            : out   std_logic_vector(  7 downto 0 );
            din             : in    std_logic_vector(  7 downto 0 );
            we              : in    std_logic;
            mono            : in    std_logic;

            sample_l        : out   std_logic_vector( 15 downto 0 );
            sample_r        : out   std_logic_vector( 15 downto 0 )
         );
    end component;

    -- Added by t.hara, 2021/Aug/6th
    component autofire is
        port(
            clk21m          : in    std_logic;
            reset           : in    std_logic;
            count_en        : in    std_logic;
            af_on_off_led   : in    std_logic;
            af_on_off_toggle: in    std_logic;
            af_increment    : in    std_logic;
            af_decrement    : in    std_logic;
            af_led_sta      : out   std_logic;
            af_mask         : out   std_logic;
            af_speed        : out   std_logic_vector( 3 downto 0 )
        );
    end component;

    -- Switched I/O ports
    signal  swio_req        : std_logic;
    signal  swio_dbi        : std_logic_vector(  7 downto 0 );
    signal  io40_n          : std_logic_vector(  7 downto 0 ) := (others => '1');
    signal  io41_id212_n    : std_logic_vector(  7 downto 0 );                      -- here to reduce LEs
    signal  io42_id212      : std_logic_vector(  7 downto 0 );
    signal  io43_id212      : std_logic_vector(  7 downto 0 ) := (others => '0');
    alias   RstKeyLock      : std_logic is io43_id212(5);                           -- RESET_n lock does not work on Cyclone I machine slot pins without a hardware patch
    signal  io44_id212      : std_logic_vector(  7 downto 0 );
    alias   GreenLeds       : std_logic_vector(  7 downto 0 ) is io44_id212;
    signal  CustomSpeed     : std_logic_vector(  3 downto 0 );
    signal  tMegaSD         : std_logic;
    signal  tPanaRedir      : std_logic;                                            -- here to reduce LEs
    signal  VdpSpeedMode    : std_logic;
    signal  V9938_n         : std_logic;
    signal  Mapper_req      : std_logic;                                            -- here to reduce LEs
    signal  Mapper_ack      : std_logic;
    signal  MegaSD_req      : std_logic;                                            -- here to reduce LEs
    signal  MegaSD_ack      : std_logic;
    signal  io41_id008_n    : std_logic;
    signal  swioKmap        : std_logic;
    signal  CmtScro         : std_logic := '0';
    signal  swioCmt         : std_logic := '0';
    signal  LightsMode      : std_logic;
    signal  Red_sta         : std_logic;
    signal  LastRst_sta     : std_logic;                                            -- here to reduce LEs
    signal  RstReq_sta      : std_logic;                                            -- here to reduce LEs
    signal  Blink_ena       : std_logic;
    signal  pseudoStereo    : std_logic;
    signal  extclk3m        : std_logic;
    signal  right_inverse   : std_logic;
    signal  vram_slot_ids   : std_logic_vector(  7 downto 0 ) := "00010000";
    signal  vram_page       : std_logic_vector(  7 downto 0 );
    signal  DefKmap         : std_logic;                                            -- here to reduce LEs
    signal  ff_dip_req      : std_logic_vector(  7 downto 0 ) := "10000011";        -- overwrites any startup errors with the most common settings
    signal  ff_dip_ack      : std_logic_vector(  7 downto 0 );                      -- here to reduce LEs
    signal  LevCtrl         : std_logic_vector(  2 downto 0 );
    signal  GreenLvEna      : std_logic;
    signal  cold_reset_comb : std_logic;
    signal  full_reset_comb : std_logic;
    signal  comb_reset_n    : std_logic := '1';                                 -- reset by key combination (LCTRL+F12, LCTRL+SHIFT+F12)
    signal  safe_mode       : std_logic := '0';
    signal  portF2_ena      : std_logic := '1';
    signal  low_scale_n     : std_logic := '1';                                 -- no VGA scanline variant here (mist_video)
    signal  spMaxSpr        : std_logic;
    signal  vga_int_field   : std_logic;
    constant SdrSizeAux     : std_logic_vector(  2 downto 0 ) := "111";             -- n/a (default)
    signal  swioRESET_n     : std_logic := '1';
    signal  warmRESET       : std_logic := '0';
    signal  WarmMSXlogo     : std_logic;                                            -- here to reduce LEs
    signal  JIS2_ena        : std_logic;
    signal  portF4_mode     : std_logic;
    signal  bios_reload_ack : std_logic := '0';
    signal  RatioMode       : std_logic_vector(  2 downto 0 ) := (others => '0');
    signal  centerYJK_R25_n : std_logic;
    signal  legacy_sel      : std_logic;
    signal  iSlt1_linear    : std_logic;
    signal  iSlt2_linear    : std_logic;
    signal  Slot0_req       : std_logic;                                            -- here to reduce LEs
    signal  Slot0Mode       : std_logic;
--  signal  vga_scanlines   : std_logic_vector(  1 downto 0 ) := "00";
--  signal  btn_scan        : std_logic := '1';
    signal  Mapper0_req     : std_logic;                                            -- here to reduce LEs
    signal  Mapper0_ack     : std_logic;
    signal  iPsg2_ena       : std_logic;
    signal  cbios_mode      : std_logic;
    signal  xmr_ena         : std_logic;

    -- System timer (S1990)
    signal  systim_req      : std_logic;
    signal  systim_dbi      : std_logic_vector(  7 downto 0 );

    -- Operation mode
    signal  w_key_mode      : std_logic;                                            -- Kana keyboard layout: 1=JIS layout (PSG)
    signal  Kmap            : std_logic;                                            -- '0': Japanese-106    '1': Non-Japanese (English-101, French, ..)
    signal  DisplayMode     : std_logic_vector(  1 downto 0 ) := "10";
    signal  Slot1Mode       : std_logic;
    signal  Slot2Mode       : std_logic_vector(  1 downto 0 );
    signal  iSlt0_1         : std_logic := '0';                                     -- '0': disable Slot0-1 '1': enable Slot0-1
    alias   FullRAM         : std_logic is Mapper_ack;                              -- '0': 2048 kB RAM     '1': 4096 kB RAM
    alias   MmcMode         : std_logic is MegaSD_ack;                              -- '0': disable SD/MMC  '1': enable SD/MMC

    -- Clock, Reset control signals
    --signal  clk21m          : std_logic;
    --signal  memclk          : std_logic;
    signal  cpuclk          : std_logic := '1';
    signal  clkena          : std_logic := '0';
    signal  clkdiv          : std_logic_vector(  1 downto 0 ) := "10";              -- 5.37MHz sync
    signal  ff_clksel       : std_logic;
    signal  ff_clksel5m_n   : std_logic;
    signal  hybridclk_n     : std_logic;
    signal  hybstartcnt     : std_logic_vector(  2 downto 0 );
    signal  hybtoutcnt      : std_logic_vector(  2 downto 0 );
--  signal  reset           : std_logic;
    signal  RstSeq          : std_logic_vector(  4 downto 0 ) := (others => '0');
    signal  FreeCounter     : std_logic_vector( 15 downto 0 ) := (others => '0');
    signal  HardRst_cnt     : std_logic_vector(  3 downto 0 ) := (others => '0');
    signal  LogoRstCnt      : std_logic_vector(  5 downto 0 ) := (others => '0');
    signal  logo_timeout    : std_logic_vector(  1 downto 0 );
    signal  iCpuClk         : std_logic;
    signal  power_on_reset  : std_logic := '0';

    -- MSX cartridge slot control signals
    signal  iSltRst_n       : std_logic := '0';
    signal  xSltRst_n       : std_logic := '1';
    signal  BusDir          : std_logic;
--  signal  BusDir_o        : std_logic;
    signal  iSltRfsh_n      : std_logic;
    signal  iSltMerq_n      : std_logic;
    signal  iSltIorq_n      : std_logic;
    signal  xSltRd_n        : std_logic;
    signal  xSltWr_n        : std_logic;
    signal  iSltAdr         : std_logic_vector( 15 downto 0 );
    signal  iSltDat         : std_logic_vector(  7 downto 0 );
    signal  dlydbi          : std_logic_vector(  7 downto 0 );
    signal  CpuM1_n         : std_logic;
    signal  CpuRfsh_n       : std_logic;
    signal  wait_n_s        : std_logic := '1';

    -- Internal bus signals (common)
    signal  req             : std_logic;
    signal  ack             : std_logic;
    signal  iack            : std_logic;
    signal  mem             : std_logic;
    signal  wrt             : std_logic;
    signal  adr             : std_logic_vector( 15 downto 0 );
    signal  dbi             : std_logic_vector(  7 downto 0 );
    signal  dbo             : std_logic_vector(  7 downto 0 );

    -- Primary, Expansion slot signals
    signal  ExpDbi          : std_logic_vector(  7 downto 0 );
    signal  ExpSlot0        : std_logic_vector(  7 downto 0 );
    signal  ExpSlot3        : std_logic_vector(  7 downto 0 );
    signal  PriSltNum       : std_logic_vector(  1 downto 0 );
    signal  ExpSltNum0      : std_logic_vector(  1 downto 0 );
    signal  ExpSltNum3      : std_logic_vector(  1 downto 0 );

    -- Slot decode signals
    signal  iSltBot         : std_logic;
    signal  iSltMap0        : std_logic := '0';
    signal  iSltMap         : std_logic;
    signal  jSltMem         : std_logic;
    signal  iSltScc1        : std_logic;
    signal  jSltScc1        : std_logic;
    signal  iSltScc2        : std_logic;
    signal  jSltScc2        : std_logic;
    signal  iSltErm         : std_logic;
    signal  iSltLin1        : std_logic;
    signal  iSltLin2        : std_logic;

    -- BIOS-ROM decode signals
    signal  RomReq          : std_logic;
    signal  rom_main        : std_logic;
    signal  rom_opll        : std_logic;
    signal  rom_extd        : std_logic;
    signal  rom_kanj        : std_logic;
    signal  rom_xbas        : std_logic;
    signal  rom_free        : std_logic;

    -- IPL-ROM signals
    signal  RomDbi          : std_logic_vector(  7 downto 0 );
    signal  ff_ldbios_n     : std_logic := '0';
    signal  ff_reload_n     : std_logic := '0';

    -- ESE-RAM signals
    signal  ErmReq          : std_logic;
    signal  ErmRam          : std_logic;
    signal  ErmWrt          : std_logic;
    signal  ErmAdr          : std_logic_vector( 19 downto 0 );

    -- SD/MMC signals
    signal  MmcEna          : std_logic;
    signal  MmcAct          : std_logic;
    signal  MmcDbi          : std_logic_vector(  7 downto 0 );
    signal  MmcEnaLed       : std_logic;
    signal  Blink_s         : std_logic;

-- EPCS/ASMI signals
    signal  EPC_CK          : std_logic;
    signal  EPC_CS          : std_logic;
    signal  EPC_OE          : std_logic;
    signal  EPC_DI          : std_logic;
    signal  EPC_DO          : std_logic;
	 
    -- Mapper RAM signals
    signal  MapReq          : std_logic;
    signal  MapDbi          : std_logic_vector(  7 downto 0 );
    signal  MapRam          : std_logic;
    signal  MapWrt          : std_logic;
    signal  MapAdr          : std_logic_vector( 21 downto 0 );

    -- PPI(8255) signals
    signal  PpiReq          : std_logic;
    signal  PpiDbi          : std_logic_vector(  7 downto 0 );
    signal  PpiPortA        : std_logic_vector(  7 downto 0 );
    signal  PpiPortB        : std_logic_vector(  7 downto 0 );
    signal  PpiPortC        : std_logic_vector(  7 downto 0 );

    signal  w_page_dec      : std_logic_vector(  3 downto 0 );
    signal  w_prislt_dec    : std_logic_vector(  3 downto 0 );
    signal  w_expslt0_dec   : std_logic_vector(  3 downto 0 );
    signal  w_expslt3_dec   : std_logic_vector(  3 downto 0 );

    -- PS/2 signals
    signal  Paus            : std_logic;
    signal  Scro            : std_logic;
    signal  Reso            : std_logic;
    signal  Reso_v          : std_logic;
    signal  Kana            : std_logic;
    signal  Caps            : std_logic;
    signal  Fkeys           : std_logic_vector(  7 downto 0 );

    -- CMT signals
    signal  CmtIn           : std_logic;
    alias   CmtOut          : std_logic is PpiPortC(5);
	 
	 -- Mix signals
	 signal audioPcm              :std_logic_vector(  16 downto 0 );
	 signal audioFm               :std_logic_vector(   15 downto 0 );

    -- 1bit sound port signal
    alias   KeyClick        : std_logic is PpiPortC(7);

    -- RTC signals
    signal  RtcReq          : std_logic;
    signal  RtcDbi          : std_logic_vector(  7 downto 0 );
    signal  rtcclk          : std_logic := '1';
    signal  rtcena          : std_logic := '0';
    signal  rtcdiv3         : std_logic_vector(  1 downto 0 ) := "10";

    -- Kanji signals
    signal  KanReq          : std_logic;
    signal  KanDbi          : std_logic_vector(  7 downto 0 );
    signal  KanRom          : std_logic;
    signal  KanAdr          : std_logic_vector( 17 downto 0 );

    -- VDP signals
    signal  VdpReq          : std_logic;
    signal  VdpDbi          : std_logic_vector(  7 downto 0 );
    signal  VideoSC         : std_logic;
    signal  VideoDLClk      : std_logic;
    signal  VideoDHClk      : std_logic;
    signal  WeVdp_n         : std_logic;
    signal  VdpAdr          : std_logic_vector( 16 downto 0 );
    signal  VrmDbo          : std_logic_vector(  7 downto 0 );
    signal  VrmDbi          : std_logic_vector( 15 downto 0 );
    signal  pVdpInt_n       : std_logic;
    signal  ntsc_pal_type   : std_logic;
    signal  forced_v_mode   : std_logic;
    signal  legacy_vga      : std_logic;
    signal  VDP_ID          : std_logic_vector(  4 downto 0 );
    signal  OFFSET_Y        : std_logic_vector(  6 downto 0 );

    -- Video signals
    signal  VideoR          : std_logic_vector( 5 downto 0 );                       -- RGB Red
    signal  VideoG          : std_logic_vector( 5 downto 0 );                       -- RGB Green
    signal  VideoB          : std_logic_vector( 5 downto 0 );                       -- RGB Blue
    signal  VideoHS_n       : std_logic;                                            -- Horizontal Sync
    signal  VideoVS_n       : std_logic;                                            -- Vertical Sync
    signal  VideoCS_n       : std_logic;                                            -- Composite Sync
    signal  videoY          : std_logic_vector(  5 downto 0 );                      -- S-Video Y
    signal  videoC          : std_logic_vector(  5 downto 0 );                      -- S-Video C
    signal  videoV          : std_logic_vector(  5 downto 0 );                      -- Composite Video

    -- PSG signals
    signal  PsgReq          : std_logic;
    signal  PsgDbi          : std_logic_vector(  7 downto 0 );
    signal  PsgAmp          : std_logic_vector( 14 downto 0 );

    -- PSG2 signals
    signal  Psg2Req         : std_logic;
    signal  Psg2Dbi         : std_logic_vector(  7 downto 0 );
    signal  Psg2Amp         : std_logic_vector( 14 downto 0 );

    -- SCC signals
    signal  Scc1Req         : std_logic;
    signal  Scc1Ack         : std_logic;
    signal  Scc1Dbi         : std_logic_vector(  7 downto 0 );
    signal  Scc1Ram         : std_logic;
    signal  Scc1Wrt         : std_logic;
    signal  Scc1Adr         : std_logic_vector( 21 downto 0 );
    signal  Scc1AmpL        : std_logic_vector( 14 downto 0 );

    signal  Scc2Req         : std_logic;
    signal  Scc2Ack         : std_logic;
    signal  Scc2Dbi         : std_logic_vector(  7 downto 0 );
    signal  Scc2Ram         : std_logic;
    signal  Scc2Wrt         : std_logic;
    signal  Scc2Adr         : std_logic_vector( 21 downto 0 );
    signal  Scc2AmpL        : std_logic_vector( 14 downto 0 );

    signal  Scc1Type        : std_logic_vector(  1 downto 0 );

    -- OPLL signals
    signal  OpllReq         : std_logic;
    signal  OpllAck         : std_logic;
    signal  OpllAmp         : std_logic_vector(  9 downto 0 );
	 signal  Opllwav         : std_logic_vector (  15 downto 0 );
    signal  OpllEnaWait     : std_logic;

    -- Sound signals
    constant DAC_msbi       : integer := 13;
    signal  DACin           : std_logic_vector( DAC_msbi downto  0 );
    signal  DACout          : std_logic;

    signal  OpllVol         : std_logic_vector(  2 downto 0 ) := "100";
    signal  SccVol          : std_logic_vector(  2 downto 0 ) := "100";
    signal  PsgVol          : std_logic_vector(  2 downto 0 ) := "100";
    signal  MstrVol         : std_logic_vector(  2 downto 0 ) := "000";

--  signal  pSltSndL        : std_logic_vector(  5 downto 0 );
--  signal  pSltSndR        : std_logic_vector(  5 downto 0 );
--  signal  pSltSound       : std_logic_vector(  5 downto 0 );

    -- External memory signals
    signal  RamReq          : std_logic;
    signal  RamAck          : std_logic;

    -- OPL4 wave memory in the SDRAM (cpu slots the cpu does not use)
    signal  wave_req_t      : std_logic := '0';                                     -- request: toggles
    signal  wave_done_t     : std_logic := '0';                                     -- done when equal to wave_req_t
    signal  wave_we         : std_logic := '0';
    signal  wave_adr        : std_logic_vector( 21 downto 0 ) := (others => '0');
    signal  wave_wdat       : std_logic_vector(  7 downto 0 ) := (others => '0');
    signal  wave_rdat       : std_logic_vector( 15 downto 0 ) := (others => '1');
    signal  wave_sdr_adr    : std_logic_vector( 24 downto 0 );
    signal  wave_pend       : std_logic;
    signal  wave_slot       : std_logic := '0';                                     -- this cpu slot is for the wave memory
    signal  sdr_wr_a0       : std_logic := '0';                                     -- byte of the cpu / wave write (taken at "001")
    signal  CpuAdr_r        : std_logic_vector( 24 downto 0 ) := (others => '0');   -- CpuAdr registered in memclk (ZEMMIX-dl0)
    signal  wave_wait       : std_logic_vector(  1 downto 0 ) := "00";               -- cpu slots waited (R800)
    -- wave memory client before the ZEMMIX.ROM loader (7Eh/7Fh test, later the PCM engine)
    signal  wt_req_t        : std_logic := '0';
    signal  wt_done_t       : std_logic;
    signal  wt_we           : std_logic := '0';
    signal  wt_adr          : std_logic_vector( 21 downto 0 ) := (others => '0');
    signal  wt_wdat         : std_logic_vector(  7 downto 0 ) := (others => '0');
    signal  wt_rdat         : std_logic_vector( 15 downto 0 );
    signal  romload_rcv     : std_logic_vector( 23 downto 0 );
    signal  romload_lost    : std_logic_vector( 23 downto 0 );
    -- OPL4 wave part (MoonSound)
    signal  opl4_cs         : std_logic;
    signal  opl4_a          : std_logic_vector(  2 downto 0 );
    signal  opl4_do         : std_logic_vector(  7 downto 0 ) := (others => '1');
    signal  opl4_status     : std_logic_vector(  1 downto 0 ) := "00";
    signal  opl4_wait_n     : std_logic := '1';
    signal  RamDbi          : std_logic_vector(  7 downto 0 );
    signal  CpuAdr          : std_logic_vector( 24 downto 0 );

    -- SDRAM control signals
    signal  SdrSta          : std_logic_vector(  2 downto 0 );
    signal  SdrCmd          : std_logic_vector(  3 downto 0 );
    signal  SdrBa           : std_logic_vector(  1 downto 0 ) := "00";
    signal  SdrUdq          : std_logic;
    signal  SdrLdq          : std_logic;
    signal  SdrAdr          : std_logic_vector( 12 downto 0 ) := (others => '0');
    signal  SdrDat          : std_logic_vector( 15 downto 0 );
    signal  SdrSize         : std_logic_vector(  1 downto 0 ) := "11";

    constant SdrCmd_de      : std_logic_vector(  3 downto 0 ) := "1111";            -- deselect
    constant SdrCmd_pr      : std_logic_vector(  3 downto 0 ) := "0010";            -- precharge all
    constant SdrCmd_re      : std_logic_vector(  3 downto 0 ) := "0001";            -- refresh
    constant SdrCmd_ms      : std_logic_vector(  3 downto 0 ) := "0000";            -- mode register set

    constant SdrCmd_xx      : std_logic_vector(  3 downto 0 ) := "0111";            -- no operation
    constant SdrCmd_ac      : std_logic_vector(  3 downto 0 ) := "0011";            -- activate
    constant SdrCmd_rd      : std_logic_vector(  3 downto 0 ) := "0101";            -- read
    constant SdrCmd_wr      : std_logic_vector(  3 downto 0 ) := "0100";            -- write

    -- Clock divider
    signal  clkdiv3         : std_logic_vector(  1 downto 0 ) := "10";
    signal  ff_mem_seq      : std_logic_vector(  1 downto 0 );

    -- Operation mode
    signal  ff_clk21m_cnt   : std_logic_vector( 20 downto 0 ) := (others => '0');   -- free run counter
    signal  GreenLv         : std_logic_vector(  6 downto 0 );                      -- green level
    signal  GreenLv_cnt     : std_logic_vector(  3 downto 0 );                      -- green level counter

    -- w_10hz with LFSR counter
    signal  w_10hz_lfsr     : std_logic_vector( 21 downto 0 ) := (others => '0');
    signal  w_10hz_d0       : std_logic;
    signal  w_10hz          : std_logic := '1';

    -- Sound output, toggle keys
    signal  vFKeys          : std_logic_vector(  7 downto 0 );
    signal  ff_Scro         : std_logic;
    signal  ff_Reso         : std_logic;

    -- DRAM arbiter
    signal  w_wrt_req       : std_logic;

    -- SDRAM controller
    signal  ff_sdr_seq      : std_logic_vector(  2 downto 0 );

    -- Port F2 device (ESP8266 BIOS)
    signal  portF2_req      : std_logic;
    signal  portF2          : std_logic_vector(  7 downto 0 ) := (others => '1');

    -- Port F4 device
    signal  portF4_req      : std_logic;
    signal  portF4_bit7     : std_logic;                                            -- 1=hard reset, 0=soft reset
    signal  portF4_bit5     : std_logic;                                            -- MSXtR: set by the Z80 boot, read by the R800 at reset

    -- S1990 registers (I/O $E4-$E5)
    signal  s1990_req       : std_logic;
    signal  s1990_sel       : std_logic_vector(  7 downto 0 );                      -- E4h: register select
    signal  s1990_cpu       : std_logic_vector(  6 downto 5 );                      -- R#6: bit6 1=ROM 0=DRAM, bit5 1=Z80 0=R800
    signal  s1990_dbi       : std_logic_vector(  7 downto 0 );
    signal  s1990_r800      : std_logic;                                            -- '1' => R800 selected (MSXtR only)

    -- R800: a second CPU (T80s on clk21m) on the internal bus, the T80a is the Z80
    signal  r8_cen          : std_logic;
    signal  r8_wait_n       : std_logic;
    signal  r8_merq_n       : std_logic;
    signal  r8_iorq_n       : std_logic;
    signal  r8_rd_n         : std_logic;
    signal  r8_wr_n         : std_logic;
    signal  r8_m1_n         : std_logic;
    signal  r8_rfsh_n       : std_logic;
    signal  r8_adr          : std_logic_vector( 15 downto 0 );
    signal  r8_dbo          : std_logic_vector(  7 downto 0 );
    signal  r8_active       : std_logic;                                            -- the R800 is the running CPU
    signal  r8_stall        : std_logic;                                            -- R800 ahead of a real R800
    signal  r8_iohold       : std_logic;                                            -- R800 I/O before its real time
    signal  r8_started      : std_logic;                                            -- the R800 runs from reset at its first selection
    signal  r8_owner        : std_logic;                                            -- the R800 owns the bus (the Z80 has released it)
    signal  r8_parked       : std_logic;                                            -- the R800 is stopped on the T1 of an M1
    signal  z80_busrq_n     : std_logic;
    signal  z80_busak_n     : std_logic;
    signal  r8_ext          : std_logic;                                            -- R800 access to an external slot / I/O port
    signal  r8_ext_cnt      : std_logic_vector(  2 downto 0 );
    signal  c_merq_n        : std_logic;                                            -- CPU bus seen by the internal bus registers
    signal  c_iorq_n        : std_logic;
    signal  c_rd_n          : std_logic;
    signal  c_wr_n          : std_logic;
    signal  c_rfsh_n        : std_logic;
    signal  c_adr           : std_logic_vector( 15 downto 0 );
    signal  c_dat           : std_logic_vector(  7 downto 0 );
    signal  rc_rd           : std_logic;                                            -- R800 bus cycle tracking
    signal  rc_wr           : std_logic;
    signal  rc_io           : std_logic;
    signal  rc_req          : std_logic;
    signal  rc_wram         : std_logic;
    signal  rc_cnt          : std_logic_vector(  2 downto 0 );
    signal  rc_done         : std_logic;
    signal  rc_mmcbusy      : std_logic;
    signal  rc_vdpbusy      : std_logic;
    signal  vdp_busy        : std_logic;
    signal  r8_xwait_d      : std_logic;                                            -- external waits delayed by one clock (dlydbi)
    type    r8_cache_t      is array( 0 to 16383 ) of std_logic_vector( 19 downto 0 );    -- valid & tag(CpuAdr 24..14) & data
    signal  r8_cache        : r8_cache_t;                                           -- R800 read cache of the SDRAM
    signal  rc_q            : std_logic_vector( 19 downto 0 );
    signal  rc_cacheable    : std_logic;
    signal  r8_hit          : std_logic;
    signal  r8_dbi          : std_logic_vector(  7 downto 0 );
    signal  rc_we           : std_logic;
    signal  rc_wa           : std_logic_vector( 13 downto 0 );
    signal  rc_wd           : std_logic_vector( 19 downto 0 );
    signal  rc_clr          : std_logic_vector( 13 downto 0 ) := (others => '0');
    signal  sdr_slot_adr    : std_logic_vector( 24 downto 0 );                      -- SDRAM CPU slot tracking
    signal  sdr_slot_ok     : std_logic := '0';
    signal  sdr_rd_adr      : std_logic_vector( 24 downto 0 );
    signal  sdr_rd_ok       : std_logic := '0';
    signal  sdr_wr_adr      : std_logic_vector( 24 downto 0 );
    signal  sdr_wr_dat      : std_logic_vector(  7 downto 0 );
    signal  sdr_wr_ok       : std_logic := '0';

    -- turboR PCM device
    signal  tr_pcm_req      : std_logic;
    signal  tr_pcm_dbi      : std_logic_vector(  7 downto 0 );
    signal  tr_pcm_wave_in  : std_logic_vector(  7 downto 0 );
    signal  tr_pcm_wave_out : std_logic_vector(  7 downto 0 );

    -- ESP signals
    signal  esp_dout_s      : std_logic_vector(  7 downto 0 ) := (others => '1');
    signal  esp_wait_s      : std_logic := '1';
    signal  vdp_wait_n_s    : std_logic;
--  signal  esp_tx_i        : std_logic;
--  signal  esp_rx_o        : std_logic;

    -- OPL3 signals
    signal  opl3_dout_s     : std_logic_vector(  7 downto 0 ) := (others => '1');
    --signal  opl3_sound_s    : std_logic_vector( 15 downto 0 ) := (others => '0');
    signal  opl3_ce         : std_logic := '0';
    signal  opl3_enabled    : std_logic := '1';
    signal  opl3_Int_n      : std_logic := '1';

    -- MIDI signals
--  signal  midi_o          : std_logic;
--  signal  midi_active_o   : std_logic;
    signal  midi_dout_s     : std_logic_vector(  7 downto 0 ) := (others => '1');

    -- Autofire,  Added by t.hara, 2021/Aug/6th
    signal  af_on_off_led   : std_logic;
    signal  af_on_off_toggle: std_logic;
    signal  af_increment    : std_logic;
    signal  af_decrement    : std_logic;
    signal  af_led_sta      : std_logic;
    signal  af_mask         : std_logic;
    signal  w_pJoyA_in      : std_logic_vector(  5 downto 0 );
    signal  w_pJoyA_in_m    : std_logic_vector(  5 downto 0 );    -- 2022/Dec/14th Added by t.hara for ESEPS2MOUSE
    signal  w_pJoyA_out_m   : std_logic_vector(  1 downto 0 );    -- 2022/Dec/14th Added by t.hara for ESEPS2MOUSE
    signal  w_pStrA_m       : std_logic;                          -- 2022/Dec/14th Added by t.hara for ESEPS2MOUSE
    signal  w_pJoyB_in      : std_logic_vector(  5 downto 0 );
    signal  w_PpiPortB      : std_logic_vector(  7 downto 0 );

    signal  w_pLed          : std_logic_vector(  7 downto 0 );    -- 0=Off, 1=On (green)         -- 2022/Dec./18th  Added by t.hara for ESEPS2MOUSE
    signal  w_pLedPwr       : std_logic;

begin

    -- Internal OPL3 On/Off toggle
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            -- OPL3 can be managed by the SCRLK key or by the CmtScro signal
            if( use_opl3_g )then
                opl3_enabled <= CmtScro;
            else
                opl3_enabled <= '0';
            end if;
        end if;
    end process;

    clk21m_out <= clk21m;
    vga_status <= DisplayMode(1);

    ----------------------------------------------------------------
    -- Clock generator (21.48MHz > 3.58MHz)
    -- pCpuClk should be independent from reset
    ----------------------------------------------------------------

    -- Clock enabler : 3.58MHz = 21.48MHz / 6
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            clkena <= '0';
        elsif( clk21m'event and clk21m = '1' )then
            if( clkdiv3 = "00" )then
                clkena <= cpuclk;
            else
                clkena <= '0';
            end if;
        end if;
    end process;

    -- CPUCLK : 3.58MHz = 21.48MHz / 6
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            cpuclk <= '1';
        elsif( clk21m'event and clk21m = '1' )then
            if( clkdiv3 = "10" )then
                cpuclk <= not cpuclk;
            else
                -- hold
            end if;
        end if;
    end process;

    -- CPUCLK Prescaler : 21.48MHz / 6
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            clkdiv3 <= "10";
        elsif( clk21m'event and clk21m = '1' )then
            if( clkdiv3 = "00" )then
                clkdiv3 <= "10";
            else
                clkdiv3 <= clkdiv3 - 1;
            end if;
        end if;
    end process;

    -- Turbo Clocks Prescaler : 21.48MHz / 4
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            clkdiv <= "10";                                                             -- 5.37MHz sync
        elsif( clk21m'event and clk21m = '1' )then
            clkdiv <= clkdiv - 1;
        end if;
    end process;

    -- hybrid clock start counter
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            hybstartcnt <= (others => '0');
        elsif( clk21m'event and clk21m = '1' )then
            if( ff_clk21m_cnt( 16 downto 0 ) = "00000000000000000" )then
                if( mmcena = '0' )then
                    hybstartcnt <= "111";                                               -- begin after 48ms
                elsif( hybstartcnt /= "000" )then
                    hybstartcnt <= hybstartcnt - 1;
                end if;
            end if;
        end if;
    end process;

    -- hybrid clock timeout counter
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            hybtoutcnt <= (others => '0');
        elsif( clk21m'event and clk21m = '1' )then
            if( hybstartcnt = "000" or hybtoutcnt /= "000" )then
                if( mmcena = '1' )then
                    hybtoutcnt <= "111";                                                -- timeout after 96ms
                elsif( ff_clk21m_cnt( 17 downto 0 ) = "000000000000000000" )then
                    hybtoutcnt <= hybtoutcnt - 1;
                end if;
            end if;
        end if;
    end process;

    -- hybrid clock enabler
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            hybridclk_n <= '1';
        elsif( clk21m'event and clk21m = '1' )then
            if( hybtoutcnt = "000" )then
                hybridclk_n <= '1';
            else
                hybridclk_n <= not tMegaSD;
            end if;
        end if;
    end process;

    -- logo speed limiter
    process( reset, clk21m )
        constant lsl_mode : std_logic := '1';                                           -- lsl_mode = '0' : logo only
    begin                                                                               -- lsl_mode = '1' : logo + beep sound (default)
        if( reset = '1' )then
            logo_timeout <= "00";
        elsif( clk21m'event and clk21m = '1' )then                                      -- times change depending on the mappers installed, and
            if( ff_ldbios_n = '0' )then                                                 -- the current configuration has only one external mapper
                if( LastRst_sta = portF4_mode )then
                    if( lsl_mode = '0' )then
                        LogoRstCnt <= "100110";                                         -- 3800ms  <= '0' : OCM-BIOS begins
                    else
                        LogoRstCnt <= "110001";                                         -- 4900ms  <= '1' : OCM-BIOS begins
                    end if;
                end if;
            elsif( w_10hz = '1' and LogoRstCnt /= "000000" )then
                LogoRstCnt <= LogoRstCnt - 1;
                if( (LogoRstCnt = "011000" and lsl_mode = '0') or                       -- 2400ms  <= '0' : MSX2+ animation starts here w/o external mapper
                    (LogoRstCnt = "100011" and lsl_mode = '1') )then                    -- 3500ms  <= '1' : MSX2+ animation starts here w/o external mapper
                    logo_timeout <= "01";
                end if;
            elsif( LogoRstCnt = "000000" )then                                          -- 0ms     <= '0' : MSX2+ logo ends
                logo_timeout <= "10";                                                   --         or '1' : BEEP sound ends
            end if;
        end if;
    end process;

    -- virtual DIP-SW assignment (1/2)
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '0' )then
            if( cpuclk = '0' and clkdiv = "00" and wait_n_s = '0' )then
                if( logo_timeout = "00" )then                                           -- ultra-fast boot
                    ff_clksel5m_n   <=  '1';
                    ff_clksel       <=  '1';
                elsif( logo_timeout = "10" )then
                    if( io42_id212(0) = '0' )then
                        ff_clksel5m_n   <=  io41_id008_n    and hybridclk_n;
                        ff_clksel       <=  io42_id212(0)   and hybridclk_n;
                    else
                        ff_clksel5m_n   <=  io41_id008_n;
                        ff_clksel       <=  io42_id212(0);
                    end if;
                else
                    ff_clksel5m_n   <=  '1';
                    ff_clksel       <=  '0';
                end if;
            end if;
        end if;
    end process;

    -- virtual DIP-SW assignment (2/2)
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            Kmap            <=  swioKmap;                                               -- keyboard layout assignment
            CmtScro         <=  swioCmt;
            DisplayMode(1)  <=  io42_id212(1);
            DisplayMode(0)  <=  io42_id212(2);
            Slot1Mode       <=  io42_id212(3);
            Slot2Mode(1)    <=  io42_id212(4);
            Slot2Mode(0)    <=  io42_id212(5);
        end if;
    end process;

    -- cpu clock assignment
    iCpuClk <=  '1'         when( power_on_reset = '0' )else
                rtcclk      when( reset = '1' )else                                     --  3.58MHz
                clkdiv(0)   when( ff_clksel = '1' )else                                 -- 10.74MHz
                clkdiv(1)   when( ff_clksel5m_n = '0' )else                             --  5.37MHz
                cpuclk;                                                                 --  3.58MHz

    -- clock assignment of external slots
    pCpuClk <=  '1'         when( power_on_reset = '0' )else
                rtcclk      when( reset = '1' )else                                     --  3.58MHz
                clkdiv(0)   when( ff_clksel = '1' and extclk3m = '0' )else              -- 10.74MHz
                clkdiv(1)   when( ff_clksel5m_n = '0' and extclk3m = '0' )else          --  5.37MHz
                cpuclk;                                                                 --  3.58MHz

    ----------------------------------------------------------------
    -- Real Time Clock enabler
    ----------------------------------------------------------------

    -- RTC enabler : 3.58MHz = 21.48MHz / 6
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            if( rtcdiv3 = "00" )then
                rtcena <= rtcclk;
            else
                rtcena <= '0';
            end if;
        end if;
    end process;

    -- RTCCLK : 3.58MHz = 21.48MHz / 6
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            if( rtcdiv3 = "10" )then
                rtcclk <= not rtcclk;
            else
                -- hold
            end if;
        end if;
    end process;

    -- RTC Prescaler : 21.48MHz / 6
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            if( rtcdiv3 = "00" )then
                rtcdiv3 <= "10";
            else
                rtcdiv3 <= rtcdiv3 - 1;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Reset control
    -- "RstSeq" should be cleared when power-on reset
    ----------------------------------------------------------------

    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            -- 00 > 01 > 11 > 10
            ff_mem_seq <= ff_mem_seq(0) & (not ff_mem_seq(1));
        end if;
    end process;

    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( ff_mem_seq = "00" )then
                FreeCounter <= FreeCounter + 1;
            end if;
        end if;
    end process;

    -- hard reset timer
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            if( xSltRst_n = '0' )then
                -- hard reset is held down
                iSltRst_n <= '0';                                                       -- reset = '1'
                if( HardRst_cnt = "0000" )then
                    if( ff_reload_n = '0' )then
                        HardRst_cnt <= "0010";                                          -- 100ms to timeout
                    else
                        HardRst_cnt <= "1001";                                          -- short click < 800ms (M51953BFP is not there)
                    end if;
                elsif( w_10hz = '1' and HardRst_cnt /= "0001" )then                     -- timeout
                    HardRst_cnt <= HardRst_cnt - 1;
                end if;
            else
                -- hard reset has been released
                HardRst_cnt <= "0000";
                iSltRst_n <= '1';                                                       -- reset = '0'
            end if;
        end if;
    end process;

    -- RstSeq count
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( HardRst_cnt = "0010" or bios_reload_ack = '1' )then                     -- long click > 800ms
                RstSeq <= "00000";                                                      -- RstSeq is required
                ff_reload_n <= '0';                                                     -- OCM-BIOS is partial
            elsif( ff_mem_seq = "00" and FreeCounter = X"FFFF" and RstSeq /= "11111" )then
                RstSeq <= RstSeq + 1;                                                   -- 3ms (= 65536 / 21.48MHz)
            elsif( ff_ldbios_n = '1' )then
                ff_reload_n <= '1';                                                     -- OCM-BIOS is complete
            end if;
        end if;
    end process;

    -- hard reset button
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            xSltRst_n <= pSltRst_n;                                                     -- hard reset (OSD / image mount): no port $43 reset lock (RstKeyLock is not initialized by switched_io_ports)
        end if;
    end process;

    -- reset assignment
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( RstSeq = "11111" )then
                -- RstSeq has finished
                reset <= not (iSltRst_n and swioRESET_n and comb_reset_n);              -- global reset
            else
                -- RstSeq is in progress
                reset <= '1';                                                           -- SDRAM integrity protection
            end if;
        end if;
    end process;

    -- power on reset
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( ff_clk21m_cnt( 19 downto 15 ) = "11001" )then                           -- about 38ms
                power_on_reset <= '1';
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Operation mode
    ----------------------------------------------------------------

    -- free run counter
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            ff_clk21m_cnt <= ff_clk21m_cnt + 1;
        end if;
    end process;

    -- w_10hz with LFSR counter = 100ms
    -- http://outputlogic.com/?page_id=275
    w_10hz_d0 <= w_10hz_lfsr(21) xnor w_10hz_lfsr(20);

    process( w_10hz_lfsr )
    begin
        -- for XTAL 21.47727MHz
--      if( w_10hz_lfsr = "1000111100000111101010" )then    -- x"23C1EA" / LFSR count = 2147728 clock ticks
        -- for XTAL 50.00000MHz
        if( w_10hz_lfsr = "0011101100100110000010" )then    -- x"0EC982" / LFSR count = 2148438 clock ticks
            w_10hz <= '1';
        else
            w_10hz <= '0';
        end if;
    end process;

    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            if( w_10hz = '1' )then
                w_10hz_lfsr <= (others => '0');
            else
                w_10hz_lfsr <= (w_10hz_lfsr( 20 downto 0 ) & w_10hz_d0);
            end if;
        end if;
    end process;

    -- green level counter
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            GreenLv_cnt <= "0000";
        elsif( clk21m'event and clk21m = '1' )then
            if( GreenLvEna = '1' )then
                GreenLv_cnt <= "1111";                      -- 1600ms
            elsif( w_10hz = '1' and GreenLv_cnt /= "0000" )then
                GreenLv_cnt <= GreenLv_cnt - 1;
            end if;
        end if;
    end process;

    -- green level assignment
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            GreenLv <= (others => '0');
        elsif( clk21m'event and clk21m = '1' )then
            case LevCtrl is
                when "111"  =>  GreenLv <= "1111111";
                when "110"  =>  GreenLv <= "0111111";
                when "101"  =>  GreenLv <= "0011111";
                when "100"  =>  GreenLv <= "0001111";
                when "011"  =>  GreenLv <= "0000111";
                when "010"  =>  GreenLv <= "0000011";
                when "001"  =>  GreenLv <= "0000001";
                when others =>  GreenLv <= "0000000";
            end case;
        end if;
    end process;

    -- blink assignment (generic)
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            Blink_s <= ff_clk21m_cnt(20) or (not ff_clk21m_cnt(19));
            if( Blink_ena = '1' and MmcEna = '1' )then
                MmcEnaLed <= Blink_s;
            elsif( Blink_ena = '0' and LightsMode = '0' )then
                MmcEnaLed <= MmcMode;
            elsif( LightsMode = '1' )then
                MmcEnaLed <= GreenLeds(7);
            else
                MmcEnaLed <= '0';
            end if;
        end if;
    end process;

    -- power LED assignment (generic)
    w_pLedPwr <=
                ('1'                                 )      -- LED light test on reset
                                                            when( iSltRst_n = '0' or power_on_reset = '0' )else
                ('1'                                 )      -- On
                                                            when( Paus = '0' and Red_sta = '1' and GreenLv_cnt = "0000" and af_led_sta = '0' )else
                ('0'                                 );     -- Off
    pLedPwr <= w_pLedPwr;

    -- LEDs assignment (specific for SM-X and SX-2)
    w_pLed  <=  (others     => FreeCounter(1)        )      -- LED lights test on reset
                                                            when( iSltRst_n = '0' or power_on_reset = '0' )else

                (others     => '0'                   )      -- Blackout Mode
                                                            when( Paus = '1' )else

                (GreenLeds(0)                        ) &    -- Lights Mode + Blink
                (GreenLeds(1)                        ) &
                (GreenLeds(2)                        ) &
                (GreenLeds(3)                        ) &
                (GreenLeds(4)                        ) &
                (GreenLeds(5)                        ) &
                (GreenLeds(6)                        ) &
                (MmcEnaLed                           )      when( LightsMode = '1' )else

                (GreenLv(0)                          ) &    -- Volume + Blink
                (GreenLv(1)                          ) &
                (GreenLv(2)                          ) &
                (GreenLv(3)                          ) &
                (GreenLv(4)                          ) &
                (GreenLv(5)                          ) &
                (GreenLv(6)                          ) &
                (MmcEnaLed                           )      when( GreenLv_cnt /= "0000" and af_led_sta = '0' )else

                (GreenLv(0)                          ) &    -- Volume + Autofire
                (GreenLv(1)                          ) &
                (GreenLv(2)                          ) &
                (GreenLv(3)                          ) &
                (GreenLv(4)                          ) &
                (GreenLv(5)                          ) &
                (GreenLv(6)                          ) &
                (not af_mask                         )      when( GreenLv_cnt /= "0000" )else

                "0000000" & not af_mask                     -- Autofire by t.hara, 2021/Aug/7th
                                                            when( af_led_sta = '1' )else

                (io42_id212(0)                       ) &    -- Virtual DIP-SW (Auto) + Blink
                (DisplayMode(1)                      ) &
                (DisplayMode(0)                      ) &
                (Slot1Mode                           ) &
                (Slot2Mode(1)                        ) &
                (Slot2Mode(0)                        ) &
                (FullRAM                             ) &
                (MmcEnaLed                           );
    pLed  <= w_pLed;

    -- DIP-SW latch
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            ff_dip_req <= not pDip;                         -- convert negative logic to positive logic, and latch
        end if;
    end process;

    -- Kana keyboard layout: 1=JIS layout (PSG)
    w_key_mode  <=  '1';

    ----------------------------------------------------------------
    -- MSX cartridge slot control
    ----------------------------------------------------------------
    pSltCs1_n   <=  pSltRd_n when( pSltAdr(15 downto 14) = "01" )else '1';
    pSltCs2_n   <=  pSltRd_n when( pSltAdr(15 downto 14) = "10" )else '1';
    pSltCs12_n  <=  pSltRd_n when( pSltAdr(15 downto 14) = "01" )else
                    pSltRd_n when( pSltAdr(15 downto 14) = "10" )else '1';
    pSltM1_n    <=  r8_m1_n     when( r8_owner = '1' )else CpuM1_n;
    pSltRfsh_n  <=  r8_rfsh_n   when( r8_owner = '1' )else CpuRfsh_n;

    -- the R800 drives the slot bus while it owns it (the Z80 has released it)
    pSltAdr     <=  r8_adr      when( r8_owner = '1' )else (others => 'Z');
    pSltMerq_n  <=  r8_merq_n   when( r8_owner = '1' )else 'Z';
    pSltIorq_n  <=  r8_iorq_n   when( r8_owner = '1' )else 'Z';
    pSltRd_n    <=  r8_rd_n     when( r8_owner = '1' )else 'Z';
    pSltWr_n    <=  r8_wr_n     when( r8_owner = '1' )else 'Z';

    pSltInt_n   <=  '0' when( pVdpInt_n = '0' ) or
                            ( opl3_Int_n = '0' and opl3_enabled = '1' )else
                    'Z';

    pSltSltsl_n <=  '1' when( Scc1Type /= "00" )else
                    '0' when( pSltMerq_n = '0' and c_rfsh_n = '1' and PriSltNum = "01" )else
                    '1';

    pSltSlts2_n <=  '1' when( Slot2Mode /= "00" )else
                    '0' when( pSltMerq_n = '0' and c_rfsh_n = '1' and PriSltNum = "10" )else
                    '1';

    pSltBdir_n  <=  'Z';

    BusDir_o    <=  '0' when( pSltRd_n = '1' )else
                    '1' when( pSltIorq_n = '0' and BusDir = '1' )else
                    '1' when( pSltMerq_n = '0' and PriSltNum = "00" )else
                    '1' when( pSltMerq_n = '0' and PriSltNum = "11" )else
                    '1' when( pSltMerq_n = '0' and PriSltNum = "01" and Scc1Type /= "00" )else
                    '1' when( pSltMerq_n = '0' and PriSltNum = "10" and Slot2Mode /= "00" )else
                    '0';

    pSltDat     <=  dbi     when( BusDir_o = '1' )else
                    r8_dbo  when( r8_owner = '1' and r8_wr_n = '0' )else
                    (others => 'Z');

    pSltRsv5    <=  'Z';
    pSltRsv16   <=  'Z';

    pSltSw1     <=  'Z';
    pSltSw2     <=  'Z';

    pSltWait_n  <=  'Z';

    ----------------------------------------------------------------
    -- Z80 CPU wait control
    ----------------------------------------------------------------
    process( iCpuClk, reset )

        variable iCpuM1_n   : std_logic;                                -- slack 1.759ns
        variable jSltMerq_n : std_logic;
        variable jSltIorq_n : std_logic;
        variable count      : std_logic_vector(3 downto 0);             -- slack 0.822ns

    begin

        if( reset = '1' )then
            iCpuM1_n    := '1';
            jSltIorq_n  := '1';
            jSltMerq_n  := '1';
            count       := "0000";
            wait_n_s    <= '1';                                         -- WAIT_n fix by Victor Trucco

        elsif( iCpuClk'event and iCpuClk = '1' )then

            if( pSltMerq_n = '0' and jSltMerq_n = '1' )then
                if( ff_clksel = '1' )then
                    if( ff_ldbios_n = '0' )then
                        count := "0010";                                -- 8.06MHz (simulated)
                    else
                        count := CustomSpeed;                           -- 4.10MHz up to 8.06MHz (simulated)
                    end if;
                elsif( ff_clksel5m_n = '0' and (iSltScc1 = '1' or iSltScc2 = '1') )then
                    count := "0001";
                end if;
            elsif( pSltIorq_n = '0' and jSltIorq_n = '1' )then          -- wait for external bus
                if( ff_clksel = '1' )then
                    count := "0110";                                    -- "0011" = original value, "0110" = better reading the pull-up states at 10.74MHz
                elsif( ff_clksel5m_n = '0' )then
                    if( extclk3m = '0' )then
                        count := "0010";                                -- "0010" = calibrated to minimize artifacts in Gradius 2 Enhanced at 5.37 MHz, and other titles
                    else
                        count := "0110";                                -- "0110" = calibrated to properly access the ADPCM unit (NMS-1205) with async 5.37 MHz
                    end if;
                end if;
            elsif( count /= "0000" )then                                -- countdown timer
                count := count - 1;
            end if;

            if( (CpuM1_n = '0' and iCpuM1_n = '1') or pSltWait_n = '0' or esp_wait_s = '0' or vdp_wait_n_s = '0' or opl4_wait_n = '0' )then
                wait_n_s <= '0';
            elsif( count /= "0000" )then
                wait_n_s <= '0';
            elsif( (ff_clksel = '1' or ff_clksel5m_n = '0') and OpllReq = '1' and OpllAck = '0' )then
                wait_n_s <= '0';
            elsif( ErmReq = '1' and adr(15 downto 13) = "010" and MmcAct = '1' )then
                wait_n_s <= '0';
            else
                wait_n_s <= '1';
            end if;

            iCpuM1_n    := CpuM1_n;
            jSltIorq_n  := pSltIorq_n;
            jSltMerq_n  := pSltMerq_n;

        end if;

    end process;

    ----------------------------------------------------------------
    -- On chip internal bus control
    ----------------------------------------------------------------
    process( clk21m, reset )

        variable ExpDec : std_logic;

    begin

        if( reset = '1' )then

            iSltRfsh_n      <= '1';
            iSltMerq_n      <= '1';
            iSltIorq_n      <= '1';
            xSltRd_n        <= '1';
            xSltWr_n        <= '1';
            iSltAdr         <= (others => '1');
            iSltDat         <= (others => '1');

            iack            <= '0';

            dlydbi          <= (others => '1');
            ExpDec          := '0';

        elsif( clk21m'event and clk21m = '1' )then

            -- MSX slot signals
            iSltRfsh_n      <= c_rfsh_n;
            iSltMerq_n      <= c_merq_n;
            iSltIorq_n      <= c_iorq_n;
            xSltRd_n        <= c_rd_n;
            xSltWr_n        <= c_wr_n;
            iSltAdr         <= c_adr;
            iSltDat         <= c_dat;

            if( iSltMerq_n  = '1' and iSltIorq_n = '1' )then
                iack <= '0';
            elsif( ack = '1' )then
                iack <= '1';
            end if;

            -- input assignments for internal devices
            if( mem = '1' and ExpDec = '1' )then
                dlydbi <= ExpDbi;
            elsif( mem = '1' and iSltBot = '1' )then                                                        -- IPL-ROM
                dlydbi <= RomDbi;
            elsif( mem = '1' and iSltErm = '1' and MmcEna = '1' )then                                       -- MegaSD
                dlydbi <= MmcDbi;
            elsif( mem = '0' and adr(  7 downto 3 ) = "10011" )then                                         -- VDP (V9968: 98-9Fh)
                dlydbi <= VdpDbi;
            elsif( mem = '0' and adr(  7 downto 2 ) = "101000" )then                                        -- PSG (AY-3-8910)
                dlydbi <= PsgDbi;
            elsif( mem = '0' and adr(  7 downto 2 ) = "000100" and iPsg2_ena = '1' and use_dualpsg_g )then  -- PSG2 (AY-3-8910)
                dlydbi <= Psg2Dbi;
            elsif( mem = '0' and adr(  7 downto 2 ) = "101010" )then                                        -- PPI (8255)
                dlydbi <= PpiDbi;
            elsif( mem = '0' and adr(  7 downto 2 ) = "110110" and JIS2_ena = '1' )then                     -- Kanji-data (JIS1+JIS2)
                dlydbi <= KanDbi;
            elsif( mem = '0' and adr(  7 downto 1 ) = "1101100" )then                                       -- Kanji-data (JIS1 only)
                dlydbi <= KanDbi;
            elsif( mem = '0' and adr(  7 downto 2 ) = "111111" and (FullRAM or iSlt0_1) = '1' )then         -- Memory-mapper 4096 kB | Extra-mapper 4096 kB
                dlydbi <= MapDbi;
            elsif( mem = '0' and adr(  7 downto 2 ) = "111111" )then                                        -- Memory-mapper 2048 kB
                dlydbi <= "1" & MapDbi(  6 downto 0 );
            elsif( mem = '0' and adr(  7 downto 1 ) = "1011010" )then                                       -- RTC (RP-5C01)
                dlydbi <= RtcDbi;
            elsif( mem = '0' and adr(  7 downto 1 ) = "1110011" )then                                       -- System timer (S1990)
                dlydbi <= systim_dbi;
            elsif( mem = '0' and adr(  7 downto 1 ) = "1110010" and portF4_mode = '1' )then                 -- S1990 registers
                dlydbi <= s1990_dbi;
            elsif( mem = '0' and adr(  7 downto 1 ) = "1010010" )then                                       -- turboR PCM device
                dlydbi <= tr_pcm_dbi;
            elsif( mem = '0' and adr(  7 downto 1 ) = "0111111" and opl3_enabled = '1' and use_opl4_g )then  -- OPL4 wave ports 7E-7Fh
                dlydbi <= opl4_do;
            elsif( mem = '0' and adr(  7 downto 4 ) = "0100" and io40_n /= "11111111" )then                 -- Switched I/O ports
                dlydbi <= swio_dbi;
            elsif( mem = '0' and adr(  7 downto 0 ) = "10100111" and portF4_mode = '1' )then                -- Pause R800 (read only)
                dlydbi <= (others => '0');
            elsif( mem = '0' and adr(  7 downto 0 ) = "11110010" and portF2_ena = '1' and use_wifi_g )then                       -- Port F2 (ESP8266 BIOS)
                dlydbi <= portF2;
            elsif( mem = '0' and adr(  7 downto 0 ) = "11110100" and portF4_mode = '1' )then                -- Port F4 normal (Z80 mode)
                dlydbi <= portF4_bit7 & '0' & portF4_bit5 & "00000";
            elsif( mem = '0' and adr(  7 downto 0 ) = "11110100" )then                                      -- Port F4 inverted
                dlydbi <= portF4_bit7 & "1111111";
            elsif( mem = '0' and adr(  7 downto 1 ) = "0000011" and use_wifi_g )then                        -- ESP ports 06-07h
                dlydbi <= esp_dout_s;
            elsif( mem = '0' and adr(  7 downto 2 ) = "110001" and adr( 1 downto 0 ) = "00" and opl3_enabled = '1' and use_opl4_g )then  -- C4h status: OPL3 + {LD, BUSY} of the OPL4
                dlydbi <= opl3_dout_s or ("000000" & opl4_status);
            elsif( mem = '0' and adr(  7 downto 2 ) = "110001" and opl3_enabled = '1' )then                 -- OPL3 / MoonSound FM ports C4-C7h
                dlydbi <= opl3_dout_s;
--          elsif( mem = '0' and adr(  7 downto 1 ) = "0111110" and opl3_enabled = '1' )then                -- OPLL ports 7C-7Dh via OPL3
--              dlydbi <= opl3_dout_s;
            elsif( mem = '0' and adr(  7 downto 0 ) = "11101001" and use_midi_g )then                       -- MIDI port E9h
                dlydbi <= midi_dout_s;
            else
                dlydbi <= (others => '1');
            end if;

            if( adr = X"FFFF" )then
                ExpDec := '1';
            else
                ExpDec := '0';
            end if;

        end if;

    end process;

    ----------------------------------------------------------------
    process( clk21m, reset )

    begin

        if( reset = '1' )then

            jSltScc1    <= '0';
            jSltScc2    <= '0';
            jSltMem     <= '0';

            wrt <= '0';

        elsif( clk21m'event and clk21m = '0' )then

            if( mem = '1' and iSltScc1 = '1' )then
                jSltScc1 <= '1';
            else
                jSltScc1 <= '0';
            end if;

            if( mem = '1' and iSltScc2 = '1' )then
                jSltScc2 <= '1';
            else
                jSltScc2 <= '0';
            end if;

            if( mem = '1' and iSltErm = '1' )then
                if( MmcEna = '1' and adr(15 downto 13) = "010" )then
                    jSltMem <= '0';
                elsif( MmcMode = '1' or ff_ldbios_n = '0' )then         -- enable SD/MMC drive
                    jSltMem <= '1';
                else                                                    -- disable SD/MMC drive
                    jSltMem <= '0';
                end if;
            elsif( mem = '1' and ((iSltMap0 or iSltMap or rom_main or rom_opll or rom_extd or rom_xbas or rom_free or iSltLin1 or iSltLin2) = '1') )then
                jSltMem <= '1';
            else
                jSltMem <= '0';
            end if;

            if( req = '0' )then
                wrt <= not c_wr_n;                                      -- 1=write, 0=read
            end if;

        end if;

    end process;

    -- access request, CPU > Components
    req     <=  '0'         when( rc_mmcbusy = '1' or rc_vdpbusy = '1' )else   -- R800: device busy, hold the request
                '0'         when( r8_iohold = '1' and rc_req = '0' )else       -- R800: I/O at the real R800 time
                '1'         when( ((iSltMerq_n = '0') or (iSltIorq_n = '0')) and
                                  ((xSltRd_n = '0') or (xSltWr_n = '0')) and iack = '0' )else '0';

    mem     <=  iSltIorq_n;                                             -- 1=memory area, 0=I/O area
    dbo     <=  iSltDat;                                                -- CPU data (CPU > device)
    adr     <=  iSltAdr;                                                -- CPU address (CPU > device)

    -- access acknowledge, Components > CPU
    ack     <=  RamAck      when( RamReq   = '1' )else                  -- ErmAck, MapAck, KanAck
                Scc1Ack     when( jSltScc1 = '1' )else                  -- Scc1Ack
                Scc2Ack     when( jSltScc2 = '1' )else                  -- Scc2Ack
                OpllAck     when( OpllReq  = '1' )else                  -- OpllAck
                req;                                                    -- PsgAck, PpiAck, VdpAck, RtcAck, ...

    dbi     <=  Scc1Dbi     when( jSltScc1 = '1' )else
                Scc2Dbi     when( jSltScc2 = '1' )else
                RamDbi      when( jSltMem  = '1' )else
                dlydbi;

    ----------------------------------------------------------------
    -- R800 (MSXtR): a second CPU, like the real machine
    ----------------------------------------------------------------
    -- The T80a (U01) stays the Z80 with the OCM derived clock. The R800
    -- is a T80s on clk21m (21.48MHz) with the R800 extensions. The S1990
    -- R#6 selects the running CPU, the other one is stopped with its state
    -- and the bus (internal and cartridge slots) belongs to the running one:
    --  * Z80  : BUSRQ, it ends its bus cycle and releases the bus (the real
    --           Z80 stops inside the CHGCPU OTIR and sends its 2nd byte
    --           when resumed)
    --  * R800 : clock enable off on the T1 of its next M1, so that no
    --           bus cycle is left half done, then the Z80 gets the bus back
    -- The R800 drives the cartridge slot bus while it owns it, an access
    -- to an external slot or I/O port lasts like a Z80 one.
    -- The R800 starts from reset at its first selection (the BIOS uses
    -- the F4 bit 5 to tell it apart and parks it inside CHGCPU).
    -- An R800 access waits until it is really completed: the SDRAM CPU
    -- slot has read/written this very address, or the request of this
    -- bus cycle has been acked (+3 clocks for registered device data).
    ----------------------------------------------------------------
    U01_R8 : entity work.T80s
        generic map(
            Mode        => 0,
            T2Write     => 1,
            IOWait      => 1,
            MulDlyB     => 34,                  -- MULUB = 14 R800 cycles at 21.48MHz
            MulDlyW     => 107                  -- MULUW = 36 R800 cycles at 21.48MHz
        )
        port map(
            RESET_n     => (not reset),
            R800_mode   => '1',
            CLK         => clk21m,
            CEN         => r8_cen,
            WAIT_n      => r8_wait_n,
            INT_n       => pSltInt_n,
            NMI_n       => '1',
            BUSRQ_n     => '1',
            M1_n        => r8_m1_n,
            MREQ_n      => r8_merq_n,
            IORQ_n      => r8_iorq_n,
            RD_n        => r8_rd_n,
            WR_n        => r8_wr_n,
            RFSH_n      => r8_rfsh_n,
            HALT_n      => open,
            BUSAK_n     => open,
            A           => r8_adr,
            DI          => r8_dbi,
            DO          => r8_dbo
        );

    -- R800 read cache: 16K byte lines, direct mapped on the physical address (CpuAdr),
    -- write through. Every CPU write to the SDRAM updates it (Z80 too), it is cleared
    -- during reset (RstSeq clears SDRAM areas). A hit has no wait state: the address
    -- is registered at the start of T2, the entry is read at the clk21m falling edge
    -- and the data is taken at the end of T2 (half a clk21m cycle, constrained).
    rc_cacheable <= mem and jSltMem and (not jSltScc1) and (not jSltScc2);

    process( clk21m )
    begin
        if( clk21m'event and clk21m = '0' )then
            rc_q <= r8_cache( conv_integer(CpuAdr(13 downto 0)) );
        end if;
    end process;

    r8_hit  <=  '1' when( r8_owner = '1' and rc_rd = '1' and rc_cacheable = '1' and
                          rc_q(19) = '1' and rc_q(18 downto 8) = CpuAdr(24 downto 14) )else '0';
    r8_dbi  <=  rc_q(7 downto 0)    when( r8_hit = '1' )else
                pSltDat             when( r8_ext = '1' and r8_rd_n = '0' )else             -- from a cartridge
                dbi;

    rc_we   <=  '1' when( reset = '1' or w_wrt_req = '1' )else
                '1' when( r8_owner = '1' and rc_rd = '1' and rc_cacheable = '1' and r8_hit = '0' and rc_done = '1' )else
                '0';
    rc_wa   <=  rc_clr                  when( reset = '1' )else
                CpuAdr(13 downto 0);
    rc_wd   <=  (others => '0')                         when( reset = '1' )else
                '1' & CpuAdr(24 downto 14) & dbo        when( w_wrt_req = '1' )else
                '1' & CpuAdr(24 downto 14) & RamDbi;

    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            if( rc_we = '1' )then
                r8_cache( conv_integer(rc_wa) ) <= rc_wd;
            end if;
            if( reset = '1' )then
                rc_clr <= rc_clr + 1;
            end if;
        end if;
    end process;

    -- R800 speed: hold the T80s when it is faster than a real R800 (see r800_timing.vhd)
    -- R800 speed: hold the T80s when it is faster than a real R800 (see r800_timing.vhd)
    r8_active <= r8_owner;

    U01_R8T : entity work.r800_timing
        port map(
            clk21m      => clk21m,
            reset       => reset,
            active      => r8_active,
            m1_n        => r8_m1_n,
            merq_n      => r8_merq_n,
            iorq_n      => r8_iorq_n,
            rd_n        => r8_rd_n,
            wr_n        => r8_wr_n,
            rfsh_n      => r8_rfsh_n,
            wait_n      => r8_wait_n,
            adr         => r8_adr,
            di          => r8_dbi,
            ppi_a       => PpiPortA,
            exp0        => ExpSlot0,
            exp3        => ExpSlot3,
            dram_mode   => not s1990_cpu(6),
            stall       => r8_stall,
            io_hold     => r8_iohold
        );

    r8_cen  <=  '0' when( r8_owner = '0' or r8_stall = '1' )else
                '0' when( s1990_r800 = '0' and r8_m1_n = '0' and r8_merq_n = '1' )else
                '1';

    r8_parked   <= '1' when( r8_started = '0' or (r8_m1_n = '0' and r8_merq_n = '1' and r8_iorq_n = '1') )else '0';
    z80_busrq_n <= '0' when( s1990_r800 = '1' or r8_owner = '1' )else '1';

    -- bus owner: the R800 once the Z80 has released the bus, the Z80 again once the R800 is stopped
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            r8_owner    <= '0';
            r8_started  <= '0';
        elsif( clk21m'event and clk21m = '1' )then
            if( r8_owner = '0' )then
                if( s1990_r800 = '1' and z80_busak_n = '0' )then
                    r8_owner   <= '1';
                    r8_started <= '1';
                end if;
            elsif( s1990_r800 = '0' and r8_parked = '1' )then
                r8_owner <= '0';
            end if;
        end if;
    end process;

    -- CPU bus seen by the internal bus registers (idle while the bus changes hands)
    c_merq_n <= r8_merq_n when( r8_owner = '1' )else '1' when( z80_busak_n = '0' )else pSltMerq_n;
    c_iorq_n <= r8_iorq_n when( r8_owner = '1' )else '1' when( z80_busak_n = '0' )else pSltIorq_n;
    c_rd_n   <= r8_rd_n   when( r8_owner = '1' )else '1' when( z80_busak_n = '0' )else pSltRd_n;
    c_wr_n   <= r8_wr_n   when( r8_owner = '1' )else '1' when( z80_busak_n = '0' )else pSltWr_n;
    c_rfsh_n <= r8_rfsh_n when( r8_owner = '1' )else '1' when( z80_busak_n = '0' )else CpuRfsh_n;
    c_adr    <= r8_adr    when( r8_owner = '1' )else pSltAdr;
    c_dat    <= r8_dbo    when( r8_owner = '1' )else pSltDat;

    -- R800 bus cycle tracking
    rc_rd   <=  '1' when( r8_merq_n = '0' and r8_rd_n = '0' )else '0';
    rc_wr   <=  '1' when( r8_merq_n = '0' and r8_wr_n = '0' )else '0';
    rc_io   <=  '1' when( r8_iorq_n = '0' and (r8_rd_n = '0' or r8_wr_n = '0') )else '0';

    process( reset, clk21m )
    begin
        if( reset = '1' )then
            rc_req  <= '0';
            rc_wram <= '0';
            rc_cnt  <= (others => '0');
        elsif( clk21m'event and clk21m = '1' )then
            if( r8_owner = '0' or (rc_rd = '0' and rc_wr = '0' and rc_io = '0') )then
                rc_req  <= '0';
                rc_wram <= '0';
                rc_cnt  <= (others => '0');
            else
                if( req = '1' )then
                    rc_req <= '1';
                end if;
                if( w_wrt_req = '1' )then
                    rc_wram <= '1';
                end if;
                if( rc_req = '1' and rc_cnt /= "111" )then
                    rc_cnt <= rc_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    rc_done <=  '0' when( rc_req = '0' or iack = '0' )else
                '0' when( rc_rd = '1' and mem = '1' and jSltMem = '1' and jSltScc1 = '0' and jSltScc2 = '0' and
                          not (sdr_rd_ok = '1' and sdr_rd_adr = CpuAdr) )else
                '0' when( rc_wram = '1' and not (sdr_wr_ok = '1' and sdr_wr_adr = CpuAdr and sdr_wr_dat = dbo) )else
                '0' when( (rc_io = '1' or (rc_rd = '1' and (jSltMem = '0' or jSltScc1 = '1' or jSltScc2 = '1'))) and rc_cnt < "011" )else
                '1';

    -- a device that ends its wait on edge W gives its data in dlydbi on edge W+1: the R800
    -- samples on the first edge with WAIT high, so the external waits last one clock more
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            r8_xwait_d <= '1';
        elsif( clk21m'event and clk21m = '1' )then
            r8_xwait_d <= pSltWait_n and esp_wait_s and vdp_wait_n_s and opl4_wait_n;
        end if;
    end process;

    r8_wait_n <= '1' when( r8_owner = '0' )else                                           -- stopped anyway
                 '1' when( r8_hit = '1' )else                                             -- cache hit: no wait state
                 '0' when( (rc_rd = '1' or rc_wr = '1' or rc_io = '1') and rc_done = '0' )else
                 '0' when( r8_ext = '1' and r8_ext_cnt /= "111" )else                     -- external: as long as a Z80 access
                 '0' when( pSltWait_n = '0' or esp_wait_s = '0' or vdp_wait_n_s = '0' or opl4_wait_n = '0' or r8_xwait_d = '0' )else
                 '1';

    -- R800 access to the cartridge slots (no internal device answers): the strobes last
    -- about 8 clk21m (370ns), like a Z80 access, for the cartridges
    r8_ext  <=  '0' when( r8_owner = '0' or (rc_rd = '0' and rc_wr = '0' and rc_io = '0') )else
                '1' when( mem = '1' and PriSltNum = "01" and Scc1Type = "00" )else
                '1' when( mem = '1' and PriSltNum = "10" and Slot2Mode = "00" )else
                '1' when( mem = '0' and BusDir = '0' )else
                '0';

    process( reset, clk21m )
    begin
        if( reset = '1' )then
            r8_ext_cnt <= (others => '0');
        elsif( clk21m'event and clk21m = '1' )then
            if( r8_ext = '0' )then
                r8_ext_cnt <= (others => '0');
            elsif( r8_ext_cnt /= "111" )then
                r8_ext_cnt <= r8_ext_cnt + 1;
            end if;
        end if;
    end process;

    -- the MegaSD data port (4000-57FFh) and the V9968 ignore/overwrite an access that comes
    -- while the previous one is running, the R800 is fast enough for that: hold the request.
    -- Only before it is issued: the access itself makes the device busy, and the MegaSD gets
    -- its ack from the SDRAM slot (RamAck), so dropping req then would restart it forever.
    rc_mmcbusy <= r8_owner and (not rc_req) and mem and iSltErm and MmcEna and MmcAct when( adr(15 downto 13) = "010" and adr(12 downto 11) /= "11" )else '0';
    rc_vdpbusy <= r8_owner and (not rc_req) and (not mem) and vdp_busy when( adr(7 downto 3) = "10011" )else '0';

    ----------------------------------------------------------------
    -- Port F2 (ESP8266 BIOS)
    ----------------------------------------------------------------
    -- this device allows to program operating states of ESP8266 and
    -- to distinguish whether the system boot was cold (power off or
    -- hard reset) or warm (RESET or GETRESET from command line)
    ----------------------------------------------------------------
    process( clk21m, reset )
    begin
        if( clk21m'event and clk21m = '1' )then
            if( reset = '1' and warmRESET /= '1' )then
                portF2 <= (others => '1');
            elsif( portF2_req = '1' and wrt = '1' )then
                portF2 <= dbo;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Port F4
    ----------------------------------------------------------------
    process( clk21m, reset, LastRst_sta )
    begin
        if( reset = '1' )then
            portF4_bit7 <= not LastRst_sta;
            portF4_bit5 <= '0';
        elsif( clk21m'event and clk21m = '1' )then
            if( portF4_req = '1' and wrt = '1' )then
                portF4_bit7 <= dbo(7);
                portF4_bit5 <= dbo(5) and portF4_mode;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- S1990 registers (MSXtR only)
    ----------------------------------------------------------------
    -- E4h : register select (read back as written)
    -- E5h : register data
    --       R#5  = firmware switch (bit6, always off)
    --       R#6  = CPU mode, bit6 1=ROM 0=DRAM, bit5 1=Z80 0=R800
    --       R#13 = 03h, R#14 = 2Fh, R#15 = 8Bh, others = FFh
    -- the R800 is emulated by the T80 at 10.74MHz with MULU opcodes,
    -- the DRAM mode is only stored, the BIOS is always read from ROM
    --
    -- two CPUs like the real machine: the S1990 R#6 selects the running one,
    -- the other is frozen with its state (see the R800 section)
    ----------------------------------------------------------------
    process( clk21m, reset )
    begin
        if( reset = '1' )then
            s1990_sel <= (others => '0');
            s1990_cpu <= "11";                                                          -- Z80, ROM mode
        elsif( clk21m'event and clk21m = '1' )then
            if( s1990_req = '1' and wrt = '1' )then
                if( adr(0) = '0' )then
                    s1990_sel <= dbo;
                elsif( s1990_sel = X"06" )then
                    s1990_cpu <= dbo(6 downto 5);
                end if;
            end if;
        end if;
    end process;

    s1990_dbi   <=  s1990_sel                       when( adr(0) = '0' )else
                    "00000000"                      when( s1990_sel = X"05" )else
                    "0" & s1990_cpu & "00000"       when( s1990_sel = X"06" )else
                    X"03"                           when( s1990_sel = X"0D" )else
                    X"2F"                           when( s1990_sel = X"0E" )else
                    X"8B"                           when( s1990_sel = X"0F" )else
                    X"FF";

    s1990_r800  <=  portF4_mode and not s1990_cpu(5);

    ----------------------------------------------------------------
    -- PPI(8255) / primary-slot, keyboard, 1bit sound port
    ----------------------------------------------------------------
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            PpiPortA    <= "11111111";          -- primary slot : page 0 => boot-rom, page 1/2 => ese-mmc, page 3 => mapper
            PpiPortC    <= (others => '0');
            ff_ldbios_n <= '0';                 -- OCM-BIOS is required
        elsif( clk21m'event and clk21m = '1' )then
            -- I/O port access on A8-ABh ... PPI(8255) access
            if( PpiReq = '1' )then
                if( wrt = '1' and adr(1 downto 0) = "00" )then
                    PpiPortA    <= dbo;
                    ff_ldbios_n <= '1';         -- OCM-BIOS is ready
                elsif( wrt = '1' and adr(1 downto 0) = "10" )then
                    PpiPortC  <= dbo;
                elsif( wrt = '1' and adr(1 downto 0) = "11" and dbo(7) = '0' )then
                    case dbo(3 downto 1) is
                        when "000"  => PpiPortC(0) <= dbo(0); -- key_matrix Y(0)
                        when "001"  => PpiPortC(1) <= dbo(0); -- key_matrix Y(1)
                        when "010"  => PpiPortC(2) <= dbo(0); -- key_matrix Y(2)
                        when "011"  => PpiPortC(3) <= dbo(0); -- key_matrix Y(3)
                        when "100"  => PpiPortC(4) <= dbo(0); -- cassete motor (0=On,1=Off)
                        when "101"  => PpiPortC(5) <= dbo(0); -- cassete audio out
                        when "110"  => PpiPortC(6) <= dbo(0); -- CAPS lamp (0=On,1=Off)
                        when others => PpiPortC(7) <= dbo(0); -- 1bit sound port
                    end case;
                end if;
            end if;
        end if;
    end process;

    Caps    <=  PpiPortC(6);

    -- I/O port access on A8-ABh ... PPI(8255) register read
    PpiDbi  <=  PpiPortA when adr(1 downto 0) = "00" else
                PpiPortB when adr(1 downto 0) = "01" else
                PpiPortC when adr(1 downto 0) = "10" else
                (others => '1');

    ----------------------------------------------------------------
    -- Expansion slot
    ----------------------------------------------------------------

    -- slot #0
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            ExpSlot0 <= (others => '0');
        elsif( clk21m'event and clk21m = '1' )then
            -- Memory mapped I/O port access on FFFFh ... expansion slot register (master mode)
            if( req = '1' and iSltMerq_n = '0' and wrt = '1' and adr = X"FFFF" )then
                if( PpiPortA(7 downto 6) = "00" )then
                    if( Slot0Mode = '1' )then
                        ExpSlot0 <= dbo;
                    else
                        ExpSlot0 <= (others => '0');
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- slot #3
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            ExpSlot3 <= "00101011";         -- primary slot : page 0 => ipl-rom / xbasic, page 1/2 => megasd, page 3 => mapper
        elsif( clk21m'event and clk21m = '1' )then
            -- Memory mapped I/O port access on FFFFh ... expansion slot register (master mode)
            if( req = '1' and iSltMerq_n = '0' and wrt = '1' and adr = X"FFFF" )then
                if( PpiPortA(7 downto 6) = "11" )then
                    ExpSlot3 <= dbo;
                end if;
            end if;
        end if;
    end process;

    -- primary slot number (master mode)
    with adr(15 downto 14) select PriSltNum <=
        PpiPortA(1 downto 0) when "00",
        PpiPortA(3 downto 2) when "01",
        PpiPortA(5 downto 4) when "10",
        PpiPortA(7 downto 6) when others;

    -- expansion slot number : slot 0 (master mode)
    with adr(15 downto 14) select ExpSltNum0 <=
        ExpSlot0(1 downto 0) when "00",
        ExpSlot0(3 downto 2) when "01",
        ExpSlot0(5 downto 4) when "10",
        ExpSlot0(7 downto 6) when others;

    -- expansion slot number : slot 3 (master mode)
    with adr(15 downto 14) select ExpSltNum3 <=
        ExpSlot3(1 downto 0) when "00",
        ExpSlot3(3 downto 2) when "01",
        ExpSlot3(5 downto 4) when "10",
        ExpSlot3(7 downto 6) when others;

    -- expansion slot register read
    with PpiPortA(7 downto 6) select ExpDbi <=
        not ExpSlot0         when "00",
        not ExpSlot3         when "11",
        (others => '1')      when others;

    ----------------------------------------------------------------
    --  Slot/Page Decode
    ----------------------------------------------------------------
    with( adr(15 downto 14) ) select w_page_dec <=
        "0001"      when "00",
        "0010"      when "01",
        "0100"      when "10",
        "1000"      when "11",
        "XXXX"      when others;

    with( PriSltNum ) select w_prislt_dec <=
        "0001"      when "00",
        "0010"      when "01",
        "0100"      when "10",
        "1000"      when "11",
        "XXXX"      when others;

    with( ExpSltNum0 ) select w_expslt0_dec <=
        "0001"      when "00",
        "0010"      when "01",
        "0100"      when "10",
        "1000"      when "11",
        "XXXX"      when others;

    with( ExpSltNum3 ) select w_expslt3_dec <=
        "0001"      when "00",
        "0010"      when "01",
        "0100"      when "10",
        "1000"      when "11",
        "XXXX"      when others;

    ----------------------------------------------------------------
    --  Address Decode for CPU
    ----------------------------------------------------------------
    -- Slot0-X
    rom_main    <=  mem when( (w_prislt_dec(0) and (w_expslt0_dec(0) or (not Slot0Mode)) and (w_page_dec(0) or w_page_dec(1))) = '1'            )else   -- 0-0 (0000-7FFFh)    32 kB  MSX2P   .ROM / MSXTR   .ROM
                    '0';
    iSltMap0    <=  mem when( (w_prislt_dec(0) and w_expslt0_dec(1) and Slot0Mode and iSlt0_1 ) = '1' and adr /= X"FFFF" and SdrSize /= "00"    )else   -- 0-1 (0000-FFFEh)  4096 kB  Extra-Mapper
                    '0';
    rom_opll    <=  mem when( (w_prislt_dec(0) and w_expslt0_dec(2) and Slot0Mode and w_page_dec(1)) = '1'                                      )else   -- 0-2 (4000-7FFFh)    16 kB  MSX2PMUS.ROM / MSXTRMUS.ROM
                    '0';
    rom_free    <=  mem when( (w_prislt_dec(0) and w_expslt0_dec(3) and Slot0Mode and w_page_dec(1)) = '1'                                      )else   -- 0-3 (4000-7FFFh)    16 kB  FREE16KB.ROM / MSXTROPT.ROM
                    mem when( (w_prislt_dec(0) and cbios_mode and w_page_dec(2)) = '1'                                                          )else   -- 0   (8000-BFFFh)    16 kB  C-BIOS Logo ROM preallocated in Slot0-3 area
                    '0';
    -- Slot1
    iSltScc1    <=  mem when( (w_prislt_dec(1) and (w_page_dec(1) or w_page_dec(2)) and (not iSlt1_linear)) = '1' and Scc1Type /= "00"          )else   -- 1   (4000-BFFFh)  2048 kB  ESE-SCC1
                    '0';
    iSltLin1    <=  mem when( (w_prislt_dec(1) and iSlt1_linear) = '1' and Scc1Type /= "00"                                                     )else   -- 1   (0000-FFFFh)    64 kB  Linear over ESE-SCC1
                    '0';
    -- Slot2
    iSltScc2    <=  mem when( (w_prislt_dec(2) and (w_page_dec(1) or w_page_dec(2)) and (not iSlt2_linear)) = '1' and Slot2Mode /= "00"         )else   -- 2   (4000-BFFFh)  2048 kB  ESE-SCC2
                    '0';
    iSltLin2    <=  mem when( (w_prislt_dec(2) and iSlt2_linear) = '1' and Slot2Mode /= "00"                                                    )else   -- 2   (0000-FFFFh)    64 kB  Linear over ESE-SCC2
                    '0';
    -- Slot3-X
    iSltMap     <=  mem when( (w_prislt_dec(3) and w_expslt3_dec(0)) = '1' and adr /= X"FFFF"                                                   )else   -- 3-0 (0000-FFFEh)  4096 kB  Internal Mapper
                    '0';
    rom_extd    <=  mem when( (w_prislt_dec(3) and w_expslt3_dec(1) and (w_page_dec(0) or w_page_dec(1) or w_page_dec(2))) = '1'                )else   -- 3-1 (0000-BFFFh)    48 kB  (MSX2PEXT.ROM or MSXTREXT.ROM) + MSXKANJI.ROM
                    '0';
    iSltErm     <=  mem when( (w_prislt_dec(3) and w_expslt3_dec(2) and (w_page_dec(1) or w_page_dec(2))) = '1'                                 )else   -- 3-2 (4000-BFFFh)   128 kB  (MEGASDHC.ROM + FILL64KB.ROM) or NEXTOR16.ROM
                    '0';
    rom_xbas    <=  mem when( (w_prislt_dec(3) and w_expslt3_dec(3) and w_page_dec(1) and ff_ldbios_n) = '1'                                    )else   -- 3-3 (4000-7FFFh)    16 kB  XBASIC2 .ROM / XBASIC21.ROM
                    '0';
    iSltBot     <=  mem when( (w_prislt_dec(3) and w_expslt3_dec(3) and (w_page_dec(0) or w_page_dec(3)) and (not ff_ldbios_n)) = '1'           )else   -- 3-3 (0000-3FFFh & C000-FFFFh)     3 kB  IPL-ROM (pre-boot state)
                    '0';
    -- I/O
    rom_kanj    <=  not mem     when( adr(7 downto 2) = "110110" )else
                    '0';

    -- RamX / RamY access request
    RamReq  <=  Scc1Ram or Scc2Ram or ErmRam or MapRam or RomReq or KanRom;

    -- access request to component
    VdpReq      <=  req when( mem = '0' and adr(7 downto 3) = "10011"                                                   )else '0';  -- I/O:98-9Fh / VDP (V9968)
    PsgReq      <=  req when( mem = '0' and adr(7 downto 2) = "101000"                                                  )else '0';  -- I/O:A0-A3h / PSG (AY-3-8910)
    Psg2Req     <=  req when( mem = '0' and adr(7 downto 2) = "000100" and iPsg2_ena = '1' and use_dualpsg_g            )else '0';  -- I/O:10-13h / PSG2 (AY-3-8910)
    PpiReq      <=  req when( mem = '0' and adr(7 downto 2) = "101010"                                                  )else '0';  -- I/O:A8-ABh / PPI (8255)
    OpllReq     <=  req when( mem = '0' and adr(7 downto 1) = "0111110" and (Slot0Mode = '1' or cbios_mode = '1')       )else '0';  -- I/O:7C-7Dh / OPLL (YM2413) (Slot0 Primary Mode allows an external OPLL, C-BIOS mode does not)
    KanReq      <=  req when( mem = '0' and adr(7 downto 2) = "110110"                                                  )else '0';  -- I/O:D8-DBh / Kanji-data
    RomReq      <=  req when( (rom_main or rom_opll or rom_extd or rom_xbas or rom_free or iSltLin1 or iSltLin2) = '1'  )else '0';
    MapReq      <=  req when( mem = '0' and adr(7 downto 2) = "111111"                                                  )else       -- I/O:FC-FFh / Memory-mapper
                    req when( iSltMap0 = '1' or iSltMap  = '1'                                                          )else '0';  -- MEM:       / Extra-mapper, Memory-mapper
    Scc1Req     <=  req when( iSltScc1 = '1'                                                                            )else '0';  -- MEM:       / ESE-SCC1
    Scc2Req     <=  req when( iSltScc2 = '1'                                                                            )else '0';  -- MEM:       / ESE-SCC2
    ErmReq      <=  req when( iSltErm  = '1'                                                                            )else '0';  -- MEM:       / ESE-RAM, MegaSD
    RtcReq      <=  req when( mem = '0' and adr(7 downto 1) = "1011010"                                                 )else '0';  -- I/O:B4-B5h / RTC (RP-5C01)
    s1990_req   <=  req when( mem = '0' and adr(7 downto 1) = "1110010" and portF4_mode = '1'                          )else '0';  -- I/O:E4-E5h / S1990 registers
    systim_req  <=  req when( mem = '0' and adr(7 downto 1) = "1110011"                                                 )else '0';  -- I/O:E6-E7h / System timer (S1990)
    swio_req    <=  req when( mem = '0' and adr(7 downto 4) = "0100"                                                    )else '0';  -- I/O:40-4Fh / Switched I/O ports
    portF2_req  <=  req when( mem = '0' and adr(7 downto 0) = "11110010" and portF2_ena = '1' and use_wifi_g                             )else '0';  -- I/O:F2h    / Port F2 device (ESP8266 BIOS)
    portF4_req  <=  req when( mem = '0' and adr(7 downto 0) = "11110100"                                                )else '0';  -- I/O:F4h    / Port F4 device
    tr_pcm_req  <=  req when( mem = '0' and adr(7 downto 1) = "1010010"                                                 )else '0';  -- I/O:A4-A5h / turboR PCM device

    BusDir  <=  '1' when( pSltAdr(7 downto 3) = "10011"                                         )else   -- I/O:98-9Fh / VDP (V9968)
                '1' when( pSltAdr(7 downto 2) = "101000"                                        )else   -- I/O:A0-A3h / PSG (AY-3-8910)
                '1' when( pSltAdr(7 downto 2) = "000100" and iPsg2_ena = '1' and use_dualpsg_g  )else   -- I/O:10-13h / PSG2 (AY-3-8910)
                '1' when( pSltAdr(7 downto 2) = "101010"                                        )else   -- I/O:A8-ABh / PPI (8255)
                '1' when( pSltAdr(7 downto 2) = "110110" and JIS2_ena = '1'                     )else   -- I/O:D8-DBh / Kanji-data (JIS1+JIS2)
                '1' when( pSltAdr(7 downto 1) = "1101100"                                       )else   -- I/O:D8-D9h / Kanji-data (JIS1 only)
                '1' when( pSltAdr(7 downto 2) = "111111"                                        )else   -- I/O:FC-FFh / Memory-mapper
                '1' when( pSltAdr(7 downto 1) = "1011010"                                       )else   -- I/O:B4-B5h / RTC (RP-5C01)
                '1' when( pSltAdr(7 downto 1) = "1110010" and portF4_mode = '1'                 )else   -- I/O:E4-E5h / S1990 registers
                '1' when( pSltAdr(7 downto 1) = "1110011"                                       )else   -- I/O:E6-E7h / System timer (S1990)
                '1' when( pSltAdr(7 downto 4) = "0100" and io40_n /= "11111111"                 )else   -- I/O:40-4Fh / Switched I/O ports
                '1' when( pSltAdr(7 downto 0) = "10100111" and portF4_mode = '1'                )else   -- I/O:A7h    / Pause R800 (read only)
                '1' when( pSltAdr(7 downto 0) = "11110010" and portF2_ena = '1' and use_wifi_g                   )else   -- I/O:F2h    / Port F2 device (ESP8266 BIOS)
                '1' when( pSltAdr(7 downto 0) = "11110100"                                      )else   -- I/O:F4h    / Port F4 device
                '1' when( pSltAdr(7 downto 1) = "1010010"                                       )else   -- I/O:A4-A5h / turboR PCM device
                '1' when( pSltAdr(7 downto 1) = "0111111" and opl3_enabled = '1' and use_opl4_g    )else   -- I/O:7E-7Fh / OPL4 wave
                '1' when( pSltAdr(7 downto 1) = "0000011" and use_wifi_g                        )else   -- I/O:06-07h / ESP
                '1' when( pSltAdr(7 downto 2) = "110001" and opl3_enabled = '1'                 )else   -- I/O:C4-C7h / OPL3 (MoonSound FM)
--              '1' when( pSltAdr(7 downto 1) = "0111110" and opl3_enabled = '1'                )else   -- I/O:7C-7Dh / OPLL via OPL3
                '1' when( pSltAdr(7 downto 0) = "11101001" and use_midi_g                       )else   -- I/O:E9h    / MIDI
                '0';

    ----------------------------------------------------------------
    -- Video output
    ----------------------------------------------------------------
--  V9938_n <= '0';         -- '0' is V9938 VDP core
    V9938_n <= '1';         -- '1' is TH9958 VDP core

    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            -- F18A: the VDP always outputs 15kHz with separate H / V syncs
            -- and the mist_video scandoubler makes 31kHz, so always take
            -- the VGA branch (RGB, HS, VS) whatever DisplayMode is.
            case std_logic_vector'("10") is
            when "00" =>                                            -- TV 15kHz
                pDac_VR     <= videoC;                              -- Chrominance of S-Video Out
                pDac_VG     <= videoY;                              -- Luminance of S-Video Out
                pDac_VB     <= videoV;                              -- Composite Video Out
                Reso_v      <= '0';                                 -- Hsync:15kHz
                pVideoHS_n  <= 'Z';                                 -- CSync Disabled
                pVideoVS_n  <= DACout;                              -- Audio Out (Mono)
--              legacy_vga  <= '0';                                 -- behaves like vAllow_n        (for V9938 VDP core)

            when "01" =>                                            -- RGB 15kHz
                pDac_VR     <= VideoR;                              -- Luminance 100%
                pDac_VG     <= VideoG;
                pDac_VB     <= VideoB;
                Reso_v      <= '0';                                 -- Hsync:15kHz
                pVideoHS_n  <= VideoCS_n;                           -- CSync Enabled
                pVideoVS_n  <= DACout;                              -- Audio Out (Mono)
--              legacy_vga  <= '0';                                 -- behaves like vAllow_n        (for V9938 VDP core)

            when others =>                                          -- VGA / VGA+ 31kHz
                pDac_VR     <= VideoR;                              -- Luminance 100%
                pDac_VG     <= VideoG;
                pDac_VB     <= VideoB;
                Reso_v      <= '1';                                 -- Hsync:31kHz
                pVideoHS_n  <= VideoHS_n;
                pVideoVS_n  <= VideoVS_n;
--              legacy_vga  <= not DisplayMode(0);                  -- behaves like vAllow_n        (for V9938 VDP core)
                if( legacy_sel = '0' )then                          -- Assignment of Legacy Output  (for TH9958 VDP core)
                    legacy_vga  <= not DisplayMode(0);              -- to VGA
                else
                    legacy_vga  <= DisplayMode(0);                  -- to VGA+
                end if;

            end case;
        end if;
    end process;

    -- PRTSCR key
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            ff_Reso <= Reso;
        end if;
    end process;

    pVideoClk <= 'Z';
    pVideoDat <= 'Z';

--    ----------------------------------------------------------------
--    -- Sound output
--    ----------------------------------------------------------------
--
--    -- | b7    | b6    | b5   | b4   | b3  | b2  | b1  | b0  |
--    -- | SHIFT | LCTRL | PgUp | PgDn | F9  | F10 | F11 | F12 |          Added the CTRL status by t.hara, 2021/Aug/6th, Left-CTRL since 2024/Jan/21st

    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            vFkeys  <=  Fkeys;
        end if;
    end process;


    -- Cassette Magnetic Tape (CMT) interface
    CmtIn   <= null                                         when( power_on_reset = '0' )else
               ear_i                                        when( portF4_mode = '0' )else                       -- CMT enabled  (MSX2+)
               '0';                                         -- CMT data input is always '0' on MSXtR            -- CMT disabled (MSXtR)

    mic_o   <= null                                         when( power_on_reset = '0' )else
               CmtOut                                       when( portF4_mode = '0' )else                       -- CMT enabled  (MSX2+)
               'Z';                                                                                             -- CMT disabled (MSXtR)
					
    -- SCRLK key
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            ff_Scro <= Scro;
        end if;
    end process;

    -----------------------------------------------------------------
    -- External memory access
    -----------------------------------------------------------------
    -- Slot map / SDRAM memory map      (SDRAM 8 MB at least)
    --
    -- Slot 0-0 : MainROM               [ D ]020000-027FFF (  32 kB)
    -- Slot 3-3 : XBASIC                [ D ]028000-02BFFF (  16 kB)
    -- Slot 0-2 : FM-BIOS               [ D ]02C000-02FFFF (  16 kB)
    -- Slot 0-3 : rom_free(OPT)         [ D ]03C000-03FFFF (  16 kB)
    -- Slot 1   : (EXTERNAL-SLOT)
    --            / ESE-SCC1-SMN(M4)    [A~B]100000-xFFFFF (2048 kB)        <= only for SDRAM < 16 MB + Mapper 4096 kB / shared with Mapper starting from 1024 kB
    --            / Linear-1-SMN(M4)    [ A ]100000-10FFFF (  64 kB)        <= only for SDRAM < 16 MB + Mapper 4096 kB / shared with ESE-SCC1-SMN(M4)
    --            / ESE-SCC1-SMN(M2)    [ B ]000000-1FFFFF (2048 kB)        <= only for SDRAM < 16 MB + Mapper 2048 kB
    --            / Linear-1-SMN(M2)    [ B ]000000-10FFFF (  64 kB)        <= only for SDRAM < 16 MB + Mapper 2048 kB / shared with ESE-SCC1-SMN(M2)
    -- Slot 2   : (EXTERNAL-SLOT)
    --            / ESE-SCC2(L)         [ C ]000000-1FFFFF (2048 kB)        <= alias ESE-SCC2-SMN(L)
    --            / Linear-2            [ C ]000000-00FFFF (  64 kB)        <= alias Linear-2-SMN / shared with ESE-SCC2(L)
    --            / ESE-SCC2-SMN(H)(M4) [A~B]100000-xFFFFF (2048 kB)        <= only for SDRAM < 16 MB + Mapper 4096 kB / shared with ESE-SCC1-SMN(M4) in read-only mode
    --            / ESE-SCC2-SMN(H)(M2) [ B ]000000-1FFFFF (2048 kB)        <= only for SDRAM < 16 MB + Mapper 2048 kB / shared with ESE-SCC1-SMN(M2) in read-only mode
    -- Slot 3-0 : Mapper(RAM)           [A+B]000000-1FFFFF (4096 kB)        <= recognized as Main-RAM by the system if Extra-Mapper is disabled
    -- Slot 3-1 : ExtROM + KanjiROM     [ D ]030000-03BFFF (  48 kB)
    -- Slot 3-2 : MegaSDHC / NEXTOR     [ D ]000000-01FFFF ( 128 kB)
    --            ESE-RAM               [ D ]000000-07FFFF (BIOS: 512 kB)
    --            RAMDISK(unused)       [ D ]080000-0FF3FF (FREE: 509 kB)
    --            IPL-ROM(hex)          [ D ]0FF400-0FFFFF (   3 kB)        <= reserved to extend IPL-ROM
    -- Slot 3-3 : IPL-ROM(preloader)    (blockRAM: < 1 kB, see IPLROM*.ASM) <= swapped with XBASIC at boot time
    -- VRAM     : VRAM                  [ D ]100000-1FFFFF (1024 kB)
    -- I/O      : Kanji-data            [ D ]040000-07FFFF ( 256 kB)
    -----------------------------------------------------------------
    -- Slot map / SDRAM memory map      (SDRAM 16 MB at least)
    --
    -- Slot 0-1 : Extra-Mapper(RAM)     [A+B]200000-3FFFFF (4096 kB)        <= recognized as Main-RAM by the system if enabled
    -- Slot 1   : ESE-SCC1              [ C ]200000-3FFFFF (2048 kB)
    --            / Linear-1            [ C ]200000-20FFFF (  64 kB)        <= shared with ESE-SCC1
    -- Slot 2   : ESE-SCC2(H)           [ C ]200000-3FFFFF (2048 kB)        <= shared with ESE-SCC1 in read-only mode
    -----------------------------------------------------------------
    -- Memo: SdrAdr(12 downto 11) <= CpuAdr(24 downto 23);
    --       SdrBa ( 1 downto  0) <= CpuAdr(22 downto 21);
    -----------------------------------------------------------------
    CpuAdr(24 downto 20) <= "01" & "0"  & MapAdr(21 downto 20)              when( iSltMap0 = '1' and iSlt0_1 = '1' )else        -- [A+B]2xxxxx => 4096 kB Extra-Mapper(RAM)
                            "00" & "0"  & MapAdr(21 downto 20)              when( iSltMap  = '1' and FullRAM = '1' )else        -- [A+B]0xxxxx => 4096 kB Mapper(RAM)
                            "00" & "00" & MapAdr(20)                        when( iSltMap  = '1' )else                          -- [ A ]0xxxxx => 2048 kB Mapper(RAM)
                            "00" & "100"                                    when( iSltLin2 = '1' )else                          -- [ C ]0xxxxx =>   64 kB Linear over ESE-SCC2(L) / ESE-SCC2-SMN(L)
                            "0" & Scc2Adr(21) & "10" & Scc2Adr(20)          when( iSltScc2 = '1' and SdrSize /= "00" )else      -- [ C ]0xxxxx => 4096 kB ESE-SCC2(L) + ESE-SCC2(H)
                            "00" & "1" & Scc2Adr(21 downto 20)              when( iSltScc2 = '1' and Scc2Adr(21) = '0' )else    -- [ C ]0xxxxx => 2048 kB ESE-SCC2-SMN(L)               <= only for SDRAM < 16 MB
                            "00" & "0" & Scc2Adr(20) & not Scc2Adr(20)      when( iSltScc2 = '1' and FullRAM = '1' )else        -- [A~B]1xxxxx => 2048 kB ESE-SCC2-SMN(H)(M4)           <= only for SDRAM < 16 MB + Mapper 4096 kB
                            "00" & not Scc2Adr(21) & Scc2Adr(21 downto 20)  when( iSltScc2 = '1' )else                          -- [ B ]0xxxxx => 2048 kB ESE-SCC2-SMN(H)(M2)           <= only for SDRAM < 16 MB + Mapper 2048 kB
                            "01" & "100"                                    when( iSltLin1 = '1' and SdrSize /= "00" )else      -- [ C ]2xxxxx =>   64 kB Linear over ESE-SCC1
                            "01" & "10" & Scc1Adr(20)                       when( iSltScc1 = '1' and SdrSize /= "00" )else      -- [ C ]2xxxxx => 2048 kB ESE-SCC1
                            "00" & "001"                                    when( iSltLin1 = '1' and FullRAM = '1' )else        -- [ A ]1xxxxx =>   64 kB Linear over ESE-SCC1-SMN(M4)  <= only for SDRAM < 16 MB + Mapper 4096 kB
                            "00" & "0" & Scc1Adr(20) & not Scc1Adr(20)      when( iSltScc1 = '1' and FullRAM = '1' )else        -- [A~B]1xxxxx => 2048 kB ESE-SCC1-SMN(M4)              <= only for SDRAM < 16 MB + Mapper 4096 kB
                            "00" & "010"                                    when( iSltLin1 = '1' )else                          -- [ B ]0xxxxx =>   64 kB Linear over ESE-SCC1-SMN(M2)  <= only for SDRAM < 16 MB + Mapper 2048 kB
                            "00" & "01" & Scc1Adr(20)                       when( iSltScc1 = '1' )else                          -- [ B ]0xxxxx => 2048 kB ESE-SCC1-SMN(M2)              <= only for SDRAM < 16 MB + Mapper 2048 kB
                            "00" & "110";                                                                                       -- [ D ]0xxxxx => 1024 kB ESE-RAM
--                          "00" & "111";                                                                                       -- [ D ]1xxxxx => 1024 kB VRAM

    CpuAdr(19 downto  0) <= MapAdr(19 downto  0)                            when( iSltMap0 = '1' or iSltMap  = '1' )else        -- [A+B]200000-3FFFFF (4096 kB) Internal Slot0-1
                                                                                                                                -- [A+B]000000-1FFFFF (4096 kB) Internal Slot3-0
                            "0000"   & adr(15 downto  0)                    when( iSltLin1 = '1' or iSltLin2 = '1' )else        -- [ C ]000000-00FFFF (  64 kB) Internal Slot2 Linear
                                                                                                                                -- [ C ]200000-20FFFF (  64 kB) Internal Slot1 Linear
                                                                                                                                -- [ A ]100000-10FFFF (  64 kB) Internal Slot1 Linear   <= only for SDRAM < 16 MB + Mapper 4096 kB
                                                                                                                                -- [ B ]000000-00FFFF (  64 kB) Internal Slot1 Linear   <= only for SDRAM < 16 MB + Mapper 2048 kB
                            Scc2Adr(19 downto  0)                           when( iSltScc2 = '1' )else                          -- [ C ]000000-3FFFFF (4096 kB) Internal Slot2
                                                                                                                                -- [CAB]000000-xFFFFF (4096 kB) Internal Slot2          <= only for SDRAM < 16 MB + Mapper 4096 kB
                                                                                                                                -- [C+B]000000-1FFFFF (4096 kB) Internal Slot2          <= only for SDRAM < 16 MB + Mapper 2048 kB
                            Scc1Adr(19 downto  0)                           when( iSltScc1 = '1' )else                          -- [ C ]200000-3FFFFF (2048 kB) Internal Slot1
                                                                                                                                -- [A~B]100000-xFFFFF (2048 kB) Internal Slot1          <= only for SDRAM < 16 MB + Mapper 4096 kB
                                                                                                                                -- [ B ]000000-1FFFFF (2048 kB) Internal Slot1          <= only for SDRAM < 16 MB + Mapper 2048 kB
                            "0"      & ErmAdr(18 downto  0)                 when( iSltErm  = '1' )else                          -- [ D ]000000-07FFFF ( 512 kB) Internal Slot3-2
                            "00100"  & adr(14 downto  0)                    when( rom_main = '1' )else                          -- [ D ]020000-027FFF (  32 kB) Internal Slot0-0
                            "001010" & adr(13 downto  0)                    when( rom_xbas = '1' )else                          -- [ D ]028000-02BFFF (  16 kB) Internal Slot3-3
                            "001011" & adr(13 downto  0)                    when( rom_opll = '1' )else                          -- [ D ]02C000-02FFFF (  16 kB) Internal Slot0-2
                            "0011"   & adr(15 downto  0)                    when( rom_extd = '1' )else                          -- [ D ]030000-03BFFF (  48 kB) Internal Slot3-1
                            "001111" & adr(13 downto  0)                    when( rom_free = '1' )else                          -- [ D ]03C000-03FFFF (  16 kB) Internal Slot0-3
                            "01"     & KanAdr(17 downto  0)                 when( rom_kanj = '1' )else                          -- [ D ]040000-07FFFF ( 256 kB) Kanji-data (JIS1+JIS2)
                            (others => '0');

    -- CpuAdr registered in memclk for the SDRAM side (ZEMMIX-dl0): the slot decoding
    -- (iSltAdr, PpiPortA, ExpSlot3 -> iSlt* -> CpuAdr) was the critical memclk path into
    -- SdrAdr / SdrUdq. The cpu sees its address one memclk (11.6 ns) later, and every
    -- SDRAM process uses this copy, so the R800 slot tracking stays consistent.
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            CpuAdr_r <= CpuAdr;
        end if;
    end process;

    ----------------------------------------------------------------
    -- SDRAM access
    ----------------------------------------------------------------
    --   SdrSta = "000" => idle
    --   SdrSta = "001" => precharge all
    --   SdrSta = "010" => refresh
    --   SdrSta = "011" => mode register set
    --   SdrSta = "100" => read cpu
    --   SdrSta = "101" => write cpu
    --   SdrSta = "110" => read vdp
    --   SdrSta = "111" => write vdp
    ----------------------------------------------------------------
    w_wrt_req   <=  (RamReq and (
                        (Scc1Wrt and iSltScc1 ) or
                        (Scc2Wrt and iSltScc2 ) or
                        (ErmWrt  and iSltErm  ) or
                        (MapWrt  and iSltMap0 ) or
                        (MapWrt  and iSltMap  )));

    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( ff_sdr_seq = "111" )then
                if( RstSeq(4 downto 2) = "000" )then
                    SdrSta <= "000";                                                -- idle
                elsif( RstSeq(4 downto 2) = "001" )then
                --  case RstSeq(1 downto 0) is
                --      when "00"       => SdrSta <= "000";                         -- idle
                --      when "01"       => SdrSta <= "001";                         -- precharge all
                --      when "10"       => SdrSta <= "010";                         -- refresh (more than 8 cycles)
                --      when others     => SdrSta <= "011";                         -- mode register set
                --  end case;
                    SdrSta <= "0" & RstSeq(1 downto 0);
                elsif( RstSeq(4 downto 3) /= "11" )then
                    SdrSta <= "101";                                                -- Write (Initialize memory content)
                elsif( iSltRfsh_n = '0' and VideoDLClk = '1' )then
                    SdrSta <= "010";                                                -- refresh
                else
                    --  Normal memory access mode
                    SdrSta(2) <= '1';                                               -- read/write cpu/vdp
                end if;
            elsif( ff_sdr_seq = "001" and SdrSta(2) = '1' and RstSeq(4 downto 3) = "11" )then
                SdrSta(1) <= VideoDLClk;                                            -- 0:cpu, 1:vdp
                if( VideoDLClk = '0' and wave_slot = '1' )then
                    SdrSta(0) <= wave_we;           -- for the OPL4 wave memory (in a free cpu slot)
                elsif( VideoDLClk = '0' )then
                    SdrSta(0) <= w_wrt_req;         -- for cpu
                else
                    SdrSta(0) <= not WeVdp_n;       -- for vdp
                end if;
            end if;
        end if;
    end process;

    -- OPL4 wave memory (ZEMMIX-0au.4): 4 MB at the top of the 32 MB SDRAM (CpuAdr
    -- 1C00000-1FFFFFF, not used by the memory map), served in the cpu slots the cpu
    -- does not need. The Z80 does not wait for the SDRAM (it takes RamDbi at a fixed
    -- time), so a slot is taken only out of its memory cycles: the worst delay of a
    -- cpu access grows by about 2 memclk. The R800 waits for its own slot (rc_done,
    -- sdr_rd_ok / sdr_wr_ok), so under the R800 a request waiting for 3 cpu slots
    -- takes the next one anyway (not on the MegaSD, which acks on the SDRAM slot).
    -- A wave slot does not touch RamDbi nor the R800 slot tracking, and RamAck waits
    -- for a real cpu slot (iack drops req: a cpu write acked in a wave slot is lost).
    wave_pend <= wave_req_t xor wave_done_t;
    wave_sdr_adr <= "111" & wave_adr;

    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( ff_sdr_seq = "111" )then
                -- V9968 dot states (DH/DL): 01, 10, 00, 11. A slot starts when DH rises: with
                -- DL = 0 it is the cpu slot, with DL = 1 the vdp slot. At "111" the previous dot
                -- state is still there, DL = 1 before a cpu slot (as the refresh above)
                if( wave_pend = '1' and RstSeq(4 downto 3) = "11" and VideoDLClk = '1' and iSltRfsh_n = '1' and
                    ( (RamReq = '0' and iSltMerq_n = '1') or
                      (r8_owner = '1' and wave_wait = "11" and iSltErm = '0') ) )then
                    wave_slot <= '1';
                else
                    wave_slot <= '0';
                end if;
            end if;
            if( ff_sdr_seq = "101" )then
                if( wave_slot = '1' and SdrSta(2 downto 1) = "10" )then
                    -- the access is done when its data is on the bus (read) or written,
                    -- only in a real cpu slot (else it is tried again)
                    if( wave_we = '0' )then
                        wave_rdat <= pMemDat;
                    end if;
                    wave_done_t <= wave_req_t;
                    wave_wait   <= "00";
                elsif( wave_pend = '0' )then
                    wave_wait   <= "00";
                elsif( SdrSta(2 downto 1) = "10" and wave_wait /= "11" )then
                    wave_wait   <= wave_wait + 1;                           -- one more cpu slot waited
                end if;
            end if;
        end if;
    end process;

    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            case ff_sdr_seq is
                when "000" =>
                    if( SdrSta(2) = '1' )then               -- cpu/vdp read/write
                        SdrCmd <= SdrCmd_ac;
                    elsif( SdrSta(1 downto 0) = "00" )then  -- idle
                        SdrCmd <= SdrCmd_xx;
                    elsif( SdrSta(1 downto 0) = "01" )then  -- precharge all
                        SdrCmd <= SdrCmd_pr;
                    elsif( SdrSta(1 downto 0) = "10" )then  -- refresh
                        SdrCmd <= SdrCmd_re;
                    else                                    -- mode register set
                        SdrCmd <= SdrCmd_ms;
                    end if;
                when "001" =>
                    SdrCmd <= SdrCmd_xx;
                when "010" =>
                    if( SdrSta(2) = '1' )then
                        if( SdrSta(0) = '0' )then
                            SdrCmd <= SdrCmd_rd;            -- "100"(cpu read) / "110"(vdp read)
                        else
                            SdrCmd <= SdrCmd_wr;            -- "101"(cpu write) / "111"(vdp write)
                        end if;
                    end if;
                when "011" =>
                    SdrCmd <= SdrCmd_xx;
                when others =>
                    null;
            end case;
        end if;
    end process;

    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            case ff_sdr_seq is
                when "000" =>
                    SdrUdq <= '1';
                    SdrLdq <= '1';
                when "001" =>
                    -- byte of a cpu / wave write, taken one memclk before "010": CpuAdr(0)
                    -- comes from iSltAdr (clk21m) through the slot decoding, a long path
                    if( wave_slot = '1' )then
                        sdr_wr_a0 <= wave_adr(0);
                    else
                        sdr_wr_a0 <= CpuAdr_r(0);
                    end if;
                when "010" =>
                    if( SdrSta(2) = '1' )then
                        if( SdrSta(0) = '0' )then
                            SdrUdq <= '0';
                            SdrLdq <= '0';
                        else
                            if( RstSeq(4 downto 3) /= "11" )then
                                SdrUdq <= '0';
                                SdrLdq <= '0';
                            elsif( VideoDLClk = '0' )then
                                SdrUdq <= not sdr_wr_a0;                -- cpu or OPL4 wave write
                                SdrLdq <= sdr_wr_a0;
                            else
                                SdrUdq <= not VdpAdr(16);
                                SdrLdq <= VdpAdr(16);
                            end if;
                        end if;
                    end if;
                when "011" =>
                    SdrUdq <= '1';
                    SdrLdq <= '1';
                when others =>
                    null;
            end case;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- SDRAM controller compatible with 8 MB, 16 MB and 32 MB single chip
    -- STABLE VERSION 2022.08.24 by KdL  [ USE AT YOUR OWN RISK!! ]
    -----------------------------------------------------------------------
    -- * ClrAdr counter has been removed.
    -- * Other SDRAM processes are unchanged.
    -----------------------------------------------------------------------
    -- Memo: SdrAdr(12 downto 11) <= CpuAdr(24 downto 23);
    --       SdrBa ( 1 downto  0) <= CpuAdr(22 downto 21);
    -----------------------------------------------------------------------
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            case ff_sdr_seq is
                when "000" =>
                    if( SdrSta(2) = '0' )then                                       -- set [command mode]
                        --           WBL=single TM=off CL=2 WT=0(seq) BL=1
                        SdrAdr <= "00" & "010" & "0" & "010" & "0" & "000";
                        SdrBa  <= "00";                                             -- bank A
                    else                                                            -- set [row address]
                        if( RstSeq(4 downto 2) = "011" and warmRESET /= '1' )then
                            SdrAdr <= (others => '0');                              -- clear "AB" mark (ESE-SCC2 >> ESE-SCC1 >> ESE-RAM)
                            SdrBa  <= "1" & RstSeq(1);                              -- bank C+D
                        elsif( VideoDLClk = '0' and wave_slot = '1' )then
                            SdrAdr <= wave_sdr_adr(24 downto 23) & wave_sdr_adr(11 downto 1);   -- OPL4 wave memory
                            SdrBa  <= wave_sdr_adr(22 downto 21);
                        elsif( VideoDLClk = '0' )then
                            SdrAdr <= CpuAdr_r(24 downto 23) & CpuAdr_r(11 downto 1);   -- cpu read/write
                            SdrBa  <= CpuAdr_r(22 downto 21);                         -- bank A+B+C+D
                        else
                            SdrAdr <= "00" & VdpAdr(10 downto 0);                   -- vdp read/write
                            SdrBa  <= "11";                                         -- bank D
                        end if;
                    end if;
                when "010" =>                                                                               -- set [column address]
                    SdrAdr(10 downto 9) <= "10";                                                            -- A10=1 => enable auto precharge
                    -- when A10=1, SdrBa is ignored and all banks are selected
                    -- be careful not to assign SdrBa during auto precharge, otherwise it will cause instability
                    if( RstSeq(4 downto 1) = "0110" and warmRESET /= '1' )then
                        SdrAdr(12 downto 11) <= CpuAdr_r(24 downto 23);
                        SdrAdr(8 downto 0) <= RstSeq(0) & "00000000";                                       -- clear ESE-SCC2 >> ESE-SCC1
                    elsif( RstSeq(4 downto 1) = "0111" and warmRESET /= '1' )then
                        SdrAdr(12 downto 11) <= CpuAdr_r(24 downto 23);
                        SdrAdr(8 downto 0) <= (others => '0');                                              -- clear ESE-RAM
                    elsif( VideoDLClk = '0' and wave_slot = '1' )then
                        SdrAdr(12 downto 11) <= wave_sdr_adr(24 downto 23);
                        SdrAdr(8 downto 0) <= wave_sdr_adr(20 downto 12);                                   -- OPL4 wave memory
                    elsif( VideoDLClk = '0' )then
                        SdrAdr(12 downto 11) <= CpuAdr_r(24 downto 23);
                        SdrAdr(8 downto 0) <= CpuAdr_r(20 downto 12);                                         -- cpu read/write
                    elsif( VdpAdr(15) = '0' )then
                        SdrAdr(12 downto 11) <= "00";
                        SdrAdr(8 downto 0) <= "1" & vram_page(3 downto 0) & VdpAdr(14 downto 11);           -- vdp read/write (even)
                    else
                        SdrAdr(12 downto 11) <= "00";
                        SdrAdr(8 downto 0) <= "1" & vram_page(7 downto 4) & VdpAdr(14 downto 11);           -- vdp read/write (odd)
                    end if;
                when others =>
                    null;
            end case;
        end if;
    end process;

    -- SDRAM size : "00" = 8 MB, "01" = 16 MB, "10" = 32 MB (default), "11" = Reserved (pre-boot state)
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( ff_ldbios_n = '1' )then
                SdrSize <= "10";                                -- 32768 kB
            end if;
        end if;
    end process;

    -- SDRAM constraints
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( SdrSize /= "00" )then
                iSlt0_1 <= Mapper0_ack;
            else
                iSlt0_1 <= '0';
            end if;
        end if;
    end process;

    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( ff_sdr_seq = "010" )then
                if( SdrSta(2) = '1' )then
                    if( SdrSta(0) = '0' )then
                        SdrDat <= (others => 'Z');
                    else
                        if( RstSeq(4 downto 3) /= "11" )then
                            SdrDat <= (others => '0');
                        elsif( VideoDLClk = '0' and wave_slot = '1' )then
                            SdrDat <= wave_wdat & wave_wdat;    -- OPL4 wave memory write
                        elsif( VideoDLClk = '0' )then
                            SdrDat <= dbo & dbo;                -- "101"(cpu write)
                        else
                            SdrDat <= VrmDbo & VrmDbo;          -- "111"(vdp write)
                        end if;
                    end if;
                end if;
            else
                SdrDat <= (others => 'Z');
            end if;
        end if;
    end process;

    -- CPU slot completion tracking (R800): row address at "000", column at "010",
    -- the slot is valid for an address only if CpuAdr was the same at both points
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( wave_slot = '1' )then
                null;                                                       -- OPL4 wave slot: not a cpu slot
            elsif( ff_sdr_seq = "000" )then
                sdr_slot_adr <= CpuAdr_r;
            end if;
            if( wave_slot = '1' )then
                null;
            elsif( ff_sdr_seq = "010" )then
                if( sdr_slot_adr = CpuAdr_r )then
                    sdr_slot_ok <= '1';
                else
                    sdr_slot_ok <= '0';
                end if;
                if( SdrSta = "101" and RstSeq(4 downto 3) = "11" )then        -- write cpu
                    if( sdr_slot_adr = CpuAdr_r )then
                        sdr_wr_ok <= '1';
                    else
                        sdr_wr_ok <= '0';
                    end if;
                    sdr_wr_adr <= CpuAdr_r;
                    sdr_wr_dat <= dbo;
                    sdr_rd_ok  <= '0';
                end if;
            end if;
            if( ff_sdr_seq = "101" and SdrSta = "100" and wave_slot = '0' )then  -- read cpu
                sdr_rd_adr <= sdr_slot_adr;
                sdr_rd_ok  <= sdr_slot_ok;
            end if;
        end if;
    end process;

    -- Data read latch for CPU
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( ff_sdr_seq = "101" )then
                if( SdrSta = "100" and wave_slot = '0' )then  -- read cpu (not in an OPL4 wave slot)
                    if( CpuAdr_r(0) = '0' )then
                        RamDbi <= pMemDat(  7 downto 0 );
                    else
                        RamDbi <= pMemDat( 15 downto 8 );
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Data read latch for VDP
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            if( ff_sdr_seq = "101" )then
                if( SdrSta = "110" )then                        -- read vdp
                    VrmDbi <= pMemDat( 15 downto 0 );
                end if;
            end if;
        end if;
    end process;

    -- SDRAM controller state
    process( memclk )
    begin
        if( memclk'event and memclk = '1' )then
            case ff_sdr_seq is
                when "000" =>
                    if( VideoDHClk = '1' or RstSeq(4 downto 3) /= "11" )then
                        ff_sdr_seq <= "001";
                    end if;
                when "111" =>
                    if( VideoDHClk = '0' or RstSeq(4 downto 3) /= "11" )then
                        ff_sdr_seq <= "000";
                    end if;
                when others =>
                    ff_sdr_seq <= ff_sdr_seq + 1;
            end case;
        end if;
    end process;

    process( reset, clk21m )
    begin
        if( reset = '1' )then
            RamAck <= '0';
        elsif( clk21m'event and clk21m = '1' )then
            if( RamReq = '0' )then
                RamAck <= '0';
            elsif( VideoDLClk = '0' and VideoDHClk = '1' and wave_slot = '0' )then     -- not in an OPL4 wave slot
                RamAck <= '1';
            end if;
            if( VideoDLClk = '0' )then
                vram_page <= vram_slot_ids;
            end if;
        end if;
    end process;

    pMemCke     <= '1';
    pMemCs_n    <= SdrCmd(3);
    pMemRas_n   <= SdrCmd(2);
    pMemCas_n   <= SdrCmd(1);
    pMemWe_n    <= SdrCmd(0);

    pMemUdq     <= SdrUdq;
    pMemLdq     <= SdrLdq;
    pMemBa1     <= SdrBa(1);
    pMemBa0     <= SdrBa(0);

    pMemAdr     <= SdrAdr;
    pMemDat     <= SdrDat;

    ----------------------------------------------------------------
    -- Reserved ports (USB)
    ----------------------------------------------------------------
--  pUsbP1      <= 'Z';
--  pUsbN1      <= 'Z';
    pUsbP2      <= 'Z';
    pUsbN2      <= 'Z';

    ----------------------------------------------------------------
    -- Connect components
    ----------------------------------------------------------------
--  U00 : pll4x
--      port map(
--          inclk0   => pClk21m,                -- 21.48MHz external
--          c0       => clk21m,                 -- 21.48MHz internal
--          c1       => memclk,                 -- 85.92MHz = 21.48MHz x 4
--          e0       => pMemClk                 -- 85.92MHz external
--      );

--    U00 : work.pll
--        port map(
--            inclk0   => pClk21m,
--            c0       => clk21m,                 -- 21.48MHz internal
--            c1       => memclk,                 -- 85.92MHz = 21.48MHz x 4
--            c2       => pMemClk,                -- 85.92MHz external
--            c3       => clk_hdmi_s              -- 107.40MHz = 21.48MHz x 5
--        );


    U01 : t80a
        port map(
            RESET_n     => (not reset),
            R800_mode   => '0',                 -- the Z80 (the R800 is U01_R8)
            CLK_n       => iCpuClk,
            WAIT_n      => wait_n_s,
            INT_n       => pSltInt_n,
            NMI_n       => '1',
            BUSRQ_n     => z80_busrq_n,
            M1_n        => CpuM1_n,
            MREQ_n      => pSltMerq_n,
            IORQ_n      => pSltIorq_n,
            RD_n        => pSltRd_n,
            WR_n        => pSltWr_n,
            RFSH_n      => CpuRfsh_n,
            HALT_n      => open,
            BUSAK_n     => z80_busak_n,
            A           => pSltAdr,
            D           => pSltDat
        );

    U02 : iplrom
        port map(clk21m, adr, RomDbi);

    U03 : megasd
        port map(
            clk21m      => clk21m              ,
            reset       => reset               ,
            req         => ErmReq              ,
            wrt         => wrt                 ,
            adr         => adr                 ,
            dbo         => dbo                 ,
            ramreq      => ErmRam              ,
            ramwrt      => ErmWrt              ,
            ramadr      => ErmAdr              ,
            mmcdbi      => MmcDbi              ,
            mmcena      => MmcEna              ,
            mmcact      => MmcAct              ,
            mmc_ck      => pSd_Ck              ,
            mmc_cs      => pSd_Dt(3)           ,
            mmc_di      => pSd_Cm              ,
            mmc_do      => pSd_Dt(0)           ,
            epc_ck      => EPC_CK              ,
            epc_cs      => EPC_CS              ,
            epc_oe      => EPC_OE              ,
            epc_di      => EPC_DI              ,
            epc_do      => EPC_DO              ,
            debug       => open
        );

    pSd_Dt(  2 downto 0 ) <= (others => 'Z');

--	 U04 : cyclone_asmiblock
--        port map(_CK, EPC_CS, EPC_DI, EPC_OE, EPC_DO);

    U05 : mapper
        port map(clk21m, reset, MapReq, open, mem, wrt, adr, MapDbi, dbo,
                        MapRam, MapWrt, MapAdr, RamDbi, open);

    U06_1 : eseps2
        port map(clk21m, reset, clkena, Kmap, Caps, Kana, Paus, Scro, Reso, Fkeys,
                        pPs2Clk, pPs2Dat, PpiPortC, w_PpiPortB, CmtScro);

    U06_2: eseps2mouse
    port map (
        clk21m          => clk21m          ,
        reset           => reset           ,
        clkena          => clkena          ,
        pPs2Clk         => pPs2Clk_m       ,
        pPs2Dat         => pPs2Dat_m       ,
        pJoyA_in        => pJoyA_in        ,
        pJoyA_out       => pJoyA_out       ,
        pStrA           => pStrA           ,
        pJoyA_in_m      => w_pJoyA_in_m    ,
        pJoyA_out_m     => w_pJoyA_out_m   ,
        pStrA_m         => w_pStrA_m       ,
        pLed            => w_pLed          ,
        pLedPwr         => w_pLedPwr       ,
        Slt2Mode        => Slot2Mode       ,
        Slt1Type        => Scc1Type        ,
        MstrVol         => MstrVol         ,
        OpllVol         => OpllVol         ,
        PsgVol          => PsgVol          ,
        tMegaSD         => tMegaSD         ,
        tPanaRedir      => tPanaRedir      ,
        SccVol          => SccVol          ,
        VdpSpeedMode    => VdpSpeedMode    ,
        CustomSpeed     => CustomSpeed     ,
        Af_mask         => Af_mask         ,
        V9938_n         => V9938_n         ,
        swioKmap        => swioKmap        ,
        caps            => Caps            ,
        kana            => Kana            ,
        iPsg2_ena       => iPsg2_ena       ,
        vga_scanlines   => vga_scanlines   ,
        clksel          => ff_clksel       ,
        extclk3m        => extclk3m        ,
        ntsc_pal_type   => ntsc_pal_type   ,
        forced_v_mode   => forced_v_mode   ,
        swioCmt         => swioCmt         ,
        iSlt1_linear    => iSlt1_linear    ,
        iSlt2_linear    => iSlt2_linear    ,
        right_inverse   => right_inverse   ,
        clksel5m_n      => ff_clksel5m_n
    );

    U07 : rtc
        port map(clk21m, '0', rtcena, RtcReq, open, wrt, adr, RtcDbi, dbo);

    U08 : kanji
        port map(clk21m, reset, KanReq, open, wrt, adr, KanDbi, dbo,
                        KanRom, KanAdr, RamDbi, open);

    U20 : vdp
        -- V9938 VDP core
--      port map(clk21m, reset, VdpReq, open, wrt, adr, VdpDbi, dbo, pVdpInt_n,
--                      open, WeVdp_n, VdpAdr, VrmDbi, VrmDbo,
--                      VideoR, VideoG, VideoB, VideoHS_n, VideoVS_n, VideoCS_n,
--                      VideoDHClk, VideoDLClk, open, open, Reso_v, ntsc_pal_type, forced_v_mode, legacy_vga);
        -- TH9958 VDP core
        port map(clk21m, reset, VdpReq, open, wrt, adr, VdpDbi, dbo, pVdpInt_n,
                        open, WeVdp_n, VdpAdr, VrmDbi, VrmDbo, VdpSpeedMode or (not hybridclk_n), RatioMode, centerYJK_R25_n,
                        VideoR, VideoG, VideoB, VideoHS_n, VideoVS_n, VideoCS_n,
                        VideoDHClk, VideoDLClk, BLANK_o, '0', ntsc_pal_type, forced_v_mode, legacy_vga, VDP_ID, OFFSET_Y,  -- V9968: always 15kHz, mist_video doubles
                        vdp_wait_n_s, vdp_busy);

    U21 : vencode
        port map(clk21m, reset, VideoR, VideoG, videoB, VideoHS_n, VideoVS_n,
                        videoY, videoC, videoV);

    U30_1 : msx_psg
        generic map(psg_ym_g)
        port map(clk21m, reset, clkena, PsgReq, open, wrt, adr, PsgDbi, dbo,
                        w_pJoyA_in, w_pJoyA_out_m, w_pStrA_m, w_pJoyB_in, pJoyB_out, pStrB, Kana, CmtIn, w_key_mode, PsgAmp);

    psg2_u : if use_dualpsg_g generate
        U30_2 : msx_psg
            generic map(psg_ym_g)
            port map(clk21m, reset, clkena, Psg2Req, open, wrt, adr, Psg2Dbi, dbo,
                            "111111", open, open, "111111", open, open, open, '0', '0', Psg2Amp);
    end generate;

    psg2_off : if not use_dualpsg_g generate
        Psg2Amp <= (others => '0');
    end generate;

    U31_1 : megaram
        port map(clk21m, reset, clkena, Scc1Req, Scc1Ack, wrt, adr, Scc1Dbi, dbo,
                        Scc1Ram, Scc1Wrt, Scc1Adr, RamDbi, open, Scc1Type, scc1_l, scc1_r, xmr_ena);

    Scc1Type <= Slot1Mode & "0";

    U31_2 : megaram
        port map(clk21m, reset, clkena, Scc2Req, Scc2Ack, wrt, adr, Scc2Dbi, dbo,
                        Scc2Ram, Scc2Wrt, Scc2Adr, RamDbi, open, Slot2Mode, scc2_l, scc2_r, xmr_ena);

    U32 : eseopll
        port map(clk21m, reset, clkena, OpllEnaWait, OpllReq, OpllAck, wrt, adr, dbo, OpllWav);
    -- OPLL wait enabler
    OpllEnaWait <= ff_clksel xnor ff_clksel5m_n;



    opll_o <= OpllWav;
	 -- unipolar PSG level (the mixer removes the DC): no offset, PSG and PSG2 at full resolution
	 -- (0..12285 each) and the key click at 2048, 16 bits so that the sum does not wrap
	 psg_o <=  ('0' & PsgAmp) + ('0' & Psg2Amp) + ("0000" & KeyClick & "00000000000");
	 PsgVol_o  <= PsgVol;
	 SccVol_o  <= SccVol;
	 OpllVol_o <= OpllVol;
	 vol_o <= MstrVol;
	 
    U34 : system_timer
        port map(
            clk21m  => clk21m       ,
            reset   => reset        ,
            req     => systim_req   ,
            ack     => open         ,
            wrt     => wrt          ,
            adr     => adr          ,
            dbi     => systim_dbi   ,
            dbo     => dbo
        );

    U35 : switched_io_ports
        generic map(
            use_wifi_g      => use_wifi_g
        )
        port map(
            clk21m          => clk21m           ,
            reset           => reset            ,
            power_on_reset  => power_on_reset   ,
            req             => swio_req         ,
            ack             => open             ,
            wrt             => wrt              ,
            adr             => adr              ,
            dbi             => swio_dbi         ,
            dbo             => dbo              ,

            io40_n          => io40_n           ,
            io41_id212_n    => io41_id212_n     ,
            io42_id212      => io42_id212       ,
            io43_id212      => io43_id212       ,
            io44_id212      => io44_id212       ,

            PsgVol          => PsgVol           ,
            MstrVol         => MstrVol          ,
            OpllVol         => OpllVol          ,
            SccVol          => SccVol           ,

            CustomSpeed     => CustomSpeed      ,
            tMegaSD         => tMegaSD          ,
            tPanaRedir      => tPanaRedir       ,
            VdpSpeedMode    => VdpSpeedMode     ,
            V9938_n         => V9938_n          ,
            Mapper_req      => Mapper_req       ,
            Mapper_ack      => Mapper_ack       ,
            MegaSD_req      => MegaSD_req       ,
            MegaSD_ack      => MegaSD_ack       ,

            io41_id008_n    => io41_id008_n     ,
            swioKmap        => swioKmap         ,
            CmtScro         => CmtScro          ,
            swioCmt         => swioCmt          ,
            LightsMode      => LightsMode       ,
            Red_sta         => Red_sta          ,
            LastRst_sta     => LastRst_sta      ,
            RstReq_sta      => RstReq_sta       ,
            Blink_ena       => Blink_ena        ,

            pseudoStereo    => pseudoStereo     ,
            extclk3m        => extclk3m         ,
            ntsc_pal_type   => ntsc_pal_type    ,
            forced_v_mode   => forced_v_mode    ,

            right_inverse   => right_inverse    ,
            RatioMode       => RatioMode        ,
            centerYJK_R25_n => centerYJK_R25_n  ,
            legacy_sel      => legacy_sel       ,
            iSlt1_linear    => iSlt1_linear     ,
            iSlt2_linear    => iSlt2_linear     ,

            btn_scan        => '1'              ,
            vga_scanlines   => vga_scanlines    ,
            iPsg2_ena       => iPsg2_ena        ,
            SdrSize         => SdrSize          ,
            bios_reload_ack => bios_reload_ack  ,
            Mapper0_req     => Mapper0_req      ,
            Slot0_req       => Slot0_req        ,

            xmr_ena         => xmr_ena          ,
            SdrSizeAux      => SdrSizeAux       ,
            OFFSET_Y        => OFFSET_Y         ,

            spMaxSpr        => spMaxSpr         ,
            vga_int_field   => vga_int_field    ,
            low_scale_n     => low_scale_n      ,
            cbios_mode      => cbios_mode       ,
            Mapper0_ack     => Mapper0_ack      ,
            Slot0Mode       => Slot0Mode        ,
            safe_mode       => safe_mode        ,
            portF2_ena      => portF2_ena       ,

            ff_dip_req      => ff_dip_req       ,
            ff_dip_ack      => ff_dip_ack       ,

            vram_slot_ids   => vram_slot_ids    ,
            DefKmap         => DefKmap          ,

            ff_ldbios_n     => ff_ldbios_n      ,
            VDP_ID          => VDP_ID           ,
            JIS2_ena        => JIS2_ena         ,
            portF4_mode     => portF4_mode      ,

            Scro            => Scro             ,
            ff_Scro         => ff_Scro          ,
            Reso            => Reso             ,
            ff_Reso         => ff_Reso          ,
            FKeys           => FKeys            ,
            vFKeys          => vFKeys           ,
            LevCtrl         => LevCtrl          ,
            GreenLvEna      => GreenLvEna       ,

            swioRESET_n     => swioRESET_n      ,
            warmRESET       => warmRESET        ,
            WarmMSXlogo     => WarmMSXlogo      ,
            full_reset_comb => '0'              ,   -- reset combinations handled below (comb_reset_n)
            cold_reset_comb => '0' 
        );

    U40 : tr_pcm
        port map(clk21m, reset, tr_pcm_req, open, wrt, adr(0), tr_pcm_dbi, dbo,
                        tr_pcm_wave_in, trPcm_o);

    -- turboR PCM sampler (microphone of the A1ST/GT): the 1-bit audio input (ear_i)
    tr_pcm_wave_in <= X"C0" when( ear_i = '1' )else X"40";

    -- OPL4 wave part (MoonSound, ZEMMIX-0au.3 / .6): srg320's YMF278B on clk_opl, its
    -- registers on 7E-7Fh, every C4-C7h access seen too (NEW2, LD2), wave memory in the SDRAM
    opl4_a  <= "0" & adr(1 downto 0)    when( adr(7) = '1' )else       -- C4-C7h -> 0-3
               "10" & adr(0);                                          -- 7E-7Fh -> 4-5
    opl4_cs <= '1' when( iSltIorq_n = '0' and opl3_enabled = '1' and use_opl4_g and
                         (adr(7 downto 2) = "110001" or adr(7 downto 1) = "0111111") )else '0';

    opl4_u : if use_opl4_g generate
        u_opl4 : opl4_wave
            port map(
                clk_bus     => clk21m,
                reset_bus   => reset,
                bus_cs      => opl4_cs,
                bus_a       => opl4_a,
                bus_di      => dbo,
                bus_rd_n    => xSltRd_n,
                bus_wr_n    => xSltWr_n,
                bus_do      => opl4_do,
                bus_status  => opl4_status,
                bus_wait_n  => opl4_wait_n,
                mem_req_t   => wt_req_t,
                mem_done_t  => wt_done_t,
                mem_we      => wt_we,
                mem_adr     => wt_adr,
                mem_wdat    => wt_wdat,
                mem_rdat    => wt_rdat,
                pcm_l       => opl4_l,
                pcm_r       => opl4_r,
                clk_eng     => clk_opl
            );
    end generate;

    opl4_off : if not use_opl4_g generate
        wt_req_t    <= '0';
        wt_we       <= '0';
        wt_adr      <= (others => '0');
        wt_wdat     <= (others => '0');
        opl4_l      <= (others => '0');
        opl4_r      <= (others => '0');
    end generate;

    -- ZEMMIX.ROM (YRW801, sent by the firmware when the core starts) to 000000h of
    -- the wave memory, through a FIFO: the SDRAM may not be ready yet (ZEMMIX-0au.5)
    u_romload : entity work.opl4_romload
        port map(
            clk21m      => clk21m,
            dl          => rom_dl_i,
            dl_wr       => rom_wr_i,
            dl_dat      => rom_dat_i,
            c_req_t     => wt_req_t,
            c_done_t    => wt_done_t,
            c_we        => wt_we,
            c_adr       => wt_adr,
            c_wdat      => wt_wdat,
            c_rdat      => wt_rdat,
            m_req_t     => wave_req_t,
            m_done_t    => wave_done_t,
            m_we        => wave_we,
            m_adr       => wave_adr,
            m_wdat      => wave_wdat,
            m_rdat      => wave_rdat,
            rcv_cnt     => romload_rcv,
            lost_cnt    => romload_lost,
            loading     => open
        );

    wifi : if use_wifi_g generate
        uwifi : work.wifi
            port map(
                clk_i       => clk21m,
                wait_o      => esp_wait_s,
                reset_i     => xSltRst_n,           -- swioRESET_n was purposely excluded here
                iorq_i      => iSltIorq_n,
                wrt_i       => xSltWr_n,
                rd_i        => xSltRd_n,
                tx_i        => esp_tx_i,
                rx_o        => esp_rx_o,
                adr_i       => adr,
                db_i        => dbo,
                db_o        => esp_dout_s
            );
    end generate;

--  esp_tx_i <= pUsbP1;
--  pUsbN1 <= esp_rx_o;

    midi : if use_midi_g generate
        umidi : work.midi
            port map(
                clk_i       => clk21m,
                reset_i     => (not reset),
                iorq_i      => iSltIorq_n,
                wrt_i       => xSltWr_n,
                rd_i        => xSltRd_n,
                tx_i        => midi_i,
                rx_o        => midi_o,              -- module output pin
                adr_i       => adr,
                db_i        => dbo,
                db_o        => midi_dout_s,
                tx_active_o => midi_active_o
            );
    end generate;

    opl3_u : if use_opl3_g and not opl3_fpga_g generate
        opl3_1 : opl3
        generic map(
            OPLCLK              => opl3_clk_g           -- opl_clk in Hz
        )
        port map(
            clk                 => clk21m,
            clk_opl             => clk_opl,             -- CLOCK_50 or memclk
            rst_n               => (not reset),
            irq_n               => opl3_Int_n,

            addr                => adr(1 downto 0),     -- OPL and OPL2 uses adr(0) only
            dout                => opl3_dout_s,
            din                 => dbo,
            we                  => opl3_ce,
            mono                => '0',

            sample_l            => opl3_l,
            sample_r            => opl3_r
        );
    end generate;

    opl3fpga_u : if use_opl3_g and opl3_fpga_g generate
        opl3fpga_1 : opl3fpga_msx
        generic map(
            OPLCLK              => opl3_clk_g           -- must be 50MHz (CLOCK_50)
        )
        port map(
            clk                 => clk21m,
            clk_opl             => clk_opl,
            rst_n               => (not reset),
            irq_n               => opl3_Int_n,

            addr                => adr(1 downto 0),
            dout                => opl3_dout_s,
            din                 => dbo,
            we                  => opl3_ce,
            mono                => '0',

            sample_l            => opl3_l,
            sample_r            => opl3_r
        );
    end generate;

    opl3_ce <= '1' when( adr(  7 downto 2 ) = "110001"  and iSltIorq_n = '0' and xSltWr_n = '0' and use_opl3_g )else    -- OPL3 ports C4-C7h (MoonSound FM)
--             '1' when( adr(  7 downto 1 ) = "0111110" and iSltIorq_n = '0' and xSltWr_n = '0' and use_opl3_g          -- OPLL ports 7C-7Dh via OPL3
               '0';

    -- Added by t.hara, 2021/Aug/6th
    u_autofire: autofire
    port map(
        clk21m              => clk21m,
        reset               => reset,
        count_en            => ff_clk21m_cnt(18),
        af_on_off_led       => af_on_off_led,
        af_on_off_toggle    => af_on_off_toggle,
        af_increment        => af_increment,
        af_decrement        => af_decrement,
        af_led_sta          => af_led_sta,
        af_mask             => af_mask,
        af_speed            => open
    );

    -- | b7    | b6    | b5   | b4   | b3  | b2  | b1  | b0  |
    -- | SHIFT | LCTRL | PgUp | PgDn | F9  | F10 | F11 | F12 |
    af_on_off_led    <=      vFkeys(7)  and vFkeys(6) and (vFkeys(5) xor Fkeys(5)); -- [LCTRL+SHIFT+PGUP]
    af_on_off_toggle <=      vFkeys(7)  and vFkeys(6) and (vFkeys(4) xor Fkeys(4)); -- [LCTRL+SHIFT+PGDOWN]
    af_increment     <= (not vFkeys(7)) and vFkeys(6) and (vFkeys(5) xor Fkeys(5)); -- [LCTRL+PGUP]
    af_decrement     <= (not vFkeys(7)) and vFkeys(6) and (vFkeys(4) xor Fkeys(4)); -- [LCTRL+PGDOWN]

    -- Joypad autofire
    w_pJoyA_in   <= w_pJoyA_in_m(5) & (w_pJoyA_in_m(4) or af_mask) & w_pJoyA_in_m( 3 downto 0 );
    w_pJoyB_in   <= pJoyB_in(    5) & (pJoyB_in(    4) or af_mask) & pJoyB_in(     3 downto 0 );

    -- Space key autofire
    PpiPortB     <= w_PpiPortB when( PpiPortC( 3 downto 0 ) /= "1000" )else
                    w_PpiPortB( 7 downto 1 ) & (w_PpiPortB(0) or af_mask);

    -- Cold Reset and Warm Reset combinations
    full_reset_comb  <=      vFkeys(7)  and vFkeys(6) and (vFkeys(0) xor Fkeys(0));     -- [LCTRL+SHIFT+F12]
    cold_reset_comb  <= (not vFkeys(7)) and vFkeys(6) and (vFkeys(0) xor Fkeys(0));     -- [LCTRL+F12]

    -- Reset combinations: a cold reset as before ocm-pld-dev v3.9.2, whatever
    -- the reset key lock of port $43 (bit 5, not initialized by the new
    -- switched_io_ports) and without OCM-BIOS reloading (the BIOS comes from
    -- the MiST / SiDi firmware here).
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            if( reset = '1' )then
                comb_reset_n <= '1';                                                    -- end of the reset pulse
            elsif( full_reset_comb = '1' or cold_reset_comb = '1' )then
                comb_reset_n <= '0';
            end if;
        end if;
    end process;

end RTL;