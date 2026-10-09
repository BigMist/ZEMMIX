
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;

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

  component jt2413 is
    Port ( rst   : in STD_LOGIC;
           clk   : in STD_LOGIC;
           cen   : in STD_LOGIC;  -- Optional clock enable, if not needed, leave as '1'
           din   : in STD_LOGIC_VECTOR(7 downto 0);
           addr  : in STD_LOGIC;
           cs_n  : in STD_LOGIC;
           wr_n  : in STD_LOGIC;
           -- Combined output
           snd   : out std_logic_vector(15 downto 0);
           sample: out STD_LOGIC);
  end component;
  -- A write is taken from the bus (the CPU may change it right after) and
  -- given to the jt2413 for one clkena period from the next clkena.  The
  -- next one waits as on the YM2413 (12 cycles after the address, 84 after
  -- the data): the jt2413 also applies a data write only when the channel
  -- comes around, a write before that loses the previous one.
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
        CS_n <= not pend;
        WE_n <= WE_n_buf or not pend;
        A_out   <= A_buf;
        dbo_out <= dbo_buf;
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

  U1 : jt2413 port map (reset,
								clk21m,
								clkena,
								dbo_out,
								A_out,
								CS_n,
								WE_n,
								wav,
								open);

end RTL;
