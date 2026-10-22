// =====================================================================
// fp2_parallel_mac_ref_bounded_exact.v
//
// This module is a bounded-width alternative to
// fp2_parallel_mac_ref.v. It replaces the baseline design's 35-bit
// shifted-contribution intermediate with a smaller datapath while
// preserving the FP2 formats, two-lane arithmetic, accumulator
// behavior, and external interface.
//
// The bounded-width derivation is specific to the FP2 pair-MAC
// structure. Unlike the Posit(4,1) and FP4 MACs, which generate one
// product per cycle, this module generates two independent products:
//
//       lane0_product = a0 * w0
//       lane1_product = a1 * w1
//
// The two lane products are combined before applying the frac_bits
// scaling:
//
//       pair_sum_native = lane0_product + lane1_product
//
// This order is important because the lane products may have opposite
// signs and partially or completely cancel. Saturation detection must
// therefore be applied to the combined pair_sum_native value rather
// than to either lane individually.
//
// Applying saturation or limiting a lane before forming the exact
// two-lane sum would change the cancellation behavior and could produce
// an incorrect accumulated result.
//
// ---------------------------------------------------------------------
// Reachable FP2 contribution values
// ---------------------------------------------------------------------
//
// The decoded FP2 magnitude is represented as mag2x, corresponding to
// twice the true magnitude.
//
// For E1M0:
//
//       mag2x = {0, 1, 2}
//
// For E0M1:
//
//       mag2x = {0, 2, 3}
//
// The reachable signed single-lane product values are:
//
//       E1M0: {-4, -2, -1, 0, 1, 2, 4}
//
//       E0M1: {-9, -6, -4, 0, 4, 6, 9}
//
// Combining two lane products gives:
//
//       E1M0:
//           15 reachable pair_sum_native values
//           range: -8 to +8
//
//       E0M1:
//           25 reachable pair_sum_native values
//           range: -18 to +18
//
// The bounded-width calculation is based on these reachable combined
// values rather than on the individual lane-product ranges.
//
// ---------------------------------------------------------------------
// Maximum contribution in the normal path
// ---------------------------------------------------------------------
//
// A contribution is handled by the guaranteed-saturation path when its
// magnitude is at least 65,536. Such a contribution always saturates
// the signed 16-bit accumulator, whose range is -32,768 to +32,767,
// regardless of the accumulator's current value.
//
// Across the reachable pair_sum_native values and frac_bits settings,
// the largest contribution that can still enter the normal,
// non-guaranteed path has magnitude 61,440.
//
// One case producing this value is:
//
//       format          = E0M1
//       pair_sum_native = -15
//       frac_bits       = 14
//
// Since pair_sum_native is represented in the native x4 scale:
//
//       contribution magnitude = 15 * 2^(14 - 2)
//                              = 15 * 4,096
//                              = 61,440
//
// A magnitude of 61,440 requires 16 unsigned bits:
//
//       2^15 - 1 = 32,767 < 61,440
//       2^16 - 1 = 65,535 >= 61,440
//
// The normal-path contribution magnitude is therefore represented
// using an unsigned 16-bit field.
//
// ---------------------------------------------------------------------
// Signed addition width
// ---------------------------------------------------------------------
//
// The bounded contribution is combined with the signed 16-bit
// accumulator.
//
// The largest possible absolute pre-saturation sum is:
//
//       61,440 + 32,768 = 94,208
//
// An 18-bit signed value is sufficient:
//
//       signed 18-bit range = -131,072 to +131,071
//
// The normal accumulation path therefore uses an 18-bit signed adder,
// preventing wraparound before the final saturation decision.
//
// ---------------------------------------------------------------------
// Guaranteed-saturation test
// ---------------------------------------------------------------------
//
// Let magnitude be the absolute value of pair_sum_native and let shift
// be the contribution-scaling shift.
//
// The saturation condition is:
//
//       magnitude * 2^shift >= 65,536
//
// For shifts from 0 through 16, this is equivalent to:
//
//       magnitude >= (65,536 >> shift)
//
// Since 65,536 is a power of two, the threshold calculation is exact
// over this shift range.
//
// The remaining cases are handled as follows:
//
//   shift >= 16
//       Any nonzero magnitude guarantees saturation.
//
//   0 <= shift <= 16
//       Compare magnitude against:
//
//           65,536 >> shift
//
//   shift < 0
//       Saturation is not guaranteed because the contribution is being
//       reduced rather than increased.
//
// The shifted value is a fixed constant rather than a wide variable
// operand, keeping the comparison logic relatively small.
//
// ---------------------------------------------------------------------
// Preserved order of operations
// ---------------------------------------------------------------------
//
// The implementation follows the same arithmetic sequence as the
// baseline:
//
//   1. Decode both lanes using fp2_to_fp3.v.
//
//   2. Calculate both signed lane products.
//
//   3. Add the two lane products in the native x4 scale:
//
//          pair_sum_native = lane0_product + lane1_product
//
//   4. Apply guaranteed-saturation detection to the combined value.
//
//   5. For contributions that do not guarantee saturation:
//
//          - generate the scaled 16-bit unsigned magnitude;
//          - apply the contribution sign after extension;
//          - add it to the accumulator using the 18-bit signed path;
//          - apply signed 16-bit saturation.
//
// The scaling and negative-value handling follow the same
// shift-magnitude-then-apply-sign convention as the baseline, thereby
// preserving truncation toward zero.
//
// ---------------------------------------------------------------------
// Architectural compatibility
// ---------------------------------------------------------------------
//
// The optimization is limited to the combined-contribution and
// pre-saturation addition datapath.
//
// The design does not introduce:
//
//   - a shared or block exponent;
//   - per-lane saturation;
//   - a reduced-precision internal accumulator;
//   - post-accumulation normalization; or
//   - FP2 re-encoding.
//
// The following baseline behavior remains unchanged:
//
//   - E1M0 and E0M1 format support;
//   - strict 2-bit external operand encoding;
//   - independent lane-zero controls;
//   - cancellation between opposite-sign lane products;
//   - runtime frac_bits support;
//   - truncation toward zero;
//   - signed 16-bit saturating accumulation;
//   - acc_fxp8 generation;
//   - reset and clear behavior;
//   - valid_in and valid_out sequencing;
//   - one-cycle latency; and
//   - the external module interface.
//
// The fp2_to_fp3.v decode module is reused without modification.
// =====================================================================

