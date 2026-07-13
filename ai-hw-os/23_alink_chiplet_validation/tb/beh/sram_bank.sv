// TB-ONLY BEHAVIORAL MODEL of sram_bank (spec 03_chiplet_memio.md MI-01).
// Blackbox stand-in so axs_mem (frontier-owned) can simulate before local models
// deliver the real body per THE LOOP. NEVER put this file in a synthesis filelist.
module sram_bank #(
  parameter int unsigned DW    = 32,
  parameter int unsigned DEPTH = 1024,
  parameter int unsigned AW    = $clog2(DEPTH)
) (
  input  logic          clk,
  input  logic          en,
  input  logic          we,
  input  logic [AW-1:0] addr,
  input  logic [DW-1:0] wdata,
  output logic [DW-1:0] rdata,
  output logic          rvalid
);
  logic [DW-1:0] mem [DEPTH];
  always_ff @(posedge clk) begin
    if (en && we)  mem[addr] <= wdata;
    if (en && !we) rdata     <= mem[addr];   // 1-cycle latency, registered
    rvalid <= en && !we;
  end
endmodule // END sram_bank (TB behavioral)
