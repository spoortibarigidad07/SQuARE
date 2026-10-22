`default_nettype none
// Combinational MAC-product PE for the *existing* CNN parallel-PE banks.
// The original CNN controllers sum all PE products externally.
// No internal accumulator or clock: prevents unaccounted pipeline delays.
// Outputs Q8.8 signed product, optionally scaled to a different fractional
// position (FRAC_BITS). The 16-bit port preserves existing PE connectivity.
module square_cnn_processing_element #(
    parameter integer FORMAT = 0,
    parameter integer FP2_FORMAT = 0,
    parameter integer FRAC_BITS = 8,
    parameter integer RESULT_W = 32
)(
    input  wire [7:0] a,
    input  wire [7:0] b,
    output wire signed [RESULT_W-1:0] result,
    output wire nar
);
    wire signed [31:0] p_q8;
    wire signed [31:0] p_shifted;
    square_lowp_product #(.FORMAT(FORMAT), .FP2_FORMAT(FP2_FORMAT)) u_product (
        .a(a), .b(b), .product_q8(p_q8), .nar(nar)
    );
    generate
        if (FRAC_BITS == 8) begin : no_shift
            assign p_shifted = p_q8;
        end else if (FRAC_BITS > 8) begin : left_shift
            assign p_shifted = p_q8 <<< (FRAC_BITS - 8);
        end else begin : right_shift
            assign p_shifted = p_q8 >>> (8 - FRAC_BITS);
        end
    endgenerate
    // Narrowing (if requested) wraps; 32 bits covers all input product modes.
    assign result = nar ? {RESULT_W{1'b0}} : p_shifted[RESULT_W-1:0];
endmodule
`default_nettype wire
