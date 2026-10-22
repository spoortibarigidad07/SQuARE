// =====================================================================
// fp4_mac_ref_v2.v  --  FP4-E2M1 reference MAC (Std. Ref.)
//
//     acc <- sat16( A + trunc(p * 2^F) ),   F = frac_bits
//
// where A is the current accumulator, or 0 when clear_acc is asserted.
//
// ---- Product generation ----
// p = (-1)^(s_a ^ s_b) * sig_prod * 2^combined_exp, with sig_prod in
// 0..9 and combined_exp in -2..2 (see fp4_e2m1_decode.v). The aligned
// magnitude is sig_prod shifted by combined_exp + F (range -2..33); a
// negative amount right-shifts, truncating toward zero (the sign is
// applied after the shift).
//
// ---- Reference-style (exact, full-width) accumulation ----
// The contribution is formed exactly in a WIDE_W = 38-bit intermediate
// (9 * 2^33 needs 38 signed bits), added to the sign-extended
// accumulator, and only then saturated to the 16-bit range
// [-32768, 32767].
//
// ---- Outputs ----
// acc       : 16-bit signed fixed-point accumulator (F fractional bits)
// overflow  : 1 when this cycle's result saturated; 0 when valid_out=0
// acc_fxp8  : acc[15:8], an 8-bit view of the accumulator
// valid_out : valid_in delayed by one cycle (one-cycle latency)
// =====================================================================
module fp4_mac_ref_v2 #(
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
    wire [3:0]          sig_prod;
    wire signed [3:0]   combined_exp; // -2..2

    fp4_e2m1_decode u_decode (
        .a(a), .b(b),
        .sign_prod(sign_prod), .sig_prod(sig_prod), .combined_exp(combined_exp)
    );

    // ---- alignment: single shift by combined_exp + frac_bits ----
    localparam WIDE_W  = 38; // exact width for FRAC_W=5 (see header)
    localparam SHIFT_W = FRAC_W + 3; // covers combined_exp(-2..2) + frac_bits(0..2^FRAC_W-1)
    // combined_exp is sign-extended explicitly; both operands share one width.
    wire signed [SHIFT_W-1:0] combined_exp_ext = {{(SHIFT_W-4){combined_exp[3]}}, combined_exp};
    wire signed [SHIFT_W-1:0] frac_bits_ext    = {{(SHIFT_W-FRAC_W){1'b0}}, frac_bits};
    wire signed [SHIFT_W-1:0] combined_shift    = combined_exp_ext + frac_bits_ext;
    wire signed [WIDE_W-1:0] sig_prod_ext = {{(WIDE_W-4){1'b0}}, sig_prod};
    wire signed [WIDE_W-1:0] magnitude_wide =
        (combined_shift >= 0) ? (sig_prod_ext <<< combined_shift)
                               : (sig_prod_ext >>> (-combined_shift));

    wire signed [WIDE_W-1:0] partial_signed =
        sign_prod ? -magnitude_wide : magnitude_wide;

    // ---- full-width add, then saturate ----
    wire signed [ACC_W-1:0]  base_acc     = clear_acc ? {ACC_W{1'b0}} : acc;
    wire signed [WIDE_W-1:0] base_acc_ext = {{(WIDE_W-ACC_W){base_acc[ACC_W-1]}}, base_acc};
    wire signed [WIDE_W-1:0] sum_wide     = base_acc_ext + partial_signed;

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

    assign acc_fxp8 = acc[ACC_W-1:ACC_W-8];

    // ---- Parameter guard ----
    // WIDE_W is computed for FRAC_W=5, ACC_W=16 only; any other
    // combination stops simulation/elaboration with an error.
    generate
        if (FRAC_W != 5 || ACC_W != 16) begin : unsupported_parameters
            initial begin
                $display("ERROR: fp4_mac_ref_v2 only supports FRAC_W=5, ACC_W=16 (got FRAC_W=%0d, ACC_W=%0d)", FRAC_W, ACC_W);
                $fatal(1, "fp4_mac_ref_v2: unsupported parameter combination");
            end
        end
    endgenerate

endmodule
