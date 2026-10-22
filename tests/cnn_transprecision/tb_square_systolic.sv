`timescale 1ns/1ps
module tb_square_systolic;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, clear=0;
    reg [15:0] a_left=0,b_top=0;
    reg [1:0] a_valid=0,b_valid=0;
    wire [127:0] acc_flat;
    wire [3:0] result_valid,nar_seen,overflow;
    square_systolic_posit4 #(.ROWS(2),.COLS(2)) dut(
        .clk(clk),.rst_n(rst_n),.clear(clear),
        .a_left(a_left),.b_top(b_top),
        .a_valid(a_valid),.b_valid(b_valid),
        .acc_flat(acc_flat),.result_valid(result_valid),
        .nar_seen(nar_seen),.overflow(overflow));
    task step;
        input [15:0] a,b;
        input [1:0] av,bv;
        begin
          @(negedge clk);
          a_left=a; b_top=b; a_valid=av; b_valid=bv;
          @(posedge clk); #1;
        end
    endtask
    initial begin
        repeat(2) @(negedge clk);
        rst_n=1;
        clear=1;
        step(0,0,0,0); clear=0;
        // A=[[1,2],[0.25,-1]], B=[[1,0.5],[2,1]].
        // row r: A[k] at cycle k+r; col c: B[k] at cycle k+c.
        step(16'h0004,16'h0004,2'b01,2'b01); // t0: a00 and b00
        step(16'h0205,16'h0305,2'b11,2'b11); // t1: a01,a10; b10,b01
        step(16'h0c00,16'h0400,2'b10,2'b10); // t2: a11,b11
        repeat(5) step(0,0,0,0);
        if ($signed(acc_flat[31:0]) !== 32'sd1280) $fatal(1,"C00 (5.0)");
        if ($signed(acc_flat[63:32]) !== 32'sd640) $fatal(1,"C01 (2.5)");
        if ($signed(acc_flat[95:64]) !== -32'sd448) $fatal(1,"C10 (-1.75)");
        if ($signed(acc_flat[127:96]) !== -32'sd224) $fatal(1,"C11 (-0.875)");
        if (nar_seen !== 4'b0 || overflow !== 4'b0) $fatal(1,"unexpected flags");
        $display("PASS: 2x2 skewed Posit4 systolic matrix product");
        $finish;
    end
endmodule
