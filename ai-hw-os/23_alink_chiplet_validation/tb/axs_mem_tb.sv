// axs_mem_tb — self-checking: master BFM + golden memory array.
// Headline tests: t_w_first (review fix a), t_latency (R exactly 3 clks after AR
// accept), backpressure, reset-during-traffic, random soak. Never reads an address
// it has not written (the file-11 X-state rule, honored in sim too).
// Uses TB-only behavioral sram_bank. Single PASS/FAIL banner.
`timescale 1ns/1ps
module axs_mem_tb;

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
  logic [15:0] mem_wr_cnt;

  int unsigned errors = 0;

  axs_mem dut (.*);
  bind axs_mem axs_mem_sva u_sva (.*);

  always #5 clk = ~clk;

  `include "axil_master_bfm.svh"

  // ---------- golden model: word array + write counter ----------
  logic [31:0] g_mem [logic [15:0]];
  int unsigned g_wr = 0;

  task automatic gwrite(input logic [15:0] a, input logic [31:0] d,
                        input int awl, input int wl, input int bdly, input string tag);
    logic [1:0] resp;
    @(negedge clk);
    axi_write(a, d, awl, wl, bdly, resp);
    g_mem[{4'h0, a[11:2], 2'b00}] = d;       // word-aliased golden storage
    g_wr++;
    if (resp !== 2'b00) begin
      $error("[%s] bresp=%b expected OKAY", tag, resp); errors++;
    end
    #1;
    if (mem_wr_cnt !== 16'(g_wr)) begin
      $error("[%s] mem_wr_cnt=%0d expected=%0d", tag, mem_wr_cnt, g_wr); errors++;
    end
  endtask

  task automatic gread(input logic [15:0] a, input int rdly, input string tag);
    logic [31:0] data;
    logic [1:0]  resp;
    logic [31:0] exp = g_mem[{4'h0, a[11:2], 2'b00}];
    @(negedge clk);
    axi_read(a, rdly, data, resp);
    if (data !== exp || resp !== 2'b00) begin
      $error("[%s] read %h: data=%h/%h resp=%b", tag, a, data, exp, resp); errors++;
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

    // t_w_first: W leads AW by 3 — review-fix (a) through the memory slave
    gwrite(16'h8010, 32'h0000_CAFE, 3, 0, 0, "t_w_first");

    // t_aw_first / t_same_cycle
    gwrite(16'h8014, 32'h1111_2222, 0, 3, 0, "t_aw_first");
    gwrite(16'h8018, 32'h3333_4444, 0, 0, 0, "t_same_cycle");

    // t_readback
    gread(16'h8010, 0, "t_readback0");
    gread(16'h8014, 0, "t_readback1");

    // t_latency: R must come EXACTLY 3 clks after the AR accept cycle
    begin
      automatic int lat = 0;
      @(negedge clk);
      s_axil_arvalid = 1; s_axil_araddr = 16'h8018; s_axil_rready = 1;
      forever begin
        #1;
        if (s_axil_arready === 1'b1) break;
        @(negedge clk);
      end
      @(posedge clk);                        // AR accept edge
      @(negedge clk) s_axil_arvalid = 0;
      // count with pre-NBA sampling: rvalid "arrives at clk N" == sampled high at
      // edge N, exactly how a waveform (and the Protium capture) counts it
      forever begin
        @(posedge clk);
        lat++;
        if (s_axil_rvalid === 1'b1) break;
        if (lat > 10) break;
      end
      if (lat != 3) begin
        $error("[t_latency] rvalid after %0d clks, expected 3", lat); errors++;
      end
      if (s_axil_rdata !== 32'h3333_4444) begin
        $error("[t_latency] rdata=%h expected 33334444", s_axil_rdata); errors++;
      end
      @(negedge clk) s_axil_rready = 0;
    end

    // t_b_backpressure / t_r_backpressure
    gwrite(16'h801C, 32'h5555_6666, 0, 0, 5, "t_b_backpressure");
    gread(16'h801C, 4, "t_r_backpressure");

    // t_reset_during_traffic: W captured, reset mid-write, clean op after
    @(negedge clk);
    s_axil_wvalid = 1; s_axil_wdata = 32'hDEAD_0001; s_axil_wstrb = 4'hF;
    repeat (2) @(negedge clk);
    rst = 1;
    s_axil_wvalid = 0;
    repeat (2) @(posedge clk);
    @(negedge clk) rst = 0;
    g_wr = 0;                                // mem_wr_cnt cleared by rst (array persists)
    gwrite(16'h8020, 32'h7777_8888, 2, 0, 0, "t_reset_during_traffic");
    gread(16'h8020, 0, "t_reset_during_traffic_rd");

    // t_soak: 30 random word ops across 16 addresses (write-before-read enforced)
    begin
      logic [15:0] pool [16];
      for (int i = 0; i < 16; i++) pool[i] = 16'h8800 + 16'(4 * i);
      foreach (pool[i]) gwrite(pool[i], $urandom, $urandom_range(2),
                               $urandom_range(2), $urandom_range(2), "t_soak_init");
      repeat (30) begin
        automatic int k = $urandom_range(15);
        if ($urandom_range(1)) gwrite(pool[k], $urandom, $urandom_range(2),
                                      $urandom_range(2), $urandom_range(2), "t_soak_wr");
        else                   gread(pool[k], $urandom_range(2), "t_soak_rd");
      end
    end

    if (errors == 0) $display("*** PASS: axs_mem_tb, 0 errors ***");
    else             $display("*** FAIL: axs_mem_tb, %0d errors ***", errors);
    $finish;
  end

endmodule // END axs_mem_tb
