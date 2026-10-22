// =====================================================================
// fp2_parallel_mac_e1m0.v
//
// FP2-E1M0-only variant: thin wrapper around fp2_parallel_mac_ref.v
// with fmt_sel hardwired to 0. Operand ports match the core exactly:
// strict 2-bit {sign,bit} FP2 codes plus separate per-lane zero
// controls (see fp2_to_fp3.v for why zero isn't part of the 2-bit
// value).
// =====================================================================
module fp2_parallel_mac_e1m0 #(
    parameter ACC_W  = 16,
    parameter FRAC_W = 5
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      clear_acc,
    input  wire                      valid_in,
    input  wire [FRAC_W-1:0]         frac_bits,
    input  wire [1:0]                a0, a1, w0, w1,
    input  wire                      a0_zero, a1_zero, w0_zero, w1_zero,
    output wire signed [ACC_W-1:0]   acc,
    output wire                      valid_out,
    output wire                      overflow,
    output wire signed [7:0]         acc_fxp8
);
    fp2_parallel_mac_ref #(.ACC_W(ACC_W), .FRAC_W(FRAC_W)) u_core (
        .clk(clk), .rst_n(rst_n), .clear_acc(clear_acc), .valid_in(valid_in),
        .fmt_sel(1'b0), .frac_bits(frac_bits),
        .a0(a0), .a1(a1), .w0(w0), .w1(w1),
        .a0_zero(a0_zero), .a1_zero(a1_zero), .w0_zero(w0_zero), .w1_zero(w1_zero),
        .acc(acc), .valid_out(valid_out), .overflow(overflow), .acc_fxp8(acc_fxp8)
    );
endmodule
