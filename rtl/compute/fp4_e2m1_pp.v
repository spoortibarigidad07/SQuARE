// =====================================================================
// fp4_e2m1_pp.v
// FP4 (E2M1, bias=1) partial-product generator (combinational).
//
// Encoding (4 bits): {sign, exp[1:0], mant[0]}
// Magnitude set (bias=1): {0, 0.5, 1, 1.5, 2, 3, 4, 6}
//   e==0 (subnormal): value = m * 2^(1-bias) * 0.5-step -> {0, 0.5}
//   e!=0 (normal)    : value = (1 + 0.5*m) * 2^(e-bias)
//
// Internally represented as SIG in {0,1,2,3} (= 2 * significand) and
// pow_exp in {0,1,2}, so value = SIG * 2^(pow_exp-1) exactly (integer
// SIG, no rounding). This makes the multiply an exact small integer
// multiply (SIG_a * SIG_b, 0..9) plus an exponent add -- no floating
// rounding error is introduced by this MAC (unlike the bitwise-add
// approximation in Dang et al. TCAS-I'26, which we do NOT replicate
// here in favour of bit-exact correctness; see docs/DESIGN_NOTES.md
// for the optional bitwise-add fast-path).
//
// Output `partial` is pre-scaled to the GLOBAL fixed-point scale used
// by sparx_mac_unified.v (GLOBAL_FRAC_BITS = 8): the format's native
// scale is 2^2 (FRAC_BITS=2), so an extra <<6 aligns it to 2^8.
// =====================================================================
module fp4_e2m1_pp #(
    parameter ACC_W = 32
)(
    input  wire [3:0]        a,   // {sign, e[1:0], m}
    input  wire [3:0]        b,
    output wire               sign_prod,
    output wire [ACC_W-1:0]   partial
);

    localparam GLOBAL_EXTRA_SHIFT = 6; // 8 - native FRAC_BITS(2)

    wire       sign_a = a[3];
    wire [1:0] e_a    = a[2:1];
    wire       m_a    = a[0];
    wire       sign_b = b[3];
    wire [1:0] e_b    = b[2:1];
    wire       m_b    = b[0];

    function [2:0] fp4_sig; // SIG in {0,1,2,3}
        input [1:0] e;
        input       m;
        begin
            if (e == 2'b00)
                fp4_sig = {2'b00, m};
            else
                fp4_sig = 3'd2 + m;
        end
    endfunction

    function [1:0] fp4_pow; // pow_exp in {0,1,2}
        input [1:0] e;
        begin
            fp4_pow = (e == 2'b00) ? 2'b00 : (e - 2'b01);
        end
    endfunction

    wire [2:0] sig_a = fp4_sig(e_a, m_a);
    wire [2:0] sig_b = fp4_sig(e_b, m_b);
    wire [1:0] pow_a = fp4_pow(e_a);
    wire [1:0] pow_b = fp4_pow(e_b);

    assign sign_prod = sign_a ^ sign_b;

    wire [5:0] sig_prod = sig_a * sig_b;                 // 0..9

    wire signed [3:0] pow_a_s = {2'b00, pow_a};
    wire signed [3:0] pow_b_s = {2'b00, pow_b};
    wire signed [3:0] combined_exp = pow_a_s + pow_b_s - 4'sd2; // -2..2

    wire [2:0] shift_amt = combined_exp + 4'sd2;         // 0..4 (nonneg)
    wire [6:0] total_shift = shift_amt + GLOBAL_EXTRA_SHIFT; // 6..10

    assign partial = {{(ACC_W-6){1'b0}}, sig_prod} << total_shift;

endmodule
