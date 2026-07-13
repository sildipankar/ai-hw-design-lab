// axm_chiplet_sva — bound assertions for axm_chiplet (spec 11_alink_axi.md AL-05).
// Bound from the TB: bind axm_chiplet axm_chiplet_sva u_sva (.*);
// (c_done / c_tmo are DUT internals, connected by name via .*)
// Integration-level checks: boundary registering and dbg_bus packing.
module axm_chiplet_sva (
  input logic        clk, rst,
  input logic        m_axil_awvalid, m_axil_wvalid, m_axil_arvalid,
  input logic        m_axil_bready, m_axil_rready,
  input logic        done,
  input logic [7:0]  err_cnt,
  input logic [2:0]  pmon_err,
  input logic [7:0]  dbg_bus,
  input logic        c_done, c_tmo
);

  // shadows
  logic c_done_q, c_tmo_q, done_q;
  always_ff @(posedge clk) begin
    c_done_q <= !rst && c_done;
    c_tmo_q  <= !rst && c_tmo;
    done_q   <= !rst && done;
  end

  // catches: status NOT boundary-registered (done must lag core done by 1 cycle)
  ap_done_is_registered: assert property (@(posedge clk) disable iff (rst)
    done == c_done_q
  );

  // catches: dbg_bus packing broken — bit7=tmo_sticky, bit6=done (both registered)
  ap_dbg_bus_packing: assert property (@(posedge clk) disable iff (rst)
    (dbg_bus[7] == c_tmo_q) && (dbg_bus[6] == c_done_q)
  );

  // catches: done latch dropping mid-run (must be stable once set until rst)
  ap_done_sticky: assert property (@(posedge clk) disable iff (rst)
    done_q |-> done
  );

  // catches: X on chiplet outputs after reset (deliberately NO disable iff)
  ap_no_x: assert property (@(posedge clk)
    !rst |-> !$isunknown({done, err_cnt, pmon_err, dbg_bus,
                          m_axil_awvalid, m_axil_wvalid, m_axil_arvalid,
                          m_axil_bready, m_axil_rready})
  );

  // vacuity guards
  cp_test_finished: cover property (@(posedge clk) done);
  cp_traffic_ran:   cover property (@(posedge clk) m_axil_awvalid ##[1:$] m_axil_arvalid);

endmodule // END axm_chiplet_sva
