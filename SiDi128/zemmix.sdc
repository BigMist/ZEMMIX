create_clock -name "CLOCK_50" -period 20.000 [get_ports {CLOCK_50}]
create_clock -name {SPI_SCK}  -period 41.666 -waveform { 20.8 41.666 } [get_ports {SPI_SCK}]

derive_pll_clocks
derive_clock_uncertainty;

# SPI from the ARM (user_io, OSD) is asynchronous to the core (as msx_mist.sdc)
set_clock_groups -asynchronous -group [get_clocks {SPI_SCK}] -group [get_clocks {pll|altpll_component|auto_generated|pll1|clk[*]}]

# OPL3 on CLOCK_50 (zemmix.sv, USE_CLOCK_50): its crossings with the core
# clocks are a dcfifo (CPU writes), a toggle (samples, opl3.sv) and the reset
set_clock_groups -asynchronous -group [get_clocks {CLOCK_50}] -group [get_clocks {pll|altpll_component|auto_generated|pll1|clk[*]}]

# OPL3: the NextZ80 runs with CE every second clock (opl3fm.sv, WAIT(!CE)):
# its registers, and the I/O registers it writes or reads on CE edges
# (OPL3Struct_base, seq_reset_n, FIFO rdreq), change every two clocks.  Its
# program RAM takes the address one clock after it changes: no multicycle.
set_multicycle_path -from [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -to [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -setup 2
set_multicycle_path -from [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -to [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -hold 1
set_multicycle_path -from [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -to [get_registers {*|opl3sw:opl3|OPL3Struct_base* *|opl3sw:opl3|seq_reset_n *|opl3sw:opl3|opl3_fifo:in_queue|*}] -setup 2
set_multicycle_path -from [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -to [get_registers {*|opl3sw:opl3|OPL3Struct_base* *|opl3sw:opl3|seq_reset_n *|opl3sw:opl3|opl3_fifo:in_queue|*}] -hold 1

# memclk -> clk21m (as msx_mist.sdc)
set_multicycle_path -from [get_clocks {pll|altpll_component|auto_generated|pll1|clk[1]}] -to [get_clocks {pll|altpll_component|auto_generated|pll1|clk[0]}] -setup 2
set_multicycle_path -from [get_clocks {pll|altpll_component|auto_generated|pll1|clk[1]}] -to [get_clocks {pll|altpll_component|auto_generated|pll1|clk[0]}] -hold 1
