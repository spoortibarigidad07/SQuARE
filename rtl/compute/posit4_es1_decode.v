// =====================================================================
// posit4_es1_decode.v  --  Posit(4,1) operand-pair decoder (Std. Ref.)
//
// Decodes two Posit(4,1) codewords and returns the product's sign,
// the product exponent exp_p = exp_a + exp_b (every nonzero finite
// Posit(4,1) value is an exact signed power of two), and the zero and
// NaR (Not-a-Real) flags.
// =====================================================================
module posit4_es1_decode (
    input  wire [3:0]        a,
    input  wire [3:0]        b,
    output wire               sign_prod,
    output wire signed [4:0]  exp_p,       // exp_a + exp_b, range -8..8
    output wire               op_zero,     // either operand decodes to zero
    output wire               nar          // either operand was Not-a-Real
);

    // Posit(4,1) decode table: {is_zero, is_nar, sign, exponent}
    function [6:0] posit4_decode;
        input [3:0] code;
        begin
            case (code)
                4'b0000: posit4_decode = {1'b1,1'b0,1'b0, 4'sd0};
                4'b0001: posit4_decode = {1'b0,1'b0,1'b0,-4'sd4};
                4'b0010: posit4_decode = {1'b0,1'b0,1'b0,-4'sd2};
                4'b0011: posit4_decode = {1'b0,1'b0,1'b0,-4'sd1};
                4'b0100: posit4_decode = {1'b0,1'b0,1'b0, 4'sd0};
                4'b0101: posit4_decode = {1'b0,1'b0,1'b0, 4'sd1};
                4'b0110: posit4_decode = {1'b0,1'b0,1'b0, 4'sd2};
                4'b0111: posit4_decode = {1'b0,1'b0,1'b0, 4'sd4};
                4'b1000: posit4_decode = {1'b0,1'b1,1'b0, 4'sd0};
                4'b1001: posit4_decode = {1'b0,1'b0,1'b1, 4'sd4};
                4'b1010: posit4_decode = {1'b0,1'b0,1'b1, 4'sd2};
                4'b1011: posit4_decode = {1'b0,1'b0,1'b1, 4'sd1};
                4'b1100: posit4_decode = {1'b0,1'b0,1'b1, 4'sd0};
                4'b1101: posit4_decode = {1'b0,1'b0,1'b1,-4'sd1};
                4'b1110: posit4_decode = {1'b0,1'b0,1'b1,-4'sd2};
                4'b1111: posit4_decode = {1'b0,1'b0,1'b1,-4'sd4};
                default: posit4_decode = 7'd0;
            endcase
        end
    endfunction

    wire [6:0] da = posit4_decode(a);
    wire [6:0] db = posit4_decode(b);

    wire is_zero_a = da[6];
    wire is_nar_a  = da[5];
    wire sign_a    = da[4];
    wire signed [3:0] exp_a = da[3:0];

    wire is_zero_b = db[6];
    wire is_nar_b  = db[5];
    wire sign_b    = db[4];
    wire signed [3:0] exp_b = db[3:0];

    assign nar       = is_nar_a | is_nar_b;
    assign op_zero    = is_zero_a | is_zero_b;
    assign sign_prod  = sign_a ^ sign_b;
    assign exp_p       = exp_a + exp_b; // range -8..8

endmodule
