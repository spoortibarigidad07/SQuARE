// =====================================================================
// fp4_e2m1_decode.v
//
// This module provides the decode-only portion of fp4_e2m1_pp.v.
//
// It uses the same fp4_sig and fp4_pow functions and produces the
// following decoded values:
//
//   - sig_a;
//   - sig_b;
//   - pow_a;
//   - pow_b; and
//   - sign_prod.
//
// Unlike fp4_e2m1_pp.v, this module does not generate a fixed Q8.8
// partial product.
//
// In the original FP4 datapath, fp4_e2m1_pp.v first shifts the decoded
// significand product to a fixed Q8.8 scale. The wrapper then shifts
// the result again according to frac_bits.
//
// The optimized fp4_mac_ref_v2.v implementation avoids these two
// separate shift stages. It uses the decoded exponent and significand
// information from this module to calculate the final shift directly:
//
//       combined_shift = pow_a + pow_b - 2 + frac_bits
//
// The significand product is then shifted once using the combined
// shift amount.
//
// The original fp4_e2m1_pp.v module remains unchanged and continues to
// be used by:
//
//   - sparx_mac_unified.v;
//   - sparx_mac_unified_v2.v; and
//   - fp4_mac_ref.v.
//
// This module is therefore an additional decode path for the optimized
// FP4 MAC implementation. It does not replace or modify the original
// preprocessing module.
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

    // Identical to fp4_e2m1_pp.v's fp4_sig / fp4_pow functions (copied
    // verbatim, not re-derived), EXCEPT sized to the width the values
    // actually need: fp4_sig only ever returns {0,1,2,3} (2 bits'
    // worth), not the 3 bits originally declared -- the original width
    // left a permanently-zero MSB on sig_a/sig_b and forced a wider
    // (3-bit x 3-bit) multiply than the values require. Numerically
    // identical; only the declared widths changed.
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

    // 2-bit x 2-bit product needs 4 bits at most (max 3*3=9=4'b1001),
    // not the 6 bits a naive 3-bit x 3-bit multiply would have used.
    wire [3:0] sig_prod_wide = sig_a * sig_b; // 0..9

    assign sig_prod = sig_prod_wide;

    wire signed [3:0] pow_a_s = {2'b00, pow_a};
    wire signed [3:0] pow_b_s = {2'b00, pow_b};
    assign combined_exp = pow_a_s + pow_b_s - 4'sd2; // -2..2

endmodule
