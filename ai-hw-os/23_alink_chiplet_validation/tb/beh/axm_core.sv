// TB-ONLY BEHAVIORAL MODEL of axm_core (spec 11_alink_axi.md AL-04, pure wiring).
// Wires the SIMPLIFIED behavioral cmd_gen to the REAL frontier-owned axm_engine —
// so integration sims exercise the real engine RTL. NEVER synthesize this file.
module axm_core (
  input  logic        clk,
  input  logic        rst,
  input  logic        go,
  input  logic [31:0] seed,
  output logic        done,
  output logic [7:0]  err_cnt,
  output logic [31:0] chk_sig,
  output logic        tmo_sticky,
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
  output logic [2:0]  gen_state,
  output logic [2:0]  eng_state
);
  logic        cmd_valid, cmd_ready, cmd_write;
  logic [15:0] cmd_addr;
  logic [31:0] cmd_wdata;
  logic        rsp_valid, rsp_err;
  logic [31:0] rsp_rdata;

  cmd_gen u_gen (
    .clk(clk), .rst(rst), .go(go), .seed(seed),
    .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_write(cmd_write),
    .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata),
    .rsp_valid(rsp_valid), .rsp_rdata(rsp_rdata), .rsp_err(rsp_err),
    .done(done), .err_cnt(err_cnt), .chk_sig(chk_sig), .state_dbg(gen_state)
  );

  axm_engine u_eng (
    .clk(clk), .rst(rst),
    .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_write(cmd_write),
    .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata),
    .rsp_valid(rsp_valid), .rsp_rdata(rsp_rdata), .rsp_err(rsp_err),
    .m_axil_awvalid(m_axil_awvalid), .m_axil_awready(m_axil_awready),
    .m_axil_awaddr(m_axil_awaddr),
    .m_axil_wvalid(m_axil_wvalid), .m_axil_wready(m_axil_wready),
    .m_axil_wdata(m_axil_wdata), .m_axil_wstrb(m_axil_wstrb),
    .m_axil_bvalid(m_axil_bvalid), .m_axil_bready(m_axil_bready),
    .m_axil_bresp(m_axil_bresp),
    .m_axil_arvalid(m_axil_arvalid), .m_axil_arready(m_axil_arready),
    .m_axil_araddr(m_axil_araddr),
    .m_axil_rvalid(m_axil_rvalid), .m_axil_rready(m_axil_rready),
    .m_axil_rdata(m_axil_rdata), .m_axil_rresp(m_axil_rresp),
    .tmo_sticky(tmo_sticky), .state_dbg(eng_state)
  );
endmodule // END axm_core (TB behavioral wiring)
