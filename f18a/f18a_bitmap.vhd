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

-- V9938 bitmap modes: G4 (256 x 4 bpp), G5 (512 x 2 bpp), G6 (512 x 4 bpp)
-- and G7 (256 x 8 bpp), like openMSX SDLRasterizer::renderBitmapLine.
--
-- At the start of each line (the tile prescan trigger) the line is read
-- from VRAM and written, one pixel per clock, into the tile line buffer,
-- which the color module shows like tile pixels.  The line address comes
-- from R2 (page) ANDed with the display line (with the R23 scroll):
--
--   G4, G5:  vline = (R2 << 3 | 7) & (0x300 | y), address = vline * 128 + i
--   G6, G7:  vline = (R2 << 3 | 7) & (0x100 | y), address = vline * 256 + i,
--            in the planar (rotated) VRAM layout.
--
-- Line buffer entry: PIX | PRI | palette select (2) | color (4).  Color 0
-- is transparent (PIX = 0, the border color shows) unless TP.  In G7 the
-- entry is the 8-bit GGGRRRBB color itself (G7 has no transparency), which
-- f18a_color shows without the palette.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity f18a_bitmap is
   port (
      clk         : in  std_logic;
      rst_n       : in  std_logic;
      start       : in  std_logic;                    -- one clock at the start of a line
      mode        : in  std_logic_vector(0 to 1);     -- "00" G4, "01" G5, "10" G6, "11" G7
      r2          : in  std_logic_vector(0 to 7);     -- name (page) register
      y           : in  unsigned(0 to 7);             -- display line, with the scroll
      tp          : in  std_logic;                    -- R8 TP: color 0 is not transparent
   -- V9958 horizontal scroll: the line starts hs * 8 pixels in; with multi
   -- (R#25 SP2 and an odd page) it continues into the other page, starting
   -- with the page in hp1 (R#26 bit 5: '1' odd).
      hs          : in  unsigned(0 to 4) := "00000";
      multi       : in  std_logic := '0';
      hp1         : in  std_logic := '0';
   -- VRAM
      active      : out std_logic;                    -- '1' while reading VRAM
      vaddr       : out std_logic_vector(0 to 16);
      vdin        : in  std_logic_vector(0 to 7);
   -- Line buffer
      we          : out std_logic;
      x           : out unsigned(0 to 8);
      din         : out std_logic_vector(0 to 7);
      done        : out std_logic;                    -- one clock when the line is complete
   -- V9958 YJK (G7 byte order): J and K of each group of 4 pixels (openMSX
   -- renderYJK), K = p1(2-0) p0(2-0), J = p3(2-0) p2(2-0), 6-bit signed.
      jk_we       : out std_logic;
      jk_x        : out unsigned(0 to 5);             -- group (pixel / 4)
      jk          : out std_logic_vector(0 to 11)     -- J & K
   );
end f18a_bitmap;

architecture rtl of f18a_bitmap is

   -- A pixel is shown (not transparent) unless its color is 0 and TP = 0.
   function pix_flag(c : std_logic_vector; tp : std_logic) return std_logic is
   begin
      if tp = '1' or unsigned(c) /= 0 then return '1'; else return '0'; end if;
   end function;

   type state_t is (S_IDLE, S_ADDR, S_WAIT, S_PIX);
   signal state_r    : state_t := S_IDLE;

   signal byte_r     : unsigned(0 to 7) := (others => '0');     -- byte in the line
   signal data_r     : std_logic_vector(0 to 7) := (others => '0');
   signal pix_r      : unsigned(0 to 1) := (others => '0');     -- pixel in the byte
   signal x_r        : unsigned(0 to 8) := (others => '0');
   signal we_r       : std_logic := '0';
   signal din_r      : std_logic_vector(0 to 7) := (others => '0');
   signal done_r     : std_logic := '0';
   signal hist_r     : std_logic_vector(0 to 8) := (others => '0');   -- low 3 bits of the last 3 bytes
   signal jk_we_r    : std_logic := '0';
   signal jk_x_r     : unsigned(0 to 5) := (others => '0');
   signal jk_r       : std_logic_vector(0 to 11) := (others => '0');

   signal planar_s   : std_logic;
   signal last_byte_s: unsigned(0 to 7);
   signal last_pix_s : unsigned(0 to 1);
   signal vline_s    : std_logic_vector(0 to 9);
   signal laddr_s    : std_logic_vector(0 to 16);  -- logical address
   signal src_s      : unsigned(0 to 8);           -- byte read, with the scroll (bit 0: next page)
   signal odd_s      : std_logic;                  -- the odd page of a multi page pair
   signal color_s    : std_logic_vector(0 to 3);

begin

   planar_s    <= mode(0);                                  -- G6, G7
   last_byte_s <= x"7F" when planar_s = '0' else x"FF";     -- 128 or 256 bytes
   last_pix_s  <=
      "11" when mode = "01" else                            -- G5: 4 pixels per byte
      "00" when mode = "11" else                            -- G7: 1
      "01";                                                 -- G4, G6: 2

   -- V9958 scroll: start 4 (G4, G5) or 8 (G6, G7) bytes per 8 pixels in.
   src_s <= ('0' & byte_r) + ("00" & hs & "00") when planar_s = '0' else
            ('0' & byte_r) + ('0' & hs & "000");
   odd_s <= hp1 xor src_s(0) when planar_s = '1' else hp1 xor src_s(1);

   -- Line address.  R2 bits 6-5 select the page, the lower R2 bits mask y;
   -- with V9958 multi page scroll the page bit alternates.
   vline_s(0) <= r2(1) and not planar_s;
   vline_s(1) <= r2(2) and (not multi or odd_s);
   vline_s(2 to 9) <= std_logic_vector(y) and (r2(3 to 7) & "111");
   laddr_s <=
      vline_s & std_logic_vector(src_s(2 to 8)) when planar_s = '0' else
      vline_s(1 to 9) & std_logic_vector(src_s(1 to 8));

   -- Physical address: planar = logical rotated right by one.
   vaddr <= laddr_s when planar_s = '0' else laddr_s(16) & laddr_s(0 to 15);

   -- Current pixel color.
   process (mode, pix_r, data_r)
   begin
      case mode is
      when "01" =>                                          -- G5, 2 bits, MSB first
         case pix_r is
         when "00"   => color_s <= "00" & data_r(0 to 1);
         when "01"   => color_s <= "00" & data_r(2 to 3);
         when "10"   => color_s <= "00" & data_r(4 to 5);
         when others => color_s <= "00" & data_r(6 to 7);
         end case;
      when "11" =>                                          -- G7: one pixel per byte, see din_r
         color_s <= data_r(4 to 7);
      when others =>                                        -- G4, G6, 4 bits, MSB first
         if pix_r(1) = '0' then
            color_s <= data_r(0 to 3);
         else
            color_s <= data_r(4 to 7);
         end if;
      end case;
   end process;

   process (clk) begin if rising_edge(clk) then
      we_r <= '0';
      done_r <= '0';
      if rst_n = '0' then
         state_r <= S_IDLE;
      else
         case state_r is

         when S_IDLE =>
            if start = '1' then
               state_r <= S_ADDR;
               byte_r <= (others => '0');
               x_r <= (others => '1');               -- first write is x = 0
            end if;

         when S_ADDR =>
            -- The address is presented now, the data arrives in two clocks.
            state_r <= S_WAIT;

         when S_WAIT =>
            state_r <= S_PIX;
            pix_r <= (others => '0');

         when S_PIX =>
            if pix_r = 0 then
               data_r <= vdin;
            end if;
            if pix_r = last_pix_s then
               if byte_r = last_byte_s then
                  state_r <= S_IDLE;
                  done_r <= '1';
               else
                  state_r <= S_ADDR;
                  byte_r <= byte_r + 1;
               end if;
            else
               pix_r <= pix_r + 1;
            end if;
         end case;

         -- Line buffer write for the pixel of the previous clock (the byte
         -- is latched in the first S_PIX clock).
         if state_r = S_PIX then
            we_r <= '1';
            x_r <= x_r + 1;
         end if;
      end if;
   end if; end process;

   -- The pixel written is from data_r, which holds the byte from the
   -- second S_PIX clock on; the first pixel uses vdin directly.
   process (clk) begin if rising_edge(clk) then
      jk_we_r <= '0';
      if state_r = S_PIX and pix_r = 0 and mode = "11" then
         -- YJK: J and K at the 4th byte of each group (p0 p1 p2 in hist_r).
         hist_r <= hist_r(3 to 8) & vdin(5 to 7);
         if byte_r(6 to 7) = "11" then
            jk_we_r <= '1';
            jk_x_r <= byte_r(0 to 5);
            jk_r <= vdin(5 to 7) & hist_r(6 to 8) & hist_r(3 to 5) & hist_r(0 to 2);
         end if;
      end if;
      if state_r = S_PIX then
         if pix_r = 0 then
            if mode = "01" then
               din_r <= pix_flag(vdin(0 to 1), tp) & '0' & "00" & "00" & vdin(0 to 1);
            elsif mode = "11" then
               din_r <= vdin;                       -- G7: GGGRRRBB
            else
               din_r <= pix_flag(vdin(0 to 3), tp) & '0' & "00" & vdin(0 to 3);
            end if;
         else
            din_r <= pix_flag(color_s, tp) & '0' & "00" & color_s;
         end if;
      end if;
   end if; end process;

   active <= '0' when state_r = S_IDLE else '1';
   we     <= we_r;
   x      <= x_r;
   din    <= din_r;
   done   <= done_r;
   jk_we  <= jk_we_r;
   jk_x   <= jk_x_r;
   jk     <= jk_r;

end rtl;
