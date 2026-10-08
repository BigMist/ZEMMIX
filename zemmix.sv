
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

// remove this if the 2nd chip is actually used
`ifdef DUAL_SDRAM
assign SDRAM2_A = 13'hZZZZ;
assign SDRAM2_BA = 0;
assign SDRAM2_DQML = 0;
assign SDRAM2_DQMH = 0;
assign SDRAM2_CKE = 0;
assign SDRAM2_CLK = 0;
assign SDRAM2_nCS = 1;
assign SDRAM2_DQ = 16'hZZZZ;
assign SDRAM2_nCAS = 1;
assign SDRAM2_nRAS = 1;
assign SDRAM2_nWE = 1;
`endif

`include "build_id.v"

// remove this if the 2nd chip is actually used
`ifdef DUAL_SDRAM
assign SDRAM2_A = 13'hZZZZ;
assign SDRAM2_BA = 0;
assign SDRAM2_DQML = 0;
assign SDRAM2_DQMH = 0;
assign SDRAM2_CKE = 0;
assign SDRAM2_CLK = 0;
assign SDRAM2_nCS = 1;
assign SDRAM2_DQ = 16'hZZZZ;
assign SDRAM2_nCAS = 1;
assign SDRAM2_nRAS = 1;
assign SDRAM2_nWE = 1;
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
   "T0,Reset;",
	"V,v1.0.",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////
wire clk_sys;
wire memclk;
wire clk_hdmi;
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

reg reset;
reg  [27:0] img_reset_cnt = 0;
`ifdef USE_EXTBUS	
wire resetW = status[0] | buttons[1] | img_reset_cnt != 0 | !locked | !BUS_nRESET;
`else
wire resetW = status[0] | buttons[1] | img_reset_cnt != 0 | !locked;
`endif

always @(posedge clk_sys) begin
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

// OPL3 clock: 50MHz as the OPL3 was designed for, memclk without CLOCK_50
`ifdef USE_CLOCK_50
localparam OPL3_FPGA = "true";   // OPL3 of Greg Taylor (misc/opl3fpga), needs 50MHz
localparam OPL3_CLK = 50000000;
wire clk_opl = CLOCK_50;
`else
localparam OPL3_FPGA = "false";  // opl3sw (misc/opl3) on memclk
localparam OPL3_CLK = 86000000;
wire clk_opl = memclk;
`endif

emsx_top #(
    .use_wifi_g(true),   // activar interfaz UNAPI
    .use_midi_g(true),   // activar interfaz midi
    .use_opl3_g(true),  // false. cambiar a true para activar OPL3
    .opl3_fpga_g(OPL3_FPGA),
    .use_opl4_g(OPL3_FPGA),    // OPL4 wave part (MoonSound) with the OPL3 of misc/opl3fpga
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
		  .rom_dl_i    (ioctl_download && {ioctl_ext_index, ioctl_index} == 8'd0),   // ZEMMIX.ROM (YRW801) sent by the firmware
		  .rom_wr_i    (ioctl_wr),
		  .rom_dat_i   (ioctl_dout),
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
	.R            (R_O ),
	.G            (G_O ),
	.B            (B_O ),
	.HSync        (HSync),
	.VSync        (VSync),
	.VGA_R        (VGA_R      ),
	.VGA_G        (VGA_G      ),
	.VGA_B        (VGA_B      ),
	.VGA_VS       (VGA_VS     ),
	.VGA_HS       (VGA_HS     ),
	.ce_divider   (3'd1       ),                 // F18A: pixels at clk_sys/2 (684 per line)
	.scandoubler_disable(scandoubler_disable),   // F18A: 15kHz from the VDP, MiST doubles
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
	.scandoubler_disable (1'b0),                 // F18A: HDMI always doubled
	.no_csync    ( 1'b1       ),
	.ypbpr       ( 1'b0       ),
	.rotate      ( 2'b00      ),
	.blend       ( 1'b0       ),
	.R           (R_O),
	.G           (G_O),
	.B           (B_O),
	.HBlank      ( blank       ),                // F18A: H+V blank, held high on vblank lines
	.VBlank      ( ~VSync      ),                // F18A: frame start for the OSD (vertical sync, active high)
	.HSync       ( HSync       ),
	.VSync       ( VSync       ),
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
