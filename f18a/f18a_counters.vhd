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

-- Counters for tile and sprite address generation.  Tightly bound to the
-- raster parameters (f18a_raster, f18a_video_pkg).


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;
use work.f18a_video_pkg.all;


entity f18a_counters is
   port (
      clk            : in std_logic;
      vga_clk        : in std_logic;
      rst_n          : in std_logic;            -- reset active low
      raster_x       : in unsigned(0 to 9);
      raster_y       : in unsigned(0 to 9);
      y_tick         : in std_logic;
      y_max          : in std_logic;
      frame_pal      : in std_logic;            -- PAL geometry in use, see f18a_video_pkg
      lines212       : in std_logic;            -- V9938 R9 LN: 212 active lines
      vscroll        : in unsigned(0 to 7);     -- V9938 R23 vertical scroll (0 for a 9918A)
      v9938          : in std_logic;            -- V9938 mode: text starts 9 pixels in, not 6
      hlow           : in unsigned(0 to 2) := "000";  -- V9958 R#27: background moved right, border at the left
      hmask          : in std_logic := '0';     -- V9958 R#25 MSK: the first 8 pixels are border
      sprt_yreal     : in std_logic;            -- 1 to use real sprite location, 0 for original off-by-one
      gmode          : in unsigned(0 to 3);
      row30          : in std_logic;            -- 1 when 30 rows
      blank_in       : in std_logic;            -- raster blanking signal in
      sl_blank       : out std_logic;           -- scan line blanking signal out
      intr_en        : out std_logic;           -- interrupt tick
      sp_cf_en       : out std_logic;           -- sprite collision flag tick
      scanline       : out unsigned(0 to 7);    -- current horz scan line location
      in_margin      : out std_logic;
      y_margin_n     : out std_logic;
      x_pixel_max    : out unsigned(0 to 8);    -- max pixel count
      x_pixel_pos    : out unsigned(0 to 8);    -- current x location for tiles
      x_sprt_pos     : out unsigned(0 to 7);    -- current x location for sprites
      y_next         : out unsigned(0 to 8);    -- next y location for tiles
      y_sprt_pos     : out unsigned(0 to 7);    -- next y location for sprites
      prescan_start  : out std_logic
   );
end f18a_counters;

