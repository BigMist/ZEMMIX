// V9968 command engine timing (ZEMMIX-f7c.3): runs each command in SCREEN 5
// and measures the time from the R#46 write until CE = 0 (S#2 polled like a
// CPU would), in V9938 cycles (21.48 MHz, 4 clk), then dumps the VRAM so the
// results can be compared between the openMSX timing and the old fixed wait.
//
//   +define+MODE=0  screen off (R#1 BL = 0)
//   +define+MODE=1  screen on, sprites off (R#8 SPD = 1)
//   +define+MODE=2  screen on, sprites on
//   +define+OLD     the former fixed wait per step (CMD_TIMING_OPENMSX = 0)
//   +define+SMALL HMMV 256x16, HMMM / YMMM / LMMV / LMMM 256x8 (default 256x212, 256x64)
//   +define+DUMP=\"file\"  VRAM dump (hex, one byte per line, 00000h-1FFFFh)
//
//   iverilog -g2012 -DMODE=2 -DSMALL -o ct v9968/sim/cmd_timing_tb.v v9968/v9968_vram.v v9968/rtl/*.v
//   vvp ct                                    (about 5 minutes)
//
//   The full sizes simulate ~0.4 s of VDP time: use Verilator (~2 minutes)
//   verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -O3 --top-module cmd_timing_tb \
//     -DMODE=2 --Mdir obj_ct -o sim v9968/sim/cmd_timing_tb.v v9968/v9968_vram.v v9968/rtl/*.v
//   obj_ct/sim
//
// openMSX reference (master, Zemmix_turboR, same registers, started at VR
// 1 -> 0, CE polled; resolution about 30 cycles), V9938 cycles:
//                   screen off           sprites off          sprites on
//   HMMV 256x212    1343280              1628070              1694040
//   HMMM 256x64      752940               793140              1039680
//   YMMM 64 lines    537870               564390               901170
//   LMMV 256x64     1605090              1947630              2106510
//   LMMM 256x64     2136210              2166180              2939010
//   LINE 200/100      26250                29010                34170
//   SRCH 256          23340                24990                31830
//   HMMC 16x16        19080 (CPU paced, 150 cycles per byte)

`timescale 1ns/1ps

`ifndef MODE
`define MODE 2
`endif
`ifdef SMALL							// quick run: 256x16 HMMV, 256x8 block moves
`define NY_HMMV 16
`define NY_BLK 8
`else
`define NY_HMMV 212
`define NY_BLK 64
`endif

module cmd_timing_tb;
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
		.reset_n(reset_n), .video_reset_n(reset_n), .clk(clk), .initial_busy(initial_busy),
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
`ifdef OLD
	defparam u_core.u_command.CMD_TIMING_OPENMSX = 0;
