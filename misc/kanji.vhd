--
-- kanji.vhd
--   Kanji ROM (JIS1: D8h/D9h, JIS2: DAh/DBh) for the ZEMMIX, after the OCM
--   kanji.vhd (ocm-pld-dev esemsx3/src/peripheral) by t.hara / KdL.
--
-- The OCM module prefetched: a read gave the byte fetched by the access
-- before, and the first one came from a fetch done by the write of the
-- pointer.  On the ZEMMIX that fetch took the old pointer (the first byte
-- was wrong on the Z80) and the R800 was one byte late on every read
-- (ZEMMIX-cb8).  Here a read of D9h / DBh is a plain SDRAM read of the
-- pointer: the CPU gets that byte from RamDbi (emsx_top: jSltMem), and the
-- pointer moves when the I/O cycle is over (cyc low), so that the address
-- stays the same while the R800 waits for the SDRAM.  A write does not
-- read.
--

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_unsigned.all;

entity kanji is
    port(
        clk21m      : in    std_logic;
        reset       : in    std_logic;
        req         : in    std_logic;
        ack         : out   std_logic;
        wrt         : in    std_logic;
        adr         : in    std_logic_vector( 15 downto  0 );
        dbi         : out   std_logic_vector(  7 downto  0 );
        dbo         : in    std_logic_vector(  7 downto  0 );
        cyc         : in    std_logic;                              -- I/O cycle on D8h-DBh
        ramreq      : out   std_logic;
        ramadr      : out   std_logic_vector( 17 downto  0 );
        ramdbi      : in    std_logic_vector(  7 downto  0 );
        ramdbo      : out   std_logic_vector(  7 downto  0 )
    );
end kanji;

architecture rtl of kanji is

    signal rd_pend      : std_logic;                                -- a read to move the pointer after
    signal rd_sel       : std_logic;                                -- its pointer: 0 JIS1, 1 JIS2
    signal kanjiptr1    : std_logic_vector( 16 downto  0 );
    signal kanjiptr2    : std_logic_vector( 16 downto  0 );

begin

    ramreq  <=  req   when( wrt = '0' and adr(0) = '1' )else
                '0';

    ramadr  <=  ('0' & kanjiptr1) when( adr(1) = '0' )else
                ('1' & kanjiptr2);

    ramdbo  <=  dbo;
    dbi     <=  ramdbi;

    -- writes: ack at once (reads: RamAck)
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            ack <= '0';
        elsif( clk21m'event and clk21m = '1' )then
            if( wrt = '1' )then
                ack <= req;
            else
                ack <= '0';
            end if;
        end if;
    end process;

    process( reset, clk21m )
    begin
        if( reset = '1' )then
            rd_pend   <= '0';
            rd_sel    <= '0';
            kanjiptr1 <= (others => '0');
            kanjiptr2 <= (others => '0');
        elsif( clk21m'event and clk21m = '1' )then
            if( req = '1' and wrt = '1' )then
                -- pointer: D8h / DAh bits 10-5, D9h / DBh bits 16-11, the byte to 0
                if( adr(1) = '0' )then
                    if( adr(0) = '0' )then
                        kanjiptr1( 10 downto  5 ) <= dbo( 5 downto  0 );
                    else
                        kanjiptr1( 16 downto 11 ) <= dbo( 5 downto  0 );
                    end if;
                    kanjiptr1(  4 downto  0 ) <= (others => '0');
                else
                    if( adr(0) = '0' )then
                        kanjiptr2( 10 downto  5 ) <= dbo( 5 downto  0 );
                    else
                        kanjiptr2( 16 downto 11 ) <= dbo( 5 downto  0 );
                    end if;
                    kanjiptr2(  4 downto  0 ) <= (others => '0');
                end if;
                rd_pend <= '0';
            elsif( req = '1' and wrt = '0' and adr(0) = '1' )then
                rd_pend <= '1';
                rd_sel  <= adr(1);
            elsif( rd_pend = '1' and cyc = '0' )then
                -- the read is over: next byte of the 32 of the character
                if( rd_sel = '0' )then
                    kanjiptr1(  4 downto  0 ) <= kanjiptr1( 4 downto  0 ) + 1;
                else
                    kanjiptr2(  4 downto  0 ) <= kanjiptr2( 4 downto  0 ) + 1;
                end if;
                rd_pend <= '0';
            end if;
        end if;
    end process;

end rtl;
