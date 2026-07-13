// TB-ONLY BEHAVIORAL MODEL of axs_dec (spec 11_alink_axi.md AL-06) — SIMPLIFIED.
// NOT the spec implementation (14B/local-model work). Locking router for the
// one-outstanding system: registered wr/rd locks, valid ANDed toward the selected
// target, ready ANDed back, B/R payload muxed by the lock. Costs one extra cycle
// per direction vs the spec (lock is registered before routing starts).
// Port-compatible with AL-06 so axs_chiplet integration sims run. NEVER synthesize.
module axs_dec (
  input  logic        clk,
  input  logic        rst,
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
  output logic        m0_axil_awvalid,
  input  logic        m0_axil_awready,
  output logic [15:0] m0_axil_awaddr,
  output logic        m0_axil_wvalid,
  input  logic        m0_axil_wready,
  output logic [31:0] m0_axil_wdata,
  output logic [3:0]  m0_axil_wstrb,
  input  logic        m0_axil_bvalid,
  output logic        m0_axil_bready,
  input  logic [1:0]  m0_axil_bresp,
  output logic        m0_axil_arvalid,
  input  logic        m0_axil_arready,
  output logic [15:0] m0_axil_araddr,
  input  logic        m0_axil_rvalid,
  output logic        m0_axil_rready,
  input  logic [31:0] m0_axil_rdata,
  input  logic [1:0]  m0_axil_rresp,
  output logic        m1_axil_awvalid,
  input  logic        m1_axil_awready,
  output logic [15:0] m1_axil_awaddr,
  output logic        m1_axil_wvalid,
  input  logic        m1_axil_wready,
  output logic [31:0] m1_axil_wdata,
  output logic [3:0]  m1_axil_wstrb,
  input  logic        m1_axil_bvalid,
  output logic        m1_axil_bready,
  input  logic [1:0]  m1_axil_bresp,
  output logic        m1_axil_arvalid,
  input  logic        m1_axil_arready,
  output logic [15:0] m1_axil_araddr,
  input  logic        m1_axil_rvalid,
  output logic        m1_axil_rready,
  input  logic [31:0] m1_axil_rdata,
  input  logic [1:0]  m1_axil_rresp,
  output logic [1:0]  dbg_sel     // {rd_sel, wr_sel}
);
  logic wlock, wsel, rlock, rsel;
  assign dbg_sel = {rsel, wsel};

  // registered locks: no combinational valid<->ready loop
  always_ff @(posedge clk) begin
    if (rst) begin
      wlock <= 1'b0; wsel <= 1'b0;
      rlock <= 1'b0; rsel <= 1'b0;
    end else begin
      if (!wlock && s_axil_awvalid) begin
        wsel  <= s_axil_awaddr[15];
        wlock <= 1'b1;
      end else if (wlock && s_axil_bvalid && s_axil_bready) begin
        wlock <= 1'b0;              // write channels released after B completes
      end
      if (!rlock && s_axil_arvalid) begin
        rsel  <= s_axil_araddr[15];
        rlock <= 1'b1;
      end else if (rlock && s_axil_rvalid && s_axil_rready) begin
        rlock <= 1'b0;              // read channels released after R completes
      end
    end
  end

  // write channels: route by wsel while locked
  assign m0_axil_awvalid = wlock && !wsel && s_axil_awvalid;
  assign m1_axil_awvalid = wlock &&  wsel && s_axil_awvalid;
  assign m0_axil_wvalid  = wlock && !wsel && s_axil_wvalid;
  assign m1_axil_wvalid  = wlock &&  wsel && s_axil_wvalid;
  assign s_axil_awready  = wlock && (wsel ? m1_axil_awready : m0_axil_awready);
  assign s_axil_wready   = wlock && (wsel ? m1_axil_wready  : m0_axil_wready);
  assign s_axil_bvalid   = wlock && (wsel ? m1_axil_bvalid  : m0_axil_bvalid);
  assign s_axil_bresp    = wsel ? m1_axil_bresp : m0_axil_bresp;
  assign m0_axil_bready  = wlock && !wsel && s_axil_bready;
  assign m1_axil_bready  = wlock &&  wsel && s_axil_bready;
  assign m0_axil_awaddr  = s_axil_awaddr;
  assign m1_axil_awaddr  = s_axil_awaddr;
  assign m0_axil_wdata   = s_axil_wdata;
  assign m1_axil_wdata   = s_axil_wdata;
  assign m0_axil_wstrb   = s_axil_wstrb;
  assign m1_axil_wstrb   = s_axil_wstrb;

  // read channels: route by rsel while locked
  assign m0_axil_arvalid = rlock && !rsel && s_axil_arvalid;
  assign m1_axil_arvalid = rlock &&  rsel && s_axil_arvalid;
  assign s_axil_arready  = rlock && (rsel ? m1_axil_arready : m0_axil_arready);
  assign s_axil_rvalid   = rlock && (rsel ? m1_axil_rvalid  : m0_axil_rvalid);
  assign s_axil_rdata    = rsel ? m1_axil_rdata : m0_axil_rdata;
  assign s_axil_rresp    = rsel ? m1_axil_rresp : m0_axil_rresp;
  assign m0_axil_rready  = rlock && !rsel && s_axil_rready;
  assign m1_axil_rready  = rlock &&  rsel && s_axil_rready;
  assign m0_axil_araddr  = s_axil_araddr;
  assign m1_axil_araddr  = s_axil_araddr;

endmodule // END axs_dec (TB behavioral, SIMPLIFIED)
