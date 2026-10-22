// =====================================================================
// fp2_pair_mac_fp4xfp2.v
//
// Section IV-D "FP4xFP2 Processing Unit" (Dang et al.) -- processes ONE
// TRUE packed FP2 weight-pair (4 bits storing W1 and W2, per Table I)
// against TWO independent FP4 activations (Fa, Fb) in a single cycle:
//
//     Psum = Fa*W1 + Fb*W2
//
// feeding one shared fixed-point accumulator (LSB = 2^-8, consistent
// with the rest of this package). This is the actual "4 bits store 2
// weights" datapath the FP2 paper describes for its primary use case
// -- distinct from fp2_pp.v, which is only the per-element primitive
// this module unpacks into and reuses.
// =====================================================================
module fp2_pair_mac_fp4xfp2 #(
    parameter ACC_W = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear_acc,  // start of new dot product
    input  wire                     valid_in,
    input  wire                     is_e0m1,    // block/layer FP2 mode
    input  wire [3:0]               wp,         // packed weight pair {S,EM,C}
    input  wire [3:0]               fa,         // FP4 activation, slot 1
    input  wire [3:0]               fb,         // FP4 activation, slot 2
    output reg  signed [ACC_W-1:0]  acc,
    output reg                      valid_out
);

    wire [3:0] w1_elem, w2_elem;
    fp2_pair_unpack u_unpack (
        .wp(wp), .is_e0m1(is_e0m1),
        .elem1(w1_elem), .elem2(w2_elem)
    );

    wire sign_p1, sign_p2;
    wire [ACC_W-1:0] pp1, pp2;

    fp4_x_fp2_pp #(.ACC_W(ACC_W)) u_pp1 (
        .f(fa), .w(w1_elem), .sign_prod(sign_p1), .partial(pp1)
    );
    fp4_x_fp2_pp #(.ACC_W(ACC_W)) u_pp2 (
        .f(fb), .w(w2_elem), .sign_prod(sign_p2), .partial(pp2)
    );

    wire signed [ACC_W-1:0] term1 = sign_p1 ? -$signed(pp1) : $signed(pp1);
    wire signed [ACC_W-1:0] term2 = sign_p2 ? -$signed(pp2) : $signed(pp2);
    wire signed [ACC_W-1:0] psum  = term1 + term2; // 2-tap dot product, 1 cycle

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
