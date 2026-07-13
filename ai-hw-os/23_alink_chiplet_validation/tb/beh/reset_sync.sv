// TB-ONLY BEHAVIORAL MODEL of reset_sync (spec 01_common_ip.md C-09).
// Blackbox stand-in so alink_top (frontier-owned) can simulate before local models
// deliver the real body per THE LOOP. NEVER put this file in a synthesis filelist.
module reset_sync (
  input  logic clk,
  input  logic arst_n_in,   // async assert
  output logic rst_out      // sync active-high, released 4 clk edges after release
);
  logic [3:0] sh;
  always_ff @(posedge clk or negedge arst_n_in) begin
    if (!arst_n_in) sh <= 4'hF;
    else            sh <= {sh[2:0], 1'b0};
  end
  assign rst_out = sh[3];
endmodule // END reset_sync (TB behavioral)
