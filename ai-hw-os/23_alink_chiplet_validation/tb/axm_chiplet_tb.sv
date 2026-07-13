// axm_chiplet_tb — integration smoke: REAL axm_engine + axm_chiplet RTL with
// TB-only behavioral cmd_gen/axm_core/axil_pmon (blackbox stand-ins) and the TB as
// the AXS-side slave (reactive BFM). Golden chk_sig computed independently from the
// behavioral cmd_gen's documented pattern. Clean run, poisoned run (one corrupted
// read -> err_cnt==1), reset-during-traffic rerun. Single PASS/FAIL banner.
`timescale 1ns/1ps
module axm_chiplet_tb;

  logic        clk = 0, rst, go;
  logic [31:0] seed;
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
  logic        done;
  logic [7:0]  err_cnt;
  logic [31:0] chk_sig;
  logic [2:0]  pmon_err;
  logic [15:0] pmon_cnt_r;
  logic [7:0]  dbg_bus;

  int unsigned errors = 0;

  axm_chiplet dut (.*);
  bind axm_chiplet axm_chiplet_sva u_sva (.*);

  always #5 clk = ~clk;

  `include "axil_slave_bfm.svh"

  // golden signature: replicates the behavioral cmd_gen's documented sequence
  // (8 patterned reads, scratch0 readback, ID) — computed from expectations only
  function automatic logic [31:0] golden_sig(input logic [31:0] s);
    logic [31:0] sig = '0;
    for (int i = 0; i < 8; i++)
      sig = {sig[30:0], sig[31]} ^ (s ^ (32'h9E37_79B9 * i) ^ 32'h0BAD_F00D);
    sig = {sig[30:0], sig[31]} ^ 32'h5A5A_A5A5;
    sig = {sig[30:0], sig[31]} ^ 32'hA11C_0001;
    return sig;
  endfunction

  task automatic run_test(input logic [31:0] s, input string tag,
                          input logic [7:0] exp_err);
    int guard = 0;
    @(negedge clk);
    seed = s;
    go = 1;
    @(negedge clk);
    go = 0;
    while (done !== 1'b1 && guard < 20000) begin
      @(posedge clk);
      guard++;
    end
    if (done !== 1'b1) begin
      $error("[%s] test never finished (hang)", tag); errors++;
      return;
    end
    repeat (2) @(posedge clk);      // let boundary registers settle
    #1;
    if (err_cnt !== exp_err) begin
      $error("[%s] err_cnt=%0d expected=%0d", tag, err_cnt, exp_err); errors++;
    end
    if (exp_err == 0 && chk_sig !== golden_sig(s)) begin
      $error("[%s] chk_sig=%h expected=%h", tag, chk_sig, golden_sig(s)); errors++;
    end
    if (exp_err == 0 && pmon_err !== 3'b000) begin
      $error("[%s] pmon_err=%b on a clean run", tag, pmon_err); errors++;
    end
    if (pmon_cnt_r !== 16'd10) begin  // 8 mem reads + scratch + ID
      $error("[%s] pmon_cnt_r=%0d expected=10", tag, pmon_cnt_r); errors++;
    end
    if (dbg_bus[6] !== 1'b1) begin
      $error("[%s] dbg_bus[6] (done) not set", tag); errors++;
    end
  endtask

  task automatic do_reset();
    @(negedge clk);
    rst = 1;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 0;
    bfm_mem.delete();
    bfm_mem[16'h0000] = 32'hA11C_0001;   // ID register emulation for P3
    bfm_reads = 0; bfm_writes = 0;
  endtask

  initial begin
    rst = 1; go = 0; seed = '0;
    do_reset();

    // t_clean_run: full self-test, no errors expected
    run_test(32'h0000_0001, "t_clean_run", 8'd0);

    // t_poisoned_run: corrupt exactly one read -> err_cnt must be exactly 1
    do_reset();
    bfm_corrupt_mask = 32'h0000_0001;    // XORed into the FIRST read, then clears
    run_test(32'h0000_0002, "t_poisoned_run", 8'd1);

    // t_reset_during_traffic: kill a run mid-flight, then a clean rerun
    do_reset();
    @(negedge clk);
    seed = 32'h0000_0003; go = 1;
    @(negedge clk) go = 0;
    repeat (30) @(posedge clk);          // somewhere inside phase 1
    do_reset();
    run_test(32'h0000_0003, "t_reset_during_traffic", 8'd0);

    if (errors == 0) $display("*** PASS: axm_chiplet_tb, 0 errors ***");
    else             $display("*** FAIL: axm_chiplet_tb, %0d errors ***", errors);
    $finish;
  end

endmodule // END axm_chiplet_tb
