// axs_regs_sva — bound assertions for axs_regs (spec 11_alink_axi.md AL-07 + fix a).
// Bound from the TB: bind axs_regs axs_regs_sva u_sva (.*);
// (aw_got / w_got are DUT internals, connected by name via .*)
// xsim workarounds: shadow registers instead of $past/$stable.
module axs_regs_sva (
  input logic        clk, rst,
  input logic        s_axil_awvalid, s_axil_awready,
  input logic        s_axil_wvalid, s_axil_wready,
  input logic        s_axil_bvalid, s_axil_bready,
  input logic [1:0]  s_axil_bresp,
  input logic        s_axil_arvalid, s_axil_arready,
  input logic        s_axil_rvalid, s_axil_rready,
  input logic [31:0] s_axil_rdata,
  input logic [1:0]  s_axil_rresp,
  input logic [15:0] wrcnt,
  input logic        aw_got, w_got
);

  // shadows
  logic        bv_q, br_q, rv_q, rr_q;
  logic [1:0]  bresp_q, rresp_q;
  logic [31:0] rdata_q;
  logic [15:0] wrcnt_q;
  always_ff @(posedge clk) begin
    bv_q    <= !rst && s_axil_bvalid;
    br_q    <= s_axil_bready;
    rv_q    <= !rst && s_axil_rvalid;
    rr_q    <= s_axil_rready;
    bresp_q <= s_axil_bresp;
    rresp_q <= s_axil_rresp;
    rdata_q <= s_axil_rdata;
    wrcnt_q <= wrcnt;
  end

  // catches: bvalid dropped before bready (protocol break)
  ap_bvalid_holds: assert property (@(posedge clk) disable iff (rst)
    (bv_q && !br_q) |-> s_axil_bvalid
  );
  // catches: bresp mutating while B stalls
  ap_bresp_stable: assert property (@(posedge clk) disable iff (rst)
    (bv_q && s_axil_bvalid) |-> (s_axil_bresp == bresp_q)
  );
  // catches: rvalid dropped before rready
  ap_rvalid_holds: assert property (@(posedge clk) disable iff (rst)
    (rv_q && !rr_q) |-> s_axil_rvalid
  );
  // catches: rdata/rresp mutating while R stalls (payload-stability law)
  ap_rpayload_stable: assert property (@(posedge clk) disable iff (rst)
    (rv_q && s_axil_rvalid) |-> (s_axil_rdata == rdata_q && s_axil_rresp == rresp_q)
  );

  // catches: fix (a) regression — awready must NOT wait for wvalid (and vice versa):
  // with nothing captured and no response pending, both readys are up unconditionally
  ap_aw_ready_independent: assert property (@(posedge clk) disable iff (rst)
    (!aw_got && !s_axil_bvalid) |-> s_axil_awready
  );
  ap_w_ready_independent: assert property (@(posedge clk) disable iff (rst)
    (!w_got && !s_axil_bvalid) |-> s_axil_wready
  );

  // catches: wrcnt jumping by >1 or counting non-OKAY writes
  ap_wrcnt_steps_by_one: assert property (@(posedge clk) disable iff (rst)
    (wrcnt == wrcnt_q) || (wrcnt == wrcnt_q + 16'd1)
  );

  // catches: X on handshake outputs after reset (deliberately NO disable iff)
  ap_no_x: assert property (@(posedge clk)
    !rst |-> !$isunknown({s_axil_awready, s_axil_wready, s_axil_bvalid,
                          s_axil_arready, s_axil_rvalid})
  );

  // vacuity guards — cp_w_first proves the fix-a path (W captured while AW absent)
  cp_w_first:       cover property (@(posedge clk)
                      s_axil_wvalid && s_axil_wready && !s_axil_awvalid);
  cp_aw_first:      cover property (@(posedge clk)
                      s_axil_awvalid && s_axil_awready && !s_axil_wvalid);
  cp_slverr_write:  cover property (@(posedge clk)
                      s_axil_bvalid && s_axil_bready && s_axil_bresp == 2'b10);
  cp_slverr_read:   cover property (@(posedge clk)
                      s_axil_rvalid && s_axil_rready && s_axil_rresp == 2'b10);
  cp_b_backpress:   cover property (@(posedge clk) s_axil_bvalid && !s_axil_bready);
  cp_r_backpress:   cover property (@(posedge clk) s_axil_rvalid && !s_axil_rready);

endmodule // END axs_regs_sva
