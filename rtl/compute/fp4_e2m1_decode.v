// =====================================================================
// fp4_e2m1_decode.v  --  FP4-E2M1 operand-pair decoder (Std. Ref.)
//
// Decodes two FP4-E2M1 codewords {sign, e[1:0], m}. Each value is
// sig * 2^(pow-1), with sig in {0,1,2,3} and pow in {0,1,2}. Returns the
// product sign, the significand product sig_a*sig_b (0..9) and the
// combined exponent pow_a + pow_b - 2 (-2..2).
// =====================================================================
module fp4_e2m1_decode (
    input  wire [3:0]        a,   // {sign, e[1:0], m}
    input  wire [3:0]        b,
    output wire               sign_prod,
    output wire [3:0]         sig_prod,     // sig_a * sig_b, 0..9
    output wire signed [3:0]  combined_exp  // pow_a + pow_b - 2, range -2..2
);

    wire       sign_a = a[3];
    wire [1:0] e_a    = a[2:1];
    wire       m_a    = a[0];
    wire       sign_b = b[3];
    wire [1:0] e_b    = b[2:1];
    wire       m_b    = b[0];

    function [1:0] fp4_sig; // SIG in {0,1,2,3}
        input [1:0] e;
        input       m;
        begin
            if (e == 2'b00)
                fp4_sig = {1'b0, m};
            else
                fp4_sig = 2'd2 + m;
        end
    endfunction

    function [1:0] fp4_pow; // pow_exp in {0,1,2}
        input [1:0] e;
        begin
            fp4_pow = (e == 2'b00) ? 2'b00 : (e - 2'b01);
        end
    endfunction

    wire [1:0] sig_a = fp4_sig(e_a, m_a);
    wire [1:0] sig_b = fp4_sig(e_b, m_b);
    wire [1:0] pow_a = fp4_pow(e_a);
    wire [1:0] pow_b = fp4_pow(e_b);

    assign sign_prod = sign_a ^ sign_b;

    wire [3:0] sig_prod_wide = sig_a * sig_b; // 0..9

    assign sig_prod = sig_prod_wide;

    wire signed [3:0] pow_a_s = {2'b00, pow_a};
    wire signed [3:0] pow_b_s = {2'b00, pow_b};
    assign combined_exp = pow_a_s + pow_b_s - 4'sd2; // -2..2

endmodule
