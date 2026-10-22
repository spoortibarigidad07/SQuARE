// =====================================================================
// fp2_block_scale_apply.v
//
// Applies a 32-element FP2 block's shared exponent X (or the combined
// X_activation + X_weight from fp2_block_exp_adder, see fp2_pp.v) to a
// block's completed fixed-point accumulation. This matches Dang et
// al.'s own architectural claim (Sec. IV-B): the shared exponent is
// added ONCE per 32-element block, not per element -- "X introduces
// minimal extra overhead in the spatial MAC section and no additional
// latency" -- because X is just an exponent multiplying the WHOLE
// block dot-product, applied after all (up to 16, via
// fp2_pair_mac_fp4xfp2 / fp2xfp2) per-pair partial sums for that block
// have already been accumulated.
//
// block_acc   : signed fixed-point sum of all element products in this
//               block (e.g. the final `acc` from N calls into
//               fp2_pair_mac_fp4xfp2 / fp2xfp2 for one 32-element
//               block), LSB = 2^-GLOBAL_FRAC_BITS.
// x_shared    : combined block exponent (unsigned), typically the sum
//               of the activation and weight block's shared max-
//               exponent fields (fp2_pp.v's fp2_block_exp_adder).
// block_result: block_acc arithmetically left-shifted by x_shared,
//               i.e. the fully block-scaled dot-product result.
// =====================================================================
module fp2_block_scale_apply #(
    parameter ACC_W = 32,
    parameter OUT_W = 48
)(
    input  wire signed [ACC_W-1:0] block_acc,
    input  wire        [7:0]       x_shared,
    output wire signed [OUT_W-1:0] block_result
);
    localparam MAX_SHIFT = OUT_W - ACC_W;

    // Saturate the shift amount so it never exceeds what OUT_W can
    // represent without further loss beyond the accumulator's own
    // native precision (documented limitation, not silent truncation).
    wire [7:0] shift_amt = (x_shared > MAX_SHIFT[7:0]) ? MAX_SHIFT[7:0] : x_shared;

    wire signed [OUT_W-1:0] sign_extended =
        {{(OUT_W-ACC_W){block_acc[ACC_W-1]}}, block_acc};

    assign block_result = sign_extended <<< shift_amt;

endmodule
