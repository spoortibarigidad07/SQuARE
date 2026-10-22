// =====================================================================
// sparx_mac_unified.v
//
// STATUS: LEGACY / INTEGRATION REFERENCE -- NOT the final synthesis
// comparison target. This module intentionally stays at its original
// ACC_W=32, non-saturating, one-shared-accumulator convention (the
// original SPARX-style design, unchanged since before the per-format
// fxp16/fxp8 decisions below existed). For the actual final comparison
// table, use the three standalone modules instead, each independently
// tuned per the mentor's per-format spec:
//   posit4_mac_ref.v        -- Posit(4,1), fxp16 (ACC_W=16, saturating)
//   fp4_mac_ref.v            -- FP4 (E2M1), fxp8 MSB-window (acc_fxp8)
//   fp2_parallel_mac_ref.v   -- FP2, fxp8 MSB-window (acc_fxp8)
// A single shared accumulator, by construction, can't simultaneously be
// "16 for Posit4, 8-window for FP2" -- it's one width for whichever
// format is active, which is exactly why this module can't just adopt
// the same per-format defaults as the standalone modules without
// abandoning the "one shared accumulator" design point entirely (see
// Sec. 2 of docs/DESIGN_NOTES.md for why that design point exists).
// `sparx_mac_unified_v2.v` (mode_sel=11, adding the parallel FP2 MAC)
// is similarly an integration/demo wrapper, not a comparison target --
// see its own header for the details.
//
// Drop-in replacement for the "Approximate Multiplier" block inside the
// SPARX MAC processing element (Kumar et al., Fig. 3(b): the block
// feeding `acc`/`MAC_out` in the neuron-lane datapath). One physical
// accumulator register is shared across all three arithmetic modes --
// only the combinational partial-product generator is muxed, which is
// the efficient way to add multi-format support to a PE lane (rather
// than instantiating three independent accumulators).
//
// mode_sel: 2'b00 = Posit(4,1)
//           2'b01 = FP4 (E2M1)
//           2'b10 = FP2 (element-level, mode bit carried per-operand)
//           2'b11 = reserved (legacy SPARX ILM path / passthrough)
//
// Integration into SPARX's custom instruction (Fig. 3(a)):
//   the original 3-bit `abc` field used a single approximation bit `b`.
//   Extending that to a 2-bit arithmetic-select subfield (b1,b0) in the
//   func3 encoding lets the EX-stage decode drive `mode_sel` directly,
//   with b1b0=01 remaining backward-compatible with the original
//   "approximate" mode if the legacy ILM datapath is retained on
//   mode_sel==2'b11.
//
// Accumulator convention: signed fixed-point, LSB = 2^-frac_bits
// (frac_bits is now a runtime input, default tested at 8, i.e.
// real_value = acc / 2^frac_bits -- see the "Adaptive frac_bits"
// note below for how this works without touching the pp generators).
//
// Operand isolation: `a`/`b` are gated to 0 for any lane not selected by
// `mode_sel`, so only the active format's combinational logic actually
// toggles on a given cycle -- see docs/DESIGN_NOTES.md Sec. 6.
//
// ---- Adaptive frac_bits (added; the three pp generators themselves
// UNCHANGED) ----
// posit4_es1_pp.v / fp4_e2m1_pp.v / fp2_pp.v each always emit `partial`
// pre-scaled to a FIXED Q8.8 convention (baked into each primitive
// internally) -- all three were deliberately left untouched (already
// exhaustively tested elsewhere). This module applies ONE additional
// rescale on top of whichever partial the mode mux selects:
//     rescale_shift = frac_bits - 8   (signed; 8 = every pp generator's
//                                       fixed native scale)
//     sel_partial_adaptive = rescale_shift>=0 ? sel_partial<<rescale_shift
//                                             : sel_partial>>(-rescale_shift)
// Since all three formats share the identical native scale, one
// rescale stage after the mux covers all three modes uniformly --
// frac_bits=8 reproduces the original fixed behavior exactly
// (rescale_shift=0, a no-op). Right-shifts (frac_bits<8) truncate, no
// rounding added (consistent with the rest of this package). The
// accumulator itself stays a plain, non-saturating signed add, exactly
// as before -- saturation was never part of these three formats' spec.
// frac_bits must stay constant per dot product, same convention as
// fp2_parallel_mac_ref.v.
// =====================================================================
module sparx_mac_unified #(
    parameter ACC_W  = 32,
    parameter FRAC_W = 5     // width of the frac_bits input port (0..31)
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear_acc,   // start of new dot-product
    input  wire                     valid_in,
    input  wire [1:0]                mode_sel,
    input  wire [FRAC_W-1:0]        frac_bits,   // adaptive; must stay constant per dot product
    input  wire [3:0]                a,
    input  wire [3:0]                b,
    output reg  signed [ACC_W-1:0]  acc,         // = SPARX's MAC_out/acc
    output reg                       valid_out,
    output wire                      nar_flag     // sticky, Posit4 mode only
);

    // ---- operand isolation ----
    // Without this, `a`/`b` feed all three combinational partial-product
    // generators every cycle regardless of `mode_sel`, so the two
    // inactive lanes still toggle internally on every operand change --
    // wasted dynamic power that won't show up as a functional bug in
    // simulation, only in a real power report. Gating each lane's
    // inputs to a constant (0) when it isn't selected freezes its
    // internal switching activity; only the selected lane's logic
    // actually toggles on a given cycle.
    wire en_posit = (mode_sel == 2'b00);
    wire en_fp4   = (mode_sel == 2'b01);
    wire en_fp2   = (mode_sel == 2'b10);

    wire [3:0] a_posit = en_posit ? a : 4'b0;
    wire [3:0] b_posit = en_posit ? b : 4'b0;
    wire [3:0] a_fp4   = en_fp4   ? a : 4'b0;
    wire [3:0] b_fp4   = en_fp4   ? b : 4'b0;
    wire [3:0] a_fp2   = en_fp2   ? a : 4'b0;
    wire [3:0] b_fp2   = en_fp2   ? b : 4'b0;

    // ---- combinational partial-product generators (one per format) ----
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

    // ---- mode mux (single shared datapath into the accumulator) ----
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

    wire skip_nar        = (mode_sel == 2'b00) && nar_w;
    wire do_accumulate    = valid_in && !skip_nar;

    // ---- adaptive rescale: fixed-Q8.8 sel_partial -> requested frac_bits ----
    localparam WIDE_W = ACC_W + 24; // comfortably covers the full frac_bits port range
    wire signed [FRAC_W+2:0] rescale_shift = $signed({3'b000, frac_bits}) - 8'sd8; // frac_bits - 8, signed
    wire signed [WIDE_W-1:0] sel_partial_ext = {{(WIDE_W-ACC_W){1'b0}}, sel_partial}; // unsigned magnitude
    wire signed [WIDE_W-1:0] sel_partial_adaptive_wide =
        (rescale_shift >= 0) ? (sel_partial_ext <<< rescale_shift)
                              : (sel_partial_ext >>> (-rescale_shift));
    wire [ACC_W-1:0] sel_partial_adaptive = sel_partial_adaptive_wide[ACC_W-1:0];

    // ---- sticky NaR flag: set the first time a NaR is seen on a valid
    // Posit4-mode cycle, held until the next clear_acc (start of a new
    // dot product) or reset -- NOT purely combinational (this replaces
    // an earlier revision where the doc comment claimed "sticky" but
    // the RTL was a bare combinational `assign`, i.e. it dropped the
    // instant the NaR-triggering operand cycle passed).
    reg nar_flag_r;
    assign nar_flag = nar_flag_r;

    // ---- single shared accumulator register ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc        <= {ACC_W{1'b0}};
            valid_out  <= 1'b0;
            nar_flag_r <= 1'b0;
        end else begin
            if (clear_acc) begin
                acc        <= {ACC_W{1'b0}};
                nar_flag_r <= 1'b0;
            end

            if (valid_in) begin
                if (do_accumulate)
                    acc <= (clear_acc ? {ACC_W{1'b0}} : acc) +
                           (sel_sign ? -$signed(sel_partial_adaptive) : $signed(sel_partial_adaptive));
                if (skip_nar)
                    nar_flag_r <= 1'b1;   // sticky set (overrides the clear above
                                          // if clear_acc and the NaR both land
                                          // on the same cycle -- same last-write-
                                          // wins convention used for `acc`)
                valid_out <= 1'b1;
            end else begin
                valid_out <= 1'b0;
            end
        end
    end

endmodule
