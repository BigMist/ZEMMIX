// Testbench of misc/sdram2.sv (ZEMMIX-1os.2): an SDRAM model that checks the
// command timing (tRCD, tRC, tRP + write recovery, tRFC, refresh interval,
// mode register) and returns read data with CAS latency 2 and the board
// delay DLY, and two clients doing random reads / writes on their clocks
// (p0 on memclk / 4 as the OPL4, p1 on memclk / 2 as the V9990), checked
// against a copy of the memory.  The reads of p1 are lines of 4 words.
//
// ADAPTER = 1: p1 through misc/v9990_vram_sdram.sv, its client as the VRAM
// cache of the V9990 (req held until ack, the next req right after),
// latency in clk_p1.
//
//   iverilog -g2012 -o sdram2_tb misc/sim/sdram2_tb.sv misc/sdram2.sv misc/v9990_vram_sdram.sv && vvp sdram2_tb
//   (-Psdram2_tb.ADAPTER=1)

`timescale 1ps/1ps

module sdram2_tb;

localparam real T   = 11640.0;       // memclk 85.9 MHz
parameter       ADAPTER = 0;
parameter       DLY = 5000;          // FPGA out -> SDRAM -> FPGA in
localparam      N   = 40000;         // accesses per port

reg clk = 0;
always #(T/2) clk = ~clk;
reg [1:0] div = 0;
always @(posedge clk) div <= div + 1'd1;
wire clk_p0 = div[1];                // memclk / 4
wire clk_p1 = div[0];                // memclk / 2

reg reset = 1;
wire ready;

reg         p0_req = 0, p0_we = 0, p1_we = 0;
wire        p1_req;
reg         p1_req_r = 0;
reg   [1:0] p0_be, p1_be;
reg  [23:0] p0_addr, p1_addr;
reg  [15:0] p0_din, p1_din;
wire        p0_ack, p1_ack, p1_ack_s;
wire  [1:0] s1_be;
wire [23:0] s1_addr;
wire [15:0] s1_din;
wire [63:0] p1_dout_s;
wire        s1_we;

// the V9990 core side of the adapter
reg         c_req = 0;
wire        c_ack;
wire [63:0] c_rdata;

generate if (ADAPTER) begin
	v9990_vram_sdram adapter (
		.clk(clk_p1), .req(c_req), .we(p1_we), .be(p1_be), .addr(p1_addr[17:0]), .wdata(p1_din),
		.ack(c_ack), .rdata(c_rdata),
		.s_req(p1_req), .s_ack(p1_ack_s), .s_we(s1_we), .s_be(s1_be), .s_addr(s1_addr),
		.s_din(s1_din), .s_dout(p1_dout_s));
end else begin
	assign p1_req = p1_req_r;
	assign s1_we = p1_we; assign s1_be = p1_be; assign s1_addr = p1_addr; assign s1_din = p1_din;
end endgenerate
assign p1_ack = p1_ack_s;
wire [15:0] p0_dout;
wire [63:0] p1_dout = ADAPTER ? c_rdata : p1_dout_s;

wire [12:0] A;
wire [15:0] DQ;
wire [1:0]  BA;
wire DQML, DQMH, nWE, nCAS, nRAS, nCS, CKE;

sdram2 #(.CLK_HZ(85909091)) dut (
	.clk(clk), .reset(reset), .ready(ready),
	.p0_req(p0_req), .p0_ack(p0_ack), .p0_we(p0_we), .p0_be(p0_be), .p0_addr(p0_addr), .p0_din(p0_din), .p0_dout(p0_dout),
	.p1_req(p1_req), .p1_ack(p1_ack_s), .p1_we(s1_we), .p1_be(s1_be), .p1_addr(s1_addr), .p1_din(s1_din), .p1_dout(p1_dout_s),
	.SDRAM_A(A), .SDRAM_DQ(DQ), .SDRAM_DQML(DQML), .SDRAM_DQMH(DQMH), .SDRAM_nWE(nWE),
	.SDRAM_nCAS(nCAS), .SDRAM_nRAS(nRAS), .SDRAM_nCS(nCS), .SDRAM_BA(BA), .SDRAM_CKE(CKE)
);

// ---------------------------------------------------------------- SDRAM model
// The model samples on the SDRAM clock (memclk inverted).  Only rows 0-15 of
// each bank are stored (the clients stay there).
integer errors = 0;
reg [15:0] mem [0:4*16*512-1];
function integer idx(input [1:0] b, input [12:0] r, input [8:0] c);
	idx = {b, r[3:0], c};
endfunction

integer cyc = 0;                     // SDRAM clocks
integer act_at [0:3], free_at [0:3];
reg     open [0:3];
reg [12:0] row [0:3];
integer any_free_at = 0, last_ref = -1, refs = 0, max_ref_gap = 0, mode_set = 0;
integer i;
initial for (i = 0; i < 4; i = i + 1) begin act_at[i] = -100; free_at[i] = 0; open[i] = 0; end

reg [15:0] dq_drv;
reg        dq_en = 0;
assign DQ = dq_en ? dq_drv : 16'hZZZZ;

task automatic drive(input [15:0] d);
	begin
		#(T + 6000 + DLY);       // tAC (CL2) from the next SDRAM clock
		dq_drv = d; dq_en = 1;
		#(T - 6000 + 2700);      // tOH after the clock after
		dq_en = 0;
	end
endtask

wire [3:0] c = {nCS, nRAS, nCAS, nWE};
always @(negedge clk) begin
	cyc = cyc + 1;
	case (c)
	4'b0011: begin // ACT
		if (cyc < any_free_at) begin errors++; $display("%t ACT during refresh / precharge all", $time); end
		if (open[BA]) begin errors++; $display("%t ACT bank %0d open", $time, BA); end
		if (cyc < free_at[BA]) begin errors++; $display("%t ACT bank %0d: tRC / tRP (%0d < %0d)", $time, BA, cyc, free_at[BA]); end
		if (!mode_set) begin errors++; $display("%t ACT before the mode register", $time); end
		open[BA] = 1; row[BA] = A; act_at[BA] = cyc;
		free_at[BA] = cyc + 6;                                        // tRC 63 ns
	end
	4'b0101, 4'b0100: begin // RD, WR
		if (!open[BA]) begin errors++; $display("%t RD/WR bank %0d closed", $time, BA); end
		if (cyc - act_at[BA] < 2) begin errors++; $display("%t tRCD", $time); end
		// reads of a line: the bank stays open until the READ with A10
		if (!A[10] && c == 4'b0100) begin errors++; $display("%t write without auto precharge", $time); end
		if (row[BA] > 15) begin errors++; $display("%t row %0d out of the model", $time, row[BA]); end
		if (A[10]) open[BA] = 0;
		if (c == 4'b0100) begin
			if (!DQML) mem[idx(BA, row[BA], A[8:0])][7:0]  = DQ[7:0];
			if (!DQMH) mem[idx(BA, row[BA], A[8:0])][15:8] = DQ[15:8];
			if (free_at[BA] < cyc + 4) free_at[BA] = cyc + 4;         // tWR 2 + tRP 2
		end else begin
			if (DQML || DQMH) begin errors++; $display("%t DQM on read", $time); end
			fork drive(mem[idx(BA, row[BA], A[8:0])]); join_none
			if (free_at[BA] < cyc + 3) free_at[BA] = cyc + 3;         // tRP 2
		end
	end
	4'b0010: begin // PRE
		if (!A[10]) begin errors++; $display("%t precharge one bank", $time); end
		for (i = 0; i < 4; i = i + 1) open[i] = 0;
		any_free_at = cyc + 2;
	end
	4'b0001: begin // REF
		for (i = 0; i < 4; i = i + 1)
			if (open[i] || cyc < free_at[i]) begin errors++; $display("%t REF with bank %0d busy", $time, i); end
		if (cyc < any_free_at) begin errors++; $display("%t REF: tRFC", $time); end
		any_free_at = cyc + 7;                                        // tRFC 66 ns
		if (ready) begin
			if (last_ref >= 0 && cyc - last_ref > max_ref_gap) max_ref_gap = cyc - last_ref;
			last_ref = cyc; refs = refs + 1;
		end
	end
	4'b0000: begin // MRS
		if (A != 13'h0220 || BA != 0) begin errors++; $display("%t mode %h", $time, A); end
		if (cyc < any_free_at) begin errors++; $display("%t MRS: tRFC", $time); end
		mode_set = 1;
	end
	default: ;
	endcase
end

// ---------------------------------------------------------------- clients
reg [15:0] ref_mem [0:4*16*512-1];
initial for (i = 0; i < 4*16*512; i = i + 1) begin mem[i] = 16'hxxxx; ref_mem[i] = 16'hxxxx; end

// p0: rows 0-15 of bank 0-1 (OPL4), p1: rows 0-15 of bank 2-3 (V9990)
function [23:0] raddr(input integer port);
	reg [23:0] a;
	begin
		a = 24'd0;
		a[23] = port[0];
		a[22] = (ADAPTER && port[0]) ? 1'b0 : $urandom % 2;   // the adapter: bank 2
		a[12:9]  = $urandom % 16;
		a[8:0]   = $urandom % 512;
		raddr = a;
	end
endfunction
// a line of p1 (4 words) as ref_mem has it
function [63:0] rline(input [23:0] a);
	begin
		rline = {ref_mem[ri({a[23:2], 2'd3})], ref_mem[ri({a[23:2], 2'd2})],
		         ref_mem[ri({a[23:2], 2'd1})], ref_mem[ri({a[23:2], 2'd0})]};
	end
endfunction
function integer ri(input [23:0] a);
	ri = idx(a[23:22], a[21:9], a[8:0]);
endfunction

integer done0 = 0, done1 = 0, rd0 = 0, rd1 = 0;
integer lat_max0 = 0, lat_max1 = 0;
time    t0, t1_end;

task automatic client0;
	integer k;
	time t;
	reg [15:0] exp;
	begin
		for (k = 0; k < N; k = k + 1) begin
			@(posedge clk_p0);
			p0_addr = raddr(0);
			p0_we   = ($urandom % 3) == 0 || ref_mem[ri(p0_addr)] === 16'hxxxx;
			p0_be   = p0_we ? (1 + $urandom % 3) : 2'b11;
			p0_din  = $urandom;
			p0_req  = ~p0_req;
			t = $time;
			do @(posedge clk_p0); while (p0_ack != p0_req);
			if (($time - t) / T > lat_max0) lat_max0 = ($time - t) / T;
			if (p0_we) begin
				if (p0_be[0]) ref_mem[ri(p0_addr)][7:0]  = p0_din[7:0];
				if (p0_be[1]) ref_mem[ri(p0_addr)][15:8] = p0_din[15:8];
			end else begin
				exp = ref_mem[ri(p0_addr)];
				rd0 = rd0 + 1;
				for (int b = 0; b < 16; b++)
					if (exp[b] !== 1'bx && exp[b] !== p0_dout[b]) begin
						errors++; $display("%t p0 read %h: %h, expected %h", $time, p0_addr, p0_dout, exp); break;
					end
			end
		end
		done0 = 1;
	end
endtask

task automatic client1;
	integer k;
	time t;
	reg [63:0] exp;
	begin
		for (k = 0; k < N; k = k + 1) begin
			@(posedge clk_p1);
			#1;                     // as a flip-flop: after the edge
			p1_addr = raddr(1);
			p1_we   = ($urandom % 3) == 0 || rline(p1_addr) === 64'hx;
			if (!p1_we) p1_addr[1:0] = 2'd0;                  // reads: lines
			p1_be   = p1_we ? (1 + $urandom % 3) : 2'b11;
			p1_din  = $urandom;
			t = $time;
			if (ADAPTER) begin
				// as the core: req from this clock, ack sampled on the following ones
				c_req = 1;
				do @(posedge clk_p1); while (!c_ack);
				#1;
				c_req = 0;
			end else begin
				p1_req_r = ~p1_req_r;
				do @(posedge clk_p1); while (p1_ack != p1_req);
			end
			if (($time - t) / T > lat_max1) lat_max1 = ($time - t) / T;
			if (p1_we) begin
				if (p1_be[0]) ref_mem[ri(p1_addr)][7:0]  = p1_din[7:0];
				if (p1_be[1]) ref_mem[ri(p1_addr)][15:8] = p1_din[15:8];
			end else begin
				exp = rline(p1_addr);
				rd1 = rd1 + 1;
				for (int b = 0; b < 64; b++)
					if (exp[b] !== 1'bx && exp[b] !== p1_dout[b]) begin
						errors++; $display("%t p1 read %h: %h, expected %h", $time, p1_addr, p1_dout, exp); break;
					end
			end
		end
		done1 = 1;
		t1_end = $time;
	end
endtask

initial begin
	repeat (10) @(posedge clk);
	reset = 0;
	// a write before ready waits for it (the ZEMMIX.ROM loader may start early)
	@(posedge clk_p0);
	p0_addr = 24'h000123; p0_we = 1; p0_be = 2'b11; p0_din = 16'hA55A;
	p0_req = ~p0_req;
	repeat (100) @(posedge clk_p0);
	if (p0_ack == p0_req) begin errors++; $display("write acked before ready"); end
	do @(posedge clk_p0); while (p0_ack != p0_req);
	ref_mem[ri(p0_addr)] = p0_din;
	if (!ready) begin errors++; $display("write done before ready"); end
	$display("ready after %0d us", $time / 1000000);
	t0 = $time;
	fork client0; client1; join
	$display("%0d + %0d accesses (%0d + %0d reads) in %0d memclk: %.2f M/s",
	         N, N, rd0, rd1, ($time - t0) / T, 2.0 * N / (($time - t0) / 1e12) / 1e6);
	$display("max latency p0 %0d, p1 %0d memclk; %0d refreshes, max gap %0d memclk (%.2f us)",
	         lat_max0, lat_max1, refs, max_ref_gap, max_ref_gap * T / 1e6);
	if (ADAPTER)
		$display("adapter: p1 %.2f M accesses/s alone with p0 busy, %.1f clk_v99 per access",
		         N / ((t1_end - t0) / 1e12) / 1e6, (t1_end - t0) / (2.0 * T) / N);
	if (max_ref_gap * T > 7.8e6) begin errors++; $display("refresh gap over 7.8 us"); end
	if (errors == 0) $display("PASS");
	else $display("FAIL: %0d errors", errors);
	$finish;
end

initial begin #(400.0 * 1e9); $display("TIMEOUT"); $finish; end

endmodule
