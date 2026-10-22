// =====================================================================
// fp2_pair_mac_fp2xfp2.v
//
// Section IV-E "FP2xFP2 Processing Unit" (Dang et al.) -- BOTH the
// weight pair and the activation pair are stored in the packed 4-bit
// FP2 format; this module unpacks both, runs the two element-level
// FP2xFP2 products (reusing the verified fp2_pp.v primitive), and
// sums them into a single-cycle 2-tap Psum, matching the paper's
// description of reducing FP2xFP2 computation "by approximately
// one-quarter" versus a naive dense floating-point implementation.
// =====================================================================
module fp2_pair_mac_fp2xfp2 #(
    parameter ACC_W = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear_acc,
    input  wire                     valid_in,
    input  wire                     is_e0m1_w,   // weight-pair FP2 mode
    input  wire                     is_e0m1_a,   // activation-pair FP2 mode
    input  wire [3:0]               wp,          // packed weight pair
    input  wire [3:0]               ap,          // packed activation pair
    output reg  signed [ACC_W-1:0]  acc,
    output reg                      valid_out
);

    wire [3:0] w1, w2, a1, a2;
    fp2_pair_unpack u_unpack_w (.wp(wp), .is_e0m1(is_e0m1_w), .elem1(w1), .elem2(w2));
    fp2_pair_unpack u_unpack_a (.wp(ap), .is_e0m1(is_e0m1_a), .elem1(a1), .elem2(a2));

    wire sign_p1, sign_p2;
    wire [ACC_W-1:0] pp1, pp2;

    fp2_pp #(.ACC_W(ACC_W)) u_pp1 (.a(a1), .b_in(w1), .sign_prod(sign_p1), .partial(pp1));
    fp2_pp #(.ACC_W(ACC_W)) u_pp2 (.a(a2), .b_in(w2), .sign_prod(sign_p2), .partial(pp2));

    wire signed [ACC_W-1:0] term1 = sign_p1 ? -$signed(pp1) : $signed(pp1);
    wire signed [ACC_W-1:0] term2 = sign_p2 ? -$signed(pp2) : $signed(pp2);
    wire signed [ACC_W-1:0] psum  = term1 + term2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc <= {ACC_W{1'b0}};
            valid_out <= 1'b0;
        end else begin
            if (clear_acc)
                acc <= {ACC_W{1'b0}};
            if (valid_in) begin
                acc <= (clear_acc ? {ACC_W{1'b0}} : acc) + psum;
                valid_out <= 1'b1;
            end else begin
                valid_out <= 1'b0;
            end
        end
    end

endmodule
