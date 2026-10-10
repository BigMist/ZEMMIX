// V9990 interlace (R#7 IL) at 31 kHz: the odd field one line lower (bob),
// as a TV shows it (ZEMMIX-91t.1).
//
// The V9990 gives 15 kHz lines of 1368 clk_sys; mist_video doubles each line
// of a field, so in interlace both fields are shown at the same height and
// what differs between them (EO pages: Dream Puzzle at 512 x 424) jumps up and
// down every field.  Here each input line L gives two 31 kHz lines of 684
// clk_sys during input line L + 1: L and L in the even field, L - 1 and L in
// the odd one, so the odd field is half a TV line (one 31 kHz line) lower.
// Fine lines still flicker at 30 Hz, as on a real CRT; a weave with a field
// buffer does not fit in the block RAM of the SiDi128.  The output goes to
// mist_video with its scandoubler bypassed.
//
// The blank (HDMI DE) is always the one of line L: only the colours move, so
// the active window does not move with the field (an HDMI sink goes black
// when the first active line changes every frame).
//
// field: 0 while the V9990 shows the even lines (EO 0), 1 the odd ones.

module v99_bob
(
	input            clk,               // clk_sys
	input            field,

	input      [7:0] r_in,              // the V9990 at 15 kHz (on clk)
	input      [7:0] g_in,
	input      [7:0] b_in,
	input            hs_n_in,
	input            vs_n_in,
	input            blank_in,

	output reg [7:0] r_out,             // 31 kHz, one sample per clk
	output reg [7:0] g_out,
	output reg [7:0] b_out,
	output reg       hs_n_out,
	output reg       vs_n_out,
	output reg       blank_out
);

localparam LINE = 684;                  // samples of an input line, clocks of an output line
localparam HS   = 50;                   // hsync of an output line (100 clk_sys at 15 kHz)

// ---- input: the lines in a buffer of four ------------------------------
reg        hs_d = 1'b1;
reg [10:0] ic = 11'd0;                  // clock of the input line
reg  [1:0] wb = 2'd0;                   // line written now
reg        lb_vs [4];
reg        lb_fld [4];

wire hs_fall = hs_d & ~hs_n_in;

reg [23:0] lb [4096];                   // {r, g, b}, line in bits 11-10 of the address
reg        lbb [4096];                  // blank

always @(posedge clk) begin
	hs_d <= hs_n_in;
	ic   <= ic + 1'd1;
	if (!ic[0] && ic < 2*LINE)
	begin
		lb[{wb, ic[10:1]}]  <= {r_in, g_in, b_in};
		lbb[{wb, ic[10:1]}] <= blank_in;
	end
	if (hs_fall) begin
		ic         <= 11'd0;
		lb_vs[wb]  <= vs_n_in;
		lb_fld[wb] <= field;
		wb         <= wb + 1'd1;
	end
end

// ---- output: line L twice, or L - 1 then L -----------------------------
wire        half = ic >= LINE;
wire  [9:0] ox   = half ? 10'(ic - LINE) : ic[9:0];
wire  [1:0] l1   = wb - 2'd1;           // line L, the last one written
wire  [1:0] l2   = wb - 2'd2;           // line L - 1
wire  [1:0] src  = (!half && lb_fld[l1]) ? l2 : l1;

reg  [23:0] lq;
reg         lqb, s1_hs, s1_vs;

always @(posedge clk) begin
	lq    <= lb[{src, ox}];
	lqb   <= lbb[{l1, ox}];
	s1_hs <= ox >= HS;
	s1_vs <= lb_vs[l1];
	{r_out, g_out, b_out} <= lq;
	blank_out <= lqb;
	hs_n_out <= s1_hs;
	vs_n_out <= s1_vs;
end

endmodule
