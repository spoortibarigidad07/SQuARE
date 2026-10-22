// =====================================================================
// posit4_mac_ref_v2.v  --  Posit(4,1) reference MAC (Std. Ref.)
//
//     acc <- sat16( A + trunc(p * 2^F) ),   F = frac_bits
//
// where A is the current accumulator, or 0 when clear_acc is asserted.
//
// ---- Product generation ----
// Every nonzero finite Posit(4,1) value is an exact signed power of two,
// so the product is p = (-1)^(s_a ^ s_b) * 2^(E_a + E_b) and its aligned
// magnitude is a single bit: 2^(exp_p + F). The combined shift amount
// exp_p + F (range -8..39) is signed; a negative amount right-shifts,
// truncating toward zero (the sign is applied after the shift).
//
// ---- Reference-style (exact, full-width) accumulation ----
// The contribution is formed exactly in a WIDE_W = 48-bit intermediate
// (the largest magnitude 2^39 needs 41 signed bits), added to the
// sign-extended accumulator, and only then saturated to the 16-bit
// range [-32768, 32767].
//
// ---- Zero and NaR ----
// A zero operand contributes 0. A NaR operand contributes 0 and sets the
// sticky nar_flag, which is cleared by clear_acc (with valid_in).
//
// ---- Outputs ----
// acc       : 16-bit signed fixed-point accumulator (F fractional bits)
// overflow  : 1 when this cycle's result saturated; 0 when valid_out=0
// nar_flag  : sticky NaR indicator for the current dot product
// valid_out : valid_in delayed by one cycle (one-cycle latency)
// =====================================================================
module posit4_mac_ref_v2 #(
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

    // ---- alignment: single shift by exp_p + frac_bits ----
    localparam WIDE_W  = 48; // full-width intermediate (>= 41 bits required)
    localparam SHIFT_W = FRAC_W + 3; // covers exp_p(-8..8) + frac_bits(0..2^FRAC_W-1)
    // exp_p is sign-extended explicitly; both operands share one width.
    wire signed [SHIFT_W-1:0] exp_p_ext     = {{(SHIFT_W-5){exp_p[4]}}, exp_p};
    wire signed [SHIFT_W-1:0] frac_bits_ext = {{(SHIFT_W-FRAC_W){1'b0}}, frac_bits};
    wire signed [SHIFT_W-1:0] combined_shift = exp_p_ext + frac_bits_ext;
    wire signed [WIDE_W-1:0] one_ext = {{(WIDE_W-1){1'b0}}, 1'b1};
    wire signed [WIDE_W-1:0] magnitude_wide =
        op_zero ? {WIDE_W{1'b0}} :
        (combined_shift >= 0) ? (one_ext <<< combined_shift)
                               : (one_ext >>> (-combined_shift));

    wire signed [WIDE_W-1:0] partial_signed =
        (op_zero || nar_w) ? {WIDE_W{1'b0}} :
        (sign_prod ? -magnitude_wide : magnitude_wide);

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
            acc        <= {ACC_W{1'b0}};
            valid_out  <= 1'b0;
            nar_flag_r <= 1'b0;
            overflow   <= 1'b0;
        end else begin
            if (valid_in) begin
                if (clear_acc)
                    nar_flag_r <= 1'b0;

                acc      <= sum_saturated;
                overflow <= ovf_pos | ovf_neg;
                if (skip_nar)
                    nar_flag_r <= 1'b1;
                valid_out <= 1'b1;
            end else begin
                valid_out <= 1'b0;
                overflow  <= 1'b0;
            end
        end
    end

    // ---- Parameter guard ----
    // WIDE_W is sized for FRAC_W=5, ACC_W=16 only; any other
    // combination stops simulation/elaboration with an error.
    generate
        if (FRAC_W != 5 || ACC_W != 16) begin : unsupported_parameters
            initial begin
                $display("ERROR: posit4_mac_ref_v2 only supports FRAC_W=5, ACC_W=16 (got FRAC_W=%0d, ACC_W=%0d)", FRAC_W, ACC_W);
                $fatal(1, "posit4_mac_ref_v2: unsupported parameter combination");
            end
        end
    endgenerate

endmodule
