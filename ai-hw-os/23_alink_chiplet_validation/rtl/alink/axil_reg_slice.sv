// axil_reg_slice — full AXI4-Lite register slice: all 5 channels independently
// skid-buffered. Two instances back-to-back form the MASTER-SIDE + SLAVE-SIDE
// bridge pair at the chiplet cut.
//
// MANDATORY REVIEW FIX (b) (15_bin_link_contract.md §4, ALINK row): "master/slave
// register-slice bridge pair at the cut, preserving per-channel state."
//
// SPEC GAP (15_bin_link_contract.md:27): the fix mandates this module but NO port or
// behavior spec exists in file 11 or 15. Conservative definition implemented here:
//   - one skid_buffer (C-05, 2-deep, registered ready) per channel;
//   - each AXI channel maps whole onto one lane (contract P2: one logical channel =
//     one lane — no split buses to realign);
//   - per-lane FIFO order (P1) since a skid buffer is a 2-deep in-order queue;
//   - lossless under backpressure (P3) by valid/ready construction;
//   - nothing time-based crosses (P4): pure handshakes, no ticks, no fixed latency.
// AW, W, AR run forward (master->slave); B, R run backward. Payloads:
//   AW: awaddr[16] | W: {wdata,wstrb}[36] | AR: araddr[16] | B: bresp[2] | R: {rdata,rresp}[34]
//
// AXION profile: sync active-high rst; single tool clock.
module axil_reg_slice (
  input  logic        clk,
  input  logic        rst,
  // s_axil_*: SLAVE side (faces the master device / upstream)
  input  logic        s_axil_awvalid,
  output logic        s_axil_awready,
  input  logic [15:0] s_axil_awaddr,
  input  logic        s_axil_wvalid,
  output logic        s_axil_wready,
  input  logic [31:0] s_axil_wdata,
  input  logic [3:0]  s_axil_wstrb,
  output logic        s_axil_bvalid,
  input  logic        s_axil_bready,
  output logic [1:0]  s_axil_bresp,
  input  logic        s_axil_arvalid,
  output logic        s_axil_arready,
  input  logic [15:0] s_axil_araddr,
  output logic        s_axil_rvalid,
  input  logic        s_axil_rready,
  output logic [31:0] s_axil_rdata,
  output logic [1:0]  s_axil_rresp,
  // m_axil_*: MASTER side (faces the slave device / downstream)
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
  input  logic [1:0]  m_axil_rresp
);

  // ---- AW lane (forward) ----
  skid_buffer #(.WIDTH(16)) u_aw (
    .clk(clk), .rst(rst),
    .s_valid(s_axil_awvalid), .s_ready(s_axil_awready), .s_data(s_axil_awaddr),
    .m_valid(m_axil_awvalid), .m_ready(m_axil_awready), .m_data(m_axil_awaddr)
  );

  // ---- W lane (forward): one logical channel = one lane, so wdata+wstrb travel together
  skid_buffer #(.WIDTH(36)) u_w (
    .clk(clk), .rst(rst),
    .s_valid(s_axil_wvalid), .s_ready(s_axil_wready), .s_data({s_axil_wdata, s_axil_wstrb}),
    .m_valid(m_axil_wvalid), .m_ready(m_axil_wready), .m_data({m_axil_wdata, m_axil_wstrb})
  );

  // ---- B lane (backward) ----
  skid_buffer #(.WIDTH(2)) u_b (
    .clk(clk), .rst(rst),
    .s_valid(m_axil_bvalid), .s_ready(m_axil_bready), .s_data(m_axil_bresp),
    .m_valid(s_axil_bvalid), .m_ready(s_axil_bready), .m_data(s_axil_bresp)
  );

  // ---- AR lane (forward) ----
  skid_buffer #(.WIDTH(16)) u_ar (
    .clk(clk), .rst(rst),
    .s_valid(s_axil_arvalid), .s_ready(s_axil_arready), .s_data(s_axil_araddr),
    .m_valid(m_axil_arvalid), .m_ready(m_axil_arready), .m_data(m_axil_araddr)
  );

  // ---- R lane (backward) ----
  skid_buffer #(.WIDTH(34)) u_r (
    .clk(clk), .rst(rst),
    .s_valid(m_axil_rvalid), .s_ready(m_axil_rready), .s_data({m_axil_rdata, m_axil_rresp}),
    .m_valid(s_axil_rvalid), .m_ready(s_axil_rready), .m_data({s_axil_rdata, s_axil_rresp})
  );

endmodule // END axil_reg_slice
