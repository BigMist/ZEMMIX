// PLL for the F18A OCM-PLD wrapper (ocm/f18a_vdp_ocm.vhd).
//
//    clk_core = 21.477MHz * 4 = 85.91MHz
//    clk_pix  = 21.477MHz / 2 = 10.74MHz, phase aligned with clk_core
//
// Set intended_device_family to the FPGA of the target core if Quartus
// complains (the altpll parameters are the same for Cyclone I to 10 LP).

module f18a_vdp_pll (
   input  wire clk_21m,
   output wire clk_core,
   output wire clk_pix,
   output wire locked
);

   wire [4:0] clk;

   altpll #(
      .intended_device_family ("Cyclone IV GX"),
      .lpm_type               ("altpll"),
      .operation_mode         ("NORMAL"),
      .pll_type               ("AUTO"),
      .compensate_clock       ("CLK0"),
      .inclk0_input_frequency (46545),     // 21.484MHz (ZEMMIX: 50 x 55 / 128), in ps
      .bandwidth_type         ("AUTO"),
      .clk0_multiply_by       (4),         // 85.91MHz
      .clk0_divide_by         (1),
      .clk0_duty_cycle        (50),
      .clk0_phase_shift       ("0"),
      .clk1_multiply_by       (1),         // 10.74MHz
      .clk1_divide_by         (2),
      .clk1_duty_cycle        (50),
      .clk1_phase_shift       ("0"),
      .port_clk0              ("PORT_USED"),
      .port_clk1              ("PORT_USED"),
      .port_locked            ("PORT_USED"),
      .width_clock            (5)
   ) pll_inst (
      .inclk  ({1'b0, clk_21m}),
      .clk    (clk),
      .locked (locked)
   );

   assign clk_core = clk[0];
   assign clk_pix  = clk[1];

endmodule
