//
// audio_mix.sv
//   Sound mixer of the ZEMMIX: OPL3, OPLL, SCC x2, PSG (+PSG2, key click), turboR PCM
//   and tape input, to signed 16-bit samples (I2S / SPDIF) and offset binary (sigma-delta DAC).
//
//   * every source is sign extended and summed with headroom (20 bits), then saturated
//   * PSG + tape are unipolar: their DC is removed by a slow high-pass (~1.6Hz)
//   * the 8-bit turboR PCM goes through a gentle low-pass (~13kHz) against its steps
//   * per source volumes of the OCM (PsgVol, SccVol, OpllVol: 0 = mute, 4 = normal,
//     7 = +6dB), OPL3 follows OpllVol (FM) and the PCM follows PsgVol
//   * master volume (MstrVol: 0 = 0dB ... 6 = -18dB, 7 = mute) after the saturation
//
module audio_mix (
    input  wire               clk,                  // clk_sys (21.48MHz)
    input  wire               reset,

    input  wire signed [15:0] opl3_l,
    input  wire signed [15:0] opl3_r,
    input  wire signed [15:0] opl4_l,               // OPL4 wave (PCM of the MoonSound), follows OpllVol
    input  wire signed [15:0] opl4_r,
    input  wire signed [15:0] opll,
    input  wire signed [14:0] scc1_l,
    input  wire signed [14:0] scc1_r,
    input  wire signed [14:0] scc2_l,
    input  wire signed [14:0] scc2_r,
    input  wire        [15:0] psg,                  // PSG + PSG2 + key click, unsigned 0..26618
    input  wire signed [ 7:0] pcm,                  // turboR PCM, signed
    input  wire               tape_en,
    input  wire               tape_in,

    input  wire        [ 2:0] psg_vol,
    input  wire        [ 2:0] scc_vol,
    input  wire        [ 2:0] opll_vol,
    input  wire        [ 2:0] mstr_vol,

    output reg  signed [15:0] out_l,                // I2S / SPDIF
    output reg  signed [15:0] out_r,
    output wire        [15:0] dac_l,                // sigma-delta DAC (offset binary)
    output wire        [15:0] dac_r
);

    // ---- gains in 1/16 (about 3dB steps)
    function automatic [5:0] src_gain(input [2:0] v);
        case (v)
            3'd0: src_gain = 6'd0;                  // mute
            3'd1: src_gain = 6'd4;                  // -12dB
            3'd2: src_gain = 6'd6;                  // -8.5dB
            3'd3: src_gain = 6'd11;                 // -3.3dB
            3'd4: src_gain = 6'd16;                 //  0dB (default)
            3'd5: src_gain = 6'd22;                 // +2.8dB
            3'd6: src_gain = 6'd28;                 // +4.9dB
            default: src_gain = 6'd32;              // +6dB
        endcase
    endfunction

    function automatic [4:0] mstr_gain(input [2:0] v);
        case (v)
            3'd0: mstr_gain = 5'd16;                //  0dB (default)
            3'd1: mstr_gain = 5'd11;                // -3.3dB
            3'd2: mstr_gain = 5'd8;                 // -6dB
            3'd3: mstr_gain = 5'd6;                 // -8.5dB
            3'd4: mstr_gain = 5'd4;                 // -12dB
            3'd5: mstr_gain = 5'd3;                 // -14.5dB
            3'd6: mstr_gain = 5'd2;                 // -18dB
            default: mstr_gain = 5'd0;              // mute
        endcase
    endfunction

    // ---- filter clocks
    reg [8:0] div = 9'd0;
    always @(posedge clk) begin
        if (reset)  div <= 9'd0;
        else        div <= div + 9'd1;
    end
    wire tick_dc  = (div == 9'd0);                  // 21.48MHz / 512 = 41.95kHz
    wire tick_pcm = (div[5:0] == 6'd0);             // 21.48MHz / 64  = 335.6kHz

    // ---- stage 1: sources
    // PSG + tape: unipolar, DC removed by a leaky integrator (tau = 4096 / 41.95kHz)
    wire signed [17:0] uni   = $signed({2'b00, psg}) + (tape_en && tape_in ? 18'sd4096 : 18'sd0);
    reg  signed [29:0] dc_acc;
    wire signed [17:0] dc    = dc_acc >>> 12;
    always @(posedge clk) begin
        if (reset)          dc_acc <= 30'sd0;
        else if (tick_dc)   dc_acc <= dc_acc + uni - dc;
    end

    // PCM: one pole low-pass, y += (x - y) / 4 at 335.6kHz (fc ~13kHz)
    wire signed [15:0] pcm_x = {{2{pcm[7]}}, pcm, 6'b0};    // +-8192
    reg  signed [15:0] pcm_y;
    always @(posedge clk) begin
        if (reset)          pcm_y <= 16'sd0;
        else if (tick_pcm)  pcm_y <= pcm_y + ((pcm_x - pcm_y) >>> 2);
    end

    reg signed [17:0] s_psg;
    reg signed [15:0] s_pcm, s_opll, s_opl3l, s_opl3r;
    reg signed [15:0] s_opl4l, s_opl4r;
    reg signed [15:0] s_sccl, s_sccr;
    reg        [ 5:0] g_psg, g_scc, g_opll;
    reg        [ 4:0] g_mstr;
    always @(posedge clk) begin
        s_psg   <= uni - dc;
        s_pcm   <= pcm_y;
        s_opll  <= opll;
        s_opl3l <= opl3_l;
        s_opl3r <= opl3_r;
        s_opl4l <= opl4_l;
        s_opl4r <= opl4_r;
        s_sccl  <= scc1_l + scc2_l;                 // 15-bit signed, sign extended to 16
        s_sccr  <= scc1_r + scc2_r;
        g_psg   <= src_gain(psg_vol);
        g_scc   <= src_gain(scc_vol);
        g_opll  <= src_gain(opll_vol);
        g_mstr  <= mstr_gain(mstr_vol);
    end

    // ---- stage 2: per source volume (x gain / 16), products at full width
    wire signed [24:0] p_psg   = s_psg   * $signed({1'b0, g_psg });
    wire signed [22:0] p_pcm   = s_pcm   * $signed({1'b0, g_psg });
    wire signed [22:0] p_opll  = s_opll  * $signed({1'b0, g_opll});
    wire signed [22:0] p_opl3l = s_opl3l * $signed({1'b0, g_opll});
    wire signed [22:0] p_opl3r = s_opl3r * $signed({1'b0, g_opll});
    wire signed [22:0] p_opl4l = s_opl4l * $signed({1'b0, g_opll});
    wire signed [22:0] p_opl4r = s_opl4r * $signed({1'b0, g_opll});
    wire signed [22:0] p_sccl  = s_sccl  * $signed({1'b0, g_scc });
    wire signed [22:0] p_sccr  = s_sccr  * $signed({1'b0, g_scc });

    reg signed [19:0] v_psg, v_pcm, v_opll, v_opl3l, v_opl3r, v_opl4l, v_opl4r, v_sccl, v_sccr;
    always @(posedge clk) begin
        v_psg   <= p_psg   >>> 4;
        v_pcm   <= p_pcm   >>> 4;
        v_opll  <= p_opll  >>> 4;
        v_opl3l <= p_opl3l >>> 4;
        v_opl3r <= p_opl3r >>> 4;
        v_opl4l <= p_opl4l >>> 4;
        v_opl4r <= p_opl4r >>> 4;
        v_sccl  <= p_sccl  >>> 4;
        v_sccr  <= p_sccr  >>> 4;
    end

    // ---- stage 3: sum with headroom and saturation to 16 bits
    wire signed [22:0] sum_l = v_opl3l + v_opl4l + v_opll + v_sccl + v_psg + v_pcm;
    wire signed [22:0] sum_r = v_opl3r + v_opl4r + v_opll + v_sccr + v_psg + v_pcm;

    function automatic signed [15:0] sat16(input signed [22:0] x);
        if (x > 23'sd32767)         sat16 = 16'sh7FFF;
        else if (x < -23'sd32768)   sat16 = 16'sh8000;
        else                        sat16 = x[15:0];
    endfunction

    reg signed [15:0] m_l, m_r;
    always @(posedge clk) begin
        m_l <= sat16(sum_l);
        m_r <= sat16(sum_r);
    end

    // ---- stage 4: master volume
    wire signed [21:0] o_l = m_l * $signed({1'b0, g_mstr});
    wire signed [21:0] o_r = m_r * $signed({1'b0, g_mstr});
    always @(posedge clk) begin
        out_l <= o_l >>> 4;
        out_r <= o_r >>> 4;
    end

    // sigma-delta DAC: offset binary (0 = most negative, 8000h = silence)
    assign dac_l = {~out_l[15], out_l[14:0]};
    assign dac_r = {~out_r[15], out_r[14:0]};

endmodule
