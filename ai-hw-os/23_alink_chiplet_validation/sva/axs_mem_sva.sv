// axs_mem_sva — bound assertions for axs_mem (spec 11_alink_axi.md AL-08 + fix a).
// Bound from the TB: bind axs_mem axs_mem_sva u_sva (.*);
// (aw_got / w_got / ram_en / ram_we are DUT internals, connected by name via .*)
// xsim workarounds: shadow registers instead of $past/$stable.
module axs_mem_sva (
  input logic        clk, rst,
  input logic        s_axil_awvalid, s_axil_awready,
  input logic        s_axil_wvalid, s_axil_wready,
  input logic        s_axil_bvalid, s_axil_bready,
  input logic        s_axil_arvalid, s_axil_arready,
  input logic        s_axil_rvalid, s_axil_rready,
  input logic [31:0] s_axil_rdata,
  input logic        aw_got, w_got,
  input logic        ram_en, ram_we
);

  // shadows
  logic        bv_q, br_q, rv_q, rr_q, ram_we_q;
  logic [31:0] rdata_q;
  always_ff @(posedge clk) begin
    bv_q     <= !rst && s_axil_bvalid;
    br_q     <= s_axil_bready;
    rv_q     <= !rst && s_axil_rvalid;
    rr_q     <= s_axil_rready;
    rdata_q  <= s_axil_rdata;
    ram_we_q <= !rst && ram_we;
  end

  // catches: bvalid dropped before bready (protocol break)
  ap_bvalid_holds: assert property (@(posedge clk) disable iff (rst)
    (bv_q && !br_q) |-> s_axil_bvalid
  );
  // catches: rvalid dropped before rready
  ap_rvalid_holds: assert property (@(posedge clk) disable iff (rst)
    (rv_q && !rr_q) |-> s_axil_rvalid
  );
  // catches: rdata mutating while R stalls (payload-stability law)
  ap_rdata_stable: assert property (@(posedge clk) disable iff (rst)
    (rv_q && s_axil_rvalid) |-> (s_axil_rdata == rdata_q)
  );

  // catches: RAM write pulse longer than 1 cycle (double write / wr_cnt drift)
  ap_ram_write_is_pulse: assert property (@(posedge clk) disable iff (rst)
    !(ram_we && ram_we_q)
  );
  // catches: we without en (illegal sram_bank drive)
  ap_we_implies_en: assert property (@(posedge clk) disable iff (rst)
    ram_we |-> ram_en
  );

  // catches: fix (a) regression — a captured-but-unexecuted AW must close only ITS
  // ready (never both); ready re-opening while holding a capture = double-accept bug
  ap_awready_not_while_captured: assert property (@(posedge clk) disable iff (rst)
    s_axil_awready |-> !aw_got
  );
  ap_wready_not_while_captured: assert property (@(posedge clk) disable iff (rst)
    s_axil_wready |-> !w_got
  );

  // catches: X on handshake outputs after reset (deliberately NO disable iff)
  ap_no_x: assert property (@(posedge clk)
    !rst |-> !$isunknown({s_axil_awready, s_axil_wready, s_axil_bvalid,
                          s_axil_arready, s_axil_rvalid})
  );

  // vacuity guards — cp_w_first proves the fix-a path through this slave
  cp_w_first:     cover property (@(posedge clk)
                    s_axil_wvalid && s_axil_wready && !s_axil_awvalid);
  cp_ram_write:   cover property (@(posedge clk) ram_en && ram_we);
  cp_ram_read:    cover property (@(posedge clk) ram_en && !ram_we);
  cp_b_backpress: cover property (@(posedge clk) s_axil_bvalid && !s_axil_bready);
  cp_r_backpress: cover property (@(posedge clk) s_axil_rvalid && !s_axil_rready);

endmodule // END axs_mem_sva
