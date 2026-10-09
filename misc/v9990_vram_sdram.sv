// V9990 VRAM in the 2nd SDRAM (ZEMMIX-1os.4): the memory port of the VRAM
// cache of the V9990 (v9990/rtl/v9990_vram_cache.vhd, clk_v99, 42.95 MHz)
// to port 1 of sdram2 (memclk = 2 x clk_v99, same PLL).
//
// Cache port: req held with we / be / addr / wdata until ack (one clock);
// reads are lines of 4 words (addr with bits 1-0 at 0), rdata the 4 words
// with ack.  sdram2 port: toggle handshake, req / we / be / addr / din
// stable until ack equals req; its reads of port 1 are those lines.
//
// The 512 KB (256K words) are in bank 2 of the SDRAM: {2'b10, 4'b0000, addr}.
// A line takes about 7 clk_v99 from req to ack, a write about 5.
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
	output reg        ack = 1'b0,
	output     [63:0] rdata,

	output reg        s_req = 1'b0,     // to sdram2 port 1 (memclk)
	input             s_ack,
	output reg        s_we = 1'b0,
	output reg  [1:0] s_be = 2'b11,
	output reg [23:0] s_addr = 24'd0,
	output reg [15:0] s_din = 16'd0,
	input      [63:0] s_dout
);

reg busy = 1'b0;
wire done = busy & (s_ack == s_req);

always @(posedge clk) begin
	ack <= 1'b0;
	if (done) begin
		busy <= 1'b0;
		ack  <= 1'b1;
	end
	// the clock of an ack: req is still the request just acked
	else if (req & ~busy & ~ack) begin
		s_we   <= we;
		s_be   <= be;
		s_addr <= {2'b10, 4'b0000, addr};
		s_din  <= wdata;
		s_req  <= ~s_req;
		busy   <= 1'b1;
	end
end

assign rdata = s_dout;

endmodule
