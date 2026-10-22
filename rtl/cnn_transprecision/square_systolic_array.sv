`default_nettype none
// 2D output-stationary systolic array. Stream codes with standard skew:
// row r receives operand A[k] at cycle k+r, column c receives B[k]
// at cycle k+c. Cell (r,c) thus multiplies matching k at cycle k+r+c.
// PEs register one-cycle forwarding along the row/column axes.
module square_systolic_array #(
    parameter integer ROWS = 2,
    parameter integer COLS = 2,
    parameter integer FORMAT = 0,
    parameter integer FP2_FORMAT = 0,
    parameter integer ACC_W = 32,
    parameter integer SATURATE = 0
)(
    input wire clk, rst_n, clear,
    input wire [ROWS*8-1:0] a_left,
    input wire [COLS*8-1:0] b_top,
    input wire [ROWS-1:0] a_valid,
    input wire [COLS-1:0] b_valid,
    output wire [ROWS*COLS*ACC_W-1:0] acc_flat,
    output wire [ROWS*COLS-1:0] result_valid,
    output wire [ROWS*COLS-1:0] nar_seen,
    output wire [ROWS*COLS-1:0] overflow
);
    wire [7:0] a_pipe [0:ROWS-1][0:COLS];
    wire [7:0] b_pipe [0:ROWS][0:COLS-1];
    wire av_pipe [0:ROWS-1][0:COLS];
    wire bv_pipe [0:ROWS][0:COLS-1];
    genvar r,c;
    generate
        for (r=0;r<ROWS;r=r+1) begin : rows
            assign a_pipe[r][0] = a_left[r*8+:8];
            assign av_pipe[r][0] = a_valid[r];
        end
        for (c=0;c<COLS;c=c+1) begin : columns
            assign b_pipe[0][c] = b_top[c*8+:8];
            assign bv_pipe[0][c] = b_valid[c];
        end
        for (r=0;r<ROWS;r=r+1) begin : rows_pe
            for (c=0;c<COLS;c=c+1) begin : cols_pe
                square_systolic_pe #(
                    .FORMAT(FORMAT), .FP2_FORMAT(FP2_FORMAT),
                    .ACC_W(ACC_W), .SATURATE(SATURATE)
                ) u_pe (
                    .clk(clk),.rst_n(rst_n),.clear(clear),
                    .a_in(a_pipe[r][c]),.b_in(b_pipe[r][c]),
                    .a_valid_in(av_pipe[r][c]),.b_valid_in(bv_pipe[r][c]),
                    .a_out(a_pipe[r][c+1]),.b_out(b_pipe[r+1][c]),
                    .a_valid_out(av_pipe[r][c+1]),.b_valid_out(bv_pipe[r+1][c]),
                    .acc(acc_flat[(r*COLS+c)*ACC_W+:ACC_W]),
                    .result_valid(result_valid[r*COLS+c]),
                    .nar_seen(nar_seen[r*COLS+c]),
                    .overflow(overflow[r*COLS+c])
                );
            end
        end
    endgenerate
endmodule
`default_nettype wire
