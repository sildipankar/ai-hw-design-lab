// axil_reg_slice_tb — self-checking: master BFM on the s side, reactive slave BFM
// on the m side, golden dictionary proves end-to-end transaction integrity through
// all 5 independently skid-buffered lanes under heavy random stalls.
// Single PASS/FAIL banner.
`timescale 1ns/1ps
module axil_reg_slice_tb;

  logic        clk = 0, rst;
  // s side (TB is the master)
  logic        s_axil_awvalid, s_axil_awready;
  logic [15:0] s_axil_awaddr;
  logic        s_axil_wvalid, s_axil_wready;
  logic [31:0] s_axil_wdata;
  logic [3:0]  s_axil_wstrb;
  logic        s_axil_bvalid, s_axil_bready;
  logic [1:0]  s_axil_bresp;
  logic        s_axil_arvalid, s_axil_arready;
  logic [15:0] s_axil_araddr;
  logic        s_axil_rvalid, s_axil_rready;
  logic [31:0] s_axil_rdata;
  logic [1:0]  s_axil_rresp;
  // m side (TB is the slave)
  logic        m_axil_awvalid, m_axil_awready;
  logic [15:0] m_axil_awaddr;
  logic        m_axil_wvalid, m_axil_wready;
  logic [31:0] m_axil_wdata;
  logic [3:0]  m_axil_wstrb;
  logic        m_axil_bvalid, m_axil_bready;
  logic [1:0]  m_axil_bresp;
  logic        m_axil_arvalid, m_axil_arready;
  logic [15:0] m_axil_araddr;
  logic        m_axil_rvalid, m_axil_rready;
  logic [31:0] m_axil_rdata;
  logic [1:0]  m_axil_rresp;

  int unsigned errors = 0;

  axil_reg_slice dut (.*);
  bind axil_reg_slice axil_reg_slice_sva u_sva (.*);

  always #5 clk = ~clk;

  `include "axil_master_bfm.svh"
  `include "axil_slave_bfm.svh"

  // golden mirror, independent of the slave BFM dictionary
  logic [31:0] g_mem [logic [15:0]];

  task automatic thru_write(input logic [15:0] a, input logic [31:0] d, string tag);
    logic [1:0] resp;
    @(negedge clk);
    axi_write(a, d, $urandom_range(2), $urandom_range(2), $urandom_range(2), resp);
    g_mem[a] = d;
    if (resp !== 2'b00) begin
      $error("[%s] bresp=%b expected OKAY", tag, resp); errors++;
    end
    if (bfm_mem[a] !== d) begin
      $error("[%s] slave got %h expected %h (payload corrupted in a lane)",
             tag, bfm_mem[a], d);
      errors++;
    end
  endtask

  task automatic thru_read(input logic [15:0] a, string tag);
    logic [31:0] data;
    logic [1:0]  resp;
    @(negedge clk);
    axi_read(a, $urandom_range(2), data, resp);
    if (data !== g_mem[a] || resp !== 2'b00) begin
      $error("[%s] read %h: data=%h/%h resp=%b (R lane corrupted)",
             tag, a, data, g_mem[a], resp);
      errors++;
    end
  endtask

  initial begin
    // t_reset
    rst = 1;
    s_axil_awvalid = 0; s_axil_awaddr = '0;
    s_axil_wvalid = 0;  s_axil_wdata = '0; s_axil_wstrb = '0;
    s_axil_bready = 0;
    s_axil_arvalid = 0; s_axil_araddr = '0;
    s_axil_rready = 0;
    repeat (3) @(posedge clk);
    rst = 0;
    #1;
    if (m_axil_awvalid !== 1'b0 || s_axil_bvalid !== 1'b0) begin
      $error("[t_reset] spurious valids after reset"); errors++;
    end

    // t_fast_path: no delays anywhere
    thru_write(16'h0100, 32'h1234_5678, "t_fast_path");
    thru_read (16'h0100, "t_fast_path");

    // t_ordered_burst: 10 writes then 10 readbacks (per-lane FIFO order, P1)
    for (int i = 0; i < 10; i++) thru_write(16'h0200 + 16'(4*i), $urandom, "t_burst_wr");
    for (int i = 0; i < 10; i++) thru_read (16'h0200 + 16'(4*i), "t_burst_rd");

    // t_backpressure_heavy: slave slow on every channel (P3: zero drops under stall)
    bfm_awready_dly = 4; bfm_wready_dly = 6; bfm_b_dly = 5;
    bfm_ar_dly = 4; bfm_r_dly = 6;
    for (int i = 0; i < 6; i++) thru_write(16'h0300 + 16'(4*i), $urandom, "t_bp_wr");
    for (int i = 0; i < 6; i++) thru_read (16'h0300 + 16'(4*i), "t_bp_rd");
    bfm_awready_dly = 0; bfm_wready_dly = 0; bfm_b_dly = 0;
    bfm_ar_dly = 0; bfm_r_dly = 0;

    // t_reset_during_traffic: beat parked inside a skid, reset, clean traffic after
    @(negedge clk);
    s_axil_awvalid = 1; s_axil_awaddr = 16'h0400;    // no W: AW sits in the lane
    repeat (3) @(negedge clk);
    rst = 1;
    s_axil_awvalid = 0;
    repeat (2) @(posedge clk);
    @(negedge clk) rst = 0;
    thru_write(16'h0404, 32'hAABB_CCDD, "t_reset_during_traffic");
    thru_read (16'h0404, "t_reset_during_traffic");

    // t_soak: 40 random ops with random stalls both sides
    repeat (40) begin
      automatic logic [15:0] a = 16'h0500 + 16'(4 * $urandom_range(15));
      bfm_awready_dly = $urandom_range(3); bfm_wready_dly = $urandom_range(3);
      bfm_b_dly = $urandom_range(3); bfm_ar_dly = $urandom_range(3);
      bfm_r_dly = $urandom_range(3);
      if ($urandom_range(1) || !g_mem.exists(a)) thru_write(a, $urandom, "t_soak_wr");
      else                                       thru_read(a, "t_soak_rd");
    end

    if (errors == 0) $display("*** PASS: axil_reg_slice_tb, 0 errors ***");
    else             $display("*** FAIL: axil_reg_slice_tb, %0d errors ***", errors);
    $finish;
  end

endmodule // END axil_reg_slice_tb
