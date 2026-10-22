// =====================================================================
// posit4_es1_decode.v
//
// This module provides the decode-only portion of posit4_es1_pp.v.
//
// It uses the same 16-entry posit4_decode lookup function and produces
// the following decoded values:
//
//   - sign;
//   - exponent;
//   - zero indication; and
//   - NaR indication.
//
// Unlike posit4_es1_pp.v, this module does not generate a fixed Q8.8
// partial value by shifting the decoded magnitude by exp + 8.
//
// In posit4_mac_ref.v, the fixed-scale partial produced by
// posit4_es1_pp.v is subsequently shifted again according to
// frac_bits. The optimized posit4_mac_ref_v2.v implementation avoids
// these two separate shift stages by using this decode-only module and
// computing the final shift directly:
//
//       combined_shift = exp_p + frac_bits
//
// The contribution magnitude is then generated using a single shift
// operation.
//
// The original posit4_es1_pp.v module remains unchanged. It is still
// used by:
//
//   - sparx_mac_unified.v;
//   - sparx_mac_unified_v2.v; and
//   - posit4_mac_ref.v.
//
// This module is therefore an additional decode path intended for the
// optimized Posit(4,1) MAC implementation. It does not replace or
// modify the original preprocessing module.
// =====================================================================

module posit4_es1_decode (
    input  wire [3:0]        a,
    input  wire [3:0]        b,
    output wire               sign_prod,
    output wire signed [4:0]  exp_p,       // exp_a + exp_b, range -8..8
    output wire               op_zero,     // either operand decodes to zero
    output wire               nar          // either operand was Not-a-Real
);

    // Identical to posit4_es1_pp.v's posit4_decode function (copied
    // verbatim -- not re-derived -- to avoid any risk of an accidental
    // re-derivation bug; this table was independently hand-verified
    // against the real Posit(4,es=1) encoding during the area/timing
    // review and is unchanged here).
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
