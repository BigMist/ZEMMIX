--
-- F18A
--   A pin-compatible enhanced replacement for the TMS9918A VDP family.
--   https://dnotq.io
--

-- Released under the 3-Clause BSD License:
--
-- Copyright 2011-2018 Matthew Hagerty (matthew <at> dnotq <dot> io)
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
--
-- 2. Redistributions in binary form must reproduce the above copyright
-- notice, this list of conditions and the following disclaimer in the
-- documentation and/or other materials provided with the distribution.
--
-- 3. Neither the name of the copyright holder nor the names of its
-- contributors may be used to endorse or promote products derived from this
-- software without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
-- IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
-- ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.

-- Drop-in replacement for the ESE / OCM-PLD V9938/V9958 VDP (entity VDP in
-- esemsx3/src/video/vdp.vhd): same entity name, ports and port order, so a
-- core that instantiates that VDP can use the F18A instead by compiling this
-- file (and ocm/f18a_vdp_pll.v) in place of the src/video/vdp*.vhd files.
--
-- This is an interface wrapper only, no code from the ESE-VDP is used.
--
-- What is supported:
--
--  * I/O ports 98h (data) and 99h (control / status), as a TMS9918A with
--    the F18A extensions.  Ports 9Ah (palette) and 9Bh (indirect register)
--    are ignored, reads return FFh.
--  * Register writes to R#8 and above are ignored while the F18A is locked
--    (an MSX2 BIOS writes them), instead of being masked to R#0-7 like a
--    9918A.  R#57 still unlocks the F18A.
--  * R#9 bit 1 (NT) selects PAL / NTSC when NTSC_PAL_TYPE = '1', otherwise
--    FORCED_V_MODE does, like the original VDP.
--  * 15KHz RGB with HS, VS and CS (DISPRESO = '0') or 31KHz through a line
--    doubler (DISPRESO = '1'), 6-bit RGB, BLANK_O.
--  * PVIDEODHCLK / PVIDEODLCLK are generated exactly like the original VDP:
--    the OCM SDRAM controller uses them for the CPU / VDP time slots.
--
-- Not supported (the F18A is a 9918A, not a V9938): the V9938/V9958 modes
-- (G4-G7, T2, YJK), the command engine, 128KB VRAM, the 512 color palette,
-- sprite mode 2, R#18 adjust, R#23 scroll, line interrupts, interlace and
-- the status registers S#1-S#9.  The VRAM is inside the F18A, so the
-- external VRAM port is unused (PRAMWE_N and PRAMOE_N stay high).
--
-- These inputs are accepted and ignored: VDPSPEEDMODE, RATIOMODE,
-- CENTERYJK_R25_N, LEGACY_VGA, VGA_INT_FIELD, SPMAXSPR, VDP_ID, OFFSET_Y.
--
-- Clocks: the F18A runs at 85.91MHz (core) and 10.74MHz (pixel) from a PLL
-- on CLK21M (21.477MHz * 4 and / 2), so its 15KHz line is exactly 1368
-- CLK21M cycles like the V9938 and its outputs are aligned to CLK21M.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vdp is
   generic (
      -- '1' = V9938 (MSX2): R#0-R#46, ports 9Ah / 9Bh, 128 KB VRAM in
      -- internal RAM (128 M9K).  '0' = TMS9918A + F18A, 16 KB.
      V9938             : std_logic := '1';
      -- '1' = V9958 (MSX2+, with V9938 = '1'): YJK, horizontal scroll,
      -- commands in every mode, S#1 ID 2.
      V9958             : std_logic := '1'
   );
   port (
      -- VDP clock ... 21.477MHz
      clk21m            : in  std_logic;
      reset             : in  std_logic;
      req               : in  std_logic;
      ack               : out std_logic;
      wrt               : in  std_logic;
      adr               : in  std_logic_vector(15 downto 0);
      dbi               : out std_logic_vector( 7 downto 0);
      dbo               : in  std_logic_vector( 7 downto 0);

      int_n             : out std_logic;

      pramoe_n          : out std_logic;
      pramwe_n          : out std_logic;
      pramadr           : out std_logic_vector(16 downto 0);
      pramdbi           : in  std_logic_vector(15 downto 0);
      pramdbo           : out std_logic_vector( 7 downto 0);

      vdpspeedmode      : in  std_logic;
      ratiomode         : in  std_logic_vector( 2 downto 0);
      centeryjk_r25_n   : in  std_logic;

      -- Video output
      pvideor           : out std_logic_vector( 5 downto 0);
      pvideog           : out std_logic_vector( 5 downto 0);
      pvideob           : out std_logic_vector( 5 downto 0);

      pvideohs_n        : out std_logic;
      pvideovs_n        : out std_logic;
      pvideocs_n        : out std_logic;

      pvideodhclk       : out std_logic;
      pvideodlclk       : out std_logic;

      blank_o           : out std_logic;
      interlacemode     : out std_logic;

      -- Display resolution (0=15KHz, 1=31KHz)
      dispreso          : in  std_logic;

      ntsc_pal_type     : in  std_logic;
      forced_v_mode     : in  std_logic;
      legacy_vga        : in  std_logic;
      vga_int_field     : in  std_logic := '0';   -- default: older emsx_top (ZEMMIX) has no such port

      spmaxspr          : in  std_logic := '0';   -- default: older emsx_top (ZEMMIX) has no such port

      vdp_id            : in  std_logic_vector( 4 downto 0);
      offset_y          : in  std_logic_vector( 6 downto 0)
   );
