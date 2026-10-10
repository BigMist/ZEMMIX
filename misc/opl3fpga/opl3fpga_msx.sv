//
// opl3fpga_msx.sv
//   OPL3 of Greg Taylor (gtaylormb/opl3_fpga, LGPL-3.0) with the ports emsx_top uses
//   (those of the old opl3sw wrapper, removed).
//
//   * clk_opl must be CLOCK_50: opl3_pkg.sv has CLK_FREQ = 50e6 (sample rate and timers)
//   * writes: one per rising edge of we, address/data as in the real chip
//     (addr[0] = 0 index, 1 data; addr[1] = bank), through the dcfifo of host_if
//   * reads: status on addr 0 / 2 (C4h / C6h, host_if), and on addr 1 / 3 (C5h / C7h)
//     the FM register selected last, from a copy of the 512 registers: the YMF278B
//     (OPL4) reads its FM registers back and MoonSound software (MBWAVE) uses that to
//     tell it from an OPL3. One index latch for both banks, as openMSX.
//   * samples: 16-bit signed, already in the clk domain (dac_prep, clk_dac = clk)
//   * irq_n: synchronized to clk
//
module opl3fpga_msx
#(
 parameter            OPLCLK = 50000000 // must match CLK_FREQ of opl3_pkg.sv
)
(
 input                clk,
 input                clk_opl,
 input                rst_n,
 output               irq_n,

 input          [1:0] addr,
 output         [7:0] dout,
 input          [7:0] din,
 input                we,
 input                mono,             // not used

 output signed [15:0] sample_l,
 output signed [15:0] sample_r
);

wire irq_opl_n;

// copy of the FM registers for the reads of C5h / C7h
reg  [7:0] fm_regs [0:511];
reg  [8:0] fm_idx = 0;
reg  [7:0] fm_q = 8'hFF;
reg        we_d = 0;
wire [7:0] opl_dout;
always @(posedge clk) begin
    we_d <= we;
    if (we && !we_d) begin
        if (!addr[0]) fm_idx <= {addr[1], din};
        else          fm_regs[fm_idx] <= din;
    end
    fm_q <= fm_regs[fm_idx];
end
assign dout = addr[0] ? fm_q : opl_dout;

opl3fpga opl3fpga
(
    .clk          (clk_opl),
    .clk_host     (clk),
    .clk_dac      (clk),
    .ic_n         (rst_n),
    .cs_n         (1'b0),
    .rd_n         (1'b1),
    .wr_n         (~we),
    .address      (addr),
    .din          (din),
    .dout         (opl_dout),
    .sample_valid (),
    .sample_l     (sample_l),
    .sample_r     (sample_r),
    .led          (),
    .irq_n        (irq_opl_n)
);

reg [1:0] irq_sync = 2'b11;
always @(posedge clk) irq_sync <= {irq_sync[0], irq_opl_n};
assign irq_n = irq_sync[1];

endmodule
