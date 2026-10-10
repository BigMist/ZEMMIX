
`default_nettype none

module zemmix
(
	input         CLOCK_27,
`ifdef USE_CLOCK_50
   input         CLOCK_50,
`endif
	output        LED,
	output [VGA_BITS-1:0] VGA_R,
	output [VGA_BITS-1:0] VGA_G,
	output [VGA_BITS-1:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,

`ifdef USE_HDMI
	output        HDMI_RST,
	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_PCLK,
	output        HDMI_DE,
	inout         HDMI_SDA,
	inout         HDMI_SCL,
	input         HDMI_INT,
`endif

	input         SPI_SCK,
	inout         SPI_DO,
	input         SPI_DI,
	input         SPI_SS2,    // data_io
	input         SPI_SS3,    // OSD
	input         CONF_DATA0, // SPI_SS for user_io

`ifdef USE_QSPI
	input         QSCK,
	input         QCSn,
	inout   [3:0] QDAT,
`endif
`ifndef NO_DIRECT_UPLOAD
	input         SPI_SS4,
`endif

	output [12:0] SDRAM_A,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nWE,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nCS,
	output  [1:0] SDRAM_BA,
	output        SDRAM_CLK,
	output        SDRAM_CKE,

`ifdef DUAL_SDRAM
	output [12:0] SDRAM2_A,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_DQML,
	output        SDRAM2_DQMH,
	output        SDRAM2_nWE,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nCS,
	output  [1:0] SDRAM2_BA,
	output        SDRAM2_CLK,
	output        SDRAM2_CKE,
`endif

	output        AUDIO_L,
	output        AUDIO_R,
`ifdef I2S_AUDIO
	output        I2S_BCK,
	output        I2S_LRCK,
	output        I2S_DATA,
`endif
`ifdef I2S_AUDIO_HDMI
	output        HDMI_MCLK,
	output        HDMI_BCK,
	output        HDMI_LRCK,
	output        HDMI_SDATA,
`endif
`ifdef SPDIF_AUDIO
	output        SPDIF,
`endif
`ifdef USE_AUDIO_IN
	input         AUDIO_IN,
`endif

`ifdef PIN_REFLECTION
	output        joy_clk,
   input         joy_xclk,
	
   output        joy_load,
   input         joy_xload,
   
	input         joy_data,
   output        joy_xdata,	
`endif
	
`ifdef USE_EXTBUS	
	inout [23:0]  BUS_A = 24'b0,
	inout  [15:0]  BUS_D = 16'b0,
	inout         BUS_USER1,
	inout         BUS_USER2,
	inout         BUS_USER3,
	inout         BUS_USER5,
	inout         BUS_USER6,
	inout         BUS_USER7,
	inout         BUS_N41,
	inout         BUS_N42,
	inout         BUS_N43,
	inout         BUS_N44,
	inout         BUS_N45,
	inout         BUS_N46,
	inout         BUS_N47,
	inout         BUS_N48,
	inout         BUS_nRESET,
	inout         BUS_nM1,
	inout         BUS_nMREQ,
	inout         BUS_nIORQ,
	inout         BUS_nRD,
	inout         BUS_nWR,
	inout         BUS_nRFSH,
	inout         BUS_nHALT,
	inout         BUS_nBUSAK,
	inout reg     BUS_CLK,
	inout         BUS_nINT,
	inout         BUS_nWAIT,
	input         BUS_RX,
	output        BUS_TX,
`endif
   input         UART_RX,
	output        UART_TX
);

`ifdef NO_DIRECT_UPLOAD
localparam bit DIRECT_UPLOAD = 0;
wire SPI_SS4 = 1;
`else
localparam bit DIRECT_UPLOAD = 1;
`endif

`ifdef USE_QSPI
localparam bit QSPI = 1;
assign QDAT = 4'hZ;
`else
localparam bit QSPI = 0;
`endif

`ifdef VGA_8BIT
localparam VGA_BITS = 8;
`else
localparam VGA_BITS = 6;
`endif

`ifdef USE_HDMI
localparam bit HDMI = 1;
assign HDMI_RST = 1'b1;
`else
localparam bit HDMI = 0;
`endif

`ifdef BIG_OSD
localparam bit BIG_OSD = 1;
`define SEP "-;",
`else
localparam bit BIG_OSD = 0;
`define SEP
`endif

`include "build_id.v"

// 2nd SDRAM (SiDi128 only): the OPL4 wave memory and the V9990 VRAM, the
// controller is further down (sdram2, after the clocks)
// OPL4_SDRAM1 (NeptUNO+ dual): the OPL4 wave memory stays in the top 4 MB of the
// 1st SDRAM, the 2nd SDRAM keeps only the V9990 VRAM
`ifdef DUAL_SDRAM
`ifdef OPL4_SDRAM1
localparam SDRAM2 = "false";
`else
localparam SDRAM2 = "true";
`endif
`else
localparam SDRAM2 = "false";
`endif

// V9990 (GFX9000, ports 60h-6Fh): its 512 KB VRAM is in the 2nd SDRAM
`ifdef V9990
`ifndef DUAL_SDRAM
v9990_needs_DUAL_SDRAM v9990_needs_DUAL_SDRAM();   // no such module: build error
`endif
localparam V9990 = "true";
`define V99_OSD "ODE,HDMI screen,Auto,V9958,V9990;",
`else
localparam V9990 = "false";
`define V99_OSD
`endif

`ifdef USE_HDMI
wire        i2c_start;
wire        i2c_read;
wire  [6:0] i2c_addr;
wire  [7:0] i2c_subaddr;
wire  [7:0] i2c_dout;
wire  [7:0] i2c_din;
wire        i2c_ack;
wire        i2c_end;
`endif

