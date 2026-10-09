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

-- Final pixel selection and color lookup table.


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;


entity f18a_color is
   port (
      clk         : in std_logic;
      vga_clk     : in std_logic;
      we1         : in std_logic;
      addr1       : in std_logic_vector(0 to 5);
      din         : in std_logic_vector(0 to 11);
      dout1       : out std_logic_vector(0 to 11);    -- to the GPU

      tile_color  : in  std_logic_vector(0 to 7);
      sprt_color  : in  std_logic_vector(0 to 7);
      bg_color    : in  std_logic_vector(0 to 5);
      show_bg     : in  std_logic;
      g5          : in  std_logic;                    -- V9938 G5: sprite colors split in two halves
      g7          : in  std_logic;                    -- V9938 G7: tile entries and the border are GGGRRRBB
      g7_bg       : in  std_logic_vector(0 to 7);     -- G7 border (R#7)
      v9938       : in  std_logic := '0';             -- palette entries hold 3-bit V9938 levels
   -- V9958 YJK: the tile entry is the G7 byte (Y = bits 7-3), jk the J / K
   -- of its group of 4 pixels; with yae a byte with bit 3 set is palette
   -- color byte >> 4.  bogus: YJK in G4 / G5, the background is color 15.
      yjk         : in  std_logic := '0';
      yae         : in  std_logic := '0';
      bogus       : in  std_logic := '0';
      tp          : in  std_logic := '0';             -- R#8 TP: color 0 is not transparent
      jk          : in  std_logic_vector(0 to 11) := (others => '0');
      half        : in  std_logic;                    -- G5 half pixel: '0' left (bits 3-2), '1' right (1-0)
      tile_r      : out std_logic_vector(0 to 7);     -- 8 bits per channel
      tile_g      : out std_logic_vector(0 to 7);
      tile_b      : out std_logic_vector(0 to 7)
   );
end f18a_color;

architecture rtl of f18a_color is

   type colrom_t is array (0 to 15) of std_logic_vector(0 to 3);

   -- 64 palette registers of 12 bit color.
   type colram_t is array (0 to 63) of std_logic_vector(0 to 11);
   signal colram : colram_t :=
   (
   -- Palette 0, original 9918A NTSC color approximations
   x"000", --  0 Transparent
   x"000", --  1 Black
   x"2C3", --  2 Medium Green
   x"5D6", --  3 Light Green
   x"54F", --  4 Dark Blue
   x"76F", --  5 Light Blue
   x"D54", --  6 Dark Red
   x"4EF", --  7 Cyan
   x"F54", --  8 Medium Red
   x"F76", --  9 Light Red
   x"DC3", -- 10 Dark Yellow
   x"ED6", -- 11 Light Yellow
   x"2B2", -- 12 Dark Green
   x"C5C", -- 13 Magenta
   x"CCC", -- 14 Gray
   x"FFF", -- 15 White

   -- Palette 1, ECM1 (0 index is always 000) version of palette 0
   x"000", --  0 Black
   x"2C3", --  1 Medium Green
   x"000", --  2 Black
   x"54F", --  3 Dark Blue
   x"000", --  4 Black
   x"D54", --  5 Dark Red
   x"000", --  6 Black
   x"4EF", --  7 Cyan
   x"000", --  8 Black
   x"CCC", --  9 Gray
   x"000", -- 10 Black
   x"DC3", -- 11 Dark Yellow
   x"000", -- 12 Black
   x"C5C", -- 13 Magenta
   x"000", -- 14 Black
   x"FFF", -- 15 White

   -- Palette 2, CGA colors
   x"000", --  0 >000000 (  0   0   0) black
   x"00A", --  1 >0000AA (  0   0 170) blue
   x"0A0", --  2 >00AA00 (  0 170   0) green
   x"0AA", --  3 >00AAAA (  0 170 170) cyan
   x"A00", --  4 >AA0000 (170   0   0) red
   x"A0A", --  5 >AA00AA (170   0 170) magenta
   x"A50", --  6 >AA5500 (170  85   0) brown
   x"AAA", --  7 >AAAAAA (170 170 170) light gray
   x"555", --  8 >555555 ( 85  85  85) gray
   x"55F", --  9 >5555FF ( 85  85 255) light blue
   x"5F5", -- 10 >55FF55 ( 85 255  85) light green
   x"5FF", -- 11 >55FFFF ( 85 255 255) light cyan
   x"F55", -- 12 >FF5555 (255  85  85) light red
   x"F5F", -- 13 >FF55FF (255  85 255) light magenta
   x"FF5", -- 14 >FFFF55 (255 255  85) yellow
   x"FFF", -- 15 >FFFFFF (255 255 255) white

   -- Palette 3, ECM1 (0 index is always 000) version of palette 2
   x"000", --  0 >000000 (  0   0   0) black
   x"555", --  1 >555555 ( 85  85  85) gray
   x"000", --  2 >000000 (  0   0   0) black
   x"00A", --  3 >0000AA (  0   0 170) blue
   x"000", --  4 >000000 (  0   0   0) black
   x"0A0", --  5 >00AA00 (  0 170   0) green
   x"000", --  6 >000000 (  0   0   0) black
   x"0AA", --  7 >00AAAA (  0 170 170) cyan
   x"000", --  8 >000000 (  0   0   0) black
   x"A00", --  9 >AA0000 (170   0   0) red
   x"000", -- 10 >000000 (  0   0   0) black
   x"A0A", -- 11 >AA00AA (170   0 170) magenta
   x"000", -- 12 >000000 (  0   0   0) black
   x"A50", -- 13 >AA5500 (170  85   0) brown
   x"000", -- 14 >000000 (  0   0   0) black
   x"FFF"  -- 15 >FFFFFF (255 255 255) white
   );

   signal addr2         : std_logic_vector(0 to 5);
   signal addr2_next    : std_logic_vector(0 to 5);
   signal dout2         : std_logic_vector(0 to 11);
   signal dout1_reg     : std_logic_vector(0 to 11);
   signal sprt_pix      : std_logic;
   signal sprt_en       : std_logic;
   signal tile_en       : std_logic;

   -- G7: the color is an 8-bit GGGRRRBB code, not a palette entry.  Sprites
   -- use 16 fixed colors (openMSX Renderer::GRAPHIC7_SPRITE_PALETTE).
   type g7spr_t is array (0 to 15) of std_logic_vector(0 to 7);
   constant G7_SPRITE : g7spr_t := (
      x"00", x"01", x"0C", x"0D", x"60", x"61", x"6C", x"6D",
      x"9D", x"03", x"1C", x"1F", x"E0", x"E3", x"FC", x"FF");
   signal g7_next       : std_logic_vector(0 to 7);
   signal yae_pal_s     : std_logic;                     -- YAE: this pixel is a palette color
   signal yjk_use_next, yjk_use_r : std_logic := '0';
   signal yjk_rgb_next, yjk_rgb_c, yjk_rgb_r : std_logic_vector(0 to 14) := (others => '0');

   -- 5-bit V9958 level to 8 bits (c << 3 | c >> 2).
   function lvl8_5(c : std_logic_vector(0 to 4)) return std_logic_vector is
   begin
      return c & c(0 to 2);
   end function;

   function clamp5(v : signed) return std_logic_vector is
   begin
      if v < 0 then
         return "00000";
      elsif v > 31 then
         return "11111";
      end if;
      return std_logic_vector(resize(unsigned(v), 5));
   end function;
   signal g7_code       : std_logic_vector(0 to 7);
   signal g7_r          : std_logic := '0';

   -- 3-bit V9938 level to 8 bits (c * 255 / 7: c << 5 | c << 2 | c >> 1).
   -- Its high nibble is the 4-bit palette value (c << 1 | c >> 2).
   function lvl8(c : std_logic_vector(0 to 2)) return std_logic_vector is
   begin
      return c & c & c(0 to 1);
   end function;

   -- A 4-bit palette channel to 8 bits: the 3-bit level in V9938 mode, the
   -- nibble repeated otherwise (the F18A / 9918A palettes).
   function pal8(v : std_logic_vector(0 to 3); v9938 : std_logic) return std_logic_vector is
   begin
      if v9938 = '1' then
         return lvl8(v(0 to 2));
      end if;
      return v & v;
   end function;

begin

   process (clk)
   begin
      if rising_edge(clk) then
         if we1 = '1' then
            colram(to_integer(unsigned(addr1))) <= din;
         end if;

         -- to the GPU! :-)
         dout1_reg <= colram(to_integer(unsigned(addr1)));

         -- YJK: one register at the core clock (timing); the line buffer
         -- data is stable for the 8 core clocks of a pixel.
         yjk_rgb_c <= yjk_rgb_next;
      end if;
   end process;

   -- Infer distributed RAM.
   dout1 <= dout1_reg;
   dout2 <= colram(to_integer(unsigned(addr2)));

   -- Color format:
   --    0     1     2     3     4     5     6     7
   -- | PIX | PRI |      6-bit color address           |
   --
   -- PIX = if there is a pixel or not.  If PIX = 1 for tiles
   --       then the 6-bit color address is valid and PRI should
   --       be considered to determine the final color.
   -- PRI = priority over sprites.  1 = priority
   --

   -- Sprite / tile / background address selector
   -- If the sprite does not have a pixel, or if there is a tile and
   -- it has priority, the color will be that of the tile.
   -- In G7 / YJK the tile entry has no PIX / PRI bits: tiles always show
   -- (but a YAE palette color 0 is transparent without TP).
   yae_pal_s <= yjk and yae and tile_color(4);
   sprt_pix <= sprt_color(0) and (g7 or yjk or bogus or not (tile_color(0) and tile_color(1)));


   -- The blank bit and margin override any sprite or tile pixels.
   sprt_en <= sprt_pix and not show_bg;
   tile_en <= '0' when show_bg = '1' else
              '0' when yae_pal_s = '1' and tile_color(0 to 3) = "0000" and tp = '0' else
              tile_color(0) or g7 or yjk or bogus;

   -- YJK (openMSX yjk2rgb): R = Y + J, G = Y + K, B = (5Y - 2J - K + 2) / 4.
   process (tile_color, jk)
      variable y5, j6, k6, b : signed(0 to 9);
   begin
      y5 := signed(resize(unsigned(tile_color(0 to 4)), 10));
      j6 := resize(signed(jk(0 to 5)), 10);
      k6 := resize(signed(jk(6 to 11)), 10);
      b  := shift_right(resize(y5 * 5, 10) - (j6 + j6) - k6 + 2, 2);
      yjk_rgb_next <= clamp5(y5 + j6) & clamp5(y5 + k6) & clamp5(b);
   end process;
   yjk_use_next <= tile_en and yjk and not yae_pal_s and not sprt_en;

   g7_next <=
      G7_SPRITE(to_integer(unsigned(sprt_color(4 to 7)))) when sprt_en = '1' else
      tile_color when tile_en = '1' else
      g7_bg;

   addr2_next <=
      "0000" & sprt_color(4 to 5) when sprt_en = '1' and g5 = '1' and half = '0' else
      "0000" & sprt_color(6 to 7) when sprt_en = '1' and g5 = '1' else
      sprt_color(2 to 7) when sprt_en = '1' else
      "001111" when tile_en = '1' and bogus = '1' else
      "00" & tile_color(0 to 3) when tile_en = '1' and yae_pal_s = '1' else
      tile_color(2 to 7) when tile_en = '1' else
      bg_color;

   -- Register at the VGA clock.  Matches the in_margin register
   -- in the counters module.
   process (vga_clk) begin if rising_edge(vga_clk) then
      addr2 <= addr2_next;
      g7_code <= g7_next;
      g7_r <= g7;
      yjk_use_r <= yjk_use_next;
      yjk_rgb_r <= yjk_rgb_c;
   end if; end process;


   -- G7 blue: 2 bits to the levels 0, 2, 4, 7.
   tile_r <= lvl8_5(yjk_rgb_r(0 to 4))   when yjk_use_r = '1' else
             lvl8(g7_code(3 to 5)) when g7_r = '1' else pal8(dout2(0 to 3), v9938);
   tile_g <= lvl8_5(yjk_rgb_r(5 to 9))   when yjk_use_r = '1' else
             lvl8(g7_code(0 to 2)) when g7_r = '1' else pal8(dout2(4 to 7), v9938);
   tile_b <= lvl8_5(yjk_rgb_r(10 to 14)) when yjk_use_r = '1' else
             pal8(dout2(8 to 11), v9938) when g7_r = '0' else
             lvl8("000") when g7_code(6) = '0' and g7_code(7) = '0' else
             lvl8("010") when g7_code(6) = '0' else
             lvl8("100") when g7_code(7) = '0' else
             lvl8("111");

end rtl;
