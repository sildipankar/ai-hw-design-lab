// =============================================================================
// axis_src_sink -- AXI-Stream LFSR traffic source + MISR signature sink.
// Plug-and-play template for FPGA prototyping (Protium): drop the source and
// sink around any streaming DUT, force `start` in hardware, read
// signature/beat_cnt/pkt_cnt in waves, compare against a golden simulation.
//
// Three modules in this file (all synthesizable):
//   axis_lfsr_src    -- deterministic pseudo-random packet generator
//   axis_sig_sink    -- MISR signature + beat/packet counters
//   axis_example_top -- src wired straight to sink (synth top + wiring example)
//
// RULES
//   - clk / rst_n come from outside (tool-generated clock, no dividers here).
//   - DATA_W must be a multiple of 32.
//   - SEED / TSEED must be nonzero (an all-zero LFSR locks up).
//   - Data advances ONLY on tvalid&&tready, so the signature depends only on
//     the data stream, never on throttle timing or backpressure.
//   - Edit only inside // === USER ... === fences.
// =============================================================================

// -----------------------------------------------------------------------------
// axis_lfsr_src -- AXI-Stream master, NUM_PKTS packets of PKT_BEATS beats.
//   start rising edge : reset counters + reload seeds + run.
//   Data LFSR         : taps 32,22,2,1 (XOR), one 32-bit LFSR per 32-bit lane,
//                       lane seed = SEED ^ lane*32'h9E3779B9. Advances ONLY on
//                       a completed handshake.
//   Throttle LFSR     : free-running, gates tvalid. AXIS-compliant: once
//                       tvalid=1 it holds until tready (gate is only
//                       re-evaluated after a completed beat).
// -----------------------------------------------------------------------------
module axis_lfsr_src #(
    parameter int          DATA_W    = 32,
    parameter logic [31:0] SEED      = 32'h1EDC_2026,
    parameter int          PKT_BEATS = 16,
    parameter int          NUM_PKTS  = 8,
    parameter bit          THROTTLE  = 1'b1
)(
    input  logic              clk,
    input  logic              rst_n,          // async, active low
    input  logic              start,          // rising edge = (re)start
    output logic              m_tvalid,
    input  logic              m_tready,
    output logic [DATA_W-1:0] m_tdata,
    output logic              m_tlast,
    output logic              busy,           // high while sending
    output logic              done            // high after last beat, until next start
);
    localparam int LANES = DATA_W / 32;
    localparam logic [31:0] THR_SEED = SEED ^ 32'hA5A5_0F0F; // throttle seed

    // 32-bit maximal-length LFSR, taps 32,22,2,1 (XOR)
    function automatic logic [31:0] lfsr32_next(input logic [31:0] v);
        return {v[30:0], v[31] ^ v[21] ^ v[1] ^ v[0]};
    endfunction

    function automatic logic [31:0] lane_seed(input int lane);
        return SEED ^ (32'h9E3779B9 * lane);
    endfunction

    // ---- start rising-edge detect -------------------------------------------
    logic start_q;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) start_q <= 1'b0;
        else        start_q <= start;
    wire start_rise = start & ~start_q;

    // ---- free-running throttle LFSR (reloaded on start for repeatable runs) -
    logic [31:0] thr_lfsr;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)          thr_lfsr <= THR_SEED;
        else if (start_rise) thr_lfsr <= THR_SEED;
        else                 thr_lfsr <= lfsr32_next(thr_lfsr);

    // === USER THROTTLE PROFILE START =========================================
    // gate=1 means "offer a beat". Default ~50% duty. Example 75%:
    //   wire gate = THROTTLE ? (thr_lfsr[1:0] != 2'b00) : 1'b1;
    wire gate = THROTTLE ? thr_lfsr[0] : 1'b1;
    // === USER THROTTLE PROFILE END ===========================================

    // ---- stream engine -------------------------------------------------------
    logic [31:0] lane_lfsr [LANES];
    logic        running;
    logic        offer;          // a beat is currently offered (drives tvalid)
    logic [31:0] beat_in_pkt;
    logic [31:0] pkts_sent;

    wire hs        = m_tvalid & m_tready;
    wire last_beat = (beat_in_pkt == 32'(PKT_BEATS - 1));
    wire last_pkt  = (pkts_sent  == 32'(NUM_PKTS  - 1));

    assign m_tvalid = offer;
    assign m_tlast  = last_beat;
    assign busy     = running;

    always_comb
        for (int i = 0; i < LANES; i++)
            m_tdata[32*i +: 32] = lane_lfsr[i];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running     <= 1'b0;
            offer       <= 1'b0;
            done        <= 1'b0;
            beat_in_pkt <= '0;
            pkts_sent   <= '0;
            for (int i = 0; i < LANES; i++) lane_lfsr[i] <= lane_seed(i);
        end else if (start_rise) begin
            running     <= 1'b1;
            offer       <= 1'b0;
            done        <= 1'b0;
            beat_in_pkt <= '0;
            pkts_sent   <= '0;
            for (int i = 0; i < LANES; i++) lane_lfsr[i] <= lane_seed(i);
        end else if (running) begin
            if (!offer) begin
                offer <= gate;                       // may begin offering
            end else if (hs) begin                   // beat completed
                for (int i = 0; i < LANES; i++)
                    lane_lfsr[i] <= lfsr32_next(lane_lfsr[i]);
                if (last_beat) begin
                    beat_in_pkt <= '0;
                    pkts_sent   <= pkts_sent + 1;
                    if (last_pkt) begin
                        running <= 1'b0;
                        offer   <= 1'b0;
                        done    <= 1'b1;
                    end else begin
                        offer <= gate;               // reconsider after beat
                    end
                end else begin
                    beat_in_pkt <= beat_in_pkt + 1;
                    offer       <= gate;             // reconsider after beat
                end
            end
            // offer && !hs : hold tvalid/tdata/tlast (AXIS requirement)
        end
    end

`ifdef SIMULATION
    initial begin
        if (DATA_W % 32 != 0) $fatal(1, "axis_lfsr_src: DATA_W must be a multiple of 32");
        if (SEED == 32'h0)    $fatal(1, "axis_lfsr_src: SEED must be nonzero");
    end
`endif
endmodule

// -----------------------------------------------------------------------------
// axis_sig_sink -- AXI-Stream slave: MISR signature + beat/packet counters.
//   s_tready is registered; free toggling of tready is legal AXIS, so it is
//   LFSR-throttled when THROTTLE=1, constant 1 otherwise.
//   On each handshake:
//     fb        = sig[31]^sig[21]^sig[1]^sig[0]
//     signature <= {sig[30:0], fb} ^ fold32(s_tdata)   (init 32'hFFFF_FFFF)
//   clear (sync, level): re-init signature and counters.
// -----------------------------------------------------------------------------
module axis_sig_sink #(
    parameter int          DATA_W   = 32,
    parameter bit          THROTTLE = 1'b1,
    parameter logic [31:0] TSEED    = 32'hBEEF_0107
)(
    input  logic              clk,
    input  logic              rst_n,          // async, active low
    input  logic              clear,          // sync clear of signature/counters
    input  logic              s_tvalid,
    output logic              s_tready,
    input  logic [DATA_W-1:0] s_tdata,
    input  logic              s_tlast,
    output logic [31:0]       signature,
    output logic [31:0]       beat_cnt,
    output logic [31:0]       pkt_cnt
);
    function automatic logic [31:0] lfsr32_next(input logic [31:0] v);
        return {v[30:0], v[31] ^ v[21] ^ v[1] ^ v[0]};
    endfunction

    // XOR-fold DATA_W down to 32 bits
    function automatic logic [31:0] fold32(input logic [DATA_W-1:0] d);
        fold32 = '0;
        for (int i = 0; i < DATA_W/32; i++) fold32 ^= d[32*i +: 32];
    endfunction

    // ---- free-running throttle LFSR (reloaded on clear for repeatable runs) -
    logic [31:0] thr_lfsr;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)     thr_lfsr <= TSEED;
        else if (clear) thr_lfsr <= TSEED;
        else            thr_lfsr <= lfsr32_next(thr_lfsr);

    // === USER READY PROFILE START ============================================
    // tready may toggle freely (AXIS allows a slave to drop ready any time).
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) s_tready <= 1'b0;
        else        s_tready <= THROTTLE ? thr_lfsr[0] : 1'b1;
    // === USER READY PROFILE END ==============================================

    wire hs = s_tvalid & s_tready;
    wire fb = signature[31] ^ signature[21] ^ signature[1] ^ signature[0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            signature <= 32'hFFFF_FFFF;
            beat_cnt  <= '0;
            pkt_cnt   <= '0;
        end else if (clear) begin
            signature <= 32'hFFFF_FFFF;
            beat_cnt  <= '0;
            pkt_cnt   <= '0;
        end else if (hs) begin
            signature <= {signature[30:0], fb} ^ fold32(s_tdata);
            beat_cnt  <= beat_cnt + 1;
            if (s_tlast) pkt_cnt <= pkt_cnt + 1;
        end
    end

`ifdef SIMULATION
    initial begin
        if (DATA_W % 32 != 0) $fatal(1, "axis_sig_sink: DATA_W must be a multiple of 32");
        if (TSEED == 32'h0)   $fatal(1, "axis_sig_sink: TSEED must be nonzero");
    end
`endif
endmodule

// -----------------------------------------------------------------------------
// axis_example_top -- synthesis top + wiring example: src straight to sink.
//   A start rising edge also pulses the sink's clear for one cycle, so every
//   new start yields a fresh, repeatable signature (no separate clear pin).
//   To test your own streaming DUT, splice it in at the USER fence below.
// -----------------------------------------------------------------------------
module axis_example_top #(
    parameter int          DATA_W    = 32,
    parameter logic [31:0] SEED      = 32'h1EDC_2026,
    parameter int          PKT_BEATS = 16,
    parameter int          NUM_PKTS  = 8,
    parameter bit          THROTTLE  = 1'b1
)(
    input  logic        clk,
    input  logic        rst_n,          // async, active low
    input  logic        start,          // rising edge = run (force in HW)
    output logic        done,
    output logic [31:0] signature,
    output logic [31:0] beat_cnt,
    output logic [31:0] pkt_cnt
);
    // src-side stream
    logic              src_tvalid, src_tready, src_tlast;
    logic [DATA_W-1:0] src_tdata;
    // sink-side stream
    logic              snk_tvalid, snk_tready, snk_tlast;
    logic [DATA_W-1:0] snk_tdata;

    logic busy_unused;

    // start rising edge -> one-cycle sink clear (first beat arrives later)
    logic start_q;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) start_q <= 1'b0;
        else        start_q <= start;
    wire clear_pulse = start & ~start_q;

    axis_lfsr_src #(
        .DATA_W(DATA_W), .SEED(SEED), .PKT_BEATS(PKT_BEATS),
        .NUM_PKTS(NUM_PKTS), .THROTTLE(THROTTLE)
    ) u_src (
        .clk, .rst_n, .start,
        .m_tvalid(src_tvalid), .m_tready(src_tready),
        .m_tdata(src_tdata),   .m_tlast(src_tlast),
        .busy(busy_unused), .done
    );

    // === USER DUT START =======================================================
    // src drives sink directly. To test your streaming DUT, delete these four
    // assigns and connect: src_* -> DUT slave port, DUT master port -> snk_*.
    assign snk_tvalid = src_tvalid;
    assign snk_tdata  = src_tdata;
    assign snk_tlast  = src_tlast;
    assign src_tready = snk_tready;
    // === USER DUT END =========================================================

    axis_sig_sink #(
        .DATA_W(DATA_W), .THROTTLE(THROTTLE)
    ) u_snk (
        .clk, .rst_n, .clear(clear_pulse),
        .s_tvalid(snk_tvalid), .s_tready(snk_tready),
        .s_tdata(snk_tdata),   .s_tlast(snk_tlast),
        .signature, .beat_cnt, .pkt_cnt
    );
endmodule
