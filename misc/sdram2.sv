// SDRAM2: controller for the 2nd SDRAM of the SiDi128 (DUAL_SDRAM), for the
// OPL4 wave memory and the V9990 VRAM (ZEMMIX-1os.2).
//
// Same timing as the SDRAM controller of emsx_top, which works on these
// boards: memclk (85.9 MHz), SDRAM_CLK = memclk inverted (altddio_out in
// zemmix.sv), CAS latency 2, single accesses with auto precharge, the read
// data taken from the pins RD_DELAY memclk after the edge that gives READ.
//
// One access every 6 memclk (ACT, NOP, READ/WRITE, NOP x3: tRC, tRAS and
// the write recovery + precharge of the auto precharge all fit), a refresh
// every 7 us that takes 7 memclk.  Banks are not interleaved.
//
// Reads of port 1 (the V9990 VRAM cache, v9990/rtl/v9990_vram_cache.vhd)
// are lines of 4 words: addr with bits 1-0 at 0, 4 READ one after the
// other in the open row, the last one with auto precharge; p1_dout has
// the 4 words (word 0 in bits 15-0).  9 memclk to the next ACT.
//
// Address: 16-bit words, {bank[1:0], row[12:0], col[8:0]} = 32 MB.  A chip
// with 10 column bits works as well (A9 is 0: half of each row is used).
//
// Ports p0 (OPL4) and p1 (V9990), toggle handshake: the client sets we, be,
// addr, din and toggles req; they stay as they are until ack equals req
// again.  dout is valid when ack equals req (reads).  The clients run on
// clocks from the same PLL (clk_sys = memclk / 4, 42.95 MHz = memclk / 2),
// so req, addr, ... are taken as they are, without synchronizers.  With
// both ports waiting they take turns.
//
// reset: only at power on (the PLL lock): the wave memory keeps ZEMMIX.ROM
// over the MSX resets.  A request before ready waits for it.

module sdram2 #(
	parameter CLK_HZ   = 85909091,
	parameter RD_DELAY = 3
)(
	input             clk,
	input             reset,
	output reg        ready,

	input             p0_req,
	output reg        p0_ack = 1'b0,
	input             p0_we,
	input      [1:0]  p0_be,
	input     [23:0]  p0_addr,
	input     [15:0]  p0_din,
	output reg [15:0] p0_dout,

	input             p1_req,
	output reg        p1_ack = 1'b0,
	input             p1_we,
	input      [1:0]  p1_be,
	input     [23:0]  p1_addr,
	input     [15:0]  p1_din,
	output reg [63:0] p1_dout,

	output reg [12:0] SDRAM_A,
	inout      [15:0] SDRAM_DQ,
	output reg        SDRAM_DQML,
	output reg        SDRAM_DQMH,
	output            SDRAM_nWE,
	output            SDRAM_nCAS,
	output            SDRAM_nRAS,
	output            SDRAM_nCS,
	output reg  [1:0] SDRAM_BA,
	output            SDRAM_CKE
);

localparam INIT_WAIT = CLK_HZ / 5000;      // 200 us after power on
localparam REF_EVERY = CLK_HZ / 142857;    // 7 us: 8192 rows in 57 ms (64 ms)

//                         nCS nRAS nCAS nWE
localparam CMD_NOP = 4'b0111;
localparam CMD_ACT = 4'b0011;
localparam CMD_RD  = 4'b0101;
localparam CMD_WR  = 4'b0100;
localparam CMD_PRE = 4'b0010;
localparam CMD_REF = 4'b0001;
localparam CMD_MRS = 4'b0000;

// burst single write, CAS latency 2, sequential, burst length 1 (as emsx_top)
localparam MODE = 13'b00_0_1_0_0_010_0_000;

reg  [3:0] cmd = CMD_NOP;
assign {SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} = cmd;
assign SDRAM_CKE = 1'b1;

reg [15:0] dq_out;
reg        dq_oe = 1'b0;
reg [15:0] dq_in;
assign SDRAM_DQ = dq_oe ? dq_out : 16'hZZZZ;

reg  [1:0] rst_s = 2'b11;
reg [14:0] wait_cnt = 15'd0;
reg  [3:0] init_step = 4'd0;           // 0 precharge all, 1-8 refresh, 9 mode, 10 done
reg  [9:0] ref_cnt = 10'd0;
reg        ref_due = 1'b0;

reg  [3:0] busy = 4'd0;                // memclk left before the next command
reg  [1:0] step = 2'd0;                // access: 2 ACT given, 1 READ / WRITE now
reg  [1:0] brst = 2'd0;                // line read: READs left after the first
reg  [1:0] inflight = 2'b00;           // ports with an access given and not acked
reg        acc_port, acc_we, last_port = 1'b1;
reg  [1:0] acc_be;
wire       line = acc_port & ~acc_we;      // port 1 reads: lines
reg  [8:0] acc_col;
reg [15:0] acc_din;
reg [RD_DELAY:0] rd_pipe = 0;          // a READ RD_DELAY + 1 memclk ago: [RD_DELAY]
reg [RD_DELAY:0] rd_port = 0;
reg [RD_DELAY:0] rd_last = 0;          // the last READ of an access

wire p0_pend = (p0_req ^ p0_ack) & ~inflight[0];
wire p1_pend = (p1_req ^ p1_ack) & ~inflight[1];
wire take1   = p1_pend & (~p0_pend | ~last_port);