`endif

	v9968_vram #(.VRAM_256K(0)) u_vram (
		.clk(clk), .bus_address(vram_address), .bus_valid(vram_valid), .bus_write(vram_write),
		.bus_refresh(vram_refresh), .bus_wdata(vram_wdata), .bus_wdata_mask(vram_wdata_mask),
		.bus_rdata(vram_rdata), .bus_rdata_en(vram_rdata_en)
	);

	// ---------------------------------------------------------------- CPU
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

	// R#32-R#45
	task automatic cmd_regs(input [9:0] sx, input [9:0] sy, input [9:0] dx, input [9:0] dy,
	                        input [9:0] nx, input [9:0] ny, input [7:0] col, input [7:0] arg);
		begin
			reg_w(32, sx[7:0]); reg_w(33, {6'd0, sx[9:8]});
			reg_w(34, sy[7:0]); reg_w(35, {6'd0, sy[9:8]});
			reg_w(36, dx[7:0]); reg_w(37, {6'd0, dx[9:8]});
			reg_w(38, dy[7:0]); reg_w(39, {6'd0, dy[9:8]});
			reg_w(40, nx[7:0]); reg_w(41, {6'd0, nx[9:8]});
			reg_w(42, ny[7:0]); reg_w(43, {6'd0, ny[9:8]});
			reg_w(44, col);     reg_w(45, arg);
		end
	endtask

	// Time stamps: R#46 write (register_write of R#46) and CE falling
	realtime t_start, t_end;
	always @(posedge clk)
		if (u_core.u_command.register_write && u_core.u_command.register_num == 6'd46) t_start = $realtime;
	always @(negedge u_core.u_command.ff_command_execute) t_end = $realtime;

	localparam real CYC = 4 * 11.64;		// ns per V9938 cycle

	// S#2 polled until CE = 0
	task automatic wait_ce;
		reg [7:0] s;
		begin
			reg_w(15, 8'd2);
			s = 8'h01;
			while (s[0]) io_read(3'd1, s);
			reg_w(15, 8'd0);
		end
	endtask

	// Start at the top of the display (first display line), like the
	// openMSX reference run (VR 1 -> 0)
	task automatic sync_frame;
		begin
			while (u_core.w_screen_pos_y != 10'h3FF) @(posedge clk);
			while (u_core.w_screen_pos_y != 10'd0) @(posedge clk);
		end
	endtask

	task automatic run(input [7:0] r46, input [8*8-1:0] name);
		begin
			sync_frame;
			reg_w(46, r46);
			wait_ce;
			$display("RESULT mode=%0d %0s %0d", `MODE, name, $rtoi((t_end - t_start) / CYC));
		end
	endtask

	// CPU transfer (HMMC, LMMC): R#17 = R#44 without increment, S#2 TR
	// polled, one byte at most every 150 V9938 cycles (about a Z80 OTIR / TR
	// polling loop; the openMSX reference run paces the same)
	task automatic run_transfer(input [7:0] r46, input integer n, input [8*8-1:0] name);
		reg [7:0] s;
		integer i;
		realtime t_last;
		begin
			t_last = 0;
			reg_w(17, 8'hAC);
			reg_w(15, 8'd2);
			sync_frame;
			reg_w(46, r46);
			i = 1;
			s = 8'h01;
			while (s[0]) begin
				io_read(3'd1, s);
				if (s[7] && s[0] && ($realtime - t_last) >= 150 * CYC) begin
					t_last = $realtime;
					io_write(3'd3, 8'h30 + i[7:0]);
					i = i + 1;
				end
			end
			reg_w(15, 8'd0);
			$display("RESULT mode=%0d %0s %0d (%0d bytes)", `MODE, name, $rtoi((t_end - t_start) / CYC), i);
		end
	endtask

	integer k, f;
	initial begin
		// VRAM pattern
		for (k = 0; k < (1 << 15); k = k + 1) begin
			u_vram.ram0[k] = (k * 7) ^ 8'h5A;
			u_vram.ram1[k] = (k * 13) ^ 8'hA5;
			u_vram.ram2[k] = (k * 3) + 8'h11;
			u_vram.ram3[k] = (k * 5) ^ 8'h3C;
		end
		repeat (10) @(posedge clk);
		reset_n <= 1;
		repeat (300) @(posedge clk);
		initial_busy <= 0;
		repeat (10) @(posedge clk);
		// SCREEN 5, 212 lines, 128 KB
		reg_w(0, 8'h06);
		reg_w(1, (`MODE == 0) ? 8'h00 : 8'h40);
		reg_w(8, (`MODE == 1) ? 8'h0A : 8'h08);
		reg_w(9, 8'h80);
		reg_w(2, 8'h1F); reg_w(5, 8'hEF); reg_w(11, 8'h00); reg_w(6, 8'h0F);
		reg_w(14, 8'h00);

		//        SX   SY   DX   DY   NX   NY   COL    ARG
		cmd_regs(  0,   0,   0,   0, 256, `NY_HMMV, 8'h11, 8'h00); run(8'hC0, "HMMV");
		cmd_regs(  0,   0,   0, 256, 256,  `NY_BLK, 8'h00, 8'h00); run(8'hD0, "HMMM");
		cmd_regs(  0,  10,   0, 400,   0,  `NY_BLK, 8'h00, 8'h00); run(8'hE0, "YMMM");
		cmd_regs(  0,   0,   0,   0, 256,  `NY_BLK, 8'h05, 8'h00); run(8'h82, "LMMV");
		cmd_regs(  0,   0,   0, 300, 256,  `NY_BLK, 8'h00, 8'h00); run(8'h93, "LMMM");
		cmd_regs(  0,   0,  10,  10, 200, 100, 8'h07, 8'h00); run(8'h70, "LINE");
		cmd_regs(  0,   0,  10,  10, 200, 100, 8'h08, 8'h01); run(8'h70, "LINEY");
		cmd_regs(  0,   0,   0,   0,   0,   0, 8'h02, 8'h00); run(8'h60, "SRCH");
		cmd_regs(  0,   0, 100, 100,   0,   0, 8'h09, 8'h00); run(8'h50, "PSET");
		cmd_regs(100, 100,   0,   0,   0,   0, 8'h00, 8'h00); run(8'h40, "POINT");
		cmd_regs(  0,   0,  32, 200,  16,  16, 8'h21, 8'h00); run_transfer(8'hF0, 128, "HMMC");
		cmd_regs(  0,   0,  64, 200,  16,  16, 8'h03, 8'h00); run_transfer(8'hB0, 256, "LMMC");

`ifdef DUMP
		f = $fopen(`DUMP, "w");
		for (k = 0; k < (1 << 15); k = k + 1)
			$fdisplay(f, "%02x\n%02x\n%02x\n%02x", u_vram.ram0[k], u_vram.ram1[k], u_vram.ram2[k], u_vram.ram3[k]);
		$fclose(f);
`endif
		$display("done");
		$finish;
	end
endmodule
