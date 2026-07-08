// =============================================================================
// tb_universal -- generic self-checking testbench TEMPLATE. Simulation only.
// Run: powershell -ExecutionPolicy Bypass -File scripts\run_sim.ps1 tb_universal
// Prints "TB PASS" and $finishes on success, "TB FAIL: N errors" otherwise.
//
// HOW THIS TEMPLATE WORKS
//   - Scaffolding (clock, reset task, watchdog, scoreboard, error counter,
//     report task) is complete and generic. DO NOT EDIT it.
//   - To swap in another DUT, edit ONLY the four fenced sections:
//       USER CONFIG        : clock period, timeout, transaction count, widths
//       USER DUT SIGNALS   : declare wires matching your DUT ports
//       USER DUT INSTANCE  : instantiate your DUT (file must not be tb_*.sv)
//       USER TEST SEQUENCE : stimulus + when to sb_push / sb_check
//   - Scoreboard usage pattern (in USER TEST SEQUENCE):
//       sb_push(<expected value>)  when you SEND a transaction
//       sb_check(<observed value>) when the DUT presents an OUTPUT
//     The scoreboard is an in-order queue: first pushed = first checked.
// =============================================================================
`timescale 1ns/1ps
module tb_universal;

    // === USER CONFIG START ===
    localparam int  W          = 32;    // data width (matches DUT parameter)
    localparam time CLK_PERIOD = 10ns;  // 100 MHz
    localparam time TIMEOUT    = 1ms;   // watchdog: sim aborts + TB FAIL
    localparam int  N_TX       = 200;   // number of random transactions
    localparam int  DRAIN_CYC  = 20;    // idle cycles after last send (> DUT latency)
    // === USER CONFIG END ===

    // -------------------------------------------------------------------------
    // SCAFFOLDING -- do not edit below this line (until USER DUT SIGNALS)
    // -------------------------------------------------------------------------

    // ---- clock / reset ------------------------------------------------------
    logic clk   = 1'b0;
    logic rst_n = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic do_reset(input int cycles = 5);
        rst_n = 1'b0;
        repeat (cycles) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
    endtask

    // ---- error counter + in-order scoreboard --------------------------------
    int           errors = 0;
    int           n_checked = 0;
    logic [W-1:0] sb_q[$];              // queue of expected values

    task automatic sb_push(input logic [W-1:0] exp_val);
        sb_q.push_back(exp_val);
    endtask

    task automatic sb_check(input logic [W-1:0] got);
        logic [W-1:0] exp_val;
        if (sb_q.size() == 0) begin
            $display("ERROR: DUT output %h but scoreboard is empty", got);
            errors++;
        end else begin
            exp_val = sb_q.pop_front();
            n_checked++;
            if (got !== exp_val) begin
                $display("ERROR: tx %0d  got %h  expected %h", n_checked, got, exp_val);
                errors++;
            end
        end
    endtask

    // ---- final report: call this at the end of the test sequence ------------
    task automatic report_and_finish();
        if (sb_q.size() != 0) begin
            $display("ERROR: %0d expected outputs never appeared", sb_q.size());
            errors += sb_q.size();
        end
        $display("checked %0d transactions", n_checked);
        if (errors == 0) $display("TB PASS");
        else             $display("TB FAIL: %0d errors", errors);
        $finish;
    endtask

    // ---- watchdog ------------------------------------------------------------
    initial begin
        #(TIMEOUT);
        $display("TB FAIL: watchdog timeout");
        $finish;
    end

    // -------------------------------------------------------------------------
    // END SCAFFOLDING
    // -------------------------------------------------------------------------

    // === USER DUT SIGNALS START ===
    // Declare one wire per DUT port (clk / rst_n already exist above).
    logic         in_valid;
    logic [W-1:0] a, b;
    logic         out_valid;
    logic [W-1:0] sum;
    // === USER DUT SIGNALS END ===

    // === USER DUT INSTANCE START ===
    // Swap in your DUT here; keep instance name "dut" for easy waveform lookup.
    example_dut #(.W(W)) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (in_valid),
        .a         (a),
        .b         (b),
        .out_valid (out_valid),
        .sum       (sum)
    );
    // === USER DUT INSTANCE END ===

    // === USER TEST SEQUENCE START ===
    // Checker: whenever the DUT flags a valid output, compare it against the
    // oldest expected value. Adapt the condition/signal to your DUT.
    always @(posedge clk) begin
        if (rst_n && out_valid) sb_check(sum);
    end

    // Stimulus: N_TX random a/b with random 0..3 idle-cycle gaps between sends.
    // Pattern per transaction: drive inputs (nonblocking), push expected value,
    // hold for one clock, deassert valid. Adapt to your DUT's protocol.
    initial begin
        logic [W-1:0] ra, rb;
        in_valid = 1'b0;
        a = '0;
        b = '0;

        do_reset();

        for (int i = 0; i < N_TX; i++) begin
            ra = $urandom();
            rb = $urandom();
            a        <= ra;
            b        <= rb;
            in_valid <= 1'b1;
            sb_push(ra + rb);                       // expected: sum = a + b
            @(posedge clk);
            in_valid <= 1'b0;
            repeat ($urandom_range(0, 3)) @(posedge clk);   // random gap
        end

        repeat (DRAIN_CYC) @(posedge clk);          // let the pipeline drain
        report_and_finish();                        // prints TB PASS/FAIL, $finish
    end
    // === USER TEST SEQUENCE END ===

endmodule
