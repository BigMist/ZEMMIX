// -----------------------------------------------------------------------------
//	v9968_vdp_ocm.v
//	V9968 (HRA!) as the ZEMMIX / OCM-PLD VDP.
//
//	Drop-in for the ESE / OCM VDP entity (esemsx3/src/video/vdp.vhd), same
//	module name and ports (lower case, the VHDL component binds by name), plus
//	wait_n.  The ports of the V9968 are at 98h-9Ch (9Ch: V9968 extension
//	port), emsx_top decodes 98h-9Fh for it.
//
//	Clocks: the V9968 runs at CLK21M x 4 (85.94MHz) from v9968_pll.  Its 15KHz
//	line is 5472 core clocks = 1368 CLK21M cycles, like the V9938.
//
//	VRAM: in block RAM (v9968_vram), the OCM SDRAM VRAM port is unused, like
//	with the F18A.
//
//	Video: the native pixel stream of the V9968 (before its upscan / 800x480
//	scaler) at 15KHz, 684 half pixels of two CLK21M cycles per line, 6-bit RGB
//	with HS, VS, CS and BLANK_O, as the F18A wrapper gives it to zemmix.sv
//	(mist_video doubles it).  DISPRESO is ignored: always 15KHz.
//
//	Bus: every CPU access (req) is passed to the V9968 bus (msx_slot of the
//	cartridge) through toggles.  A VRAM read waits for a VRAM slot, so
//	wait_n is low from the read request until its data is in dbi.
// -----------------------------------------------------------------------------