architecture rtl of f18a_counters is

   -- Start and end points of the active area in raster pixels (half VDP
   -- pixels).  Anything outside of this area will be border color.
   -- Values are inclusive to the active area.

   -- 64 to 575 (256 VDP pixels), text mode 80 to 559 (240 VDP pixels)
   constant XSTART   : integer := 64;     -- X start
   -- The text modes (240 pixels) start 6 pixels into the 256 pixel area on
   -- the 9918A and 9 on the V9938 (openMSX VDP::getLeftSprites).  The
   -- original F18A used 8.
   constant XSTART2  : integer := 76;     -- X start for text mode (9918A)
   constant XSTART2V : integer := 82;     -- X start for text mode (V9938)
   constant XEND     : integer := 575;    -- X end
   constant XEND2    : integer := 555;    -- X end for text mode (9918A)
   constant XEND2V   : integer := 561;    -- X end for text mode (V9938)
   signal xstart2_s  : unsigned(0 to 9);

   -- 32/40 x 24 tiles = 256/240 x 192 VDP pixels = 512/480 x 192 raster pixels
   -- 0 to 47 (top 48px margin), 48 to 431 (384px), 432 to 479 (bottom 48px margin)
   -- The vertical positions depend on the geometry in use (NTSC / PAL),
   -- see f18a_video_pkg and the geometry signals below.


   -- Vertical positions for the raster geometry in use.
   signal ystart_s   : unsigned(0 to 9);  -- 192 line area
   signal yend_s     : unsigned(0 to 9);
   signal ystart2_s  : unsigned(0 to 9);  -- 240 line (30 row) area
   signal yend2_s    : unsigned(0 to 9);
   signal sl_reset1_s: unsigned(0 to 9);  -- 2 lines before each area
   signal sl_reset2_s: unsigned(0 to 9);

   -- Margin indicators
   signal xmargin    : std_logic;
   signal ymargin    : std_logic;

   signal xstart_mux : unsigned(0 to 9);
   signal xend_mux   : unsigned(0 to 9);
   signal ystart_mux : unsigned(0 to 9);
   signal yend_mux   : unsigned(0 to 9);

   signal margin_next: std_logic;
   signal margin_reg : std_logic;
   signal y_margin_reg : std_logic;

   signal row30reg   : std_logic;
   signal y_count_en : std_logic := '0';

   signal x_pixel_pos_reg  : unsigned(0 to 8);     -- current x location for tiles
   signal x_pixel_pos_next : unsigned(0 to 8);
   signal x_sprt_pos_reg   : unsigned(0 to 7);     -- current x location for sprites
   signal x_sprt_pos_next  : unsigned(0 to 7);

   -- Interrupt
   signal intr_ff       : std_logic;
   signal valid_y       : std_logic;
   signal valid_y_last  : std_logic;

   signal vga_clk_logic : std_logic := '0';
   signal vga_clk_last  : std_logic;
   signal sprt_cf_ff    : std_logic;

   -- X 1x-pixels
   signal x480 : unsigned(0 to 9);  -- text modes (8x6 tiles)
   signal x512 : unsigned(0 to 9);  -- graphics modes (8x8 tiles)
   signal x512s : unsigned(0 to 9); -- the same without the V9958 R#27 scroll (sprites)
   signal lborder_s : unsigned(0 to 6);  -- V9958 left border width (R#27 / MSK), raster pixels

   -- X 2x-pixels
   signal x240 : unsigned(0 to 7);
   signal x256 : unsigned(0 to 7);


   -- Y lines, counted from 2 lines before the area (first count is 1).
   signal y_count : unsigned(0 to 8) := (others => '0');

   -- Next VDP line (y_count - 1).
   signal y_half : unsigned(0 to 7);

   -- Scan line counter
   signal scanline_cnt     : unsigned(0 to 8) := (others => '0');
   signal scanline_reset   : std_logic;

begin

   -- Register row30 to allow more efficient routing.
   process (vga_clk) begin if rising_edge(vga_clk) then
      row30reg <= row30;
   end if; end process;

   -- Indexes for tile and sprite output line buffers.
   -- Tile index is 0 - 255 or 0 - 511 depending on the graphics mode.
   -- Keep the output x position at zero until the raster is in range
   -- to keep the line buffers on a zero index.  Otherwise the last
   -- few buffer tiles are being accessed and the propagation delay
   -- causes a thin line of the last pixel color to appear on the left
   -- edge of the margin-to-active area boundary.
   -- V9958 R#27: the background (not the sprites) moves hlow pixels right.
   x512 <= raster_x - XSTART - (hlow & '0');
   x512s <= raster_x - XSTART;
   xstart2_s <= to_unsigned(XSTART2V, 10) when v9938 = '1' else to_unsigned(XSTART2, 10);
   x480 <= raster_x - xstart2_s - (hlow & '0');
   x256 <= x512(1 to 8);
   x240 <= x480(1 to 8);
   x_pixel_max <=
      "011101111" when gmode = 1 else  -- 239 for text1 mode
      "111011111" when gmode = 9 else  -- 479 for text2 mode
      "111111111" when gmode > 9 else  -- 511 for 9938 modes
      "011111111";                     -- 255 for gm1, gm2, mcm

   x_pixel_pos_next <=
      x512(1 to 9) when gmode > 9 else    -- hi-res 1x pixel modes
      x480(1 to 9) when gmode = 9 else    -- text2 mode
      '0' & x240 when gmode = 1 else      -- text1 mode
      '0' & x256;                         -- gm1, gm2, mcm

   x_sprt_pos_next <= x512s(1 to 8);      -- sprites are always on a 0 to 255 grid, not scrolled

   process (vga_clk) begin if rising_edge(vga_clk) then
      if xmargin = '1' then
         x_pixel_pos_reg <= (others => '0');
         x_sprt_pos_reg <= (others => '0');
      else
         x_pixel_pos_reg <= x_pixel_pos_next;
         x_sprt_pos_reg <= x_sprt_pos_next;
      end if;
   end if; end process;

   x_pixel_pos <= x_pixel_pos_reg;
   x_sprt_pos <= x_sprt_pos_reg;


   -- Trigger the prescan for tiles and sprites.
   prescan_start <= '1' when raster_x = 1 and y_count_en = '1' else '0';

   -- Normalized Y counter.
   process (vga_clk)
   begin
      if rising_edge(vga_clk) then
         if y_max = '1' then
            -- Reset the counter to zero outside the active area.
            y_count <= (others => '0');
            y_count_en <= '0';
         elsif y_tick = '1' and (y_count_en = '1' or scanline_reset = '1') then
            y_count_en <= '1';
            y_count <= y_count + 1;
         end if;
      end if;
   end process;

   -- Vertical geometry.  Each area starts 2 lines after its scan line
   -- reset; when the 30 row area starts on line 0 or 1, the reset is at the
   -- end of the previous frame.
   process (frame_pal, lines212)
      variable g      : video_geom_t;
      variable ystart : integer;
      variable lines  : integer;
   begin
      g := video_geom(frame_pal);
      if lines212 = '1' then
         ystart := g.ystart - LINES_212_SHIFT;
         lines  := 212;
      else
         ystart := g.ystart;
         lines  := 192;
      end if;
      ystart_s    <= to_unsigned(ystart, 10);
      yend_s      <= to_unsigned(ystart + lines - 1, 10);
      ystart2_s   <= to_unsigned(g.ystart30, 10);
      yend2_s     <= to_unsigned(g.ystart30 + 239, 10);
      sl_reset1_s <= to_unsigned(ystart - 2, 10);
      if g.ystart30 >= 2 then
         sl_reset2_s <= to_unsigned(g.ystart30 - 2, 10);
      else
         sl_reset2_s <= to_unsigned(g.vtotal + g.ystart30 - 2, 10);
      end if;
   end process;

   -- One raster line per VDP line.  The tiles and sprites prepare the next
   -- line during the current one: on the line before the area y_count is 1
   -- and line 0 is prepared.  The V9938 vertical scroll (R23) moves the
   -- whole picture, wrapping at 256 lines.
   y_half <= resize(y_count - 1, 8) + vscroll;
   y_next <= '0' & y_half;

   -- Horizontal scan line output.
   scanline_reset <= '1' when
      (raster_y = sl_reset1_s and row30reg = '0') or
      (raster_y = sl_reset2_s and row30reg = '1') else '0';

   process (vga_clk) begin if rising_edge(vga_clk) then
      if raster_x = 1 then
         -- Reset 2 rasters before the visible area.
         if scanline_reset = '1' then
            scanline_cnt <= (others => '0');
         -- Stick at the max until reset.
         elsif scanline_cnt /= "111111111" then
            scanline_cnt <= scanline_cnt + 1;
         end if;
      end if;
   end if; end process;

   -- Current scan line, 1 on the first line of the area (as the original
   -- double scan F18A reported it).
   scanline <= resize(scanline_cnt - 1, 8);

   sl_blank <= blank_in;

   -- Sprites are always a 0 to 191 grid and 1 line behind the raster.
   -- Sprites are not affected by the scrolling.
   y_sprt_pos <= y_half - 1 when sprt_yreal = '0' else y_half;


   -- Indicate when the raster is in the margin.  The margin is NOT the
   -- same as the blanking area, which is controlled by the VGA controller.
   -- Mux the consistent data and slow changing data first, then feed
   -- the comparators below.
   process (gmode, row30reg, ystart_s, yend_s, ystart2_s, yend2_s, v9938) begin
      if gmode = 1 or gmode = 9 then
         if v9938 = '1' then
            xstart_mux <= to_unsigned(XSTART2V, 10);
            xend_mux <= to_unsigned(XEND2V, 10);
         else
            xstart_mux <= to_unsigned(XSTART2, 10);
            xend_mux <= to_unsigned(XEND2, 10);
         end if;
      else
         xstart_mux <= to_unsigned(XSTART, 10);
         xend_mux <= to_unsigned(XEND, 10);
      end if;

      if row30reg = '0' then
         ystart_mux <= ystart_s;
         yend_mux <= yend_s;
      else
         ystart_mux <= ystart2_s;
         yend_mux <= yend2_s;
      end if;
   end process;

   -- V9958: R#27 (or with MSK 8) pixels at the left are border, sprites too.
   lborder_s <= ("000" & hlow & '0') when hmask = '0' else to_unsigned(16, 7);
   margin_next <= '1' when
       raster_x < xstart_mux + lborder_s or raster_x > xend_mux or
       raster_y < ystart_mux or raster_y > yend_mux else '0';
   xmargin <= '1' when raster_x < xstart_mux or raster_x > xend_mux else '0';
   ymargin <= '1' when raster_y < ystart_mux or raster_y > yend_mux else '0';

   -- Register the margin indicator to prevent vertical lines in
   -- the output due to combinatorial logic switching noise.
   -- Switch at the VGA clock to match the 1-pixel delay in the
   -- color module.
   -- The y_margin_n signal is needed in the sprite module to prevent
   -- collision detection of off-screen sprites.
   process (vga_clk) begin if rising_edge(vga_clk) then
      margin_reg <= margin_next;
      y_margin_reg <= not ymargin;
   end if; end process;
   in_margin <= margin_reg;
   y_margin_n <= y_margin_reg;

   -- The VDP interrupt does NOT happen at vsync, it happens after the last
   -- line of the active display area.
   valid_y <= '1' when
      (raster_y = yend_s + 1 and row30reg = '0') or
      (raster_y = yend2_s + 1 and row30reg = '1')
      else '0';

   -- Interrupt edge detector for one clock tick.
   process (clk) begin if rising_edge(clk) then
      intr_ff <= '0';
      valid_y_last <= valid_y;

      if valid_y = '1' and valid_y_last = '0' then
         intr_ff <= '1';
      end if;
   end if; end process;

   intr_en <= intr_ff;


   --         __    __    __    __    __    __
   -- clk1 __|  |__|  |__|  |__|  |__|  |__|  |__
   --
   --         ___________             ___________
   -- clk2 __|           |___________|           |_
   --
   --               _____                   _____
   -- tick ________|     |_________________|     |_

   -- Convert the vga_clk (pixel clock) into logic so it can be used
   -- to make a core clock tick.
   process (vga_clk) begin
      if rising_edge(vga_clk) then
         -- This toggles at half the pixel clock, so both edges will be
         -- detected to restore the pixel clock.
         vga_clk_logic <= not vga_clk_logic;
      end if;
   end process;

   -- Sprite collisions are reported once per pixel.
   process (clk) begin if rising_edge(clk) then
      vga_clk_last <= vga_clk_logic;

      -- Make a one clock tick once per pixel clock.
      -- Transitions of the vga_clk_logic happen for every rising edge of vga_clk.
      sprt_cf_ff <= vga_clk_logic xor vga_clk_last;
   end if; end process;

   sp_cf_en <= sprt_cf_ff;

end rtl;
