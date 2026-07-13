// alink_top_sva — bound assertions for alink_top (spec 11_alink_axi.md AL-11 + fix b).
// Bound from the TB: bind alink_top alink_top_sva u_sva (.*);
// (rst / go are DUT internals, connected by name via .*)
module alink_top_sva (
  input logic        clk, arst_n,
  input logic        run,
  input logic        test_done, test_pass,
  input logic [7:0]  err_cnt,
  input logic [7:0]  led,
  input logic        rst, go
);

  // shadows
  logic go_q, done_q, pass_q;
  always_ff @(posedge clk) begin
    go_q   <= !rst && go;
    done_q <= !rst && test_done;
    pass_q <= !rst && test_pass;
  end

  // catches: go wider than one cycle (cmd_gen would restart mid-test)
  ap_go_is_pulse: assert property (@(posedge clk) disable iff (rst)
    go_q |-> !go
  );

  // catches: verdict latch dropping (results must hold until rst)
  ap_done_sticky: assert property (@(posedge clk) disable iff (rst)
    done_q |-> test_done
  );
  ap_pass_sticky: assert property (@(posedge clk) disable iff (rst)
    pass_q |-> test_pass
  );

  // catches: pass declared with errors (verdict equation broken)
  ap_pass_implies_clean: assert property (@(posedge clk) disable iff (rst)
    test_pass |-> (test_done && err_cnt == '0)
  );

  // catches: led packing broken — bit7=test_pass, bit6=test_done, bit0=run
  ap_led_packing: assert property (@(posedge clk) disable iff (rst)
    (led[7] == test_pass) && (led[6] == test_done) && (led[0] == run)
  );

  // catches: X on the verdict pins after reset release (deliberately NO disable iff)
  ap_no_x: assert property (@(posedge clk)
    !rst |-> !$isunknown({test_done, test_pass, err_cnt, led})
  );

  // vacuity guards
  cp_test_completed: cover property (@(posedge clk) test_done);
  cp_test_passed:    cover property (@(posedge clk) test_pass);
  cp_go_fired:       cover property (@(posedge clk) go);

endmodule // END alink_top_sva
