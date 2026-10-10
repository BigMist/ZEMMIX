#************************************************************
# THIS IS A WIZARD-GENERATED FILE.                           
#
# Version 13.1.4 Build 182 03/12/2014 SJ Full Version
#
#************************************************************

# Copyright (C) 1991-2014 Altera Corporation
# Your use of Altera Corporation's design tools, logic functions 
# and other software and tools, and its AMPP partner logic 
# functions, and any output files from any of the foregoing 
# (including device programming or simulation files), and any 
# associated documentation or information are expressly subject 
# to the terms and conditions of the Altera Program License 
# Subscription Agreement, Altera MegaCore Function License 
# Agreement, or other applicable license agreement, including, 
# without limitation, that your use is for the sole purpose of 
# programming logic devices manufactured by Altera and sold by 
# Altera or its authorized distributors.  Please refer to the 
# applicable agreement for further details.



# Clock constraints

create_clock -name "CLOCK_50" -period 20.000 [get_ports {CLOCK_50}]
create_clock -name {SPI_SCK}  -period 41.666 -waveform { 20.8 41.666 } [get_ports {SPI_SCK}]

# Automatically constrain PLL and other generated clocks
derive_pll_clocks -create_base_clocks

# Automatically calculate clock uncertainty to jitter and other effects.
derive_clock_uncertainty

# Clock groups
set_clock_groups -asynchronous -group [get_clocks {SPI_SCK}] -group [get_clocks pll|altpll_component|auto_generated|pll1|clk[*]]

# Some relaxed constrain to the VGA pins. The signals should arrive together, the delay is not really important.
set_output_delay -clock [get_clocks pll|altpll_component|auto_generated|pll1|clk[0]] -max 0 [get_ports {VGA_*}]
set_output_delay -clock [get_clocks pll|altpll_component|auto_generated|pll1|clk[0]] -min -5 [get_ports {VGA_*}]

set_multicycle_path -to {VGA_*[*]} -setup 2
set_multicycle_path -to {VGA_*[*]} -hold 1

# SDRAM delays
set_input_delay -clock [get_clocks {pll|altpll_component|auto_generated|pll1|clk[1]}] -reference_pin [get_ports {SDRAM_CLK}] -max 6.4 [get_ports SDRAM_DQ[*]]
set_input_delay -clock [get_clocks {pll|altpll_component|auto_generated|pll1|clk[1]}] -reference_pin [get_ports {SDRAM_CLK}] -min 3.2 [get_ports SDRAM_DQ[*]]

set_output_delay -clock [get_clocks {pll|altpll_component|auto_generated|pll1|clk[1]}] -reference_pin [get_ports {SDRAM_CLK}] -max 1.5 [get_ports {SDRAM_D* SDRAM_A* SDRAM_BA* SDRAM_n* SDRAM_CKE}]
set_output_delay -clock [get_clocks {pll|altpll_component|auto_generated|pll1|clk[1]}] -reference_pin [get_ports {SDRAM_CLK}] -min -0.8 [get_ports {SDRAM_D* SDRAM_A* SDRAM_BA* SDRAM_n* SDRAM_CKE}]

set_multicycle_path -from [get_clocks {pll|altpll_component|auto_generated|pll1|clk[1]}] -to [get_clocks {pll|altpll_component|auto_generated|pll1|clk[0]}] -setup 2
set_multicycle_path -from [get_clocks {pll|altpll_component|auto_generated|pll1|clk[1]}] -to [get_clocks {pll|altpll_component|auto_generated|pll1|clk[0]}] -hold 1

set_false_path -to [get_ports {AUDIO_L}]
set_false_path -to [get_ports {AUDIO_R}]
set_false_path -to [get_ports {LED}]

# OPL3 on CLOCK_50 (zemmix.sv, USE_CLOCK_50): its crossings with the core
# clocks are a dcfifo (CPU writes), a toggle (samples, opl3.sv) and the reset
set_clock_groups -asynchronous -group [get_clocks {CLOCK_50}] -group [get_clocks pll|altpll_component|auto_generated|pll1|clk[*]]

# OPL3: the NextZ80 runs with CE every second clock (opl3fm.sv, WAIT(!CE)):
# its registers, and the I/O registers it writes or reads on CE edges
# (OPL3Struct_base, seq_reset_n, FIFO rdreq), change every two clocks.
set_multicycle_path -from [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -to [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -setup 2
set_multicycle_path -from [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -to [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -hold 1
set_multicycle_path -from [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -to [get_registers {*|opl3sw:opl3|OPL3Struct_base* *|opl3sw:opl3|seq_reset_n *|opl3sw:opl3|opl3_fifo:in_queue|*}] -setup 2
set_multicycle_path -from [get_registers {*|opl3sw:opl3|NextZ80:Z80|*}] -to [get_registers {*|opl3sw:opl3|OPL3Struct_base* *|opl3sw:opl3|seq_reset_n *|opl3sw:opl3|opl3_fifo:in_queue|*}] -hold 1

# 2nd SDRAM (DUAL_SDRAM): no I/O constraints, as on the SiDi128.  SDRAM2_CLK is memclk
# inverted (altddio_out in zemmix.sv): the chip samples half a memclk after the pins
# change, the delays of the first SDRAM do not describe it (false hold violations).
