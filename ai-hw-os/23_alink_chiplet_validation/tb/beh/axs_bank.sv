// TB-ONLY BEHAVIORAL MODEL of axs_bank (spec 11_alink_axi.md AL-09, pure wiring).
// Wires the REAL frontier-owned axs_regs (s0) and axs_mem (s1) — so integration sims
// exercise the real slave RTL. NEVER synthesize this file.
module axs_bank (
  input  logic        clk,
  input  logic        rst,
  input  logic        s0_axil_awvalid,
  output logic        s0_axil_awready,
  input  logic [15:0] s0_axil_awaddr,
  input  logic        s0_axil_wvalid,
  output logic        s0_axil_wready,
  input  logic [31:0] s0_axil_wdata,
  input  logic [3:0]  s0_axil_wstrb,
  output logic        s0_axil_bvalid,
  input  logic        s0_axil_bready,
  output logic [1:0]  s0_axil_bresp,
  input  logic        s0_axil_arvalid,
  output logic        s0_axil_arready,
  input  logic [15:0] s0_axil_araddr,
  output logic        s0_axil_rvalid,
  input  logic        s0_axil_rready,
  output logic [31:0] s0_axil_rdata,
  output logic [1:0]  s0_axil_rresp,
  input  logic        s1_axil_awvalid,
  output logic        s1_axil_awready,
  input  logic [15:0] s1_axil_awaddr,
  input  logic        s1_axil_wvalid,
  output logic        s1_axil_wready,
  input  logic [31:0] s1_axil_wdata,
  input  logic [3:0]  s1_axil_wstrb,
  output logic        s1_axil_bvalid,
  input  logic        s1_axil_bready,
  output logic [1:0]  s1_axil_bresp,
  input  logic        s1_axil_arvalid,
  output logic        s1_axil_arready,
  input  logic [15:0] s1_axil_araddr,
  output logic        s1_axil_rvalid,
  input  logic        s1_axil_rready,
  output logic [31:0] s1_axil_rdata,
  output logic [1:0]  s1_axil_rresp,
  output logic [31:0] scratch0,
  output logic [15:0] wrcnt,
  output logic [15:0] mem_wr_cnt
);
  logic [31:0] scratch1_nc;   // probed at bank level: scratch0 only (spec)

  axs_regs u_regs (
    .clk(clk), .rst(rst),
    .s_axil_awvalid(s0_axil_awvalid), .s_axil_awready(s0_axil_awready),
    .s_axil_awaddr(s0_axil_awaddr),
    .s_axil_wvalid(s0_axil_wvalid), .s_axil_wready(s0_axil_wready),
    .s_axil_wdata(s0_axil_wdata), .s_axil_wstrb(s0_axil_wstrb),
    .s_axil_bvalid(s0_axil_bvalid), .s_axil_bready(s0_axil_bready),
    .s_axil_bresp(s0_axil_bresp),
    .s_axil_arvalid(s0_axil_arvalid), .s_axil_arready(s0_axil_arready),
    .s_axil_araddr(s0_axil_araddr),
    .s_axil_rvalid(s0_axil_rvalid), .s_axil_rready(s0_axil_rready),
    .s_axil_rdata(s0_axil_rdata), .s_axil_rresp(s0_axil_rresp),
    .scratch0(scratch0), .scratch1(scratch1_nc), .wrcnt(wrcnt)
  );

  axs_mem u_mem (
    .clk(clk), .rst(rst),
    .s_axil_awvalid(s1_axil_awvalid), .s_axil_awready(s1_axil_awready),
    .s_axil_awaddr(s1_axil_awaddr),
    .s_axil_wvalid(s1_axil_wvalid), .s_axil_wready(s1_axil_wready),
    .s_axil_wdata(s1_axil_wdata), .s_axil_wstrb(s1_axil_wstrb),
    .s_axil_bvalid(s1_axil_bvalid), .s_axil_bready(s1_axil_bready),
    .s_axil_bresp(s1_axil_bresp),
    .s_axil_arvalid(s1_axil_arvalid), .s_axil_arready(s1_axil_arready),
    .s_axil_araddr(s1_axil_araddr),
    .s_axil_rvalid(s1_axil_rvalid), .s_axil_rready(s1_axil_rready),
    .s_axil_rdata(s1_axil_rdata), .s_axil_rresp(s1_axil_rresp),
    .mem_wr_cnt(mem_wr_cnt)
  );
endmodule // END axs_bank (TB behavioral wiring)
