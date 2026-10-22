`default_nettype none
// SQuARE register-controlled accelerator peripheral. 32-bit, word-aligned bus.
// A transaction is accepted when req && !ack. ack is a registered one-cycle pulse.
module square_mac_peripheral (
    input wire clk, input wire rst_n,
    input wire req, input wire we, input wire [7:0] addr,
    input wire [31:0] wdata, output reg [31:0] rdata,
    output reg ack
);
    reg [1:0] mode;
    reg [4:0] frac;
    reg [3:0] op_a, op_b;
    reg [7:0] pair_operands;
    reg [3:0] pair_zero;
    reg pair_format;
    reg pulse_valid, pulse_clear;
    wire signed [31:0] acc_out;
    wire valid_out, nar_flag, pair_overflow;
    wire signed [15:0] pair_acc;
    wire signed [7:0] pair_acc8;
    wire shared_valid, pair_valid;
    wire signed [31:0] shared_acc;
    wire active = req && !ack;
    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        ack<=0; mode<=0; frac<=8; op_a<=0; op_b<=0;
        pair_operands<=0; pair_zero<=0; pair_format<=0;
        pulse_valid<=0; pulse_clear<=0;
      end else begin
        ack<=active;
        pulse_valid<=0; pulse_clear<=0;
        if (active && we) begin
          case (addr)
            8'h00: begin mode<=wdata[1:0]; frac<=wdata[6:2]; pair_format<=wdata[7]; end
            8'h04: begin op_a<=wdata[3:0]; op_b<=wdata[7:4]; end
            8'h08: pair_operands<=wdata[7:0];
            8'h0c: pair_zero<=wdata[3:0];
            8'h10: begin pulse_valid<=wdata[0]; pulse_clear<=wdata[1]; end
            default: begin end
          endcase
        end
      end
    end
    always @(*) begin
      case (addr)
        8'h00: rdata={24'b0,pair_format,frac,mode};
        8'h04: rdata={24'b0,op_b,op_a};
        8'h08: rdata={24'b0,pair_operands};
        8'h0c: rdata={28'b0,pair_zero};
        8'h14: rdata=acc_out;
        8'h18: rdata={27'b0,nar_flag,pair_overflow,pair_valid,shared_valid,valid_out};
        8'h1c: rdata={{24{pair_acc8[7]}},pair_acc8};
        default:rdata=0;
      endcase
    end
    sparx_mac_unified_v2 #(.ACC_W(32),.FP2P_ACC_W(16)) mac(
      .clk(clk),.rst_n(rst_n),.clear_acc(pulse_clear),.valid_in(pulse_valid),
      .mode_sel(mode),.frac_bits(frac),.a(op_a),.b(op_b),
      .fp2p_fmt_sel(pair_format),.fp2p_frac_bits(frac),
      .fp2p_a0(pair_operands[1:0]),.fp2p_a1(pair_operands[3:2]),
      .fp2p_w0(pair_operands[5:4]),.fp2p_w1(pair_operands[7:6]),
      .fp2p_a0_zero(pair_zero[0]),.fp2p_a1_zero(pair_zero[1]),
      .fp2p_w0_zero(pair_zero[2]),.fp2p_w1_zero(pair_zero[3]),
      .acc(shared_acc),.valid_out(shared_valid),.nar_flag(nar_flag),
      .fp2p_acc(pair_acc),.fp2p_valid_out(pair_valid),
      .fp2p_overflow(pair_overflow),.fp2p_acc_fxp8(pair_acc8),
      .acc_out(acc_out),.valid_out_final(valid_out)
    );
endmodule
`default_nettype wire
