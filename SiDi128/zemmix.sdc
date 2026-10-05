create_clock -name "CLOCK_50" -period 20.000 [get_ports {CLOCK_50}]
create_clock -name {SPI_SCK}  -period 41.666 -waveform { 20.8 41.666 } [get_ports {SPI_SCK}]

derive_pll_clocks
derive_clock_uncertainty;

# SPI from the ARM (user_io, OSD) is asynchronous to the core (as msx_mist.sdc)
set_clock_groups -asynchronous -group [get_clocks {SPI_SCK}] -group [get_clocks {pll|altpll_component|auto_generated|pll1|clk[*]}]

# OPL3: the NextZ80 runs on memclk (86MHz) with CE every third clock
# (opl3fm.sv, WAIT(!CE)): its registers change only on CE edges (3 clocks),
# and its program RAM reads the address two clocks before the next CE edge.
set_multicycle_path -from [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -to [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -setup 3
set_multicycle_path -from [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -to [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -hold 2
set_multicycle_path -from [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -to [get_registers {*|opl3sw:opl3|opl3_mem:ram|*}] -setup 2
set_multicycle_path -from [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -to [get_registers {*|opl3sw:opl3|opl3_mem:ram|*}] -hold 1
# Z80 I/O: written / read on CE edges only (OPL3Struct_base, seq_reset_n, FIFO rdreq)
set_multicycle_path -from [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -to [get_registers {*|opl3sw:opl3|OPL3Struct_base* *|opl3sw:opl3|seq_reset_n *|opl3sw:opl3|opl3_fifo:in_queue|*}] -setup 3
set_multicycle_path -from [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -to [get_registers {*|opl3sw:opl3|OPL3Struct_base* *|opl3sw:opl3|seq_reset_n *|opl3sw:opl3|opl3_fifo:in_queue|*}] -hold 2

# memclk -> clk21m (OPL3 samples to the DACs) (as msx_mist.sdc)
set_multicycle_path -from [get_clocks {pll|altpll_component|auto_generated|pll1|clk[1]}] -to [get_clocks {pll|altpll_component|auto_generated|pll1|clk[0]}] -setup 2
set_multicycle_path -from [get_clocks {pll|altpll_component|auto_generated|pll1|clk[1]}] -to [get_clocks {pll|altpll_component|auto_generated|pll1|clk[0]}] -hold 1
