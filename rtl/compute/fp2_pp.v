// =====================================================================
// fp2_pp.v
// FP2 (Dang et al., TCAS-I'26) ELEMENT-LEVEL partial-product generator.
//
// *** SCOPE, READ BEFORE USE ***
// This module computes the product of two ALREADY-UNPACKED FP2 values.
// It does NOT implement the paper's actual storage format, which packs
// TWO floating-point values into a single 4-bit encoding space (Table I
// of the paper) to achieve the claimed 2-bit-per-value density. That
// pack/unpack datapath -- and the two hardware processing units built
// on top of it (FP4xFP2, Sec. IV-D, and FP2xFP2, Sec. IV-E) -- live in
// fp2_pair_unpack.v, fp4_x_fp2_pp.v, fp2_pair_mac_fp4xfp2.v and
// fp2_pair_mac_fp2xfp2.v. Use those for a paper-faithful "complete" FP2
// MAC; this file is the per-element primitive they are built on.
//
// NOTE ON SCOPE: FP2's storage-side compression packs TWO adjacent
// weights sharing 1 sign/exp-or-mant bit into a 4-bit slot, plus a
// per-BLOCK (32-element) shared scale X. That block-level scale is a
// pure exponent-add handled once per block by block_exp_adder.v, fully
// decoupled from the element datapath (this is exactly how Dang et al.
// architect it in Sec. IV-B: "Separate the storage of the shared scale
// X from the data itself... an independent compute channel for X").
// This module implements the PER-ELEMENT magnitude arithmetic that
// runs inside every PE lane; block_exp_adder.v supplies the exponent
// that a downstream stage uses to align/rescale the lane's partial
// sum before it is added into the block accumulator.
//
// Per-element encoding (4 bits): {sign, mode, zero, b}
//   mode=0 -> FP2-E1M0 : b=0 -> 1.0   b=1 -> 0.5
//   mode=1 -> FP2-E0M1 : b=0 -> 1.0   b=1 -> 1.5
// (matches quantization steps scale*{0,+/-0.5,+/-1} and scale*{0,+/-1,+/-1.5}
//  from Eq.1 of the FP2 paper, with "scale" = the block exponent X)
//
// Mixed-mode multiply (E1M0 x E0M1) is supported natively since each
// operand carries its own mode bit (Sec. IV-F of the FP2 paper).
//
// Output `partial` is pre-scaled to GLOBAL_FRAC_BITS = 8 (native format
// scale is 2^2, so an extra <<6 aligns it, identical convention to
// fp4_e2m1_pp.v).
// =====================================================================
module fp2_pp #(
    parameter ACC_W = 32
)(
    input  wire [3:0]        a,      // {sign, mode, zero, b}
    input  wire [3:0]        b_in,
    output wire               sign_prod,
    output wire [ACC_W-1:0]   partial
);

    localparam GLOBAL_EXTRA_SHIFT = 6; // 8 - native FRAC_BITS(2)

    wire sign_a = a[3],    mode_a = a[2],    zero_a = a[1],    bit_a = a[0];
    wire sign_b = b_in[3], mode_b = b_in[2], zero_b = b_in[1], bit_b = b_in[0];

    // magnitude x2 (so all values are small integers: {0,1,2,3})
    function [1:0] fp2_mag2x;
        input mode;
        input z;
        input bitv;
        begin
            if (z)
                fp2_mag2x = 2'd0;
            else if (mode == 1'b0)          // E1M0
                fp2_mag2x = bitv ? 2'd1 : 2'd2;
            else                             // E0M1
                fp2_mag2x = bitv ? 2'd3 : 2'd2;
        end
    endfunction

    wire [1:0] mag_a = fp2_mag2x(mode_a, zero_a, bit_a);
    wire [1:0] mag_b = fp2_mag2x(mode_b, zero_b, bit_b);

    assign sign_prod = sign_a ^ sign_b;

    wire [3:0] prod = mag_a * mag_b;    // 0..9 ; represents (real*4)

    assign partial = {{(ACC_W-4){1'b0}}, prod} << GLOBAL_EXTRA_SHIFT;

endmodule

// ---------------------------------------------------------------------
// block_exp_adder.v-equivalent (kept in this file for convenience):
// combines two 8-bit block-shared exponents X_a, X_b -- pure adder,
// evaluated once per 32-element block rather than per PE lane.
// ---------------------------------------------------------------------
module fp2_block_exp_adder (
    input  wire [7:0] x_a,
    input  wire [7:0] x_b,
    output wire [8:0] x_sum
);
    assign x_sum = x_a + x_b;
endmodule
