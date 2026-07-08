// =============================================================================
// async_fifo -- dual-clock FIFO, Cummings gray-pointer style. Plug-and-play.
//
// HOW THIS TEMPLATE WORKS
//   - Gray-coded read/write pointers (DEPTH_LOG2+1 bits) cross domains through
//     2-flop (* ASYNC_REG *) synchronizers. full/empty are registered in their
//     own domain per the Cummings equations. This machinery is complete and
//     correct: DO NOT EDIT anything below the USER PARAMS fence.
//   - You only touch WIDTH / DEPTH_LOG2 in the fenced parameter list.
//   - First-word fall-through (FWFT): rd_data always shows the head word while
//     empty=0; assert rd_en for one rd_clk to pop it.
//   - wr_clk / rd_clk come from outside (tool-generated clocks, no dividers
//     here). Resets are async active-low, one per domain.
//   - Fully synthesizable. FWFT read implies distributed RAM (LUTRAM) on FPGA.
// =============================================================================
module async_fifo #(
    // ======================= USER PARAMS START ===============================
    parameter int WIDTH      = 32,  // data width
    parameter int DEPTH_LOG2 = 4    // depth = 2**DEPTH_LOG2 entries (min 2)
    // ======================= USER PARAMS END =================================
)(
    // write domain
    input  logic             wr_clk,
    input  logic             wr_rst_n,
    input  logic             wr_en,      // push wr_data (ignored when full)
    input  logic [WIDTH-1:0] wr_data,
    output logic             full,

    // read domain
    input  logic             rd_clk,
    input  logic             rd_rst_n,
    input  logic             rd_en,      // pop head word (ignored when empty)
    output logic [WIDTH-1:0] rd_data,    // FWFT: valid whenever empty=0
    output logic             empty
);

    // =========================================================================
    // CDC protocol engine (DO NOT EDIT: gray coding, sync stages, ASYNC_REG,
    // full/empty equations are load-bearing for metastability safety)
    // =========================================================================
    localparam int PTR_W = DEPTH_LOG2 + 1;      // one extra wrap bit
    localparam int DEPTH = 1 << DEPTH_LOG2;

    logic [WIDTH-1:0] mem [0:DEPTH-1];

    // write-domain pointers + read-gray synchronized into write domain
    logic [PTR_W-1:0] wbin, wgray;
    logic [PTR_W-1:0] wbin_next, wgray_next;
    (* ASYNC_REG = "TRUE" *) logic [PTR_W-1:0] rq1_rgray, rq2_rgray;

    // read-domain pointers + write-gray synchronized into read domain
    logic [PTR_W-1:0] rbin, rgray;
    logic [PTR_W-1:0] rbin_next, rgray_next;
    (* ASYNC_REG = "TRUE" *) logic [PTR_W-1:0] wq1_wgray, wq2_wgray;

    // ---- write domain -------------------------------------------------------
    assign wbin_next  = wbin + PTR_W'(wr_en & ~full);
    assign wgray_next = (wbin_next >> 1) ^ wbin_next;

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wbin  <= '0;
            wgray <= '0;
            full  <= 1'b0;
        end else begin
            wbin  <= wbin_next;
            wgray <= wgray_next;
            // Cummings full: next wgray equals synced rgray with the two MSBs
            // inverted (write pointer one full wrap ahead of read pointer)
            full  <= (wgray_next ==
                      {~rq2_rgray[PTR_W-1:PTR_W-2], rq2_rgray[PTR_W-3:0]});
        end
    end

    always_ff @(posedge wr_clk) begin
        if (wr_en && !full)
            mem[wbin[DEPTH_LOG2-1:0]] <= wr_data;
    end

    // read gray pointer -> write domain (2-flop synchronizer)
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rq1_rgray <= '0;
            rq2_rgray <= '0;
        end else begin
            rq1_rgray <= rgray;
            rq2_rgray <= rq1_rgray;
        end
    end

    // ---- read domain --------------------------------------------------------
    assign rbin_next  = rbin + PTR_W'(rd_en & ~empty);
    assign rgray_next = (rbin_next >> 1) ^ rbin_next;

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rbin  <= '0;
            rgray <= '0;
            empty <= 1'b1;
        end else begin
            rbin  <= rbin_next;
            rgray <= rgray_next;
            // Cummings empty: next rgray catches up with synced wgray
            empty <= (rgray_next == wq2_wgray);
        end
    end

    // FWFT combinational read of the head word
    assign rd_data = mem[rbin[DEPTH_LOG2-1:0]];

    // write gray pointer -> read domain (2-flop synchronizer)
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wq1_wgray <= '0;
            wq2_wgray <= '0;
        end else begin
            wq1_wgray <= wgray;
            wq2_wgray <= wq1_wgray;
        end
    end

endmodule
