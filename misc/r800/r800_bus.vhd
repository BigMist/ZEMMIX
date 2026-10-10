--
-- r800_bus.vhd
--   Bus of the R800 core (misc/r800/r800_*.v, derived from NextZ80 by Nicolae
--   Dumitrache, LGPL) with the T80s ports, so that it can take the place of
--   the T80s of U01_R8 (ZEMMIX-i8e.4).
--
-- The R800 core does one bus access per clock with the data read in that clock,
-- about one clock per opcode byte plus one per access: the timing model of
-- the R800.  Here every access of the core becomes a T80 like bus cycle
-- on clk21m while the core is held (its WAIT):
--   T1   the clock the core shows the access: address, M1_n low for an
--        opcode fetch, strobes high (r800_timing and the CPU switch stop the
--        R800 at the T1 of an M1 with CEN)
--   T2   MREQ_n / IORQ_n with RD_n or WR_n (M1_n + IORQ_n for INTA) until
--        WAIT_n is high
--   T3   strobes kept; the data of the bus is there one clock after the wait
--        ends (as for the T80s): the core takes DI and goes on at its end
-- so an access lasts at least 3 clk21m, one R800 cycle, and r800_timing
-- holds the R800 to the real R800 time.  CEN low freezes it
-- all.  RFSH_n is a refresh request for the SDRAM of the OCM bus (it refreshes
-- on the CPU refresh): low 4 clocks (one CPU turn) every 128 (6 us), whatever the core does;
-- r800_timing models the time of the R800 refresh itself.
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity r800_bus is
    port(
        RESET_n     : in    std_logic;
        CLK         : in    std_logic;
        CEN         : in    std_logic;
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
        DI          : in    std_logic_vector(  7 downto 0 );
        DO          : out   std_logic_vector(  7 downto 0 )
    );
end r800_bus;

architecture rtl of r800_bus is

    component R800
        port(
            DI      : in    std_logic_vector(  7 downto 0 );
            DO      : out   std_logic_vector(  7 downto 0 );
            ADDR    : out   std_logic_vector( 15 downto 0 );
            WR      : out   std_logic;
            MREQ    : out   std_logic;
            IORQ    : out   std_logic;
            HALT    : out   std_logic;
            M1      : out   std_logic;
            CLK     : in    std_logic;
            RESET   : in    std_logic;
            INT     : in    std_logic;
            NMI     : in    std_logic;
            WAIT_I  : in    std_logic
        );
    end component;

    signal c_do        : std_logic_vector(  7 downto 0 );
    signal c_adr       : std_logic_vector( 15 downto 0 );
    signal c_wr        : std_logic;
    signal c_mreq      : std_logic;
    signal c_iorq      : std_logic;
    signal c_halt      : std_logic;
    signal c_m1        : std_logic;
    signal c_wait      : std_logic;
    signal c_reset     : std_logic;
    signal c_int       : std_logic;
    signal c_nmi       : std_logic;
    signal rfsh_cnt     : std_logic_vector(  6 downto 0 ) := (others => '0');
    signal w_acc        : std_logic;
    signal w_inta       : std_logic;
    signal t2           : std_logic := '0';     -- T2 (wait for WAIT_n)
    signal t3           : std_logic := '0';     -- T3 (data)

begin

    c_reset <= not RESET_n;
    c_int   <= not INT_n;
    c_nmi   <= not NMI_n;

    -- an access of the core in this clock, and the interrupt acknowledge
    w_acc   <= c_mreq or c_iorq;
    w_inta  <= c_iorq and c_m1;
    -- held while frozen, and during an access until the bus is done (WAIT_n in T2)
    -- the core takes the reset even when frozen (as the T80s): it starts again at 0
    c_wait <= '0' when( RESET_n = '0' )else
              '1' when( CEN = '0' )else
               '1' when( w_acc = '1' and t3 = '0' )else
               '0';

    u_cpu : R800
        port map(
            DI      => DI,
            DO      => c_do,
            ADDR    => c_adr,
            WR      => c_wr,
            MREQ    => c_mreq,
            IORQ    => c_iorq,
            HALT    => c_halt,
            M1      => c_m1,
            CLK     => CLK,
            RESET   => c_reset,
            INT     => c_int,
            NMI     => c_nmi,
            WAIT_I  => c_wait
        );

    process( CLK )
    begin
        if( CLK'event and CLK = '1' )then
            if( RESET_n = '0' )then
                t2 <= '0';
                t3 <= '0';
            elsif( CEN = '1' )then
                if( t3 = '1' )then
                    t3 <= '0';                          -- done: the core goes on now
                elsif( t2 = '1' )then
                    if( WAIT_n = '1' )then
                        t2 <= '0';
                        t3 <= '1';
                    end if;
                elsif( w_acc = '1' )then
                    t2 <= '1';
                end if;
            end if;
        end if;
    end process;

    -- SDRAM refresh request
    process( CLK )
    begin
        if( CLK'event and CLK = '1' )then
            if( RESET_n = '0' )then
                rfsh_cnt <= (others => '0');
            else
                rfsh_cnt <= std_logic_vector( unsigned( rfsh_cnt ) + 1 );
            end if;
        end if;
    end process;

    A       <= c_adr;
    DO      <= c_do;
    M1_n    <= '0' when( w_acc = '1' and c_m1 = '1' and RESET_n = '1' )else '1';
    MREQ_n  <= '0' when( (t2 = '1' or t3 = '1') and c_mreq = '1' )else '1';
    IORQ_n  <= '0' when( (t2 = '1' or t3 = '1') and c_iorq = '1' )else '1';
    RD_n    <= '0' when( (t2 = '1' or t3 = '1') and c_wr = '0' and w_inta = '0' )else '1';
    WR_n    <= '0' when( (t2 = '1' or t3 = '1') and c_wr = '1' )else '1';
    RFSH_n  <= '0' when( rfsh_cnt(6 downto 2) = "11111" )else '1';
    HALT_n  <= not c_halt;
    BUSAK_n <= '1';

end rtl;