module vdp #(
	parameter			VRAM_256K = 0
) (
	input				clk21m,
	input				reset,
	input				req,
	output				ack,
	input				wrt,
	input		[15:0]	adr,
	output		[7:0]	dbi,
	input		[7:0]	dbo,

	output				int_n,
	output				wait_n,
	output				busy,			//	a request (read or write) is still running in the V9968
	output				field_o,		//	ZEMMIX: field (EO page, 1 = odd), on clk21m
	output				interlace_o,	//	ZEMMIX: R#9 IL, on clk21m (31 kHz bob in zemmix.sv)

	output				pramoe_n,
	output				pramwe_n,
	output		[16:0]	pramadr,
	input		[15:0]	pramdbi,
	output		[7:0]	pramdbo,

	input				vdpspeedmode,
	input		[2:0]	ratiomode,
	input				centeryjk_r25_n,

	output		[5:0]	pvideor,
	output		[5:0]	pvideog,
	output		[5:0]	pvideob,
	output				pvideohs_n,
	output				pvideovs_n,
	output				pvideocs_n,
	output				pvideodhclk,
	output				pvideodlclk,
	output				blank_o,

	input				dispreso,
	input				ntsc_pal_type,
	input				forced_v_mode,
	input				legacy_vga,
	input		[4:0]	vdp_id,
	input		[6:0]	offset_y
);
	// 15KHz video window, in half pixels (8 core clocks) from the left of the
	// V9968 upscan line buffer (its write address), and in 15KHz lines.
	localparam			c_h_total			= 11'd684;
	localparam			c_h_visible			= 11'd576;		//	as the V9968 video_out (576 half pixels)
	localparam			c_hs_start			= 11'd590;
	localparam			c_hs_end			= 11'd636;		//	46 half pixels = 4.28us
	localparam			c_v_visible			= 9'd240;
	localparam			c_v_start_60		= 9'd7;			//	V9968 video_out: v_count 14
	localparam			c_v_start_50		= 9'd34;		//	18 lines over the 212 lines image, as at 60Hz
	localparam			c_vs_start_60		= 9'd255;		//	V9968 video_out: v_count 510-516
	localparam			c_vs_start_50		= 9'd306;		//	V9968 video_out: v_count 612-618
	localparam			c_vs_lines			= 9'd3;

	wire				clk;
	wire				pll_locked;

	// --------------------------------------------------------------------
	//	Clock and reset
	// --------------------------------------------------------------------
	v9968_pll u_pll (
		.clk_21m			( clk21m			),
		.clk_core			( clk				),
		.locked				( pll_locked		)
	);

	reg			[2:0]	ff_reset_n = 3'd0;
	reg			[7:0]	ff_initial_count = 8'd0;
	wire				reset_n;
	wire				w_initial_busy;

	always @( posedge clk ) begin
		ff_reset_n	<= { ff_reset_n[1:0], ~reset & pll_locked };
	end

	assign reset_n = ff_reset_n[2];

	//	initial_busy: a few clocks after reset (SDRAM initialization on the
	//	cartridge).
	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_initial_count	<= 8'd0;
		end
		else if( ff_initial_count != 8'hFF ) begin
			ff_initial_count	<= ff_initial_count + 8'd1;
		end
	end

	assign w_initial_busy = (ff_initial_count != 8'hFF);

	// --------------------------------------------------------------------
	//	Dot clocks for the OCM SDRAM controller, same sequence as the
	//	original VDP (ssg): DH = 10.74MHz, DL = 5.37MHz.
	// --------------------------------------------------------------------
	reg			[1:0]	ff_dotstate = 2'd0;
	reg					ff_dhclk = 1'b0;
	reg					ff_dlclk = 1'b0;

	always @( posedge clk21m ) begin
		if( reset ) begin
			ff_dotstate	<= 2'b00;
			ff_dhclk	<= 1'b0;
			ff_dlclk	<= 1'b0;
		end
		else begin
			case( ff_dotstate )
			2'b00:		begin ff_dotstate <= 2'b01; ff_dhclk <= 1'b0; ff_dlclk <= 1'b1; end
			2'b01:		begin ff_dotstate <= 2'b11; ff_dhclk <= 1'b1; ff_dlclk <= 1'b0; end
			2'b11:		begin ff_dotstate <= 2'b10; ff_dhclk <= 1'b0; ff_dlclk <= 1'b0; end
			default:	begin ff_dotstate <= 2'b00; ff_dhclk <= 1'b1; ff_dlclk <= 1'b1; end
			endcase
		end
	end

	assign pvideodhclk	= ff_dhclk;
	assign pvideodlclk	= ff_dlclk;

	// --------------------------------------------------------------------
	//	Host bus bridge, CLK21M side
	// --------------------------------------------------------------------
	reg					ff_req_toggle = 1'b0;
	reg			[2:0]	ff_req_address = 3'd0;
	reg					ff_req_write = 1'b0;
	reg			[7:0]	ff_req_wdata = 8'd0;
	reg					ff_ack = 1'b0;
	reg					ff_read_wait = 1'b0;
	reg					ff_busy = 1'b0;
	reg			[2:0]	ff_done_sync = 3'd0;
	reg			[7:0]	ff_dbi = 8'hFF;
	wire				w_done;
	reg					ff_done_toggle = 1'b0;		//	core side
	reg			[7:0]	ff_done_rdata = 8'hFF;		//	core side

	always @( posedge clk21m ) begin
		ff_ack		<= req;
		ff_done_sync	<= { ff_done_sync[1:0], ff_done_toggle };
	end

	assign w_done = ff_done_sync[2] ^ ff_done_sync[1];

	always @( posedge clk21m ) begin
		if( reset ) begin
			ff_req_toggle	<= 1'b0;
			ff_read_wait	<= 1'b0;
			ff_busy			<= 1'b0;
			ff_dbi			<= 8'hFF;
		end
		else begin
			if( req ) begin
				ff_req_address	<= adr[2:0];
				ff_req_write	<= wrt;
				ff_req_wdata	<= dbo;
				ff_req_toggle	<= ~ff_req_toggle;
				ff_read_wait	<= ~wrt;
				ff_busy			<= 1'b1;
			end
			else if( w_done ) begin
				ff_read_wait	<= 1'b0;
				ff_busy			<= 1'b0;
			end

			if( w_done && !ff_req_write ) begin
				ff_dbi			<= ff_done_rdata;
			end
		end
	end

	assign ack		= ff_ack;
	assign dbi		= ff_dbi;
	assign wait_n	= ~(ff_read_wait | req & ~wrt);
	assign busy		= ff_busy;		//	a new request now would overwrite the running one (R800 fast path holds it)

	// --------------------------------------------------------------------
	//	Host bus bridge, core side (as msx_slot of the cartridge)
	// --------------------------------------------------------------------
	localparam			c_write_hold	= 6'd24;		//	ioreq kept after a write, like a slot cycle
	reg			[2:0]	ff_req_sync = 3'd0;
	wire				w_req;
	reg					ff_bus_valid;
	reg					ff_bus_ioreq;
	reg					ff_bus_write;
	reg			[2:0]	ff_bus_address;
	reg			[7:0]	ff_bus_wdata;
	reg			[7:0]	ff_bus_timer;
	wire				w_bus_ready;
	wire		[7:0]	w_bus_rdata;
	wire				w_bus_rdata_en;

	always @( posedge clk ) begin
		ff_req_sync	<= { ff_req_sync[1:0], ff_req_toggle };
	end

	assign w_req = ff_req_sync[2] ^ ff_req_sync[1];

	always @( posedge clk ) begin
		if( !reset_n ) begin
			ff_bus_valid	<= 1'b0;
			ff_bus_ioreq	<= 1'b0;
			ff_bus_write	<= 1'b1;
			ff_bus_address	<= 3'd0;
			ff_bus_wdata	<= 8'd0;
			ff_bus_timer	<= 8'd0;
			ff_done_toggle	<= 1'b0;
			ff_done_rdata	<= 8'hFF;
		end
		else if( w_req ) begin
			//	ff_req_* are stable: set with the toggle, two clocks ago
			ff_bus_valid	<= 1'b1;
			ff_bus_ioreq	<= 1'b1;
			ff_bus_write	<= ff_req_write;
			ff_bus_address	<= ff_req_address;
			ff_bus_wdata	<= ff_req_wdata;
			ff_bus_timer	<= 8'd0;
		end
		else if( ff_bus_ioreq ) begin
			ff_bus_timer	<= ff_bus_timer + 8'd1;
			if( ff_bus_valid && w_bus_ready ) begin
				ff_bus_valid	<= 1'b0;
			end

			if( !ff_bus_write && w_bus_rdata_en ) begin
				//	read data
				ff_bus_valid	<= 1'b0;
				ff_bus_ioreq	<= 1'b0;
				ff_done_rdata	<= w_bus_rdata;
				ff_done_toggle	<= ~ff_done_toggle;
			end
			else if( !ff_bus_write && ff_bus_timer == 8'hFF ) begin
				//	no answer (should not happen)
				ff_bus_valid	<= 1'b0;
				ff_bus_ioreq	<= 1'b0;
				ff_done_rdata	<= 8'hFF;
				ff_done_toggle	<= ~ff_done_toggle;
			end
			else if( ff_bus_write && !ff_bus_valid && ff_bus_timer >= c_write_hold ) begin
				ff_bus_ioreq	<= 1'b0;
				ff_done_toggle	<= ~ff_done_toggle;
			end
		end
	end

	// --------------------------------------------------------------------
	//	V9968
	// --------------------------------------------------------------------
	wire		[17:2]	w_vram_address;
	wire				w_vram_write;
	wire				w_vram_valid;
	wire		[31:0]	w_vram_wdata;
	wire		[3:0]	w_vram_wdata_mask;
	wire		[31:0]	w_vram_rdata;
	wire				w_vram_rdata_en;
	wire				w_vram_refresh;
	wire				w_int_n;

	wire		[11:0]	w_h_count;
	wire		[ 9:0]	w_v_count;
	wire		[13:0]	w_screen_pos_x;
	wire		[7:0]	w_pixel_r;
	wire		[7:0]	w_pixel_g;
	wire		[7:0]	w_pixel_b;
	wire		[7:0]	w_display_adjust;
	wire				w_50hz_mode;
	wire				w_field;
	wire				w_interlace_mode;

	v9968_core u_v9968 (
		.reset_n				( reset_n				),
		.clk					( clk					),
		.initial_busy			( w_initial_busy		),
		.bus_address			( ff_bus_address		),
		.bus_ioreq				( ff_bus_ioreq			),
		.bus_write				( ff_bus_write			),
		.bus_valid				( ff_bus_valid			),
		.bus_ready				( w_bus_ready			),
		.bus_wdata				( ff_bus_wdata			),
		.bus_rdata				( w_bus_rdata			),
		.bus_rdata_en			( w_bus_rdata_en		),
		.int_n					( w_int_n				),
		.vram_address			( w_vram_address		),
		.vram_write				( w_vram_write			),
		.vram_valid				( w_vram_valid			),
		.vram_wdata				( w_vram_wdata			),
		.vram_wdata_mask		( w_vram_wdata_mask		),
		.vram_rdata				( w_vram_rdata			),
		.vram_rdata_en			( w_vram_rdata_en		),
		.vram_refresh			( w_vram_refresh		),
		.pixel_h_count			( w_h_count				),
		.pixel_v_count			( w_v_count				),
		.pixel_screen_pos_x		( w_screen_pos_x		),
		.pixel_r				( w_pixel_r				),
		.pixel_g				( w_pixel_g				),
		.pixel_b				( w_pixel_b				),
		.pixel_display_adjust	( w_display_adjust		),
		.pixel_50hz_mode		( w_50hz_mode			),
		.pixel_field			( w_field				),
		.pixel_interlace_mode	( w_interlace_mode		),
		.force_highspeed		( vdpspeedmode			),
		.ext_cmd_wr				( 1'b0					),		//	geo3d not connected
		.ext_cmd_num			( 6'd0					),
		.ext_cmd_data			( 8'd0					),
		.ext_cmd_ce				(						),
		.button					( 2'b00					),
		.pulse0					(						),
		.pulse1					(						),
		.pulse2					(						),
		.pulse3					(						),
		.pulse4					(						),
		.pulse5					(						),
		.pulse6					(						),
		.pulse7					(						)
	);

	v9968_vram #(
		.VRAM_256K				( VRAM_256K				)
	) u_vram (
		.clk					( clk					),
		.bus_address			( w_vram_address		),
		.bus_valid				( w_vram_valid			),
		.bus_write				( w_vram_write			),
		.bus_refresh			( w_vram_refresh		),
		.bus_wdata				( w_vram_wdata			),
		.bus_wdata_mask			( w_vram_wdata_mask		),
		.bus_rdata				( w_vram_rdata			),
		.bus_rdata_en			( w_vram_rdata_en		)
	);

	//	Interrupt, synchronized to CLK21M
	reg			[1:0]	ff_int_sync = 2'b11;

	always @( posedge clk21m ) begin
		ff_int_sync	<= { ff_int_sync[0], w_int_n };
	end

	assign int_n = ff_int_sync[1];

	//	External VRAM port unused
	assign pramoe_n	= 1'b1;
	assign pramwe_n	= 1'b1;
	assign pramadr	= 17'd0;
	assign pramdbo	= 8'd0;

	// --------------------------------------------------------------------
	//	15KHz video
	//
	//	The upscan of the V9968 writes w_pixel_* at h_count[2:0] == 7 to the
	//	line buffer address screen_pos_x[13:3] + 32 - (R#18 adjust); here that
	//	address is the column of a 684 half pixel line, the pixel is output at
	//	once and HS / BLANK come from the column.  The line (v_count / 2)
	//	changes at column 636 - adjust, inside the hsync.
	// --------------------------------------------------------------------
	wire				w_tick;
	wire		[10:0]	w_column_raw;
	wire		[10:0]	w_column;
	wire		[ 8:0]	w_line;
	wire		[ 8:0]	w_v_start;
	wire		[ 8:0]	w_vs_start;
	wire				w_h_visible;
	wire				w_v_visible;
	reg					ff_hs = 1'b0;
	reg					ff_vs = 1'b0;
	reg					ff_blank = 1'b1;
	reg			[17:0]	ff_rgb = 18'd0;

	assign w_tick		= (w_h_count[2:0] == 3'd7);
	assign w_column_raw	= w_screen_pos_x[13:3] + 11'd32 - { 6'd0, ~w_display_adjust[3], w_display_adjust[2:0], 1'b0 };
	assign w_column		= w_column_raw[10] ? (w_column_raw + c_h_total) : w_column_raw;
	assign w_line		= w_v_count[9:1];
	assign w_v_start	= w_50hz_mode ? c_v_start_50  : c_v_start_60;
	assign w_vs_start	= w_50hz_mode ? c_vs_start_50 : c_vs_start_60;
	assign w_h_visible	= (w_column < c_h_visible);
	assign w_v_visible	= (w_line >= w_v_start) && (w_line < w_v_start + c_v_visible);

	always @( posedge clk ) begin
		if( w_tick ) begin
			if( w_column == c_hs_start ) begin
				ff_hs	<= 1'b1;
				//	VS for the line that starts in this hsync
				ff_vs	<= (w_line + 9'd1 >= w_vs_start) && (w_line + 9'd1 < w_vs_start + c_vs_lines);
			end
			else if( w_column == c_hs_end ) begin
				ff_hs	<= 1'b0;
			end

			ff_blank	<= ~(w_h_visible & w_v_visible);
			if( w_h_visible & w_v_visible ) begin
				ff_rgb	<= { w_pixel_r[7:2], w_pixel_g[7:2], w_pixel_b[7:2] };
			end
			else begin
				ff_rgb	<= 18'd0;
			end
		end
	end

	//	Into the CLK21M domain (CLK21M x 4 from the PLL, related clocks).
	reg			[17:0]	ff_video_rgb = 18'd0;
	reg					ff_video_hs_n = 1'b1;
	reg					ff_video_vs_n = 1'b1;
	reg					ff_video_cs_n = 1'b1;
	reg					ff_video_blank = 1'b1;

	always @( posedge clk21m ) begin
		ff_video_rgb	<= ff_rgb;
		ff_video_hs_n	<= ~ff_hs;
		ff_video_vs_n	<= ~ff_vs;
		ff_video_cs_n	<= ~(ff_hs ^ ff_vs);
		ff_video_blank	<= ff_blank;
	end

	assign pvideor		= ff_video_rgb[17:12];
	assign pvideog		= ff_video_rgb[11: 6];
	assign pvideob		= ff_video_rgb[ 5: 0];
	assign pvideohs_n	= ff_video_hs_n;
	assign pvideovs_n	= ff_video_vs_n;
	assign pvideocs_n	= ff_video_cs_n;
	assign blank_o		= ff_video_blank;
	// --------------------------------------------------------------------
	//	Field and interlace for the 31 kHz bob of zemmix.sv (ZEMMIX-f7c.2)
	// --------------------------------------------------------------------
	reg			[1:0]	ff_field_s = 2'd0;
	reg			[1:0]	ff_il_s = 2'd0;

	always @( posedge clk21m ) begin
		ff_field_s	<= { ff_field_s[0], w_field };
		ff_il_s		<= { ff_il_s[0], w_interlace_mode };
	end

	assign field_o		= ff_field_s[1];
	assign interlace_o	= ff_il_s[1];

endmodule
