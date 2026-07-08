// =============================================================================
// tb_async_fifo -- self-checking TB for the Cummings-style async FIFO.
// Sim only. Run: powershell -File scripts\run_sim.ps1 async_fifo
// wr_clk 7ns / rd_clk 11ns (unrelated). Drives on negedge (race-free),
// samples/models on posedge. Prints "TB PASS" and $finishes on success.
// Plan: burst-fill to hit full with reader paused, then 500 random-rate
// pushes vs random-rate pops, queue-model compare on every pop, final
// empty/leftover checks. Watchdog 1 ms.
// =============================================================================
`timescale 1ns/1ps
module tb_async_fifo;

    localparam int WIDTH      = 32;
    localparam int DEPTH_LOG2 = 4;
    localparam int N_WORDS    = 500;

    logic wr_clk = 1'b0;
    logic rd_clk = 1'b0;
    always #3.5 wr_clk = ~wr_clk;               // 7 ns period
    always #5.5 rd_clk = ~rd_clk;               // 11 ns period

    logic wr_rst_n = 1'b0;
    logic rd_rst_n = 1'b0;

    logic             wr_en   = 1'b0;
    logic [WIDTH-1:0] wr_data = '0;
    logic             full;
    logic             rd_en   = 1'b0;
    logic [WIDTH-1:0] rd_data;
    logic             empty;

    int               errors   = 0;
    int               n_pushed = 0;
    int               n_popped = 0;
    logic [WIDTH-1:0] model_q[$];               // reference queue model
    logic [WIDTH-1:0] exp_word;                 // ('expect' is reserved)
    bit               push_done    = 1'b0;
    bit               reader_pause = 1'b1;      // burst-fill phase first
    bit               saw_full     = 1'b0;

    async_fifo #(.WIDTH(WIDTH), .DEPTH_LOG2(DEPTH_LOG2)) dut (
        .wr_clk, .wr_rst_n, .wr_en, .wr_data, .full,
        .rd_clk, .rd_rst_n, .rd_en, .rd_data, .empty
    );

    // ---- per-domain async active-low resets ---------------------------------
    initial begin
        fork
            begin repeat (4) @(negedge wr_clk); wr_rst_n = 1'b1; end
            begin repeat (4) @(negedge rd_clk); rd_rst_n = 1'b1; end
        join
    end

    // ---- reference model: sample DUT pins on posedge ------------------------
    always @(posedge wr_clk) begin
        if (wr_rst_n && wr_en && !full) begin
            model_q.push_back(wr_data);
            n_pushed++;
        end
        if (wr_rst_n && full) saw_full = 1'b1;
    end

    always @(posedge rd_clk) begin
        if (rd_rst_n && rd_en && !empty) begin
            if (model_q.size() == 0) begin
                errors++;
                $display("ERROR: pop but model queue empty (t=%0t)", $time);
            end else begin
                exp_word = model_q.pop_front();
                if (rd_data !== exp_word) begin
                    errors++;
                    $display("ERROR: pop %0d got %h expected %h (t=%0t)",
                             n_popped, rd_data, exp_word, $time);
                end
            end
            n_popped++;
        end
    end

    // ---- writer: negedge driving --------------------------------------------
    initial begin : p_writer
        wait (wr_rst_n && rd_rst_n);
        @(negedge wr_clk);
        // phase 1: burst fill with reader paused, until full asserts
        while (!full) begin
            wr_en   <= 1'b1;
            wr_data <= $urandom();
            @(negedge wr_clk);
        end
        wr_en <= 1'b0;
        $display("burst fill: full=1 after %0d pushes", n_pushed);
        reader_pause = 1'b0;
        // phase 2: random-rate pushes until N_WORDS total, respecting full
        while (n_pushed < N_WORDS) begin
            if (!full && ($urandom_range(0, 99) < 70)) begin
                wr_en   <= 1'b1;
                wr_data <= $urandom();
            end else begin
                wr_en <= 1'b0;
            end
            @(negedge wr_clk);
        end
        wr_en <= 1'b0;
        push_done = 1'b1;
    end

    // ---- reader: negedge driving, random rate, respecting empty -------------
    initial begin : p_reader
        wait (wr_rst_n && rd_rst_n);
        @(negedge rd_clk);
        forever begin
            if (!reader_pause && !empty &&
                (push_done || ($urandom_range(0, 99) < 60)))
                rd_en <= 1'b1;
            else
                rd_en <= 1'b0;
            @(negedge rd_clk);
        end
    end

    // ---- end-of-test checks --------------------------------------------------
    initial begin : p_finish
        wait (push_done);
        wait (n_popped == N_WORDS);
        repeat (6) @(posedge rd_clk);
        if (!saw_full) begin
            errors++; $display("ERROR: full was never observed");
        end
        if (!empty) begin
            errors++; $display("ERROR: fifo not empty at end");
        end
        if (model_q.size() != 0) begin
            errors++;
            $display("ERROR: model queue has %0d leftover words", model_q.size());
        end
        if (n_pushed != N_WORDS) begin
            errors++;
            $display("ERROR: pushed %0d != %0d", n_pushed, N_WORDS);
        end
        $display("pushed=%0d popped=%0d errors=%0d", n_pushed, n_popped, errors);
        if (errors == 0) $display("TB PASS");
        else             $display("TB FAIL: %0d errors", errors);
        $finish;
    end

    // ---- watchdog -------------------------------------------------------------
    initial begin
        #1ms;
        $display("TB FAIL: watchdog timeout (pushed=%0d popped=%0d)",
                 n_pushed, n_popped);
        $finish;
    end

endmodule
