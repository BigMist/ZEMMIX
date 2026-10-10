-- Option D model: Z80 (T80a, OCM derived clock + waits) and R800 (T80s on clk21m)
-- sharing the OCM internal bus, switched by the S1990 R#6 like the real turboR.
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.prog_pkg.all;

entity tb_dt is
  generic ( custom : integer := 2; cache_en : std_logic := '1' );
end tb_dt;

architecture sim of tb_dt is
  signal clk21m, memclk : std_logic := '0';
  signal done : boolean := false;
  signal reset : std_logic := '1';

  -- Z80 (T80a)
  signal iCpuClk : std_logic;
  signal clkdiv : std_logic_vector(1 downto 0) := "10";
  signal pSltMerq_n, pSltIorq_n, pSltRd_n, pSltWr_n, CpuM1_n, CpuRfsh_n, z_halt_n : std_logic;
  signal pSltAdr : std_logic_vector(15 downto 0);
  signal pSltDat : std_logic_vector(7 downto 0);
  signal wait_slow, z_wait_n : std_logic := '1';

  -- R800 (T80s)
  signal r8_cen, r8_wait_n : std_logic := '0';
  signal r8_merq_n, r8_iorq_n, r8_rd_n, r8_wr_n, r8_m1_n, r8_rfsh_n, r8_halt_n : std_logic;
  signal r8_adr : std_logic_vector(15 downto 0);
  signal r8_do, r8_di : std_logic_vector(7 downto 0);
  signal r8_started : std_logic := '0';

  -- CPU switch
  signal r800_sel : std_logic := '0';
  signal r800_sel_d : std_logic := '0';
  signal sw_gap : integer range 0 to 3 := 0;
  signal z80_hold : std_logic := '0';
  signal z80_resume : integer range 0 to 15 := 0;

  -- muxed CPU bus seen by the internal bus registers
  signal c_merq_n, c_iorq_n, c_rd_n, c_wr_n, c_rfsh_n : std_logic;
  signal c_adr : std_logic_vector(15 downto 0);
  signal c_dat : std_logic_vector(7 downto 0);

  -- internal bus
  signal iSltMerq_n, iSltIorq_n, xSltRd_n, xSltWr_n, iSltRfsh_n : std_logic := '1';
  signal iSltAdr : std_logic_vector(15 downto 0) := (others => '1');
  signal iSltDat : std_logic_vector(7 downto 0) := (others => '1');
  signal iack, req, ack, mem, wrt, jSltMem : std_logic := '0';
  signal adr : std_logic_vector(15 downto 0);
  signal dbo, dbi, dlydbi : std_logic_vector(7 downto 0);

  -- SDRAM
  signal ram : mem_t := PROG;
  signal RamReq, RamAck, w_wrt_req : std_logic := '0';
  signal RamDbi : std_logic_vector(7 downto 0) := (others => '1');
  signal ff_sdr_seq : std_logic_vector(2 downto 0) := "000";
  signal SdrSta : std_logic_vector(2 downto 0) := "000";
  signal dotstate : std_logic_vector(1 downto 0) := "00";
  signal DHClk, DLClk : std_logic := '0';
  signal slot_adr, rd_adr, wr_adr : std_logic_vector(15 downto 0) := (others => '1');
  signal wr_dat : std_logic_vector(7 downto 0) := (others => '0');
  signal rd_ok, wr_ok, slot_ok : std_logic := '0';

  -- R800 bus cycle tracking
  signal rc_rd, rc_wr, rc_io, rc_req, rc_wram, rc_done : std_logic := '0';
  signal rc_cnt : integer range 0 to 7 := 0;

  -- R800 read cache (byte lines, direct mapped, write through, any CPU write updates it)
  type cache_t is array(0 to 16383) of std_logic_vector(10 downto 0);   -- valid & tag(1:0) & data
  signal cache : cache_t := (others => (others => '0'));
  signal cq : std_logic_vector(10 downto 0) := (others => '0');
  signal r8_hit : std_logic := '0';
  signal r8_dbi : std_logic_vector(7 downto 0);
  signal r8_stall, r8_iohold, r8_active : std_logic;

  -- devices
  signal s1990_sel : std_logic_vector(7 downto 0) := (others => '0');
  signal s1990_cpu : std_logic_vector(6 downto 5) := "11";
  signal f4_reg : std_logic_vector(7 downto 0) := (others => '0');
  signal tdiv : integer range 0 to 83 := 0;
  signal tcnt : std_logic_vector(15 downto 0) := (others => '0');
