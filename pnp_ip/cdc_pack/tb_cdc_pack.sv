// =============================================================================
// tb_cdc_pack -- self-checking TB for the CDC primitive pack.
// Sim only. Run: powershell -File scripts\run_sim.ps1 cdc_pack
// clk_a 7ns / clk_b 13ns (unrelated). Drives on negedge (race-free),
// samples/models on posedge. DUT = cdc_example_top (all three primitives).
// Tests (run concurrently):
//   bus_handshake : 50 random words, respect src_ready, queue-compare on b_valid
//   pulse_sync    : 20 pulses spaced >= 4 dst periods, count received == 20
//   bit_sync      : each level change visible on b_level within 3 dst clocks
// Prints "TB PASS" and $finishes on success. Watchdog 1 ms.
// =============================================================================
`timescale 1ns/1ps
module tb_cdc_pack;

    localparam int N_BUS_WORDS = 50;
    localparam int N_PULSES    = 20;

    logic clk_a = 1'b0;
    logic clk_b = 1'b0;
    always #3.5 clk_a = ~clk_a;                 // 7 ns period (src / domain A)
    always #6.5 clk_b = ~clk_b;                 // 13 ns period (dst / domain B)

    logic rst_a_n = 1'b0;
    logic rst_b_n = 1'b0;

    logic        a_level = 1'b0;
    logic        b_level;
    logic        a_pulse = 1'b0;
    logic        b_pulse;
    logic        a_valid = 1'b0;
    logic        a_ready;
    logic [31:0] a_data  = '0;
    logic        b_valid;
    logic [31:0] b_data;

    int          errors      = 0;
    int          n_sent      = 0;
    int          n_recv      = 0;
    int          pulses_recv = 0;
    logic [31:0] model_q[$];                    // reference queue model
    logic [31:0] exp_word;                      // ('expect' is reserved)
    bit          bus_done    = 1'b0;
    bit          pulse_done  = 1'b0;
    bit          bit_done    = 1'b0;

    cdc_example_top dut (
        .clk_a, .rst_a_n, .clk_b, .rst_b_n,
        .a_level, .b_level,
        .a_pulse, .b_pulse,
        .a_valid, .a_ready, .a_data,
        .b_valid, .b_data
    );

    // ---- per-domain async active-low resets ---------------------------------
    initial begin
        fork
            begin repeat (4) @(negedge clk_a); rst_a_n = 1'b1; end
            begin repeat (4) @(negedge clk_b); rst_b_n = 1'b1; end
        join
    end

    // =========================================================================
    // TEST 1: cdc_bus_handshake -- 50 random words with queue-model compare
    // =========================================================================
    initial begin : p_bus_src
        wait (rst_a_n && rst_b_n);
        @(negedge clk_a);
        for (int i = 0; i < N_BUS_WORDS; i++) begin
            while (!a_ready) @(negedge clk_a);  // respect src_ready
            a_data  <= $urandom();
            a_valid <= 1'b1;
            @(negedge clk_a);
            a_valid <= 1'b0;
            repeat ($urandom_range(0, 3)) @(negedge clk_a);
        end
    end

    // model push: sample handshake on src posedge
    always @(posedge clk_a) begin
        if (rst_a_n && a_valid && a_ready) begin
            model_q.push_back(a_data);
            n_sent++;
        end
    end

    // compare on dst posedge whenever b_valid strobes
    always @(posedge clk_b) begin
        if (rst_b_n && b_valid) begin
            if (model_q.size() == 0) begin
                errors++;
                $display("ERROR: b_valid but model queue empty (t=%0t)", $time);
            end else begin
                exp_word = model_q.pop_front();
                if (b_data !== exp_word) begin
                    errors++;
                    $display("ERROR: bus word %0d got %h expected %h (t=%0t)",
                             n_recv, b_data, exp_word, $time);
                end
            end
            n_recv++;
        end
    end

    initial begin : p_bus_check
        wait (n_sent == N_BUS_WORDS);
        wait (n_recv == N_BUS_WORDS);
        repeat (4) @(posedge clk_b);            // catch any spurious extras
        if (model_q.size() != 0) begin
            errors++;
            $display("ERROR: %0d bus words never received", model_q.size());
        end
        if (n_recv != N_BUS_WORDS) begin
            errors++;
            $display("ERROR: received %0d != %0d", n_recv, N_BUS_WORDS);
        end
        bus_done = 1'b1;
    end

    // =========================================================================
    // TEST 2: cdc_pulse_sync -- 20 pulses spaced >= 4 dst periods
    // =========================================================================
    initial begin : p_pulse_src
        wait (rst_a_n && rst_b_n);
        @(negedge clk_a);
        for (int i = 0; i < N_PULSES; i++) begin
            a_pulse <= 1'b1;
            @(negedge clk_a);
            a_pulse <= 1'b0;
            repeat (9) @(negedge clk_a);        // 10 clk_a = 70 ns >= 4*13 ns
        end
        repeat (8) @(posedge clk_b);            // let the last pulse cross
        if (pulses_recv != N_PULSES) begin
            errors++;
            $display("ERROR: pulses received %0d != %0d", pulses_recv, N_PULSES);
        end
        pulse_done = 1'b1;
    end

    always @(posedge clk_b) begin
        if (rst_b_n && b_pulse) pulses_recv++;
    end

    // =========================================================================
    // TEST 3: cdc_bit_sync -- level change propagates within 3 dst clocks
    // =========================================================================
    initial begin : p_bit
        logic lvl;
        wait (rst_a_n && rst_b_n);
        repeat (4) @(posedge clk_b);            // flush X out of the sync chain
        for (int i = 0; i < 6; i++) begin
            @(negedge clk_a);
            lvl = ~a_level;
            a_level <= lvl;
            repeat (3) @(posedge clk_b);
            #1;                                 // let posedge NBAs settle
            if (b_level !== lvl) begin
                errors++;
                $display("ERROR: bit_sync level %b not seen within 3 dst clks (t=%0t)",
                         lvl, $time);
            end
            repeat (2) @(posedge clk_b);
        end
        bit_done = 1'b1;
    end

    // ---- end of test -----------------------------------------------------------
    initial begin : p_finish
        wait (bus_done && pulse_done && bit_done);
        $display("bus=%0d/%0d pulses=%0d/%0d errors=%0d",
                 n_recv, N_BUS_WORDS, pulses_recv, N_PULSES, errors);
        if (errors == 0) $display("TB PASS");
        else             $display("TB FAIL: %0d errors", errors);
        $finish;
    end

    // ---- watchdog ---------------------------------------------------------------
    initial begin
        #1ms;
        $display("TB FAIL: watchdog timeout (sent=%0d recv=%0d pulses=%0d)",
                 n_sent, n_recv, pulses_recv);
        $finish;
    end

endmodule