end vdp;

architecture rtl of vdp is

   component f18a_vdp_pll is
      port (
         clk_21m        : in  std_logic;
         clk_core       : out std_logic;
         clk_pix        : out std_logic;
         locked         : out std_logic
      );
   end component;

   -- F18A clocks.
   signal clk_core_s    : std_logic;
   signal clk_pix_s     : std_logic;
   signal pll_locked_s  : std_logic;
   signal f18a_rst_n_s  : std_logic;

   -- Dot clock outputs for the OCM SDRAM controller.
   signal dotstate_r    : std_logic_vector(1 downto 0) := "00";
   signal dhclk_r       : std_logic := '0';
   signal dlclk_r       : std_logic := '0';

   -- Host bus bridge, CLK21M domain.  Each access becomes a 9918A strobe
   -- of STROBE_CLKS cycles (186ns); the F18A synchronizes it to 100MHz.
   constant STROBE_CLKS : integer := 4;
   signal busy_r        : std_logic := '0';
   signal strobe_cnt_r  : integer range 0 to STROBE_CLKS := 0;
   signal rd_r          : std_logic := '0';
   signal mode_r        : std_logic := '0';
   signal mode1_r       : std_logic := '0';              -- ports 9Ah / 9Bh
   signal csw_n_r       : std_logic := '1';
   signal csr_n_r       : std_logic := '1';
   signal cd_r          : std_logic_vector(7 downto 0) := (others => '0');
   signal dbi_r         : std_logic_vector(7 downto 0) := (others => '1');
   signal ack_r         : std_logic := '0';
   signal cd_o_s        : std_logic_vector(0 to 7);

   -- Control port tracking for R#9 (PAL / NTSC).
   signal ctrl_ff_r     : std_logic := '0';
   signal ctrl_1st_r    : std_logic_vector(7 downto 0) := (others => '0');
   signal r9_pal_r      : std_logic := '0';
   signal pal_s         : std_logic;
   signal r9_pal_core_s : std_logic;
   signal interlace_s   : std_logic;

   -- Interrupt synchronizer.
   signal int_n_s       : std_logic;
   signal int_sync_r    : std_logic_vector(1 downto 0) := "11";

   -- 15KHz video from the F18A, registered in the CLK21M domain.
   signal red15_s, grn15_s, blu15_s : std_logic_vector(0 to 7);   -- 8 bits, 6 are used
   signal hs15_n_s, vs15_n_s, cs15_n_s, blank15_s : std_logic;
   signal rgb15_r       : std_logic_vector(17 downto 0) := (others => '0');
   signal hs15_n_r      : std_logic := '1';
   signal vs15_n_r      : std_logic := '1';
   signal cs15_n_r      : std_logic := '1';
   signal blank15_r     : std_logic := '1';

   -- 31KHz line doubler.  Every 15KHz line has 684 half pixels of two
   -- CLK21M cycles; it is written at half rate and read twice at full rate.
   constant HALF_PX     : integer := 684;
   constant HS31_CLKS   : integer := 52;             -- half of the 15KHz hsync
   type line_t is array (0 to 2 * 1024 - 1) of std_logic_vector(18 downto 0);
   signal linebuf       : line_t := (others => (others => '0'));
   signal in_x_r        : unsigned(10 downto 0) := (others => '0');
   signal in_bank_r     : std_logic := '0';
   signal out_x_r       : unsigned(9 downto 0) := (others => '0');
   signal hs15_d_r      : std_logic := '1';
   signal vs31_r        : std_logic := '1';
   signal rd31_r        : std_logic_vector(18 downto 0) := (others => '0');
   signal hs31_n_r      : std_logic := '1';
   signal hs31_n_d_r    : std_logic := '1';
   signal vs31_d_r      : std_logic := '1';

   -- Video outputs.
   signal vid_rgb_r     : std_logic_vector(17 downto 0) := (others => '0');
   signal vid_hs_n_r    : std_logic := '1';
   signal vid_vs_n_r    : std_logic := '1';
   signal vid_cs_n_r    : std_logic := '1';
   signal vid_blank_r   : std_logic := '1';

   function vram_abits(v : std_logic) return integer is
   begin
      if v = '1' then return 17; else return 14; end if;
   end function;

