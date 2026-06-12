
module RefModule (
  input clk,
  input L,
  input q_in,
  input r_in,
  output reg Q
);

  // Note: no `initial Q=0`. A real DFF powers up as X; the original
  // testbench's match formula tolerates X on the ref side, so both a
  // candidate with and without an explicit initial value will match.
  always @(posedge clk)
    Q <= L ? r_in : q_in;

endmodule

