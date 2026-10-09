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

-- Raster generator: 15KHz NTSC (262 lines) or PAL (313 lines) video timing
-- like the 9918A / 9929A, 684 pixels per line at the 10.74MHz pixel clock
-- (half a VDP pixel each).  See f18a_video_pkg for the geometry.
--
-- The "counters" module has knowledge of the raster positions; any change
-- here must be considered there as well.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.f18a_video_pkg.all;

entity f18a_raster is
   port (
      vga_clk     : in  std_logic;       -- pixel clock, 10.74MHz
      rst_n       : in  std_logic;
      pal         : in  std_logic;       -- '1' = PAL, '0' = NTSC, read at the end of a frame
      hadj        : in  signed(0 to 4);  -- V9938 R18 set adjust: +n moves the picture n pixels left
      vadj        : in  signed(0 to 3);  --                       +n moves the picture n lines up
      interlace   : in  std_logic := '0'; -- V9938 R9 IL: the odd fields are half a line lower
      field       : out std_logic;       -- V9938 S#2 EO: toggles every frame, '1' = odd field
      frame_pal   : out std_logic;       -- standard in use
      hsync_n     : out std_logic;
      vsync_n     : out std_logic;
      csync_n     : out std_logic;       -- composite sync for RGB / SCART
      raster_x    : out unsigned(0 to 9);
      raster_y    : out unsigned(0 to 9);
      y_tick      : out std_logic;       -- last pixel of a line
      y_max       : out std_logic;       -- first line after the picture
      blank       : out std_logic
   );
end f18a_raster;

architecture rtl of f18a_raster is

   -- Horizontal and vertical counters.
   signal hcounter      : unsigned(0 to 9) := (others => '0');
   signal vcounter      : unsigned(0 to 9) := (others => '0');

   -- Frame geometry in use, only changed at the end of a frame.
   signal frame_pal_r   : std_logic := '0';
   signal vlast_r       : unsigned(0 to 9) := to_unsigned(GEOM_NTSC.vtotal - 1, 10);
   signal vsize_r       : unsigned(0 to 9) := to_unsigned(GEOM_NTSC.vsize, 10);

   signal hsync_first_s : unsigned(0 to 9);
   signal vsync_first_s : unsigned(0 to 9);
   signal hsync_r       : std_logic := '0';
   signal vsync_r       : std_logic := '0';
   signal blank_r       : std_logic := '1';
   signal field_r       : std_logic := '0';

begin

   process (vga_clk)
      procedure select_geometry is
      begin
         frame_pal_r <= pal;
         vlast_r <= to_unsigned(video_geom(pal).vtotal - 1, 10);
         vsize_r <= to_unsigned(video_geom(pal).vsize, 10);
      end procedure;
   begin
      if rising_edge(vga_clk) then
      if rst_n = '0' then
         hcounter <= (others => '0');
         vcounter <= (others => '0');
         select_geometry;
      else
         if hcounter = H_TOTAL - 1 then
            hcounter <= (others => '0');
            if vcounter = vlast_r then
               vcounter <= (others => '0');
               select_geometry;
               field_r <= not field_r;
            else
               vcounter <= vcounter + 1;
            end if;
         else
            hcounter <= hcounter + 1;
         end if;
      end if;
      end if;
   end process;

   -- The set adjust (V9938 R18) moves the picture against the syncs; the
   -- picture keeps its raster position and the syncs move the other way.
   hsync_first_s <= to_unsigned(H_SYNC_FIRST + 2 * to_integer(hadj), 10);
   vsync_first_s <= vsize_r + to_unsigned(V_BLANK_BEFORE_SYNC + 8, 10) + unsigned(resize(vadj, 10)) - 8;

   -- Syncs and blank, registered.  The vertical sync starts and ends with
   -- the horizontal sync pulse.
   process (vga_clk)
      variable hpos : integer range -H_TOTAL to 2 * H_TOTAL;
      variable vpos : integer range 0 to 2 * H_TOTAL;
      variable vline : integer range 0 to 1;
   begin if rising_edge(vga_clk) then
      -- Position in the hsync pulse, wrapping at the end of the line.
      hpos := to_integer(hcounter) - to_integer(hsync_first_s);
      if hpos < 0 then
         hpos := hpos + H_TOTAL;
      end if;
      if hpos < H_SYNC_END - H_SYNC_FIRST then
         hsync_r <= '1';
      else
         hsync_r <= '0';
      end if;

      -- Interlace: in the even fields the vertical sync starts and ends
      -- half a line later, so the odd fields show half a line lower.
      if interlace = '1' and field_r = '0' then
         vpos := to_integer(hsync_first_s) + H_TOTAL / 2;
         vline := 0;
         if vpos >= H_TOTAL then
            vpos := vpos - H_TOTAL;
            vline := 1;                    -- the half line point is in the next line
         end if;
      else
         vpos := to_integer(hsync_first_s);
         vline := 0;
      end if;
      if to_integer(hcounter) = vpos then
         if to_integer(vcounter) >= to_integer(vsync_first_s) + vline and
            to_integer(vcounter) < to_integer(vsync_first_s) + vline + V_SYNC_LINES then
            vsync_r <= '1';
         else
            vsync_r <= '0';
         end if;
      end if;

      -- Registered to prevent thin, top to bottom, vertical artifacts on
      -- the screen.
      if hcounter >= H_VISIBLE_FIRST and hcounter < H_VISIBLE_END and vcounter < vsize_r then
         blank_r <= '0';
      else
         blank_r <= '1';
      end if;
   end if; end process;

   hsync_n   <= not hsync_r;
   vsync_n   <= not vsync_r;
   -- Composite sync: hsync, inverted during vsync so the monitor keeps its
   -- horizontal lock.
   csync_n   <= not (hsync_r xor vsync_r);
   blank     <= blank_r;
   field     <= field_r;

   raster_x  <= hcounter;
   raster_y  <= vcounter;
   y_tick    <= '1' when hcounter = H_TOTAL - 1 else '0';
   y_max     <= '1' when vcounter = vsize_r else '0';
   frame_pal <= frame_pal_r;

end rtl;
