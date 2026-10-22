// =====================================================================
// fp4_mac_ref_v2_bounded_exact.v
//
// This module is a tighter bounded-width alternative to
// fp4_mac_ref_v2.v.
//
// The earlier bounded implementation,
// fp4_mac_ref_v2_bounded.v, is retained unchanged as a conservative
// reference. This version improves the guaranteed-saturation decision
// by considering both the combined shift and the actual significand
// product.
//
// The v1 implementation treats every nonzero product with
// combined_shift >= 16 as guaranteed to saturate. This condition is
// correct but conservative because some larger significand products
// also guarantee saturation at combined_shift values of 13, 14, and
// 15.
//
// ---------------------------------------------------------------------
// Product-aware guaranteed-saturation condition
// ---------------------------------------------------------------------
//
// The possible FP4 significand-product values are:
//
//       {0, 1, 2, 3, 4, 6, 9}
//
// A contribution is guaranteed to saturate the signed 16-bit
// accumulator when its magnitude is at least 65,536. This gives the
// following exact conditions:
//
//   combined_shift >= 16
//       Guaranteed for every nonzero sig_prod.
//
//   combined_shift == 15
//       Guaranteed when sig_prod >= 2.
//
//   combined_shift == 14
//       Guaranteed when sig_prod >= 4.
//
//   combined_shift == 13
//       Guaranteed when sig_prod >= 8.
//
//       Among the supported significand products, only sig_prod = 9
//       satisfies this condition.
//
//   combined_shift <= 12
//       Saturation is not guaranteed solely from the contribution.
//
// These conditions are equivalent to checking:
//
//       sig_prod * 2^combined_shift >= 65,536
//
// for every supported sig_prod and combined_shift combination.
//
// ---------------------------------------------------------------------
// Maximum contribution entering the normal addition path
// ---------------------------------------------------------------------
//
// Under the product-aware saturation rule, the largest contribution
// that is not handled by the guaranteed-saturation path is 49,152.
//
// This value can be produced by either:
//
//       sig_prod = 6, combined_shift = 13
//
// or:
//
//       sig_prod = 3, combined_shift = 14
//
// since:
//
//       6 * 2^13 = 49,152
//       3 * 2^14 = 49,152
//
// The bounded magnitude therefore requires 16 unsigned bits:
//
//       2^15 - 1 = 32,767 < 49,152
//       2^16 - 1 = 65,535 >= 49,152
//
// ---------------------------------------------------------------------
// Signed addition width
// ---------------------------------------------------------------------
//
// The bounded contribution is added to the signed 16-bit accumulator,
// whose range is -32,768 to +32,767.
//
// The limiting combinations are:
//
//       +49,152 + 32,767  =  81,919
//       +49,152 - 32,768  =  16,384
//       -49,152 + 32,767  = -16,385
//       -49,152 - 32,768  = -81,920
//
// The largest absolute result is 81,920. An 18-bit signed value is
// sufficient to represent the complete pre-saturation sum:
//
//       signed 18-bit range = -131,072 to +131,071
//
// The normal addition path therefore uses an 18-bit signed adder.
//
// ---------------------------------------------------------------------
// Unsigned bounded-magnitude representation
// ---------------------------------------------------------------------
//
// The bounded magnitude is declared as an unsigned 16-bit value.
//
// This is necessary because the largest normal-path magnitude, 49,152,
// is greater than the maximum positive signed 16-bit value of 32,767.
// For example:
//
//       49,152 = 16'hC000
//
// If 16'hC000 were interpreted as a signed 16-bit value, it would
// represent -16,384 rather than +49,152.
//
// The magnitude is therefore:
//
//   1. stored as an unsigned 16-bit value;
//   2. zero-extended into the 18-bit signed contribution field; and
//   3. negated only after extension when the product sign is negative.
//
// This ensures that the magnitude remains non-negative until the
// product sign is applied.
//
// ---------------------------------------------------------------------
// Architectural compatibility
// ---------------------------------------------------------------------
//
// The optimization is limited to the contribution-generation and
// pre-saturation addition datapath.
//
// The design does not introduce:
//
//   - a shared or block exponent;
//   - a reduced-precision internal accumulator;
//   - post-accumulation normalization; or
//   - FP4 re-encoding.
//
// The signed 16-bit adaptive fixed-point accumulator, interface,
// control behavior, rounding, saturation semantics, and one-cycle
// latency remain unchanged.
//
// The existing fp4_e2m1_decode.v module is reused without
// modification.
// =====================================================================
module fp4_mac_ref_v2_bounded_exact #(
    parameter ACC_W  = 16,
    parameter FRAC_W = 5
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear_acc,
    input  wire                     valid_in,
    input  wire [FRAC_W-1:0]        frac_bits,
    input  wire [3:0]               a,
    input  wire [3:0]               b,
    output reg  signed [ACC_W-1:0]  acc,
    output reg                       valid_out,
    output reg                       overflow,
    output wire signed [7:0]         acc_fxp8
);

    wire               sign_prod;
    wire [3:0]          sig_prod;     // 0..9
    wire signed [3:0]   combined_exp; // -2..2

    fp4_e2m1_decode u_decode (
        .a(a), .b(b),
        .sign_prod(sign_prod), .sig_prod(sig_prod), .combined_exp(combined_exp)
    );

    // ---- combined shift: identical derivation to the baseline and v1 ----
    localparam SHIFT_W = FRAC_W + 3;
    wire signed [SHIFT_W-1:0] combined_exp_ext = {{(SHIFT_W-4){combined_exp[3]}}, combined_exp};
    wire signed [SHIFT_W-1:0] frac_bits_ext    = {{(SHIFT_W-FRAC_W){1'b0}}, frac_bits};
    wire signed [SHIFT_W-1:0] combined_shift    = combined_exp_ext + frac_bits_ext;

    // ---- exact, product-aware guaranteed-saturation detection ----
    // (see header for the independent re-verification of this table
    // against the literal magnitude>=65536 threshold)
    //
    // Threshold constants are explicitly sized to SHIFT_W bits (not
    // hardcoded literal widths like `16'sd16`) so they match
    // combined_shift's actual declared width exactly -- Verilator's
    // lint (-Wall) flagged the original mismatched-width comparisons
    // (WIDTHEXPAND); Verilog's automatic sign-extension made them
    // functionally correct regardless (confirmed by the exhaustive
    // cross-check results), but explicit matching widths is cleaner
    // and avoids relying on implicit extension. Values 13-16 are
    // comfortably within SHIFT_W's signed range at the default
    // FRAC_W=5 (SHIFT_W=8, range -128..127) -- verified in Python
    // before use, learning from the earlier 4'sd8 literal-overflow bug
    // elsewhere in this project (a value that WAS too wide for its
    // declared width).
    localparam signed [SHIFT_W-1:0] THRESH_13 = 13;
    localparam signed [SHIFT_W-1:0] THRESH_14 = 14;
    localparam signed [SHIFT_W-1:0] THRESH_15 = 15;
    localparam signed [SHIFT_W-1:0] THRESH_16 = 16;
    wire guaranteed_sat =
        (sig_prod != 4'd0) && (
            (combined_shift >= THRESH_16) ||
            (combined_shift == THRESH_15 && sig_prod >= 4'd2) ||
            (combined_shift == THRESH_14 && sig_prod >= 4'd4) ||
            (combined_shift == THRESH_13 && sig_prod >= 4'd8)
        );

    // ---- bounded magnitude: exact 16-bit UNSIGNED capacity (0..49,152;
    // see header derivation). Declared plain unsigned, NOT signed --
    // see header for why this distinction is load-bearing here (49,152
    // would misread as negative under a naive signed interpretation).
    // Computed unconditionally, including when guaranteed_sat is true,
    // where its value is provably never used (final mux bypasses it) --
    // same safety argument as v1 and posit4_mac_ref_v2_bounded.v.
    wire [15:0] sig_prod_ext = {12'b0, sig_prod}; // plain unsigned zero-extend, no sign concerns
    wire [15:0] bounded_mag_wide =
        (combined_shift >= 0) ? (sig_prod_ext << combined_shift)
                               : (sig_prod_ext >> (-combined_shift));
    wire [15:0] bounded_mag = (sig_prod == 4'd0) ? 16'd0 : bounded_mag_wide;

    // ---- 18-bit SIGNED contribution and accumulate ----
    // Zero-extend the UNSIGNED magnitude into the signed 18-bit field
    // FIRST (a plain, unsigned-safe concatenation -- bounded_mag is
    // always representationally non-negative, so this zero-extension
    // is exact regardless of its numeric value), THEN apply the
    // product sign as a signed negation -- not the other way around.
    localparam CONTRIB_W = 18; // exact minimum, see header derivation (no extra headroom)
    wire signed [CONTRIB_W-1:0] bounded_mag_zext = {2'b00, bounded_mag}; // unsigned->signed-field zero-extend, still non-negative
    wire signed [CONTRIB_W-1:0] contribution =
        sign_prod ? -bounded_mag_zext : bounded_mag_zext;

    wire signed [ACC_W-1:0]      base_acc     = clear_acc ? {ACC_W{1'b0}} : acc;
    wire signed [CONTRIB_W-1:0]  base_acc_ext = {{(CONTRIB_W-ACC_W){base_acc[ACC_W-1]}}, base_acc};
    wire signed [CONTRIB_W-1:0]  sum_bounded  = base_acc_ext + contribution;

    localparam signed [CONTRIB_W-1:0] SAT_MAX = (1 <<< (ACC_W-1)) - 1;
    localparam signed [CONTRIB_W-1:0] SAT_MIN = -(1 <<< (ACC_W-1));

    wire ovf_pos_normal = (sum_bounded > SAT_MAX);
    wire ovf_neg_normal = (sum_bounded < SAT_MIN);
    wire signed [ACC_W-1:0] sum_saturated_normal =
        ovf_pos_normal ? SAT_MAX[ACC_W-1:0] :
        ovf_neg_normal ? SAT_MIN[ACC_W-1:0] :
                          sum_bounded[ACC_W-1:0];

    wire signed [ACC_W-1:0] sum_saturated =
        guaranteed_sat ? (sign_prod ? SAT_MIN[ACC_W-1:0] : SAT_MAX[ACC_W-1:0])
                        : sum_saturated_normal;
    wire ovf_final = guaranteed_sat ? 1'b1 : (ovf_pos_normal | ovf_neg_normal);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc       <= {ACC_W{1'b0}};
            valid_out <= 1'b0;
            overflow  <= 1'b0;
        end else begin
            if (valid_in) begin
                acc       <= sum_saturated;
                overflow  <= ovf_final;
                valid_out <= 1'b1;
            end else begin
                valid_out <= 1'b0;
                overflow  <= 1'b0;
            end
        end
    end

    assign acc_fxp8 = acc[ACC_W-1:ACC_W-8];

    // ---- PARAMETER SAFETY GUARD ----
    // Verified correct ONLY for the default FRAC_W=5, ACC_W=16 -- both
    // the exact-detection thresholds and the 16/18-bit derivation are
    // tied to ACC_W=16 (2^16=65536 is the saturation threshold itself)
    // and to FP4's specific sig_prod range. Same form as v1 and
    // posit4_mac_ref_v2_bounded.v; Vivado/Genus untested against this
    // construct in any of the three modules.
    generate
        if (FRAC_W != 5 || ACC_W != 16) begin : unsupported_parameters
            initial begin
                $display("ERROR: fp4_mac_ref_v2_bounded_exact only supports FRAC_W=5, ACC_W=16 (got FRAC_W=%0d, ACC_W=%0d)", FRAC_W, ACC_W);
                $fatal(1, "fp4_mac_ref_v2_bounded_exact: unsupported parameter combination");
            end
        end
    endgenerate

endmodule