begin
  process
  begin
    while not done loop
      clk21m <= '1'; memclk <= '1'; wait for 5.82 ns; memclk <= '0'; wait for 5.82 ns;
      memclk <= '1'; wait for 5.82 ns; memclk <= '0'; wait for 5.82 ns;
      clk21m <= '0'; memclk <= '1'; wait for 5.82 ns; memclk <= '0'; wait for 5.82 ns;
      memclk <= '1'; wait for 5.82 ns; memclk <= '0'; wait for 5.82 ns;
    end loop;
    wait;
  end process;
  reset <= '0' after 1 us;

  process(reset, clk21m) begin
    if reset = '1' then clkdiv <= "10";
    elsif rising_edge(clk21m) then clkdiv <= clkdiv - 1; end if;
  end process;
  iCpuClk <= clkdiv(0);

  ---------------------------------------------------------------- Z80
  z80 : entity work.T80a
    port map(RESET_n => not reset, R800_mode => '0', CLK_n => iCpuClk, WAIT_n => z_wait_n,
             INT_n => '1', NMI_n => '1', BUSRQ_n => '1', M1_n => CpuM1_n, MREQ_n => pSltMerq_n,
             IORQ_n => pSltIorq_n, RD_n => pSltRd_n, WR_n => pSltWr_n, RFSH_n => CpuRfsh_n,
             HALT_n => z_halt_n, BUSAK_n => open, A => pSltAdr, D => pSltDat);

  process(reset, iCpuClk)
    variable iCpuM1_n, jSltIorq_n, jSltMerq_n : std_logic := '1';
    variable count : std_logic_vector(3 downto 0) := "0000";
  begin
    if reset = '1' then
      iCpuM1_n := '1'; jSltIorq_n := '1'; jSltMerq_n := '1'; count := "0000"; wait_slow <= '1';
    elsif rising_edge(iCpuClk) then
      if pSltMerq_n = '0' and jSltMerq_n = '1' then count := std_logic_vector(to_unsigned(custom, 4));
      elsif pSltIorq_n = '0' and jSltIorq_n = '1' then count := "0110";
      elsif count /= "0000" then count := count - 1; end if;
      if (CpuM1_n = '0' and iCpuM1_n = '1') or count /= "0000" then wait_slow <= '0'; else wait_slow <= '1'; end if;
      iCpuM1_n := CpuM1_n; jSltIorq_n := pSltIorq_n; jSltMerq_n := pSltMerq_n;
    end if;
  end process;
  z_wait_n <= '0' when z80_hold = '1' or z80_resume /= 0 else wait_slow;

  -- the Z80 sees dbi unless it writes (synthesized internal tristate)
  process(all)
    alias z_wr is <<signal .tb_dt.z80.Write : std_logic>>;
  begin
    if z_wr = '1' then pSltDat <= (others => 'Z'); else pSltDat <= dbi; end if;
  end process;

  ---------------------------------------------------------------- R800
  r800 : entity work.T80s
    generic map(Mode => 0, T2Write => 1, IOWait => 1, MulDlyB => 34, MulDlyW => 107)
    port map(RESET_n => not reset, R800_mode => '1', CLK => clk21m, CEN => r8_cen, WAIT_n => r8_wait_n,
             INT_n => '1', NMI_n => '1', BUSRQ_n => '1', M1_n => r8_m1_n, MREQ_n => r8_merq_n,
             IORQ_n => r8_iorq_n, RD_n => r8_rd_n, WR_n => r8_wr_n, RFSH_n => r8_rfsh_n,
             HALT_n => r8_halt_n, BUSAK_n => open, A => r8_adr, DI => r8_di, DO => r8_do);
  sllprobe : process
    alias mc  is <<signal .tb_dt.r800.u0.MCycle : std_logic_vector(2 downto 0)>>;
    alias ts  is <<signal .tb_dt.r800.u0.TState : unsigned(2 downto 0)>>;
    alias ir  is <<signal .tb_dt.r800.u0.IR : std_logic_vector(7 downto 0)>>;
    alias iset is <<signal .tb_dt.r800.u0.ISet : std_logic_vector(1 downto 0)>>;
    alias xy  is <<signal .tb_dt.r800.u0.XY_State : std_logic_vector(1 downto 0)>>;
    alias f   is <<signal .tb_dt.r800.u0.F : std_logic_vector(7 downto 0)>>;
    alias tr  is <<signal .tb_dt.r800.u0.T_Res : std_logic>>;
    alias sx  is <<signal .tb_dt.r800.u0.R800_SllXY : std_logic>>;
    alias sv  is <<signal .tb_dt.r800.u0.Save_ALU_r : std_logic>>;
    variable n : integer := 0;
  begin
    wait until rising_edge(clk21m);
    if r8_cen = '1' and (xy /= "00" or n > 0) and n < 400 and r800_sel = '1' then
      n := n + 1;
      report "SLL mc=" & to_string(mc) & " ts=" & integer'image(to_integer(ts)) & " ir=" & to_hstring(ir) & " iset=" & to_string(iset) &
             " xy=" & to_string(xy) & " F=" & to_hstring(f) & " tres=" & std_logic'image(tr) & " sllxy=" & std_logic'image(sx) & " save=" & std_logic'image(sv);
    end if;
  end process;
  r8_di <= r8_dbi;
  r8_active <= r800_sel and r8_started;
  tim : entity work.r800_timing
    port map(clk21m => clk21m, reset => reset, active => r8_active,
             m1_n => r8_m1_n, merq_n => r8_merq_n, iorq_n => r8_iorq_n, rd_n => r8_rd_n, wr_n => r8_wr_n,
             rfsh_n => r8_rfsh_n, wait_n => r8_wait_n, adr => r8_adr, di => r8_dbi,
             ppi_a => x"FF", exp0 => x"00", exp3 => x"00", dram_mode => not s1990_cpu(6),
             stall => r8_stall, io_hold => r8_iohold);
  -- cache read at the clk21m falling edge (address registered at the start of T2)
  process(clk21m) begin
    if falling_edge(clk21m) then cq <= cache(to_integer(unsigned(adr(13 downto 0)))); end if;
  end process;
  r8_hit <= '1' when cache_en = '1' and r800_sel = '1' and rc_rd = '1' and mem = '1' and jSltMem = '1' and
                     cq(10) = '1' and cq(9 downto 8) = adr(15 downto 14) else '0';
  r8_dbi <= cq(7 downto 0) when r8_hit = '1' else dbi;
  process(clk21m) begin
    if rising_edge(clk21m) then
      if w_wrt_req = '1' then
        cache(to_integer(unsigned(adr(13 downto 0)))) <= '1' & adr(15 downto 14) & dbo;
      elsif r800_sel = '1' and rc_rd = '1' and mem = '1' and jSltMem = '1' and r8_hit = '0' and rc_done = '1' then
        cache(to_integer(unsigned(adr(13 downto 0)))) <= '1' & adr(15 downto 14) & RamDbi;
      end if;
    end if;
  end process;

  -- R800 clock enable: off until its first activation, then frozen on the T1 of the
  -- first M1 after the switch to the Z80 (no bus cycle is ever left half done)
  r8_cen <= '0' when r8_started = '0' or r8_stall = '1' else
            '0' when r800_sel = '0' and r8_m1_n = '0' and r8_merq_n = '1' else
            '1';

  process(reset, clk21m)
  begin
    if reset = '1' then
      r8_started <= '0'; r800_sel_d <= '0'; sw_gap <= 0; z80_hold <= '0'; z80_resume <= 0;
    elsif rising_edge(clk21m) then
      if r800_sel = '1' then r8_started <= '1'; end if;
      r800_sel_d <= r800_sel;
      if r800_sel /= r800_sel_d then sw_gap <= 2;
      elsif sw_gap /= 0 then sw_gap <= sw_gap - 1; end if;
      -- Z80 frozen by WAIT from its next bus cycle on (the real Z80 stops inside the OTIR)
      if r800_sel = '1' then
        if pSltMerq_n = '1' and pSltIorq_n = '1' then z80_hold <= '1'; end if;
        z80_resume <= 0;
      else
        if z80_hold = '1' then z80_resume <= 12; z80_hold <= '0';     -- its frozen cycle is redone by the bus
        elsif z80_resume /= 0 then z80_resume <= z80_resume - 1; end if;
      end if;
    end if;
  end process;

  -- bus mux, idle for 2 clocks on a switch (iack reset)
  c_merq_n <= '1' when sw_gap /= 0 else r8_merq_n when r800_sel = '1' else pSltMerq_n;
  c_iorq_n <= '1' when sw_gap /= 0 else r8_iorq_n when r800_sel = '1' else pSltIorq_n;
  c_rd_n   <= '1' when sw_gap /= 0 else r8_rd_n   when r800_sel = '1' else pSltRd_n;
  c_wr_n   <= '1' when sw_gap /= 0 else r8_wr_n   when r800_sel = '1' else pSltWr_n;
  c_rfsh_n <= r8_rfsh_n when r800_sel = '1' else CpuRfsh_n;
  c_adr    <= r8_adr when r800_sel = '1' else pSltAdr;
  c_dat    <= r8_do when r800_sel = '1' else pSltDat;

  -- R800 waits: until the access of this cycle is really completed
  rc_rd <= '1' when r8_merq_n = '0' and r8_rd_n = '0' else '0';
  rc_wr <= '1' when r8_merq_n = '0' and r8_wr_n = '0' else '0';
  rc_io <= '1' when r8_iorq_n = '0' and (r8_rd_n = '0' or r8_wr_n = '0') else '0';
  process(reset, clk21m)
  begin
    if reset = '1' then rc_req <= '0'; rc_wram <= '0'; rc_cnt <= 0;
    elsif rising_edge(clk21m) then
      if r800_sel = '0' or (rc_rd = '0' and rc_wr = '0' and rc_io = '0') then
        rc_req <= '0'; rc_wram <= '0'; rc_cnt <= 0;
      else
        if req = '1' then rc_req <= '1'; end if;
        if w_wrt_req = '1' then rc_wram <= '1'; end if;
        if rc_req = '1' and rc_cnt /= 7 then rc_cnt <= rc_cnt + 1; end if;
      end if;
    end if;
  end process;
  rc_done <= '0' when rc_req = '0' or iack = '0' else
             '0' when rc_rd = '1' and jSltMem = '1' and not (rd_ok = '1' and rd_adr = adr) else
             '0' when rc_wram = '1' and not (wr_ok = '1' and wr_adr = adr and wr_dat = dbo) else
             '0' when (rc_io = '1' or (rc_rd = '1' and jSltMem = '0')) and rc_cnt < 3 else
             '1';
  r8_wait_n <= '1' when r800_sel = '0' else
               '1' when r8_hit = '1' else
               '0' when (rc_rd = '1' or rc_wr = '1' or rc_io = '1') and rc_done = '0' else
               '1';

  ---------------------------------------------------------------- internal bus (OCM)
  process(reset, clk21m)
  begin
    if reset = '1' then
      iSltRfsh_n <= '1'; iSltMerq_n <= '1'; iSltIorq_n <= '1'; xSltRd_n <= '1'; xSltWr_n <= '1';
      iSltAdr <= (others => '1'); iSltDat <= (others => '1'); iack <= '0'; dlydbi <= (others => '1');
    elsif rising_edge(clk21m) then
      iSltRfsh_n <= c_rfsh_n; iSltMerq_n <= c_merq_n; iSltIorq_n <= c_iorq_n;
      xSltRd_n <= c_rd_n; xSltWr_n <= c_wr_n; iSltAdr <= c_adr; iSltDat <= c_dat;
      if iSltMerq_n = '1' and iSltIorq_n = '1' then iack <= '0';
      elsif ack = '1' then iack <= '1'; end if;
      if mem = '0' and adr(7 downto 1) = "1110011" then
        if adr(0) = '0' then dlydbi <= tcnt(7 downto 0); else dlydbi <= tcnt(15 downto 8); end if;
      elsif mem = '0' and adr(7 downto 1) = "1110010" then
        if adr(0) = '0' then dlydbi <= s1990_sel;
        elsif s1990_sel = x"06" then dlydbi <= "0" & s1990_cpu & "00000";
        else dlydbi <= x"FF"; end if;
      elsif mem = '0' and adr(7 downto 0) = x"F4" then
        dlydbi <= f4_reg;
      else
        dlydbi <= (others => '1');
      end if;
    end if;
  end process;

  process(reset, clk21m)
  begin
    if reset = '1' then jSltMem <= '0'; wrt <= '0';
    elsif falling_edge(clk21m) then
      if mem = '1' then jSltMem <= '1'; else jSltMem <= '0'; end if;
      if req = '0' then wrt <= not c_wr_n; end if;
    end if;
  end process;

  req <= '0' when (r8_iohold = '1' and rc_req = '0') else
         '1' when ((iSltMerq_n = '0') or (iSltIorq_n = '0')) and ((xSltRd_n = '0') or (xSltWr_n = '0')) and iack = '0' else '0';
  mem <= iSltIorq_n;
  dbo <= iSltDat;
  adr <= iSltAdr;
  RamReq <= req when mem = '1' else '0';
  ack <= RamAck when RamReq = '1' else req;
  dbi <= RamDbi when jSltMem = '1' else dlydbi;
  w_wrt_req <= RamReq and wrt;

  ---------------------------------------------------------------- devices
  process(clk21m)
    variable l : line;
  begin
    if rising_edge(clk21m) then
      if reset = '1' then
        s1990_sel <= (others => '0'); s1990_cpu <= "11"; f4_reg <= (others => '0');
      elsif req = '1' and wrt = '1' and mem = '0' then
        if adr(7 downto 0) = x"E4" then s1990_sel <= dbo; end if;
        if adr(7 downto 0) = x"E5" and s1990_sel = x"06" then
          s1990_cpu <= dbo(6 downto 5);
          report "R#6 <= " & to_hstring(dbo) & " by " & std_logic'image(r800_sel);
        end if;
        if adr(7 downto 0) = x"F4" then f4_reg <= dbo(7) & '0' & dbo(5) & "00000"; end if;
        if adr(7 downto 0) = x"01" then
          if dbo = x"0A" then writeline(output, l);
          elsif dbo /= x"0D" then write(l, character'val(to_integer(unsigned(dbo)))); end if;
        end if;
      end if;
      if req = '1' and wrt = '1' and mem = '0' and adr(7 downto 0) = x"E6" then
        tdiv <= 0; tcnt <= (others => '0');
      elsif tdiv = 83 then tdiv <= 0; tcnt <= tcnt + 1;
      else tdiv <= tdiv + 1; end if;
    end if;
  end process;
  r800_sel <= not s1990_cpu(5);

  ---------------------------------------------------------------- VDP dot state, SDRAM
  process(clk21m)
  begin
    if rising_edge(clk21m) then
      if reset = '1' then dotstate <= "00"; DHClk <= '0'; DLClk <= '0';
      else
        case dotstate is
          when "00" => dotstate <= "01"; DHClk <= '0'; DLClk <= '1';
          when "01" => dotstate <= "11"; DHClk <= '1'; DLClk <= '0';
          when "11" => dotstate <= "10"; DHClk <= '0'; DLClk <= '0';
          when others => dotstate <= "00"; DHClk <= '1'; DLClk <= '1';
        end case;
      end if;
    end if;
  end process;

  process(reset, clk21m)
  begin
    if reset = '1' then RamAck <= '0';
    elsif rising_edge(clk21m) then
      if RamReq = '0' then RamAck <= '0';
      elsif DLClk = '0' and DHClk = '1' then RamAck <= '1'; end if;
    end if;
  end process;

  process(memclk)
  begin
    if rising_edge(memclk) then
      case ff_sdr_seq is
        when "000" => if DHClk = '1' then ff_sdr_seq <= "001"; end if;
        when "111" => if DHClk = '0' then ff_sdr_seq <= "000"; end if;
        when others => ff_sdr_seq <= ff_sdr_seq + 1;
      end case;
      if ff_sdr_seq = "111" then
        if iSltRfsh_n = '0' and DLClk = '1' then SdrSta <= "010";
        else SdrSta(2) <= '1'; end if;
      elsif ff_sdr_seq = "001" and SdrSta(2) = '1' then
        SdrSta(1) <= DLClk;
        if DLClk = '0' then SdrSta(0) <= w_wrt_req; else SdrSta(0) <= '0'; end if;
      end if;
      if ff_sdr_seq = "000" then slot_adr <= adr; end if;
      if ff_sdr_seq = "010" then
        if slot_adr = adr then slot_ok <= '1'; else slot_ok <= '0'; end if;
        if SdrSta = "101" then
          ram(to_integer(unsigned(adr))) <= dbo;
          if slot_adr = adr then wr_ok <= '1'; else wr_ok <= '0'; end if;
          wr_adr <= adr; wr_dat <= dbo; rd_ok <= '0';
        end if;
      end if;
      if ff_sdr_seq = "101" and SdrSta = "100" then
        RamDbi <= ram(to_integer(unsigned(adr)));
        rd_adr <= slot_adr; rd_ok <= slot_ok;
      end if;
    end if;
  end process;

  ztrace : process(clk21m)
    variable l : line;
    variable n : integer := 0;
    variable sw : integer := 0;
    variable prev_sel : std_logic := '0';
  begin
    if rising_edge(clk21m) then
      if prev_sel = '1' and r800_sel = '0' then sw := sw + 1; end if;
      prev_sel := r800_sel;
      if false and CpuM1_n = '0' and pSltMerq_n = '0' and z_wait_n = '1' then
        n := n + 1;
        write(l, string'("Z ") & to_hstring(pSltAdr) & " m1=" & std_logic'image(CpuM1_n) & " mq=" & std_logic'image(pSltMerq_n) &
          " io=" & std_logic'image(pSltIorq_n) & " rd=" & std_logic'image(pSltRd_n) & " wr=" & std_logic'image(pSltWr_n) &
          " W=" & std_logic'image(z_wait_n) & " hold=" & std_logic'image(z80_hold) & " res=" & integer'image(z80_resume) &
          " gap=" & integer'image(sw_gap) & " req=" & std_logic'image(req) & " iack=" & std_logic'image(iack) &
          " d=" & to_hstring(dbi) & " adr=" & to_hstring(adr) & " jm=" & std_logic'image(jSltMem));
        writeline(output, l);
      end if;
    end if;
  end process;

  process
  begin
    wait until z_halt_n = '0' for 1000 ms;
    report "end: z80 halt_n=" & std_logic'image(z_halt_n);
    done <= true; wait;
  end process;
end sim;
