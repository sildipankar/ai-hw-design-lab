// =============================================================================
// tb_universal_top -- self-checking TB for the universal bring-up top.
// Sim only. Run: powershell -File scripts\run_sim.ps1 universal_top
// A behavioral mirror (generic over 32-bit lane count) recomputes the lane
// LFSRs, the example DUT, and the MISR; every hardware run is compared to it.
// Prints "TB PASS" and $finishes on success, "TB FAIL" otherwise.
// =============================================================================
`timescale 1ns/1ps
module tb_universal_top;

    localparam int          NS     = 1024;            // samples per run
    localparam logic [31:0] SEED   = 32'hACE1_2026;
    localparam logic [31:0] CVAL32 = 32'hDEAD_BEEF;
    localparam logic [63:0] CVAL64 = 64'hDEAD_BEEF_0BAD_F00D;
    localparam int          MW     = 128;             // mirror max data width

    // Golden signature for DATA_W=32, stim_mode=0 (LFSR), NS=1024: taken from
    // the mirror on the first sim run, then wired into u_dut32.EXPECTED_SIG so
    // the pass logic is exercised. Cross-checked against the mirror at time 0.
    localparam logic [31:0] GOLD32 = 32'hD544_6A1D;   // from golden sim run

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;                             // 100 MHz

    // shared controls: both instances run in lockstep
    logic       start;
    logic [1:0] stim_mode;
    logic [3:0] gap;

    // per-instance observables
    logic done32, pass32;
    logic done64, pass64;
    logic [31:0] sig32, scnt32;
    logic [31:0] sig64, scnt64;

    int errors = 0;

    universal_top #(
        .DATA_W(32), .LFSR_SEED(SEED), .NUM_SAMPLES(NS), .EXPECTED_SIG(GOLD32)
    ) u_dut32 (
        .clk(clk), .rst_n(rst_n), .start(start), .stim_mode(stim_mode),
        .const_val(CVAL32), .gap(gap),
        .done(done32), .pass(pass32), .signature(sig32), .sample_cnt(scnt32)
    );

    universal_top #(
        .DATA_W(64), .LFSR_SEED(SEED), .NUM_SAMPLES(NS), .EXPECTED_SIG(32'h0)
    ) u_dut64 (
        .clk(clk), .rst_n(rst_n), .start(start), .stim_mode(stim_mode),
        .const_val(CVAL64), .gap(gap),
        .done(done64), .pass(pass64), .signature(sig64), .sample_cnt(scnt64)
    );

    // ---- behavioral mirror --------------------------------------------------
    // Recomputes the expected end-of-run signature for any data_w (lane count
    // = ceil(data_w/32)), replicating: lane LFSR seeds/advance, counter,
    // walking-one, const, the example DUT (rotl1 ^ identity), fold32, MISR.
    // gap never affects the data sequence, so the mirror ignores it.
    function automatic logic [31:0] mirror_sig(
        input int            data_w,
        input int            num_samples,
        input logic [31:0]   seed_base,
        input logic [1:0]    mode,
        input logic [MW-1:0] cval);
        int lanes;
        logic [MW-1:0] lfsr, cnt, walk, stim, resp, mask;
        logic [31:0]   sig, fold, lane;
        logic          fb;
        lanes = (data_w + 31) / 32;
        mask  = (MW'(1) << data_w) - MW'(1);
        lfsr  = '0;
        for (int l = 0; l < lanes; l++) begin
            lane = seed_base ^ (32'h9E37_79B9 * l);
            if (lane == 32'h0) lane = 32'h0000_0001;  // nonzero guard
            lfsr[32*l +: 32] = lane;
        end
        cnt  = '0;
        walk = MW'(1);
        sig  = 32'hFFFF_FFFF;
        for (int s = 0; s < num_samples; s++) begin
            case (mode)
                2'd0:    stim = lfsr & mask;
                2'd1:    stim = cnt  & mask;
                2'd2:    stim = walk & mask;
                default: stim = cval & mask;
            endcase
            // example DUT: rotate-left-1 XOR identity, within data_w bits
            resp = (((stim << 1) | (stim >> (data_w - 1))) ^ stim) & mask;
            // fold32: XOR of 32-bit lanes
            fold = '0;
            for (int l = 0; l < lanes; l++) fold ^= resp[32*l +: 32];
            // MISR update
            fb  = sig[31] ^ sig[21] ^ sig[1] ^ sig[0];
            sig = {sig[30:0], fb} ^ fold;
            // advance generators (per emitted sample, like the RTL)
            for (int l = 0; l < lanes; l++) begin
                lane = lfsr[32*l +: 32];
                lfsr[32*l +: 32] =
                    {lane[30:0], lane[31] ^ lane[21] ^ lane[1] ^ lane[0]};
            end
            cnt  = (cnt + MW'(1)) & mask;
            walk = ((walk << 1) | (walk >> (data_w - 1))) & mask;
        end
        return sig;
    endfunction

    // ---- one hardware run: start edge, wait done, stability checks ---------
    task automatic run_once(
        input  logic [1:0]  mode,
        input  logic [3:0]  gap_i,
        output logic [31:0] got32,
        output logic [31:0] got64);
        stim_mode <= mode;
        gap       <= gap_i;
        @(posedge clk);
        start <= 1'b1;                                // rising edge = run
        do @(posedge clk); while (done32 || done64);  // wait for the clear
        wait (done32 && done64);
        @(posedge clk);
        got32 = sig32;
        got64 = sig64;
        if (scnt32 !== 32'(NS)) begin
            $display("ERROR: m%0d g%0d w32 sample_cnt=%0d expected %0d",
                     mode, gap_i, scnt32, NS);
            errors++;
        end
        if (scnt64 !== 32'(NS)) begin
            $display("ERROR: m%0d g%0d w64 sample_cnt=%0d expected %0d",
                     mode, gap_i, scnt64, NS);
            errors++;
        end
        // signature/count must freeze after done
        repeat (5) @(posedge clk);
        if (sig32 !== got32 || scnt32 !== 32'(NS)) begin
            $display("ERROR: m%0d g%0d w32 sig/cnt moved after done",
                     mode, gap_i);
            errors++;
        end
        if (sig64 !== got64 || scnt64 !== 32'(NS)) begin
            $display("ERROR: m%0d g%0d w64 sig/cnt moved after done",
                     mode, gap_i);
            errors++;
        end
        start <= 1'b0;                                // rearm for next edge
        repeat (3) @(posedge clk);
    endtask

    // ---- run + compare against the mirror, check pass semantics ------------
    task automatic run_and_check(
        input  logic [1:0]  mode,
        input  logic [3:0]  gap_i,
        output logic [31:0] got32,
        output logic [31:0] got64);
        logic [31:0] exp32, exp64;
        logic        exp_p32;
        run_once(mode, gap_i, got32, got64);
        exp32 = mirror_sig(32, NS, SEED, mode, MW'(CVAL32));
        exp64 = mirror_sig(64, NS, SEED, mode, MW'(CVAL64));
        if (got32 !== exp32) begin
            $display("ERROR: mode %0d gap %0d w32 sig=%08h mirror=%08h",
                     mode, gap_i, got32, exp32);
            errors++;
        end else begin
            $display("  ok: mode %0d gap %0d  w32 sig=%08h", mode, gap_i, got32);
        end
        if (got64 !== exp64) begin
            $display("ERROR: mode %0d gap %0d w64 sig=%08h mirror=%08h",
                     mode, gap_i, got64, exp64);
            errors++;
        end else begin
            $display("  ok: mode %0d gap %0d  w64 sig=%08h", mode, gap_i, got64);
        end
        // pass pin: u_dut32 checks against GOLD32; u_dut64 has no check (0)
        exp_p32 = (GOLD32 != 32'h0) && (exp32 == GOLD32);
        if (pass32 !== exp_p32) begin
            $display("ERROR: mode %0d gap %0d w32 pass=%b expected %b",
                     mode, gap_i, pass32, exp_p32);
            errors++;
        end
        if (pass64 !== 1'b0) begin
            $display("ERROR: mode %0d gap %0d w64 pass=%b (EXPECTED_SIG=0)",
                     mode, gap_i, pass64);
            errors++;
        end
    endtask

    // ---- watchdog -----------------------------------------------------------
    initial begin
        #1ms;
        $display("TB FAIL: watchdog timeout");
        $finish;
    end

    // ---- test sequence -------------------------------------------------------
    initial begin
        logic [31:0] a32, a64, b32, b64;
        logic [3:0]  gv;
        start = 0; stim_mode = '0; gap = '0;

        // guard against a stale hardcoded golden value
        if (GOLD32 != 32'h0 &&
            mirror_sig(32, NS, SEED, 2'd0, MW'(CVAL32)) != GOLD32) begin
            $display("ERROR: GOLD32 stale, mirror mode0 = %08h",
                     mirror_sig(32, NS, SEED, 2'd0, MW'(CVAL32)));
            errors++;
        end

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);
        if (done32 !== 1'b0 || pass32 !== 1'b0 ||
            done64 !== 1'b0 || pass64 !== 1'b0) begin
            $display("ERROR: done/pass not low before first start");
            errors++;
        end

        // all 4 modes x 2 gap values; each config run twice (determinism)
        for (int m = 0; m < 4; m++) begin
            for (int g = 0; g < 2; g++) begin
                gv = (g == 0) ? 4'd0 : 4'd3;
                run_and_check(2'(m), gv, a32, a64);
                run_and_check(2'(m), gv, b32, b64);   // fresh start edge
                if (a32 !== b32 || a64 !== b64) begin
                    $display("ERROR: mode %0d gap %0d rerun sig mismatch", m, gv);
                    errors++;
                end
            end
        end

        if (errors == 0) $display("TB PASS");
        else             $display("TB FAIL: %0d errors", errors);
        $finish;
    end

endmodule
