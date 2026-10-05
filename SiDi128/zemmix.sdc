create_clock -name "CLOCK_50" -period 20.000 [get_ports {CLOCK_50}]
create_clock -name {SPI_SCK}  -period 41.666 -waveform { 20.8 41.666 } [get_ports {SPI_SCK}]

derive_pll_clocks
derive_clock_uncertainty;

# SPI from the ARM (user_io, OSD) is asynchronous to the core (as msx_mist.sdc)
set_clock_groups -asynchronous -group [get_clocks {SPI_SCK}] -group [get_clocks {pll|altpll_component|auto_generated|pll1|clk[*]}]

# OPL3: the NextZ80 runs on memclk (86MHz) with CE every second clock
# (opl3fm.sv: CE <= !CE, WAIT(!CE))
set_multicycle_path -from [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -to [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -setup 2
set_multicycle_path -from [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -to [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -hold 1

# memclk -> clk21m (OPL3 samples to the DACs) (as msx_mist.sdc)
set_multicycle_path -from [get_clocks {pll|altpll_component|auto_generated|pll1|clk[1]}] -to [get_clocks {pll|altpll_component|auto_generated|pll1|clk[0]}] -setup 2
set_multicycle_path -from [get_clocks {pll|altpll_component|auto_generated|pll1|clk[1]}] -to [get_clocks {pll|altpll_component|auto_generated|pll1|clk[0]}] -hold 1
