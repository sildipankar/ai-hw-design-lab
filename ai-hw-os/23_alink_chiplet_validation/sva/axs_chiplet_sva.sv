// axs_chiplet_sva — bound assertions for axs_chiplet (spec 11_alink_axi.md AL-10).
// Bound from the TB: bind axs_chiplet axs_chiplet_sva u_sva (.*);
// (c_wrcnt / c_mem_wr_cnt are DUT internals, connected by name via .*)
// Integration-level checks: boundary registering and probe consistency.
module axs_chiplet_sva (
  input logic        clk, rst,
  input logic        s_axil_awready, s_axil_wready, s_axil_bvalid,
  input logic        s_axil_arready, s_axil_rvalid,
  input logic [1:0]  dbg_sel,
  input logic [31:0] dbg_scratch0,
  input logic [15:0] dbg_wrcnt, dbg_mem_wr_cnt,
  input logic [15:0] c_wrcnt, c_mem_wr_cnt
);

  // shadows
  logic [15:0] c_wrcnt_q, c_mem_wr_cnt_q;
  always_ff @(posedge clk) begin
    c_wrcnt_q      <= c_wrcnt;
    c_mem_wr_cnt_q <= c_mem_wr_cnt;
  end

  // catches: probes NOT boundary-registered (must lag child probes by 1 cycle)
  ap_wrcnt_registered: assert property (@(posedge clk) disable iff (rst)
    dbg_wrcnt == c_wrcnt_q
  );
  ap_mem_wr_cnt_registered: assert property (@(posedge clk) disable iff (rst)
    dbg_mem_wr_cnt == c_mem_wr_cnt_q
  );

  // catches: X on chiplet outputs after reset (deliberately NO disable iff)
  ap_no_x: assert property (@(posedge clk)
    !rst |-> !$isunknown({s_axil_awready, s_axil_wready, s_axil_bvalid,
                          s_axil_arready, s_axil_rvalid,
                          dbg_sel, dbg_scratch0, dbg_wrcnt, dbg_mem_wr_cnt})
  );

  // vacuity guards: both targets must be exercised (dbg_sel visits 0 and 1 per bit)
  cp_write_to_regs: cover property (@(posedge clk) dbg_sel[0] == 1'b0 && s_axil_bvalid);
  cp_write_to_mem:  cover property (@(posedge clk) dbg_sel[0] == 1'b1 && s_axil_bvalid);
  cp_read_from_mem: cover property (@(posedge clk) dbg_sel[1] == 1'b1 && s_axil_rvalid);

endmodule // END axs_chiplet_sva
