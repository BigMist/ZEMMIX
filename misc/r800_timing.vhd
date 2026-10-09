--
-- r800_timing.vhd
--   R800 speed regulator for the T80s that plays the R800 (MSXtR)
--
-- The T80s runs on clk21m with Z80 bus cycles, so most instructions take
-- a different time than on a real R800. This block keeps the time a real
-- R800 would have reached (in R800 cycles, 1 cycle = 3 x clk21m) with the
-- openMSX R800 rules and holds the T80s when it goes ahead of it:
--  * opcode/operand fetch : 1 cycle, +1 on a DRAM page break (256 bytes)
--  * data access          : 1 cycle + page break (not on the 2nd byte of a word)
--  * internal ROM / external slot : +1 / +2 per access (ROM: no page mode)
--  * I/O                  : 1 cycle, wait for an even cycle, 6 cycles,
--                           VDP ports at least 62 cycles apart
--  * refresh              : 25 cycles every 210 (on an even cycle)
--  * a few instructions have internal cycles (table), a taken jump +1
-- The T80s is held at the T1 of an M1 while it is early, and an I/O access
-- is held until its exact time. When it is late (an R800 NOP is 1 cycle, a
-- T80s M1 is 4 clk21m), the delay is kept, up to c_lim cycles, so that the
-- next fast instructions catch up.
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity r800_timing is
    generic(
        c_lim       : integer := 32                                     -- late cycles that can be caught up
    );
    port(
        clk21m      : in    std_logic;
        reset       : in    std_logic;
        active      : in    std_logic;                                  -- the R800 is the running CPU
        m1_n        : in    std_logic;
        merq_n      : in    std_logic;
        iorq_n      : in    std_logic;
        rd_n        : in    std_logic;
        wr_n        : in    std_logic;
        rfsh_n      : in    std_logic;
        wait_n      : in    std_logic;
        adr         : in    std_logic_vector( 15 downto 0 );
        di          : in    std_logic_vector(  7 downto 0 );            -- data read by the R800 (opcodes)
        ppi_a       : in    std_logic_vector(  7 downto 0 );            -- primary slots
        exp0        : in    std_logic_vector(  7 downto 0 );            -- secondary slots of slot 0
        exp3        : in    std_logic_vector(  7 downto 0 );            -- secondary slots of slot 3
        dram_mode   : in    std_logic;                                  -- S1990 R#6 bit6 = 0
        stall       : out   std_logic;                                  -- hold the T80s (clock enable off)
        io_hold     : out   std_logic                                   -- hold the I/O request
    );
end r800_timing;

architecture rtl of r800_timing is
    subtype u16 is unsigned( 15 downto 0 );

    signal ff_e         : u16 := (others => '0');                       -- R800 cycles elapsed
    signal ff_ph        : unsigned(  1 downto 0 ) := "00";
    signal ff_v         : u16 := (others => '0');                       -- R800 cycles a real R800 would have used
    signal ff_lref      : u16 := (others => '0');                       -- last refresh
    signal ff_lvdp      : u16 := (others => '0');                       -- last VDP access
    signal ff_act       : std_logic := '0';

    signal ff_page      : std_logic_vector(  7 downto 0 ) := (others => '0');
    signal ff_page_ok   : std_logic := '0';
    signal ff_exp_pc    : std_logic_vector( 15 downto 0 ) := (others => '0');
    signal ff_data      : std_logic := '0';                             -- this instruction did a data access
    signal ff_last_data : std_logic := '0';                             -- the last access was a data access
    signal ff_last_adr  : std_logic_vector( 15 downto 0 ) := (others => '0');
    signal ff_op        : std_logic_vector(  7 downto 0 ) := (others => '0');
    signal ff_pfx       : std_logic_vector(  1 downto 0 ) := "00";      -- 00: none, 01: CB, 10: ED, 11: DD/FD
    signal ff_acc_d     : std_logic := '0';
    signal ff_bnd_done  : std_logic := '0';
    signal ff_io_done   : std_logic := '0';
    signal ff_io_hold   : std_logic := '0';

    signal w_mem_rd     : std_logic;
    signal w_mem_wr     : std_logic;
    signal w_io         : std_logic;
    signal w_inta       : std_logic;
    signal w_acc        : std_logic;
    signal w_t1         : std_logic;
    signal w_dly        : unsigned(  1 downto 0 );
    signal w_prefix     : std_logic;
    signal w_extra      : unsigned(  5 downto 0 );
    signal w_v1         : u16;
    signal w_refresh    : std_logic;
    signal w_v2         : u16;
    signal w_v3         : u16;
    signal w_stall      : std_logic;
    signal w_t_io0      : u16;
    signal w_t_io       : u16;
    signal w_vdp        : std_logic;
    signal w_io_hold    : std_logic;

    function even( v : u16 ) return u16 is
    begin
        if( v(0) = '1' )then
            return v + 1;
        else
            return v;
        end if;
    end function;
