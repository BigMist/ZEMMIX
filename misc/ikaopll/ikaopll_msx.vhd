-- MSX-MUSIC (YM2413, I/O 7Ch / 7Dh): IKAOPLL by Raki (ika-musume), a die
-- shot based, cycle accurate YM2413 (submodule IKAOPLL/, BSD-2), with the
-- interface of the OCM eseopll.
--
-- phiM is clkena (3.58MHz = 21.48MHz / 6).  A write is taken from the bus
-- (the CPU may change it right after) and given to the chip for one clkena
-- period from the next clkena.  The next one waits as on the YM2413 (12
-- cycles after the address, 84 after the data) when enawait is 1: the
-- chip applies a data write only when its channel comes around, a write
-- before that loses the previous one.  At 3.58MHz the software waits.
--
-- wav: the 16-bit accumulated output of the chip (synth x4, rhythm x6: the
-- 2:3 of the chip) sampled on its strobe, x4 with saturation: a channel at
-- full level is about +-4080, as the jt2413 it replaces was in the mix.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity eseopll is
  port(
    clk21m  : in std_logic;
    reset   : in std_logic;
    clkena  : in std_logic;
    enawait : in std_logic;
    req     : in std_logic;
    ack     : out std_logic;
    wrt     : in std_logic;
    adr     : in std_logic_vector(15 downto 0);
    dbo     : in std_logic_vector(7 downto 0);
    wav     : out std_logic_vector(15 downto 0)
 );
end eseopll;

architecture RTL of eseopll is

  component IKAOPLL is
    generic (
      FULLY_SYNCHRONOUS        : integer := 1;
      FAST_RESET               : integer := 0;
      ALTPATCH_CONFIG_MODE     : integer := 0;
      USE_PIPELINED_MULTIPLIER : integer := 0
    );
    port (
      i_XIN_EMUCLK         : in  std_logic;
      o_XOUT               : out std_logic;
      i_phiM_PCEN_n        : in  std_logic;
      i_IC_n               : in  std_logic;
      i_ALTPATCH_EN        : in  std_logic;
      i_CS_n               : in  std_logic;
      i_WR_n               : in  std_logic;
      i_A0                 : in  std_logic;
      i_D                  : in  std_logic_vector(7 downto 0);
      o_D                  : out std_logic_vector(1 downto 0);
      o_D_OE               : out std_logic;
      o_DAC_EN_MO          : out std_logic;
      o_DAC_EN_RO          : out std_logic;
      o_IMP_NOFLUC_SIGN    : out std_logic;
      o_IMP_NOFLUC_MAG     : out std_logic_vector(7 downto 0);
      o_IMP_FLUC_SIGNED_MO : out std_logic_vector(9 downto 0);
      o_IMP_FLUC_SIGNED_RO : out std_logic_vector(9 downto 0);
      i_ACC_SIGNED_MOVOL   : in  std_logic_vector(4 downto 0);
      i_ACC_SIGNED_ROVOL   : in  std_logic_vector(4 downto 0);
      o_ACC_SIGNED_STRB    : out std_logic;
      o_ACC_SIGNED         : out std_logic_vector(15 downto 0)
    );
  end component;

  signal CS_n     : std_logic := '1';
  signal WE_n     : std_logic := '1';
  signal A_out    : std_logic := '0';
  signal dbo_out  : std_logic_vector(7 downto 0) := (others => '0');

  signal counter  : integer range 0 to 84*6;
  signal pend     : std_logic := '0';
  signal ack_r    : std_logic := '0';

  signal A_buf    : std_logic := '0';
  signal dbo_buf  : std_logic_vector(7 downto 0) := (others => '0');
  signal WE_n_buf : std_logic := '1';

  signal ic_n     : std_logic;
  signal pcen_n   : std_logic;
  signal strb     : std_logic;
  signal strb_d   : std_logic := '0';
  signal acc      : std_logic_vector(15 downto 0);
  signal wav_r    : std_logic_vector(15 downto 0) := (others => '0');

begin

  process (clk21m, reset)
  begin

    if reset = '1' then

      counter <= 0;
      pend    <= '0';
      CS_n    <= '1';
      WE_n    <= '1';
      ack_r   <= '0';

    elsif rising_edge (clk21m) then

      if clkena = '1' then
        CS_n    <= not pend;
        WE_n    <= WE_n_buf or not pend;
        if pend = '1' then
          A_out   <= A_buf;
          dbo_out <= dbo_buf;
        end if;
        pend    <= '0';
      end if;

      -- req stays high one clock after ack (iack): that is not a new one
      ack_r <= '0';
      if counter /= 0 then
        counter <= counter - 1;
      end if;
      if req = '1' and ack_r = '0' and counter = 0 and (pend = '0' or clkena = '1') then
        if enawait = '1' then
          if adr(0) = '0' then
            counter <= 12*6;
          else
            counter <= 84*6;
          end if;
        end if;
        A_buf    <= adr(0);
        dbo_buf  <= dbo;
        WE_n_buf <= not wrt;
        pend     <= '1';
        ack_r    <= '1';
      end if;

    end if;

  end process;

  ack <= ack_r;

  ic_n   <= not reset;
  pcen_n <= not clkena;

  U1 : IKAOPLL
    generic map (
      FULLY_SYNCHRONOUS        => 1,
      FAST_RESET               => 1,
      ALTPATCH_CONFIG_MODE     => 0,
      USE_PIPELINED_MULTIPLIER => 1
    )
    port map (
      i_XIN_EMUCLK         => clk21m,
      o_XOUT               => open,
      i_phiM_PCEN_n        => pcen_n,
      i_IC_n               => ic_n,
      i_ALTPATCH_EN        => '0',
      i_CS_n               => CS_n,
      i_WR_n               => WE_n,
      i_A0                 => A_out,
      i_D                  => dbo_out,
      o_D                  => open,
      o_D_OE               => open,
      o_DAC_EN_MO          => open,
      o_DAC_EN_RO          => open,
      o_IMP_NOFLUC_SIGN    => open,
      o_IMP_NOFLUC_MAG     => open,
      o_IMP_FLUC_SIGNED_MO => open,
      o_IMP_FLUC_SIGNED_RO => open,
      i_ACC_SIGNED_MOVOL   => "00100",
      i_ACC_SIGNED_ROVOL   => "00110",
      o_ACC_SIGNED_STRB    => strb,
      o_ACC_SIGNED         => acc
    );

  process (clk21m)
    variable a : signed(15 downto 0);
  begin
    if rising_edge (clk21m) then
      strb_d <= strb;
      if strb = '1' and strb_d = '0' then
        a := signed(acc);
        if a > 8191 then
          wav_r <= x"7FFF";
        elsif a < -8192 then
          wav_r <= x"8000";
        else
          wav_r <= std_logic_vector(shift_left(a, 2));
        end if;
      end if;
    end if;
  end process;

  wav <= wav_r;

end RTL;
