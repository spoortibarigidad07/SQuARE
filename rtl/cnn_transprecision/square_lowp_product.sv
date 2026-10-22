`default_nettype none
// Exact products at the common Q8.8 scale.
// FORMAT: 0 Posit(4,1); 1 FP4 E2M1; 2 FP2 single; 3 DP2 two-lane FP2.
// Posit/FP4 8-bit operand: [3:0] encoding, upper bits ignored.
// FP2 operand: [1:0] = {sign, magnitude_bit}, [4] = explicit zero.
// DP2 operand: [1:0] lane0, [3:2] lane1, [4] zero0, [5] zero1.
// FP2_FORMAT: 0 E1M0, 1 E0M1. NaR products are inhibited by caller.
module square_lowp_product #(
    parameter integer FORMAT = 0,
    parameter integer FP2_FORMAT = 0
)(
    input  wire [7:0] a,
    input  wire [7:0] b,
    output wire signed [31:0] product_q8,
    output wire nar
);
    generate
        if (FORMAT == 0) begin : posit
            wire s;
            wire [31:0] magnitude;
            wire invalid;
            posit4_es1_pp #(.ACC_W(32)) u_pp (
                .a(a[3:0]), .b(b[3:0]), .sign_prod(s),
                .partial(magnitude), .nar(invalid)
            );
            assign product_q8 = invalid ? 32'sd0 :
                (s ? -$signed(magnitude) : $signed(magnitude));
            assign nar = invalid;
        end else if (FORMAT == 1) begin : fp4
            wire s;
            wire [31:0] magnitude;
            fp4_e2m1_pp #(.ACC_W(32)) u_pp (
                .a(a[3:0]), .b(b[3:0]), .sign_prod(s), .partial(magnitude)
            );
            assign product_q8 = s ? -$signed(magnitude) : $signed(magnitude);
            assign nar = 1'b0;
        end else if (FORMAT == 2 || FORMAT == 3) begin : fp2
            wire s0;
            wire [31:0] p0;
            localparam FP2_FMT_BIT = (FP2_FORMAT != 0);
            wire [3:0] fa0 = {a[1], FP2_FMT_BIT, a[4], a[0]};
            wire [3:0] fb0 = {b[1], FP2_FMT_BIT, b[4], b[0]};
            fp2_pp #(.ACC_W(32)) u_p0 (
                .a(fa0), .b_in(fb0), .sign_prod(s0), .partial(p0)
            );
            wire signed [31:0] t0 = s0 ? -$signed(p0) : $signed(p0);
            if (FORMAT == 3) begin : lane1
                wire s1;
                wire [31:0] p1;
                wire [3:0] fa1 = {a[3], FP2_FMT_BIT, a[5], a[2]};
                wire [3:0] fb1 = {b[3], FP2_FMT_BIT, b[5], b[2]};
                fp2_pp #(.ACC_W(32)) u_p1 (
                    .a(fa1), .b_in(fb1), .sign_prod(s1), .partial(p1)
                );
                wire signed [31:0] t1 = s1 ? -$signed(p1) : $signed(p1);
                assign product_q8 = t0 + t1;
            end else begin : single_lane
                assign product_q8 = t0;
            end
            assign nar = 1'b0;
        end else begin : invalid_format
            assign product_q8 = 32'sd0;
            assign nar = 1'b1;
        end
    endgenerate
endmodule
`default_nettype wire
