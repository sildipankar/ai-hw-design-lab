// axs_chiplet — CHIPLET 2 TOP: axs_dec routes, axs_bank contains the two slaves.
// Spec: 11_alink_axi.md AL-10 (27B-routed -> frontier-owned integration).
// Wiring: s_axil -> axs_dec; dec m0 -> bank s0 (regs), dec m1 -> bank s1 (mem).
// Debug outputs are boundary-registered (global rule 5); the AXI bus passes through
// combinationally to the pins, mirroring AL-05 — flagged in BUILD_REPORT (AL-10 is
// silent on registering).
// AXION profile: sync active-high rst; single tool clock.
module axs_chiplet (
  input  logic        clk,
  input  logic        rst,
  // chiplet AXI4-Lite SLAVE port (17 signals, from axm_chiplet)
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
  // registered debug
  output logic [1:0]  dbg_sel,
  output logic [31:0] dbg_scratch0,
  output logic [15:0] dbg_wrcnt,
  output logic [15:0] dbg_mem_wr_cnt
);

  // dec -> bank wires, one full AXI-Lite bundle per target
  logic        d0_awvalid, d0_awready, d0_wvalid, d0_wready, d0_bvalid, d0_bready;
  logic        d0_arvalid, d0_arready, d0_rvalid, d0_rready;
  logic [15:0] d0_awaddr, d0_araddr;
  logic [31:0] d0_wdata, d0_rdata;
  logic [3:0]  d0_wstrb;
  logic [1:0]  d0_bresp, d0_rresp;

  logic        d1_awvalid, d1_awready, d1_wvalid, d1_wready, d1_bvalid, d1_bready;
  logic        d1_arvalid, d1_arready, d1_rvalid, d1_rready;
  logic [15:0] d1_awaddr, d1_araddr;
  logic [31:0] d1_wdata, d1_rdata;
  logic [3:0]  d1_wstrb;
  logic [1:0]  d1_bresp, d1_rresp;

  logic [1:0]  c_dbg_sel;
  logic [31:0] c_scratch0;
  logic [15:0] c_wrcnt, c_mem_wr_cnt;

  axs_dec u_dec (
    .clk             (clk),
    .rst             (rst),
    .s_axil_awvalid  (s_axil_awvalid),
    .s_axil_awready  (s_axil_awready),
    .s_axil_awaddr   (s_axil_awaddr),
    .s_axil_wvalid   (s_axil_wvalid),
    .s_axil_wready   (s_axil_wready),
    .s_axil_wdata    (s_axil_wdata),
    .s_axil_wstrb    (s_axil_wstrb),
    .s_axil_bvalid   (s_axil_bvalid),
    .s_axil_bready   (s_axil_bready),
    .s_axil_bresp    (s_axil_bresp),
    .s_axil_arvalid  (s_axil_arvalid),
    .s_axil_arready  (s_axil_arready),
    .s_axil_araddr   (s_axil_araddr),
    .s_axil_rvalid   (s_axil_rvalid),
    .s_axil_rready   (s_axil_rready),
    .s_axil_rdata    (s_axil_rdata),
    .s_axil_rresp    (s_axil_rresp),
    .m0_axil_awvalid (d0_awvalid),
    .m0_axil_awready (d0_awready),
    .m0_axil_awaddr  (d0_awaddr),
    .m0_axil_wvalid  (d0_wvalid),
    .m0_axil_wready  (d0_wready),
    .m0_axil_wdata   (d0_wdata),
    .m0_axil_wstrb   (d0_wstrb),
    .m0_axil_bvalid  (d0_bvalid),
    .m0_axil_bready  (d0_bready),
    .m0_axil_bresp   (d0_bresp),
    .m0_axil_arvalid (d0_arvalid),
    .m0_axil_arready (d0_arready),
    .m0_axil_araddr  (d0_araddr),
    .m0_axil_rvalid  (d0_rvalid),
    .m0_axil_rready  (d0_rready),
    .m0_axil_rdata   (d0_rdata),
    .m0_axil_rresp   (d0_rresp),
    .m1_axil_awvalid (d1_awvalid),
    .m1_axil_awready (d1_awready),
    .m1_axil_awaddr  (d1_awaddr),
    .m1_axil_wvalid  (d1_wvalid),
    .m1_axil_wready  (d1_wready),
    .m1_axil_wdata   (d1_wdata),
    .m1_axil_wstrb   (d1_wstrb),
    .m1_axil_bvalid  (d1_bvalid),
    .m1_axil_bready  (d1_bready),
    .m1_axil_bresp   (d1_bresp),
    .m1_axil_arvalid (d1_arvalid),
    .m1_axil_arready (d1_arready),
    .m1_axil_araddr  (d1_araddr),
    .m1_axil_rvalid  (d1_rvalid),
    .m1_axil_rready  (d1_rready),
    .m1_axil_rdata   (d1_rdata),
    .m1_axil_rresp   (d1_rresp),
    .dbg_sel         (c_dbg_sel)
  );

  axs_bank u_bank (
    .clk             (clk),
    .rst             (rst),
    .s0_axil_awvalid (d0_awvalid),
    .s0_axil_awready (d0_awready),
    .s0_axil_awaddr  (d0_awaddr),
    .s0_axil_wvalid  (d0_wvalid),
    .s0_axil_wready  (d0_wready),
    .s0_axil_wdata   (d0_wdata),
    .s0_axil_wstrb   (d0_wstrb),
    .s0_axil_bvalid  (d0_bvalid),
    .s0_axil_bready  (d0_bready),
    .s0_axil_bresp   (d0_bresp),
    .s0_axil_arvalid (d0_arvalid),
    .s0_axil_arready (d0_arready),
    .s0_axil_araddr  (d0_araddr),
    .s0_axil_rvalid  (d0_rvalid),
    .s0_axil_rready  (d0_rready),
    .s0_axil_rdata   (d0_rdata),
    .s0_axil_rresp   (d0_rresp),
    .s1_axil_awvalid (d1_awvalid),
    .s1_axil_awready (d1_awready),
    .s1_axil_awaddr  (d1_awaddr),
    .s1_axil_wvalid  (d1_wvalid),
    .s1_axil_wready  (d1_wready),
    .s1_axil_wdata   (d1_wdata),
    .s1_axil_wstrb   (d1_wstrb),
    .s1_axil_bvalid  (d1_bvalid),
    .s1_axil_bready  (d1_bready),
    .s1_axil_bresp   (d1_bresp),
    .s1_axil_arvalid (d1_arvalid),
    .s1_axil_arready (d1_arready),
    .s1_axil_araddr  (d1_araddr),
    .s1_axil_rvalid  (d1_rvalid),
    .s1_axil_rready  (d1_rready),
    .s1_axil_rdata   (d1_rdata),
    .s1_axil_rresp   (d1_rresp),
    .scratch0        (c_scratch0),
    .wrcnt           (c_wrcnt),
    .mem_wr_cnt      (c_mem_wr_cnt)
  );

  // boundary-registered debug outputs
  always_ff @(posedge clk) begin
    if (rst) begin
      dbg_sel        <= '0;
      dbg_scratch0   <= '0;
      dbg_wrcnt      <= '0;
      dbg_mem_wr_cnt <= '0;
    end else begin
      dbg_sel        <= c_dbg_sel;
      dbg_scratch0   <= c_scratch0;
      dbg_wrcnt      <= c_wrcnt;
      dbg_mem_wr_cnt <= c_mem_wr_cnt;
    end
  end

endmodule // END axs_chiplet
