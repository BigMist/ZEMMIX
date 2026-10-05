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

-- Version history.  See README.md for details.
--
--   V1.9 Dec 31, 2018
--   V1.8 Aug 24, 2016
--   V1.7 Jan  1, 2016
--   V1.6 May  3, 2014 .. Apr 26, 2015
--   V1.5 Jul 23, 2013
--   V1.4 Mar 20, 2013 .. Apr 26, 2013
--   V1.3 Jul 26, 2012, Release firmware

-- Main F18A core.
--   TODO:
--
--     Register mode_i and cd_i in the host-interface (CPU) module.
--
--     The host interface module needs to renamed and split up, it is too big.
--
--     Rewrite sprite layer and remove sprite linking.
--
--     Rewrite GPU module and fix memory interface to not block.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity f18a_core is
   generic (
      -- VRAM size: 14 = 16 KB (9918A), 17 = 128 KB (needed by the V9938 mode).
      VRAM_ABITS           : integer := 14
   );
   port (
      -- Clocks, phase aligned: the core clock is 8 times the pixel clock.
      -- 85.91MHz / 10.74MHz from 21.477MHz (x4 and /2) give 15.70KHz lines
      -- like the 9918A.
      clk_core_i           : in  std_logic;
      clk_pix_i            : in  std_logic;

      -- 9918A to Host System Interface
      reset_n_i            : in  std_logic;  -- Must be active for at least one pixel clock cycle
      mode_i               : in  std_logic;
      csw_n_i              : in  std_logic;
      csr_n_i              : in  std_logic;
      vr8_ignore_i         : in  std_logic;  -- '1' = ignore VR8+ writes when locked (V9938 hosts), '0' = mask like a 9918A
      v9938_i              : in  std_logic;  -- '1' = V9938 mode (static, needs VRAM_ABITS = 17)
      v9958_i              : in  std_logic := '0';  -- '1' = V9958 (static, with v9938_i = '1')
      mode1_i              : in  std_logic;  -- port address bit 1 (V9938 ports 9Ah / 9Bh), '0' for a 9918A
      int_n_o              : out std_logic;
      cd_i                 : in  std_logic_vector(0 to 7);
      cd_o                 : out std_logic_vector(0 to 7);

      -- 15KHz RGB Video Output, clk_pix_i domain
      pal_i                : in  std_logic;  -- '1' = PAL (313 lines, 50Hz), '0' = NTSC (262 lines, 60Hz)
      red_o                : out std_logic_vector(0 to 3);
      grn_o                : out std_logic_vector(0 to 3);
      blu_o                : out std_logic_vector(0 to 3);
      red8_o               : out std_logic_vector(0 to 7);  -- the same at 8 bits per channel
      grn8_o               : out std_logic_vector(0 to 7);
      blu8_o               : out std_logic_vector(0 to 7);
      hsync_n_o            : out std_logic;
      vsync_n_o            : out std_logic;
      csync_n_o            : out std_logic;  -- composite sync for RGB / SCART
      blank_o              : out std_logic;  -- '1' outside the picture (not display enable)
      r9_pal_o             : out std_logic;  -- V9938 mode: R#9 NT ('1' = PAL), to drive pal_i
      cmd_fast_i           : in  std_logic := '1';  -- V9938 command engine: '1' fast, '0' V9938 timing
      interlace_o          : out std_logic;  -- V9938 mode: R#9 IL (interlaced output)

      -- Feature Selection
      sprite_max_i         : in std_logic;   -- Default sprite max, '0' = 32, '1' = 4

      -- SPI to GPU
      spi_clk_o            : out std_logic;
      spi_cs_o             : out std_logic;
      spi_mosi_o           : out std_logic;
      spi_miso_i           : in  std_logic
   );
end f18a_core;

