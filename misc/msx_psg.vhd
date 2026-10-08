--
-- msx_psg.vhd
--   Programmable Sound Generator (AY-3-8910/YM2149)
--   MSX side of the PSG (ports A/B: joysticks, kana LED, tape in) from the OCM sm_psg.vhd,
--   sound by ay_ym_psg.v (Kyp069 AY-3-891x + YM2149 personality)
--
-- Copyright (c) 2006 Kazuhiro Tsujikawa (ESE Artists' factory)
-- All rights reserved.
--
-- Redistribution and use of this source code or any derivative works, are
-- permitted provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice,
--    this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
-- 3. Redistributions may not be sold, nor may they be used in a commercial
--    product or activity without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
-- "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
-- TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
-- CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
-- EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
-- PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
-- OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
-- WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
-- OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
-- ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_unsigned.all;

entity msx_psg is
    generic(
        YM          : integer := 0                                  -- 0 = AY-3-8910, 1 = YM2149
    );
    port(
        clk21m      : in    std_logic;
        reset       : in    std_logic;
        clkena      : in    std_logic;                              -- 3.58MHz
        req         : in    std_logic;
        ack         : out   std_logic;
        wrt         : in    std_logic;
        adr         : in    std_logic_vector( 15 downto 0 );
        dbi         : out   std_logic_vector(  7 downto 0 );
        dbo         : in    std_logic_vector(  7 downto 0 );

        joya_in     : in    std_logic_vector(  5 downto 0 );
        joya_out    : out   std_logic_vector(  1 downto 0 );
        stra        : out   std_logic;
        joyb_in     : in    std_logic_vector(  5 downto 0 );
        joyb_out    : out   std_logic_vector(  1 downto 0 );
        strb        : out   std_logic;

        kana        : out   std_logic;
        cmtin       : in    std_logic;
        keymode     : in    std_logic;

        wave        : out   std_logic_vector( 14 downto 0 )         -- A+B+C, unsigned 0..12285
 );
end msx_psg;

architecture rtl of msx_psg is

    component ay_ym_psg
        generic(
            YM      : integer := 0
        );
        port(
            clock   : in    std_logic;
            sel     : in    std_logic;
            ce      : in    std_logic;
            reset   : in    std_logic;
            bdir    : in    std_logic;
            bc1     : in    std_logic;
            d       : in    std_logic_vector(  7 downto 0 );
            q       : out   std_logic_vector(  7 downto 0 );
            a       : out   std_logic_vector( 11 downto 0 );
            b       : out   std_logic_vector( 11 downto 0 );
            c       : out   std_logic_vector( 11 downto 0 );
            mix     : out   std_logic_vector( 14 downto 0 );
            ioad    : in    std_logic_vector(  7 downto 0 );
            ioaq    : out   std_logic_vector(  7 downto 0 );
            iobd    : in    std_logic_vector(  7 downto 0 );
            iobq    : out   std_logic_vector(  7 downto 0 )
        );
    end component;

    -- psg signals
    signal psgdbi       : std_logic_vector(  7 downto 0 );
    signal psgregptr    : std_logic_vector(  3 downto 0 );
    signal reset_n      : std_logic;

    -- bus cycle to the chip, held until the next clkena (the chip samples the bus with ce)
    signal wr_pend      : std_logic;
    signal wr_data      : std_logic;                                -- 0 = register pointer, 1 = register data
    signal wr_val       : std_logic_vector(  7 downto 0 );
    signal bdir         : std_logic;
    signal bc1          : std_logic;

    signal rega         : std_logic_vector(  7 downto 0 );
    signal regb         : std_logic_vector(  7 downto 0 );

begin

    ack <= req;
    reset_n <= not reset;

    ----------------------------------------------------------------
    -- psg register read: ports A/B come from here, as on the MSX the port
    -- directions of R#7 are ignored (A is always input, B always output)
    ----------------------------------------------------------------
    dbi <=  rega    when( psgregptr = "1110" and adr(1 downto 0) = "10" )else
            regb    when( psgregptr = "1111" and adr(1 downto 0) = "10" )else
            psgdbi  when( adr(1 downto 0) = "10" )else
            (others => '1');

    ----------------------------------------------------------------
    -- psg register write
    ----------------------------------------------------------------
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            psgregptr   <= (others => '0');
        elsif( clk21m'event and clk21m = '1' )then
            if (req = '1' and wrt = '1' and adr(1 downto 0) = "00") then
                -- register pointer
                psgregptr <= dbo(3 downto 0);
            end if;
        end if;
    end process;

    -- A0h: bdir=1 bc1=1 (address), A1h: bdir=1 bc1=0 (data). The pointer only
    -- takes the low nibble, like the OCM PSG and openMSX
    process( reset, clk21m )
    begin
        if( reset = '1' )then
            wr_pend     <= '0';
            wr_data     <= '0';
            wr_val      <= (others => '0');
        elsif( clk21m'event and clk21m = '1' )then
            if( req = '1' and wrt = '1' and adr(1) = '0' )then
                wr_pend <= '1';
                wr_data <= adr(0);
                if( adr(0) = '0' )then
                    wr_val <= "0000" & dbo(3 downto 0);
                else
                    wr_val <= dbo;
                end if;
            elsif( clkena = '1' )then
                wr_pend <= '0';
            end if;
        end if;
    end process;

    bdir <= wr_pend;
    bc1  <= wr_pend and not wr_data;

    process( reset, clk21m )
    begin
        if( reset = '1' )then
            rega <= (others => '0');
        elsif( clk21m'event and clk21m = '1' )then
            -- psg register #15 bit6 - joystick select : 0=port-a, 1=port-b
            if( regb(6) = '0' )then
                rega(5 downto 0) <= joya_in;
            else
                rega(5 downto 0) <= joyb_in;
            end if;

            rega(7) <= cmtin;       -- cassete voice input : always '0' on msx turbor
            rega(6) <= keymode;     -- keyboard mode : 1=jis
        end if;
    end process;

    process( reset, clk21m )
    begin
        if( reset = '1' )then
            regb        <= (others => '0');
        elsif( clk21m'event and clk21m = '1' )then
            if( req = '1' and wrt = '1' and adr(1 downto 0) = "01" )then
                -- psg registers
                if( psgregptr = "1111" )then
                    regb <= dbo;
                end if;
            end if;
        end if;
    end process;
    process( clk21m )
    begin
        if( clk21m'event and clk21m = '1' )then
            -- strobe output
            strb <= regb(5);
            stra <= regb(4);
        end if;
    end process;

    process( reset, clk21m )
    begin
        if( reset = '1' )then
            kana <= '0';
        elsif( clk21m'event and clk21m = '1' )then
            if( regb(7) = '0' )then
                kana <= '0'; -- kana-led : 0=on, Z=off
            else
                kana <= '1'; -- kana-led : 0=on, Z=off
            end if;
        end if;
    end process;

    process( reset, clk21m )
    begin
        if( reset = '1' )then
            joya_out <= "ZZ";
        elsif( clk21m'event and clk21m = '1' )then
            -- trigger a/b output joystick port-a
            case regb(1 downto 0) is
                when "00"   => joya_out <= "00";
                when "01"   => joya_out <= "0Z";
                when "10"   => joya_out <= "Z0";
                when others => joya_out <= "ZZ";
            end case;
        end if;
    end process;

    process( reset, clk21m )
    begin
        if( reset = '1' )then
            joyb_out <= "ZZ";
        elsif( clk21m'event and clk21m = '1' )then
            -- trigger a/b output joystick port-b
            case regb(3 downto 2) is
                when "00"   => joyb_out <= "00";
                when "01"   => joyb_out <= "0Z";
                when "10"   => joyb_out <= "Z0";
                when others => joyb_out <= "ZZ";
            end case;
        end if;
    end process;

    ----------------------------------------------------------------
    -- connect components
    ----------------------------------------------------------------
    -- ce = 3.58MHz with sel = 0 (further division by two): a 1.79MHz PSG, as on the MSX
    u_psgch: ay_ym_psg
    generic map(
        YM          => YM
    )
    port map(
        clock       => clk21m   ,
        sel         => '0'      ,
        ce          => clkena   ,
        reset       => reset_n  ,
        bdir        => bdir     ,
        bc1         => bc1      ,
        d           => wr_val   ,
        q           => psgdbi   ,
        a           => open     ,
        b           => open     ,
        c           => open     ,
        mix         => wave     ,
        ioad        => rega     ,
        ioaq        => open     ,
        iobd        => regb     ,
        iobq        => open
    );

end rtl;
