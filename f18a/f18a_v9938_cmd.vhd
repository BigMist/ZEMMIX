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

-- V9938 command engine (R#32-R#46): HMMC, YMMM, HMMM, HMMV, LMMC, LMCM,
-- LMMM, LMMV, LINE, SRCH, PSET, POINT and STOP with the logical
-- operations, in the bitmap modes G4-G7.  Functionally like openMSX
-- VDPCmdEngine (current version, see sim/v9938_cmd.py, the reference model
-- the RTL is tested against), without its access slot timing: the engine
-- runs as fast as the VRAM port allows, sharing port A with the CPU
-- interface, which has priority.
--
-- VRAM access: mem_req stays high with mem_we / mem_addr / mem_dout until
-- mem_ack (one clock); read data comes on mem_din the clock after, with
-- mem_rvalid.  Addresses are physical (G6 / G7 already planar).
--
-- Speed: with fast = '1' the engine runs as fast as the VRAM port allows.
-- With fast = '0' it follows the V9938 timing of openMSX (VDPAccessSlots,
-- VDPCmdEngine): every access waits for the first command slot of the line
-- that is at least 'delta' cycles (21.477 MHz) after the previous access,
-- with the slot tables (display off / sprites off / sprites on) and the
-- deltas of each command step.  The small corrections of openMSX (padded
-- memory cycles, +1 with sprites) are left out.
--
-- The counters SY, DY, NY, ASX, ADX and ANX are 16 bits: openMSX steps
-- them without masking, so after a command DY can be above 1023 or
-- negative, and the registers read back (debugger) the high byte of that.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity f18a_v9938_cmd is
   port (
      clk         : in  std_logic;
      rst_n       : in  std_logic;
      mode_ok     : in  std_logic;                    -- '1' in G4-G7 (commands possible)
      bmode       : in  std_logic_vector(0 to 1);     -- "00" G4, "01" G5, "10" G6, "11" G7
      nb          : in  std_logic := '0';             -- V9958 R#25 CMD in a non-bitmap mode: G7
                                                      -- coordinates on a linear 256 byte per line VRAM
   -- Timing
      fast        : in  std_logic := '1';             -- '1': no V9938 timing
      cyc         : in  unsigned(10 downto 0) := (others => '0');  -- V9938 cycle in the line, 0-1367
      cyc_tick    : in  std_logic := '0';             -- one clock at the start of each cycle
      scr_on      : in  std_logic := '0';             -- display enabled and in the active lines
      spr_on      : in  std_logic := '0';             -- sprites enabled (R#8 SPD = 0)
   -- CPU
      reg_we      : in  std_logic;                    -- one clock: write R#32 + reg_idx
      reg_idx     : in  unsigned(0 to 3);
      reg_din     : in  std_logic_vector(0 to 7);
      s7_rd       : in  std_logic;                    -- one clock: S#7 read
      s9_rd       : in  std_logic;                    -- one clock: S#9 read (clears BD)
   -- Status
      tr          : out std_logic;                    -- S#2 TR
      bd          : out std_logic;                    -- S#2 BD
      ce          : out std_logic;                    -- S#2 CE
      busy        : out std_logic;                    -- '1' while working (not idle or waiting for a transfer)
      col         : out std_logic_vector(0 to 7);     -- S#7
      asx         : out std_logic_vector(0 to 8);     -- S#8, S#9 bit 0
   -- VRAM
      mem_req     : out std_logic;
      mem_we      : out std_logic;
      mem_addr    : out std_logic_vector(0 to 16);
      mem_dout    : out std_logic_vector(0 to 7);
      mem_ack     : in  std_logic;
      mem_rvalid  : in  std_logic;
      mem_din     : in  std_logic_vector(0 to 7)
   );
end f18a_v9938_cmd;

architecture rtl of f18a_v9938_cmd is

   subtype u16 is unsigned(15 downto 0);
   subtype u8  is unsigned(7 downto 0);

   -- openMSX VDPAccessSlots slotsScreenOff: 154 slots per line.
   constant SLOTS_SCREEN_OFF : std_logic_vector(0 to 1367) :=
      x"8080808080808080808080808080808000000000080808080808080808080808" &
      x"0808080008080808080808080808080808080800080808080808080808080808" &
      x"0808080008080808080808080808080808080800080808080808080808080808" &
      x"0808080008080808080808080808080808080800080808080808080808080808" &
      x"0808080008080808080808080808080808080800080808080808000000000808" &
      x"0808080808080200808080";

   -- openMSX VDPAccessSlots slotsSpritesOff: 88 slots per line.
   constant SLOTS_SPRITES_OFF : std_logic_vector(0 to 1367) :=
      x"0202020202020202020202020202020000000000202002080000020800000208" &
      x"0000020000000208000002080000020800000200000002080000020800000208" &
      x"0000020000000208000002080000020800000200000002080000020800000208" &
      x"0000020000000208000002080000020800000200000002080000020800000208" &
      x"0000020000000208000002080000020800000200000002080000000000002020" &
      x"2020202020200802020202";

   -- openMSX VDPAccessSlots slotsSpritesOn: 31 slots per line.
   constant SLOTS_SPRITES_ON : std_logic_vector(0 to 1367) :=
      x"0000000800000000000000080000000000000000202000080000000800000008" &
      x"0000000000000008000000080000000800000000000000080000000800000008" &
      x"0000000000000008000000080000000800000000000000080000000800000008" &
      x"0000000000000008000000080000000800000000000000080000000800000008" &
      x"0000000000000008000000080000000800000000000000080000000000008000" &
      x"0000000000002000000000";

   -- Delay from the R#46 write to the first access (openMSX CMD_START_*),
   -- per command (R#46 bits 7-4).
   type start_t is array (0 to 15) of natural range 0 to 255;
   constant START_DELTA : start_t := (
      0, 0, 0, 0, 63, 88, 88, 112, 88, 64, 76, 88, 112, 100, 100, 112);

   -- Commands, R#46 bits 7-4.
   constant C_POINT : unsigned(3 downto 0) := x"4";
   constant C_PSET  : unsigned(3 downto 0) := x"5";
   constant C_SRCH  : unsigned(3 downto 0) := x"6";
   constant C_LINE  : unsigned(3 downto 0) := x"7";
   constant C_LMMV  : unsigned(3 downto 0) := x"8";
   constant C_LMMM  : unsigned(3 downto 0) := x"9";
   constant C_LMCM  : unsigned(3 downto 0) := x"A";
   constant C_LMMC  : unsigned(3 downto 0) := x"B";
   constant C_HMMV  : unsigned(3 downto 0) := x"C";
   constant C_HMMM  : unsigned(3 downto 0) := x"D";
   constant C_YMMM  : unsigned(3 downto 0) := x"E";
   constant C_HMMC  : unsigned(3 downto 0) := x"F";

   -- Pixel address in the current mode (physical, G6 / G7 planar; the V9958
   -- non-bitmap mode linear).
   function addr_of(m : std_logic_vector(0 to 1); nb : std_logic; x, y : u16) return unsigned is
   begin
      if nb = '1' then
         return y(8 downto 0) & x(7 downto 0);
      end if;
      case m is
      when "00"   => return y(9 downto 0) & x(7 downto 1);              -- G4
      when "01"   => return y(9 downto 0) & x(8 downto 2);              -- G5
      when "10"   => return x(1) & y(8 downto 0) & x(8 downto 2);       -- G6
      when others => return x(0) & y(8 downto 0) & x(7 downto 1);       -- G7
      end case;
   end function;

   -- The pixel at x in the byte b.
   function pix_of(m : std_logic_vector(0 to 1); b : u8; x : u16) return u8 is
   begin
      case m is
      when "00" | "10" =>
         if x(0) = '0' then return x"0" & b(7 downto 4); else return x"0" & b(3 downto 0); end if;
      when "01" =>
         case x(1 downto 0) is
         when "00"   => return "000000" & b(7 downto 6);
         when "01"   => return "000000" & b(5 downto 4);
         when "10"   => return "000000" & b(3 downto 2);
         when others => return "000000" & b(1 downto 0);
         end case;
      when others => return b;
      end case;
   end function;

   -- The color c moved to the position of the pixel x (it is not masked:
   -- an MXS source of FFh writes more than one pixel, like openMSX).
   function shift_col(m : std_logic_vector(0 to 1); c : u8; x : u16) return u8 is
   begin
      case m is
      when "00" | "10" =>
         if x(0) = '0' then return c(3 downto 0) & x"0"; else return c; end if;
      when "01" =>
         case x(1 downto 0) is
         when "00"   => return c(1 downto 0) & "000000";
         when "01"   => return c(3 downto 0) & "0000";
         when "10"   => return c(5 downto 0) & "00";
         when others => return c;
         end case;
      when others => return c;
      end case;
   end function;

   -- 1 at the other pixels of the byte.
   function pix_mask(m : std_logic_vector(0 to 1); x : u16) return u8 is
   begin
      case m is
      when "00" | "10" =>
         if x(0) = '0' then return x"0F"; else return x"F0"; end if;
      when "01" =>
         case x(1 downto 0) is
         when "00"   => return x"3F";
         when "01"   => return x"CF";
         when "10"   => return x"F3";
         when others => return x"FC";
         end case;
      when others => return x"00";
      end case;
   end function;

   -- Logical operation: bit 8 = write, bits 7-0 = new byte.  The T
   -- operations do not write color 0; codes 5-7 and 13-15 never write.
   function logop(op : unsigned(3 downto 0); src, c, mask : u8) return unsigned is
      variable v : u8;
   begin
      if op(3) = '1' and c = 0 then
         return '0' & src;
      end if;
      case op(2 downto 0) is
      when "000"  => v := (src and mask) or c;                    -- IMP
      when "001"  => v := src and (c or mask);                    -- AND
      when "010"  => v := src or c;                               -- OR
      when "011"  => v := src xor c;                              -- EOR
      when "100"  => v := (src and mask) or not (c or mask);      -- NOT
      when others => return '0' & src;
      end case;
      return '1' & v;
   end function;

   -- Clipping, like openMSX clipNX_1_pixel / clipNX_1_byte / clipNX_2_* /
   -- clipNY_1 / clipNY_2.  ppl: pixels per line, sh: log2(pixels per byte)
   -- (0 for the pixel commands).
   function clip_nx(ppl : unsigned(9 downto 0); sh : natural; sx, dx : unsigned(8 downto 0);
                    nx : unsigned(9 downto 0); two, dix : boolean) return unsigned is
      variable bpl, s, d, n, lo, hi : unsigned(9 downto 0);
   begin
      bpl := shift_right(ppl, sh);
      s := shift_right(resize(sx, 10), sh);
      d := shift_right(resize(dx, 10), sh);
      if d >= bpl or (two and s >= bpl) then
         return to_unsigned(1, 10);
      end if;
      n := shift_right(nx, sh);
      if n = 0 then n := bpl; end if;
      if two then
         if s < d then lo := s; hi := d; else lo := d; hi := s; end if;
      else
         lo := d; hi := d;
      end if;
      if dix then
         if lo + 1 < n then n := lo + 1; end if;
      else
         if bpl - hi < n then n := bpl - hi; end if;
      end if;
      return n;
   end function;

   function clip_ny(sy, dy : u16; ny : unsigned(9 downto 0); two, diy : boolean) return unsigned is
      variable n : unsigned(10 downto 0);
      variable y : u16;
   begin
      n := resize(ny, 11);
      if n = 0 then n := to_unsigned(1024, 11); end if;
      if diy then
         y := dy;
         if two and sy < dy then y := sy; end if;
         y := y + 1;
         if y < resize(n, 16) then n := y(10 downto 0); end if;
      end if;
      return n;
   end function;

   type state_t is (S_IDLE, S_SETUP, S_SETUP2, S_SETUP3, S_UNIT, S_SRC, S_DST, S_DST_RMW, S_STEP,
                    S_XWAIT, S_RD, S_RD_DATA, S_WR);
   signal state, ret_st : state_t := S_IDLE;

   -- Registers.
   signal sx_r, dx_r    : unsigned(8 downto 0) := (others => '0');
   signal nx_r          : unsigned(9 downto 0) := (others => '0');
   signal sy_r, dy_r, ny_r : u16 := (others => '0');
   signal col_r, arg_r, cmd_r : u8 := (others => '0');
   -- Internal counters.
   signal asx_r, adx_r, anx_r : u16 := (others => '0');
   signal tmp_nx        : unsigned(9 downto 0) := (others => '0');
   signal tmp_ny        : unsigned(10 downto 0) := (others => '0');
   signal tr_r, bd_r, ce_r : std_logic := '0';
   signal xfer_r        : std_logic := '0';            -- openMSX 'transfer'

   -- Access.
   signal req_r, we_r   : std_logic := '0';
   signal addr_r        : unsigned(16 downto 0) := (others => '0');
   signal dout_r        : u8 := (others => '0');
   signal rdata         : u8 := (others => '0');
   signal src_x         : u16 := (others => '0');      -- x of the source byte read
   signal wbyte         : u8 := (others => '0');       -- byte for the H commands
   signal pcolor        : u8 := (others => '0');       -- color for the L commands
   -- Setup pipeline: the clipping inputs.
   signal cs_sh_r       : natural range 0 to 2 := 0;
   signal cs_sx_r, cs_dx_r : unsigned(8 downto 0) := (others => '0');
   signal cs_nx_r       : unsigned(9 downto 0) := (others => '0');
   signal cs_y_r        : u16 := (others => '0');
   signal cs_two_r, cs_twoy_r : boolean := false;

   -- Timing.
   signal since_r       : u8 := (others => '1');       -- cycles since the last access
   signal need_r        : u8 := (others => '0');       -- minimum for the pending access
   signal unit_delta_r  : u8 := (others => '0');       -- before the first access of a pixel / byte
   signal go_r          : std_logic := '0';
   signal slot_s        : std_logic;

   -- Decoded.
   signal cmd_s         : unsigned(3 downto 0);
   signal emode_s       : std_logic_vector(0 to 1);   -- pixel format: the non-bitmap mode is like G7
   signal op_s          : unsigned(3 downto 0);
   signal ppl_s         : natural range 256 to 512;
   signal sh_s          : natural range 0 to 2;
   signal cmask_s       : u8;
   signal ppl_bit_s     : natural range 8 to 9;       -- x & ppl /= 0: outside the line
   signal byte_cmd_s    : boolean;
   signal xfer_cmd_s    : boolean;
   signal mxs_s, mxd_s  : std_logic;
   signal dix_s, diy_s  : boolean;
   signal tx_s, ty_s    : u16;

begin

   cmd_s   <= cmd_r(7 downto 4);
   emode_s <= "11" when nb = '1' else bmode;
   op_s    <= cmd_r(3 downto 0);
   ppl_s   <= 512 when emode_s = "01" or emode_s = "10" else 256;
   ppl_bit_s <= 9 when emode_s = "01" or emode_s = "10" else 8;
   sh_s    <= 1 when emode_s = "00" or emode_s = "10" else 2 when emode_s = "01" else 0;
   cmask_s <= x"0F" when emode_s = "00" or emode_s = "10" else x"03" when emode_s = "01" else x"FF";
   byte_cmd_s <= cmd_s(3 downto 2) = "11";             -- HMMV HMMM YMMM HMMC
   xfer_cmd_s <= cmd_s = C_LMCM or cmd_s = C_LMMC or cmd_s = C_HMMC;
   mxs_s   <= arg_r(4);
   mxd_s   <= arg_r(5);
   dix_s   <= arg_r(2) = '1';
   diy_s   <= arg_r(3) = '1';
   -- X step: one pixel, or one byte in the H commands.
   tx_s    <= (others => '1') when dix_s and not byte_cmd_s else
              to_unsigned(1, 16) when not byte_cmd_s else
              to_unsigned(65536 - 2 ** sh_s, 16) when dix_s else
              to_unsigned(2 ** sh_s, 16);
   ty_s    <= (others => '1') when diy_s else to_unsigned(1, 16);

   process (clk)
      variable v9      : unsigned(8 downto 0);
      variable a       : u16;
      variable sp, sb  : u8;
      variable ny_dec  : u16;
      variable dyn     : u16;
      variable two     : boolean;
      variable done    : boolean;
      variable dl_main, dl_eol : natural range 0 to 255;

      procedure finish is
      begin
         ce_r  <= '0';
         cmd_r <= (others => '0');
         state <= S_IDLE;
      end procedure;

      procedure read_at(x, y : u16; ret : state_t; dl : u8) is
      begin
         req_r  <= '1';
         we_r   <= '0';
         need_r <= dl;
         addr_r <= addr_of(emode_s, nb, x, y);
         ret_st <= ret;
         state  <= S_RD;
      end procedure;

      procedure write_at(ad : unsigned(16 downto 0); d : u8; ret : state_t; dl : u8) is
      begin
         req_r  <= '1';
         we_r   <= '1';
         need_r <= dl;
         addr_r <= ad;
         dout_r <= d;
         ret_st <= ret;
         state  <= S_WR;
      end procedure;

   begin
      if rising_edge(clk) then
      if rst_n = '0' then
         state  <= S_IDLE;
         req_r  <= '0';
         we_r   <= '0';
         tr_r   <= '0';
         bd_r   <= '0';
         ce_r   <= '0';
         xfer_r <= '0';
         sx_r   <= (others => '0');
         dx_r   <= (others => '0');
         nx_r   <= (others => '0');
         sy_r   <= (others => '0');
         dy_r   <= (others => '0');
         ny_r   <= (others => '0');
         col_r  <= (others => '0');
         arg_r  <= (others => '0');
         cmd_r  <= (others => '0');
         asx_r  <= (others => '0');
         adx_r  <= (others => '0');
         anx_r  <= (others => '0');
      else

         -- The pending access may go at a command slot 'need' cycles after
         -- the slot of the previous one.  since_r counts the cycles from
         -- that slot; at a cycle start it still holds the count of the
         -- cycle before, hence the + 1.
         if cyc_tick = '1' and since_r /= x"FF" then
            since_r <= since_r + 1;
         end if;
         if req_r = '0' or mem_ack = '1' then
            go_r <= '0';
         elsif fast = '1' then
            go_r <= '1';
         elsif go_r = '0' and cyc_tick = '1' and slot_s = '1' and resize(since_r, 9) + 1 >= need_r then
            go_r <= '1';
            since_r <= (others => '0');
         end if;

         case state is

         when S_IDLE =>
            null;

         -- The command was written to R#46: set up the counters.
         -- The setup takes three clocks (timing): the clipping inputs,
         -- the clipping, the counters.
         when S_SETUP =>
            state <= S_SETUP2;
            if cmd_s >= C_LINE and cmd_s /= C_SRCH then
               ny_r <= ny_r and to_unsigned(1023, 16);
            end if;
            -- Clipping inputs: LMCM clips the source, YMMM goes to the edge.
            cs_sh_r <= 0;
            cs_sx_r <= sx_r;
            cs_dx_r <= dx_r;
            cs_nx_r <= nx_r;
            cs_two_r <= cmd_s = C_LMMM or cmd_s = C_HMMM or cmd_s = C_YMMM;
            cs_twoy_r <= cmd_s = C_LMMM or cmd_s = C_HMMM or cmd_s = C_YMMM;
            cs_y_r <= dy_r;
            if byte_cmd_s then cs_sh_r <= sh_s; end if;
            if cmd_s = C_LMCM then cs_dx_r <= sx_r; cs_y_r <= sy_r; end if;
            if cmd_s = C_YMMM then cs_nx_r <= to_unsigned(512, 10); cs_two_r <= false; end if;

         when S_SETUP2 =>
            state <= S_SETUP3;
            tmp_nx <= clip_nx(to_unsigned(ppl_s, 10), cs_sh_r, cs_sx_r, cs_dx_r, cs_nx_r, cs_two_r, dix_s);
            tmp_ny <= clip_ny(sy_r, cs_y_r, ny_r(9 downto 0), cs_twoy_r, diy_s);

         when S_SETUP3 =>
            state <= S_UNIT;
            anx_r  <= resize(tmp_nx, 16);
            asx_r  <= resize(sx_r, 16);
            adx_r  <= resize(dx_r, 16);
            if cmd_s = C_LINE then
               asx_r <= shift_right(resize(nx_r, 16) - 1, 1);
               anx_r <= (others => '0');
            elsif cmd_s = C_LMMV or cmd_s = C_LMMC or cmd_s = C_HMMV or cmd_s = C_HMMC or
                  cmd_s = C_YMMM then
               asx_r <= asx_r;     -- not used by these commands, S#8 keeps it
            elsif cmd_s = C_POINT or cmd_s = C_PSET then
               asx_r <= asx_r;
               adx_r <= adx_r;
               anx_r <= anx_r;
            elsif cmd_s = C_LMCM then
               adx_r <= adx_r;
            end if;
            -- Transfers: TR on; LMCM reads the first pixel right away,
            -- HMMC / LMMC use a byte already written to R#44.
            if xfer_cmd_s then
               tr_r <= '1';
               if cmd_s = C_LMCM then xfer_r <= '1'; end if;
               state <= S_XWAIT;
            end if;

         -- Transfer commands: one byte / pixel for each R#44 write or S#7 read.
         when S_XWAIT =>
            if xfer_r = '1' then
               xfer_r <= '0';
               ny_r <= ny_r and to_unsigned(1023, 16);
               state <= S_UNIT;
            end if;

         -- One pixel / byte: read the source or go to the destination.
         when S_UNIT =>
            pcolor <= col_r and cmask_s;
            case cmd_s is
            when C_POINT =>
               src_x <= resize(sx_r, 16);
               if mxs_s = '1' then state <= S_SRC; else read_at(resize(sx_r, 16), sy_r, S_SRC, unit_delta_r); end if;
            when C_SRCH | C_LMMM | C_LMCM | C_HMMM =>
               src_x <= asx_r;
               if mxs_s = '1' then state <= S_SRC; else read_at(asx_r, sy_r, S_SRC, unit_delta_r); end if;
            when C_YMMM =>
               src_x <= adx_r;
               if mxd_s = '1' then state <= S_STEP; else read_at(adx_r, sy_r, S_SRC, unit_delta_r); end if;
            when others =>
               wbyte <= col_r;
               state <= S_DST;
            end case;

         -- Source byte in rdata (or FFh from the expansion VRAM).
         when S_SRC =>
            if mxs_s = '1' and cmd_s /= C_YMMM then
               sp := x"FF"; sb := x"FF";
            else
               sp := pix_of(emode_s, rdata, src_x); sb := rdata;
            end if;
            pcolor <= sp;
            wbyte  <= sb;
            state  <= S_DST;
            case cmd_s is
            when C_POINT =>
               col_r <= sp;
               finish;
            when C_LMCM =>
               col_r <= sp;
               state <= S_STEP;
            when C_SRCH =>
               if (sp = (col_r and cmask_s)) xor (arg_r(1) = '1') then
                  bd_r <= '1';
                  finish;
               else
                  a := asx_r + tx_s;
                  asx_r <= a;
                  unit_delta_r <= to_unsigned(88, 8);
                  if a(ppl_bit_s) = '1' then
                     finish;           -- not found (BD is left as it is)
                  else
                     state <= S_UNIT;
                  end if;
               end if;
            when others =>
               null;
            end case;

         -- Destination: H commands write, L commands read-modify-write.
         when S_DST =>
            if cmd_s = C_PSET then
               a := resize(dx_r, 16);
            else
               a := adx_r;
            end if;
            src_x <= a;
            if mxd_s = '1' then
               state <= S_STEP;
            elsif byte_cmd_s then
               -- HMMM / YMMM: 24 cycles after the source read.
               if cmd_s = C_HMMM or cmd_s = C_YMMM then
                  write_at(addr_of(emode_s, nb, a, dy_r), wbyte, S_STEP, to_unsigned(24, 8));
               else
                  write_at(addr_of(emode_s, nb, a, dy_r), wbyte, S_STEP, unit_delta_r);
               end if;
            else
               -- LMMM: 32 cycles after the source read.
               if cmd_s = C_LMMM then
                  read_at(a, dy_r, S_DST_RMW, to_unsigned(32, 8));
               else
                  read_at(a, dy_r, S_DST_RMW, unit_delta_r);
               end if;
            end if;

         when S_DST_RMW =>
            v9 := logop(op_s, rdata, shift_col(emode_s, pcolor, src_x), pix_mask(emode_s, src_x));
            if v9(8) = '1' then
               write_at(addr_r, v9(7 downto 0), S_STEP, to_unsigned(24, 8));
            else
               state <= S_STEP;
            end if;

         -- Move to the next pixel / byte / line.
         when S_STEP =>
            done := false;
            case cmd_s is
            when C_PSET =>
               done := true;

            when C_LINE =>
               unit_delta_r <= to_unsigned(84, 8);
               if arg_r(0) = '0' then
                  -- X major.
                  a := adx_r + tx_s;
                  adx_r <= a;
                  anx_r <= anx_r + 1;
                  if anx_r = resize(nx_r, 16) or a(ppl_bit_s) = '1' then
                     done := true;
                  elsif asx_r < ny_r then
                     unit_delta_r <= to_unsigned(84 + 36, 8);
                     dyn := dy_r + ty_s;
                     dy_r <= dyn;
                     if diy_s and dyn(15) = '1' then
                        asx_r <= asx_r + resize(nx_r, 16);
                        done := true;      -- stop above the top
                     else
                        asx_r <= (asx_r + resize(nx_r, 16) - ny_r) and to_unsigned(1023, 16);
                     end if;
                  else
                     asx_r <= (asx_r - ny_r) and to_unsigned(1023, 16);
                  end if;
               else
                  -- Y major.
                  dyn := dy_r + ty_s;
                  dy_r <= dyn;
                  if diy_s and dyn(15) = '1' then
                     done := true;         -- stop above the top
                  else
                     a := adx_r;
                     if asx_r < ny_r then
                        unit_delta_r <= to_unsigned(84 + 36, 8);
                        a := adx_r + tx_s;
                        asx_r <= (asx_r + resize(nx_r, 16) - ny_r) and to_unsigned(1023, 16);
                     else
                        asx_r <= (asx_r - ny_r) and to_unsigned(1023, 16);
                     end if;
                     adx_r <= a;
                     anx_r <= anx_r + 1;
                     if anx_r = resize(nx_r, 16) or a(ppl_bit_s) = '1' then
                        done := true;
                     end if;
                  end if;
               end if;

            when C_LMMV | C_LMMM | C_LMCM | C_LMMC | C_HMMV | C_HMMM | C_YMMM | C_HMMC =>
               two := cmd_s = C_LMMM or cmd_s = C_HMMM or cmd_s = C_YMMM;
               -- Delay to the next pixel / byte, longer after the last of a line.
               case cmd_s is
               when C_LMMV => dl_main := 72; dl_eol := 72 + 58;
               when C_LMMM => dl_main := 60; dl_eol := 60 + 68;
               when C_HMMV => dl_main := 46; dl_eol := 46 + 58;
               when C_HMMM => dl_main := 60; dl_eol := 60 + 68;
               when C_YMMM => dl_main := 36; dl_eol := 36 + 68;
               when others => dl_main := 1;  dl_eol := 1;      -- transfers: the CPU paces them
               end case;
               unit_delta_r <= to_unsigned(dl_main, 8);
               if cmd_s /= C_LMCM then adx_r <= adx_r + tx_s; end if;
               if cmd_s = C_LMMM or cmd_s = C_HMMM or cmd_s = C_LMCM then
                  asx_r <= asx_r + tx_s;
               end if;
               if anx_r = 1 then
                  -- End of the line.
                  unit_delta_r <= to_unsigned(dl_eol, 8);
                  if two or cmd_s = C_LMCM then sy_r <= sy_r + ty_s; end if;
                  if cmd_s /= C_LMCM then dy_r <= dy_r + ty_s; end if;
                  ny_dec := ny_r - 1;
                  if cmd_s = C_LMMM or cmd_s = C_HMMM or cmd_s = C_LMCM then
                     asx_r <= resize(sx_r, 16);
                  end if;
                  if cmd_s /= C_LMCM then adx_r <= resize(dx_r, 16); end if;
                  anx_r <= resize(tmp_nx, 16);
                  if tmp_ny = 1 then
                     ny_r <= ny_dec;
                     done := true;
                  else
                     tmp_ny <= tmp_ny - 1;
                     if xfer_cmd_s then
                        ny_r <= ny_dec;    -- masked at the next transfer
                     else
                        ny_r <= ny_dec and to_unsigned(1023, 16);
                     end if;
                  end if;
               else
                  anx_r <= anx_r - 1;
               end if;

            when others =>
               done := true;
            end case;

            if done then
               finish;
            elsif xfer_cmd_s then
               state <= S_XWAIT;
            else
               state <= S_UNIT;
            end if;

         -- VRAM access.
         when S_RD =>
            if mem_ack = '1' then
               req_r <= '0';
               state <= S_RD_DATA;
            end if;

         when S_RD_DATA =>
            if mem_rvalid = '1' then
               rdata <= unsigned(mem_din);
               state <= ret_st;
            end if;

         when S_WR =>
            if mem_ack = '1' then
               req_r <= '0';
               we_r  <= '0';
               state <= ret_st;
            end if;

         end case;

         -- A mode without commands stops the command.
         if mode_ok = '0' and ce_r = '1' then
            req_r <= '0';
            we_r  <= '0';
            finish;
         end if;

         -- S#7 read.
         if s7_rd = '1' then
            if ce_r = '0' then tr_r <= '0'; end if;
            xfer_r <= '1';
         end if;

         -- S#9 read clears BD.
         if s9_rd = '1' then
            bd_r <= '0';
         end if;

         -- CPU register writes.
         if reg_we = '1' then
            case to_integer(reg_idx) is
            when 0  => sx_r(7 downto 0) <= unsigned(reg_din);
            when 1  => sx_r(8) <= reg_din(7);
            when 2  => sy_r <= "000000" & sy_r(9 downto 8) & unsigned(reg_din);
            when 3  => sy_r <= "000000" & unsigned(reg_din(6 to 7)) & sy_r(7 downto 0);
            when 4  => dx_r(7 downto 0) <= unsigned(reg_din);
            when 5  => dx_r(8) <= reg_din(7);
            when 6  => dy_r <= "000000" & dy_r(9 downto 8) & unsigned(reg_din);
            when 7  => dy_r <= "000000" & unsigned(reg_din(6 to 7)) & dy_r(7 downto 0);
            when 8  => nx_r(7 downto 0) <= unsigned(reg_din);
            when 9  => nx_r(9 downto 8) <= unsigned(reg_din(6 to 7));
            when 10 => ny_r <= "000000" & ny_r(9 downto 8) & unsigned(reg_din);
            when 11 => ny_r <= "000000" & unsigned(reg_din(6 to 7)) & ny_r(7 downto 0);
            when 12 =>
               col_r <= unsigned(reg_din);
               if ce_r = '0' then tr_r <= '0'; end if;
               xfer_r <= '1';
            when 13 => arg_r <= unsigned(reg_din);
            when 14 =>
               -- Start (or restart, or STOP).
               cmd_r <= unsigned(reg_din);
               req_r <= '0';
               we_r  <= '0';
               if mode_ok = '0' or reg_din(0 to 1) = "00" then
                  ce_r  <= '0';
                  cmd_r <= (others => '0');
                  state <= S_IDLE;
               else
                  ce_r  <= '1';
                  state <= S_SETUP;
                  since_r <= (others => '0');
                  unit_delta_r <= to_unsigned(START_DELTA(to_integer(unsigned(reg_din(0 to 3)))), 8);
               end if;
            when others =>
               null;
            end case;
         end if;

      end if;
      end if;
   end process;

   tr       <= tr_r;
   bd       <= bd_r;
   ce       <= ce_r;
   busy     <= '0' when state = S_IDLE or state = S_XWAIT else '1';
   col      <= std_logic_vector(col_r);
   asx      <= std_logic_vector(asx_r(8 downto 0));
   mem_req  <= req_r and go_r;

   -- Command slot at this cycle.
   slot_s <= SLOTS_SCREEN_OFF(to_integer(cyc)) when scr_on = '0' else
             SLOTS_SPRITES_ON(to_integer(cyc)) when spr_on = '1' else
             SLOTS_SPRITES_OFF(to_integer(cyc));
   mem_we   <= we_r;
   mem_addr <= std_logic_vector(addr_r);
   mem_dout <= std_logic_vector(dout_r);

end rtl;
