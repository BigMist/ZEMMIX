// Frame of Space Manbow on the V9968 (ZEMMIX-60f): v9968_core + v9968_vram as in
// v9968_vdp_ocm.v, the VRAM / palette / registers dumped by openMSX at a vertical
// interrupt of the game, and the register writes of the game's interrupt routine
// (captured in openMSX) done on each interrupt.  Writes the pixels of a frame:
// "v x r g b" for every new pixel_screen_pos_x[13:4] of each line.
//
//   iverilog -g2012 -o manbow_tb v9968/sim/manbow_tb.v v9968/v9968_vram.v v9968/rtl/*.v
//   vvp manbow_tb +vram=vram.bin +pal=pal.bin +out=frame.txt

`timescale 1ns/1ps

module manbow_tb;

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
		.force_highspeed(1'b0),
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

	// a register write as the game does it (two OUT 99h, ~0.2 line apart)
	task automatic reg_w(input [5:0] r, input [7:0] v);
		begin
			io_write(3'd1, v);
			repeat (500) @(posedge clk);
			io_write(3'd1, 8'h80 | r);
			repeat (500) @(posedge clk);
		end
	endtask

	reg [7:0] vram [0:131071];
	reg [7:0] pal [0:31];
	reg [7:0] regs [0:46];
	integer i, chunk, fd, rf;
	reg [7:0] s, s1;
	reg [8*256-1:0] fname;

	// ------------------------------------------------------------ capture
	reg capture = 0;
	reg [9:0] last_x = 10'h3FF;
	always @(posedge clk) if (capture && screen_pos_x[13:4] != last_x) begin
		last_x <= screen_pos_x[13:4];
		$fdisplay(fd, "%0d %0d %0d %0d %0d", v_count, screen_pos_x[13:4], pr, pg, pb);
	end

	// ----------------------------------------------------------- the game
	reg [7:0] r19 = 8'h90;

	initial begin
		if (!$value$plusargs("vram=%s", fname)) fname = "vram.bin";
		rf = $fopen(fname, "rb"); i = $fread(vram, rf); $fclose(rf);
		if (!$value$plusargs("pal=%s", fname)) fname = "pal.bin";
		rf = $fopen(fname, "rb"); i = $fread(pal, rf); $fclose(rf);
		if (!$value$plusargs("out=%s", fname)) fname = "frame.txt";
		fd = $fopen(fname, "w");
		// registers at the dump (a vertical interrupt): see regs.txt
		{regs[0],regs[1],regs[2],regs[3],regs[4],regs[5],regs[6],regs[7]} = 64'h04_62_30_FF_03_EF_19_FF;
		{regs[8],regs[9],regs[10],regs[11],regs[12],regs[13],regs[14],regs[15]} = 64'h28_80_00_01_00_00_03_00;
		{regs[16],regs[17],regs[18],regs[19],regs[20],regs[21],regs[22],regs[23]} = 64'h0A_2F_70_90_00_00_00_24;
		{regs[24],regs[25],regs[26],regs[27]} = 32'h00_02_00_07;

		repeat (10) @(posedge clk);
		reset_n <= 1;
		repeat (300) @(posedge clk);
		initial_busy <= 0;
		repeat (10) @(posedge clk);

		// mode for the load, display off
		reg_w(1, 8'h22);
		reg_w(0, 8'h04);
		reg_w(9, 8'h80);
		if ($test$plusargs("fastload")) begin
			// straight into the VRAM: G3 / G4 are not interleaved, byte A is
			// word A[16:2], lane A[1:0]
			for (i = 0; i < 131072; i = i + 4) begin
				u_vram.ram0[i >> 2] = vram[i];
				u_vram.ram1[i >> 2] = vram[i + 1];
				u_vram.ram2[i >> 2] = vram[i + 2];
				u_vram.ram3[i >> 2] = vram[i + 3];
			end
		end
		else
		// VRAM through port 98h, 16 KB at a time (R14)
		for (chunk = 0; chunk < 8; chunk = chunk + 1) begin
			reg_w(14, chunk);
			io_write(3'd1, 8'h00);
			io_write(3'd1, 8'h40);
			for (i = 0; i < 16384; i = i + 1)
				io_write(3'd0, vram[chunk * 16384 + i]);
			$display("VRAM %0d KB", (chunk + 1) * 16);
		end
		// palette
		reg_w(16, 8'h00);
		for (i = 0; i < 32; i = i + 1) io_write(3'd2, pal[i]);
		// registers of the dump
		for (i = 0; i < 28; i = i + 1)
			if (i != 15 && i != 16 && i != 17 && i != 14) reg_w(i, regs[i]);
		reg_w(14, regs[14]);
		reg_w(17, regs[17]);
		reg_w(0, 8'h14);					// line interrupts on, as in the frame

		// interrupt routine of the game, for 3 frames; capture the last one
		repeat (8) begin
			@(negedge int_n);
			repeat (LINE) @(posedge clk);	// ~1.2 lines to the first OUT
			reg_w(15, 8'h01);
			io_read(3'd1, s1);				// S#1: FH
			reg_w(15, 8'h00);
			io_read(3'd1, s);				// S#0: F
			if (s[7]) begin					// vertical: top of the screen, SCREEN 5
				if (capture) begin
					capture <= 0;
					$fclose(fd);
					$display("frame written");
					$finish;
				end
				reg_w(1, 8'h22); reg_w(8, 8'h2A); reg_w(23, 8'hC0); reg_w(27, 8'h00);
				reg_w(2, 8'h3F); reg_w(5, 8'hE7); reg_w(19, 8'hDB); reg_w(1, 8'h62);
				reg_w(0, 8'h16);
				r19 = 8'hDB;
				if (!capture && $time > 0) begin
					// capture from the next frame start (v_count wraps)
					@(posedge clk);
					fork begin
						@(v_count == 0);
						capture <= 1;
						$display("capture on");
					end join_none
				end
			end
			else if (s1[0] && r19 == 8'hDB) begin	// line ~28: SCREEN 4, play field
				reg_w(1, 8'h22); reg_w(0, 8'h04); reg_w(8, 8'h28); reg_w(23, 8'h24);
				reg_w(27, 8'h07); reg_w(2, 8'h30); reg_w(5, 8'hE7); reg_w(1, 8'h62);
				reg_w(19, 8'h90); reg_w(0, 8'h14);
				r19 = 8'h90;
			end
			else if (s1[0]) begin				// line ~109: sprites
				reg_w(5, 8'hEF); reg_w(0, 8'h04);
			end
		end
		$display("no frame");
		$finish;
	end

	initial begin
		#2000000000;
		$display("TIMEOUT");
		$finish;
	end

endmodule