architecture rtl of f18a_core is

   function vr0_map(a : std_logic_vector(0 to 16); vr : std_logic) return std_logic_vector is
   begin
      if vr = '1' then
         return a;
      end if;
      return a(2 to 10) & a(10 to 16) & '1';
   end function;

   -- Output video registers.
   signal blank_r          : std_logic := '1';
   signal hsync_r          : std_logic := '1';
   signal vsync_r          : std_logic := '1';
   signal csync_r          : std_logic := '1';
   signal red_r, red_s     : std_logic_vector(0 to 7) := x"00";
   signal grn_r, grn_s     : std_logic_vector(0 to 7) := x"00";
   signal blu_r, blu_s     : std_logic_vector(0 to 7) := x"00";

   -- Video signals
   -- blank here is NOT the same as the soft_blank signal from the CPU I/O
   signal blank_s          : std_logic;                  -- raster blanking
   signal sl_blank_s       : std_logic;                  -- scan line blanking for GPU
   signal vsync_s          : std_logic;                  -- active low
   signal hsync_s          : std_logic;                  -- active low
   signal csync_s          : std_logic;                  -- active low
   signal raster_x_s       : unsigned(0 to 9);
   signal raster_y_s       : unsigned(0 to 9);
   signal y_tick_s         : std_logic;
   signal y_max_s          : std_logic;
   signal frame_pal_s      : std_logic;
   signal v38_lines212_s   : std_logic;                  -- V9938 display controls
   signal v38_r9_s         : std_logic_vector(0 to 7);
   signal v38_r8vr_s       : std_logic;                  -- R#8 VR
   signal v58_r25_s, v58_r26_s, v58_r27_s : std_logic_vector(0 to 7);   -- V9958, 0 otherwise
   signal t1horz_eff_s     : std_logic_vector(0 to 7);   -- tile scroll: F18A, or V9958 R#26
   signal v58_hs_s         : unsigned(0 to 4);
   signal v58_hlow_s       : unsigned(0 to 2);
   signal v58_multi_s      : std_logic;
   signal v38_nt_hi_s, v38_pg_hi_s, v38_ct_hi_s : std_logic_vector(0 to 2);
   signal v38_r4_s, v38_r10_s : std_logic_vector(0 to 7);
   signal cpu_vaddr_m_s, tile_vaddr_m_s, sprt_vaddr_m_s : std_logic_vector(0 to 16);
   signal field_s          : std_logic;                  -- S#2 EO
   -- V9938 cycle (21.477 MHz, 4 core clocks) in the line, for the command
   -- engine timing: two per raster pixel.
   signal rx_core_r        : unsigned(0 to 9) := (others => '0');
   signal cyc_phase_r      : unsigned(0 to 2) := (others => '0');
   signal cyc_r            : unsigned(10 downto 0) := (others => '0');
   signal cyc_tick_r       : std_logic := '0';
   signal v38_blink_raw_s  : std_logic;                  -- R#13 blink state
   signal page_odd_s       : std_logic;                  -- '0': show the even bitmap page
   signal bmp_r2_s         : std_logic_vector(0 to 7);
   signal v38_vscroll_s    : unsigned(0 to 7);
   signal v38_hadj_s       : signed(0 to 4);
   signal v38_vadj_s       : signed(0 to 3);
   signal v38_sp2_s        : std_logic;                  -- V9938 sprites
   signal v38_r5_s, v38_r6_s, v38_r11_s : std_logic_vector(0 to 7);
   signal v38_tp_s, v38_spd_s : std_logic;
   signal v38_bmp_s        : std_logic;                  -- V9938 bitmap modes
   signal v38_bmode_s      : std_logic_vector(0 to 1);
   signal v38_r2_s, v38_r7_s : std_logic_vector(0 to 7);
   signal v38_blink_s      : std_logic;
   signal v38_r12_s        : std_logic_vector(0 to 7);
   signal v38_g5_s         : std_logic;
   signal v38_g7_s         : std_logic;
   signal half_r           : std_logic := '0';           -- half pixel parity, aligned with x_pixel_pos
   signal v38_vr_s         : std_logic;                  -- V9938 S#2 VR / HR
   signal v38_hr_s         : std_logic;

   -- Counter signals
   signal in_margin_s      : std_logic;
   signal y_margin_n_s     : std_logic;
   signal x_pixel_max_s    : unsigned(0 to 8);
   signal x_pixel_pos_s    : unsigned(0 to 8);
   signal x_sprt_pos_s     : unsigned(0 to 7);
   signal sp_xact_s        : std_logic;                  -- raster in the 256 pixel area
   signal y_next_s         : unsigned(0 to 8);
   signal y_sprt_pos_s     : unsigned(0 to 7);
   signal prescan_start_s  : std_logic;
   signal sprite_start_s   : std_logic;

   -- Scroll support
   signal t1ntba_s         : std_logic_vector(0 to 3);   -- tile1 name table base address
   signal t1ctba_s         : std_logic_vector(0 to 7);   -- tile1 color table base address
   signal t1hsize_s        : std_logic;                  -- tile1 horz page size (1 page or 2 pages)
   signal t1vsize_s        : std_logic;                  -- tile1 vert page size (1 page or 2 pages)
   signal t1horz_s         : std_logic_vector(0 to 7);   -- tile1 horz scroll
   signal t1vert_s         : std_logic_vector(0 to 7);   -- tile1 vert scroll
   signal t2_en_s          : std_logic;                  -- tile2 enable
   signal t2_pri_en_s      : std_logic;                  -- tile2 priority enable (0 = TL2 always on top)
   signal t2ntba_s         : std_logic_vector(0 to 3);   -- tile2 name table base address
   signal t2ctba_s         : std_logic_vector(0 to 7);   -- tile2 color table base address
   signal t2hsize_s        : std_logic;                  -- tile2 horz page size (1 page or 2 pages)
   signal t2vsize_s        : std_logic;                  -- tile2 vert page size (1 page or 2 pages)
   signal t2horz_s         : std_logic_vector(0 to 7);   -- tile2 horz scroll
   signal t2vert_s         : std_logic_vector(0 to 7);   -- tile2 vert scroll

   -- Bitmap layer
   signal bmlba_s          : std_logic_vector(0 to 7);   -- bitmap layer base address
   signal bml_x_s          : std_logic_vector(0 to 7);
   signal bml_y_s          : std_logic_vector(0 to 7);
   signal bml_w_s          : std_logic_vector(0 to 7);
   signal bml_h_s          : std_logic_vector(0 to 7);
   signal bml_ps_s         : std_logic_vector(0 to 3);   -- bitmap layer palette select
   signal bml_en_s         : std_logic;                  -- '1' to enable the bitmap layer
   signal bml_pri_s        : std_logic;                  -- '1' when bitmap has priority over tiles
   signal bml_trans_s      : std_logic;                  -- '1' to set "00" pixels transparent
   signal bml_fat_s        : std_logic;

   -- Tile and sprite output
   signal tile_color_s     : std_logic_vector(0 to 7);
   signal tile_jk_s        : std_logic_vector(0 to 11);  -- V9958 YJK
   signal v58_yjk_s, v58_yae_s, v58_bogus_s : std_logic;
   signal sprt_color_s     : std_logic_vector(0 to 7);
   signal bg_color_s       : std_logic_vector(0 to 5);

   -- Color palette access
   signal col_we_s         : std_logic;
   signal col_addr_cpu_s   : std_logic_vector(0 to 5);
   signal col_din_s        : std_logic_vector(0 to 11);
   signal col_dout_s       : std_logic_vector(0 to 11);

   -- Color output
   signal tile_r_s         : std_logic_vector(0 to 7);
   signal tile_g_s         : std_logic_vector(0 to 7);
   signal tile_b_s         : std_logic_vector(0 to 7);

   signal show_bg          : std_logic;

   -- CPU outputs
   signal pgba_s           : std_logic_vector(0 to 2);
   signal gmode_s          : unsigned(0 to 3);
   signal textfg_s         : std_logic_vector(0 to 3);
   signal textbg_s         : std_logic_vector(0 to 3);

   signal unlocked_s       : std_logic;
   signal row30_s          : std_logic;
   signal tile_ecm_s       : unsigned(0 to 1);
   signal sprt_ecm_s       : unsigned(0 to 1);

   signal tl1_off_s        : std_logic;
   signal pos_attr_s       : std_logic;
   signal tpgsize_s        : std_logic_vector(0 to 1);
   signal spgsize_s        : std_logic_vector(0 to 1);

   signal tile_ps_s        : std_logic_vector(0 to 3);
   signal sprt_ps_s        : std_logic_vector(0 to 1);
   signal sprt_yreal_s     : std_logic;
   signal reportmax_s      : std_logic;

   signal soft_blank_s     : std_logic;
   signal size_bit_s       : std_logic;
   signal mag_bit_s        : std_logic;
   signal satba_s          : std_logic_vector(0 to 6);
   signal spgba_s          : std_logic_vector(0 to 2);
   signal sp_cf_s          : std_logic;
   signal sp_5s_s          : std_logic;
   signal sp_5th_s         : std_logic_vector(0 to 4);

   signal intr_en_s        : std_logic;
   signal sp_cf_en_s       : std_logic;
   signal scanline_s       : unsigned(0 to 7);
   signal vscanln_en_s     : std_logic;   -- Virtual scan line enable

   -- CPU to VRAM
   signal cpu_din_s        : std_logic_vector(0 to 7);
   signal cpu_we_s         : std_logic;
   signal cpu_addr_s       : std_logic_vector(0 to 16);
   signal cpu_dout_s       : std_logic_vector(0 to 7);

   -- Tile to VRAM
   signal tile_active_s    : std_logic;
   signal tile_addr_s      : std_logic_vector(0 to 16);
   signal tile_dout_s      : std_logic_vector(0 to 7);

   signal override_s       : std_logic;
   signal override_r_s     : std_logic_vector(0 to 3);
   signal override_g_s     : std_logic_vector(0 to 3);
   signal override_b_s     : std_logic_vector(0 to 3);

   -- Sprite to VRAM
   signal sprt_addr_s      : std_logic_vector(0 to 16);
   signal sprt_vaddr_s     : std_logic_vector(0 to 16);  -- physical


   -- Internal options
   signal stop_sprt_s      : unsigned(0 to 5);
   signal sprite_max_s     : unsigned(0 to 4);  -- From VDP register, do not confuse with sprite_max_r

   -- Register external inputs.
   signal reset_n_r        : std_logic := '1';
   signal pal_r            : std_logic := '0';
   signal sprite_max_r     : std_logic_vector(0 to 4) := "11111";

