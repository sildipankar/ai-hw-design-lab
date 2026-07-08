// =============================================================================
// cdc_pack -- clock-domain-crossing primitive pack, plug-and-play.
// One file, four modules:
//   cdc_bit_sync       : 1-bit (or quasi-static bus) level synchronizer
//   cdc_pulse_sync     : 1-cycle pulse crosser (toggle-and-sync + edge detect)
//   cdc_bus_handshake  : multi-bit word crosser, req/ack toggle handshake
//   cdc_example_top    : synthesizable top wiring all three (usage example)
//
// HOW THIS TEMPLATE WORKS
//   - The CDC machinery is complete and correct: DO NOT EDIT sync stages,
//     toggle/edge-detect logic, or (* ASYNC_REG="TRUE" *) attributes.
//   - You only touch the // === USER ... === fenced params (widths, stages).
//   - Clocks come from outside (tool-generated, no dividers here). Resets are
//     async active-low, one per domain.
//   - Pick your primitive:
//       1-bit level / slow status ................ cdc_bit_sync
//       single-cycle event/strobe ................ cdc_pulse_sync
//       multi-bit value, occasional update ....... cdc_bus_handshake
//       multi-bit stream (word after word) ....... async_fifo (separate block)
//     cdc_bus_handshake takes several cycles in BOTH domains per word --
//     never use it for streaming data.
// =============================================================================

// -----------------------------------------------------------------------------
// cdc_bit_sync -- classic multi-flop level synchronizer.
// WIDTH > 1 is ONLY safe for quasi-static or gray-coded buses (bits may skew).
// No reset on purpose: it just follows din after STAGES dst_clk cycles.
// -----------------------------------------------------------------------------
module cdc_bit_sync #(
    // ======================= USER PARAMS START ===============================
    parameter int STAGES = 2,   // synchronizer depth (min 2)
    parameter int WIDTH  = 1    // >1 only for quasi-static / gray-coded input
    // ======================= USER PARAMS END =================================
)(
    input  logic             dst_clk,
    input  logic [WIDTH-1:0] din,     // async input (from another domain)
    output logic [WIDTH-1:0] dout     // din, synchronized to dst_clk
);
    // ---- synchronizer chain (DO NOT EDIT) -----------------------------------
    (* ASYNC_REG = "TRUE" *) logic [STAGES-1:0][WIDTH-1:0] sync_q;

    always_ff @(posedge dst_clk) begin
        sync_q[0] <= din;
        for (int i = 1; i < STAGES; i++)
            sync_q[i] <= sync_q[i-1];
    end

    assign dout = sync_q[STAGES-1];
endmodule

// -----------------------------------------------------------------------------
// cdc_pulse_sync -- carries a 1-src_clk-wide pulse into dst domain as a
// 1-dst_clk-wide pulse. Toggle-and-sync: src pulse flips a toggle flop, dst
// synchronizes the toggle and edge-detects it.
// LIMIT: src pulses must be spaced > ~3 dst_clk periods apart or they merge.
// -----------------------------------------------------------------------------
module cdc_pulse_sync (
    input  logic src_clk,
    input  logic src_rst_n,
    input  logic src_pulse,   // 1-cycle strobe in src domain
    input  logic dst_clk,
    input  logic dst_rst_n,
    output logic dst_pulse    // 1-cycle strobe in dst domain
);
    // ---- CDC protocol (DO NOT EDIT) -----------------------------------------
    logic src_toggle;
    (* ASYNC_REG = "TRUE" *) logic tgl_d1, tgl_d2;
    logic tgl_d3;

    always_ff @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n)      src_toggle <= 1'b0;
        else if (src_pulse)  src_toggle <= ~src_toggle;
    end

    always_ff @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            tgl_d1 <= 1'b0;
            tgl_d2 <= 1'b0;
            tgl_d3 <= 1'b0;
        end else begin
            tgl_d1 <= src_toggle;
            tgl_d2 <= tgl_d1;
            tgl_d3 <= tgl_d2;
        end
    end

    assign dst_pulse = tgl_d2 ^ tgl_d3;   // one dst cycle per toggle edge
endmodule

