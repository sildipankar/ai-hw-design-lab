// evt_counter — saturating event counter with sticky saturation flag.
// Spec: 22_gold_standard/README.md. Style reference for all generated RTL.

module evt_counter #(
  parameter int unsigned W = 8
) (
  input  logic         clk,
  input  logic         rst_n,
  input  logic         en,
  input  logic         evt_i,
  input  logic         clear_i,
  output logic [W-1:0] count_o,
  output logic         sat_o
);

  localparam logic [W-1:0] MAX = '1;

  logic count_up;
  logic at_max;

  assign count_up = en && evt_i && !clear_i;   // clear wins over count
  assign at_max   = (count_o == MAX);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count_o <= '0;
      sat_o   <= 1'b0;
    end else if (clear_i) begin
      count_o <= '0;
      sat_o   <= 1'b0;
    end else if (count_up) begin
      if (at_max) sat_o <= 1'b1;               // saturate: hold value, set sticky flag
      else        count_o <= count_o + W'(1);
    end
  end

endmodule // END evt_counter
