// =============================================================================
// universal_top -- universal HW bring-up top: stimulus -> DUT socket -> MISR.
//
// WHAT THIS IS
//   Drop any streaming DUT into the fenced USER DUT SOCKET and you get a
//   self-contained bring-up harness: deterministic stimulus in, 32-bit MISR
//   signature out. Control pins are simple levels/values so the whole block
//   can be driven by force/deposit on Protium (no bus master needed).
//
// OPERATION
//   1. deposit stim_mode / const_val / gap.
//   2. rising edge on start -> counters/signature cleared, generators
//      reseeded, run begins. start is a level; only its 0->1 edge matters.
//   3. NUM_SAMPLES samples are emitted (one per gap+1 cycles), pushed through
//      the DUT, responses compressed into signature.
//   4. done goes high when sample_cnt == NUM_SAMPLES; signature is final.
//      pass = done && EXPECTED_SIG != 0 && signature == EXPECTED_SIG.
//   5. re-run: drop start, raise it again. Restart only after done (a longer-
//      latency DUT may still have responses in flight mid-run).
//
// STIMULUS MODES (stim_mode)
//   0 = LFSR         per-32-bit-lane Fibonacci LFSR, taps 32,22,2,1 (XOR).
//                    lane seed = LFSR_SEED ^ lane*32'h9E3779B9 (0 -> 1 guard).
//   1 = counter      starts at 0, +1 per emitted sample.
//   2 = walking-one  starts at bit0, rotates left one place per sample.
//   3 = const_val    constant value from the const_val port.
//   Generators advance ONLY when a sample is emitted, so the data sequence
//   (and the signature) is identical for every gap value; gap changes timing
//   only. Keep stim_mode stable during a run.
//
// RULES
//   - clk/rst_n (async active-low) come from outside; NO clock dividers here.
//   - fully synthesizable; sim-only code only inside `ifdef SIMULATION.
//   - edit only between the // === USER ... START/END === fences.
// =============================================================================
module universal_top #(
    parameter int          DATA_W       = 32,
    parameter logic [31:0] LFSR_SEED    = 32'hACE1_2026,  // must be nonzero
    parameter int          NUM_SAMPLES  = 1024,
    parameter logic [31:0] EXPECTED_SIG = 32'h0           // 0 = no pass check
)(
    input  logic              clk,
    input  logic              rst_n,      // async active-low

    input  logic              start,      // level; rising edge = clear + run
    input  logic [1:0]        stim_mode,  // 0 LFSR, 1 counter, 2 walk1, 3 const
    input  logic [DATA_W-1:0] const_val,  // used when stim_mode == 3
    input  logic [3:0]        gap,        // emit 1 sample per gap+1 cycles

    output logic              done,       // sample_cnt == NUM_SAMPLES
    output logic              pass,       // done && sig==EXPECTED_SIG (!=0)
    output logic [31:0]       signature,  // MISR over DUT responses
    output logic [31:0]       sample_cnt  // responses accumulated so far
    // === USER PORTS START ===
    // add DUT-facing I/O here (prefix each new line with a comma)
    // === USER PORTS END ===
);

    localparam int          LANES = (DATA_W + 31) / 32;   // 32-bit stim lanes
    localparam logic [31:0] NS    = 32'(NUM_SAMPLES);

    // ---- fold a DATA_W response into 32 bits: XOR of its 32-bit lanes ------
    function automatic logic [31:0] fold32(input logic [DATA_W-1:0] d);
        logic [LANES*32-1:0] ext;
        logic [31:0]         acc;
        ext = '0;
        ext[DATA_W-1:0] = d;
        acc = '0;
        for (int l = 0; l < LANES; l++) acc ^= ext[32*l +: 32];
        return acc;
    endfunction

    // ---- start edge detect -------------------------------------------------
    logic start_q, running;
    wire  start_pulse = start & ~start_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_q <= 1'b0;
            running <= 1'b0;
        end else begin
            start_q <= start;
            if (start_pulse) running <= 1'b1;
        end
    end

    // ---- emit pacing: one sample per gap+1 cycles, NUM_SAMPLES total -------
    logic [31:0] sent;      // samples emitted so far this run
    logic [3:0]  gap_cnt;
    wire emit = running & ~start_pulse & (sent < NS) & (gap_cnt == 4'd0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sent    <= '0;
            gap_cnt <= '0;
        end else if (start_pulse) begin
            sent    <= '0;
            gap_cnt <= '0;
        end else if (emit) begin
            sent    <= sent + 32'd1;
            gap_cnt <= gap;
        end else if (gap_cnt != 4'd0) begin
            gap_cnt <= gap_cnt - 4'd1;
        end
    end

    // ---- stimulus generators (advance only on emit) ------------------------
    // LFSR: one 32-bit Fibonacci LFSR per lane, taps 32,22,2,1 (XOR feedback).
    logic [LANES*32-1:0] lfsr_bus;
    generate
        for (genvar gl = 0; gl < LANES; gl++) begin : g_lfsr
            localparam logic [31:0] SEED_RAW =
                LFSR_SEED ^ (32'h9E37_79B9 * 32'(gl));
            localparam logic [31:0] SEED =                 // nonzero guard
                (SEED_RAW == 32'h0) ? 32'h0000_0001 : SEED_RAW;
            logic [31:0] lane_q;
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n)           lane_q <= SEED;
                else if (start_pulse) lane_q <= SEED;
                else if (emit && stim_mode == 2'd0)
                    lane_q <= {lane_q[30:0],
                               lane_q[31] ^ lane_q[21] ^ lane_q[1] ^ lane_q[0]};
            end
            assign lfsr_bus[32*gl +: 32] = lane_q;
        end
    endgenerate

    // counter + walking-one
    logic [DATA_W-1:0] cnt_q, walk_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_q  <= '0;
            walk_q <= DATA_W'(1);
        end else if (start_pulse) begin
            cnt_q  <= '0;
            walk_q <= DATA_W'(1);
        end else if (emit) begin
            if (stim_mode == 2'd1) cnt_q  <= cnt_q + 1'b1;
            if (stim_mode == 2'd2) walk_q <= {walk_q[DATA_W-2:0],
                                              walk_q[DATA_W-1]};
        end
    end

    // mode mux -> stimulus stream into the DUT socket
    logic              stim_valid;
    logic [DATA_W-1:0] stim_data;
    assign stim_valid = emit;
    always_comb begin
        case (stim_mode)
            2'd0:    stim_data = lfsr_bus[DATA_W-1:0];
            2'd1:    stim_data = cnt_q;
            2'd2:    stim_data = walk_q;
            default: stim_data = const_val;
        endcase
    end

    // ---- DUT response stream (drive these from your DUT) -------------------
    logic              resp_valid;
    logic [DATA_W-1:0] resp_data;

    // === USER DUT SOCKET START ===
    // Replace the example below with your DUT. CONTRACT:
    //   in : stim_valid / stim_data[DATA_W-1:0]  (1 sample per stim_valid
    //        cycle; with gap=0 samples arrive back-to-back -- set gap >= your
    //        DUT's initiation interval if it cannot take one per cycle)
    //   out: resp_valid / resp_data[DATA_W-1:0]  (exactly ONE resp_valid per
    //        stim_valid, in order, at any fixed latency)
    //   Declare any extra internal signals here, above their first use.
    // Example DUT: registered rotate-left-1 XOR identity, latency 1.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_valid <= 1'b0;
            resp_data  <= '0;
        end else begin
            resp_valid <= stim_valid;
            resp_data  <= {stim_data[DATA_W-2:0], stim_data[DATA_W-1]}
                          ^ stim_data;
        end
    end
    // === USER DUT SOCKET END ===

    // ---- MISR signature checker (do not edit) ------------------------------
    // signature <= {signature[30:0], fb} ^ fold32(resp_data) on each response
    // fb = sig[31]^sig[21]^sig[1]^sig[0]; init 32'hFFFF_FFFF on start edge.
    wire sig_fb = signature[31] ^ signature[21] ^ signature[1] ^ signature[0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            signature  <= 32'hFFFF_FFFF;
            sample_cnt <= '0;
            done       <= 1'b0;
        end else if (start_pulse) begin
            signature  <= 32'hFFFF_FFFF;
            sample_cnt <= '0;
            done       <= 1'b0;
        end else if (resp_valid && (sample_cnt < NS)) begin
            signature  <= {signature[30:0], sig_fb} ^ fold32(resp_data);
            sample_cnt <= sample_cnt + 32'd1;
            if (sample_cnt == NS - 32'd1) done <= 1'b1;
        end
    end

    assign pass = done & (EXPECTED_SIG != 32'h0) & (signature == EXPECTED_SIG);

`ifdef EMU_FINISH
    // Protium bring-up aid: compile with -d EMU_FINISH to print the run
    // signature and stop when done. Keep $display/$finish in this fenced
    // block only, never inside datapath always blocks.
    always @(posedge clk)
        if (done) begin
            $display("universal_top: DONE samples=%0d signature=%08h pass=%0d",
                     sample_cnt, signature, pass);
            $finish;
        end
`endif

endmodule
