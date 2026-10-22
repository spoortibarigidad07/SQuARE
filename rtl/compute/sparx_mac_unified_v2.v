// =====================================================================
// sparx_mac_unified_v2.v
//
// Additional top-level (does NOT replace sparx_mac_unified.v, which is
// left exactly as-is and remains valid for anyone who only needs its
// simpler one-product-per-cycle interface). This version fills in
// mode_sel==2'b11 (previously "reserved") with the redesigned two-lane
// parallel FP2 MAC (fp2_parallel_mac_ref.v), addressing the point that
// the original top-level's FP2 mode computes only one product per
// cycle while the clarified FP2 spec needs two in parallel.
//
// mode_sel: 2'b00 = Posit(4,1)
//           2'b01 = FP4 (E2M1)
//           2'b10 = FP2 (element-level, legacy, ONE product/cycle)
//           2'b11 = FP2 (two-lane PARALLEL, adaptive fxp, saturating)
//
// ---- Architectural note: two accumulator registers, not one ----
// Every other mode in this file follows the established pattern (Sec.
// 2 of DESIGN_NOTES.md): pure combinational partial-product generator,
// one shared registered accumulator. fp2_parallel_mac_ref.v does NOT
// fit that pattern -- it's a complete, self-contained MAC with its own
// registered, SATURATING accumulator (needed for its adaptive-width
// semantics, which are genuinely different from the other three modes'
// simple fixed-width wrapping accumulator). Rather than re-deriving
// and re-verifying that saturation logic at this top level, this
// module instantiates fp2_parallel_mac_ref as a self-contained
// sub-block and MUXES THE OUTPUTS between the shared accumulator
// (modes 00/01/10) and fp2_parallel_mac_ref's own accumulator (mode
// 11). This is a real, documented divergence from the single-shared-
// accumulator philosophy, justified by mode 11's different
// accumulation semantics rather than an oversight.
//
// mode_sel must stay constant across one dot product (switching modes
// mid-accumulation mixes semantics from two different accumulators,
// same underlying issue as changing frac_bits/fmt_sel mid-accumulation
// within mode 11 alone -- see fp2_parallel_mac_ref.v's own usage
// contract note).
//
// ---- Output behavior: stated precisely, so there is no ambiguity ----
// This module does NOT have all modes sharing one common accumulator.
// There are TWO physically separate accumulator registers:
//   - `acc`/`valid_out`/`nar_flag`     : modes 00/01/10 (Posit/FP4/legacy-FP2)
//   - `fp2p_acc`/`fp2p_valid_out`/`fp2p_overflow` : mode 11 only
// Both output pairs are exposed directly (Option A) for anyone who
// wants unambiguous, mode-specific signals. For convenience, a THIRD,
// pre-muxed pair (`acc_out`/`valid_out_final`, Option B) is ALSO
// provided below, selecting whichever of the two is live for the
// current `mode_sel` -- use this if you just want "the answer" without
// caring which physical register produced it, but be aware its bit
// width is the wider of the two (`fp2p_acc` zero/sign-extended down or
// `acc` as-is), and it says nothing about overflow (read `fp2p_overflow`
// directly for that, it only applies to mode 11 regardless).
// =====================================================================
// ---- Adaptive frac_bits, modes 00/01/10 (added; the three pp
// generators themselves UNCHANGED, same approach as
// sparx_mac_unified.v) ----
// posit4_es1_pp.v / fp4_e2m1_pp.v / fp2_pp.v each always emit `partial`
// pre-scaled to a FIXED Q8.8 convention baked in internally -- left
// untouched. This module applies ONE additional rescale
// (`frac_bits - 8`) on top of whichever partial the mode mux selects,
// covering all three modes uniformly since they share the same native
// scale. This `frac_bits` port is independent of mode 11's own
// `fp2p_frac_bits` -- two genuinely separate controls for two
// genuinely separate accumulator paths, same reasoning as keeping
// `fp2p_*` operands separate from `a`/`b`.
// =====================================================================
module sparx_mac_unified_v2 #(
    parameter ACC_W            = 32,   // shared accumulator width, modes 00/01/10
    parameter FRAC_W           = 5,    // width of modes 00/01/10's frac_bits port
    parameter FP2P_ACC_W       = 16,   // mode 11's own accumulator width -- matches
                                       // the mentor's "adaptive fxp16" requirement,
                                       // same default as fp2_parallel_mac_ref.v
                                       // standalone. Widen only if you have a
                                       // specific reason to; the resizing logic
                                       // below (Sec. below) handles either width
                                       // safely via a generate block.
    parameter FP2P_FRAC_W      = 5     // width of mode 11's frac_bits port
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          clear_acc,
    input  wire                          valid_in,
    input  wire [1:0]                    mode_sel,
    input  wire [FRAC_W-1:0]             frac_bits,   // adaptive; modes 00/01/10 only; must stay constant per dot product

    // ---- modes 00/01/10: unchanged interface from sparx_mac_unified.v ----
    input  wire [3:0]                    a,
    input  wire [3:0]                    b,

    // ---- mode 11: the new parallel FP2 MAC's own operand set ----
    input  wire                          fp2p_fmt_sel,    // 0=E1M0, 1=E0M1
    input  wire [FP2P_FRAC_W-1:0]        fp2p_frac_bits,
    input  wire [1:0]                    fp2p_a0, fp2p_a1, fp2p_w0, fp2p_w1,
    input  wire                          fp2p_a0_zero, fp2p_a1_zero,
    input  wire                          fp2p_w0_zero, fp2p_w1_zero,

    output reg  signed [ACC_W-1:0]       acc,          // valid for modes 00/01/10 (Option A)
    output reg                          valid_out,     // valid for modes 00/01/10 (Option A)
    output wire                          nar_flag,      // sticky, Posit4 mode only

    output wire signed [FP2P_ACC_W-1:0]  fp2p_acc,      // valid for mode 11 (Option A)
    output wire                          fp2p_valid_out,
    output wire                          fp2p_overflow,
    output wire signed [7:0]             fp2p_acc_fxp8, // MSB-8 window over fp2p_acc, mentor's fxp8 spec for FP2

    // ---- Option B: pre-muxed convenience output, see header note ----
    output wire signed [ACC_W-1:0]       acc_out,
    output wire                          valid_out_final
);

    // ---- operand isolation, ALL FOUR modes ----
    // Gating valid_in/clear_acc alone (as an earlier revision of this
    // file did) only stops the CLOCKED accumulator update -- it does
    // NOT stop the COMBINATIONAL datapath feeding that update (typecast
    // + multiply + scale, inside each pp generator or inside
    // fp2_parallel_mac_ref) from still toggling every time an inactive
    // mode's operand inputs change on the top-level ports. That was a
    // real gap for mode 11 specifically (its operands are plain
    // top-level input wires, not internally derived, so nothing
    // previously stopped them from toggling fp2_parallel_mac_ref's
    // internal logic even while mode 11 was deselected). Fixed by
    // gating ALL FOUR modes' operands the same way.
    wire en_posit = (mode_sel == 2'b00);
    wire en_fp4   = (mode_sel == 2'b01);
    wire en_fp2   = (mode_sel == 2'b10);
    wire en_fp2p  = (mode_sel == 2'b11);

    wire [3:0] a_posit = en_posit ? a : 4'b0;
    wire [3:0] b_posit = en_posit ? b : 4'b0;
    wire [3:0] a_fp4   = en_fp4   ? a : 4'b0;
    wire [3:0] b_fp4   = en_fp4   ? b : 4'b0;
    wire [3:0] a_fp2   = en_fp2   ? a : 4'b0;
    wire [3:0] b_fp2   = en_fp2   ? b : 4'b0;

    wire [1:0] fp2p_a0_g = en_fp2p ? fp2p_a0 : 2'b00;
    wire [1:0] fp2p_a1_g = en_fp2p ? fp2p_a1 : 2'b00;
    wire [1:0] fp2p_w0_g = en_fp2p ? fp2p_w0 : 2'b00;
    wire [1:0] fp2p_w1_g = en_fp2p ? fp2p_w1 : 2'b00;

    wire fp2p_a0_zero_g = en_fp2p ? fp2p_a0_zero : 1'b1;
    wire fp2p_a1_zero_g = en_fp2p ? fp2p_a1_zero : 1'b1;
    wire fp2p_w0_zero_g = en_fp2p ? fp2p_w0_zero : 1'b1;
    wire fp2p_w1_zero_g = en_fp2p ? fp2p_w1_zero : 1'b1;

    // ---- combinational partial-product generators (modes 00/01/10) ----
    wire               sign_posit, sign_fp4, sign_fp2;
    wire [ACC_W-1:0]   pp_posit,   pp_fp4,   pp_fp2;
    wire               nar_w;

    posit4_es1_pp #(.ACC_W(ACC_W)) u_posit_pp (
        .a(a_posit), .b(b_posit),
        .sign_prod(sign_posit), .partial(pp_posit), .nar(nar_w)
    );

    fp4_e2m1_pp   #(.ACC_W(ACC_W)) u_fp4_pp (
        .a(a_fp4), .b(b_fp4),
        .sign_prod(sign_fp4), .partial(pp_fp4)
    );

    fp2_pp        #(.ACC_W(ACC_W)) u_fp2_pp (
        .a(a_fp2), .b_in(b_fp2),
        .sign_prod(sign_fp2), .partial(pp_fp2)
    );

    // ---- mode 11: self-contained parallel FP2 MAC, own accumulator ----
    // valid_in/clear_acc gated (stops the accumulator from updating)
    // AND operands gated above (stops the internal combinational
    // datapath from toggling) when mode 11 isn't selected.
    wire fp2p_valid_in_gated  = en_fp2p && valid_in;
    wire fp2p_clear_acc_gated = en_fp2p && clear_acc;

    fp2_parallel_mac_ref_bounded_exact #(.ACC_W(FP2P_ACC_W), .FRAC_W(FP2P_FRAC_W)) u_fp2_parallel (
        .clk(clk), .rst_n(rst_n),
        .clear_acc(fp2p_clear_acc_gated), .valid_in(fp2p_valid_in_gated),
        .fmt_sel(fp2p_fmt_sel), .frac_bits(fp2p_frac_bits),
        .a0(fp2p_a0_g), .a1(fp2p_a1_g), .w0(fp2p_w0_g), .w1(fp2p_w1_g),
        .a0_zero(fp2p_a0_zero_g), .a1_zero(fp2p_a1_zero_g),
        .w0_zero(fp2p_w0_zero_g), .w1_zero(fp2p_w1_zero_g),
        .acc(fp2p_acc), .valid_out(fp2p_valid_out), .overflow(fp2p_overflow), .acc_fxp8(fp2p_acc_fxp8)
    );

    // ---- mode mux for the shared accumulator's combinational input (modes 00/01/10) ----
    reg                    sel_sign;
    reg  [ACC_W-1:0]       sel_partial;
    always @(*) begin
        case (mode_sel)
            2'b00:   begin sel_sign = sign_posit; sel_partial = pp_posit; end
            2'b01:   begin sel_sign = sign_fp4;   sel_partial = pp_fp4;   end
            2'b10:   begin sel_sign = sign_fp2;   sel_partial = pp_fp2;   end
            default: begin sel_sign = 1'b0;       sel_partial = {ACC_W{1'b0}}; end
        endcase
    end

    wire skip_nar      = (mode_sel == 2'b00) && nar_w;
    wire do_accumulate = valid_in && !skip_nar && !en_fp2p;

    // ---- adaptive rescale: fixed-Q8.8 sel_partial -> requested frac_bits ----
    // (modes 00/01/10 only; mode 11 already has its own independent
    // adaptive frac_bits inside fp2_parallel_mac_ref.v)
    localparam WIDE_W = ACC_W + 24;
    wire signed [FRAC_W+2:0] rescale_shift = $signed({3'b000, frac_bits}) - 8'sd8; // frac_bits - 8, signed
    wire signed [WIDE_W-1:0] sel_partial_ext = {{(WIDE_W-ACC_W){1'b0}}, sel_partial};
    wire signed [WIDE_W-1:0] sel_partial_adaptive_wide =
        (rescale_shift >= 0) ? (sel_partial_ext <<< rescale_shift)
                              : (sel_partial_ext >>> (-rescale_shift));
    wire [ACC_W-1:0] sel_partial_adaptive = sel_partial_adaptive_wide[ACC_W-1:0];

    reg nar_flag_r;
    assign nar_flag = nar_flag_r;

    // ---- shared accumulator register (modes 00/01/10 only; mode 11
    // does not touch this register at all -- it has its own inside
    // u_fp2_parallel) ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc        <= {ACC_W{1'b0}};
            valid_out  <= 1'b0;
            nar_flag_r <= 1'b0;
        end else begin
            if (clear_acc && !en_fp2p) begin
                acc        <= {ACC_W{1'b0}};
                nar_flag_r <= 1'b0;
            end

            if (valid_in && !en_fp2p) begin
                if (do_accumulate)
                    acc <= (clear_acc ? {ACC_W{1'b0}} : acc) +
                           (sel_sign ? -$signed(sel_partial_adaptive) : $signed(sel_partial_adaptive));
                if (skip_nar)
                    nar_flag_r <= 1'b1;
                valid_out <= 1'b1;
            end else if (!en_fp2p) begin
                valid_out <= 1'b0;
            end
            // when en_fp2p: acc/valid_out/nar_flag_r simply hold their
            // last value from whenever mode 11 was last NOT selected;
            // the live, meaningful outputs for mode 11 are fp2p_acc /
            // fp2p_valid_out / fp2p_overflow instead.
        end
    end

    // ---- Option B: pre-muxed convenience output ----
    // Sign/zero-extend fp2p_acc (FP2P_ACC_W bits) to ACC_W bits if
    // narrower, or truncate if wider. Using `generate if/else` rather
    // than a ternary specifically because a ternary requires BOTH
    // branches to be syntactically valid for the given parameters even
    // though only one is ever selected -- with the default
    // FP2P_ACC_W=16, ACC_W=32, a ternary's "truncate" branch would
    // read `fp2p_acc[31:0]` against a signal that's only 16 bits wide,
    // an out-of-range bit-select some tools handle inconsistently.
    // `generate if` elaborates ONLY the taken branch, so the untaken
    // one's bit-select is never checked against the actual signal
    // width for these parameters.
    wire signed [ACC_W-1:0] fp2p_acc_resized;
    generate
        if (FP2P_ACC_W >= ACC_W) begin : gen_fp2p_truncate
            assign fp2p_acc_resized = fp2p_acc[ACC_W-1:0];
        end else begin : gen_fp2p_signextend
            assign fp2p_acc_resized = {{(ACC_W-FP2P_ACC_W){fp2p_acc[FP2P_ACC_W-1]}}, fp2p_acc};
        end
    endgenerate

    assign acc_out         = en_fp2p ? fp2p_acc_resized : acc;
    assign valid_out_final = en_fp2p ? fp2p_valid_out   : valid_out;

endmodule
