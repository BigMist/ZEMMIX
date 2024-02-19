/*
 * Copyright (c) 2014, Aleksander Osman
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 *
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

module opl3
#(
 parameter            OPLCLK = 64000000 // opl_clk in Hz
)
(
 input                clk,
 input                clk_opl,
 input                rst_n,
 output reg           irq_n,

 //input         [12:0] period_80us, // from clk

 input          [1:0] addr,
 output         [7:0] dout,
 input          [7:0] din,
 input                we,
 input                mono,

 output signed [15:0] sample_l,
 output signed [15:0] sample_r
);

//------------------------------------------------------------------------------
// Ducasp hack to have mono output without having to render registers for two
// channels. So, just set mono pin and leave one channel not connected to have
// all sound (in mono) in that channel and not needing to render the other
// channel output as Quartus will exclude that as it is not connected
reg [7:0] regdin;
reg monoCx = 1'b0;
reg nextDataMono = 1'b0;
assign regdin = (monoCx && addr[0] ) ? din[5] ? {din[7:6], 2'b11, din[3:0]} : din[4] ? {din[7:6], 2'b11, din[3:0]} : din : din;
//------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0) begin
        monoCx <= 0;
        nextDataMono <= 0;
    end
    else begin
        if(~addr[0] && write && din[7:4] == 4'b1100 && mono) nextDataMono <= 1'b1; //Write to Cx next data, and force on both channels
        else if(~addr[0] && write) nextDataMono <= 1'b0; //No need to force anything
        if(write_end && nextDataMono) begin
            monoCx <= 1'b1; //Next data will be masked to both channels if only one channel is set
            nextDataMono <= 1'b0;
        end;
        if(addr[0] && write_end && monoCx) begin //Writing data end
            nextDataMono <= 1'b0;
            monoCx <= 1'b0;
        end
    end
end
//------------------------------------------------------------------------------
// Fix proposed by Laurens Holst (Grauw)

wire timer1_flag = timer1_overflow & ~timer1_mask;
wire timer2_flag = timer2_overflow & ~timer2_mask;
wire irq = timer1_flag | timer2_flag;
wire [7:0] io_readdata = { irq, timer1_flag, timer2_flag, 5'd0 };
assign irq_n = ~irq;

//wire [7:0] io_readdata = { timer1_overflow | timer2_overflow, timer1_overflow, timer2_overflow, 5'd0 };
assign dout = !addr ? io_readdata : 8'hFF;

//------------------------------------------------------------------------------

reg [12:0] period_80us = 12'b0011010110110; // Ducasp - changed period for the proper one for our clock

reg old_write;
always @(posedge clk) old_write <= we;

wire write = (~old_write & we);
wire write_end = (old_write & ~we);

reg [8:0] index;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0) index <= 0;
    else if(~addr[0] && write) index <= {addr[1], din};
end

wire       io_write     = (addr[0] && write);
wire [7:0] io_writedata = din;

//------------------------------------------------------------------------------ timer 1

reg [7:0] timer1_preset;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                  timer1_preset <= 0;
    else if(io_write && index == 2) timer1_preset <= io_writedata;
end

reg timer1_mask;
reg timer1_active;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                                      {timer1_mask, timer1_active} <= 0;
    else if(io_write && index == 4 && ~io_writedata[7]) {timer1_mask, timer1_active} <= {io_writedata[6], io_writedata[0]};
end

wire timer1_pulse;
timer timer1( clk, period_80us, timer1_preset, timer1_active, timer1_pulse );

reg timer1_overflow;
always @(posedge clk or negedge rst_n) begin
 if(rst_n == 0)                                   timer1_overflow <= 0;
 else begin
  if(io_write && index == 4 && io_writedata[7] && ~io_writedata[6]) timer1_overflow <= 0;
  if(timer1_pulse)                    timer1_overflow <= 1;
 end
end


//------------------------------------------------------------------------------ timer 2

reg [7:0] timer2_preset;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                  timer2_preset <= 0;
    else if(io_write && index == 3) timer2_preset <= io_writedata;
end

reg timer2_mask;
reg timer2_active;
always @(posedge clk or negedge rst_n) begin
    if(rst_n == 0)                                      {timer2_mask, timer2_active} <= 0;
    else if(io_write && index == 4 && ~io_writedata[7]) {timer2_mask, timer2_active} <= {io_writedata[5], io_writedata[1]};
end

wire timer2_pulse;
timer timer2( clk, {period_80us, 2'b00}, timer2_preset, timer2_active, timer2_pulse );

reg timer2_overflow;
always @(posedge clk or negedge rst_n) begin
 if(rst_n == 0)                                   timer2_overflow <= 0;
 else begin
  if(io_write && index == 4 && io_writedata[7] && ~io_writedata[5]) timer2_overflow <= 0;
  if(timer2_pulse)                       timer2_overflow <= 1;
 end
end


//------------------------------------------------------------------------------ IRQ

//always @(posedge clk or negedge rst_n) begin
// if(rst_n == 0)                                   irq_n <= 1;
// else begin
//  if(io_write && index == 4 && io_writedata[7]) irq_n <= 1;
//  if(~timer1_mask && timer1_pulse)              irq_n <= 0;
//  if(~timer2_mask && timer2_pulse)              irq_n <= 0;
// end
//end

opl3sw #(OPLCLK) opl3
(
    .reset(~rst_n),

    .cpu_clk(clk),
    .addr(addr),
    .din(regdin),
    .wr(write),

    .clk(clk_opl),
    .left(sample_l),
    .right(sample_r)
);

endmodule

module timer
(
 input         clk,
 input  [14:0] resolution,
 input   [7:0] init,
 input         active,
 output reg    overflow_pulse
);

always @(posedge clk) begin
 reg  [7:0] counter     = 0;
 reg [14:0] sub_counter = 0;
 reg        old_act;

 old_act <= active;
 overflow_pulse <= 0;

 if(~old_act && active) begin
  counter <= init;
  sub_counter <= resolution;
 end
 else if(active) begin
  sub_counter <= sub_counter - 1'd1;
  if(!sub_counter) begin
   sub_counter <= resolution;
   counter     <= counter + 1'd1;
   if(&counter) begin
    overflow_pulse <= 1;
    counter <= init;
   end
  end
 end
end

endmodule
