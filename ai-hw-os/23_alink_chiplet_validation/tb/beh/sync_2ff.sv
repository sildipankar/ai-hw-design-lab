// TB-ONLY BEHAVIORAL MODEL of sync_2ff (spec 01_common_ip.md C-07).
// Blackbox stand-in so frontier-owned CDC DUTs (pulse_sync, async_fifo) can simulate
// before local models deliver the real body for rtl\stubs\sync_2ff.sv per THE LOOP.
// NEVER put this file in a synthesis/IXCOM filelist.
module sync_2ff #(
  parameter int unsigned WIDTH = 1
) (
  input  logic             clk_dst,
  input  logic             rst_dst,
  input  logic [WIDTH-1:0] d,
  output logic [WIDTH-1:0] q
);
  (* ASYNC_REG = "true" *) logic [WIDTH-1:0] meta;
  always_ff @(posedge clk_dst) begin
    if (rst_dst) begin
      meta <= '0;
      q    <= '0;
    end else begin
      meta <= d;
      q    <= meta;
    end
  end
endmodule // END sync_2ff (TB behavioral)
