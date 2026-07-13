// axm_chiplet — CHIPLET 1 TOP: axm_core drives the AXI bus, axil_pmon taps it.
// Spec: 11_alink_axi.md AL-05 (27B-routed -> frontier-owned integration).
// Boundary rule (spec): STATUS outputs are registered here; the AXI bus itself
// passes through combinationally to the chiplet pins.
// AXION profile: sync active-high rst; single tool clock.
module axm_chiplet (
  input  logic        clk,
  input  logic        rst,
  input  logic        go,           // from alink_top supervisor
  input  logic [31:0] seed,
  // chiplet AXI4-Lite MASTER port (17 signals, to axs_chiplet)
  output logic        m_axil_awvalid,
  input  logic        m_axil_awready,
  output logic [15:0] m_axil_awaddr,
  output logic        m_axil_wvalid,
  input  logic        m_axil_wready,
  output logic [31:0] m_axil_wdata,
  output logic [3:0]  m_axil_wstrb,
  input  logic        m_axil_bvalid,
  output logic        m_axil_bready,
  input  logic [1:0]  m_axil_bresp,
  output logic        m_axil_arvalid,
  input  logic        m_axil_arready,
  output logic [15:0] m_axil_araddr,
  input  logic        m_axil_rvalid,
  output logic        m_axil_rready,
  input  logic [31:0] m_axil_rdata,
  input  logic [1:0]  m_axil_rresp,
  // registered status
  output logic        done,
  output logic [7:0]  err_cnt,
  output logic [31:0] chk_sig,
  output logic [2:0]  pmon_err,     // {err_stall, err_orphan, err_vdrop}
  output logic [15:0] pmon_cnt_r,   // R-handshake count (traffic liveness probe)
  output logic [7:0]  dbg_bus       // {tmo_sticky, done, gen_state[2:0], eng_state[2:0]}
);

  // core-side wires (bus passes through combinationally)
  logic        c_done, c_tmo;
  logic [7:0]  c_err;
  logic [31:0] c_sig;
  logic [2:0]  c_gen_state, c_eng_state;

  axm_core u_core (
    .clk            (clk),
    .rst            (rst),
    .go             (go),
    .seed           (seed),
    .done           (c_done),
    .err_cnt        (c_err),
    .chk_sig        (c_sig),
    .tmo_sticky     (c_tmo),
    .m_axil_awvalid (m_axil_awvalid),
    .m_axil_awready (m_axil_awready),
    .m_axil_awaddr  (m_axil_awaddr),
    .m_axil_wvalid  (m_axil_wvalid),
    .m_axil_wready  (m_axil_wready),
    .m_axil_wdata   (m_axil_wdata),
    .m_axil_wstrb   (m_axil_wstrb),
    .m_axil_bvalid  (m_axil_bvalid),
    .m_axil_bready  (m_axil_bready),
    .m_axil_bresp   (m_axil_bresp),
    .m_axil_arvalid (m_axil_arvalid),
    .m_axil_arready (m_axil_arready),
    .m_axil_araddr  (m_axil_araddr),
    .m_axil_rvalid  (m_axil_rvalid),
    .m_axil_rready  (m_axil_rready),
    .m_axil_rdata   (m_axil_rdata),
    .m_axil_rresp   (m_axil_rresp),
    .gen_state      (c_gen_state),
    .eng_state      (c_eng_state)
  );

  // passive monitor taps the same wires the core drives/sees
  logic [15:0] p_cnt_aw, p_cnt_ar, p_cnt_b, p_cnt_r;
  logic [7:0]  p_cnt_errresp;
  logic        p_vdrop, p_orphan, p_stall;

  axil_pmon u_pmon (
    .clk            (clk),
    .rst            (rst),
    .t_axil_awvalid (m_axil_awvalid),
    .t_axil_awready (m_axil_awready),
    .t_axil_awaddr  (m_axil_awaddr),
    .t_axil_wvalid  (m_axil_wvalid),
    .t_axil_wready  (m_axil_wready),
    .t_axil_wdata   (m_axil_wdata),
    .t_axil_wstrb   (m_axil_wstrb),
    .t_axil_bvalid  (m_axil_bvalid),
    .t_axil_bready  (m_axil_bready),
    .t_axil_bresp   (m_axil_bresp),
    .t_axil_arvalid (m_axil_arvalid),
    .t_axil_arready (m_axil_arready),
    .t_axil_araddr  (m_axil_araddr),
    .t_axil_rvalid  (m_axil_rvalid),
    .t_axil_rready  (m_axil_rready),
    .t_axil_rdata   (m_axil_rdata),
    .t_axil_rresp   (m_axil_rresp),
    .cnt_aw         (p_cnt_aw),
    .cnt_ar         (p_cnt_ar),
    .cnt_b          (p_cnt_b),
    .cnt_r          (p_cnt_r),
    .cnt_errresp    (p_cnt_errresp),
    .err_vdrop      (p_vdrop),
    .err_orphan     (p_orphan),
    .err_stall      (p_stall)
  );

  // boundary-registered status (spec: register status, NOT the AXI bus)
  always_ff @(posedge clk) begin
    if (rst) begin
      done       <= 1'b0;
      err_cnt    <= '0;
      chk_sig    <= '0;
      pmon_err   <= '0;
      pmon_cnt_r <= '0;
      dbg_bus    <= '0;
    end else begin
      done       <= c_done;
      err_cnt    <= c_err;
      chk_sig    <= c_sig;
      pmon_err   <= {p_stall, p_orphan, p_vdrop};
      pmon_cnt_r <= p_cnt_r;
      dbg_bus    <= {c_tmo, c_done, c_gen_state, c_eng_state};
    end
  end

endmodule // END axm_chiplet
