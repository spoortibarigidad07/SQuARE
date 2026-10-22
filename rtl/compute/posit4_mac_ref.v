// =====================================================================
// posit4_mac_ref.v
//
// Standalone, complete Posit(4,es=1) MAC: partial-product generator
// (posit4_es1_pp.v) plus its OWN dedicated accumulator register --
// not multiplexed with any other format. Provided specifically for
// fair, apples-to-apples synthesis/utilization/power comparison
// against another paper's dedicated Posit MAC, mirroring
// fp2_parallel_mac_ref.v's role for the parallel FP2 MAC (which was
// always structured this way). `sparx_mac_unified`/`_v2` remain the
// right choice when you actually need runtime mode-switching in one
// PE lane; this module is the right choice when you want Posit(4,1)
// in complete isolation, with no shared-mux logic contributing to its
// gate count or power number.
//
// ---- ACC_W=16 default, matching "adaptive fxp16" everywhere else ----
// A previous revision defaulted ACC_W=32, inherited unchanged from the
// original sparx_mac_unified.v convention -- inconsistent with this
// package's other "adaptive fxp" modules (fp2_parallel_mac_ref.v,
// sparx_mac_unified_v2.v's FP2P_ACC_W), which all default to 16. Fixed
// here: ACC_W now defaults to 16, so this module is fxp16 out of the
// box, matching what a final comparison table would actually want.
// ACC_W remains a parameter, so `.ACC_W(32)` still works if you
// specifically want the wider, original behavior.
//
// ---- Saturating, not wrapping, at fxp16 (a real correctness decision,
// not just a width change) ----
// Narrowing the accumulator from 32 to 16 bits without addressing
// overflow would be a REGRESSION, not just a bit-width tweak: at
// frac_bits=8 alone, 4 of the 256 exhaustive single-shot Posit4
// products already exceed +-32767 (e.g. 16*16=256 real x 2^8=65536),
// growing to 40/256 at frac_bits=12 -- not a rare corner case at this
// width. Matching fp2_parallel_mac_ref.v's precedent (adopted there
// for the identical reason), this accumulator now SATURATES at
// +32767/-32768 rather than silently wrapping, with a per-cycle
// `overflow` flag (meaningful exactly when valid_out=1, explicitly
// cleared to 0 when valid_in=0 -- same convention as
// fp2_parallel_mac_ref.v's overflow flag).
//
// ---- Adaptive frac_bits (posit4_es1_pp.v itself UNCHANGED) ----
// posit4_es1_pp.v always emits `partial` pre-scaled to a FIXED Q8.8
// convention (the "+8" baked into its own exponent-to-shift math) --
// that primitive was deliberately left untouched (already exhaustively
// tested elsewhere) rather than pushed to also carry a frac_bits port.
// Instead, this wrapper applies an ADDITIONAL rescale on top:
//     rescale_shift = frac_bits - 8   (signed; 8 = posit4_es1_pp.v's
//                                       fixed native scale)
//     partial_adaptive = rescale_shift>=0 ? partial << rescale_shift
//                                         : partial >> (-rescale_shift)
// i.e. "take the fixed-Q8.8 value, then re-scale it to whatever
// frac_bits was actually requested." For frac_bits=8 this is a no-op
// (rescale_shift=0), so the original fixed behavior is a special case
// of the new adaptive one, not a separate code path. Right-shifts
// (frac_bits<8) truncate (no rounding -- consistent with the rest of
// this package, see docs/DESIGN_NOTES.md on rounding).
// =====================================================================
module posit4_mac_ref #(
    parameter ACC_W  = 16,   // adaptive fxp16 default; override for a wider accumulator
    parameter FRAC_W = 5     // width of the frac_bits input port (0..31)
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear_acc,
    input  wire                     valid_in,
    input  wire [FRAC_W-1:0]        frac_bits,   // adaptive; must stay constant per dot product (same convention as fp2_parallel_mac_ref.v)
    input  wire [3:0]               a,
    input  wire [3:0]               b,
    output reg  signed [ACC_W-1:0]  acc,
    output reg                       valid_out,
    output wire                      nar_flag,     // sticky
    output reg                       overflow      // this cycle's result saturated; 0 whenever valid_out=0
);

    // posit4_es1_pp.v's own native Q8.8 computation needs headroom
    // independent of this wrapper's (possibly narrower, now 16 by
    // default) ACC_W: its shift amount (exp_p+8) ranges 0..16, so
    // `1<<16` alone needs 17 bits just to exist -- instantiating it
    // with the wrapper's ACC_W directly (a bug in an earlier revision
    // of this file) silently truncated that shift result to 0 for
    // several legitimate, non-overflowing products whenever ACC_W<17.
    // PP_NATIVE_W is fixed at a safe width regardless of ACC_W.
    localparam PP_NATIVE_W = 32;

    wire                    sign_prod;
    wire [PP_NATIVE_W-1:0]  partial;
    wire                    nar_w;

    posit4_es1_pp #(.ACC_W(PP_NATIVE_W)) u_posit_pp (
        .a(a), .b(b),
        .sign_prod(sign_prod), .partial(partial), .nar(nar_w)
    );

    // ---- adaptive rescale: fixed-Q8.8 partial -> requested frac_bits ----
    // NOTE: partial_adaptive_wide is kept at FULL WIDE_W width all the
    // way through the sum and saturation check below -- truncating it
    // down to ACC_W bits here (as an earlier, buggy revision did) would
    // silently corrupt any single-shot product that needs more than
    // ACC_W bits before saturation ever gets a chance to see the true
    // magnitude (e.g. 16*16=256 real x 2^8 needs 17 bits, not 16).
    localparam WIDE_W = PP_NATIVE_W + 24; // comfortably covers the full frac_bits port range, sized off the pp generator's native width, not the (possibly narrower) ACC_W
    wire signed [FRAC_W+2:0] rescale_shift = $signed({3'b000, frac_bits}) - 8'sd8; // frac_bits - 8, signed
    wire signed [WIDE_W-1:0] partial_ext = {{(WIDE_W-PP_NATIVE_W){1'b0}}, partial}; // partial is an unsigned magnitude, PP_NATIVE_W bits wide
    wire signed [WIDE_W-1:0] partial_adaptive_wide =
        (rescale_shift >= 0) ? (partial_ext <<< rescale_shift)
                              : (partial_ext >>> (-rescale_shift));

    wire skip_nar = nar_w;

    reg nar_flag_r;
    assign nar_flag = nar_flag_r;

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
            acc        <= {ACC_W{1'b0}};
            valid_out  <= 1'b0;
            nar_flag_r <= 1'b0;
            overflow   <= 1'b0;
        end else begin
            if (clear_acc) begin
                nar_flag_r <= 1'b0;
            end

            if (valid_in) begin
                // No separate "skip on NaR" gate needed here:
                // posit4_es1_pp.v already forces `partial` to 0 on NaR
                // (see its own header comment), so sum_wide naturally
                // evaluates to 0 (clear_acc case) or the unchanged old
                // acc (mid-accumulation case) with no extra
                // conditioning -- an earlier revision gated this update
                // by `do_accumulate` too, which broke the clear_acc
                // case specifically: acc held stale instead of
                // resetting to 0 whenever a NaR operand appeared on the
                // same cycle as clear_acc, since the whole update was
                // skipped entirely.
                acc      <= sum_saturated;
                overflow <= ovf_pos | ovf_neg;
                if (skip_nar)
                    nar_flag_r <= 1'b1;
                valid_out <= 1'b1;
            end else begin
                valid_out <= 1'b0;
                overflow  <= 1'b0;   // meaningful only alongside valid_out=1
            end
        end
    end

endmodule
