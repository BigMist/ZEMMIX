// V9990 VRAM in the 2nd SDRAM (ZEMMIX-1os.4): the VRAM port of v9990_core
// (clk_v99, 42.95 MHz) to port 1 of sdram2 (memclk = 2 x clk_v99, same PLL).
//
// Core port (as v9990_vram_bram): req held with we / be / addr / wdata
// until ack (one clock), rdata valid with ack.  sdram2 port: toggle
// handshake, req / we / be / addr / din stable until ack equals req.
//
// The 512 KB (256K words) are in bank 2 of the SDRAM: {2'b10, 4'b0000, addr}.
// An access takes about 5 clk_v99 from req to ack.
//
// Contents at power on: what the SDRAM has (openMSX clears the VRAM to
// 00h / FFh every 512 bytes, the core does not depend on it).

module v9990_vram_sdram
(
	input             clk,              // clk_v99
	input             req,
	input             we,
	input       [1:0] be,
	input      [17:0] addr,
	input      [15:0] wdata,
	output            ack,
	output     [15:0] rdata,

	output reg        s_req = 1'b0,     // to sdram2 port 1 (memclk)
	input             s_ack,
	output reg        s_we = 1'b0,
	output reg  [1:0] s_be = 2'b11,
	output reg [23:0] s_addr = 24'd0,
	output reg [15:0] s_din = 16'd0,
	input      [15:0] s_dout
);

reg busy = 1'b0;
wire done = busy & (s_ack == s_req);

always @(posedge clk) begin
	if (done)
		busy <= 1'b0;
	else if (req & ~busy) begin
		s_we   <= we;
		s_be   <= be;
		s_addr <= {2'b10, 4'b0000, addr};
		s_din  <= wdata;
		s_req  <= ~s_req;
		busy   <= 1'b1;
	end
end

// the core drops req after ack (or gives the next one): done is the ack
assign ack   = done;
assign rdata = s_dout;

endmodule
