//
// opl4_wave.sv
//   OPL4 (YMF278B) wave part of the ZEMMIX MoonSound (ZEMMIX-0au.3 / .6): srg320's PCM
//   engine (YMF278B.sv) on clk_eng (CLOCK_50) with a fractional CE of 33.8688 MHz on
//   average, between the MSX bus (clk_bus = clk21m) and the wave memory port of the
//   SDRAM (also clk_bus). The FM part is the OPL3 of misc/opl3fpga, outside.
//
//   * bus: every access to C4h-C7h (A = 0-3) and 7Eh-7Fh (A = 4-5) goes to the engine,
//     which follows NEW2 from the FM writes (bank 1 reg 05h) and clears LD2 when C4h
//     is read. The engine samples its bus on CE only, and the CE stops while it waits
//     for the wave memory: the accesses are taken at 50 MHz into a queue and played to
//     the engine with strobes of a few CE, one after the other, each one when the
//     engine is not BUSY (as a cpu that polls the status), so none is lost.
//   * reads of 7Fh: the queue gives the REG_Q of the engine back (toggle), and the IN
//     gets the data of its own read (counts of reads started / answered). bus_wait_n
//     is low until then, straight from the bus signals (RD_MAX at most); a Z80 at
//     3.58 MHz that does not wait samples about 700 ns after RD.
//     bus_status {LD, BUSY} (BUSY also while the queue is not empty) is given for 7Eh
//     and to be ORed into the C4h status.
//   * memory: the engine asks for a byte when a window starts and samples it at the
//     next CYCLE1_CE, about 7 CE later, with no wait. The request crosses to clk_bus
//     (toggle) and that CE is held while the data is not back: the fractional
//     accumulator keeps its credit and catches up after (the average sample rate does
//     not move). A one-word cache serves the other byte of the last 16-bit word.
//     Writes to 000000h-1FFFFFh (the YRW801 ROM) are ignored, as on the MoonSound.
//   * audio: OUT2 of the engine (PCM with the F9h mix attenuation), held every 64
//     clk_eng and copied to clk_bus with a toggle.
//
module opl4_wave
#(
    parameter          CE_INC  = 24'd10584,     // 33.8688 MHz / 50 MHz = 10584 / 15625
    parameter          CE_MOD  = 24'd15625,
    parameter          RD_MAX  = 7'd100         // longest wait of an IN 7Fh in clk_bus cycles (4.7 us)
)
(
    input  wire        clk_bus,
    input  wire        reset_bus,               // MSX reset (active high)

    // MSX bus (clk_bus, registered signals of the OCM)
    input  wire        bus_cs,                  // I/O C4h-C7h or 7Eh-7Fh, MoonSound enabled
    input  wire  [2:0] bus_a,                   // C4h-C7h -> 0-3, 7Eh-7Fh -> 4-5
    input  wire  [7:0] bus_di,
    input  wire        bus_rd_n,
    input  wire        bus_wr_n,
    output reg   [7:0] bus_do,                  // read data of 7Eh / 7Fh
    output reg   [1:0] bus_status,              // {LD, BUSY}
    output wire        bus_wait_n,

    // wave memory port (clk_bus)
    output reg         mem_req_t,
    input  wire        mem_done_t,
    output reg         mem_we,
    output reg  [21:0] mem_adr,
    output reg   [7:0] mem_wdat,
    input  wire [15:0] mem_rdat,

    // audio (clk_bus)
    output reg  signed [15:0] pcm_l,
    output reg  signed [15:0] pcm_r,

    input  wire        clk_eng
);

initial begin
    bus_do = 8'hFF; bus_status = 2'b00;
    mem_req_t = 0; mem_we = 0; mem_adr = 0; mem_wdat = 0;
    pcm_l = 0; pcm_r = 0;
end

//------------------------------------------------------------------ engine reset / bus sync (clk_eng)
reg  [1:0] rst_s = 2'b00;
always @(posedge clk_eng) rst_s <= {rst_s[0], ~reset_bus};
wire eng_rst_n = rst_s[1];

reg  [1:0] cs_s = 0, rd_s = 2'b11, wr_s = 2'b11;
reg  [2:0] a_s0 = 0, a_s = 0;
reg  [7:0] di_s0 = 0, di_s = 0;
always @(posedge clk_eng) begin
    cs_s  <= {cs_s[0], bus_cs};
    rd_s  <= {rd_s[0], bus_rd_n};
    wr_s  <= {wr_s[0], bus_wr_n};
    a_s0  <= bus_a;  a_s  <= a_s0;              // stable when the strobes are seen
    di_s0 <= bus_di; di_s <= di_s0;
end

