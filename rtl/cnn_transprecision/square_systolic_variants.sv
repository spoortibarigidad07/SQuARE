`default_nettype none

// Fixed-format top-level variants. All use square_systolic_array.

module square_systolic_posit4 #(parameter integer ROWS=2, COLS=2)(
 input wire clk,rst_n,clear,
 input wire [ROWS*8-1:0] a_left,
 input wire [COLS*8-1:0] b_top,
 input wire [ROWS-1:0] a_valid,
 input wire [COLS-1:0] b_valid,
 output wire [ROWS*COLS*32-1:0] acc_flat,
 output wire [ROWS*COLS-1:0] result_valid,nar_seen,overflow
);
 square_systolic_array #(.ROWS(ROWS),.COLS(COLS),.FORMAT(0),
  .FP2_FORMAT(0),.ACC_W(32),.SATURATE(0)) u_array(
 .clk(clk),.rst_n(rst_n),.clear(clear),.a_left(a_left),.b_top(b_top),
 .a_valid(a_valid),.b_valid(b_valid),.acc_flat(acc_flat),
 .result_valid(result_valid),.nar_seen(nar_seen),.overflow(overflow));
endmodule

module square_systolic_fp4_e2m1 #(parameter integer ROWS=2, COLS=2)(
 input wire clk,rst_n,clear,
 input wire [ROWS*8-1:0] a_left,
 input wire [COLS*8-1:0] b_top,
 input wire [ROWS-1:0] a_valid,
 input wire [COLS-1:0] b_valid,
 output wire [ROWS*COLS*32-1:0] acc_flat,
 output wire [ROWS*COLS-1:0] result_valid,nar_seen,overflow
);
 square_systolic_array #(.ROWS(ROWS),.COLS(COLS),.FORMAT(1),
  .FP2_FORMAT(0),.ACC_W(32),.SATURATE(0)) u_array(
 .clk(clk),.rst_n(rst_n),.clear(clear),.a_left(a_left),.b_top(b_top),
 .a_valid(a_valid),.b_valid(b_valid),.acc_flat(acc_flat),
 .result_valid(result_valid),.nar_seen(nar_seen),.overflow(overflow));
endmodule

module square_systolic_fp2_e1m0 #(parameter integer ROWS=2, COLS=2)(
 input wire clk,rst_n,clear,
 input wire [ROWS*8-1:0] a_left,
 input wire [COLS*8-1:0] b_top,
 input wire [ROWS-1:0] a_valid,
 input wire [COLS-1:0] b_valid,
 output wire [ROWS*COLS*32-1:0] acc_flat,
 output wire [ROWS*COLS-1:0] result_valid,nar_seen,overflow
);
 square_systolic_array #(.ROWS(ROWS),.COLS(COLS),.FORMAT(2),
  .FP2_FORMAT(0),.ACC_W(32),.SATURATE(0)) u_array(
 .clk(clk),.rst_n(rst_n),.clear(clear),.a_left(a_left),.b_top(b_top),
 .a_valid(a_valid),.b_valid(b_valid),.acc_flat(acc_flat),
 .result_valid(result_valid),.nar_seen(nar_seen),.overflow(overflow));
endmodule

module square_systolic_fp2_e0m1 #(parameter integer ROWS=2, COLS=2)(
 input wire clk,rst_n,clear,
 input wire [ROWS*8-1:0] a_left,
 input wire [COLS*8-1:0] b_top,
 input wire [ROWS-1:0] a_valid,
 input wire [COLS-1:0] b_valid,
 output wire [ROWS*COLS*32-1:0] acc_flat,
 output wire [ROWS*COLS-1:0] result_valid,nar_seen,overflow
);
 square_systolic_array #(.ROWS(ROWS),.COLS(COLS),.FORMAT(2),
  .FP2_FORMAT(1),.ACC_W(32),.SATURATE(0)) u_array(
 .clk(clk),.rst_n(rst_n),.clear(clear),.a_left(a_left),.b_top(b_top),
 .a_valid(a_valid),.b_valid(b_valid),.acc_flat(acc_flat),
 .result_valid(result_valid),.nar_seen(nar_seen),.overflow(overflow));
endmodule

module square_systolic_dp2_e1m0 #(parameter integer ROWS=2, COLS=2)(
 input wire clk,rst_n,clear,
 input wire [ROWS*8-1:0] a_left,
 input wire [COLS*8-1:0] b_top,
 input wire [ROWS-1:0] a_valid,
 input wire [COLS-1:0] b_valid,
 output wire [ROWS*COLS*16-1:0] acc_flat,
 output wire [ROWS*COLS-1:0] result_valid,nar_seen,overflow
);
 square_systolic_array #(.ROWS(ROWS),.COLS(COLS),.FORMAT(3),
  .FP2_FORMAT(0),.ACC_W(16),.SATURATE(1)) u_array(
 .clk(clk),.rst_n(rst_n),.clear(clear),.a_left(a_left),.b_top(b_top),
 .a_valid(a_valid),.b_valid(b_valid),.acc_flat(acc_flat),
 .result_valid(result_valid),.nar_seen(nar_seen),.overflow(overflow));
endmodule

module square_systolic_dp2_e0m1 #(parameter integer ROWS=2, COLS=2)(
 input wire clk,rst_n,clear,
 input wire [ROWS*8-1:0] a_left,
 input wire [COLS*8-1:0] b_top,
 input wire [ROWS-1:0] a_valid,
 input wire [COLS-1:0] b_valid,
 output wire [ROWS*COLS*16-1:0] acc_flat,
 output wire [ROWS*COLS-1:0] result_valid,nar_seen,overflow
);
 square_systolic_array #(.ROWS(ROWS),.COLS(COLS),.FORMAT(3),
  .FP2_FORMAT(1),.ACC_W(16),.SATURATE(1)) u_array(
 .clk(clk),.rst_n(rst_n),.clear(clear),.a_left(a_left),.b_top(b_top),
 .a_valid(a_valid),.b_valid(b_valid),.acc_flat(acc_flat),
 .result_valid(result_valid),.nar_seen(nar_seen),.overflow(overflow));
endmodule

`default_nettype wire
