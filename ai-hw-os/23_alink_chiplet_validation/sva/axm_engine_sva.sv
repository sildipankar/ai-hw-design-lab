// axm_engine_sva — bound assertions for axm_engine (spec 11_alink_axi.md AL-02).
// Bound from the TB: bind axm_engine axm_engine_sva u_sva (.*);
// (tmo_cnt is a DUT internal, connected by name via .*)
// xsim workarounds: shadow registers instead of $past/$stable.
module axm_engine_sva (
  input logic        clk, rst,
  input logic        cmd_valid, cmd_ready,
  input logic        rsp_valid, rsp_err,
  input logic        m_axil_awvalid, m_axil_awready,
  input logic [15:0] m_axil_awaddr,
  input logic        m_axil_wvalid, m_axil_wready,
  input logic [31:0] m_axil_wdata,
  input logic        m_axil_bvalid, m_axil_bready,
  input logic        m_axil_arvalid, m_axil_arready,
  input logic [15:0] m_axil_araddr,
  input logic        m_axil_rvalid, m_axil_rready,
  input logic        tmo_sticky,
  input logic [2:0]  state_dbg,
  input logic [11:0] tmo_cnt
);

  // shadows
  logic        awv_q, awr_q, wv_q, wr_q, arv_q, arr_q, tmo_q;
  logic [15:0] awaddr_q, araddr_q;
  logic [31:0] wdata_q;
  always_ff @(posedge clk) begin
    awv_q    <= !rst && m_axil_awvalid;
    awr_q    <= m_axil_awready;
    wv_q     <= !rst && m_axil_wvalid;
    wr_q     <= m_axil_wready;
    arv_q    <= !rst && m_axil_arvalid;
    arr_q    <= m_axil_arready;
    tmo_q    <= (tmo_cnt == 12'hFFF);          // timeout abort fires this cycle
    awaddr_q <= m_axil_awaddr;
    araddr_q <= m_axil_araddr;
    wdata_q  <= m_axil_wdata;
  end

  // catches: awvalid dropped before awready without a timeout abort (protocol break)
  ap_awvalid_holds: assert property (@(posedge clk) disable iff (rst)
    (awv_q && !awr_q && !tmo_q) |-> m_axil_awvalid
  );
  // catches: wvalid dropped before wready without a timeout abort
  ap_wvalid_holds: assert property (@(posedge clk) disable iff (rst)
    (wv_q && !wr_q && !tmo_q) |-> m_axil_wvalid
  );
  // catches: arvalid dropped before arready without a timeout abort
  ap_arvalid_holds: assert property (@(posedge clk) disable iff (rst)
    (arv_q && !arr_q && !tmo_q) |-> m_axil_arvalid
  );

  // catches: payload mutating while a valid is held (q_addr/q_wdata not stable)
  ap_awaddr_stable: assert property (@(posedge clk) disable iff (rst)
    (awv_q && m_axil_awvalid) |-> (m_axil_awaddr == awaddr_q)
  );
  ap_wdata_stable: assert property (@(posedge clk) disable iff (rst)
    (wv_q && m_axil_wvalid) |-> (m_axil_wdata == wdata_q)
  );
  ap_araddr_stable: assert property (@(posedge clk) disable iff (rst)
    (arv_q && m_axil_arvalid) |-> (m_axil_araddr == araddr_q)
  );

  // catches: command accepted outside IDLE (double-buffering bug family)
  ap_cmd_ready_iff_idle: assert property (@(posedge clk) disable iff (rst)
    cmd_ready == (state_dbg == 3'd0)
  );

  // catches: rsp_valid wider than one cycle (RESP state must be single-cycle)
  ap_rsp_is_pulse: assert property (@(posedge clk) disable iff (rst)
    rsp_valid |=> !rsp_valid
  );

  // catches: read and write in flight together (one-outstanding violated)
  ap_never_rd_and_wr: assert property (@(posedge clk) disable iff (rst)
    !((m_axil_awvalid || m_axil_wvalid) && m_axil_arvalid)
  );

  // catches: X on bus controls after reset (deliberately NO disable iff)
  ap_no_x: assert property (@(posedge clk)
    !rst |-> !$isunknown({m_axil_awvalid, m_axil_wvalid, m_axil_arvalid,
                          m_axil_bready, m_axil_rready, rsp_valid, cmd_ready})
  );

  // vacuity guards
  cp_write_done:     cover property (@(posedge clk) m_axil_bvalid && m_axil_bready);
  cp_read_done:      cover property (@(posedge clk) m_axil_rvalid && m_axil_rready);
  cp_aw_before_w:    cover property (@(posedge clk)
                       (!m_axil_awvalid && m_axil_wvalid));   // AW retired first
  cp_w_before_aw:    cover property (@(posedge clk)
                       (m_axil_awvalid && !m_axil_wvalid && wv_q)); // W retired first
  cp_timeout_fired:  cover property (@(posedge clk) tmo_sticky);
  cp_err_response:   cover property (@(posedge clk) rsp_valid && rsp_err);

endmodule // END axm_engine_sva
