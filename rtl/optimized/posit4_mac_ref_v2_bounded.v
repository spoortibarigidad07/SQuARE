// =====================================================================
// posit4_mac_ref_v2_bounded.v
//
// This module is an experimental alternative to
// posit4_mac_ref_v2.v. It replaces the baseline design's 48-bit
// shifted-magnitude intermediate with an 18-bit bounded datapath.
//
// The optimization is based on the saturation limits of the signed
// 16-bit accumulator, whose range is -32768 to +32767. Any contribution
// with a magnitude of at least 65536 (2^16) will always saturate the
// accumulator, regardless of its current value:
//
//   +65536 + (-32768) = +32768   -> positive saturation
//   -65536 + (+32767) = -32769   -> negative saturation
//
// Therefore, contributions with a magnitude greater than or equal to
// 65536 do not need to be represented explicitly. Only the product
// sign is required to select the positive or negative saturation limit.
//
// Every finite Posit(4,1) magnitude is an exact power of two and is
// therefore represented by a single set bit. The saturation condition
// can consequently be determined directly from the combined shift:
//
//   combined_shift >= 16
//
// since 2^16 = 65536.
//
// The accumulator architecture is unchanged from the baseline design.
// It remains a signed 16-bit adaptive fixed-point accumulator. This
// implementation does not use a shared or block exponent, a
// reduced-precision internal accumulator, post-accumulation
// normalization, or per-operation Posit re-encoding. Only the width of
// the intermediate magnitude and summation datapath is reduced from
// 48 bits to 18 bits.
//
// The posit4_es1_decode.v module is reused without modification. The
// Posit decoding, zero and NaR detection, and combined-shift
// calculation follow the same implementation as posit4_mac_ref_v2.v.
//
// The exponent values are manually sign-extended to a common width
// before addition. This preserves the signed interpretation of exp_p
// and avoids incorrect behavior that could result from concatenating a
// signed value with trailing zeros without proper sign extension.
//
// The following behavior is preserved from posit4_mac_ref_v2.v:
//
//   - port definitions;
//   - parameter names and default values;
//   - reset behavior;
//   - one-cycle latency;
//   - valid_in and valid_out sequencing;
//   - clear_acc behavior;
//   - accumulator and nar_flag synchronization; and
//   - parameter-validity checks.
//
// In particular, clear_acc affects the accumulator and nar_flag only
// when valid_in is asserted, matching the baseline sequential
// behavior.
//
// The only architectural change begins after combined_shift and is
// limited to the contribution-magnitude, addition, and saturation
// datapath.
// =====================================================================

