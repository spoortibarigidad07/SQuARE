// =====================================================================
// fp4_mac_ref.v
//
// Standalone, complete FP4 (E2M1) MAC: partial-product generator
// (fp4_e2m1_pp.v) plus its OWN dedicated accumulator register -- not
// multiplexed with any other format. Provided for the same reason as
// posit4_mac_ref.v: fair, apples-to-apples synthesis/utilization/
// power comparison against another paper's dedicated FP4 MAC, with no
// shared-mux logic contributing to its gate count or power number.
//
// ---- ACC_W=16 default + saturation, same rationale as posit4_mac_ref.v ----
// Previously defaulted ACC_W=32 (inconsistent with this package's other
// "adaptive fxp" modules, which all default to 16). Fixed: ACC_W now
// defaults to 16. Narrowing without addressing overflow would be a
// regression, not just a bit-width tweak -- at frac_bits=12, 56/256
// exhaustive single-shot FP4 products already exceed +-32767, not a
// rare corner case at this width. Matching fp2_parallel_mac_ref.v's
// precedent, this accumulator now SATURATES at +32767/-32768 rather
// than silently wrapping, with a per-cycle `overflow` flag (meaningful
// exactly when valid_out=1, cleared to 0 when valid_in=0).
//
// ---- Adaptive frac_bits (fp4_e2m1_pp.v itself UNCHANGED) ----
// Same approach as posit4_mac_ref.v: fp4_e2m1_pp.v always emits
// `partial` pre-scaled to a FIXED Q8.8 convention (its own internal
// `GLOBAL_EXTRA_SHIFT=6` constant) -- left untouched, already
// exhaustively tested. This wrapper applies an additional rescale on
// top, `frac_bits - 8`, so frac_bits=8 reproduces the original fixed
// behavior exactly (rescale is a no-op). Right-shifts (frac_bits<8)
// truncate, no rounding added.
// =====================================================================
// ---- fxp8 output (MSB-8 window), recommended for consistency with FP2 ----
// The mentor specified Posit(4,1)=fxp16 and FP2=fxp8 (MSB-8 window over
// a wider internal computation), explicitly leaving FP4's choice open.
// Recommendation adopted here: match FP2's fxp8-MSB-window convention,
// not Posit4's fxp16. Rationale -- the mentor's Posit4-vs-FP2 split
// tracks each format's DYNAMIC RANGE: Posit4 spans a genuinely
// exponential range (0.0625 to 16, a 256x ratio), which benefits from
// more accumulator headroom; FP2 spans a tight range close to 1 (0.5 to
// 1.5, E1M0, or 1 to 1.5, E0M1 -- at most 3x). FP4's range (0.5 to 6,
// 12x) sits much closer to FP2's end of that spectrum than to Posit4's
// -- so the same reasoning that justifies FP2's narrower fxp8 output
// applies to FP4 too, more than the reasoning for Posit4's wider fxp16
// does. `acc` (unchanged, 16-bit by default) remains the full-precision
// internal result, exactly as before; `acc_fxp8` is the new, additional
// MSB-8 window, computed the same way as fp2_parallel_mac_ref.v's (a
// bit-selection of an already-in-range value, no separate saturation or
// rounding needed at this stage).
// =====================================================================
module fp4_mac_ref #(
    parameter ACC_W  = 16,   // adaptive fxp16 default; override for a wider accumulator
    parameter FRAC_W = 5     // width of the frac_bits input port (0..31)
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear_acc,
    input  wire                     valid_in,
    input  wire [FRAC_W-1:0]        frac_bits,   // adaptive; must stay constant per dot product
    input  wire [3:0]               a,
    input  wire [3:0]               b,
    output reg  signed [ACC_W-1:0]  acc,
    output reg                       valid_out,
    output reg                       overflow,     // this cycle's result saturated; 0 whenever valid_out=0
    output wire signed [7:0]         acc_fxp8      // NEW: MSB-8 window over acc (see header note)
);

    // fp4_e2m1_pp.v's own native Q8.8 computation is bounded (max
    // 9216 at frac_bits=8, fitting in 16 bits) but instantiating it
    // with a FIXED, generous native width regardless of this wrapper's
    // (possibly narrower) ACC_W is the same defensive pattern applied
    // in posit4_mac_ref.v (where relying on "just barely fits" was
    // exactly the bug -- Posit4's native computation needs 17 bits,
    // silently truncating to 0 at ACC_W=16 in an earlier revision).
    localparam PP_NATIVE_W = 32;

    wire                    sign_prod;
    wire [PP_NATIVE_W-1:0]  partial;

    fp4_e2m1_pp #(.ACC_W(PP_NATIVE_W)) u_fp4_pp (
        .a(a), .b(b),
        .sign_prod(sign_prod), .partial(partial)
    );

    // ---- adaptive rescale: fixed-Q8.8 partial -> requested frac_bits ----
    // partial_adaptive_wide is kept at FULL WIDE_W width all the way
    // through the sum and saturation check below -- truncating it down
    // to ACC_W bits here (as an earlier, buggy revision did) would
    // silently corrupt any single-shot product that needs more than
    // ACC_W bits before saturation ever gets a chance to see the true
    // magnitude.
    localparam WIDE_W = PP_NATIVE_W + 24;
    wire signed [FRAC_W+2:0] rescale_shift = $signed({3'b000, frac_bits}) - 8'sd8;
    wire signed [WIDE_W-1:0] partial_ext = {{(WIDE_W-PP_NATIVE_W){1'b0}}, partial};
    wire signed [WIDE_W-1:0] partial_adaptive_wide =
        (rescale_shift >= 0) ? (partial_ext <<< rescale_shift)
                              : (partial_ext >>> (-rescale_shift));

    // ---- saturating accumulate (full WIDE_W precision until the
    // final, post-saturation truncation to ACC_W bits) ----
    wire signed [WIDE_W-1:0] partial_signed =
        sign_prod ? -partial_adaptive_wide : partial_adaptive_wide;
    wire signed [WIDE_W-1:0] acc_ext  = {{(WIDE_W-ACC_W){acc[ACC_W-1]}}, acc};
    wire signed [WIDE_W-1:0] sum_wide = clear_acc ? partial_signed : (acc_ext + partial_signed);

    localparam signed [WIDE_W-1:0] SAT_MAX = (1 <<< (ACC_W-1)) - 1;
    localparam signed [WIDE_W-1:0] SAT_MIN = -(1 <<< (ACC_W-1));

    wire ovf_pos = (sum_wide > SAT_MAX);
    wire ovf_neg = (sum_wide < SAT_MIN);
    wire signed [ACC_W-1:0] sum_saturated =
        ovf_pos ? SAT_MAX[ACC_W-1:0] :
        ovf_neg ? SAT_MIN[ACC_W-1:0] :
                  sum_wide[ACC_W-1:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc       <= {ACC_W{1'b0}};
            valid_out <= 1'b0;
            overflow  <= 1'b0;
        end else begin
            if (valid_in) begin
                acc       <= sum_saturated;
                overflow  <= ovf_pos | ovf_neg;
                valid_out <= 1'b1;
            end else begin
                valid_out <= 1'b0;
                overflow  <= 1'b0;
            end
        end
    end

    // ---- fxp8 MSB-window derived output (see header note) ----
    assign acc_fxp8 = acc[ACC_W-1:ACC_W-8];

endmodule
