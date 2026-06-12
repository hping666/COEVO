
module RefModule (
  input clk,
  input [7:0] d,
  output reg [7:0] q
);

  // Note: no `initial q=0`. A real DFF powers up as X; the original
  // testbench's match formula `ref === (ref ^ dut ^ ref)` tolerates X
  // on the ref side (X===X is true in Verilog), so both a candidate
  // with and without an explicit initial value will match.
  always @(posedge clk)
    q <= d;

endmodule

