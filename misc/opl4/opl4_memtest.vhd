--
-- opl4_memtest.vhd
--   TEMPORARY test of the OPL4 wave memory in the SDRAM (ZEMMIX-0au.4): the memory
--   access registers of the YMF278B on ports 7Eh (index) / 7Fh (data), without the
--   PCM engine, so that MoonSound memory test tools (and a loader of the YRW801)
--   can write and read the 4 MB of wave memory.
--
--   reg 02h : read 20h (device ID 001), writes ignored
--   reg 03h : memory address  bits 21-16 (6 bits)
--   reg 04h : memory address  bits 15-8
--   reg 05h : memory address  bits 7-0, starts the read of that byte
--   reg 06h : memory data: a write stores the byte and increments the address,
--             a read gives the byte read before, increments the address and
--             starts the read of the next byte, as the real chip
--   7Eh read: status, bit 0 = BUSY (memory access pending or in progress)
--   reg FAh-FCh: ZEMMIX.ROM loader, bytes received (low byte first), FDh-FFh: bytes lost
--
--   One access at a time: a write that comes while another write is still pending
--   replaces it (an access takes a few hundred ns, an OUT of the Z80 some us).
--
--   Wave memory port (clk21m side): a request toggles wave_req_t with wave_we,
--   wave_adr and wave_wdat stable, it is done when wave_done_t equals wave_req_t
--   (wave_rdat is the 16-bit word of the SDRAM, the byte is chosen by wave_adr(0)).
--
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_unsigned.all;

entity opl4_memtest is
    port(
        clk21m      : in    std_logic;
        reset       : in    std_logic;
        req         : in    std_logic;                          -- I/O 7E-7Fh
        wrt         : in    std_logic;
        adr0        : in    std_logic;
        dbi         : out   std_logic_vector(  7 downto 0 );
        dbo         : in    std_logic_vector(  7 downto 0 );

        wave_req_t  : out   std_logic;
        wave_done_t : in    std_logic;
        wave_we     : out   std_logic;
        wave_adr    : out   std_logic_vector( 21 downto 0 );
        wave_wdat   : out   std_logic_vector(  7 downto 0 );
        wave_rdat   : in    std_logic_vector( 15 downto 0 );

        dbg_rcv     : in    std_logic_vector( 23 downto 0 );   -- ZEMMIX.ROM loader: bytes received
        dbg_lost    : in    std_logic_vector( 23 downto 0 )    -- and lost
    );
end opl4_memtest;

architecture RTL of opl4_memtest is
    signal  ff_req      : std_logic := '0';                     -- req of the previous clock
    signal  ff_index    : std_logic_vector(  7 downto 0 ) := (others => '0');
    signal  ff_adr      : std_logic_vector( 21 downto 0 ) := (others => '0');   -- memory address register
    signal  ff_fadr     : std_logic_vector( 21 downto 0 ) := (others => '0');   -- address of the access in flight
    signal  ff_wdat     : std_logic_vector(  7 downto 0 ) := (others => '0');
    signal  ff_memdat   : std_logic_vector(  7 downto 0 ) := (others => '1');
    signal  ff_rdout    : std_logic_vector(  7 downto 0 ) := (others => '1');   -- byte given to the CPU (frozen for the whole IN)
    signal  ff_req_t    : std_logic := '0';
    signal  ff_done_t   : std_logic := '0';                     -- wave_done_t of the previous clock
    signal  ff_we       : std_logic := '0';                     -- the access in flight is a write
    signal  ff_wr_pend  : std_logic := '0';
    signal  ff_rd_pend  : std_logic := '0';
    signal  busy        : std_logic;
    signal  io_strobe   : std_logic;
begin

    busy      <= ff_req_t xor wave_done_t;
    io_strobe <= req and not ff_req;                            -- once per I/O cycle

    process( reset, clk21m )
    begin
        if( reset = '1' )then
            ff_req      <= '0';
            ff_index    <= (others => '0');
            ff_adr      <= (others => '0');
            ff_fadr     <= (others => '0');
            ff_wdat     <= (others => '0');
            ff_memdat   <= (others => '1');
            ff_rdout    <= (others => '1');
            ff_we       <= '0';
            ff_wr_pend  <= '0';
            ff_rd_pend  <= '0';
            ff_done_t   <= '0';
            ff_req_t    <= '0';                                 -- after a reset at most one spurious read is done
        elsif( clk21m'event and clk21m = '1' )then
            ff_req      <= req;
            ff_done_t   <= wave_done_t;

            -- a read finished: keep its byte
            if( ff_done_t /= wave_done_t and ff_we = '0' )then
                if( ff_fadr(0) = '0' )then
                    ff_memdat <= wave_rdat(  7 downto 0 );
                else
                    ff_memdat <= wave_rdat( 15 downto 8 );
                end if;
            end if;

            if( io_strobe = '1' )then
                if( wrt = '1' and adr0 = '0' )then
                    ff_index <= dbo;
                elsif( wrt = '1' )then
                    case ff_index is
                        when X"03" =>   ff_adr( 21 downto 16 ) <= dbo( 5 downto 0 );
                        when X"04" =>   ff_adr( 15 downto  8 ) <= dbo;
                        when X"05" =>   ff_adr(  7 downto  0 ) <= dbo;
                                        ff_rd_pend <= '1';
                        when X"06" =>   ff_wdat    <= dbo;
                                        ff_wr_pend <= '1';
                                        ff_rd_pend <= '0';
                        when others =>  null;
                    end case;
                elsif( adr0 = '1' and ff_index = X"06" )then    -- read of the data: next byte
                    ff_rdout   <= ff_memdat;
                    ff_adr     <= ff_adr + 1;
                    ff_rd_pend <= '1';
                end if;
            -- start a pending access when the memory is free (not in an I/O strobe clock)
            elsif( busy = '0' and ff_wr_pend = '1' )then
                ff_fadr    <= ff_adr;
                ff_we      <= '1';
                ff_req_t   <= not ff_req_t;
                ff_wr_pend <= '0';
                ff_adr     <= ff_adr + 1;
            elsif( busy = '0' and ff_rd_pend = '1' )then
                ff_fadr    <= ff_adr;
                ff_we      <= '0';
                ff_req_t   <= not ff_req_t;
                ff_rd_pend <= '0';
            end if;
        end if;
    end process;

    wave_req_t  <= ff_req_t;
    wave_we     <= ff_we;
    wave_adr    <= ff_fadr;
    wave_wdat   <= ff_wdat;

    dbi <=  "0000000" & (busy or ff_wr_pend or ff_rd_pend)  when( adr0 = '0' )else
            X"20"                                           when( ff_index = X"02" )else
            ff_rdout                                        when( ff_index = X"06" )else
            dbg_rcv(  7 downto  0 )                         when( ff_index = X"FA" )else
            dbg_rcv( 15 downto  8 )                         when( ff_index = X"FB" )else
            dbg_rcv( 23 downto 16 )                         when( ff_index = X"FC" )else
            dbg_lost(  7 downto  0 )                        when( ff_index = X"FD" )else
            dbg_lost( 15 downto  8 )                        when( ff_index = X"FE" )else
            dbg_lost( 23 downto 16 )                        when( ff_index = X"FF" )else
            X"FF";
end RTL;
