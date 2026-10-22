`timescale 1ns/1ps
module tb_square_lowp_product;
    reg [7:0] a,b;
    wire signed [31:0] p_posit,p_fp4,p_fp2,p_dp2,p_dp2_e0m1;
    wire nar_posit;
    square_lowp_product #(.FORMAT(0)) u_posit(.a(a),.b(b),.product_q8(p_posit),.nar(nar_posit));
    square_lowp_product #(.FORMAT(1)) u_fp4(.a(a),.b(b),.product_q8(p_fp4),.nar());
    square_lowp_product #(.FORMAT(2)) u_fp2(.a(a),.b(b),.product_q8(p_fp2),.nar());
    square_lowp_product #(.FORMAT(3)) u_dp2(.a(a),.b(b),.product_q8(p_dp2),.nar());
    square_lowp_product #(.FORMAT(3),.FP2_FORMAT(1)) u_dp2_e0m1(
        .a(a),.b(b),.product_q8(p_dp2_e0m1),.nar());
    initial begin
        a=8'h04; b=8'h05; #1; // Posit4: 1 * 2 = 2
        if (p_posit !== 32'sd512 || nar_posit !== 1'b0) $fatal(1,"Posit + product");
        a=8'h0c; b=8'h04; #1; // Posit4: -1 * 1 = -1
        if (p_posit !== -32'sd256) $fatal(1,"Posit - product");
        a=8'h08; b=8'h04; #1; // Posit4 NaR
        if (nar_posit !== 1'b1 || p_posit !== 0) $fatal(1,"Posit NaR");
        a=8'h02; b=8'h03; #1; // FP4: 1 * 1.5
        if (p_fp4 !== 32'sd384) $fatal(1,"FP4 mixed mantissa");
        a=8'h0c; b=8'h02; #1; // FP4: -2 * 1
        if (p_fp4 !== -32'sd512) $fatal(1,"FP4 sign");
        a=8'h00; b=8'h00; #1; // FP2 E1M0: +1 * +1
        if (p_fp2 !== 32'sd256) $fatal(1,"FP2 single");
        a=8'h04; b=8'h08; #1; // DP2: +1*+1 + +0.5*-1 = +0.5
        if (p_dp2 !== 32'sd128) $fatal(1,"DP2 cancellation");
        if (p_dp2_e0m1 !== -32'sd128) $fatal(1,"DP2 E0M1");
        a=8'h34; b=8'h08; #1; // DP2 zero flags: both A lanes forced 0
        if (p_dp2 !== 0) $fatal(1,"DP2 zero sideband");
        $display("PASS: Posit4, FP4, FP2, DP2 product tests");
        $finish;
    end
endmodule