`include "build_id.v"
localparam CONF_STR = {
	"ZEMMIX;;",
	"S0U,IMGVHD,Load virtual disk;",
	"P1,Configuration Switches;",
    "P1O1,CPU Clock,Standard,Turbo;",
    "P1O2,Scandoubler,VGA,RGB;",
	"P1O3,VGA Output,CRT,LCD;",
	"P1O4,Slot1,External (Optional S3),MegaSCC+ 2MB;",
    "P1O56,Slot2,External,MegaRAM 1MB/1MB,MegaSCC+ 2MB,MegaRAM 2MB/2MB;",
	"P1O7,RAM,2048kB,4096kB;",
	"P1O8,internal MegaSD,Off,on;",
    "O9,Tape sound,OFF,ON;",
    "OAB,Scanlines,Off,25%,50%,75%;",
    "OC,MoonSound (OPL3/OPL4),On,Off;",
   `V99_OSD
    "T0,Reset;",
	"V,v2.0.",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////
wire clk_sys;
wire memclk;
wire clk_hdmi;
wire clk_v99;
wire locked;

pll pll
(
`ifdef USE_CLOCK_50
   .inclk0(CLOCK_50),
`else
   .inclk0(CLOCK_27),
`endif	
	.c0(clk_sys),
	.c1(memclk),
`ifdef USE_HDMI
		.c2(clk_hdmi),
`endif
`ifdef V9990
	.c3(clk_v99),                                // 42.95 MHz, no phase shift: the V9990
`endif

	.locked(locked)
);

altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone 10 LP"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)


sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(memclk),
	.dataout(SDRAM_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);
//////////////////   2nd SDRAM (SiDi128)   ///////////////////
// OPL4 wave memory from emsx_top (opl4_wave_ext_g): byte address, 16-bit words
wire        wave_req_t, wave_we;
wire        wave_done_t;
wire [21:0] wave_adr;
wire  [7:0] wave_wdat;
wire [63:0] wave_rdat;                     // reads: lines of 4 words (sdram2 P0_LINE)

// The OPL4 wave memory (port 0) and the V9990 VRAM (port 1), misc/sdram2.sv:
// same timing as the SDRAM of emsx_top (memclk, the clock inverted).  Reset
// only by the PLL lock: the wave memory keeps ZEMMIX.ROM over the MSX resets.
`ifdef DUAL_SDRAM
altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone 10 LP"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdram2clk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(memclk),
	.dataout(SDRAM2_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);

wire        sdram2_ready;
// V9990 VRAM (misc/v9990_vram_sdram.sv, below): reads are lines of 4 words
wire        v99_s_req, v99_s_ack, v99_s_we;
wire  [1:0] v99_s_be;
wire [23:0] v99_s_addr;
wire [15:0] v99_s_din;
wire [63:0] v99_s_dout;

sdram2 #(.P0_LINE(1)) sdram2
(
	.clk        ( memclk          ),
	.reset      ( ~locked         ),
	.ready      ( sdram2_ready    ),

	// OPL4 wave memory
`ifdef OPL4_SDRAM1
	.p0_req     ( 1'b0            ),             // OPL4 in the 1st SDRAM
`else
	.p0_req     ( wave_req_t      ),
`endif
	.p0_ack     ( wave_done_t     ),
	.p0_we      ( wave_we         ),
	.p0_be      ( {wave_adr[0], ~wave_adr[0]} ),
	.p0_addr    ( {3'b000, wave_adr[21:1]} ),         // bank 0, 4 MB
	.p0_din     ( {wave_wdat, wave_wdat} ),
	.p0_dout    ( wave_rdat       ),

	// V9990 VRAM
	.p1_req     ( v99_s_req       ),
	.p1_ack     ( v99_s_ack       ),
	.p1_we      ( v99_s_we        ),
	.p1_be      ( v99_s_be        ),
	.p1_addr    ( v99_s_addr      ),
	.p1_din     ( v99_s_din       ),
	.p1_dout    ( v99_s_dout      ),

	.SDRAM_A    ( SDRAM2_A        ),
	.SDRAM_DQ   ( SDRAM2_DQ       ),
	.SDRAM_DQML ( SDRAM2_DQML     ),
	.SDRAM_DQMH ( SDRAM2_DQMH     ),
	.SDRAM_nWE  ( SDRAM2_nWE      ),
	.SDRAM_nCAS ( SDRAM2_nCAS     ),
	.SDRAM_nRAS ( SDRAM2_nRAS     ),
	.SDRAM_nCS  ( SDRAM2_nCS      ),
	.SDRAM_BA   ( SDRAM2_BA       ),
	.SDRAM_CKE  ( SDRAM2_CKE      )
);

`ifndef V9990
assign v99_s_req  = 1'b0;
assign v99_s_we   = 1'b0;
assign v99_s_be   = 2'b11;
assign v99_s_addr = 24'd0;
assign v99_s_din  = 16'd0;
`endif
`else
assign wave_done_t = 1'b0;
assign wave_rdat   = 64'hFFFFFFFFFFFFFFFF;
`endif

//////////////////   V9990 (GFX9000), SiDi128   ///////////////////
// v9990/rtl/v9990_core on clk_v99 (42.95 MHz), ports 60h-6Fh from emsx_top
// (misc/v9990_bus.vhd), its VRAM in bank 2 of the 2nd SDRAM (port 1 of sdram2)
// through a cache of 4-word lines (v9990/rtl/v9990_vram_cache.vhd,
// misc/v9990_vram_sdram.sv).  Video: to the mist_video chain (VIDEO, below).
wire        v99_reset_n, v99_req, v99_wrt, v99_ack, v99_int_n;
wire  [3:0] v99_adr;
wire  [7:0] v99_dbo, v99_dbi;
wire  [7:0] v99_red, v99_grn, v99_blu;
wire        v99_hsync_n, v99_vsync_n, v99_hblank, v99_vblank, v99_disp, v99_il;

`ifdef V9990
wire        v99_vram_req, v99_vram_we;
wire  [1:0] v99_vram_be;
wire [17:0] v99_vram_addr;
wire [15:0] v99_vram_wdata, v99_vram_rdata;
wire        v99_vram_ack;

wire        v99_m_req, v99_m_we, v99_m_ack;
wire  [1:0] v99_m_be;
wire [17:0] v99_m_addr;
wire [15:0] v99_m_wdata;
wire [63:0] v99_m_rdata;

// not reset with the V9990: an access cut short would get the ack of the
// next one (the VRAM changes only through it, the lines stay right)
v9990_vram_cache #(.LINES(4)) v9990_cache
(
	.clk     ( clk_v99        ),
	.reset_n ( 1'b1           ),
	.req     ( v99_vram_req   ),
	.we      ( v99_vram_we    ),
	.be      ( v99_vram_be    ),
	.addr    ( v99_vram_addr  ),
	.wdata   ( v99_vram_wdata ),
	.ack     ( v99_vram_ack   ),
	.rdata   ( v99_vram_rdata ),
	.m_req   ( v99_m_req      ),
	.m_we    ( v99_m_we       ),
	.m_be    ( v99_m_be       ),
	.m_addr  ( v99_m_addr     ),
	.m_wdata ( v99_m_wdata    ),
	.m_ack   ( v99_m_ack      ),
	.m_rdata ( v99_m_rdata    )
);

v9990_vram_sdram v9990_vram
(
	.clk    ( clk_v99        ),
	.req    ( v99_m_req      ),
	.we     ( v99_m_we       ),
	.be     ( v99_m_be       ),
	.addr   ( v99_m_addr     ),
	.wdata  ( v99_m_wdata    ),
	.ack    ( v99_m_ack      ),
	.rdata  ( v99_m_rdata    ),
	.s_req  ( v99_s_req      ),
	.s_ack  ( v99_s_ack      ),
	.s_we   ( v99_s_we       ),
	.s_be   ( v99_s_be       ),
	.s_addr ( v99_s_addr     ),
	.s_din  ( v99_s_din      ),
	.s_dout ( v99_s_dout     )
);

v9990_core v9990
(
	.clk          ( clk_v99         ),
	.reset_n      ( v99_reset_n     ),

	.req_i        ( v99_req         ),
	.wrt_i        ( v99_wrt         ),
	.adr_i        ( v99_adr         ),
	.dbo_i        ( v99_dbo         ),
	.ack_o        ( v99_ack         ),
	.dbi_o        ( v99_dbi         ),
	.int_n_o      ( v99_int_n       ),

	.vram_req_o   ( v99_vram_req    ),
	.vram_we_o    ( v99_vram_we     ),
	.vram_be_o    ( v99_vram_be     ),
	.vram_addr_o  ( v99_vram_addr   ),
	.vram_wdata_o ( v99_vram_wdata  ),
	.vram_ack_i   ( v99_vram_ack    ),
	.vram_rdata_i ( v99_vram_rdata  ),

	.red_o        ( v99_red         ),
	.grn_o        ( v99_grn         ),
	.blu_o        ( v99_blu         ),
	.hsync_n_o    ( v99_hsync_n     ),
	.vsync_n_o    ( v99_vsync_n     ),
	.hblank_o     ( v99_hblank      ),
	.vblank_o     ( v99_vblank      ),
	.interlace_o  ( v99_il          ),
	.disp_en_o    ( v99_disp        ),
	.vid_x_o      (                 ),
	.vid_y_o      (                 )
);
`else
assign v99_ack   = 1'b0;
assign v99_dbi   = 8'hFF;
assign v99_int_n = 1'b1;
`endif

//////////////////   RP2040 pin reflection   ///////////////////

`ifdef PIN_REFLECTION
assign joy_clk = joy_xclk;
assign joy_load = joy_xload;
assign joy_xdata = joy_data;
`endif


//////////////////   MIST ARM I/O   ///////////////////
wire  [7:0] joy_0;
wire  [7:0] joy_1;

wire  [1:0] buttons;
wire  [1:0] switches;
wire        scandoubler_disable;
wire        ypbpr;
wire        no_csync;
wire [63:0] status;

wire [31:0] sd_lba;
wire  sd_rd;
wire  sd_wr;

wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire [63:0] img_size;

wire        sd_ack_conf;
wire        sd_conf;
wire        sd_sdhc;

wire        key_strobe;
wire        key_pressed;
wire        key_extended;
wire  [7:0] key_code;

wire  [8:0] mouse_x;
wire  [8:0] mouse_y;
wire  [7:0] mouse_flags;
wire        mouse_strobe;

wire ps2k_c,ps2k_d,ps2k_c_i,ps2k_d_i;

user_io #(.STRLEN($size(CONF_STR)>>3), .PS2DIV(800), .FEATURES(32'h0 | (BIG_OSD << 13) | (HDMI << 14))) user_io
(
	.clk_sys(clk_sys),
	.clk_sd(clk_sys),
	.conf_str(CONF_STR),

	.SPI_CLK(SPI_SCK),
	.SPI_SS_IO(CONF_DATA0),
	.SPI_MOSI(SPI_DI),
	.SPI_MISO(SPI_DO),

`ifdef USE_HDMI
	.i2c_start      (i2c_start      ),
   .i2c_read       (i2c_read       ),
   .i2c_addr       (i2c_addr       ),
	.i2c_subaddr    (i2c_subaddr    ),
	.i2c_dout       (i2c_dout       ),
	.i2c_din        (i2c_din        ),
	.i2c_ack        (i2c_ack        ),
	.i2c_end        (i2c_end        ),
`endif

	.img_mounted(img_mounted),
	.img_size(img_size),
	.sd_conf(sd_conf),
	.sd_ack_conf(sd_ack_conf),
	.sd_sdhc(sd_sdhc),
	.sd_lba(sd_lba),
	.leds(8'd0),                          // keyboard LEDs to the firmware: not used
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_din(sd_buff_din),
	.sd_dout(sd_buff_dout),
	.sd_dout_strobe(sd_buff_wr),

	.key_strobe(key_strobe),
	.key_code(key_code),
	.key_pressed(key_pressed),
	.key_extended(key_extended),

	.ps2_kbd_clk(ps2k_c),
	.ps2_kbd_data(ps2k_d),
	.ps2_kbd_clk_i(msx_ps2_kbd_clk),
	.ps2_kbd_data_i(msx_ps2_kbd_data),

	.mouse_x(mouse_x),
	.mouse_y(mouse_y),
	.mouse_flags(mouse_flags),
	.mouse_strobe(mouse_strobe),

	.joystick_0(joy_0),
	.joystick_1(joy_1),


	.buttons(buttons),
	.status(status),
	.scandoubler_disable(scandoubler_disable),
	.ypbpr(ypbpr),
	.no_csync(no_csync)

);


wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_download;
wire  [5:0] ioctl_index;
wire  [1:0] ioctl_ext_index;

// ZEMMIX.ROM (YRW801) download, data_io index 0: the MSX in reset, the SDRAM for the loader
wire rom_dl = ioctl_download && {ioctl_ext_index, ioctl_index} == 8'd0;

data_io data_io
(
	.clk_sys(clk_sys),

	.SPI_SCK(SPI_SCK),
	.SPI_SS2(SPI_SS2),
	.SPI_DI(SPI_DI),
	.SPI_DO(SPI_DO),

	.clkref_n(1'b0),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_download(ioctl_download),
	.ioctl_index({ioctl_ext_index, ioctl_index})
);


sd_card sd_card (
	.clk_sys         ( clk_sys       ),   // at least 2xsd_sck
	// connection to io controller
	.sd_lba          ( sd_lba         ),
	.sd_rd           ( sd_rd          ),
	.sd_wr           ( sd_wr          ),
	.sd_ack          ( sd_ack         ),
	.sd_conf         ( sd_conf        ),
	.sd_ack_conf     ( sd_ack_conf    ),
	.sd_sdhc         ( sd_sdhc        ),
	.allow_sdhc      (1'b1            ),
	.sd_buff_dout    ( sd_buff_dout   ),
	.sd_buff_wr      ( sd_buff_wr     ),
	.sd_buff_din     ( sd_buff_din    ),
	.sd_buff_addr    ( sd_buff_addr   ),

   .img_mounted   (img_mounted),
	.img_size      (img_size),
	// connection to local CPU
	.sd_cs   		( Sd_Dt[3] ),
	.sd_sck  		( Sd_Ck    ),
	.sd_sdi  		( Sd_Cm    ),
	.sd_sdo  		( Sd_Dt[0] )
);

wire [5:0] joya = ~joy_0[5:0];
wire [5:0] joyb = ~joy_1[5:0];
wire [5:0] msx_joya;
wire [5:0] msx_joyb;
wire       msx_stra;
wire       msx_strb;

wire       Sd_Ck;
wire       Sd_Cm;
wire [3:0] Sd_Dt;

wire       msx_ps2_kbd_clk = (ps2k_c == 1'b0 ? ps2k_c : 1'bZ);
wire       msx_ps2_kbd_data = (ps2k_d == 1'b0 ? ps2k_d : 1'bZ);
reg  [7:0] dipsw;
wire [7:0] leds;

// Reset:
//  * power on: reset for a fixed 3.1 s after the PLL lock, as mist-devel/MSX_MiST
//    4d2e241 (cold boot with a black HDMI screen on the SiDi128: its IT6613 is set up
//    by the ARM over I2C after the power on); a PLL glitch starts it again
//  * OSD / button reset and img_mounted: 1.56 s as before (the OCM needs the long
//    reset to start again with the SD / image; a 98 ms one did not reset nor take
//    a newly mounted image)
//  * the ZEMMIX.ROM download (rom_dl) and the cartridge reset (BUS_nRESET)
reg  [25:0] pw_cnt = 26'h3FFFFFF;               // 2^26 / 21.48 MHz = 3.1 s
reg  [27:0] img_reset_cnt = 0;
reg reset = 1'b1;
`ifdef USE_EXTBUS	
wire resetW = ~locked | pw_cnt != 26'd0 | status[0] | buttons[1] | img_reset_cnt != 0 | !BUS_nRESET | rom_dl;
`else
wire resetW = ~locked | pw_cnt != 26'd0 | status[0] | buttons[1] | img_reset_cnt != 0 | rom_dl;
`endif

always @(posedge clk_sys) begin
	if (~locked)                pw_cnt <= 26'h3FFFFFF;
	else if (pw_cnt != 26'd0)   pw_cnt <= pw_cnt - 26'd1;
	if (img_reset_cnt != 0) img_reset_cnt <= img_reset_cnt - 1'd1;
	if (img_mounted | status[0]) img_reset_cnt <= 28'h2000000;
	reset <= resetW;
	dipsw <= {~status[8], ~status[7], ~status[6:5], ~status[4], ~status[3],1'b0 , ~status[1]};
end

always_comb begin
    for (integer i=0; i<=5; i++) begin
        msx_joya[i] <= mouse_en ? (mouse[i] ? 1'bZ : mouse[i]) : (~joya[i] & ~msx_stra ? joya[i] : 1'bZ);
        msx_joyb[i] <= (~joyb[i] & ~msx_strb ? joyb[i] : 1'bZ);
    end
end

reg        mouse_en = 0;
reg  [5:0] mouse;

always @(posedge clk_sys) begin

    reg        stra_d;
    reg  [8:0] mouse_x_latch;
    reg  [8:0] mouse_y_latch;
    reg  [1:0] mouse_state;
    reg [17:0] mouse_timeout;

    if (reset) begin
        mouse_en <= 0;
        mouse_state <= 0;
    end
    else if (mouse_strobe) mouse_en <= 1;
    else if (~&joya) mouse_en <= 0;

    if (mouse_strobe) begin
        mouse_x_latch <= ~mouse_x + 1'd1; //2nd complement of x
        mouse_y_latch <= mouse_y;
    end

    mouse[5:4] <= ~mouse_flags[1:0];
    if (mouse_en) begin
        if (mouse_timeout) begin
            mouse_timeout <= mouse_timeout - 1'd1;
            if (mouse_timeout == 1) mouse_state <= 0;
        end

        stra_d <= msx_stra;
        if (stra_d ^ msx_stra) begin
            mouse_timeout <= 18'd100000;
            mouse_state <= mouse_state + 1'd1;
            case (mouse_state)
            2'b00: mouse[3:0] <= {mouse_x_latch[5],mouse_x_latch[6],mouse_x_latch[7],mouse_x_latch[8]};
            2'b01: mouse[3:0] <= {mouse_x_latch[1],mouse_x_latch[2],mouse_x_latch[3],mouse_x_latch[4]};
            2'b10: mouse[3:0] <= {mouse_y_latch[5],mouse_y_latch[6],mouse_y_latch[7],mouse_y_latch[8]};
            2'b11:
            begin
                mouse[3:0] <= {mouse_y_latch[1],mouse_y_latch[2],mouse_y_latch[3],mouse_y_latch[4]};
                mouse_x_latch <= 0;
                mouse_y_latch <= 0;
            end
            endcase
        end
    end
end

wire        Cmt_Out;


wire  [5:0] R_O;
wire  [5:0] G_O;
wire  [5:0] B_O;
wire        HSync, VSync;
wire blank;

wire cpuClk;
localparam true = "true";
localparam false = "false";

// MoonSound: OPL3 of Greg Taylor (misc/opl3fpga) + OPL4 wave part, on CLOCK_50
`ifdef USE_CLOCK_50
localparam OPL3 = "true";
localparam OPL3_CLK = 50000000;
wire clk_opl = CLOCK_50;
`else
localparam OPL3 = "false";        // no MoonSound without CLOCK_50
localparam OPL3_CLK = 50000000;
wire clk_opl = 1'b0;
`endif

emsx_top #(
    .use_wifi_g(true),   // activar interfaz UNAPI
    .use_midi_g(true),   // activar interfaz midi
    .use_opl3_g(OPL3),         // OPL3 (MoonSound FM)
    .use_opl4_g(OPL3),         // OPL4 wave part (MoonSound) with the OPL3 of misc/opl3fpga
    .opl4_wave_ext_g(SDRAM2),  // OPL4 wave memory in the 2nd SDRAM instead of the top 4 MB of the SDRAM
    .use_v9990_g(V9990),       // V9990 (GFX9000), ports 60h-6Fh
    .use_dualpsg_g(false),// activar doble chip PSG
    .psg_ym_g(1),        // PSG: 0 = AY-3-8910, 1 = YM2149
    .opl3_clk_g(OPL3_CLK)
) emsx (

//      -- Clock, Reset ports
        .clk21m     (clk_sys),
        .memclk     (memclk),
        .clk_opl    (clk_opl),
        .pSltRst_n  (~reset),

//       -- MSX cartridge
`ifdef USE_EXTBUS	
        .pCpuClk         (BUS_CLK),
        .pSltAdr         (BUS_A[15:0]),
        .pSltDat         (BUS_D[7:0]),        
        .pSltMerq_n      (BUS_nMREQ),
        .pSltIorq_n      (BUS_nIORQ),
        .pSltRd_n        (BUS_nRD),
        .pSltWr_n        (BUS_nWR),
        .pSltRfsh_n      (BUS_nRFSH),
        .pSltWait_n      (BUS_nWAIT),
        .pSltInt_n       (BUS_nINT),
        .pSltM1_n        (BUS_nM1), 
        .pSltSltsl_n     (BUS_N43),
        .pSltSlts2_n     (BUS_N44),
        .pSltCs1_n       (BUS_USER1),
        .pSltCs2_n       (BUS_USER2),
        .pSltCs12_n      (BUS_USER3),
        .pSltSw1         (BUS_USER7),
        .pSltSw2		    (BUS_N42),
        .BusDir_o        (BUS_N41),
		  .pExtClk         (0),
 		  .pSltRsv5        (BUS_USER5),
        .pSltClk         (0),
        .pSltRsv16       (BUS_USER6),
`endif

//        -- SD-RAM ports
        .pMemAdr   ( SDRAM_A ),
        .pMemDat   ( SDRAM_DQ ),
        .pMemLdq   ( SDRAM_DQML ),
        .pMemUdq   ( SDRAM_DQMH ),
        .pMemWe_n  ( SDRAM_nWE ),
        .pMemCas_n ( SDRAM_nCAS ),
        .pMemRas_n ( SDRAM_nRAS ),
        .pMemCs_n  ( SDRAM_nCS ),
        .pMemBa0   ( SDRAM_BA[0] ),
        .pMemBa1   ( SDRAM_BA[1] ),
        .pMemCke   ( SDRAM_CKE ),

//        -- PS/2 keyboard ports
        .pPs2Clk   (msx_ps2_kbd_clk),
        .pPs2Dat   (msx_ps2_kbd_data),

//        -- Joystick ports (Port_A, Port_B)
        .pJoyA_in   ( {msx_joya[5:4], msx_joya[0], msx_joya[1], msx_joya[2], msx_joya[3]} ),
        .pStra      ( msx_stra ),
        .pJoyB_in   ( {msx_joyb[5:4], msx_joyb[0], msx_joyb[1], msx_joyb[2], msx_joyb[3]} ),
        .pStrb      ( msx_strb ),

//        -- SD/MMC slot ports
        .pSd_Ck     (Sd_Ck),
        .pSd_Cm     (Sd_Cm),
        .pSd_Dt     (Sd_Dt),

//        -- DIP switch, Lamp ports
        .pDip       (dipsw),
`ifdef USE_EXTBUS			  
        .pLed       (BUS_A[23:16]),
`endif		  
		  .pLedPwr    (),
		  .ear_i      (AUDIO_IN),

//        -- Video, Audio/CMT ports
        //.CmtIn      (rx),
        //.CmtOut     (Cmt_Out),
        .pDac_VR    (R_O),      // RGB_Red / Svideo_C
        .pDac_VG    (G_O),      // RGB_Grn / Svideo_Y
        .pDac_VB    (B_O),      // RGB_Blu / CompositeVideo
        .pVideoHS_n (HSync),    // HSync(RGB15K, VGA31K)
        .pVideoVS_n (VSync),    // VSync(RGB15K, VGA31K)
		  .blank_o    (blank),

		  .opl_on_i    (~status[12]),                                         // OSD: MoonSound on (Bloq Despl can turn it off)
		  .rom_dl_i    (rom_dl),                                              // ZEMMIX.ROM (YRW801) sent by the firmware
		  .rom_wr_i    (ioctl_wr),
		  .rom_dat_i   (ioctl_dout),
		  .wave_ext_req_t  (wave_req_t),
		  .wave_ext_done_t (wave_done_t),
		  .wave_ext_we     (wave_we),
		  .wave_ext_adr    (wave_adr),
		  .wave_ext_wdat   (wave_wdat),
		  .wave_ext_rdat   (wave_rdat),
		  .v99_clk         (clk_v99),
		  .v99_reset_n     (v99_reset_n),
		  .v99_req         (v99_req),
		  .v99_wrt         (v99_wrt),
		  .v99_adr         (v99_adr),
		  .v99_dbo         (v99_dbo),
		  .v99_ack         (v99_ack),
		  .v99_dbi         (v99_dbi),
		  .v99_int_n       (v99_int_n),
		  .opl3_l      (opl3_l),
		  .opl3_r      (opl3_r),
		  .opl4_l      (opl4_l),
		  .opl4_r      (opl4_r),
		  .opll_o      (opll_o),
		  .scc1_l      (scc1_l),
		  .scc1_r      (scc1_r),
		  .scc2_l      (scc2_l),
		  .scc2_r      (scc2_r),
		  .TrPcm_o     (TrPcm_o),
		  .psg_o       (psg_o),
		  .vol_o       (vol_o),
		  .PsgVol_o    (psg_vol),
		  .SccVol_o    (scc_vol),
		  .OpllVol_o   (opll_vol),

`ifdef SWAP_PORTS
		  // swapped ports
		  .esp_rx_o    (UART_TX),
        .esp_tx_i    (UART_RX),
   `ifdef USE_EXTBUS			  
		  .midi_o      (BUS_RX),
		  .midi_i      (BUS_TX),
   `endif
`else
        //proper port location
   `ifdef USE_EXTBUS			  
		  .esp_rx_o    (BUS_TX),
        .esp_tx_i    (BUS_RX),
   `endif
		  .midi_o      (UART_TX),
		  .midi_i      (UART_RX)
`endif

);


////////////////////   AUDIO   ///////////////////


reg signed [15:0] opll_o;
reg signed [15:0] opl3_l;
reg signed [15:0] opl3_r;
wire        [15:0] opl4_l, opl4_r;
reg signed [14:0] scc1_r;
reg signed [14:0] scc1_l;
reg signed [14:0] scc2_r;
reg signed [14:0] scc2_l;
reg signed [7:0] TrPcm_o;
reg [15:0] psg_o;

wire [2:0] vol_o, psg_vol, scc_vol, opll_vol;

`ifdef USE_AUDIO_IN
wire tape_in = AUDIO_IN;
`else
wire tape_in = 1'b0;
`endif

wire signed [15:0] i2saudio_r,i2saudio_l;
wire        [15:0] dacaudio_l,dacaudio_r;

// mixer: sign extension, headroom and saturation, DC removal of the PSG / tape,
// OCM volumes per source and master volume (misc/audio_mix.sv)
audio_mix audio_mix
(
 .clk      (clk_sys),
 .reset    (reset),
 .opl3_l   (opl3_l),
 .opl3_r   (opl3_r),
 .opl4_l   (opl4_l),
 .opl4_r   (opl4_r),
 .opll     (opll_o),
 .scc1_l   (scc1_l),
 .scc1_r   (scc1_r),
 .scc2_l   (scc2_l),
 .scc2_r   (scc2_r),
 .psg      (psg_o),
 .pcm      (TrPcm_o),
 .tape_en  (status[9]),
 .tape_in  (tape_in),
 .psg_vol  (psg_vol),
 .scc_vol  (scc_vol),
 .opll_vol (opll_vol),
 .mstr_vol (vol_o),
 .out_l    (i2saudio_l),
 .out_r    (i2saudio_r),
 .dac_l    (dacaudio_l),
 .dac_r    (dacaudio_r)
);

`ifdef I2S_AUDIO


wire [31:0] clk_rate =  32'd21_480_000;
i2s i2s (
        .reset      (reset),
        .clk        (clk_sys),
        .clk_rate   (clk_rate),

        .sclk       (I2S_BCK),
        .lrclk      (I2S_LRCK),
        .sdata      (I2S_DATA),

        .left_chan  (i2saudio_l),
        .right_chan (i2saudio_r)       
);

`ifdef I2S_AUDIO_HDMI
assign HDMI_MCLK = 0;
always @(posedge clk_sys) begin
	HDMI_BCK <= I2S_BCK;
	HDMI_LRCK <= I2S_LRCK;
	HDMI_SDATA <= I2S_DATA;
end
`endif
`endif

`ifdef SPDIF_AUDIO
spdif spdif (
	.rst_i(1'b0),
	.clk_i(clk_sys),
	.clk_rate_i(clk_rate),
	.spdif_o(SPDIF),
	.sample_i({i2saudio_l,i2saudio_r})
);
`endif

 
dac #(
   .c_bits      (16))
audiodac_l(
   .clk_i       (clk_sys ),
   .res_n_i     (1      ),
   .dac_i       (dacaudio_l),
   .dac_o       (AUDIO_L)
  );

dac #(
   .c_bits      (16))
audiodac_r(
   .clk_i       (clk_sys ),
   .res_n_i     (1      ),
   .dac_i       (dacaudio_r),
   .dac_o       (AUDIO_R)
  );


//////////////////   VIDEO   //////////////////

// Source: the V9958 of emsx_top or the V9990 (OSD, V9990 builds).  Auto: the
// V9990 while its display is on (R#8 DISP), else the V9958.  With HDMI the
// main screen goes to HDMI and the other one to VGA (switch, not mirror).  Both give 15 kHz
// lines of 1368 clk_sys; clk_v99 is clk_sys x2 from the same PLL and in phase,
// so the V9990 outputs are just registered on clk_sys.  Sampled at clk_sys/2
// (ce_divider 1): exact for P1, P2, B0, B1 and B3, B2 / B4 / B7 lose pixels.
wire  [5:0] vid_r, vid_g, vid_b;                // main screen (HDMI, or VGA without HDMI)
wire        vid_hs, vid_vs, vid_blank;
wire  [5:0] vga_r, vga_g, vga_b;                // VGA
wire        vga_hs, vga_vs;
wire        vid_byp, vga_byp;                   // 31 kHz already (V9990 interlace): no scandoubler

`ifdef V9990
reg   [5:0] v99_r, v99_g, v99_b;
reg         v99_hs, v99_vs, v99_blank, v99_on, v99_ils, v99_wv, v99_fld;

// the field: EO of the V9990 (v9990_cpu), 0 after its reset and flipped at
// every frame start, when its vsync begins
always @(posedge clk_sys) begin
	v99_r     <= v99_red[7:2];
	v99_g     <= v99_grn[7:2];
	v99_b     <= v99_blu[7:2];
	v99_hs    <= v99_hsync_n;
	v99_vs    <= v99_vsync_n;
	v99_blank <= v99_hblank | v99_vblank;
	v99_on    <= v99_disp;
	v99_ils   <= v99_il;
	if (v99_vs & ~v99_vsync_n) begin
		v99_fld <= ~v99_fld;
		v99_wv  <= v99_ils;                     // interlace from a frame start
	end
	if (~v99_reset_n) v99_fld <= 1'b0;
end

// Interlace at 31 kHz: the odd field one line lower, as on a TV (misc/v99_bob.sv)
wire  [5:0] wv_r, wv_g, wv_b;
wire        wv_hs, wv_vs, wv_blank;

v99_bob v99_bob
(
	.clk       ( clk_sys    ),
	.field     ( v99_fld    ),
	.r_in      ( v99_r      ),
	.g_in      ( v99_g      ),
	.b_in      ( v99_b      ),
	.hs_n_in   ( v99_hs     ),
	.vs_n_in   ( v99_vs     ),
	.blank_in  ( v99_blank  ),
	.r_out     ( wv_r       ),
	.g_out     ( wv_g       ),
	.b_out     ( wv_b       ),
	.hs_n_out  ( wv_hs      ),
	.vs_n_out  ( wv_vs      ),
	.blank_out ( wv_blank   )
);

wire vid_v99 = status[14:13] == 2'd2 || (status[14:13] == 2'd0 && v99_on);
assign vid_byp = vid_v99 & v99_wv;              // HDMI: always 31 kHz

assign vid_r     = ~vid_v99 ? R_O   : vid_byp ? wv_r     : v99_r;
assign vid_g     = ~vid_v99 ? G_O   : vid_byp ? wv_g     : v99_g;
assign vid_b     = ~vid_v99 ? B_O   : vid_byp ? wv_b     : v99_b;
assign vid_hs    = ~vid_v99 ? HSync : vid_byp ? wv_hs    : v99_hs;
assign vid_vs    = ~vid_v99 ? VSync : vid_byp ? wv_vs    : v99_vs;
assign vid_blank = ~vid_v99 ? blank : vid_byp ? wv_blank : v99_blank;

`ifdef USE_HDMI
wire vga_v99 = ~vid_v99;                        // VGA: the other screen
`else
wire vga_v99 = vid_v99;
`endif
assign vga_byp = vga_v99 & v99_wv & ~scandoubler_disable;    // not with 15 kHz RGB

assign vga_r     = ~vga_v99 ? R_O   : vga_byp ? wv_r  : v99_r;
assign vga_g     = ~vga_v99 ? G_O   : vga_byp ? wv_g  : v99_g;
assign vga_b     = ~vga_v99 ? B_O   : vga_byp ? wv_b  : v99_b;
assign vga_hs    = ~vga_v99 ? HSync : vga_byp ? wv_hs : v99_hs;
assign vga_vs    = ~vga_v99 ? VSync : vga_byp ? wv_vs : v99_vs;
`else
assign vid_byp   = 1'b0;
assign vga_byp   = 1'b0;
assign vid_r     = R_O;
assign vid_g     = G_O;
assign vid_b     = B_O;
assign vid_hs    = HSync;
assign vid_vs    = VSync;
assign vid_blank = blank;
assign vga_r     = R_O;
assign vga_g     = G_O;
assign vga_b     = B_O;
assign vga_hs    = HSync;
assign vga_vs    = VSync;
`endif

wire isVGA = status[2];

mist_video #(
    .COLOR_DEPTH(6),
	 .SD_HCNT_WIDTH(11),
	 .OUT_COLOR_DEPTH(VGA_BITS),
	 .USE_BLANKS(0),
	 .BIG_OSD(BIG_OSD)
) 
mist_video 
(	
	.clk_sys      (clk_sys    ),
	.SPI_SCK      (SPI_SCK    ),
	.SPI_SS3      (SPI_SS3    ),
	.SPI_DI       (SPI_DI     ),
	.R            (vga_r ),
	.G            (vga_g ),
	.B            (vga_b ),
	.HSync        (vga_hs),
	.VSync        (vga_vs),
	.VGA_R        (VGA_R      ),
	.VGA_G        (VGA_G      ),
	.VGA_B        (VGA_B      ),
	.VGA_VS       (VGA_VS     ),
	.VGA_HS       (VGA_HS     ),
	.ce_divider   (3'd1       ),                 // F18A: pixels at clk_sys/2 (684 per line)
	.scandoubler_disable(scandoubler_disable | vga_byp),   // F18A: 15kHz from the VDP, MiST doubles
	.no_csync     (1'b1),
	.scanlines    (status[11:10]),
	.ypbpr        (1'b0      )
	);

`ifdef USE_HDMI
i2c_master #(22_000_000) i2c_master (
	.CLK         (clk_sys),
	.I2C_START   (i2c_start),
	.I2C_READ    (i2c_read),
	.I2C_ADDR    (i2c_addr),
	.I2C_SUBADDR (i2c_subaddr),
	.I2C_WDATA   (i2c_dout),
	.I2C_RDATA   (i2c_din),
	.I2C_END     (i2c_end),
	.I2C_ACK     (i2c_ack),

	//I2C bus
	.I2C_SCL     (HDMI_SCL),
	.I2C_SDA     (HDMI_SDA)
);	



mist_video #(
	.COLOR_DEPTH(6),
	.SD_HCNT_WIDTH(10),
	.OUT_COLOR_DEPTH(8),
	.USE_BLANKS(1),                              // F18A: DE from the blank (HBlank)
	.OSD_COLOR(3'b001),
	.BIG_OSD(BIG_OSD),
	.VIDEO_CLEANER(1)
)

hdmi_video (
	.clk_sys     ( clk_sys    ),

	// OSD SPI interface
	.SPI_SCK     ( SPI_SCK    ),
	.SPI_SS3     ( SPI_SS3    ),
	.SPI_DI      ( SPI_DI     ),
	.scanlines   (status[11:10]),
	.ce_divider  ( 3'd1       ),                 // F18A: pixels at clk_sys/2 (684 per line)
	.scandoubler_disable (vid_byp),              // F18A: HDMI always doubled (31 kHz V9990 interlace: as is)
	.no_csync    ( 1'b1       ),
	.ypbpr       ( 1'b0       ),
	.rotate      ( 2'b00      ),
	.blend       ( 1'b0       ),
	.R           (vid_r),
	.G           (vid_g),
	.B           (vid_b),
	.HBlank      ( vid_blank   ),                // F18A: H+V blank, held high on vblank lines
	.VBlank      ( ~vid_vs     ),                // F18A: frame start for the OSD (vertical sync, active high)
	.HSync       ( vid_hs      ),
	.VSync       ( vid_vs      ),
	.VGA_R       ( HDMI_R      ),
	.VGA_G       ( HDMI_G      ),
	.VGA_B       ( HDMI_B      ),
	.VGA_VS      ( HDMI_VS     ),
	.VGA_HS      ( HDMI_HS     ),
	.VGA_DE      ( HDMI_DE     )
);
assign HDMI_PCLK = clk_hdmi;

`endif	
endmodule