begin
    w_mem_rd    <= '1' when( merq_n = '0' and rd_n = '0' and rfsh_n = '1' )else '0';
    w_mem_wr    <= '1' when( merq_n = '0' and wr_n = '0' )else '0';
    w_io        <= '1' when( iorq_n = '0' and m1_n = '1' and (rd_n = '0' or wr_n = '0') )else '0';
    w_inta      <= '1' when( iorq_n = '0' and m1_n = '0' )else '0';
    w_acc       <= w_mem_rd or w_mem_wr or w_inta;
    w_t1        <= '1' when( m1_n = '0' and merq_n = '1' and iorq_n = '1' )else '0';

    -- extra delay of the accessed slot: 0 = RAM (3-0), 1 = internal ROM, 2 = external slot
    process( adr, ppi_a, exp0, exp3, dram_mode )
        variable p      : integer range 0 to 3;
        variable prim   : std_logic_vector( 1 downto 0 );
        variable sec    : std_logic_vector( 1 downto 0 );
    begin
        p := to_integer( unsigned(adr(15 downto 14)) );
        prim := ppi_a( 2*p+1 downto 2*p );
        if( prim = "00" )then
            sec := exp0( 2*p+1 downto 2*p );
        elsif( prim = "11" )then
            sec := exp3( 2*p+1 downto 2*p );
        else
            sec := "00";
        end if;
        if( prim = "01" or prim = "10" )then
            w_dly <= "10";
        elsif( prim = "11" and sec = "00" )then
            w_dly <= "00";
        elsif( dram_mode = '1' and p < 2 and ((prim = "00" and sec = "00") or (prim = "11" and sec = "01")) )then
            w_dly <= "00";                                              -- BIOS / SUB-ROM copied to DRAM
        else
            w_dly <= "01";
        end if;
    end process;

    -- the last M1 opcode is a prefix: the instruction goes on
    w_prefix    <= '1' when( (ff_op = X"CB" or ff_op = X"ED" or ff_op = X"DD" or ff_op = X"FD") and
                             not (ff_pfx = "11" and ff_op = X"CB") )else '0';

    -- internal cycles of the instruction that ends at this M1
    process( ff_op, ff_pfx, ff_data, ff_exp_pc, adr )
        variable x : unsigned( 5 downto 0 );
        variable o : std_logic_vector( 7 downto 0 );
    begin
        o := ff_op;
        x := (others => '0');
        case ff_pfx is
        when "00" =>
            if( o = X"C5" or o = X"D5" or o = X"E5" or o = X"F5" )then             -- PUSH
                x := to_unsigned( 1, 6 );
            elsif( o(7 downto 6) = "11" and o(2 downto 0) = "111" )then             -- RST
                x := to_unsigned( 1, 6 );
            elsif( o = X"F3" or o = X"34" or o = X"35" )then                        -- DI, INC/DEC (HL)
                x := to_unsigned( 1, 6 );
            end if;
        when "01" =>
            if( o(2 downto 0) = "110" and o(7 downto 6) /= "01" )then               -- rotate/SET/RES (HL)
                x := to_unsigned( 1, 6 );
            end if;
        when "10" =>
            if( o = X"C1" or o = X"C9" or o = X"D1" or o = X"D9" )then              -- MULUB: 14
                x := to_unsigned( 12, 6 );
            elsif( o = X"C3" or o = X"F3" )then                                     -- MULUW: 36
                x := to_unsigned( 34, 6 );
            elsif( (o(7 downto 6) = "01" and o(2 downto 0) = "110") or              -- IM
                   o = X"67" or o = X"6F" or                                        -- RRD, RLD
                   o = X"A1" or o = X"A9" or o = X"B1" or o = X"B9" )then           -- CPI, CPD, CPIR, CPDR
                x := to_unsigned( 1, 6 );
            end if;
        when others =>
            if( o = X"34" or o = X"35" )then                                        -- INC/DEC (IX+d)
                x := to_unsigned( 2, 6 );
            elsif( o = X"E5" or o = X"36" or o = X"CB" or                           -- PUSH IX, LD (IX+d),n, DD CB
                   (o(7 downto 6) = "01" and o(2 downto 0) = "110" and o /= X"76") or
                   (o(7 downto 3) = "01110" and o /= X"76") or
                   (o(7 downto 6) = "10" and o(2 downto 0) = "110") )then
                x := to_unsigned( 1, 6 );
            end if;
        end case;
        -- a jump taken without data access (JP, JR, DJNZ, JP (HL))
        if( ff_data = '0' and adr /= ff_exp_pc )then
            x := x + 1;
        end if;
        w_extra <= x;
    end process;

    -- time at this M1: internal cycles, refresh, limit of the late cycles
    w_v1        <= ff_v + resize( w_extra, 16 ) when( w_prefix = '0' )else ff_v;
    w_refresh   <= '1' when( w_prefix = '0' and (w_v1 - ff_lref) >= 210 )else '0';
    w_v2        <= even( w_v1 ) + 25 when( w_refresh = '1' )else w_v1;
    w_v3        <= ff_e - to_unsigned( c_lim, 16 ) when( signed(ff_e - w_v2) > c_lim )else w_v2;

    w_stall     <= '1' when( active = '1' and ff_act = '1' and w_t1 = '1' and ff_bnd_done = '0' and
                             signed(w_v3 - ff_e) > 0 )else '0';

    -- time of an I/O access: 1 cycle, next even cycle, VDP 62 cycles after the last one
    w_vdp       <= '1' when( adr(7 downto 2) = "100110" )else '0';
    w_t_io0     <= even( ff_v + 1 );
    w_t_io      <= ff_lvdp + 62 when( w_vdp = '1' and signed(ff_lvdp + 62 - w_t_io0) > 0 )else w_t_io0;
    w_io_hold   <= '1' when( active = '1' and ff_act = '1' and w_io = '1' and ff_io_done = '0' and
                             signed(w_t_io - ff_e) > 0 )else '0';

    stall       <= w_stall;
    -- registered: req comes from the internal bus registers, one clock after the R800 signals
    io_hold     <= ff_io_hold;

    process( reset, clk21m )
        variable c : unsigned( 2 downto 0 );
    begin
        if( reset = '1' )then
            ff_e        <= (others => '0');
            ff_ph       <= "00";
            ff_v        <= (others => '0');
            ff_lref     <= (others => '0');
            ff_lvdp     <= (others => '0');
            ff_act      <= '0';
            ff_page_ok  <= '0';
            ff_data     <= '0';
            ff_last_data<= '0';
            ff_op       <= (others => '0');
            ff_pfx      <= "00";
            ff_acc_d    <= '0';
            ff_bnd_done <= '0';
            ff_io_done  <= '0';
            ff_io_hold  <= '0';
        elsif( clk21m'event and clk21m = '1' )then
            ff_io_hold <= w_io_hold;
            -- R800 time
            if( active = '1' )then
                if( ff_ph = "10" )then
                    ff_ph <= "00";
                    ff_e  <= ff_e + 1;
                else
                    ff_ph <= ff_ph + 1;
                end if;
            end if;

            ff_act <= active;
            if( active = '1' and ff_act = '0' )then
                -- the R800 starts running: it is on time
                ff_v        <= ff_e;
                ff_lref     <= ff_e;
                ff_lvdp     <= ff_e - 62;
                ff_page_ok  <= '0';
            elsif( active = '1' )then
                -- M1: end of the last instruction
                if( w_t1 = '1' and ff_bnd_done = '0' and w_stall = '0' )then
                    ff_bnd_done <= '1';
                    ff_v <= w_v3;
                    if( w_refresh = '1' )then
                        ff_lref    <= ff_lref + 210;
                        ff_page_ok <= '0';
                    end if;
                    if( w_prefix = '0' )then
                        ff_data      <= '0';
                        ff_last_data <= '0';
                        if( ff_op = X"DD" or ff_op = X"FD" )then
                            ff_pfx <= "11";
                        else
                            ff_pfx <= "00";
                        end if;
                    elsif( ff_op = X"CB" )then
                        ff_pfx <= "01";
                    elsif( ff_op = X"ED" )then
                        ff_pfx <= "10";
                    else
                        ff_pfx <= "11";
                    end if;
                elsif( m1_n = '1' )then
                    ff_bnd_done <= '0';
                end if;

                -- opcode of the M1
                if( m1_n = '0' and w_mem_rd = '1' and wait_n = '1' )then
                    ff_op <= di;
                end if;

                -- cost of a memory access, at its start
                ff_acc_d <= w_acc;
                if( w_acc = '1' and ff_acc_d = '0' )then
                    if( w_inta = '1' )then
                        ff_v    <= ff_v + 1;
                        ff_data <= '1';
                        ff_last_data <= '0';
                    elsif( w_mem_rd = '1' and (m1_n = '0' or (adr = ff_exp_pc and ff_data = '0')) )then
                        -- opcode / operand fetch
                        c := "001" + resize( w_dly, 3 );
                        if( ff_page_ok = '0' or adr(15 downto 8) /= ff_page or w_dly /= "00" )then
                            c := c + 1;
                        end if;
                        ff_v        <= ff_v + resize( c, 16 );
                        ff_page     <= adr(15 downto 8);
                        ff_page_ok  <= '1';
                        ff_exp_pc   <= std_logic_vector( unsigned(adr) + 1 );
                        ff_last_data<= '0';
                    else
                        -- data access
                        c := "001" + resize( w_dly, 3 );
                        if( not (ff_last_data = '1' and
                                 (unsigned(adr) = unsigned(ff_last_adr) + 1 or unsigned(adr) = unsigned(ff_last_adr) - 1)) )then
                            c := c + 1;
                        end if;
                        ff_v        <= ff_v + resize( c, 16 );
                        ff_page_ok  <= '0';
                        ff_data     <= '1';
                        ff_last_data<= '1';
                        ff_last_adr <= adr;
                    end if;
                end if;

                -- I/O access: at its time
                if( w_io = '1' and ff_io_done = '0' and w_io_hold = '0' )then
                    ff_io_done  <= '1';
                    ff_v        <= w_t_io + 6;
                    ff_data     <= '1';
                    ff_last_data<= '0';
                    if( w_vdp = '1' )then
                        ff_lvdp <= w_t_io;
                    end if;
                elsif( w_io = '0' )then
                    ff_io_done  <= '0';
                end if;
            end if;
        end if;
    end process;
end rtl;