module fp2_parallel_mac_ref_bounded_exact #(
    parameter ACC_W  = 16,
    parameter FRAC_W = 5
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      clear_acc,
    input  wire                      valid_in,
    input  wire                      fmt_sel,
    input  wire [FRAC_W-1:0]         frac_bits,
    input  wire [1:0]                a0, a1,
    input  wire [1:0]                w0, w1,
    input  wire                      a0_zero, a1_zero,
    input  wire                      w0_zero, w1_zero,
    output reg  signed [ACC_W-1:0]   acc,
    output reg                       valid_out,
    output reg                       overflow,
    output wire signed [7:0]         acc_fxp8
);

    // ---- typecast all four operands to internal FP3 -- UNCHANGED ----
    wire s_a0, e_a0, m_a0;
    wire s_a1, e_a1, m_a1;
    wire s_w0, e_w0, m_w0;
    wire s_w1, e_w1, m_w1;

    fp2_to_fp3 u_a0 (.sign_in(a0[1]), .bit_in(a0[0]), .zero_in(a0_zero), .fmt_sel(fmt_sel),
                      .fp3_sign(s_a0), .fp3_e(e_a0), .fp3_m(m_a0));
    fp2_to_fp3 u_a1 (.sign_in(a1[1]), .bit_in(a1[0]), .zero_in(a1_zero), .fmt_sel(fmt_sel),
                      .fp3_sign(s_a1), .fp3_e(e_a1), .fp3_m(m_a1));
    fp2_to_fp3 u_w0 (.sign_in(w0[1]), .bit_in(w0[0]), .zero_in(w0_zero), .fmt_sel(fmt_sel),
                      .fp3_sign(s_w0), .fp3_e(e_w0), .fp3_m(m_w0));
    fp2_to_fp3 u_w1 (.sign_in(w1[1]), .bit_in(w1[0]), .zero_in(w1_zero), .fmt_sel(fmt_sel),
                      .fp3_sign(s_w1), .fp3_e(e_w1), .fp3_m(m_w1));

    // ---- mag2x, lane products, combined sum -- UNCHANGED from baseline ----
    wire [1:0] mag2x_a0 = {e_a0, m_a0};
    wire [1:0] mag2x_a1 = {e_a1, m_a1};
    wire [1:0] mag2x_w0 = {e_w0, m_w0};
    wire [1:0] mag2x_w1 = {e_w1, m_w1};

    wire [3:0] prod0_mag = mag2x_a0 * mag2x_w0;   // 0..9
    wire [3:0] prod1_mag = mag2x_a1 * mag2x_w1;
    wire       prod0_sign = s_a0 ^ s_w0;
    wire       prod1_sign = s_a1 ^ s_w1;

    wire signed [5:0] p0_signed = prod0_sign ? -$signed({2'b00, prod0_mag}) : $signed({2'b00, prod0_mag});
    wire signed [5:0] p1_signed = prod1_sign ? -$signed({2'b00, prod1_mag}) : $signed({2'b00, prod1_mag});

    // ---- the combined, pre-scaling contribution -- the ONLY quantity
    // guaranteed-saturation detection and the bounded path are allowed
    // to look at (never either lane individually) ----
    wire signed [6:0] pair_sum_native = p0_signed + p1_signed;   // range -18..18, exact per the independent derivation above

    wire        pair_sum_sign      = pair_sum_native[6];
    wire [6:0]  pair_sum_magnitude = pair_sum_sign ? -pair_sum_native : pair_sum_native; // always >=0, max 18

    // ---- adaptive shift, same signed derivation as the baseline ----
    localparam SHIFT_W = FRAC_W + 3;
    localparam signed [SHIFT_W-1:0] SHIFT_OFFSET = 2;
    wire signed [SHIFT_W-1:0] shift_signed = $signed({3'b000, frac_bits}) - SHIFT_OFFSET; // frac_bits - 2, signed

    // ---- exact guaranteed-saturation test (see header derivation) ----
    // 65536 >> shift_signed shifts a CONSTANT, not pair_sum_magnitude --
    // cheap regardless of shift_signed's range. Only meaningful for
    // 0<=shift_signed<=16; the shift_signed>=16 and shift_signed<0
    // cases are handled as explicit separate conditions, matching the
    // exact three-way split verified in Python.
    wire [16:0] shrink_threshold = 17'd65536 >> shift_signed[4:0]; // valid only when 0<=shift_signed<=16; low 5 bits are sufficient since 16 fits in 5 bits and shift_signed's other cases are excluded below by construction
    wire [16:0] pair_sum_magnitude_ext = {10'b0, pair_sum_magnitude}; // zero-extend to shrink_threshold's full width -- comparing at shrink_threshold's narrow slice instead (an earlier revision did this) truncated values like 4096 down to 0, incorrectly forcing guaranteed_sat on nearly every case; caught by the standalone regression, not assumed correct
    localparam signed [SHIFT_W-1:0] THRESH_0  = 0;
    localparam signed [SHIFT_W-1:0] THRESH_16 = 16;
    wire guaranteed_sat =
        (pair_sum_magnitude != 7'd0) && (
            (shift_signed >= THRESH_16) ||
            (shift_signed >= THRESH_0 && pair_sum_magnitude_ext >= shrink_threshold)
        );

    // ---- bounded magnitude: exact 16-bit UNSIGNED capacity (0..61,440;
    // see header derivation). Declared plain unsigned, not signed --
    // 61,440 exceeds the signed 16-bit range and would misread as
    // negative under a naive signed interpretation, same reasoning as
    // FP4's bounded-exact module. Computed unconditionally, including
    // when guaranteed_sat is true, where its value is provably never
    // used (final mux bypasses it) -- same safety argument used
    // throughout this package's other bounded modules.
    wire [15:0] pair_sum_mag16 = {9'b0, pair_sum_magnitude}; // zero-extend, unsigned, no sign concerns
    wire [15:0] bounded_mag_wide =
        (shift_signed >= 0) ? (pair_sum_mag16 << shift_signed)
                             : (pair_sum_mag16 >> (-shift_signed));
    wire [15:0] bounded_mag = (pair_sum_magnitude == 7'd0) ? 16'd0 : bounded_mag_wide;

    // ---- 18-bit SIGNED contribution and accumulate ----
    // Zero-extend the UNSIGNED magnitude into the signed 18-bit field
    // FIRST, then apply the combined sign as a signed negation --
    // not the other way around (same convention as FP4's bounded-exact
    // module, for the same reason).
    localparam CONTRIB_W = 18; // exact minimum, see header derivation
    wire signed [CONTRIB_W-1:0] bounded_mag_zext = {2'b00, bounded_mag};
    wire signed [CONTRIB_W-1:0] contribution =
        pair_sum_sign ? -bounded_mag_zext : bounded_mag_zext;

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
        guaranteed_sat ? (pair_sum_sign ? SAT_MIN[ACC_W-1:0] : SAT_MAX[ACC_W-1:0])
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

    // ---- SIMULATION-ONLY usage-contract check: identical to the
    // baseline's, unchanged (frac_bits/fmt_sel must stay constant per
    // dot product). ----
    // synthesis translate_off
    reg [FRAC_W-1:0] frac_bits_latched;
    reg              fmt_sel_latched;
    reg              in_dot_product;

    initial begin
        in_dot_product = 1'b0;
        frac_bits_latched = {FRAC_W{1'b0}};
        fmt_sel_latched = 1'b0;
    end

    always @(posedge clk) begin
        if (valid_in) begin
            if (clear_acc) begin
                frac_bits_latched <= frac_bits;
                fmt_sel_latched   <= fmt_sel;
                in_dot_product    <= 1'b1;
            end else if (in_dot_product) begin
                if (frac_bits !== frac_bits_latched)
                    $display("WARNING [t=%0t]: frac_bits changed mid-accumulation (was %0d, now %0d) -- results are undefined per this module's usage contract",
                              $time, frac_bits_latched, frac_bits);
                if (fmt_sel !== fmt_sel_latched)
                    $display("WARNING [t=%0t]: fmt_sel changed mid-accumulation (was %0d, now %0d) -- results are undefined per this module's usage contract",
                              $time, fmt_sel_latched, fmt_sel);
            end
        end
    end
    // synthesis translate_on

    // ---- PARAMETER SAFETY GUARD ----
    generate
        if (FRAC_W != 5 || ACC_W != 16) begin : unsupported_parameters
            initial begin
                $display("ERROR: fp2_parallel_mac_ref_bounded_exact only supports FRAC_W=5, ACC_W=16 (got FRAC_W=%0d, ACC_W=%0d)", FRAC_W, ACC_W);
                $fatal(1, "fp2_parallel_mac_ref_bounded_exact: unsupported parameter combination");
            end
        end
    endgenerate

endmodule
