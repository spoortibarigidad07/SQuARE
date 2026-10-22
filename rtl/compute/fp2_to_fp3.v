// =====================================================================
// fp2_to_fp3.v  --  FP2 operand decoder (Std. Ref.)
//
// Converts one FP2 operand into the internal {sign, E, M} form:
//
//   E=0, M=0 -> 0
//   E=0, M=1 -> 0.5
//   E=1, M=0 -> 1.0
//   E=1, M=1 -> 1.5
//
// Operand interface: a 2-bit FP2 value code {sign, bit} plus a separate
// zero-mask bit (zero_in). Both formats use all four codes for nonzero
// values, so zero is signalled by the mask.
//
// ---- Decode table: FP2-E1M0 (fmt_sel=0) ----
//   zero=1          -> 0
//   zero=0, bit=0   -> +-1.0   (sign decides +/-)
//   zero=0, bit=1   -> +-0.5   (sign decides +/-)
//
// ---- Decode table: FP2-E0M1 (fmt_sel=1) ----
//   zero=1          -> 0
//   zero=0, bit=0   -> +-1.0   (sign decides +/-)
//   zero=0, bit=1   -> +-1.5   (sign decides +/-)
//
// {E,M} read as a 2-bit unsigned integer equals twice the magnitude
// (mag2x = 0..3).
// =====================================================================
module fp2_to_fp3 (
    input  wire sign_in,     // bit 1 of the 2-bit FP2 value code
    input  wire bit_in,      // bit 0 of the 2-bit FP2 value code
    input  wire zero_in,     // zero-mask bit
    input  wire fmt_sel,     // 0 = E1M0, 1 = E0M1
    output wire fp3_sign,
    output wire fp3_e,
    output wire fp3_m
);
    assign fp3_sign = zero_in ? 1'b0 : sign_in;
    assign fp3_e     = zero_in ? 1'b0 : (fmt_sel ? 1'b1 : ~bit_in);
    assign fp3_m     = zero_in ? 1'b0 : bit_in;  // M=bit_in in both modes (see tables above)
endmodule