// -----------------------------------------------------------------------------
// cdc_bus_handshake -- moves one WIDTH-bit word src->dst with a req/ack toggle
// handshake. src_data is captured into data_hold and held stable while the
// req toggle is in flight, so the multi-bit crossing is glitch-safe.
// THROUGHPUT: one word per ~(3 src_clk + 3 dst_clk); use async_fifo for streams.
// -----------------------------------------------------------------------------
module cdc_bus_handshake #(
    // ======================= USER PARAMS START ===============================
    parameter int WIDTH = 32
    // ======================= USER PARAMS END =================================
)(
    // src domain
    input  logic             src_clk,
    input  logic             src_rst_n,
    input  logic             src_valid,  // request to send src_data
    output logic             src_ready,  // 1 = idle, transfer accepted when valid
    input  logic [WIDTH-1:0] src_data,

    // dst domain
    input  logic             dst_clk,
    input  logic             dst_rst_n,
    output logic             dst_valid,  // 1-cycle strobe: dst_data is fresh
    output logic [WIDTH-1:0] dst_data
);
    // ---- CDC protocol (DO NOT EDIT) -----------------------------------------
    // src-domain state
    logic             req_toggle;
    logic [WIDTH-1:0] data_hold;
    (* ASYNC_REG = "TRUE" *) logic ack_s1, ack_s2;

    // dst-domain state
    (* ASYNC_REG = "TRUE" *) logic req_d1, req_d2;
    logic             req_d3;
    logic             ack_toggle;

    // ready when the last request has been acknowledged (req == synced ack)
    assign src_ready = (req_toggle == ack_s2);

    always_ff @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            req_toggle <= 1'b0;
            data_hold  <= '0;
        end else if (src_valid && src_ready) begin
            req_toggle <= ~req_toggle;    // launch request
            data_hold  <= src_data;       // held stable until ack returns
        end
    end

    // ack toggle -> src domain (2-flop synchronizer)
    always_ff @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            ack_s1 <= 1'b0;
            ack_s2 <= 1'b0;
        end else begin
            ack_s1 <= ack_toggle;
            ack_s2 <= ack_s1;
        end
    end

    // req toggle -> dst domain, edge detect, capture, ack
    always_ff @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            req_d1     <= 1'b0;
            req_d2     <= 1'b0;
            req_d3     <= 1'b0;
            ack_toggle <= 1'b0;
            dst_valid  <= 1'b0;
            dst_data   <= '0;
        end else begin
            req_d1    <= req_toggle;
            req_d2    <= req_d1;
            req_d3    <= req_d2;
            dst_valid <= 1'b0;
            if (req_d2 != req_d3) begin   // request edge arrived
                dst_data   <= data_hold;  // safe: stable for >=2 dst cycles
                dst_valid  <= 1'b1;
                ack_toggle <= req_d2;     // acknowledge back to src
            end
        end
    end
endmodule

// -----------------------------------------------------------------------------
// cdc_example_top -- synthesizable top + usage example: wires all three
// primitives between domain A (clk_a) and domain B (clk_b).
// Synth: scripts\run_synth.ps1 cdc_pack cdc_example_top
// -----------------------------------------------------------------------------
module cdc_example_top (
    input  logic        clk_a,
    input  logic        rst_a_n,
    input  logic        clk_b,
    input  logic        rst_b_n,

    // cdc_bit_sync example: level A -> B
    input  logic        a_level,
    output logic        b_level,

    // cdc_pulse_sync example: strobe A -> B
    input  logic        a_pulse,
    output logic        b_pulse,

    // cdc_bus_handshake example: 32-bit word A -> B
    input  logic        a_valid,
    output logic        a_ready,
    input  logic [31:0] a_data,
    output logic        b_valid,
    output logic [31:0] b_data
);
    cdc_bit_sync #(.STAGES(2), .WIDTH(1)) u_bit_sync (
        .dst_clk (clk_b),
        .din     (a_level),
        .dout    (b_level)
    );

    cdc_pulse_sync u_pulse_sync (
        .src_clk   (clk_a),
        .src_rst_n (rst_a_n),
        .src_pulse (a_pulse),
        .dst_clk   (clk_b),
        .dst_rst_n (rst_b_n),
        .dst_pulse (b_pulse)
    );

    cdc_bus_handshake #(.WIDTH(32)) u_bus (
        .src_clk   (clk_a),
        .src_rst_n (rst_a_n),
        .src_valid (a_valid),
        .src_ready (a_ready),
        .src_data  (a_data),
        .dst_clk   (clk_b),
        .dst_rst_n (rst_b_n),
        .dst_valid (b_valid),
        .dst_data  (b_data)
    );
endmodule
