// =============================================================================
// tb_axi_full_slave -- self-checking TB for the AXI4 full memory slave.
// Sim only. Run: powershell -File scripts\run_sim.ps1 axi_full_slave
// Prints "TB PASS" and $finishes on success, "TB FAIL" otherwise.
//
// Coverage: INCR len 0/7/15, WRAP len 3 from a mid-window start (wrap order
// verified via a linear read-back), FIXED len 3, partial wstrb, random data,
// random wvalid gaps, random rready backpressure, concurrent write+read.
// =============================================================================
`timescale 1ns/1ps
module tb_axi_full_slave;

    localparam int ID_W   = 4;
    localparam int ADDR_W = 12;
    localparam int DATA_W = 32;
    localparam int WORDS  = 2**(ADDR_W-2);

    localparam logic [1:0] B_FIXED = 2'b00;
    localparam logic [1:0] B_INCR  = 2'b01;
    localparam logic [1:0] B_WRAP  = 2'b10;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;                                // 100 MHz

    // ---- DUT hookup ---------------------------------------------------------
    logic [ID_W-1:0]     awid;    logic [ADDR_W-1:0] awaddr;
    logic [7:0]          awlen;   logic [2:0]  awsize;  logic [1:0] awburst;
    logic                awvalid, awready;
    logic [DATA_W-1:0]   wdata;   logic [DATA_W/8-1:0] wstrb;
    logic                wlast, wvalid, wready;
    logic [ID_W-1:0]     bid;     logic [1:0]  bresp;
    logic                bvalid, bready;
    logic [ID_W-1:0]     arid;    logic [ADDR_W-1:0] araddr;
    logic [7:0]          arlen;   logic [2:0]  arsize;  logic [1:0] arburst;
    logic                arvalid, arready;
    logic [ID_W-1:0]     rid;     logic [DATA_W-1:0] rdata;
    logic [1:0]          rresp;   logic rlast, rvalid, rready;

    int errors = 0;

    // reference model of the slave memory (updated by the write task)
    logic [DATA_W-1:0] model_mem [0:WORDS-1];

    axi_full_slave #(.ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W)) dut (
        .clk, .rst_n,
        .s_axi_awid(awid), .s_axi_awaddr(awaddr), .s_axi_awlen(awlen),
        .s_axi_awsize(awsize), .s_axi_awburst(awburst),
        .s_axi_awlock(1'b0), .s_axi_awcache(4'b0), .s_axi_awprot(3'b0),
        .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wlast(wlast),
        .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bid(bid), .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_arid(arid), .s_axi_araddr(araddr), .s_axi_arlen(arlen),
        .s_axi_arsize(arsize), .s_axi_arburst(arburst),
        .s_axi_arlock(1'b0), .s_axi_arcache(4'b0), .s_axi_arprot(3'b0),
        .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rid(rid), .s_axi_rdata(rdata), .s_axi_rresp(rresp),
        .s_axi_rlast(rlast), .s_axi_rvalid(rvalid), .s_axi_rready(rready)
    );

    // ---- burst next-address model (mirrors the AXI4 rules) -------------------
    function automatic logic [ADDR_W-1:0] tb_next_addr(
        input logic [ADDR_W-1:0] cur,
        input logic [1:0]        burst,
        input logic [2:0]        size,
        input logic [7:0]        len);
        int bytes_per_beat;
        int total_bytes;
        int base;
        int nxt;
        begin
            bytes_per_beat = 1 << size;
            total_bytes    = bytes_per_beat * (int'(len) + 1);
            nxt            = int'(cur) + bytes_per_beat;
            case (burst)
                B_FIXED: tb_next_addr = cur;
                B_WRAP: begin
                    base = int'(cur) & ~(total_bytes - 1);
                    if (nxt >= base + total_bytes) nxt = base;
                    tb_next_addr = ADDR_W'(nxt);
                end
                default: tb_next_addr = ADDR_W'(nxt);
            endcase
        end
    endfunction

    // ---- AXI master tasks -----------------------------------------------------
    // Handshake pattern everywhere: assert valid; @(posedge clk);
    // while(!ready) @(posedge clk); deassert.  Values read right after an edge
    // are the pre-edge values the DUT sampled, so this is race-free.

    // burst write: random data per beat, model memory updated under wstrb.
    // gaps=1 inserts random wvalid low cycles between beats.
    task automatic axi_wburst(
        input logic [ID_W-1:0]     id,
        input logic [ADDR_W-1:0]   addr,
        input logic [7:0]          len,
        input logic [1:0]          burst,
        input logic [DATA_W/8-1:0] strb,
        input bit                  gaps);
        logic [ADDR_W-1:0] a;
        logic [DATA_W-1:0] d;
        begin
            // AW
            awid    <= id;
            awaddr  <= addr;
            awlen   <= len;
            awsize  <= 3'd2;                       // full 32-bit beats
            awburst <= burst;
            awvalid <= 1'b1;
            @(posedge clk);
            while (!awready) @(posedge clk);
            awvalid <= 1'b0;
            // W beats
            a = addr;
            for (int beat = 0; beat <= int'(len); beat++) begin
                if (gaps) begin
                    wvalid <= 1'b0;
                    repeat ($urandom_range(0, 3)) @(posedge clk);
                end
                d = $urandom();
                wdata  <= d;
                wstrb  <= strb;
                wlast  <= (beat == int'(len));
                wvalid <= 1'b1;
                @(posedge clk);
                while (!wready) @(posedge clk);
                wvalid <= 1'b0;
                wlast  <= 1'b0;
                // reference model update (byte lanes under strb)
                for (int b = 0; b < DATA_W/8; b++)
                    if (strb[b]) model_mem[a[ADDR_W-1:2]][8*b +: 8] = d[8*b +: 8];
                a = tb_next_addr(a, burst, 3'd2, len);
            end
            // B
            bready <= 1'b1;
            @(posedge clk);
            while (!bvalid) @(posedge clk);
            if (bid !== id) begin
                $display("ERROR: bid=%h expected %h", bid, id); errors++;
            end
            if (bresp !== 2'b00) begin
                $display("ERROR: bresp=%b for write @%h", bresp, addr); errors++;
            end
            bready <= 1'b0;
        end
    endtask

    // burst read: every beat compared against model memory; rid/rresp/rlast
    // checked. bp=1 inserts random rready low cycles (backpressure).
    task automatic axi_rburst(
        input logic [ID_W-1:0]   id,
        input logic [ADDR_W-1:0] addr,
        input logic [7:0]        len,
        input logic [1:0]        burst,
        input bit                bp);
        logic [ADDR_W-1:0] a;
        begin
            // AR
            arid    <= id;
            araddr  <= addr;
            arlen   <= len;
            arsize  <= 3'd2;
            arburst <= burst;
            arvalid <= 1'b1;
            @(posedge clk);
            while (!arready) @(posedge clk);
            arvalid <= 1'b0;
            // R beats
            a = addr;
            for (int beat = 0; beat <= int'(len); beat++) begin
                if (bp) begin
                    rready <= 1'b0;
                    repeat ($urandom_range(0, 3)) @(posedge clk);
                end
                rready <= 1'b1;
                @(posedge clk);
                while (!rvalid) @(posedge clk);
                if (rdata !== model_mem[a[ADDR_W-1:2]]) begin
                    $display("ERROR: rdata beat %0d @%h got %h expected %h",
                             beat, a, rdata, model_mem[a[ADDR_W-1:2]]);
                    errors++;
                end
                if (rid !== id) begin
                    $display("ERROR: rid=%h expected %h", rid, id); errors++;
                end
                if (rresp !== 2'b00) begin
                    $display("ERROR: rresp=%b beat %0d @%h", rresp, beat, a); errors++;
                end
                if (rlast !== (beat == int'(len))) begin
                    $display("ERROR: rlast=%b on beat %0d of len %0d", rlast, beat, len);
                    errors++;
                end
                a = tb_next_addr(a, burst, 3'd2, len);
            end
            rready <= 1'b0;
        end
    endtask

    // ---- watchdog -------------------------------------------------------------
    initial begin
        #100us;
        $display("TB FAIL: watchdog timeout");
        $finish;
    end

    // ---- test sequence ----------------------------------------------------------
    initial begin
        awid = '0; awaddr = '0; awlen = '0; awsize = '0; awburst = '0; awvalid = 0;
        wdata = '0; wstrb = '1; wlast = 0; wvalid = 0; bready = 0;
        arid = '0; araddr = '0; arlen = '0; arsize = '0; arburst = '0; arvalid = 0;
        rready = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // 1. INCR len=0 (single beat)
        $display("-- 1: INCR len=0");
        axi_wburst(4'h1, 12'h000, 8'd0, B_INCR, '1, 0);
        axi_rburst(4'h1, 12'h000, 8'd0, B_INCR, 0);

        // 2. INCR len=7
        $display("-- 2: INCR len=7");
        axi_wburst(4'h2, 12'h100, 8'd7, B_INCR, '1, 0);
        axi_rburst(4'h2, 12'h100, 8'd7, B_INCR, 0);

        // 3. INCR len=15 (max tested burst)
        $display("-- 3: INCR len=15");
        axi_wburst(4'h3, 12'h200, 8'd15, B_INCR, '1, 0);
        axi_rburst(4'h3, 12'h200, 8'd15, B_INCR, 0);

        // 4. WRAP len=3, start mid-window: 0x308 in the 0x300..0x30F window.
        //    Beat order must be 0x308, 0x30C, 0x300, 0x304.
        $display("-- 4: WRAP len=3 from 0x308");
        axi_wburst(4'h4, 12'h308, 8'd3, B_WRAP, '1, 0);
        axi_rburst(4'h4, 12'h308, 8'd3, B_WRAP, 0);
        //    verify wrap order landed correctly: linear read of the window
        axi_rburst(4'h5, 12'h300, 8'd3, B_INCR, 0);

        // 5. FIXED len=3: same word written 4x (last wins), read back 4x
        $display("-- 5: FIXED len=3");
        axi_wburst(4'h6, 12'h040, 8'd3, B_FIXED, '1, 0);
        axi_rburst(4'h6, 12'h040, 8'd3, B_FIXED, 0);

        // 6. partial wstrb: only byte lanes 0 and 2 over known content
        $display("-- 6: wstrb partial");
        axi_wburst(4'h7, 12'h100, 8'd0, B_INCR, 4'b0101, 0);
        axi_rburst(4'h7, 12'h100, 8'd0, B_INCR, 0);

        // 7. random wvalid gaps + rready backpressure, INCR len=15
        $display("-- 7: gaps + backpressure INCR len=15");
        axi_wburst(4'h8, 12'h280, 8'd15, B_INCR, '1, 1);
        axi_rburst(4'h8, 12'h280, 8'd15, B_INCR, 1);

        // 8. WRAP with gaps + backpressure
        $display("-- 8: gaps + backpressure WRAP len=3");
        axi_wburst(4'h9, 12'h0F8, 8'd3, B_WRAP, '1, 1);
        axi_rburst(4'h9, 12'h0F8, 8'd3, B_WRAP, 1);

        // 9. write and read FSMs are independent: run both at once on
        //    disjoint regions (read re-checks region written in test 3).
        $display("-- 9: concurrent write + read");
        fork
            axi_wburst(4'hA, 12'h400, 8'd7, B_INCR, '1, 1);
            axi_rburst(4'hB, 12'h200, 8'd15, B_INCR, 1);
        join
        axi_rburst(4'hA, 12'h400, 8'd7, B_INCR, 0);

        if (errors == 0) $display("TB PASS");
        else             $display("TB FAIL: %0d errors", errors);
        $finish;
    end

endmodule
