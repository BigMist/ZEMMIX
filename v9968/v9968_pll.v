// -----------------------------------------------------------------------------
//	v9968_pll.v
//	V9968 core clock for ZEMMIX: CLK21M x 4 = 85.94MHz, phase aligned to CLK21M
//	(same scheme as f18a_vdp_pll.v), so the CLK21M <-> core crossings are
//	timed as related clocks.
// -----------------------------------------------------------------------------

module v9968_pll (
	input		clk_21m,
	output		clk_core,
	output		locked
);
	wire	[4:0]	clk;

	altpll #(
		.intended_device_family		( "Cyclone IV GX"	),
		.lpm_type					( "altpll"			),
		.operation_mode				( "NORMAL"			),
		.pll_type					( "AUTO"			),
		.compensate_clock			( "CLK0"			),
		.inclk0_input_frequency		( 46545				),		//	21.484MHz (ZEMMIX: 50 x 55 / 128), in ps
		.bandwidth_type				( "AUTO"			),
		.clk0_multiply_by			( 4					),		//	85.94MHz
		.clk0_divide_by				( 1					),
		.clk0_duty_cycle			( 50				),
		.clk0_phase_shift			( "0"				),
		.port_clk0					( "PORT_USED"		),
		.port_locked				( "PORT_USED"		),
		.width_clock				( 5					)
	) u_pll (
		.inclk						( { 1'b0, clk_21m }	),
		.clk						( clk				),
		.locked						( locked			)
	);

	assign clk_core = clk[0];
endmodule
