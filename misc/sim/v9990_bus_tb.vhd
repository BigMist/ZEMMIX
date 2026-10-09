--
-- Testbench of misc/v9990_bus.vhd with v9990_core (ZEMMIX-1os.5): Z80-like
-- OUT / IN cycles on 60h-6Fh (clk21m, a T state every 6 clocks, WAIT
-- sampled), the core on 42.95 MHz in phase, its VRAM a one-clock stub.
-- Writes registers through 64h (select) / 63h (data) and reads them back.
--
--   nvc -a v9990/rtl/v9990_pkg.vhd ... v9990/rtl/v9990_core.vhd misc/v9990_bus.vhd misc/sim/v9990_bus_tb.vhd -e v9990_bus_tb -r
--
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity v9990_bus_tb is
end v9990_bus_tb;

architecture sim of v9990_bus_tb is

    constant T21    : time := 46.56 ns;
    signal clk21m   : std_logic := '0';
    signal clk42    : std_logic := '0';
    signal reset    : std_logic := '1';
    signal cs, rd_n, wr_n : std_logic := '1';
    signal adr      : std_logic_vector(3 downto 0) := (others => '0');
    signal dbo      : std_logic_vector(7 downto 0) := (others => '0');
    signal dbi      : std_logic_vector(7 downto 0);
    signal wait_n, int_n : std_logic;

    signal v_reset_n, v_req, v_wrt, v_ack, v_int_n : std_logic;
    signal v_adr    : std_logic_vector(3 downto 0);
    signal v_dbo, v_dbi : std_logic_vector(7 downto 0);
    signal vram_req, vram_we : std_logic;
    signal vram_ack : std_logic := '0';
    signal vram_be  : std_logic_vector(1 downto 0);
    signal vram_addr : unsigned(17 downto 0);
    signal vram_wdata : std_logic_vector(15 downto 0);
    signal waits    : natural := 0;
    signal done     : boolean := false;
    signal tlen     : natural := 6;                                     -- clk21m per T state

begin

    clk21m <= not clk21m after T21 / 2 when not done;
    clk42  <= not clk42  after T21 / 4 when not done;

    process (clk42) begin
        if rising_edge(clk42) then
            vram_ack <= vram_req and not vram_ack;
        end if;
    end process;

    bus_u : entity work.v9990_bus
        port map(
            clk21m => clk21m, reset => reset, cs => cs, rd_n => rd_n, wr_n => wr_n,
            adr => adr, dbo => dbo, dbi => dbi, wait_n => wait_n, int_n => int_n,
            v_clk => clk42, v_reset_n => v_reset_n, v_req => v_req, v_wrt => v_wrt,
            v_adr => v_adr, v_dbo => v_dbo, v_ack => v_ack, v_dbi => v_dbi, v_int_n => v_int_n
        );

    core_u : entity work.v9990_core
        port map(
            clk => clk42, reset_n => v_reset_n,
            req_i => v_req, wrt_i => v_wrt, adr_i => v_adr, dbo_i => v_dbo,
            ack_o => v_ack, dbi_o => v_dbi, int_n_o => v_int_n,
            vram_req_o => vram_req, vram_we_o => vram_we, vram_be_o => vram_be,
            vram_addr_o => vram_addr, vram_wdata_o => vram_wdata,
            vram_ack_i => vram_ack, vram_rdata_i => x"FFFF",
            red_o => open, grn_o => open, blu_o => open, hsync_n_o => open, vsync_n_o => open,
            hblank_o => open, vblank_o => open, interlace_o => open, vid_x_o => open, vid_y_o => open
        );

    process
        variable errors : natural := 0;

        -- one I/O cycle: T1, T2 (+ wait states), T3; strobes from T1 to T3
        procedure io(port_n : natural; wr : boolean; d : std_logic_vector(7 downto 0);
                     q : out std_logic_vector(7 downto 0)) is
        begin
            wait until rising_edge(clk21m);
            adr <= std_logic_vector(to_unsigned(port_n, 4));
            dbo <= d;
            for i in 1 to tlen loop wait until rising_edge(clk21m); end loop;          -- T1
            cs <= '1';
            if wr then wr_n <= '0'; else rd_n <= '0'; end if;
            for i in 1 to tlen loop wait until rising_edge(clk21m); end loop;          -- T2
            while wait_n = '0' loop                                                 -- TW
                waits <= waits + 1;
                for i in 1 to tlen loop wait until rising_edge(clk21m); end loop;
            end loop;
            for i in 1 to (tlen + 1) / 2 loop wait until rising_edge(clk21m); end loop;  -- T3: data taken
            q := dbi;
            cs <= '0'; rd_n <= '1'; wr_n <= '1';
        end procedure;

        procedure outp(port_n : natural; d : natural) is
            variable q : std_logic_vector(7 downto 0);
        begin
            io(port_n, true, std_logic_vector(to_unsigned(d, 8)), q);
        end procedure;

        procedure inp_check(port_n : natural; expect : natural; what : string) is
            variable q : std_logic_vector(7 downto 0);
        begin
            io(port_n, false, x"00", q);
            if to_integer(unsigned(q)) /= expect then
                report what & ": read " & to_hstring(q) & ", expected " &
                       to_hstring(std_logic_vector(to_unsigned(expect, 8))) severity error;
                errors := errors + 1;
            end if;
        end procedure;

    begin
        for i in 1 to 20 loop wait until rising_edge(clk21m); end loop;
        reset <= '0';
        for i in 1 to 20 loop wait until rising_edge(clk21m); end loop;

        for pass in 0 to 1 loop
        -- pass 0: Z80 at 3.58 MHz, pass 1: a T state per clk21m (R800-like, waits)
        if pass = 1 then tlen <= 1; wait until rising_edge(clk21m); end if;

        -- R#15 (back drop color), no increment
        outp(4, 16#C0# + 15);
        outp(3, 16#2A# + pass);
        outp(4, 16#C0# + 15);
        inp_check(3, 16#2A# + pass, "R#15");

        -- R#16-R#17 with increment on write and read
        outp(4, 16);
        outp(3, 16#11#);
        outp(3, 16#22#);
        outp(4, 16);
        inp_check(3, 16#11#, "R#16");
        inp_check(3, 16#22#, "R#17");
        outp(4, 16#C0# + 15);
        outp(3, 16#15# + pass);
        outp(4, 16#C0# + 15);
        inp_check(3, 16#15# + pass, "R#15 again");
        report "pass " & integer'image(pass) & ": " & integer'image(waits) & " wait states so far";
        end loop;

        if errors = 0 then report "PASS"; else report "FAIL: " & integer'image(errors) & " errors" severity failure; end if;
        done <= true;
        wait;
    end process;

end sim;
