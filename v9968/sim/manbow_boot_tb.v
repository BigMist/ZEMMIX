// Boot of Space Manbow on the V9968 (ZEMMIX-60f): VRAM / registers of openMSX at
// 1.0 s, then the writes of the game to ports 98h-9Bh up to 7 s (openMSX trace
// "port value" per line) replayed, and the VRAM written out to compare with
// openMSX at 7 s.  (From manbow_tb.v.)
//
//   vvp manbow_boot_tb +vram=boot_vram.bin +pal=boot_pal.bin +trace=boottrace_pv.txt +out=vram_out.bin
//
// Original header:
// Frame of Space Manbow on the V9968 (ZEMMIX-60f): v9968_core + v9968_vram as in
// v9968_vdp_ocm.v, the VRAM / palette / registers dumped by openMSX at a vertical
// interrupt of the game, and the register writes of the game's interrupt routine
// (captured in openMSX) done on each interrupt.  Writes the pixels of a frame:
// "v x r g b" for every new pixel_screen_pos_x[13:4] of each line.
//
//   iverilog -g2012 -o manbow_tb v9968/sim/manbow_tb.v v9968/v9968_vram.v v9968/rtl/*.v
//   vvp manbow_tb +vram=vram.bin +pal=pal.bin +out=frame.txt

`timescale 1ns/1ps

module manbow_boot_tb;

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

	integer tf, n, port, val, k;
	initial begin
		if (!$value$plusargs("vram=%s", fname)) fname = "boot_vram.bin";
		rf = $fopen(fname, "rb"); i = $fread(vram, rf); $fclose(rf);
		if (!$value$plusargs("pal=%s", fname)) fname = "boot_pal.bin";
		rf = $fopen(fname, "rb"); i = $fread(pal, rf); $fclose(rf);
		// registers of openMSX at 1.0 s (boot_regs.txt)
		{regs[0],regs[1],regs[2],regs[3],regs[4],regs[5],regs[6],regs[7]} = 64'h06_60_1F_80_01_EF_0F_F1;
		{regs[8],regs[9],regs[10],regs[11],regs[12],regs[13],regs[14],regs[15]} = 64'h08_00_00_00_00_00_00_00;
		{regs[16],regs[17],regs[18],regs[19],regs[20],regs[21],regs[22],regs[23]} = 64'h00_AC_00_00_00_00_00_00;
		{regs[24],regs[25],regs[26],regs[27]} = 32'h00_00_00_00;
		repeat (10) @(posedge clk);
		reset_n <= 1;
		repeat (300) @(posedge clk);
		initial_busy <= 0;
		repeat (10) @(posedge clk);
		// VRAM straight in (SCREEN 5: not interleaved)
		for (i = 0; i < 131072; i = i + 4) begin
			u_vram.ram0[i >> 2] = vram[i];
			u_vram.ram1[i >> 2] = vram[i + 1];
			u_vram.ram2[i >> 2] = vram[i + 2];
			u_vram.ram3[i >> 2] = vram[i + 3];
		end
		reg_w(16, 8'h00);
		for (i = 0; i < 32; i = i + 1) io_write(3'd2, pal[i]);
		for (i = 0; i < 28; i = i + 1)
			if (i != 15 && i != 16) reg_w(i, regs[i]);
		// the trace
		if (!$value$plusargs("trace=%s", fname)) fname = "boottrace_pv.txt";
		tf = $fopen(fname, "r");
		n = 0;
		while (!$feof(tf)) begin
			k = $fscanf(tf, "%d %h\n", port, val);
			if (k == 2) begin
				io_write(port[2:0], val[7:0]);
				repeat (120) @(posedge clk);
				n = n + 1;
				if (n % 10000 == 0) $display("%0d writes", n);
			end
		end
		$fclose(tf);
		repeat (1000) @(posedge clk);
		if (!$value$plusargs("out=%s", fname)) fname = "vram_out.bin";
		fd = $fopen(fname, "wb");
		for (i = 0; i < 131072; i = i + 4)
			$fwrite(fd, "%c%c%c%c", u_vram.ram0[i >> 2], u_vram.ram1[i >> 2], u_vram.ram2[i >> 2], u_vram.ram3[i >> 2]);
		$fclose(fd);
		$display("done, %0d writes", n);
		$finish;
	end

endmodule
