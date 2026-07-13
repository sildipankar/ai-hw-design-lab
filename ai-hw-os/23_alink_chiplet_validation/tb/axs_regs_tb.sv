// axs_regs_tb — self-checking: master BFM + golden register mirror.
// The headline test is t_w_first: W arrives BEFORE AW (review fix a — the spec's
// original wait-for-both slave deadlocks or stalls here). Plus RO/unmapped decode,
// backpressure on B and R, reset-during-traffic, random soak.
// Single PASS/FAIL banner.
`timescale 1ns/1ps
module axs_regs_tb;

  logic        clk = 0, rst;
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
  logic [31:0] scratch0, scratch1;
  logic [15:0] wrcnt;

  int unsigned errors = 0;

  axs_regs dut (.*);
  bind axs_regs axs_regs_sva u_sva (.*);

  always #5 clk = ~clk;

  `include "axil_master_bfm.svh"

  // ---------- golden model: independent register mirror ----------
  logic [31:0] g_s0 = '0, g_s1 = '0;
  int unsigned g_wrcnt = 0;

  task automatic gwrite(input logic [15:0] a, input logic [31:0] d,
                        input int awl, input int wl, input int bdly, input string tag);
    logic [1:0] resp;
    bit ok = (a[7:0] == 8'h04) || (a[7:0] == 8'h08);
    @(negedge clk);
    axi_write(a, d, awl, wl, bdly, resp);
    if (ok) begin
      if (a[7:0] == 8'h04) g_s0 = d; else g_s1 = d;
      g_wrcnt++;
    end
    if (resp !== (ok ? 2'b00 : 2'b10)) begin
      $error("[%s] bresp=%b expected=%b for addr %h", tag, resp, ok ? 2'b00 : 2'b10, a);
      errors++;
    end
    #1;
    if (scratch0 !== g_s0 || scratch1 !== g_s1 || wrcnt !== 16'(g_wrcnt)) begin
      $error("[%s] probe mismatch: s0=%h/%h s1=%h/%h wrcnt=%0d/%0d",
             tag, scratch0, g_s0, scratch1, g_s1, wrcnt, g_wrcnt);
      errors++;
    end
  endtask

  task automatic gread(input logic [15:0] a, input int rdly, input string tag);
    logic [31:0] data, exp;
    logic [1:0]  resp, eresp;
    case (a[7:0])
      8'h00:   begin exp = 32'hA11C_0001;        eresp = 2'b00; end
      8'h04:   begin exp = g_s0;                 eresp = 2'b00; end
      8'h08:   begin exp = g_s1;                 eresp = 2'b00; end
      8'h0C:   begin exp = {16'h0, 16'(g_wrcnt)}; eresp = 2'b00; end
      default: begin exp = 32'hDEAD_BEEF;        eresp = 2'b10; end
    endcase
    @(negedge clk);
    axi_read(a, rdly, data, resp);
    if (data !== exp || resp !== eresp) begin
      $error("[%s] read %h: data=%h/%h resp=%b/%b", tag, a, data, exp, resp, eresp);
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
    if (s_axil_awready !== 1'b1 || s_axil_wready !== 1'b1 || s_axil_arready !== 1'b1) begin
      $error("[t_reset] readys not up after reset"); errors++;
    end

    // t_aw_first: AW leads W by 3
    gwrite(16'h0004, 32'h1122_3344, 0, 3, 0, "t_aw_first");

    // t_w_first: W leads AW by 3 — THE review-fix (a) test
    gwrite(16'h0008, 32'hCAFE_BABE, 3, 0, 0, "t_w_first");

    // t_same_cycle
    gwrite(16'h0004, 32'hA5A5_5A5A, 0, 0, 0, "t_same_cycle");

    // t_readbacks
    gread(16'h0004, 0, "t_readback_s0");
    gread(16'h0008, 0, "t_readback_s1");
    gread(16'h0000, 0, "t_read_id");
    gread(16'h000C, 0, "t_read_wrcnt");

    // t_unmapped_write: SLVERR, wrcnt unchanged
    gwrite(16'h0030, 32'h0BAD_0BAD, 0, 0, 0, "t_unmapped_write");
    gread(16'h000C, 0, "t_wrcnt_after_slverr");

    // t_write_ro: write to ID (RO) -> SLVERR (conservative decode, see BUILD_REPORT)
    gwrite(16'h0000, 32'h1234_5678, 0, 0, 0, "t_write_ro");

    // t_unmapped_read: DEADBEEF + SLVERR
    gread(16'h0040, 0, "t_unmapped_read");

    // t_b_backpressure: master late on bready (bvalid must hold, payload stable)
    gwrite(16'h0004, 32'h0F0F_F0F0, 0, 0, 5, "t_b_backpressure");

    // t_r_backpressure: master late on rready
    gread(16'h0004, 4, "t_r_backpressure");

    // t_reset_during_traffic: AW captured, then reset mid-write; clean op after
    @(negedge clk);
    s_axil_awvalid = 1; s_axil_awaddr = 16'h0004;
    repeat (2) @(negedge clk);
    rst = 1;
    s_axil_awvalid = 0;
    repeat (2) @(posedge clk);
    @(negedge clk) rst = 0;
    g_s0 = '0; g_s1 = '0; g_wrcnt = 0;      // registers cleared by rst
    gwrite(16'h0004, 32'h7777_1111, 0, 2, 0, "t_reset_during_traffic");
    gread(16'h0004, 0, "t_reset_during_traffic_rd");

    // t_soak: 30 random ops, random AW/W ordering and delays
    repeat (30) begin
      automatic bit wr = $urandom_range(1);
      automatic logic [15:0] a;
      case ($urandom_range(4))
        0: a = 16'h0000;
        1: a = 16'h0004;
        2: a = 16'h0008;
        3: a = 16'h000C;
        4: a = 16'h0030;                     // unmapped
      endcase
      if (wr) gwrite(a, $urandom, $urandom_range(3), $urandom_range(3),
                     $urandom_range(2), "t_soak_wr");
      else    gread(a, $urandom_range(2), "t_soak_rd");
    end

    if (errors == 0) $display("*** PASS: axs_regs_tb, 0 errors ***");
    else             $display("*** FAIL: axs_regs_tb, %0d errors ***", errors);
    $finish;
  end

endmodule // END axs_regs_tb
