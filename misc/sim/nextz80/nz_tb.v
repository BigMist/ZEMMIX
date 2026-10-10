`timescale 1ns/1ps
module nz_tb;
  reg clk=0; always #5 clk=~clk;
  reg reset=1;
  wire [7:0] DO; wire [15:0] ADDR; wire WR, MREQ, IORQ, HALT, M1;
  reg [7:0] mem [0:65535];
  wire [7:0] DI = MREQ ? mem[ADDR] : 8'hFF;
  integer i, cyc=0, last=0, n=0;
  NextZ80 cpu(.DI(DI), .DO(DO), .ADDR(ADDR), .WR(WR), .MREQ(MREQ), .IORQ(IORQ), .HALT(HALT), .M1(M1),
              .CLK(clk), .RESET(reset), .INT(1'b0), .NMI(1'b0), .WAIT(1'b0));
  // memory: data for the address given in this clock, at the next edge
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (M1 && MREQ && cyc < 900) $display("F %0d %h %h", cyc, ADDR, DI);
    if (!M1 && (MREQ||IORQ) && cyc < 900) $display("  %s%s %0d %h %h", IORQ?"IO":"MEM", WR?"W":"R", cyc, ADDR, WR?DO:DI);
    if (MREQ && WR) mem[ADDR] <= DO;
    if (IORQ && WR && !M1 && ADDR[7:0] == 8'hFE) begin
      $display("mark %0d at %0d delta %0d", n, cyc, cyc - last);
      last = cyc; n = n + 1;
    end
    if (HALT) begin $display("halt at %0d", cyc); $finish; end
  end
  initial begin
    for (i=0;i<65536;i=i+1) mem[i]=8'h00;
    $readmemh("prog.hex", mem);
    repeat(4) @(posedge clk); reset=0;
    #200000; $display("timeout"); $finish;
  end
endmodule