//------------------------------------------------------------------ fractional CE with hold
wire        cycle1_next;
reg         pend = 0;                           // a memory access of the engine is in flight
reg  [23:0] acc = 0;
wire        ce = (acc >= CE_MOD) && !(cycle1_next && pend);
always @(posedge clk_eng) begin
    if (ce)                     acc <= acc + CE_INC - CE_MOD;
    else if (acc < 24'hF00000)  acc <= acc + CE_INC;            // credit while held
end

//------------------------------------------------------------------ queue of bus accesses (clk_eng)
wire        rdx = cs_s[1] & ~rd_s[1];
wire        wrx = cs_s[1] & ~wr_s[1];
reg         rdx_d = 0, wrx_d = 0;
reg  [11:0] q [0:7];                            // {read, A, DI}
reg   [2:0] q_wp = 0, q_rp = 0;
wire        q_empty = (q_wp == q_rp);
always @(posedge clk_eng) begin
    rdx_d <= rdx;
    wrx_d <= wrx;
    if (wrx && !wrx_d) begin
        q[q_wp] <= {1'b0, a_s, di_s};
        q_wp    <= q_wp + 1'd1;
    end
    else if (rdx && !rdx_d) begin
        q[q_wp] <= {1'b1, a_s, 8'h00};
        q_wp    <= q_wp + 1'd1;
    end
end

// player: CS, then the strobe low for 2 CE and high again, the next one 12 CE later
// and when the engine is not BUSY. A read of A = 5 takes REG_Q 5 CE after its strobe.
wire  [7:0] eng_do;
wire  [1:0] eng_status;
reg         drv = 0;
reg   [3:0] ph = 0;
reg         drv_rd = 0, drv_cs = 0, drv_rd_n = 1, drv_wr_n = 1;
reg   [2:0] drv_a = 0;
reg   [7:0] drv_di = 0;
reg         rd_done_t = 0;                      // to clk_bus, rd_q stable then
reg   [7:0] rd_q = 8'hFF;
always @(posedge clk_eng) begin
    if (!drv) begin
        if (!q_empty && !eng_status[0]) begin
            {drv_rd, drv_a, drv_di} <= q[q_rp];
            q_rp   <= q_rp + 1'd1;
            drv    <= 1;
            drv_cs <= 1;
            ph     <= 0;
        end
    end
    else if (ce) begin
        ph <= ph + 1'd1;
        case (ph)
            4'd0:  if (drv_rd) drv_rd_n <= 0; else drv_wr_n <= 0;
            4'd2:  begin drv_rd_n <= 1; drv_wr_n <= 1; end
            4'd7:  if (drv_rd && drv_a == 3'd5) begin
                       rd_q      <= eng_do;
                       rd_done_t <= ~rd_done_t;
                   end
            4'd11: begin drv_cs <= 0; drv <= 0; end
            default: ;
        endcase
    end
end

//------------------------------------------------------------------ engine
wire  [7:0] eng_mdo;
wire [20:0] eng_ma;
wire        eng_mrd_n, eng_mwr_n;
wire  [9:0] eng_mcs_n;
reg   [7:0] eng_mdi = 8'hFF;
wire [15:0] out0_l, out0_r, out1_l, out1_r, out2_l, out2_r;

YMF278B ymf
(
    .CLK        (clk_eng),
    .RST_N      (eng_rst_n),
    .EN         (1'b1),
    .CE         (ce),
    .A          (drv_a),
    .DI         (drv_di),
    .DO         (eng_do),
    .RD_N       (drv_rd_n),
    .WR_N       (drv_wr_n),
    .CS_N       (~drv_cs),
    .IC_N       (eng_rst_n),
    .IRQ_N      (),
    .MA         (eng_ma),
    .MDI        (eng_mdi),
    .MDO        (eng_mdo),
    .MRD_N      (eng_mrd_n),
    .MWR_N      (eng_mwr_n),
    .MCS_N      (eng_mcs_n),
    .OUT0_L     (out0_l),
    .OUT0_R     (out0_r),
    .OUT1_L     (out1_l),
    .OUT1_R     (out1_r),
    .OUT2_L     (out2_l),
    .OUT2_R     (out2_r),
    .SND_EN     (3'b111),
    .MONO       (1'b0),
    .CYCLE1_NEXT(cycle1_next),
    .STATUS     (eng_status)
);

//------------------------------------------------------------------ bus side: reads of 7Fh, status (clk_bus)
wire       rd7f = bus_cs && !bus_rd_n && bus_a == 3'd5;
reg        rd7f_d = 0;
reg  [2:0] rd_iss = 0, rd_cmp = 0;              // reads of 7Fh started / answered (mod 8)
reg  [6:0] rd_cnt = 0;
reg  [2:0] rdd_s = 0;
wire       rd_back = rdd_s[2] != rdd_s[1];      // an answer
wire       rd_ready = (rd7f_d && rd_cmp == rd_iss) || rd_cnt >= RD_MAX;
reg  [1:0] st_s0 = 2'b00;
reg  [1:0] qb_s = 2'b00;                        // queue busy
always @(posedge clk_bus) begin
    rdd_s  <= {rdd_s[1:0], rd_done_t};
    rd7f_d <= rd7f;
    if (rd7f && !rd7f_d) rd_iss <= rd_iss + 1'd1;
    if (rd_back)         rd_cmp <= rd_cmp + 1'd1;
    if (!rd7f)           rd_cnt <= 0;
    else if (!rd_ready)  rd_cnt <= rd_cnt + 1'd1;

    st_s0 <= eng_status;
    qb_s  <= {qb_s[0], drv | !q_empty};
    bus_status <= {st_s0[1], st_s0[0] | qb_s[1]};

    if (rd7f) begin
        if (rd_back && rd_cmp + 1'd1 == rd_iss) bus_do <= rd_q;   // the answer of this IN
    end
    else if (bus_rd_n) bus_do <= {6'b000000, bus_status};      // 7Eh: status (held during an IN)
end
assign bus_wait_n = ~(rd7f && !rd_ready);

//------------------------------------------------------------------ wave memory, clk_eng side
wire [21:0] eng_adr  = {~eng_mcs_n[1], eng_ma};    // MCS_N[1] is low when A21 = 1
wire        eng_mreq = ~eng_mrd_n | ~eng_mwr_n;
reg         eng_mreq_d = 0;

reg  [20:0] c_tag = 0;                          // one-word cache
reg  [15:0] c_dat = 0;
reg         c_ok = 0;

reg         e_req_t = 0;                        // request toggle to clk_bus, payload below
reg         e_we = 0;
reg  [21:0] e_adr = 0;
reg   [7:0] e_wdat = 0;
reg         b_done_t = 0;                       // done toggle from clk_bus (b_rdat stable then)
reg  [15:0] b_rdat = 0;
reg   [2:0] done_s = 0;

always @(posedge clk_eng) begin
    eng_mreq_d <= eng_mreq;
    done_s     <= {done_s[1:0], b_done_t};

    if (!eng_rst_n) c_ok <= 0;

    if (pend) begin
        if (done_s[2] == e_req_t) begin         // the access is back
            pend <= 0;
            if (!e_we) begin
                c_tag   <= e_adr[21:1];
                c_dat   <= b_rdat;
                c_ok    <= eng_rst_n;
                eng_mdi <= e_adr[0] ? b_rdat[15:8] : b_rdat[7:0];
            end
        end
    end
    else if (eng_mreq && !eng_mreq_d) begin     // a new access of the engine
        if (!eng_mwr_n) begin
            eng_mdi <= eng_mdo;                 // the engine takes MDI back on a write
            if (eng_adr[21]) begin              // RAM: write it (and the cache), ROM: ignore it
                if (c_ok && c_tag == eng_adr[21:1]) begin
                    if (eng_adr[0]) c_dat[15:8] <= eng_mdo; else c_dat[7:0] <= eng_mdo;
                end
                e_we    <= 1;
                e_adr   <= eng_adr;
                e_wdat  <= eng_mdo;
                e_req_t <= ~e_req_t;
                pend    <= 1;
            end
        end
        else if (c_ok && c_tag == eng_adr[21:1]) begin
            eng_mdi <= eng_adr[0] ? c_dat[15:8] : c_dat[7:0];
        end
        else begin
            e_we    <= 0;
            e_adr   <= eng_adr;
            e_req_t <= ~e_req_t;
            pend    <= 1;
        end
    end
end

//------------------------------------------------------------------ wave memory, clk_bus side
reg  [2:0] req_s = 0;
reg        b_busy = 0;
reg        mem_done_d = 0;
always @(posedge clk_bus) begin
    req_s      <= {req_s[1:0], e_req_t};
    mem_done_d <= mem_done_t;
    if (!b_busy) begin
        if (req_s[2] != b_done_t) begin         // a new request (payload stable for 2 clocks)
            mem_we    <= e_we;
            mem_adr   <= e_adr;
            mem_wdat  <= e_wdat;
            mem_req_t <= ~mem_req_t;
            b_busy    <= 1;
        end
    end
    else if (mem_done_t == mem_req_t && mem_done_d == mem_req_t) begin
        b_rdat   <= mem_rdat;
        b_done_t <= req_s[2];
        b_busy   <= 0;
    end
end

//------------------------------------------------------------------ audio (to clk_bus)
reg  [15:0] hold_l = 0, hold_r = 0;
reg   [5:0] hold_cnt = 0;
reg         hold_tg = 0;
always @(posedge clk_eng) begin
    hold_cnt <= hold_cnt + 1'd1;
    if (hold_cnt == 0) begin
        hold_l  <= out2_l;
        hold_r  <= out2_r;
        hold_tg <= ~hold_tg;
    end
end
reg  [2:0] tg_s = 0;
always @(posedge clk_bus) begin
    tg_s <= {tg_s[1:0], hold_tg};
    if (tg_s[2] ^ tg_s[1]) begin
        pcm_l <= hold_l;
        pcm_r <= hold_r;
    end
end

endmodule
