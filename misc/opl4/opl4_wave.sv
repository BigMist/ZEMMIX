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
//     and to be ORed into the C4h status.  Reads of C4h are not queued: one pending
//     read is played when the queue is empty (LD2), and it does not make BUSY.
//   * memory: the engine asks for a byte when a window starts and samples it at the
//     next CYCLE1_CE, about 7 CE later, with no wait. The request crosses to clk_bus
//     (toggle) and that CE is held while the data is not back: the fractional
//     accumulator keeps its credit and catches up after (the average sample rate does
//     not move). A line cache (32 lines of what a read gives) serves most bytes.
//     Writes to 000000h-1FFFFFh (the YRW801 ROM) are ignored, as on the MoonSound.
//   * audio: OUT2 of the engine (PCM with the F9h mix attenuation), through a FIFO
//     read at a steady 44.1 kHz (no wow and flutter from the held CE), copied to
//     clk_bus with a toggle.
//
module opl4_wave
#(
    parameter          CE_INC  = 24'd10584,     // 33.8688 MHz / 50 MHz = 10584 / 15625
    parameter          CE_MOD  = 24'd15625,
    parameter          RD_MAX  = 7'd100,        // longest wait of an IN 7Fh in clk_bus cycles (4.7 us)
    parameter          LINE_RD = 0              // 1: a read of the wave memory gives 4 words (8 bytes, adr 8-aligned)
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
    input  wire [63:0] mem_rdat,                // a line of 4 words with LINE_RD (word 0 in 15-0)

    // diagnostics of the ZEMMIX.ROM load (clk_bus), read on regs F0h-F3h and FAh-FFh
    input  wire [23:0] dbg_wr,                  // F0h-F2h: bytes written to the wave memory
    input  wire  [7:0] dbg_flags,               // F3h
    input  wire [23:0] dbg_rcv,                 // FAh-FCh: bytes received
    input  wire [23:0] dbg_lost,                // FDh-FFh: bytes lost (FIFO full)

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
// A and DI are taken 3 clk_eng after the strobe is seen: DO and WR (or RD) can change in
// the same clk21m cycle (R800), and a sample taken with the strobe could still have
// bits of the old value
reg   [1:0] x_cnt = 0;
reg         x_rd = 0, x_pend = 0;
// A read of the C4h status (A = 0) only matters to the engine to clear LD2: it is not
// queued (nor BUSY) but kept as one pending read, played when the queue is empty.  A
// status read in the queue made BUSY high for the poll that queued it: an R800, whose
// IN is short, read BUSY from its own read on every poll and never left the loop
// (RoboPlay, OPL4 reset).
reg         st_pend = 0, st_take = 0;
always @(posedge clk_eng) begin
    rdx_d <= rdx;
    wrx_d <= wrx;
    if (st_take) st_pend <= 0;
    if (x_pend) begin
        if (x_cnt != 0) x_cnt <= x_cnt - 1'd1;
        else begin
            if (x_rd && a_s == 3'd0)
                st_pend <= 1;
            else begin
                q[q_wp] <= {x_rd, a_s, x_rd ? 8'h00 : di_s};
                q_wp    <= q_wp + 1'd1;
            end
            x_pend  <= 0;
        end
    end
    else if (wrx && !wrx_d) begin
        x_pend <= 1; x_rd <= 0; x_cnt <= 2'd2;
    end
    else if (rdx && !rdx_d) begin
        x_pend <= 1; x_rd <= 1; x_cnt <= 2'd2;
    end
end

// player: CS, then the strobe low for 2 CE and high again, the next one 12 CE later
// and when the engine is not BUSY. A read of A = 5 takes REG_Q 5 CE after its strobe.
wire  [7:0] eng_do;
wire  [1:0] eng_status;
wire        sample_ce;                          // the engine has a new sample
reg         drv = 0;
reg         drv_st = 0;                         // playing a C4h status read (not BUSY)
reg   [3:0] ph = 0;
reg         drv_rd = 0, drv_cs = 0, drv_rd_n = 1, drv_wr_n = 1;
reg   [2:0] drv_a = 0;
reg   [7:0] drv_di = 0;
reg         rd_done_t = 0;                      // to clk_bus, rd_q stable then
reg   [7:0] rd_q = 8'hFF;
always @(posedge clk_eng) begin
    st_take <= 0;
    if (!drv) begin
        if (!q_empty && !eng_status[0]) begin
            {drv_rd, drv_a, drv_di} <= q[q_rp];
            q_rp   <= q_rp + 1'd1;
            drv    <= 1;
            drv_st <= 0;
            drv_cs <= 1;
            ph     <= 0;
        end
        else if (q_empty && st_pend && !st_take && !eng_status[0]) begin
            {drv_rd, drv_a, drv_di} <= {1'b1, 3'd0, 8'h00};
            st_take <= 1;
            drv    <= 1;
            drv_st <= 1;
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
    .STATUS     (eng_status),
    .SAMPLE_CE  (sample_ce)
);

//------------------------------------------------------------------ bus side: reads of 7Fh, status (clk_bus)
wire       rd7f = bus_cs && !bus_rd_n && bus_a == 3'd5;
reg        rd7f_d = 0;
reg  [2:0] rd_iss = 0, rd_cmp = 0;              // reads of 7Fh started / answered (mod 8)
reg  [6:0] rd_cnt = 0;
reg  [2:0] rdd_s = 0;
wire       rd_back = rdd_s[2] != rdd_s[1];      // an answer
reg        rd_ok = 0;                          // the answer of this IN is on bus_do since the last clock
wire       rd_ready = rd_ok || rd_cnt >= RD_MAX;
reg  [1:0] st_s0 = 2'b00;
reg  [1:0] qb_s = 2'b00;                        // queue busy
reg  [7:0] idx_b = 0;                           // last index written to 7Eh
reg        wr4_d = 0;
// diagnostics (regs F4h-F7h of 7Eh / 7Fh): FIFO empty while playing / full (since
// reset), counted in the audio part below
reg  [15:0] sf_unf = 0, sf_ovf = 0;
reg  [7:0] dbg_q;
always @(*) begin
    case (idx_b)
        8'hF0: dbg_q = dbg_wr[7:0];    8'hF1: dbg_q = dbg_wr[15:8];   8'hF2: dbg_q = dbg_wr[23:16];
        8'hF3: dbg_q = dbg_flags;
        8'hF4: dbg_q = sf_unf[7:0];    8'hF5: dbg_q = sf_unf[15:8];   // FIFO empty (clk_eng, slow)
        8'hF6: dbg_q = sf_ovf[7:0];    8'hF7: dbg_q = sf_ovf[15:8];   // FIFO full
        8'hFA: dbg_q = dbg_rcv[7:0];   8'hFB: dbg_q = dbg_rcv[15:8];  8'hFC: dbg_q = dbg_rcv[23:16];
        8'hFD: dbg_q = dbg_lost[7:0];  8'hFE: dbg_q = dbg_lost[15:8]; 8'hFF: dbg_q = dbg_lost[23:16];
        default: dbg_q = 8'h00;
    endcase
end
wire       idx_dbg = (idx_b[7:4] == 4'hF) && (idx_b[3:0] <= 4'h7 || idx_b[3:0] >= 4'hA);
always @(posedge clk_bus) begin
    rdd_s  <= {rdd_s[1:0], rd_done_t};
    wr4_d  <= bus_cs && !bus_wr_n && bus_a == 3'd4;
    if (bus_cs && !bus_wr_n && bus_a == 3'd4 && !wr4_d) idx_b <= bus_di;
    rd7f_d <= rd7f;
    if (rd7f && !rd7f_d) rd_iss <= rd_iss + 1'd1;
    if (rd_back)         rd_cmp <= rd_cmp + 1'd1;
    if (!rd7f)           rd_cnt <= 0;
    else if (!rd_ready)  rd_cnt <= rd_cnt + 1'd1;
    rd_ok <= rd7f && rd7f_d && rd_cmp == rd_iss;  // one clock after bus_do took the answer

    st_s0 <= eng_status;
    qb_s  <= {qb_s[0], (drv & ~drv_st) | !q_empty};   // a status read is not BUSY
    bus_status <= {st_s0[1], st_s0[0] | qb_s[1]};

    if (rd7f) begin
        if (rd_back && rd_cmp + 1'd1 == rd_iss) bus_do <= idx_dbg ? dbg_q : rd_q;   // the answer of this IN (or a diagnostic byte)
    end
    else if (bus_rd_n) bus_do <= {6'b000000, bus_status};      // 7Eh: status (held during an IN)
end
assign bus_wait_n = ~(rd7f && !rd_ready);

//------------------------------------------------------------------ wave memory, clk_eng side
wire [21:0] eng_adr  = {~eng_mcs_n[1], eng_ma};    // MCS_N[1] is low when A21 = 1
wire        eng_mreq = ~eng_mrd_n | ~eng_mwr_n;
reg         eng_mreq_d = 0;

// Line cache: CL lines, fully associative, replaced in turn.  A line is what the memory
// gives on a read: 4 words (8 bytes) with LINE_RD (the 2nd SDRAM of the SiDi128), else
// one word.  Each slot reads consecutive bytes, so a line serves several of its samples
// (with one word per read the engine waited for the memory on almost every byte: with
// more than ~12 slots playing it made fewer than 44100 samples a second, the music went
// slower and lower).  Writes go to the memory and to the line if it is here.
localparam CL = 32;
function [20:0] tag_of(input [21:0] a);
    tag_of = LINE_RD ? {a[21:3], 2'b00} : a[21:1];
endfunction
function [7:0] byte_of(input [63:0] l, input [2:0] off);
    byte_of = LINE_RD ? l[{off, 3'b000} +: 8] : (off[0] ? l[15:8] : l[7:0]);
endfunction
reg  [20:0] lt [0:CL-1];                        // line tags
reg  [63:0] ld [0:CL-1];                        // line data (byte k in bits 8k+7..8k)
reg  [CL-1:0] lv = 0;                           // valid
reg   [4:0] lrr = 0;                            // next line to replace
reg         hit;
reg   [4:0] hit_i;
integer     ci;
always @* begin
    hit = 0; hit_i = 0;
    for (ci = 0; ci < CL; ci = ci + 1)
        if (lv[ci] && lt[ci] == tag_of(eng_adr)) begin hit = 1; hit_i = ci[4:0]; end
end
wire  [2:0] eng_off = LINE_RD ? eng_adr[2:0] : {2'b00, eng_adr[0]};

reg         e_req_t = 0;                        // request toggle to clk_bus, payload below
reg         e_we = 0;
reg  [21:0] e_adr = 0;
reg   [2:0] e_off = 0;                          // byte of the line asked by the engine
reg   [7:0] e_wdat = 0;
reg         b_done_t = 0;                       // done toggle from clk_bus (b_rdat stable then)
reg  [63:0] b_rdat = 0;
reg   [2:0] done_s = 0;

always @(posedge clk_eng) begin
    eng_mreq_d <= eng_mreq;
    done_s     <= {done_s[1:0], b_done_t};

    if (pend) begin
        if (done_s[2] == e_req_t) begin         // the access is back
            pend <= 0;
            if (!e_we) begin
                lt[lrr] <= tag_of(e_adr);
                ld[lrr] <= b_rdat;
                lv[lrr] <= eng_rst_n;
                lrr     <= lrr + 1'd1;
                eng_mdi <= byte_of(b_rdat, e_off);
            end
        end
    end
    else if (eng_mreq && !eng_mreq_d) begin     // a new access of the engine
        if (!eng_mwr_n) begin
            eng_mdi <= eng_mdo;                 // the engine takes MDI back on a write
            if (eng_adr[21]) begin              // RAM: write it (and the line), ROM: ignore it
                if (hit) ld[hit_i][{eng_off, 3'b000} +: 8] <= eng_mdo;
                e_we    <= 1;
                e_adr   <= eng_adr;
                e_wdat  <= eng_mdo;
                e_req_t <= ~e_req_t;
                pend    <= 1;
            end
        end
        else if (hit) begin
            eng_mdi <= byte_of(ld[hit_i], eng_off);
        end
        else begin
            e_we    <= 0;
            e_adr   <= LINE_RD ? {eng_adr[21:3], 3'b000} : eng_adr;
            e_off   <= eng_off;
            e_req_t <= ~e_req_t;
            pend    <= 1;
        end
    end

    if (!eng_rst_n) lv <= 0;
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
// The engine makes its samples at 44.1 kHz on average only: its CE stops while it
// waits for the wave memory and catches up after, so taken as they come the samples
// wow and flutter like a slow tape. They go through a FIFO, read at a steady 44.1 kHz
// (50 MHz * 441 / 500000), from half full: the average rates are the same.
reg  [31:0] sfifo [0:31];                       // {L, R}
reg   [4:0] sf_wp = 0, sf_rp = 0;
wire  [4:0] sf_lvl = sf_wp - sf_rp;
reg         sf_run = 0;
reg         sample_ce_d = 0;
reg  [18:0] sacc = 0;
reg  [15:0] hold_l = 0, hold_r = 0;
reg         hold_tg = 0;
always @(posedge clk_eng) begin
    sample_ce_d <= sample_ce;                   // OUT2 has the new sample one clock later
    if (sample_ce_d && sf_lvl != 5'd31) begin
        sfifo[sf_wp] <= {out2_l, out2_r};
        sf_wp <= sf_wp + 1'd1;
    end
    if (sample_ce_d && sf_lvl == 5'd31 && sf_ovf != 16'hFFFF) sf_ovf <= sf_ovf + 1'd1;   // sample lost

    if (sacc + 19'd441 >= 19'd500000) begin     // a 44.1 kHz tick
        sacc <= sacc + 19'd441 - 19'd500000;
        if (sf_run && sf_lvl != 0) begin
            {hold_l, hold_r} <= sfifo[sf_rp];
            sf_rp   <= sf_rp + 1'd1;
            hold_tg <= ~hold_tg;
        end
        else if (sf_run && sf_unf != 16'hFFFF) sf_unf <= sf_unf + 1'd1;  // empty: the last one again
        if (sf_lvl >= 5'd16) sf_run <= 1;       // start from half full
        else if (sf_lvl == 0) sf_run <= 0;      // empty (engine stopped): fill again
    end
    else sacc <= sacc + 19'd441;

    if (!eng_rst_n) begin
        sf_rp  <= sf_wp;
        sf_run <= 0;
        sf_unf <= 0;
        sf_ovf <= 0;
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
