// -----------------------------------------------------------------------------
//	v9968_vram.v
//	VRAM for the V9968 in FPGA block RAM, in place of the cartridge SDRAM.
//
//	Same bus as ip_sdram (V9968 cartridge): 32-bit words, write mask active
//	high (1 = byte not written), and the same timing: a request is taken
//	only when the controller is idle, it is busy for 8 clocks, and the read
//	data comes with bus_rdata_en 8 clocks after bus_valid.  Refresh requests
//	take a slot like on the SDRAM.  The VDP schedules its VRAM slots on that
//	timing, so it is kept exactly.
//
//	VRAM_256K = 0: 128KB (32K words, 128 M9K), the address bit 17 is ignored.
//	VRAM_256K = 1: 256KB (64K words, 256 M9K).
// -----------------------------------------------------------------------------

module v9968_vram #(
	parameter			VRAM_256K = 0
) (
	input				clk,
	input		[17:2]	bus_address,
	input				bus_valid,
	input				bus_write,
	input				bus_refresh,
	input		[31:0]	bus_wdata,
	input		[3:0]	bus_wdata_mask,
	output		[31:0]	bus_rdata,
	output				bus_rdata_en
);
	localparam			AW = VRAM_256K ? 16 : 15;
	localparam			LATENCY = 8;

	reg			[7:0]	ram0 [0:(1 << AW) - 1];
	reg			[7:0]	ram1 [0:(1 << AW) - 1];
	reg			[7:0]	ram2 [0:(1 << AW) - 1];
	reg			[7:0]	ram3 [0:(1 << AW) - 1];

	wire		[AW-1:0]	w_address;
	wire				w_accept;
	wire				w_we;
	reg			[2:0]	ff_busy_count = 3'd0;
	reg			[31:0]	ff_q;
	reg			[31:0]	ff_rdata;
	reg			[LATENCY-1:0]	ff_read_pipe = { LATENCY { 1'b0 } };

	assign w_address	= bus_address[AW+1:2];

	// ip_sdram takes a request in c_main_state_ready only, and returns there
	// 8 clocks later.
	assign w_accept		= (ff_busy_count == 3'd0) && (bus_valid || bus_refresh);
	assign w_we			= w_accept && !bus_refresh && bus_write;

	always @( posedge clk ) begin
		if( w_accept ) begin
			ff_busy_count	<= 3'd7;
		end
		else if( ff_busy_count != 3'd0 ) begin
			ff_busy_count	<= ff_busy_count - 3'd1;
		end
	end

	always @( posedge clk ) begin
		if( w_we && !bus_wdata_mask[0] ) ram0[ w_address ] <= bus_wdata[ 7: 0];
		if( w_we && !bus_wdata_mask[1] ) ram1[ w_address ] <= bus_wdata[15: 8];
		if( w_we && !bus_wdata_mask[2] ) ram2[ w_address ] <= bus_wdata[23:16];
		if( w_we && !bus_wdata_mask[3] ) ram3[ w_address ] <= bus_wdata[31:24];
		ff_q	<= { ram3[ w_address ], ram2[ w_address ], ram1[ w_address ], ram0[ w_address ] };
	end

	// Read pipe: ff_read_pipe[0] marks the clock after the request, when ff_q
	// holds the word.  It is kept until bus_rdata_en, LATENCY clocks after the
	// request; the next request is 8 clocks after this one at the earliest.
	always @( posedge clk ) begin
		ff_read_pipe	<= { ff_read_pipe[LATENCY-2:0], w_accept && !bus_refresh && !bus_write };
		if( ff_read_pipe[0] ) begin
			ff_rdata	<= ff_q;
		end
	end

	assign bus_rdata	= ff_rdata;
	assign bus_rdata_en	= ff_read_pipe[LATENCY-1];
endmodule
