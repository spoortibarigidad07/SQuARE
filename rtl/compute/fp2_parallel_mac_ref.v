// =====================================================================
// fp2_parallel_mac_ref.v  --  DP2 reference MAC (Std. Ref.)
//
`timescale 1ns/1ps

// Dual-product FP2 MAC, cancellation-preserving reduction (DP2):
//
//     acc <- sat16( A + trunc((a0*w0 + a1*w1) * 2^F) ),   F = frac_bits
//
// where A is the current accumulator, or 0 when clear_acc is asserted.
//
// ---- Operands ----
// Each of a0, a1, w0, w1 is a 2-bit FP2 value code {sign, bit} with a
// separate zero-mask bit (a0_zero, ...); see fp2_to_fp3.v.
//
// ---- Product generation ----
// mag2x = {E,M} = 2*|x| (0..3), so each product is computed in a native
// x4 integer scale:
//     u_j          = (-1)^(s_aj ^ s_wj) * mag2x(a_j) * mag2x(w_j)
//     S            = u_0 + u_1                       (-18..18)
//     contribution = trunc(S * 2^(F-2))
// The two products are added before alignment, so cancellation between
// them is preserved and a single shifter is used.
//
// ---- Reference-style (exact, full-width) accumulation ----
// The shift amount F-2 is signed (range -2..29), so F < 2 gives a right
// shift. Truncation is toward zero: the magnitude is shifted and the
// sign applied afterwards. The contribution is formed exactly in a
// WIDE_W = 35-bit intermediate (|S|max * 2^29 = 18 * 2^29 needs 35
// signed bits), added to the sign-extended accumulator, and only then
// saturated to the 16-bit range [-32768, 32767].
//
// ---- Outputs ----
// acc       : 16-bit signed fixed-point accumulator (F fractional bits)
// overflow  : 1 when this cycle's result saturated; 0 when valid_out=0
// acc_fxp8  : acc[15:8], an 8-bit view of the accumulator
// valid_out : valid_in delayed by one cycle (one-cycle latency)
//
// ---- Usage contract ----
// clear_acc acts only together with valid_in (that cycle's product is
// the first of a new dot product). frac_bits and fmt_sel must stay
// constant within one dot product; a simulation-only check below warns
// if they change.
// =====================================================================
module fp2_parallel_mac_ref #(
    parameter ACC_W  = 16,   // accumulator width
    parameter FRAC_W = 5     // width of the frac_bits input port (0..31)
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      clear_acc,   // starts a new dot product (see below)
    input  wire                      valid_in,
    input  wire                      fmt_sel,     // 0 = E1M0, 1 = E0M1, must stay constant per dot product
    input  wire [FRAC_W-1:0]         frac_bits,   // fractional-bit count F, must stay constant per dot product
    input  wire [1:0]                a0, a1,      // 2-bit {sign,bit} FP2 code, lane 0/1
    input  wire [1:0]                w0, w1,
    input  wire                      a0_zero, a1_zero,  // per-operand zero mask
    input  wire                      w0_zero, w1_zero,
    output reg  signed [ACC_W-1:0]   acc,
    output reg                       valid_out,
    output reg                       overflow,     // this cycle's result saturated; 0 whenever valid_out=0
    output wire signed [7:0]         acc_fxp8      // acc[15:8]
);

    // ---- decode all four operands ----
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

    // ---- mag2x is just {E,M} as a 2-bit unsigned integer ----
    wire [1:0] mag2x_a0 = {e_a0, m_a0};
    wire [1:0] mag2x_a1 = {e_a1, m_a1};
    wire [1:0] mag2x_w0 = {e_w0, m_w0};
    wire [1:0] mag2x_w1 = {e_w1, m_w1};

    // ---- two products ----
    wire [3:0] prod0_mag = mag2x_a0 * mag2x_w0;   // 0..9
    wire [3:0] prod1_mag = mag2x_a1 * mag2x_w1;
    wire       prod0_sign = s_a0 ^ s_w0;
    wire       prod1_sign = s_a1 ^ s_w1;

    wire signed [5:0] p0_signed = prod0_sign ? -$signed({2'b00, prod0_mag}) : $signed({2'b00, prod0_mag});
    wire signed [5:0] p1_signed = prod1_sign ? -$signed({2'b00, prod1_mag}) : $signed({2'b00, prod1_mag});

    wire signed [6:0] pair_sum_native = p0_signed + p1_signed;   // range -18..18

    // ---- alignment by 2^(F-2): signed shift amount; the magnitude is
    //      shifted and the sign applied afterwards (truncation toward zero) ----
    localparam WIDE_W = 35;   // exact width for FRAC_W=5 (see header)
    wire signed [FRAC_W+2:0] shift_signed = $signed({3'b000, frac_bits}) - 3'sd2; // frac_bits - 2, signed
    wire                     pair_sum_sign = pair_sum_native[6];
    wire signed [6:0]        pair_sum_magnitude = pair_sum_sign ? -pair_sum_native : pair_sum_native; // always >= 0
    wire signed [WIDE_W-1:0] pair_sum_mag_ext = {{(WIDE_W-7){1'b0}}, pair_sum_magnitude};
    wire signed [WIDE_W-1:0] magnitude_shifted =
        (shift_signed >= 0) ? (pair_sum_mag_ext <<< shift_signed)
                             : (pair_sum_mag_ext >>> (-shift_signed));
    wire signed [WIDE_W-1:0] partial_fxp = pair_sum_sign ? -magnitude_shifted : magnitude_shifted;

    // ---- full-width add, then saturate ----
    wire signed [ACC_W-1:0]  base_acc     = clear_acc ? {ACC_W{1'b0}} : acc;
    wire signed [WIDE_W-1:0] base_acc_ext = {{(WIDE_W-ACC_W){base_acc[ACC_W-1]}}, base_acc};
    wire signed [WIDE_W-1:0] sum_wide     = base_acc_ext + partial_fxp;

    localparam signed [WIDE_W-1:0] SAT_MAX = (1 <<< (ACC_W-1)) - 1;
    localparam signed [WIDE_W-1:0] SAT_MIN = -(1 <<< (ACC_W-1));

    wire ovf_pos = (sum_wide > SAT_MAX);
    wire ovf_neg = (sum_wide < SAT_MIN);
    wire signed [ACC_W-1:0] sum_saturated =
        ovf_pos ? SAT_MAX[ACC_W-1:0] :
        ovf_neg ? SAT_MIN[ACC_W-1:0] :
                  sum_wide[ACC_W-1:0];

    // ---- clocked update ----
    // clear_acc takes effect in the same cycle as valid_in; clear_acc
    // without valid_in leaves acc unchanged.
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
                overflow  <= 1'b0;   // meaningful only alongside valid_out=1
            end
        end
    end

    // ---- 8-bit view: top 8 bits of acc (acc[15:8] for ACC_W=16) ----
    assign acc_fxp8 = acc[ACC_W-1:ACC_W-8];

    // ---- SIMULATION-ONLY usage-contract check: frac_bits/fmt_sel must
    // not change mid-accumulation. No synthesized hardware. ----
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
                    $display("WARNING [t=%0t]: frac_bits changed mid-accumulation (was %0d, now %0d) -- results are undefined per this module's usage contract (frac_bits must stay constant across one dot product; change it only together with clear_acc)",
                              $time, frac_bits_latched, frac_bits);
                if (fmt_sel !== fmt_sel_latched)
                    $display("WARNING [t=%0t]: fmt_sel changed mid-accumulation (was %0d, now %0d) -- results are undefined per this module's usage contract (fmt_sel must stay constant across one dot product; change it only together with clear_acc)",
                              $time, fmt_sel_latched, fmt_sel);
            end
        end
    end
    // synthesis translate_on

    // ---- Parameter guard ----
    // WIDE_W is computed for FRAC_W=5, ACC_W=16 only; any other
    // combination stops simulation/elaboration with an error.
    generate
        if (FRAC_W != 5 || ACC_W != 16) begin : unsupported_parameters
            initial begin
                $display("ERROR: fp2_parallel_mac_ref only supports FRAC_W=5, ACC_W=16 (got FRAC_W=%0d, ACC_W=%0d)", FRAC_W, ACC_W);
                $fatal(1, "fp2_parallel_mac_ref: unsupported parameter combination");
            end
        end
    endgenerate

endmodule
