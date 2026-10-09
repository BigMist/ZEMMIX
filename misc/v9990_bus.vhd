--
-- v9990_bus.vhd: the MSX I/O ports 60h-6Fh to the host bus of the V9990
-- core (v9990/rtl/v9990_core.vhd), ZEMMIX-1os.5.
--
-- clk21m side: an IN / OUT on 60h-6Fh holds the cpu with wait_n until the
-- V9990 has taken it (OUT) or given its data (IN: dbi is valid when wait_n
-- goes high, and until the next access).  Writes wait too: the V9990 takes a request only when its
-- previous VRAM access is done, and the order of the accesses is kept.
--
-- V9990 side (v_clk, 42.95 MHz from the same PLL as clk21m: no
-- synchronizers): v_req held with v_wrt / v_adr / v_dbo until v_ack (one
-- clock), v_dbi valid with v_ack.  The request crosses as a toggle.
--
-- int_n: the V9990 interrupt, registered in clk21m for INT_n.
--
library ieee;
    use ieee.std_logic_1164.all;

entity v9990_bus is
    port(
        clk21m      : in    std_logic;
        reset       : in    std_logic;
        cs          : in    std_logic;                          -- I/O 60h-6Fh (IORQ low)
        rd_n        : in    std_logic;
        wr_n        : in    std_logic;
        adr         : in    std_logic_vector(  3 downto 0 );
        dbo         : in    std_logic_vector(  7 downto 0 );
        dbi         : out   std_logic_vector(  7 downto 0 );
        wait_n      : out   std_logic;
        int_n       : out   std_logic;

        v_clk       : in    std_logic;
        v_reset_n   : out   std_logic;
        v_req       : out   std_logic;
        v_wrt       : out   std_logic;
        v_adr       : out   std_logic_vector(  3 downto 0 );
        v_dbo       : out   std_logic_vector(  7 downto 0 );
        v_ack       : in    std_logic;
        v_dbi       : in    std_logic_vector(  7 downto 0 );
        v_int_n     : in    std_logic
    );
end v9990_bus;

architecture rtl of v9990_bus is

    -- clk21m
    signal  ff_req_t    : std_logic := '0';
    signal  ff_started  : std_logic := '0';                     -- this I/O cycle has its request
    signal  ff_wrt      : std_logic := '0';
    signal  ff_adr      : std_logic_vector(  3 downto 0 ) := (others => '0');
    signal  ff_dbo      : std_logic_vector(  7 downto 0 ) := (others => '0');
    signal  ff_int_n    : std_logic := '1';
    signal  busy        : std_logic;
    signal  access_s    : std_logic;

    -- v_clk
    signal  ff_seen_t   : std_logic := '0';
    signal  ff_done_t   : std_logic := '0';
    signal  ff_v_req    : std_logic := '0';
    signal  ff_v_dbi    : std_logic_vector(  7 downto 0 ) := (others => '1');
    signal  ff_v_rst    : std_logic_vector(  1 downto 0 ) := "00";

begin

    access_s <= cs and (not rd_n or not wr_n);
    busy     <= ff_req_t xor ff_done_t;

    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            ff_int_n <= v_int_n;
            if( access_s = '0' )then
                ff_started <= '0';
            elsif( ff_started = '0' and busy = '0' )then
                ff_started <= '1';
                ff_wrt     <= not wr_n;
                ff_adr     <= adr;
                ff_dbo     <= dbo;
                ff_req_t   <= not ff_req_t;
            end if;
        end if;
    end process;

    wait_n <= '0' when( access_s = '1' and (ff_started = '0' or busy = '1') )else '1';
    dbi    <= ff_v_dbi;                                         -- set with done, kept until the next access
    int_n  <= ff_int_n;

    process( v_clk )
    begin
        if( v_clk'event and v_clk = '1' )then
            ff_v_rst <= ff_v_rst(0) & not reset;
            if( ff_v_req = '1' )then
                if( v_ack = '1' )then
                    ff_v_req  <= '0';
                    ff_v_dbi  <= v_dbi;
                    ff_done_t <= ff_seen_t;
                end if;
            elsif( ff_seen_t /= ff_req_t )then
                ff_seen_t <= ff_req_t;
                ff_v_req  <= '1';
            end if;
        end if;
    end process;

    v_reset_n <= ff_v_rst(1);
    v_req     <= ff_v_req;
    v_wrt     <= ff_wrt;
    v_adr     <= ff_adr;
    v_dbo     <= ff_dbo;

end rtl;