begin

   -- Register external inputs other than those associated with data (which
   -- are registered in the host interface).
   process (clk_core_i) begin
   if rising_edge(clk_core_i) then
      reset_n_r      <= reset_n_i;
      pal_r          <= pal_i;

      -- Select the power-on / reset default maximum number of sprites per line.
      -- The max sprites can also be changed after power-on via a VDP register.
      if sprite_max_i = '0' then
         sprite_max_r <= "11111";
      else
         sprite_max_r <= "00100";
      end if;
   end if; end process;


   -- Dual-port 16K VRAM
   inst_vram : entity work.f18a_vram
   generic map (
      ABITS          => VRAM_ABITS
   )
   port map (
      clk            => clk_core_i,
   -- CPU Interface
      cpu_din        => cpu_din_s,
      cpu_we         => cpu_we_s,
      cpu_addr       => cpu_vaddr_m_s(17 - VRAM_ABITS to 16),
      cpu_dout       => cpu_dout_s,
   -- Tile Interface
      tile_active    => tile_active_s,
      tile_addr      => tile_vaddr_m_s,
      tile_dout      => tile_dout_s,
   -- Sprite Interface
      sprt_addr      => sprt_vaddr_m_s
   );

   -- V9938 R#8 VR = 0 (16K chips): only A14-A0 count, and the VDP reaches
   -- the DRAM cells in another order.  The VRAM is kept in the VR = 1 order;
   -- a VR = 0 address goes to the cell 1 | A6-A0 << 1 | A14-A6 << 2 like
   -- openMSX VDPVRAM::swapAddr (A6 twice).
   cpu_vaddr_m_s  <= vr0_map(cpu_addr_s, v38_r8vr_s);
   tile_vaddr_m_s <= vr0_map(tile_addr_s, v38_r8vr_s);
   sprt_vaddr_m_s <= vr0_map(sprt_vaddr_s, v38_r8vr_s);


   -- Host CPU interface
   inst_cpu : entity work.f18a_cpu
   port map (
      clk            => clk_core_i,
      rst_n          => reset_n_r,
      mode           => mode_i,
      csw_n          => csw_n_i,
      csr_n          => csr_n_i,
      vr8_ignore     => vr8_ignore_i,
      v9938          => v9938_i,
      v9958          => v9958_i,
      mode1          => mode1_i,
      cd_i           => cd_i,
      cd_o           => cd_o,
      sp_cf          => sp_cf_s,
      sp_5s          => sp_5s_s,
      sp_5th         => sp_5th_s,
      intr_en        => intr_en_s,
      sp_cf_en       => sp_cf_en_s,
      sp_x           => x_sprt_pos_s,
      sp_xact        => sp_xact_s,
      scanline       => scanline_s,
      vscanln_en     => vscanln_en_s,     -- Virtual scan line enable
      blank          => sl_blank_s,
      vr             => v38_vr_s,
      hr             => v38_hr_s,
      v38_lines212   => v38_lines212_s,
      v38_r9         => v38_r9_s,
      v38_vr         => v38_r8vr_s,
      v38_r4         => v38_r4_s,
      v38_r10        => v38_r10_s,
      v58_r25        => v58_r25_s,
      v58_r26        => v58_r26_s,
      v58_r27        => v58_r27_s,
      v58_yjk        => v58_yjk_s,
      v58_yae        => v58_yae_s,
      v58_bogus      => v58_bogus_s,
      v38_vscroll    => v38_vscroll_s,
      v38_hadj       => v38_hadj_s,
      v38_vadj       => v38_vadj_s,
      v38_sp2        => v38_sp2_s,
      v38_r5         => v38_r5_s,
      v38_r6         => v38_r6_s,
      v38_r11        => v38_r11_s,
      v38_tp         => v38_tp_s,
      v38_spd        => v38_spd_s,
      v38_bmp        => v38_bmp_s,
      v38_bmode      => v38_bmode_s,
      v38_r2         => v38_r2_s,
      v38_r7         => v38_r7_s,
      v38_blink      => v38_blink_s,
      v38_blink_raw  => v38_blink_raw_s,
      v38_r12        => v38_r12_s,
      eo             => field_s,
      cmd_fast       => cmd_fast_i,
      cyc            => cyc_r,
      cyc_tick       => cyc_tick_r,
   -- VRAM Interface
      vdin           => cpu_dout_s,       -- In to CPU from *out* of VRAM
      vwe            => cpu_we_s,
      vaddr          => cpu_addr_s,
      vdout          => cpu_din_s,        -- Out from CPU goes *in* to VRAM
   -- PRAM Interface
      pwe            => col_we_s,
      paddr          => col_addr_cpu_s,
      pdout          => col_din_s,        -- Out from CPU goes *in* to PRAM
      pdin           => col_dout_s,       -- in to the GPU
   -- Outputs
      intr_n         => int_n_o,
      gmode          => gmode_s,
      soft_blank     => soft_blank_s,
      size_bit       => size_bit_s,
      mag_bit        => mag_bit_s,
      pgba           => pgba_s,
      satba          => satba_s,
      spgba          => spgba_s,
      textfg         => textfg_s,
      textbg         => textbg_s,
   -- F18A specific
      unlocked       => unlocked_s,
      row30          => row30_s,
      tl1_off_o      => tl1_off_s,        -- '1' to disable tile layer 1
      pos_attr_o     => pos_attr_s,       -- '1' to use position-based tile attributes
      tpgsize_o      => tpgsize_s,        -- tile pattern table offset size
      spgsize_o      => spgsize_s,        -- sprite pattern table offset size
      tile_ecm       => tile_ecm_s,
      sprt_ecm       => sprt_ecm_s,
      tile_ps        => tile_ps_s,
      sprt_ps        => sprt_ps_s,
      sprt_yreal     => sprt_yreal_s,
   -- Sprite max
      usr_sprite_max => sprite_max_r,     -- Jumper setting, used at reset
      sprite_max     => sprite_max_s,     -- Register setting overrides jumper
      stop_sprt      => stop_sprt_s,      -- Stop Sprite to limit sprite processing
      reportmax_o    => reportmax_s,      -- Report max sprite ('1') or 5th sprite ('0')
   -- Scroll support
      t1ntba         => t1ntba_s,         -- tile1 name table base address
      t1ctba         => t1ctba_s,         -- tile1 color table base address
      t1hsize        => t1hsize_s,        -- tile1 horz page size (1 page or 2 pages)
      t1vsize        => t1vsize_s,        -- tile1 vert page size (1 page or 2 pages)
      t1horz         => t1horz_s,         -- tile1 horz scroll
      t1vert         => t1vert_s,         -- tile1 vert scroll
      t2_en          => t2_en_s,          -- tile2 enable
      t2_pri_en      => t2_pri_en_s,      -- tile2 priority enable (0 = TL2 always on top)
      t2ntba         => t2ntba_s,         -- tile2 name table base address
      t2ctba         => t2ctba_s,         -- tile2 color table base address
      t2hsize        => t2hsize_s,        -- tile2 horz page size (1 page or 2 pages)
      t2vsize        => t2vsize_s,        -- tile2 vert page size (1 page or 2 pages)
      t2horz         => t2horz_s,         -- tile2 horz scroll
      t2vert         => t2vert_s,         -- tile2 vert scroll

   -- Bitmap layer
      bmlba          => bmlba_s,
      bml_x          => bml_x_s,
      bml_y          => bml_y_s,
      bml_w          => bml_w_s,
      bml_h          => bml_h_s,
      bml_ps         => bml_ps_s,
      bml_en         => bml_en_s,
      bml_pri        => bml_pri_s,
      bml_trans      => bml_trans_s,
      bml_fat_o      => bml_fat_s,
   -- SPI Interface
      spi_clk        => spi_clk_o,
      spi_cs         => spi_cs_o,
      spi_mosi       => spi_mosi_o,
      spi_miso       => spi_miso_i
   );


   -- Video controller
   inst_raster : entity work.f18a_raster
   port map (
      vga_clk        => clk_pix_i,
      rst_n          => reset_n_r,
      pal            => pal_r,
      hadj           => v38_hadj_s,
      vadj           => v38_vadj_s,
      interlace      => v38_r9_s(4),
      field          => field_s,
      frame_pal      => frame_pal_s,
      hsync_n        => hsync_s,
      vsync_n        => vsync_s,
      csync_n        => csync_s,
      raster_x       => raster_x_s,
      raster_y       => raster_y_s,
      y_tick         => y_tick_s,
      y_max          => y_max_s,
      blank          => blank_s
   );


   -- Video counters
   inst_counters : entity work.f18a_counters
   port map (
      clk            => clk_core_i,
      vga_clk        => clk_pix_i,
      rst_n          => reset_n_r,
      raster_x       => raster_x_s,
      raster_y       => raster_y_s,
      y_tick         => y_tick_s,
      y_max          => y_max_s,
      frame_pal      => frame_pal_s,
      lines212       => v38_lines212_s,
      vscroll        => v38_vscroll_s,
      v9938          => v9938_i,
      hlow           => v58_hlow_s,
      hmask          => v58_r25_s(6),
      sprt_yreal     => sprt_yreal_s,
      gmode          => gmode_s,
      row30          => row30_s,
      blank_in       => blank_s,          -- raster blank input
      sl_blank       => sl_blank_s,       -- Scan line blank output
      intr_en        => intr_en_s,
      sp_cf_en       => sp_cf_en_s,
      scanline       => scanline_s,
   -- Sprite and pixel counters
      in_margin      => in_margin_s,
      y_margin_n     => y_margin_n_s,
      x_pixel_max    => x_pixel_max_s,
      x_pixel_pos    => x_pixel_pos_s,
      x_sprt_pos     => x_sprt_pos_s,
      y_next         => y_next_s,
      y_sprt_pos     => y_sprt_pos_s,
      prescan_start  => prescan_start_s
   );


   -- Tile layer
   inst_tiles : entity work.f18a_tiles
      port map (
      clk            => clk_core_i,
      rst_n          => reset_n_r,
      x_pixel_max    => x_pixel_max_s,
      x_pixel_pos    => x_pixel_pos_s,
      y_next_in      => y_next_s,
      prescan_start  => prescan_start_s,
   -- Table base addresses
      pgba           => pgba_s,
      gmode          => gmode_s,
      row30          => row30_s,
      v9938          => v9938_i,
      bmp_en         => v38_bmp_s,
      bmp_mode       => v38_bmode_s,
      bmp_r2         => bmp_r2_s,
      bmp_hs         => v58_hs_s,
      v38_nt_hi      => v38_nt_hi_s,
      v38_pg_hi      => v38_pg_hi_s,
      v38_ct_hi      => v38_ct_hi_s,
      bmp_multi      => v58_multi_s,
      bmp_hp1        => v58_r26_s(2),
      bmp_tp         => v38_tp_s,
      textfg         => textfg_s,
      textbg         => textbg_s,
   -- F18A specific
      unlocked       => unlocked_s,
      ecm            => tile_ecm_s,
      tl1_off_i      => tl1_off_s,        -- '1' to disable tile layer 1
      pos_attr_i     => pos_attr_s,
      tpgsize_i      => tpgsize_s,        -- tile pattern table offset size
      tile_ps        => tile_ps_s,
   -- Scroll support
      t1ntba         => t1ntba_s,         -- tile1 name table base address
      t1ctba         => t1ctba_s,         -- tile1 color table base address
      t1hsize        => t1hsize_s,        -- tile1 horz page size (1 page or 2 pages)
      t1vsize        => t1vsize_s,        -- tile1 vert page size (1 page or 2 pages)
      t1horz         => t1horz_eff_s,     -- tile1 horz scroll (F18A, or V9958 R#26)
      t1vert         => t1vert_s,         -- tile1 vert scroll
      t2_en          => t2_en_s,          -- tile2 enable
      t2_pri_en      => t2_pri_en_s,      -- tile2 priority enable (0 = TL2 always on top)
      t2ntba         => t2ntba_s,         -- tile2 name table base address
      t2ctba         => t2ctba_s,         -- tile2 color table base address
      t2hsize        => t2hsize_s,        -- tile2 horz page size (1 page or 2 pages)
      t2vsize        => t2vsize_s,        -- tile2 vert page size (1 page or 2 pages)
      t2horz         => t2horz_s,         -- tile2 horz scroll
      t2vert         => t2vert_s,         -- tile2 vert scroll

   -- Bitmap layer
      bmlba          => bmlba_s,
      bml_x          => bml_x_s,
      bml_y          => bml_y_s,
      bml_w          => bml_w_s,
      bml_h          => bml_h_s,
      bml_ps         => bml_ps_s,
      bml_en         => bml_en_s,
      bml_pri        => bml_pri_s,
      bml_trans      => bml_trans_s,
      bml_fat_i      => bml_fat_s,
      blink_on       => v38_blink_s,
      v38_vscroll    => v38_vscroll_s,
      blink_fg       => v38_r12_s(0 to 3),
      blink_bg       => v38_r12_s(4 to 7),
   -- VRAM Interface
      tile_active    => tile_active_s,    -- 1 when tiles are active, otherwise 0
      vdin           => tile_dout_s,      -- In to Tile from *out* of VRAM
      vaddr          => tile_addr_s,
   -- Outputs
      sprite_start   => sprite_start_s,
      tile_color     => tile_color_s,
      tile_jk        => tile_jk_s
   );


   -- Sprite layer
   inst_sprites : entity work.f18a_sprites
   port map (
      clk            => clk_core_i,
      rst_n          => reset_n_r,
      x_sprt_pos     => x_sprt_pos_s,
      y_sprt_pos     => y_sprt_pos_s,
      y_next_in      => y_next_s,
      y_margin_n     => y_margin_n_s,
      prescan_start  => prescan_start_s,
      sprite_start   => sprite_start_s,
      sprite_max     => sprite_max_s,
      stop_sprt      => stop_sprt_s,
   -- Table base addresses
      size_bit       => size_bit_s,
      mag_bit        => mag_bit_s,
      satba          => satba_s,
      spgba          => spgba_s,
      gmode          => gmode_s,
   -- F18A specific
      unlocked       => unlocked_s,
      row30          => row30_s,
      spgsize_i      => spgsize_s,        -- sprite pattern table offset size
      sprt_ps        => sprt_ps_s,
      ecm            => sprt_ecm_s,
      v38            => v9938_i,
      v38_mode2      => v38_sp2_s,
      v38_r5         => v38_r5_s,
      v38_r6         => v38_r6_s,
      v38_r11        => v38_r11_s,
      v38_tp         => v38_tp_s,
      v38_spd        => v38_spd_s,
   -- VRAM Interface
      vdin           => tile_dout_s,      -- In to Sprite from *out* of VRAM
      vaddr          => sprt_addr_s,         -- logical
   -- Outputs
      sprt_color     => sprt_color_s,
      sprt_cf        => sp_cf_s,
      sprt_5s        => sp_5s_s,
      sprt_5th       => sp_5th_s,
      reportmax_i    => reportmax_s
   );


   -- Color RAM and output pixel selection
   inst_color : entity work.f18a_color
   port map (
      clk            => clk_core_i,
      vga_clk        => clk_pix_i,
      we1            => col_we_s,
      addr1          => col_addr_cpu_s,
      din            => col_din_s,
      dout1          => col_dout_s,       -- to the GPU! :-)
      tile_color     => tile_color_s,
      yjk            => v58_yjk_s,
      yae            => v58_yae_s,
      bogus          => v58_bogus_s,
      tp             => v38_tp_s,
      jk             => tile_jk_s,
      sprt_color     => sprt_color_s,
      bg_color       => bg_color_s,
      show_bg        => show_bg,
      g5             => v38_g5_s,
      g7             => v38_g7_s,
      g7_bg          => v38_r7_s,
      v9938          => v9938_i,
      half           => half_r,
      tile_r         => tile_r_s,
      tile_g         => tile_g_s,
      tile_b         => tile_b_s
   );


   -- Version ROM and banner generation
   inst_version : entity work.f18a_version
   port map (
      clk            => clk_core_i,
      rst_n_i        => reset_n_r,
      vga_clk        => clk_pix_i,
      intr_en_i      => intr_en_s,
      raster_x       => raster_x_s,
      raster_y       => raster_y_s,
      blank_i        => blank_s,
      -- outputs
      override_o     => override_s,
      red_o          => override_r_s,
      grn_o          => override_g_s,
      blu_o          => override_b_s
   );


   -- V9938 S#2: VR outside the active lines, HR outside the active pixels.
   v38_vr_s <= not y_margin_n_s;
   v38_hr_s <= in_margin_s and y_margin_n_s;

   -- Half pixel parity, aligned with x_pixel_pos (one pixel clock behind
   -- raster_x; the 256 pixel area starts on an even raster_x).
   process (clk_pix_i) begin if rising_edge(clk_pix_i) then
      half_r <= raster_x_s(9);
   end if; end process;
   r9_pal_o <= v38_r9_s(6);

   -- V9958 horizontal scroll: R#26 in 8 pixel steps (the F18A tile scroll in
   -- the character modes, the bitmap engine in G4-G7, none in the text
   -- modes), R#27 fine, R#25 SP2 two pages (odd page in R#2).
   v58_hs_s     <= unsigned(v58_r26_s(3 to 7));
   v58_hlow_s   <= unsigned(v58_r27_s(5 to 7));
   v58_multi_s  <= v58_r25_s(7) and v38_r2_s(2);

   -- V9938 character mode tables above 16 KB: address bits 16-14 from R#2
   -- (name), R#4 (pattern) and R#10 (color, T2 blink).
   v38_nt_hi_s  <= v38_r2_s(1 to 3) when v9938_i = '1' else "000";
   v38_pg_hi_s  <= v38_r4_s(2 to 4) when v9938_i = '1' else "000";
   v38_ct_hi_s  <= v38_r10_s(5 to 7) when v9938_i = '1' else "000";
   t1horz_eff_s <= v58_r26_s(3 to 7) & "000" when v9958_i = '1' and v38_bmp_s = '0' and
                   gmode_s /= 1 and gmode_s /= 9 else t1horz_s;
   sp_xact_s <= '1' when raster_x_s >= 64 and raster_x_s < 64 + 512 else '0';

   process (clk_core_i) begin if rising_edge(clk_core_i) then
      rx_core_r <= raster_x_s;
      if rx_core_r /= raster_x_s then
         cyc_phase_r <= (others => '0');
      else
         cyc_phase_r <= cyc_phase_r + 1;
      end if;
      cyc_r <= resize(raster_x_s, 10) & cyc_phase_r(0);
      if cyc_phase_r = 0 or cyc_phase_r = 4 then
         cyc_tick_r <= '1';
      else
         cyc_tick_r <= '0';
      end if;
   end if; end process;
   interlace_o <= v38_r9_s(4);

   -- Bitmap even / odd page (openMSX VDP::getEvenOddMask): the odd page bit
   -- of R#2 (line bit 8) is cleared when the R#9 EO alternation is on in an
   -- even field, or while the R#13 blink state is on.
   page_odd_s <= not ((v38_r9_s(5) and not field_s) or v38_blink_raw_s);
   bmp_r2_s <= v38_r2_s(0 to 1) & (v38_r2_s(2) and page_odd_s) & v38_r2_s(3 to 7);
   v38_g5_s <= '1' when v38_bmp_s = '1' and v38_bmode_s = "01" and v58_bogus_s = '0' else '0';
   v38_g7_s <= '1' when v38_bmp_s = '1' and v38_bmode_s = "11" and v58_yjk_s = '0' else '0';

   -- G6 / G7: the sprite tables are in the planar (rotated) VRAM too.
   sprt_vaddr_s <= sprt_addr_s(16) & sprt_addr_s(0 to 15) when v38_bmp_s = '1' and v38_bmode_s(0) = '1' else
                   sprt_addr_s;

   -- Use TL1 as the background color palette selector.  In G5 the border
   -- (and transparent color 0) alternates between R7 bits 3-2 and 1-0.
   bg_color_s <=
      "0000" & v38_r7_s(4 to 5) when v38_g5_s = '1' and half_r = '0' else
      "0000" & v38_r7_s(6 to 7) when v38_g5_s = '1' else
      (tile_ps_s(2 to 3) & textbg_s);

   -- soft_blank_s == VR1 blank bit and '0' means blank to background color
   show_bg <= in_margin_s or (not soft_blank_s);

   -- The simulated scan lines of the original double scan F18A (scanlines
   -- jumper and VR50 bit) have no effect at 15KHz.
   red_s <= override_r_s & override_r_s when override_s = '1' else tile_r_s;
   grn_s <= override_g_s & override_g_s when override_s = '1' else tile_g_s;
   blu_s <= override_b_s & override_b_s when override_s = '1' else tile_b_s;


   -- Register the video outputs.
   process (clk_pix_i) begin if rising_edge(clk_pix_i) then
      blank_r  <= blank_s;
      hsync_r  <= hsync_s;
      vsync_r  <= vsync_s;
      csync_r  <= csync_s;
      red_r    <= red_s;
      grn_r    <= grn_s;
      blu_r    <= blu_s;
   end if; end process;

   blank_o     <= blank_r;
   hsync_n_o   <= hsync_r;
   vsync_n_o   <= vsync_r;
   csync_n_o   <= csync_r;
   red_o       <= red_r(0 to 3);
   grn_o       <= grn_r(0 to 3);
   blu_o       <= blu_r(0 to 3);
   red8_o      <= red_r;
   grn8_o      <= grn_r;
   blu8_o      <= blu_r;

end rtl;
