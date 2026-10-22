// =====================================================================
// fp4_x_fp2_pp.v
// FP4(E2M1) x FP2-element(E1M0/E0M1) combinational partial product --
// the workhorse of Dang et al.'s "FP4xFP2 Processing Unit" (Sec. IV-D):
// activations kept at FP4, weights compressed to FP2. This is the
// paper's "one common application scenario for the FP2 format" (weight
// compression while keeping FP4 activations).
//
// Computed EXACTLY (integer SIG_f * SIG_w), not via the paper's
// bitwise-add approximation -- see docs/DESIGN_NOTES.md Sec. 3 for why,
// and what a bitwise-add fast-path variant would take to add.
//
// Both operands are represented internally on the same footing used
// throughout this package: value = SIG * 2^(pow_exp - 1), SIG in
// {0,1,2,3}. For the FP2 element side pow_exp is always 0 (its native
// scale is fixed at 2^-1), which simplifies the combined exponent to
// pow_f - 2.
//
// Output pre-scaled to GLOBAL_FRAC_BITS = 8, matching the rest of this
// package's shared-accumulator convention.
// =====================================================================
module fp4_x_fp2_pp #(
    parameter ACC_W = 32
)(
    input  wire [3:0]        f,      // FP4 code {sign, e[1:0], m}
    input  wire [3:0]        w,      // FP2 element code {sign,mode,zero,b}
    output wire               sign_prod,
    output wire [ACC_W-1:0]   partial
);
    localparam GLOBAL_EXTRA_SHIFT = 6; // 8 - native FRAC_BITS(2)

    // -- FP4 operand decode (identical math to fp4_e2m1_pp.v) --
    wire       sign_f = f[3];
    wire [1:0] e_f    = f[2:1];
    wire       m_f    = f[0];

    function [2:0] fp4_sig;
        input [1:0] e;
        input       m;
        begin
            fp4_sig = (e == 2'b00) ? {2'b00, m} : (3'd2 + m);
        end
    endfunction

    function [1:0] fp4_pow;
        input [1:0] e;
        begin
            fp4_pow = (e == 2'b00) ? 2'b00 : (e - 2'b01);
        end
    endfunction

    wire [2:0] sig_f = fp4_sig(e_f, m_f);
    wire [1:0] pow_f = fp4_pow(e_f);

    // -- FP2 element operand decode (identical math to fp2_pp.v; pow is
    //    fixed at 0 for this format's native scale) --
    wire sign_w = w[3], mode_w = w[2], zero_w = w[1], bit_w = w[0];

    function [1:0] fp2_mag2x;
        input mode;
        input z;
        input bitv;
        begin
            if (z)
                fp2_mag2x = 2'd0;
            else if (mode == 1'b0)
                fp2_mag2x = bitv ? 2'd1 : 2'd2;
            else
                fp2_mag2x = bitv ? 2'd3 : 2'd2;
        end
    endfunction

    wire [1:0] sig_w = fp2_mag2x(mode_w, zero_w, bit_w); // pow_w == 0 always

    assign sign_prod = sign_f ^ sign_w;

    wire [5:0] sig_prod = sig_f * sig_w;               // 0..9

    wire signed [3:0] pow_f_s      = {2'b00, pow_f};
    wire signed [3:0] combined_exp = pow_f_s - 4'sd2;  // pow_w=0 => range -2..0

    wire [2:0] shift_amt   = combined_exp + 4'sd2;      // 0..2 (nonneg)
    wire [6:0] total_shift = shift_amt + GLOBAL_EXTRA_SHIFT; // 6..8

    assign partial = {{(ACC_W-6){1'b0}}, sig_prod} << total_shift;

endmodule
