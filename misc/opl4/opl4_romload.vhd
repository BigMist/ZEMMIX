--
-- opl4_romload.vhd
--   Loads the YRW801 (ZEMMIX.ROM, 2 MB) into the OPL4 wave memory (ZEMMIX-0au.5).
--   The MiST firmware sends <core>.ROM through data_io index 0 when the core
--   starts, with no flow control, while the SDRAM may not be ready yet (the OCM
--   RstSeq takes about 24 ms): the bytes go through a FIFO and are written in
--   order from address 000000h. ioctl_addr is not used, data_io sends the file
--   from its start.
--
--   Between the wave memory client (c_*: the 7Eh/7Fh test, later the PCM engine)
--   and the SDRAM port (m_*): the loader goes first, the client waits.
--
--   Debug counters (24 bits): bytes received, bytes lost (FIFO full).
--   They are not reset by the MSX reset (the firmware resets the core while it
--   sends the file), only at power on.
--
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_unsigned.all;

entity opl4_romload is
    generic(
        FIFO_AW     : integer := 12                             -- 4096 bytes
    );
    port(
        clk21m      : in    std_logic;

        dl          : in    std_logic;                          -- data_io download of index 0
        dl_wr       : in    std_logic;
        dl_dat      : in    std_logic_vector(  7 downto 0 );

        c_req_t     : in    std_logic;
        c_done_t    : out   std_logic;
        c_we        : in    std_logic;
        c_adr       : in    std_logic_vector( 21 downto 0 );
        c_wdat      : in    std_logic_vector(  7 downto 0 );
        c_rdat      : out   std_logic_vector( 15 downto 0 );

        m_req_t     : out   std_logic;
        m_done_t    : in    std_logic;
        m_we        : out   std_logic;
        m_adr       : out   std_logic_vector( 21 downto 0 );
        m_wdat      : out   std_logic_vector(  7 downto 0 );
        m_rdat      : in    std_logic_vector( 15 downto 0 );

        rcv_cnt     : out   std_logic_vector( 23 downto 0 );
        lost_cnt    : out   std_logic_vector( 23 downto 0 );
        loading     : out   std_logic                           -- download or FIFO not empty
    );
end opl4_romload;

architecture RTL of opl4_romload is
    type fifo_t is array( 0 to 2**FIFO_AW - 1 ) of std_logic_vector( 7 downto 0 );
    signal  fifo        : fifo_t;
    signal  ff_wp       : std_logic_vector( FIFO_AW-1 downto 0 ) := (others => '0');
    signal  ff_rp       : std_logic_vector( FIFO_AW-1 downto 0 ) := (others => '0');
    signal  ff_q        : std_logic_vector(  7 downto 0 ) := (others => '0');
    signal  fifo_empty  : std_logic;
    signal  fifo_full   : std_logic;

    signal  ff_dl       : std_logic := '0';
    signal  ff_ladr     : std_logic_vector( 21 downto 0 ) := (others => '0');  -- next loader address
    signal  ff_rcv      : std_logic_vector( 23 downto 0 ) := (others => '0');
    signal  ff_lost     : std_logic_vector( 23 downto 0 ) := (others => '0');

    -- SDRAM port: one access in flight, from the loader or from the client
    signal  ff_m_req_t  : std_logic := '0';
    signal  ff_m_we     : std_logic := '0';
    signal  ff_m_adr    : std_logic_vector( 21 downto 0 ) := (others => '0');
    signal  ff_m_wdat   : std_logic_vector(  7 downto 0 ) := (others => '0');
    signal  ff_own      : std_logic := '0';                     -- 1 = the access in flight is the client's
    signal  ff_c_done_t : std_logic := '0';
    signal  ff_c_rdat   : std_logic_vector( 15 downto 0 ) := (others => '1');
    signal  ff_rd_ok    : std_logic := '0';                     -- ff_q holds fifo(ff_rp)
    signal  m_busy      : std_logic;
    signal  c_pend      : std_logic;
begin

    fifo_empty <= '1' when( ff_wp = ff_rp )else '0';
    fifo_full  <= '1' when( (ff_wp + 1) = ff_rp )else '0';
    m_busy     <= ff_m_req_t xor m_done_t;
    c_pend     <= c_req_t xor ff_c_done_t;

    -- FIFO write side: the bytes of data_io index 0
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            ff_dl <= dl;
            if( dl = '1' and ff_dl = '0' )then                  -- a new download starts at 000000h
                ff_rcv  <= (others => '0');
                ff_lost <= (others => '0');
            elsif( dl = '1' and dl_wr = '1' )then
                ff_rcv <= ff_rcv + 1;
                if( fifo_full = '0' )then
                    fifo( conv_integer(ff_wp) ) <= dl_dat;
                    ff_wp <= ff_wp + 1;
                else
                    ff_lost <= ff_lost + 1;
                end if;
            end if;
        end if;
    end process;

    -- FIFO read (registered, M9K)
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            ff_q <= fifo( conv_integer(ff_rp) );
        end if;
    end process;

    -- SDRAM port
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            if( dl = '1' and ff_dl = '0' )then
                ff_ladr <= (others => '0');
            end if;

            if( m_busy = '0' )then
                if( ff_own = '1' )then                          -- give the client its answer
                    ff_c_rdat   <= m_rdat;
                    ff_c_done_t <= c_req_t;
                    ff_own      <= '0';
                    ff_rd_ok    <= '0';
                elsif( fifo_empty = '0' and ff_rd_ok = '1' )then    -- loader first
                    ff_m_we     <= '1';
                    ff_m_adr    <= ff_ladr;
                    ff_m_wdat   <= ff_q;
                    ff_m_req_t  <= not ff_m_req_t;
                    ff_ladr     <= ff_ladr + 1;
                    ff_rp       <= ff_rp + 1;
                    ff_rd_ok    <= '0';
                elsif( fifo_empty = '0' )then
                    ff_rd_ok    <= '1';                         -- ff_q is valid on the next clock
                elsif( c_pend = '1' )then
                    ff_m_we     <= c_we;
                    ff_m_adr    <= c_adr;
                    ff_m_wdat   <= c_wdat;
                    ff_m_req_t  <= not ff_m_req_t;
                    ff_own      <= '1';
                end if;
            end if;
        end if;
    end process;

    m_req_t  <= ff_m_req_t;
    m_we     <= ff_m_we;
    m_adr    <= ff_m_adr;
    m_wdat   <= ff_m_wdat;
    c_done_t <= ff_c_done_t;
    c_rdat   <= ff_c_rdat;

    rcv_cnt  <= ff_rcv;
    lost_cnt <= ff_lost;
    loading  <= dl or not fifo_empty;
end RTL;
