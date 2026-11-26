module mac_unit #(
  parameter int DATA_W = 8,
  parameter int ACC_W  = 32
)(
  input  logic                     clk,
  input  logic                     rst_n,
  input  logic                     clr,
  input  logic signed [DATA_W-1:0] a,
  input  logic signed [DATA_W-1:0] b,
  output logic signed [ACC_W-1:0]  acc
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)    acc <= '0;
    else if (clr)  acc <= '0;
    else           acc <= acc + (a * b);
  end
endmodule
