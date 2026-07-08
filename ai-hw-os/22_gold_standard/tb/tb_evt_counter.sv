// tb_evt_counter — self-checking: independent golden model + directed + random.
// Template for all generated TBs. Ends with a single PASS/FAIL banner.

module tb_evt_counter;
  localparam int unsigned W = 4;               // small W so saturation is reachable fast
  localparam logic [W-1:0] MAX = '1;

  logic clk = 0, rst_n, en, evt_i, clear_i;
  logic [W-1:0] count_o;
  logic sat_o;

  int unsigned errors = 0;

  evt_counter #(.W(W)) dut (.*);

  always #5 clk = ~clk;

  // ---------- golden model (independent: integer math, NOT copied RTL) ----------
  int unsigned g_count = 0;
  bit          g_sat   = 0;

  task automatic golden_step(bit t_en, bit t_evt, bit t_clr);
    if (t_clr) begin g_count = 0; g_sat = 0; end
    else if (t_en && t_evt) begin
      if (g_count == MAX) g_sat = 1;
      else                g_count += 1;
    end
  endtask

  task automatic check(string tag);
    if (count_o !== g_count[W-1:0]) begin
      $error("[%s] count_o=%0d expected=%0d @%0t", tag, count_o, g_count, $time);
      errors++;
    end
    if (sat_o !== g_sat) begin
      $error("[%s] sat_o=%b expected=%b @%0t", tag, sat_o, g_sat, $time);
      errors++;
    end
  endtask

  // drive one cycle then compare DUT vs golden
  task automatic cyc(bit t_en, bit t_evt, bit t_clr, string tag);
    en = t_en; evt_i = t_evt; clear_i = t_clr;
    @(posedge clk);
    golden_step(t_en, t_evt, t_clr);
    #1 check(tag);
  endtask

  initial begin
    // t_reset: outputs known after reset
    rst_n = 0; en = 0; evt_i = 0; clear_i = 0;
    repeat (2) @(posedge clk);
    rst_n = 1; #1 check("t_reset");

    // t_count: three events counted
    repeat (3) cyc(1, 1, 0, "t_count");

    // t_gate: evt without en must not count
    cyc(0, 1, 0, "t_gate");

    // t_saturate: run past MAX, expect hold + sticky flag
    repeat (MAX + 3) cyc(1, 1, 0, "t_saturate");

    // t_clear_priority: clear and event same cycle -> clear wins
    cyc(1, 1, 1, "t_clear_priority");

    // t_random soak: 200 random cycles vs golden
    repeat (200) cyc($urandom_range(1), $urandom_range(1),
                     ($urandom_range(9) == 0), "t_random");

    if (errors == 0) $display("*** PASS: tb_evt_counter, 0 errors ***");
    else             $display("*** FAIL: tb_evt_counter, %0d errors ***", errors);
    $finish;
  end

endmodule // END tb_evt_counter
