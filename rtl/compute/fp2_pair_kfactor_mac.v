// =====================================================================
// fp2_pair_kfactor_mac.v
//
// CLASSIFICATION: optimized PACKED-PAIR FP2 MAC, valid ONLY when
// operands use the packed-pair encoding (Sec. 1.4 of
// docs/DESIGN_NOTES.md) -- NOT directly comparable to
// fp2_parallel_mac_ref.v (independent two-lane FP2 reference MAC,
// different input encoding) without first proving equivalence via a
// testbench. See docs/DESIGN_NOTES.md Sec. 6.4.
//
// Optimized "K-factor" FP2xFP2 pair MAC (Dang et al. Sec. IV-E), using
// the actual Table II multiplication-factor logic, confirmed by DIRECT
// VISUAL INSPECTION of the rendered PDF (see docs/DESIGN_NOTES.md
// Sec. 0.3 for the correction history -- an earlier revision of this
// file used an incorrect K-formula derived from a mistaken reading of
// Table I's C=00 semantics; this version replaces it).
//
// Per-pair "slot coefficients" (k1,k2), each in {-1,0,+1}, capturing
// how each of the pair's two logical slots contributes once its
// magnitude is factored out (verified against every row of Table II):
//   C=00, non-special (opposite-sign pair)  -> (k1,k2) = (+1,-1)
//   C=01 (only slot 2 nonzero)              -> ( 0,+1)
//   C=10 (only slot 1 nonzero)              -> (+1, 0)
//   C=11 (same-sign pair)                   -> (+1,+1)
//   code == 4'b0000 (true all-zero)         -> ( 0, 0)   [override]
//
// K = k1_a*k1_w + k2_a*k2_w   (in {-2,-1,0,1,2})
// Psum = (sign_a^sign_w ? -1:+1) * K * (mag_a * mag_w)
//
// Still only ONE magnitude multiply (mag_a*mag_w); K and the final
// sign are both cheap selects, matching the paper's "~1/4 workload"
// claim. Verified bit-exact against fp2_pair_mac_fp2xfp2.v (the
// straightforward unpack+2-multiply reference, itself corrected) across
// all 1024 combinations in tb_fp2_pair.v.
// =====================================================================
module fp2_pair_kfactor_mac #(
    parameter ACC_W = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear_acc,
    input  wire                     valid_in,
    input  wire                     is_e0m1_w,
    input  wire                     is_e0m1_a,
    input  wire [3:0]               wp,   // packed weight pair {Sw,EMw,Cw[1:0]}
    input  wire [3:0]               ap,   // packed activation pair {Sa,EMa,Ca[1:0]}
    output reg  signed [ACC_W-1:0]  acc,
    output reg                      valid_out
);
    localparam GLOBAL_EXTRA_SHIFT = 6; // native scale 2^2 -> global 2^8

    wire sign_a = ap[3];
    wire em_a   = ap[2];

    wire sign_w = wp[3];
    wire em_w   = wp[2];

    function [1:0] fp2_mag2x_nz;
        input mode;
        input bitv;
        begin
            if (mode == 1'b0)
                fp2_mag2x_nz = bitv ? 2'd1 : 2'd2; // E1M0
            else
                fp2_mag2x_nz = bitv ? 2'd3 : 2'd2; // E0M1
        end
    endfunction

    wire [1:0] mag_a = fp2_mag2x_nz(is_e0m1_a, em_a);
    wire [1:0] mag_w = fp2_mag2x_nz(is_e0m1_w, em_w);

    wire [3:0] mag_prod = mag_a * mag_w;    // the ONLY multiply, 0..9

    // slot coefficients (k1,k2), each signed in {-1,0,1}
    function signed [1:0] slot_k1;
        input [3:0] code;
        begin
            if (code == 4'b0000)       slot_k1 = 2'sd0;
            else if (code[1:0]==2'b00) slot_k1 = 2'sd1;
            else if (code[1:0]==2'b01) slot_k1 = 2'sd0;
            else if (code[1:0]==2'b10) slot_k1 = 2'sd1;
            else                        slot_k1 = 2'sd1; // C=11
        end
    endfunction
    function signed [1:0] slot_k2;
        input [3:0] code;
        begin
            if (code == 4'b0000)       slot_k2 = 2'sd0;
            else if (code[1:0]==2'b00) slot_k2 = -2'sd1;
            else if (code[1:0]==2'b01) slot_k2 = 2'sd1;
            else if (code[1:0]==2'b10) slot_k2 = 2'sd0;
            else                        slot_k2 = 2'sd1; // C=11
        end
    endfunction

    wire signed [1:0] k1a = slot_k1(ap);
    wire signed [1:0] k2a = slot_k2(ap);
    wire signed [1:0] k1w = slot_k1(wp);
    wire signed [1:0] k2w = slot_k2(wp);

    wire signed [3:0] k_factor = (k1a*k1w) + (k2a*k2w); // in {-2,-1,0,1,2}

    wire sign_prod = sign_a ^ sign_w;

    // scaled_mag_signed = k_factor * mag_prod (magnitude-only multiply
    // already done; this is just select/negate/shift on a value in
    // {-2,-1,0,1,2}), then apply sign_prod on top.
    reg signed [6:0] scaled_mag_signed; // range -18..18
    always @(*) begin
        case (k_factor)
            -4'sd2:  scaled_mag_signed = -{1'b0, mag_prod, 1'b0}; // -2x
            -4'sd1:  scaled_mag_signed = -{3'b000, mag_prod};
             4'sd0:  scaled_mag_signed =  7'sd0;
             4'sd1:  scaled_mag_signed =  {3'b000, mag_prod};
             4'sd2:  scaled_mag_signed =  {1'b0, mag_prod, 1'b0};  // +2x
            default: scaled_mag_signed =  7'sd0;
        endcase
    end

    wire signed [ACC_W-1:0] partial_mag =
        $signed(scaled_mag_signed) <<< GLOBAL_EXTRA_SHIFT;

    wire signed [ACC_W-1:0] partial =
        sign_prod ? -partial_mag : partial_mag;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc       <= {ACC_W{1'b0}};
            valid_out <= 1'b0;
        end else begin
            if (clear_acc)
                acc <= {ACC_W{1'b0}};
            if (valid_in) begin
                acc <= (clear_acc ? {ACC_W{1'b0}} : acc) + partial;
                valid_out <= 1'b1;
            end else begin
                valid_out <= 1'b0;
            end
        end
    end

endmodule

