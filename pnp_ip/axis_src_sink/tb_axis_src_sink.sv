// =============================================================================
// tb_axis_src_sink -- self-checking TB for the AXIS src/sink template.
// Sim only. Run: powershell -File scripts\run_sim.ps1 axis_src_sink
// Prints "TB PASS" and $finishes on success, "TB FAIL" otherwise.
//
// Checks:
//   1. signature matches a behavioral mirror of the data LFSR + MISR
//      (throttle-independent: data advances only on handshakes)
//   2. beat_cnt == NUM_PKTS*PKT_BEATS, pkt_cnt == NUM_PKTS
//   3. SVA: while stalled (tvalid && !tready) tvalid holds and tdata/tlast
//      stay stable (AXIS handshake invariant)
//   4. second start edge (sink auto-cleared inside axis_example_top) yields
//      the identical signature -> determinism
// =============================================================================
`timescale 1ns/1ps
module tb_axis_src_sink;

    localparam int          DATA_W    = 32;
    localparam logic [31:0] SEED      = 32'h1EDC_2026;
    localparam int          PKT_BEATS = 16;
    localparam int          NUM_PKTS  = 8;
    localparam int          LANES     = DATA_W / 32;
    localparam int          TOTAL     = NUM_PKTS * PKT_BEATS;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;                                // 100 MHz

    logic        start;
    logic        done;
    logic [31:0] signature, beat_cnt, pkt_cnt;

    int errors = 0;

    axis_example_top #(
        .DATA_W(DATA_W), .SEED(SEED), .PKT_BEATS(PKT_BEATS),
        .NUM_PKTS(NUM_PKTS), .THROTTLE(1'b1)             // both src+sink throttled
    ) dut (
        .clk, .rst_n, .start,
        .done, .signature, .beat_cnt, .pkt_cnt
    );

    // ---- mirror the internal AXIS wires for the assertion --------------------
    logic              m_tvalid, m_tready, m_tlast;
    logic [DATA_W-1:0] m_tdata;
    assign m_tvalid = dut.src_tvalid;
    assign m_tready = dut.src_tready;
    assign m_tdata  = dut.src_tdata;
    assign m_tlast  = dut.src_tlast;

    // ---- SVA: AXIS handshake invariant ---------------------------------------
    property p_axis_hold;
        @(posedge clk) disable iff (!rst_n)
        (m_tvalid && !m_tready) |=>
            (m_tvalid && $stable(m_tdata) && $stable(m_tlast));
    endproperty
    ap_axis_hold: assert property (p_axis_hold)
        else begin
            $display("ERROR: AXIS hold violated at %0t", $time);
            errors++;
        end

    // ---- behavioral mirror: data LFSR + MISR expected signature --------------
    function automatic logic [31:0] lfsr32_next(input logic [31:0] v);
        return {v[30:0], v[31] ^ v[21] ^ v[1] ^ v[0]};
    endfunction

    function automatic logic [31:0] calc_expected();
        logic [31:0] lane [LANES];
        logic [31:0] sig;
        logic [31:0] fold;
        logic        fb;
        for (int i = 0; i < LANES; i++)
            lane[i] = SEED ^ (32'h9E3779B9 * i);
        sig = 32'hFFFF_FFFF;
        for (int b = 0; b < TOTAL; b++) begin
            fold = '0;
            for (int i = 0; i < LANES; i++) fold ^= lane[i];
            fb  = sig[31] ^ sig[21] ^ sig[1] ^ sig[0];
            sig = {sig[30:0], fb} ^ fold;
            for (int i = 0; i < LANES; i++)
                lane[i] = lfsr32_next(lane[i]);
        end
        return sig;
    endfunction

    // ---- one full run: start edge, wait done, settle, check ------------------
    task automatic run_once(input int run_id, input logic [31:0] exp_sig);
        start <= 1'b1;                                   // rising edge = run
        repeat (3) @(posedge clk);
        start <= 1'b0;                                   // drop for next edge
        while (!done) @(posedge clk);
        repeat (10) @(posedge clk);                      // pipeline settle
        if (signature !== exp_sig) begin
            $display("ERROR: run %0d signature=%h expected=%h",
                     run_id, signature, exp_sig);
            errors++;
        end else begin
            $display("  ok: run %0d signature = %h", run_id, signature);
        end
        if (beat_cnt !== 32'(TOTAL)) begin
            $display("ERROR: run %0d beat_cnt=%0d expected=%0d",
                     run_id, beat_cnt, TOTAL);
            errors++;
        end else begin
            $display("  ok: run %0d beat_cnt = %0d", run_id, beat_cnt);
        end
        if (pkt_cnt !== 32'(NUM_PKTS)) begin
            $display("ERROR: run %0d pkt_cnt=%0d expected=%0d",
                     run_id, pkt_cnt, NUM_PKTS);
            errors++;
        end else begin
            $display("  ok: run %0d pkt_cnt = %0d", run_id, pkt_cnt);
        end
    endtask

    // ---- watchdog -------------------------------------------------------------
    initial begin
        #1ms;
        $display("TB FAIL: watchdog timeout");
        $finish;
    end

    // ---- test sequence ---------------------------------------------------------
    initial begin
        logic [31:0] exp_sig;
        exp_sig = calc_expected();
        $display("expected signature = %h (%0d beats)", exp_sig, TOTAL);

        start = 1'b0;
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        run_once(1, exp_sig);                            // first run
        run_once(2, exp_sig);                            // determinism check

        if (errors == 0) $display("TB PASS");
        else             $display("TB FAIL: %0d errors", errors);
        $finish;
    end

endmodule
