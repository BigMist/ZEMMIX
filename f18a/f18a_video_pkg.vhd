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

-- Video timing geometry, in one place.
--
-- The F18A generates 15KHz video like the 9918A (NTSC) and 9929A (PAL):
-- one raster line per VDP line, 684 raster pixels per line, each raster
-- pixel is half a VDP pixel (a 10.74MHz pixel clock, 63.69us lines).
--
-- Horizontal (raster pixels, raster_x):
--
--    0 ..  38   back porch (the 9918A color burst is here)
--   39 ..  63   left border    (13 VDP pixels with the 1 pixel output delay)
--   64 .. 575   active area    (256 VDP pixels, text modes 80 .. 559)
--  576 .. 606   right border   (15 VDP pixels)
--  607 .. 622   front porch    (8 VDP pixels)
--  623 .. 674   hsync          (26 VDP pixels)
--  675 .. 683   back porch
--
-- Vertical (lines):
--                    NTSC 9918A      PAL 9929A
--   top border       27              51
--   active           192             192
--   bottom border    24              51
--   blank            3               3
--   vsync            3               3
--   blank            13              13
--   total            262 (59.9Hz)    313 (50.2Hz)

library ieee;
use ieee.std_logic_1164.all;

package f18a_video_pkg is

   -- Horizontal geometry, raster pixels.
   constant H_TOTAL        : integer := 684;
   constant H_VISIBLE_FIRST: integer := 39;     -- first raster_x with picture
   constant H_VISIBLE_END  : integer := 607;    -- first raster_x after the picture
   constant H_SYNC_FIRST   : integer := 623;
   constant H_SYNC_END     : integer := 675;

   type video_geom_t is record
      vtotal   : integer;  -- lines per frame
      vsize    : integer;  -- lines with picture (border + active)
      ystart   : integer;  -- first line of the 192-line VDP area
      ystart30 : integer;  -- first line of the 240-line (30 row) area
   end record;

   constant GEOM_NTSC : video_geom_t := (
      vtotal => 262, vsize => 243, ystart => 27, ystart30 => 1);

   constant GEOM_PAL  : video_geom_t := (
      vtotal => 313, vsize => 294, ystart => 51, ystart30 => 27);

   -- V9938 212-line mode (R9 LN): the active area grows 10 lines up and 10
   -- down, the borders shrink (openMSX VDP::execLineCountReset).
   constant LINES_212_SHIFT     : integer := 10;

   -- Vertical sync, lines after the picture.
   constant V_BLANK_BEFORE_SYNC : integer := 3;
   constant V_SYNC_LINES        : integer := 3;

   function video_geom(pal : std_logic) return video_geom_t;

end package;

package body f18a_video_pkg is

   function video_geom(pal : std_logic) return video_geom_t is
   begin
      if pal = '1' then
         return GEOM_PAL;
      else
         return GEOM_NTSC;
      end if;
   end function;

end package body;
