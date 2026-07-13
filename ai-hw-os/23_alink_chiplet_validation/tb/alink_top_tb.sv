// alink_top_tb — full-stack integration: REAL alink_top / chiplets / slices /
// engine / slaves with TB-only behavioral stand-ins for the local-model blocks
// (reset_sync, cmd_gen, axil_pmon, axs_dec, axm_core, axs_bank, sram_bank).
// Tests: clean pass (chk_sig vs independent golden), reset-during-traffic rerun,
// NEGATIVE run (arready forced low at the cut -> timeout path -> test_pass=0).
// Single PASS/FAIL banner.
`timescale 1ns/1ps
module alink_top_tb;

  logic        clk = 0, arst_n, run;
  logic [31:0] seed;
  logic        test_done, test_pass;
  logic [7:0]  err_cnt;
  logic [31:0] chk_sig;
  logic [7:0]  led;

  int unsigned errors = 0;

  alink_top dut (.*);
  bind alink_top alink_top_sva u_sva (.*);

  always #5 clk = ~clk;

  // golden signature: same expectation math as axm_chiplet_tb (behavioral cmd_gen
  // pattern), computed only from the seed and the architected register values
  function automatic logic [31:0] golden_sig(input logic [31:0] s);
    logic [31:0] sig = '0;
    for (int i = 0; i < 8; i++)
      sig = {sig[30:0], sig[31]} ^ (s ^ (32'h9E37_79B9 * i) ^ 32'h0BAD_F00D);
    sig = {sig[30:0], sig[31]} ^ 32'h5A5A_A5A5;
    sig = {sig[30:0], sig[31]} ^ 32'hA11C_0001;
    return sig;
  endfunction

  task automatic hard_reset();
    @(negedge clk);
    arst_n = 0; run = 0;
    repeat (5) @(posedge clk);
    @(negedge clk);
    arst_n = 1;
    repeat (8) @(posedge clk);       // reset_sync releases after 4 edges
  endtask

  task automatic wait_done(input int max_clks, input string tag);
    int guard = 0;
    while (test_done !== 1'b1 && guard < max_clks) begin
      @(posedge clk);
      guard++;
    end
    if (test_done !== 1'b1) begin
      $error("[%s] test_done never rose within %0d clks", tag, max_clks); errors++;
    end
    repeat (2) @(posedge clk);
    #1;
  endtask

  initial begin
    arst_n = 0; run = 0; seed = '0;
    hard_reset();

    // t_clean_pass: seed 1, full self-test through the register-slice pair
    seed = 32'h0000_0001;
    @(negedge clk) run = 1;
    wait_done(20000, "t_clean_pass");
    if (test_pass !== 1'b1) begin
      $error("[t_clean_pass] test_pass=%b expected 1 (err_cnt=%0d led=%b)",
             test_pass, err_cnt, led); errors++;
    end
    if (err_cnt !== 8'd0) begin
      $error("[t_clean_pass] err_cnt=%0d expected 0", err_cnt); errors++;
    end
    if (chk_sig !== golden_sig(32'h0000_0001)) begin
      $error("[t_clean_pass] chk_sig=%h expected=%h",
             chk_sig, golden_sig(32'h0000_0001)); errors++;
    end
    if (led[7] !== 1'b1 || led[6] !== 1'b1 || led[0] !== 1'b1) begin
      $error("[t_clean_pass] led=%b: expected pass/done/run bits set", led); errors++;
    end
    @(negedge clk) run = 0;

    // t_reset_during_traffic: start a run, yank arst_n mid-test, full rerun passes
    hard_reset();
    seed = 32'h0000_0002;
    @(negedge clk) run = 1;
    repeat (40) @(posedge clk);        // mid phase-1 traffic
    @(negedge clk) run = 0;
    hard_reset();
    seed = 32'h0000_0002;
    @(negedge clk) run = 1;
    wait_done(20000, "t_reset_during_traffic");
    if (test_pass !== 1'b1 || chk_sig !== golden_sig(32'h0000_0002)) begin
      $error("[t_reset_during_traffic] rerun after reset not clean: pass=%b sig=%h/%h",
             test_pass, chk_sig, golden_sig(32'h0000_0002)); errors++;
    end
    @(negedge clk) run = 0;

    // t_negative_stall: force the slave-side AR ready at the cut low — the read path
    // hangs, the engine timeout fires, pmon logs vdrop/stall -> test_pass MUST be 0.
    // (Sim equivalent of the pass-criteria row's runtime-force negative test.)
    hard_reset();
    force dut.b_arready = 1'b0;
    seed = 32'h0000_0003;
    @(negedge clk) run = 1;
    wait_done(80000, "t_negative_stall");   // 10 reads x 4096-clk timeouts + margin
    if (test_pass !== 1'b0) begin
      $error("[t_negative_stall] test_pass=%b expected 0 under forced stall",
             test_pass); errors++;
    end
    if (err_cnt == 8'd0) begin
      $error("[t_negative_stall] err_cnt=0, timeouts not counted"); errors++;
    end
    if (led[2] !== 1'b1) begin               // led[2] = tmo
      $error("[t_negative_stall] tmo led not set: led=%b", led); errors++;
    end
    release dut.b_arready;
    @(negedge clk) run = 0;

    // t_recover_after_negative: clean pass again after releasing the fault
    hard_reset();
    seed = 32'h0000_0004;
    @(negedge clk) run = 1;
    wait_done(20000, "t_recover_after_negative");
    if (test_pass !== 1'b1) begin
      $error("[t_recover_after_negative] test_pass=%b expected 1", test_pass); errors++;
    end

    if (errors == 0) $display("*** PASS: alink_top_tb, 0 errors ***");
    else             $display("*** FAIL: alink_top_tb, %0d errors ***", errors);
    $finish;
  end

endmodule // END alink_top_tb
