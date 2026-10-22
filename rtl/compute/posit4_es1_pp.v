// =====================================================================
// posit4_es1_pp.v
// Posit(4, es=1) partial-product generator (combinational).
//
// Every finite nonzero value representable in Posit(4,1) is an exact
// power of two (see Azizi et al., TVLSI'24, Eq.1):
//   {..., -16,-4,-2,-1,-0.5,-0.25,-0.0625, 0, 0.0625,0.25,0.5,1,2,4,16}
// so multiplication reduces to SIGNED EXPONENT ADDITION -- no true
// multiplier is required (this is the same simplification Azizi et al.
// exploit in hardware by using a decode LUT + shifter, Fig. 4(a); here
// it is expressed directly as exponent add + shift-by-add).
//
// Output `partial` is already expressed at the GLOBAL fixed-point scale
// used by sparx_mac_unified.v: value_scaled = partial * (sign?-1:+1),
// where partial = round(|a*b| * 2^GLOBAL_FRAC_BITS), GLOBAL_FRAC_BITS=8.
// =====================================================================
module posit4_es1_pp #(
    parameter ACC_W = 32
)(
    input  wire [3:0]        a,
    input  wire [3:0]        b,
    output wire               sign_prod,
    output wire [ACC_W-1:0]   partial,
    output wire               nar        // either operand was Not-a-Real
);

    // Decode returns {is_zero, is_nar, sign, exp[3:0](signed, -4..4)}
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

    assign nar   = is_nar_a | is_nar_b;
    wire op_zero = is_zero_a | is_zero_b;

    assign sign_prod = sign_a ^ sign_b;

    wire signed [4:0] exp_p    = exp_a + exp_b;      // range -8..8
    wire        [4:0] shift_amt = exp_p + 5'sd8;     // range 0..16 (nonneg)

    // GLOBAL_FRAC_BITS = 8 for this format directly matches the exponent
    // offset above, so no extra re-scaling shift is needed.
    //
    // `partial` is forced to zero for NaR as well as for a zero operand.
    // At the top level (sparx_mac_unified.v / sparx_mac_unified_v2.v)
    // this makes no difference -- both already skip the accumulate step
    // entirely whenever `nar` is asserted, so `partial`'s value was never
    // read in that case anyway. It matters if this module is ever
    // instantiated standalone: without this, a NaR operand paired with
    // an otherwise-normal operand would still produce a plausible-looking
    // nonzero `partial` (from the other operand's real exponent), which
    // a caller who forgets to check `nar` could silently misuse as if it
    // were meaningful data. Zero is still an arbitrary stand-in for "not
    // a number" (NaR has no real value), but it is a far safer default
    // to accidentally consume than an unrelated nonzero one.
    assign partial = (op_zero || nar) ? {ACC_W{1'b0}}
                                      : ({{(ACC_W-1){1'b0}}, 1'b1} << shift_amt);

endmodule