begin

   --
   -- F18A
   --

   pll_inst : f18a_vdp_pll
   port map (
      clk_21m        => clk21m,
      clk_core       => clk_core_s,
      clk_pix        => clk_pix_s,
      locked         => pll_locked_s
   );

   f18a_rst_n_s <= (not reset) and pll_locked_s;

   -- PAL / NTSC selection as in the original VDP: R#9 NT (from the core in
   -- V9938 mode, any write path; from the 99h writes in 9918A mode) when
   -- NTSC_PAL_TYPE = '1', otherwise FORCED_V_MODE.
   pal_s <=
      forced_v_mode when ntsc_pal_type = '0' else
      r9_pal_core_s when V9938 = '1' else
      r9_pal_r;

   inst_f18a : entity work.f18a_core
   generic map (
      VRAM_ABITS     => vram_abits(V9938)
   )
   port map (
      clk_core_i     => clk_core_s,
      clk_pix_i      => clk_pix_s,
      reset_n_i      => f18a_rst_n_s,
      mode_i         => mode_r,
      csw_n_i        => csw_n_r,
      csr_n_i        => csr_n_r,
      vr8_ignore_i   => '1',
      v9938_i        => V9938,
      v9958_i        => V9958,
      mode1_i        => mode1_r,
      int_n_o        => int_n_s,
      cd_i           => cd_r,
      cd_o           => cd_o_s,
      pal_i          => pal_s,
      red_o          => open,
      grn_o          => open,
      blu_o          => open,
      red8_o         => red15_s,
      grn8_o         => grn15_s,
      blu8_o         => blu15_s,
      hsync_n_o      => hs15_n_s,
      vsync_n_o      => vs15_n_s,
      csync_n_o      => cs15_n_s,
      blank_o        => blank15_s,
      r9_pal_o       => r9_pal_core_s,
      cmd_fast_i     => vdpspeedmode,   -- '0': V9938 command timing, '1': fast
      interlace_o    => interlace_s,
      sprite_max_i   => '0',            -- 32 sprites per line, F18A default
      spi_clk_o      => open,
      spi_cs_o       => open,
      spi_mosi_o     => open,
      spi_miso_i     => '1'
   );


   --
   -- Dot clocks, same sequence as the original VDP (ssg): a 4 phase
   -- 21.477MHz / 4 cycle, DH = 10.74MHz, DL = 5.37MHz.
   --

   process (reset, clk21m) begin
      if reset = '1' then
         dotstate_r <= "00";
         dhclk_r    <= '0';
         dlclk_r    <= '0';
      elsif rising_edge(clk21m) then
         case dotstate_r is
         when "00"   => dotstate_r <= "01"; dhclk_r <= '0'; dlclk_r <= '1';
         when "01"   => dotstate_r <= "11"; dhclk_r <= '1'; dlclk_r <= '0';
         when "11"   => dotstate_r <= "10"; dhclk_r <= '0'; dlclk_r <= '0';
         when others => dotstate_r <= "00"; dhclk_r <= '1'; dlclk_r <= '1';
         end case;
      end if;
   end process;

   pvideodhclk <= dhclk_r;
   pvideodlclk <= dlclk_r;


   --
   -- Host bus bridge
   --

   process (reset, clk21m) begin
      if reset = '1' then
         busy_r      <= '0';
         strobe_cnt_r <= 0;
         csw_n_r     <= '1';
         csr_n_r     <= '1';
         dbi_r       <= (others => '1');
         ack_r       <= '0';
         ctrl_ff_r   <= '0';
         r9_pal_r    <= '0';
      elsif rising_edge(clk21m) then
         ack_r <= req;

         if busy_r = '1' then
            if strobe_cnt_r = STROBE_CLKS then
               -- End of the strobe: the read data has been valid for a while.
               if rd_r = '1' then
                  dbi_r <= cd_o_s;
               end if;
               csw_n_r <= '1';
               csr_n_r <= '1';
               busy_r  <= '0';
            else
               strobe_cnt_r <= strobe_cnt_r + 1;
            end if;

         elsif req = '1' then
            if adr(1) = '0' or V9938 = '1' then
               -- Port 98h (data) or 99h (control / status), and in V9938
               -- mode 9Ah (palette) and 9Bh (indirect register).
               busy_r       <= '1';
               strobe_cnt_r <= 1;
               rd_r         <= not wrt;
               mode_r       <= adr(0);
               mode1_r      <= adr(1);
               cd_r         <= dbo;
               csw_n_r      <= not wrt;
               csr_n_r      <= wrt;

               -- Follow the control port byte order to see R#9 writes.
               -- Any data port access or a status read resets it, as in
               -- the 9918A.
               if adr(1) = '0' and adr(0) = '1' and wrt = '1' then
                  if ctrl_ff_r = '0' then
                     ctrl_1st_r <= dbo;
                     ctrl_ff_r  <= '1';
                  else
                     ctrl_ff_r  <= '0';
                     if dbo = x"89" then          -- register write, R#9
                        r9_pal_r <= ctrl_1st_r(1);
                     end if;
                  end if;
               else
                  ctrl_ff_r <= '0';
               end if;
            elsif wrt = '0' then
               -- Ports 9Ah and 9Bh are write only on the V9938.
               dbi_r <= (others => '1');
            end if;
         end if;
      end if;
   end process;

   ack <= ack_r;
   dbi <= dbi_r;


   -- Interrupt, synchronized to CLK21M.
   process (clk21m) begin
      if rising_edge(clk21m) then
         int_sync_r <= int_sync_r(0) & int_n_s;
      end if;
   end process;

   int_n <= int_sync_r(1);


   -- External VRAM port unused.
   pramoe_n <= '1';
   pramwe_n <= '1';
   pramadr  <= (others => '0');
   pramdbo  <= (others => '0');

   interlacemode <= interlace_s;


   --
   -- Video
   --

   -- 15KHz video into the CLK21M domain.  The F18A pixel clock is CLK21M / 2
   -- from the PLL, so every pixel (half a VDP pixel) lasts exactly two
   -- CLK21M cycles (1368 per line).
   process (clk21m) begin
      if rising_edge(clk21m) then
         rgb15_r   <= red15_s(0 to 5) & grn15_s(0 to 5) & blu15_s(0 to 5);
         hs15_n_r  <= hs15_n_s;
         vs15_n_r  <= vs15_n_s;
         cs15_n_r  <= cs15_n_s;
         blank15_r <= blank15_s;
      end if;
   end process;

   -- 31KHz line doubler.
   process (clk21m) begin
      if rising_edge(clk21m) then
         hs15_d_r <= hs15_n_r;

         -- Input: restart at the 15KHz hsync, store every second sample.
         if hs15_d_r = '1' and hs15_n_r = '0' then
            in_x_r    <= (others => '0');
            in_bank_r <= not in_bank_r;
            vs31_r    <= vs15_n_r;
         elsif in_x_r /= 2047 then
            in_x_r <= in_x_r + 1;
         end if;

         if in_x_r(0) = '0' and in_x_r < 2 * HALF_PX then
            linebuf(to_integer(in_bank_r & in_x_r(10 downto 1))) <= blank15_r & rgb15_r;
         end if;

         -- Output: two lines per input line from the previous input line.
         if (hs15_d_r = '1' and hs15_n_r = '0') or out_x_r = HALF_PX - 1 then
            out_x_r <= (others => '0');
         else
            out_x_r <= out_x_r + 1;
         end if;

         rd31_r <= linebuf(to_integer((not in_bank_r) & out_x_r));

         if out_x_r < HS31_CLKS then
            hs31_n_r <= '0';
         else
            hs31_n_r <= '1';
         end if;
         hs31_n_d_r <= hs31_n_r;
         vs31_d_r   <= vs31_r;
      end if;
   end process;

   -- Output selection.
   process (clk21m) begin
      if rising_edge(clk21m) then
         if dispreso = '0' then
            vid_rgb_r   <= rgb15_r;
            vid_blank_r <= blank15_r;
            vid_hs_n_r  <= hs15_n_r;
            vid_vs_n_r  <= vs15_n_r;
            vid_cs_n_r  <= cs15_n_r;
         else
            if rd31_r(18) = '1' then
               vid_rgb_r <= (others => '0');
            else
               vid_rgb_r <= rd31_r(17 downto 0);
            end if;
            vid_blank_r <= rd31_r(18);
            vid_hs_n_r  <= hs31_n_d_r;
            vid_vs_n_r  <= vs31_d_r;
            vid_cs_n_r  <= not ((not hs31_n_d_r) xor (not vs31_d_r));
         end if;
      end if;
   end process;

   pvideor    <= vid_rgb_r(17 downto 12);
   pvideog    <= vid_rgb_r(11 downto  6);
   pvideob    <= vid_rgb_r( 5 downto  0);
   pvideohs_n <= vid_hs_n_r;
   pvideovs_n <= vid_vs_n_r;
   pvideocs_n <= vid_cs_n_r;
   blank_o    <= vid_blank_r;

end rtl;