// the pins: input register every memclk (FAST_INPUT_REGISTER)
always @(posedge clk) dq_in <= SDRAM_DQ;

always @(posedge clk) begin
	rst_s <= {rst_s[0], reset};

	cmd   <= CMD_NOP;
	dq_oe <= 1'b0;
	if (busy != 4'd0) busy <= busy - 1'd1;
	if (step != 2'd0) step <= step - 1'd1;

	// read data: taken from the pins RD_DELAY memclk after READ
	rd_pipe <= {rd_pipe[RD_DELAY-1:0], 1'b0};
	rd_port <= {rd_port[RD_DELAY-1:0], acc_port};
	rd_last <= {rd_last[RD_DELAY-1:0], 1'b0};
	if (rd_pipe[RD_DELAY]) begin
		if (rd_port[RD_DELAY]) begin
			p1_dout <= {dq_in, p1_dout[63:16]};           // 4 words: word 0 ends in 15-0
			if (rd_last[RD_DELAY]) begin p1_ack <= p1_req; inflight[1] <= 1'b0; end
		end
		else begin p0_dout <= dq_in; p0_ack <= p0_req; inflight[0] <= 1'b0; end
	end

	if (rst_s[1]) begin
		ready     <= 1'b0;
		wait_cnt  <= 15'd0;
		init_step <= 4'd0;
		busy      <= 4'd0;
		step      <= 2'd0;
		brst      <= 2'd0;
		inflight  <= 2'b00;
		rd_pipe   <= 0;                         // an access cut short is given again
	end
	else if (!ready) begin
		// power on: 200 us, precharge all, 8 refresh, mode register
		if (wait_cnt != INIT_WAIT[14:0])
			wait_cnt <= wait_cnt + 1'd1;
		else if (busy == 4'd0) begin
			init_step <= init_step + 1'd1;
			if (init_step == 4'd0) begin
				cmd     <= CMD_PRE;
				SDRAM_A <= 13'h0400;               // A10: all banks
				busy    <= 4'd2;
			end else if (init_step <= 4'd8) begin
				cmd  <= CMD_REF;
				busy <= 4'd6;
			end else if (init_step == 4'd9) begin
				cmd      <= CMD_MRS;
				SDRAM_A  <= MODE;
				SDRAM_BA <= 2'b00;
				busy     <= 4'd2;
			end else
				ready <= 1'b1;                      // what was asked before is done now
		end
	end
	else if (step == 2'd1) begin
		// tRCD: READ / WRITE two memclk after ACT, auto precharge (A10); a
		// line read of port 1: the first of 4 READ, without auto precharge
		cmd        <= acc_we ? CMD_WR : CMD_RD;
		SDRAM_A    <= {2'b00, ~line, 1'b0, acc_col};
		SDRAM_DQML <= acc_we & ~acc_be[0];
		SDRAM_DQMH <= acc_we & ~acc_be[1];
		dq_out     <= acc_din;
		dq_oe      <= acc_we;
		if (line) begin
			brst    <= 2'd3;
			acc_col <= acc_col + 1'd1;
		end
		if (!acc_we) begin
			rd_pipe[0] <= 1'b1;
			rd_last[0] <= ~line;
		end
		else if (acc_port) begin
			p1_ack <= p1_req; inflight[1] <= 1'b0;
		end else begin
			p0_ack <= p0_req; inflight[0] <= 1'b0;
		end
	end
	else if (brst != 2'd0) begin
		// the next READ of a line, the last one with auto precharge
		cmd        <= CMD_RD;
		SDRAM_A    <= {2'b00, brst == 2'd1, 1'b0, acc_col};
		acc_col    <= acc_col + 1'd1;
		brst       <= brst - 1'd1;
		rd_pipe[0] <= 1'b1;
		rd_last[0] <= brst == 2'd1;
	end
	else if (busy == 4'd0) begin
		if (ref_due) begin
			cmd  <= CMD_REF;
			busy <= 4'd6;                           // tRFC: 7 memclk (81 ns)
		end else if (p0_pend | p1_pend) begin
			acc_port  <= take1;
			last_port <= take1;
			inflight[take1] <= 1'b1;
			acc_we    <= take1 ? p1_we   : p0_we;
			acc_be    <= take1 ? p1_be   : p0_be;
			acc_din   <= take1 ? p1_din  : p0_din;
			acc_col   <= take1 ? p1_addr[8:0] : p0_addr[8:0];
			SDRAM_A   <= take1 ? p1_addr[21:9] : p0_addr[21:9];
			SDRAM_BA  <= take1 ? p1_addr[23:22] : p0_addr[23:22];
			cmd       <= CMD_ACT;
			step      <= 2'd2;
			// tRC: next ACT 6 memclk later; a line: 3 READ more, then tRP
			busy      <= (take1 & ~p1_we) ? 4'd8 : 4'd5;
		end
	end

	// refresh every 7 us (after the arbiter: a refresh given now clears it first)
	if (ready && busy == 4'd0 && step == 2'd0 && brst == 2'd0 && ref_due && !rst_s[1])
		ref_due <= 1'b0;
	if (ref_cnt == REF_EVERY[9:0] - 1'd1) begin
		ref_cnt <= 10'd0;
		ref_due <= ready;
	end else
		ref_cnt <= ref_cnt + 1'd1;
end

endmodule
