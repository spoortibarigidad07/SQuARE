`default_nettype none
// Wishbone classic single-transfer adapter to SQuARE register peripheral.
// Address window decoding is performed by the system interconnect.
module square_wishbone_adapter(
    input wire clk, input wire rst,
    input wire cyc_i, input wire stb_i, input wire we_i,
    input wire [31:0] adr_i, input wire [31:0] dat_i,
    output wire [31:0] dat_o, output wire ack_o
);
    wire peripheral_ack;
    wire [31:0] peripheral_data;
    reg pending;
    reg wait_release;
    reg [7:0] addr_hold;
    reg [31:0] data_hold;
    reg we_hold;
    reg request_pulse;
    reg ack_reg;
    reg [31:0] read_reg;

    always @(posedge clk or posedge rst) begin
      if (rst) begin
        pending <= 1'b0;
        wait_release <= 1'b0;
        request_pulse <= 1'b0;
        ack_reg <= 1'b0;
        addr_hold <= 8'b0;
        data_hold <= 32'b0;
        we_hold <= 1'b0;
        read_reg <= 32'b0;
      end else begin
        request_pulse <= 1'b0;
        ack_reg <= 1'b0;
        if (!cyc_i || !stb_i) wait_release <= 1'b0;
        if (!pending && !wait_release && cyc_i && stb_i) begin
          pending <= 1'b1;
          wait_release <= 1'b1;
          request_pulse <= 1'b1;
          addr_hold <= adr_i[7:0];
          data_hold <= dat_i;
          we_hold <= we_i;
        end
        if (pending && peripheral_ack) begin
          pending <= 1'b0;
          ack_reg <= 1'b1;
          read_reg <= peripheral_data;
        end
      end
    end
    assign ack_o = ack_reg;
    assign dat_o = read_reg;
    square_mac_peripheral u_square(
       .clk(clk), .rst_n(~rst), .req(request_pulse), .we(we_hold),
       .addr(addr_hold), .wdata(data_hold),
       .rdata(peripheral_data), .ack(peripheral_ack)
    );
endmodule
`default_nettype wire
