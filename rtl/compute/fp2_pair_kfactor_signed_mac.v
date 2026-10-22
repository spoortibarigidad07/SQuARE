// =====================================================================
// fp2_pair_kfactor_signed_mac.v
//
// CLASSIFICATION (read this before comparing to fp2_parallel_mac_ref.v):
//   fp2_pair_kfactor_signed_mac.v = optimized PACKED-PAIR FP2 MAC,
//   valid ONLY when operands use the packed-pair encoding (Table I:
//   two values sharing one 4-bit {S,EM,C} code, Sec. 1.4 of
//   docs/DESIGN_NOTES.md). It is NOT directly comparable to
//   fp2_parallel_mac_ref.v (independent two-lane FP2 reference MAC,
//   different input encoding entirely) unless the input encoding is
//   first made identical AND equivalence is demonstrated by an actual
//   testbench, not assumed from both modules doing "FP2 MAC things."
//   See docs/DESIGN_NOTES.md Sec. 6.4 for why the K-factor trick this
//   file implements does not have an analogous form for independent
//   lanes.
//
// SIGNED-K variant of fp2_pair_kfactor_mac.v (see that file for the
// corrected slot-coefficient derivation, confirmed by direct visual
// inspection of the rendered Table I/II -- docs/DESIGN_NOTES.md
// Sec. 0.3). Computes an explicit combined signed factor
//     K_signed = (sign_a^sign_w ? -1:+1) * K,   K in {-2,-1,0,1,2}
// so K_signed ranges over {-2,-1,0,1,2} (note: with sign folded in, the
// achievable combined range is still exactly 5 values, same set as K
// alone, since sign flips values across zero symmetrically), then
// scales the single magnitude product (mag_a*mag_w) by K_signed
// directly.
//
// Verified bit-exact against fp2_pair_kfactor_mac.v and
// fp2_pair_mac_fp2xfp2.v across all 1024 combinations in
// tb_fp2_pair.v, with an occurrence tally confirming every value in
// {-2,-1,0,1,2} is genuinely reached.
// =====================================================================
module fp2_pair_kfactor_signed_mac #(
    parameter ACC_W = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear_acc,
    input  wire                     valid_in,
    input  wire                     is_e0m1_w,
    input  wire                     is_e0m1_a,
    input  wire [3:0]               wp,
    input  wire [3:0]               ap,
    output reg  signed [ACC_W-1:0]  acc,
    output reg                      valid_out,
    output wire signed [2:0]        k_signed_dbg // exposed for observability/debug
);
    localparam GLOBAL_EXTRA_SHIFT = 6;

    wire sign_a = ap[3];
    wire em_a   = ap[2];

    wire sign_w = wp[3];
    wire em_w   = wp[2];

    function [1:0] fp2_mag2x_nz;
        input mode;
        input bitv;
        begin
            if (mode == 1'b0)
                fp2_mag2x_nz = bitv ? 2'd1 : 2'd2;
            else
                fp2_mag2x_nz = bitv ? 2'd3 : 2'd2;
        end
    endfunction

    wire [1:0] mag_a = fp2_mag2x_nz(is_e0m1_a, em_a);
    wire [1:0] mag_w = fp2_mag2x_nz(is_e0m1_w, em_w);

    wire [3:0] mag_prod = mag_a * mag_w;              // 0..9, the ONLY multiply

    function signed [1:0] slot_k1;
        input [3:0] code;
        begin
            if (code == 4'b0000)       slot_k1 = 2'sd0;
            else if (code[1:0]==2'b01) slot_k1 = 2'sd0;
            else                        slot_k1 = 2'sd1; // C=00,10,11 all have slot1=+1
        end
    endfunction
    function signed [1:0] slot_k2;
        input [3:0] code;
        begin
            if (code == 4'b0000)       slot_k2 = 2'sd0;
            else if (code[1:0]==2'b00) slot_k2 = -2'sd1;
            else if (code[1:0]==2'b10) slot_k2 = 2'sd0;
            else                        slot_k2 = 2'sd1; // C=01,11
        end
    endfunction

    wire signed [1:0] k1a = slot_k1(ap);
    wire signed [1:0] k2a = slot_k2(ap);
    wire signed [1:0] k1w = slot_k1(wp);
    wire signed [1:0] k2w = slot_k2(wp);

    wire signed [3:0] k_mag_signed = (k1a*k1w) + (k2a*k2w); // {-2,-1,0,1,2}

    wire sign_prod = sign_a ^ sign_w;

    // Explicit combined signed K
    wire signed [2:0] k_signed = sign_prod ? -k_mag_signed[2:0] : k_mag_signed[2:0];
    assign k_signed_dbg = k_signed;

    reg signed [6:0] scaled_mag_signed;
    always @(*) begin
        case (k_signed)
            -3'sd2:  scaled_mag_signed = -{1'b0, mag_prod, 1'b0};
            -3'sd1:  scaled_mag_signed = -{3'b000, mag_prod};
             3'sd0:  scaled_mag_signed =  7'sd0;
             3'sd1:  scaled_mag_signed =  {3'b000, mag_prod};
             3'sd2:  scaled_mag_signed =  {1'b0, mag_prod, 1'b0};
            default: scaled_mag_signed =  7'sd0;
        endcase
    end

    wire signed [ACC_W-1:0] partial_signed =
        $signed(scaled_mag_signed) <<< GLOBAL_EXTRA_SHIFT;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc       <= {ACC_W{1'b0}};
            valid_out <= 1'b0;
        end else begin
            if (clear_acc)
                acc <= {ACC_W{1'b0}};
            if (valid_in) begin
                acc <= (clear_acc ? {ACC_W{1'b0}} : acc) + partial_signed;
                valid_out <= 1'b1;
            end else begin
                valid_out <= 1'b0;
            end
        end
    end

endmodule

