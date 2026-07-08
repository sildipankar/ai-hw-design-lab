// =============================================================================
// tb_dpi -- DPI-C testbench TEMPLATE: RTL vs C golden model, cycle by cycle.
// Run: powershell -ExecutionPolicy Bypass -File scripts\run_sim.ps1 tb_dpi
// Prints "TB PASS" and $finishes on success, "TB FAIL: N errors" otherwise.
//
// HOW THIS TEMPLATE WORKS
//   - golden.c holds the C reference model (built with xsc into library "dpi").
//   - The TB mirrors the DUT's accumulator in a C-side model (model_acc) using
//     the SAME inputs it drives into the RTL, then compares DUT acc vs model
//     just after every clock edge (#1 lets nonblocking updates settle).
//   - NOTE: this DPI TB is the ONLY deliverable style that is not
//     synthesizable; mac_dut.sv itself IS synthesizable.
//   - Edit only the fenced USER sections: add DPI imports + extra tests there.
// =============================================================================
`timescale 1ns/1ps
module tb_dpi;

    // ---- DPI imports ---------------------------------------------------------
    // SV int <-> C int, by value; no svdpi.h needed for scalar ints.
    import "DPI-C" function int golden_mac(input int acc, input int a, input int b);

    // === USER DPI IMPORTS START ===
    // Add further imports here, one per C function in golden.c, e.g.:
    // import "DPI-C" function int my_func(input int x);
    // === USER DPI IMPORTS END ===

    localparam int W        = 32;   // must stay 32 while the model uses C int
    localparam int N_CYCLES = 300;  // random stimulus cycles

    // ---- clock / reset / DUT hookup ------------------------------------------
    logic clk   = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;           // 100 MHz

    logic         clr, en;
    logic [W-1:0] a, b, acc;

    mac_dut #(.W(W)) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .clr   (clr),
        .en    (en),
        .a     (a),
        .b     (b),
        .acc   (acc)
    );

    // ---- bookkeeping ----------------------------------------------------------
    int errors    = 0;
    int model_acc = 0;              // C-side mirror of the DUT accumulator
    // per-cycle stimulus temporaries (declared before use; never name one "expect")
    logic         ren, rclr;
    int           ra, rb;
    logic [W-1:0] exp_val;

    // ---- watchdog --------------------------------------------------------------
    initial begin
        #1ms;
        $display("TB FAIL: watchdog timeout");
        $finish;
    end

    // ---- one checked cycle: drive DUT + mirror C model + compare ----------------
    task automatic mac_cycle(input logic t_clr, input logic t_en,
                             input int t_a, input int t_b);
        clr <= t_clr;
        en  <= t_en;
        a   <= t_a;
        b   <= t_b;
        // mirror what the RTL will do at the coming posedge
        if (t_clr)      model_acc = 0;
        else if (t_en)  model_acc = golden_mac(model_acc, t_a, t_b);
        @(posedge clk);
        #1;                                  // let nonblocking acc update settle
        exp_val = model_acc;
        if (acc !== exp_val) begin
            $display("ERROR: @%0t acc=%h expected %h (clr=%b en=%b a=%h b=%h)",
                     $time, acc, exp_val, t_clr, t_en, t_a, t_b);
            errors++;
        end
    endtask

    // ---- test sequence -----------------------------------------------------------
    initial begin
        clr = 1'b0; en = 1'b0; a = '0; b = '0;
        model_acc = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // 300 random cycles: en ~75%, clr ~5%, full-width random a/b
        for (int i = 0; i < N_CYCLES; i++) begin
            ren  = ($urandom_range(0, 3)  != 0);
            rclr = ($urandom_range(0, 19) == 0);
            ra   = $urandom();
            rb   = $urandom();
            mac_cycle(rclr, ren, ra, rb);
        end

        // === USER TESTS START ===
        // Add directed tests here using mac_cycle(clr, en, a, b), e.g.:
        mac_cycle(1'b1, 1'b0, 0, 0);         // clear
        mac_cycle(1'b0, 1'b1, 7, 6);         // acc = 42
        mac_cycle(1'b0, 1'b0, 99, 99);       // hold (en=0)
        mac_cycle(1'b0, 1'b1, -1, 2);        // signed wrap: acc = 42 - 2 = 40
        // === USER TESTS END ===

        if (errors == 0) $display("TB PASS");
        else             $display("TB FAIL: %0d errors", errors);
        $finish;
    end

endmodule
