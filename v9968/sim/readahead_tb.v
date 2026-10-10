// V9938 read-ahead of port 98h in the V9968 (ZEMMIX-f7c.1), as openMSX:
// a read address setup prefetches, a 98h read returns the latch and
// prefetches the next byte, a 98h write also loads the latch.
//
//   iverilog -g2012 -o readahead_tb v9968/sim/readahead_tb.v v9968/v9968_vram.v v9968/rtl/*.v
//   vvp readahead_tb

`timescale 1ns/1ps

module readahead_tb;
	reg clk = 0;
	always #5.82 clk = ~clk;			// 85.9 MHz

	reg			reset_n = 0;
	reg			initial_busy = 1;
	reg	[2:0]	bus_address = 0;
	reg			bus_ioreq = 0, bus_write = 1, bus_valid = 0;
	wire		bus_ready;
	reg	[7:0]	bus_wdata = 0;
	wire [7:0]	bus_rdata;
	wire		bus_rdata_en;
	wire		int_n;

	wire [17:2]	vram_address;
	wire		vram_write, vram_valid, vram_rdata_en, vram_refresh;
	wire [31:0]	vram_wdata, vram_rdata;
	wire [3:0]	vram_wdata_mask;

	wire [11:0]	h_count;
	wire [9:0]	v_count;
	wire [13:0]	screen_pos_x;
	wire [7:0]	pr, pg, pb;

	v9968_core u_core (
		.reset_n(reset_n), .clk(clk), .initial_busy(initial_busy),
		.bus_address(bus_address), .bus_ioreq(bus_ioreq), .bus_write(bus_write),
		.bus_valid(bus_valid), .bus_ready(bus_ready), .bus_wdata(bus_wdata),
		.bus_rdata(bus_rdata), .bus_rdata_en(bus_rdata_en), .int_n(int_n),
		.vram_address(vram_address), .vram_write(vram_write), .vram_valid(vram_valid),
		.vram_wdata(vram_wdata), .vram_wdata_mask(vram_wdata_mask), .vram_rdata(vram_rdata),
		.vram_rdata_en(vram_rdata_en), .vram_refresh(vram_refresh),
		.pixel_h_count(h_count), .pixel_v_count(v_count), .pixel_screen_pos_x(screen_pos_x),
		.pixel_r(pr), .pixel_g(pg), .pixel_b(pb),
		.pixel_display_adjust(), .pixel_50hz_mode(), .pixel_field(), .pixel_interlace_mode(),
		.force_highspeed(1'b0), .gamma_openmsx(1'b0), .video_auto(1'b1), .video_50hz(1'b0),
		.ext_cmd_wr(1'b0), .ext_cmd_num(6'd0), .ext_cmd_data(8'd0), .ext_cmd_ce(),
		.button(2'b00), .pulse0(), .pulse1(), .pulse2(), .pulse3(), .pulse4(), .pulse5(),
		.pulse6(), .pulse7()
	);

	v9968_vram #(.VRAM_256K(0)) u_vram (
		.clk(clk), .bus_address(vram_address), .bus_valid(vram_valid), .bus_write(vram_write),
		.bus_refresh(vram_refresh), .bus_wdata(vram_wdata), .bus_wdata_mask(vram_wdata_mask),
		.bus_rdata(vram_rdata), .bus_rdata_en(vram_rdata_en)
	);

	// ---------------------------------------------------------------- CPU
	localparam LINE = 5472;				// clk per line (1368 clk21m)

	task automatic io_write(input [2:0] port, input [7:0] data);
		begin
			@(posedge clk);
			bus_address <= port; bus_wdata <= data; bus_write <= 1;
			bus_ioreq <= 1; bus_valid <= 1;
			@(posedge clk);
			while (!bus_ready) @(posedge clk);
			bus_valid <= 0;
			repeat (24) @(posedge clk);			// ioreq kept as the wrapper does
			bus_ioreq <= 0;
			@(posedge clk);
		end
	endtask

	task automatic io_read(input [2:0] port, output [7:0] data);
		begin
			@(posedge clk);
			bus_address <= port; bus_write <= 0;
			bus_ioreq <= 1; bus_valid <= 1;
			@(posedge clk);
			while (!bus_ready) @(posedge clk);
			bus_valid <= 0;
			while (!bus_rdata_en) @(posedge clk);
			data = bus_rdata;
			bus_ioreq <= 0; bus_write <= 1;
			@(posedge clk);
		end
	endtask

	task automatic reg_w(input [5:0] r, input [7:0] v);
		begin
			io_write(3'd1, v);
			io_write(3'd1, 8'h80 | r);
		end
	endtask
	task automatic set_w(input [13:0] a);
		begin
			io_write(3'd1, a[7:0]);
			io_write(3'd1, 8'h40 | a[13:8]);
		end
	endtask
	task automatic set_r(input [13:0] a);
		begin
			io_write(3'd1, a[7:0]);
			io_write(3'd1, {2'b00, a[13:8]});
		end
	endtask
	integer errs = 0;
	task automatic expect_rd(input [7:0] e, input [8*24-1:0] what);
		reg [7:0] v;
		begin
			io_read(3'd0, v);
			if (v !== e) begin errs = errs + 1; $display("FAIL %0s: read %02X, expected %02X", what, v, e); end
			else $display("ok   %0s: %02X", what, v);
		end
	endtask

	initial begin
		repeat (10) @(posedge clk);
		reset_n <= 1;
		repeat (300) @(posedge clk);
		initial_busy <= 0;
		repeat (10) @(posedge clk);
		reg_w(0, 8'h06); reg_w(1, 8'h20); reg_w(8, 8'h08); reg_w(9, 8'h80);   // SCREEN 5, 128 KB
		reg_w(14, 8'h00);
		// A: write 4 bytes, read them back
		set_w(14'h0100);
		io_write(0, 8'h11); io_write(0, 8'h22); io_write(0, 8'h33); io_write(0, 8'h44);
		set_r(14'h0100);
		expect_rd(8'h11, "A0 0100"); expect_rd(8'h22, "A1 0101"); expect_rd(8'h33, "A2 0102"); expect_rd(8'h44, "A3 0103");
		// B: the write loads the latch; the next read gives the next byte
		set_w(14'h0200);
		io_write(0, 8'hA0); io_write(0, 8'hA1); io_write(0, 8'hA2); io_write(0, 8'hA3);
		set_w(14'h0200);
		io_write(0, 8'h55);
		expect_rd(8'h55, "B latch after OUT");
		expect_rd(8'hA1, "B next 0201");
		expect_rd(8'hA2, "B next 0202");
		// C: R#14 pages 2 and 0
		reg_w(14, 8'h02); set_w(14'h0000); io_write(0, 8'h77);
		reg_w(14, 8'h00); set_w(14'h0000); io_write(0, 8'h66);
		reg_w(14, 8'h02); set_r(14'h0000); expect_rd(8'h77, "C page 2 (08000h)");
		reg_w(14, 8'h00); set_r(14'h0000); expect_rd(8'h66, "C page 0 (00000h)");
		// D: write address after reads, then the next write goes there
		set_r(14'h0100); expect_rd(8'h11, "D read 0100");
		set_w(14'h0101); io_write(0, 8'hEE);
		set_r(14'h0100); expect_rd(8'h11, "D 0100"); expect_rd(8'hEE, "D 0101 written"); expect_rd(8'h33, "D 0102");
		$display("%0d errors", errs);
		$finish;
	end
endmodule
