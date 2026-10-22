`default_nettype none
// Output-stationary systolic PE. One signed fixed-point accumulation per cell.
// A moves right, B moves down. Both have explicit valid pipelines.
// clear+valid processes the first product into a cleared accumulator.
// Overflow is per-cycle; Posit NaR latches sticky until clear.
module square_systolic_pe #(
    parameter integer FORMAT = 0,
    parameter integer FP2_FORMAT = 0,
    parameter integer ACC_W = 32,
    parameter integer SATURATE = 0
)(
    input  wire clk, rst_n, clear,
    input  wire [7:0] a_in, b_in,
    input  wire a_valid_in, b_valid_in,
    output reg  [7:0] a_out, b_out,
    output reg a_valid_out, b_valid_out,
    output reg signed [ACC_W-1:0] acc,
    output reg result_valid, nar_seen, overflow
);
    wire signed [31:0] product_q8;
    wire product_nar;
    square_lowp_product #(.FORMAT(FORMAT), .FP2_FORMAT(FP2_FORMAT)) u_pp (
        .a(a_in), .b(b_in), .product_q8(product_q8), .nar(product_nar)
    );
    // Wide signed addition preserves carry before optional saturation.
    localparam integer EXT_W = (ACC_W > 32 ? ACC_W : 32) + 2;
    wire signed [EXT_W-1:0] ext_acc = {{(EXT_W-ACC_W){acc[ACC_W-1]}},acc};
    wire signed [EXT_W-1:0] ext_pp = {{(EXT_W-32){product_q8[31]}},product_q8};
    wire signed [EXT_W-1:0] wide_sum = (clear ? {EXT_W{1'b0}} : ext_acc) + ext_pp;
    localparam signed [EXT_W-1:0] MAX_ACC = ({{(EXT_W-1){1'b0}},1'b1} <<< (ACC_W-1)) - 1'b1;
    localparam signed [EXT_W-1:0] MIN_ACC = -({{(EXT_W-1){1'b0}},1'b1} <<< (ACC_W-1));
    wire over_pos = wide_sum > MAX_ACC;
    wire over_neg = wide_sum < MIN_ACC;
    wire signed [ACC_W-1:0] next_acc =
        (SATURATE && over_pos) ? MAX_ACC[ACC_W-1:0] :
        (SATURATE && over_neg) ? MIN_ACC[ACC_W-1:0] : wide_sum[ACC_W-1:0];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out <= 0; b_out <= 0;
            a_valid_out <= 0; b_valid_out <= 0;
            acc <= 0; result_valid <= 0;
            nar_seen <= 0; overflow <= 0;
        end else begin
            a_out <= a_in;
            b_out <= b_in;
            a_valid_out <= a_valid_in;
            b_valid_out <= b_valid_in;
            result_valid <= 0;
            overflow <= 0;
            if (clear) begin
                acc <= 0;
                nar_seen <= 0;
            end
            if (a_valid_in && b_valid_in) begin
                if (product_nar) begin
                    nar_seen <= 1;
                end else begin
                    acc <= next_acc;
                    result_valid <= 1;
                    overflow <= over_pos || over_neg;
                end
            end
        end
    end
endmodule
`default_nettype wire
