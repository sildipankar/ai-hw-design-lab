// axil_reg_slice_sva — bound assertions for axil_reg_slice (fix b bridge module).
// Bound from the TB: bind axil_reg_slice axil_reg_slice_sva u_sva (.*);
// Checks the DUT's driven outputs on both faces: forward-channel valids toward the
// slave (m side) and backward-channel valids toward the master (s side).
// xsim workarounds: shadow registers instead of $past/$stable.
module axil_reg_slice_sva (
  input logic        clk, rst,
  input logic        s_axil_awvalid, s_axil_awready,
  input logic        s_axil_wvalid,  s_axil_wready,
  input logic        s_axil_bvalid,  s_axil_bready,
  input logic [1:0]  s_axil_bresp,
  input logic        s_axil_arvalid, s_axil_arready,
  input logic        s_axil_rvalid,  s_axil_rready,
  input logic [31:0] s_axil_rdata,
  input logic        m_axil_awvalid, m_axil_awready,
  input logic [15:0] m_axil_awaddr,
  input logic        m_axil_wvalid,  m_axil_wready,
  input logic [31:0] m_axil_wdata,
  input logic        m_axil_bvalid,  m_axil_bready,
  input logic        m_axil_arvalid, m_axil_arready,
  input logic [15:0] m_axil_araddr,
  input logic        m_axil_rvalid,  m_axil_rready,
  input logic [31:0] m_axil_rdata
);

  // shadows for each DUT-driven valid + its payload
  logic        m_awv_q, m_awr_q, m_wv_q, m_wr_q, m_arv_q, m_arr_q;
  logic        s_bv_q, s_br_q, s_rv_q, s_rr_q;
  logic [15:0] m_awaddr_q, m_araddr_q;
  logic [31:0] m_wdata_q, s_rdata_q;
  logic [1:0]  s_bresp_q;
  always_ff @(posedge clk) begin
    m_awv_q    <= !rst && m_axil_awvalid;  m_awr_q <= m_axil_awready;
    m_wv_q     <= !rst && m_axil_wvalid;   m_wr_q  <= m_axil_wready;
    m_arv_q    <= !rst && m_axil_arvalid;  m_arr_q <= m_axil_arready;
    s_bv_q     <= !rst && s_axil_bvalid;   s_br_q  <= s_axil_bready;
    s_rv_q     <= !rst && s_axil_rvalid;   s_rr_q  <= s_axil_rready;
    m_awaddr_q <= m_axil_awaddr;
    m_araddr_q <= m_axil_araddr;
    m_wdata_q  <= m_axil_wdata;
    s_rdata_q  <= s_axil_rdata;
    s_bresp_q  <= s_axil_bresp;
  end

  // catches: any forward valid dropped before its ready (per-lane FIFO promise P1)
  ap_aw_holds: assert property (@(posedge clk) disable iff (rst)
    (m_awv_q && !m_awr_q) |-> m_axil_awvalid);
  ap_w_holds: assert property (@(posedge clk) disable iff (rst)
    (m_wv_q && !m_wr_q) |-> m_axil_wvalid);
  ap_ar_holds: assert property (@(posedge clk) disable iff (rst)
    (m_arv_q && !m_arr_q) |-> m_axil_arvalid);
  // catches: any backward valid dropped before its ready
  ap_b_holds: assert property (@(posedge clk) disable iff (rst)
    (s_bv_q && !s_br_q) |-> s_axil_bvalid);
  ap_r_holds: assert property (@(posedge clk) disable iff (rst)
    (s_rv_q && !s_rr_q) |-> s_axil_rvalid);

  // catches: payload mutating while its valid is held (skid stability broken)
  ap_awaddr_stable: assert property (@(posedge clk) disable iff (rst)
    (m_awv_q && m_axil_awvalid && !m_awr_q) |-> (m_axil_awaddr == m_awaddr_q));
  ap_wdata_stable: assert property (@(posedge clk) disable iff (rst)
    (m_wv_q && m_axil_wvalid && !m_wr_q) |-> (m_axil_wdata == m_wdata_q));
  ap_araddr_stable: assert property (@(posedge clk) disable iff (rst)
    (m_arv_q && m_axil_arvalid && !m_arr_q) |-> (m_axil_araddr == m_araddr_q));
  ap_rdata_stable: assert property (@(posedge clk) disable iff (rst)
    (s_rv_q && s_axil_rvalid && !s_rr_q) |-> (s_axil_rdata == s_rdata_q));
  ap_bresp_stable: assert property (@(posedge clk) disable iff (rst)
    (s_bv_q && s_axil_bvalid && !s_br_q) |-> (s_axil_bresp == s_bresp_q));

  // catches: X on any handshake output after reset (deliberately NO disable iff)
  ap_no_x: assert property (@(posedge clk)
    !rst |-> !$isunknown({s_axil_awready, s_axil_wready, s_axil_bvalid,
                          s_axil_arready, s_axil_rvalid,
                          m_axil_awvalid, m_axil_wvalid, m_axil_bready,
                          m_axil_arvalid, m_axil_rready})
  );

  // vacuity guards: every lane must see backpressure in the sim
  cp_aw_stall: cover property (@(posedge clk) m_axil_awvalid && !m_axil_awready);
  cp_w_stall:  cover property (@(posedge clk) m_axil_wvalid  && !m_axil_wready);
  cp_ar_stall: cover property (@(posedge clk) m_axil_arvalid && !m_axil_arready);
  cp_b_stall:  cover property (@(posedge clk) s_axil_bvalid  && !s_axil_bready);
  cp_r_stall:  cover property (@(posedge clk) s_axil_rvalid  && !s_axil_rready);

endmodule // END axil_reg_slice_sva
