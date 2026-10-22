// =====================================================================
// fp2_pair_unpack.v
//
// TRUE packed-pair FP2 unpacking, matching Table I of Dang et al.
// (TCAS-I'26, Sec. III) as confirmed by DIRECT VISUAL INSPECTION of the
// rendered PDF table (not text extraction -- see docs/DESIGN_NOTES.md
// Sec. 0.3 for the full correction history; an earlier revision of this
// file got this wrong because a linearized text extraction of Table I
// silently merged two distinct table cells into what looked like one
// descriptive phrase).
//
// Table I, read directly from the rendered table:
//   F1<>0 & F2<>0 (S1=S2)      -> C=11   (same-sign pair, collapses to
//                                          one shared value for both slots)
//   F1<>0 & F2=0               -> C=10   (only slot 1 nonzero)
//   F1=0  & F2<>0               -> C=01   (only slot 2 nonzero)
//   S1<>S2, F1<>0 & F2<>0      -> C=00   (OPPOSITE-SIGN pair: S,E/M fields
//                                          store "same as above" i.e. the
//                                          ordinary same-sign encoding,
//                                          but this ROW's own C-column
//                                          value is 00, separate from
//                                          that "same as above" note)
//   F1=0  & F2=0                -> S=0,E=0,M=0,C=00  (the UNIQUE
//                                          all-fields-zero code)
//
// So C=00 is used for TWO different conditions, disambiguated only by
// whether the rest of the 4-bit code is also all-zero:
//   code == 4'b0000  -> true "both zero"
//   code != 4'b0000 (but C==00) -> opposite-sign pair: (F, -F), where F
//                                  is decoded from the pair's S/EM fields
//                                  exactly as the ordinary same-sign case
//                                  would be.
//
// This was verified against every row of Table II (Sec. IV-E's
// multiplication-factor table) by direct visual cross-check: all 8
// non-trivial (C_F,C_W) rows' printed Psum expressions match exactly
// under this decode (e.g. the K=0 row "(C_F=11,C_W=00): F*W + F*(-W)"
// requires C_W=00 to decode as (W,-W), not (0,0)).
// =====================================================================
module fp2_pair_unpack (
    input  wire [3:0] wp,        // packed pair: {S, EM, C[1:0]}
    input  wire       is_e0m1,   // 0 = E1M0, 1 = E0M1 (block/layer mode)
    output wire [3:0] elem1,     // {sign, mode, zero, b}
    output wire [3:0] elem2
);
    wire s      = wp[3];
    wire em_bit = wp[2];
    wire [1:0] c = wp[1:0];

    // The unique all-fields-zero code is the only genuine "both zero".
    wire is_true_zero = (wp == 4'b0000);
    // Any OTHER code with C=00 is the opposite-sign, both-nonzero pair.
    wire is_opposite_pair = (c == 2'b00) && !is_true_zero;

    wire zero1 = is_true_zero || (c == 2'b01);
    wire zero2 = is_true_zero || (c == 2'b10);

    // Slot 1 always takes the stored sign S. Slot 2 takes the SAME sign
    // S normally, but the OPPOSITE sign in the opposite-pair case.
    wire sign2 = is_opposite_pair ? ~s : s;

    assign elem1 = {s,     is_e0m1, zero1, em_bit};
    assign elem2 = {sign2, is_e0m1, zero2, em_bit};
endmodule