module posit4_mac_ref_v2_bounded #(
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
    output wire                      nar_flag,     // sticky
    output reg                       overflow      // this cycle's result saturated; 0 whenever valid_out=0
);

    wire               sign_prod;
    wire signed [4:0]  exp_p;     // -8..8
    wire               op_zero, nar_w;

    posit4_es1_decode u_decode (
        .a(a), .b(b),
        .sign_prod(sign_prod), .exp_p(exp_p), .op_zero(op_zero), .nar(nar_w)
    );

    wire skip_nar = nar_w;

    reg nar_flag_r;
    assign nar_flag = nar_flag_r;

    // ---- combined shift: identical derivation to posit4_mac_ref_v2.v,
    // same explicit-width sign-extension pattern (see that module's
    // header for why concatenation-with-zeros would silently corrupt
    // negative exp_p values -- avoided here the same way) ----
    localparam SHIFT_W = FRAC_W + 3; // comfortably covers exp_p(-8..8) + frac_bits(0..2^FRAC_W-1); = 8 at defaults
    wire signed [SHIFT_W-1:0] exp_p_ext     = {{(SHIFT_W-5){exp_p[4]}}, exp_p};
    wire signed [SHIFT_W-1:0] frac_bits_ext = {{(SHIFT_W-FRAC_W){1'b0}}, frac_bits};
    wire signed [SHIFT_W-1:0] combined_shift = exp_p_ext + frac_bits_ext;

    // ---- guaranteed-saturation detection ----
    // Only fires for a REAL nonzero, non-NaR product whose combined
    // shift is >=16 (magnitude 2^16=65536 or more) -- explicitly
    // excludes op_zero/nar_w so a NaR or zero operand can never be
    // mistaken for a forced-saturation case (Requirement: "Preserve
    // zero and NaR handling exactly").
    wire guaranteed_sat = (!op_zero) && (!nar_w) && (combined_shift >= 16'sd16);

    // ---- bounded magnitude, 0..65535 capacity (16 unsigned bits) ----
    // Only ever a power of two from 2^0 to 2^15 in practice (magnitude
    // 0 when combined_shift<0, since a single bit right-shifted by any
    // positive amount vanishes -- there is no fractional bit to
    // preserve), but sized for the full 0..65535 range as specified.
    // The low 4 bits of combined_shift are only meaningful when
    // 0<=combined_shift<=15 (i.e. whenever guaranteed_sat is false and
    // the shift is non-negative); when guaranteed_sat is true this
    // value is computed but never used (final mux bypasses it
    // entirely), so an out-of-range low-4-bits slice there is benign,
    // not an X-propagation risk.
    wire signed [SHIFT_W-1:0] shift_lo_wide = combined_shift;
    wire [3:0] shift_lo = shift_lo_wide[3:0];
    wire [15:0] bounded_mag_raw = (combined_shift < 16'sd0) ? 16'd0 : (16'd1 << shift_lo);
    wire [15:0] bounded_mag = (op_zero || nar_w || guaranteed_sat) ? 16'd0 : bounded_mag_raw;

    // ---- signed 18-bit contribution and accumulate (bounded datapath;
    // this is the actual optimization -- 18 bits instead of 48) ----
    localparam CONTRIB_W = 18; // per spec: "likely 18 bits, so no intermediate sum can wrap before saturation"
    wire signed [CONTRIB_W-1:0] contribution =
        (op_zero || nar_w) ? {CONTRIB_W{1'b0}} :
        sign_prod ? -$signed({2'b00, bounded_mag}) : $signed({2'b00, bounded_mag});

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

    // ---- final mux: forced rail (guaranteed_sat) vs. the normal
    // bounded-adder result. When guaranteed_sat, the actual magnitude
    // was never computed -- only sign_prod decides which rail. ----
    wire signed [ACC_W-1:0] sum_saturated =
        guaranteed_sat ? (sign_prod ? SAT_MIN[ACC_W-1:0] : SAT_MAX[ACC_W-1:0])
                        : sum_saturated_normal;
    wire ovf_final = guaranteed_sat ? 1'b1 : (ovf_pos_normal | ovf_neg_normal);

    // ---- sequencing: copied verbatim from posit4_mac_ref_v2.v,
    // including the round-5 nar_flag/acc sync fix (nar_flag_r's
    // clear_acc reset lives inside the valid_in branch) ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc        <= {ACC_W{1'b0}};
            valid_out  <= 1'b0;
            nar_flag_r <= 1'b0;
            overflow   <= 1'b0;
        end else begin
            if (valid_in) begin
                if (clear_acc)
                    nar_flag_r <= 1'b0;

                acc      <= sum_saturated;
                overflow <= ovf_final;
                if (skip_nar)
                    nar_flag_r <= 1'b1;
                valid_out <= 1'b1;
            end else begin
                valid_out <= 1'b0;
                overflow  <= 1'b0;
            end
        end
    end

    // ---- PARAMETER SAFETY GUARD ----
    // Verified correct ONLY for the default FRAC_W=5, ACC_W=16 -- the
    // 65536/CONTRIB_W=18 derivation is tied directly to ACC_W=16
    // (2^ACC_W=65536 is the guaranteed-saturation threshold itself; a
    // different ACC_W would need a different threshold and a
    // different CONTRIB_W, not just a parameter substitution). Same
    // portable initial+$fatal form as posit4_mac_ref_v2.v, verified in
    // both Icarus Verilog and Verilator there; Vivado/Genus untested
    // against this construct in either module.
    generate
        if (FRAC_W != 5 || ACC_W != 16) begin : unsupported_parameters
            initial begin
                $display("ERROR: posit4_mac_ref_v2_bounded only supports FRAC_W=5, ACC_W=16 (got FRAC_W=%0d, ACC_W=%0d)", FRAC_W, ACC_W);
                $fatal(1, "posit4_mac_ref_v2_bounded: unsupported parameter combination");
            end
        end
    endgenerate

endmodule
