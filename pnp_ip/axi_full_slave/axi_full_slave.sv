// =============================================================================
// axi_full_slave -- AXI4 (full) memory slave, plug-and-play template.
//
// HOW THIS TEMPLATE WORKS
//   - The AXI4 burst protocol machinery is complete and correct. DO NOT EDIT it.
//   - You only touch the one fenced section:
//       USER MEMORY : swap the internal BRAM for your own memory / register file.
//   - clk / rst_n come from outside (tool-generated clock, no dividers here).
//   - Fully synthesizable. Sim-only code sits inside `ifdef SIMULATION.
//
// BEHAVIOR
//   - Memory slave: 2^(ADDR_W-2) words of DATA_W bits (DATA_W=32 default),
//     BRAM-inferable (no reset on the array, 1-cycle registered read).
//   - Bursts: FIXED (2'b00), INCR (2'b01), WRAP (2'b10). Reserved 2'b11 is
//     treated as INCR. WRAP base = addr & ~(total_bytes-1), stepped per beat.
//   - Single outstanding transaction per direction; the write and read FSMs
//     are independent and run concurrently.
//   - awlock/awcache/awprot and arlock/arcache/arprot are accepted and
//     ignored (plain memory: no exclusive access, no cache/protection use).
//   - Responses are always OKAY. Reads take 2 cycles/beat (MEM then DATA).
// =============================================================================
module axi_full_slave #(
    parameter int ID_W   = 4,          // AXI ID width
    parameter int ADDR_W = 12,         // byte address width: 4KB window
    parameter int DATA_W = 32          // data bus width (bytes = DATA_W/8)
)(
    input  logic                clk,
    input  logic                rst_n,   // async active-low

    // ---- AXI4 slave: write address channel (complete, do not edit) ---------
    input  logic [ID_W-1:0]     s_axi_awid,
    input  logic [ADDR_W-1:0]   s_axi_awaddr,
    input  logic [7:0]          s_axi_awlen,
    input  logic [2:0]          s_axi_awsize,
    input  logic [1:0]          s_axi_awburst,
    input  logic                s_axi_awlock,   // accepted, ignored
    input  logic [3:0]          s_axi_awcache,  // accepted, ignored
    input  logic [2:0]          s_axi_awprot,   // accepted, ignored
    input  logic                s_axi_awvalid,
    output logic                s_axi_awready,

    // ---- write data channel -------------------------------------------------
    input  logic [DATA_W-1:0]   s_axi_wdata,
    input  logic [DATA_W/8-1:0] s_axi_wstrb,
    input  logic                s_axi_wlast,
    input  logic                s_axi_wvalid,
    output logic                s_axi_wready,

    // ---- write response channel ---------------------------------------------
    output logic [ID_W-1:0]     s_axi_bid,
    output logic [1:0]          s_axi_bresp,
    output logic                s_axi_bvalid,
    input  logic                s_axi_bready,

    // ---- read address channel -----------------------------------------------
    input  logic [ID_W-1:0]     s_axi_arid,
    input  logic [ADDR_W-1:0]   s_axi_araddr,
    input  logic [7:0]          s_axi_arlen,
    input  logic [2:0]          s_axi_arsize,
    input  logic [1:0]          s_axi_arburst,
    input  logic                s_axi_arlock,   // accepted, ignored
    input  logic [3:0]          s_axi_arcache,  // accepted, ignored
    input  logic [2:0]          s_axi_arprot,   // accepted, ignored
    input  logic                s_axi_arvalid,
    output logic                s_axi_arready,

    // ---- read data channel --------------------------------------------------
    output logic [ID_W-1:0]     s_axi_rid,
    output logic [DATA_W-1:0]   s_axi_rdata,
    output logic [1:0]          s_axi_rresp,
    output logic                s_axi_rlast,
    output logic                s_axi_rvalid,
    input  logic                s_axi_rready
);

    localparam int BYTES = DATA_W/8;           // bytes per full-width beat
    localparam int LSB   = $clog2(BYTES);      // byte-offset bits (2 for 32b)
    localparam int WORDS = 2**(ADDR_W-LSB);    // memory depth in words

    // ---- burst next-address (do not edit) -----------------------------------
    // FIXED: hold. INCR: +bytes/beat. WRAP: wrap inside a total_bytes-aligned
    // window; base = addr & ~(total_bytes-1). All math in int intermediates,
    // stepped once per beat (base is invariant across a legal WRAP burst).
    function automatic logic [ADDR_W-1:0] next_addr(
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
                2'b00: next_addr = cur;                        // FIXED
                2'b10: begin                                   // WRAP
                    base = int'(cur) & ~(total_bytes - 1);
                    if (nxt >= base + total_bytes) nxt = base;
                    next_addr = ADDR_W'(nxt);
                end
                default: next_addr = ADDR_W'(nxt);             // INCR + reserved
            endcase
        end
    endfunction

    // =========================================================================
    // Write FSM (do not edit): IDLE -> DATA -> RESP
    //   IDLE: awready; latch the AW command.
    //   DATA: wready; each accepted beat writes memory (wstrb per byte lane)
    //         and steps the address; wlast moves to RESP.
    //   RESP: bvalid with latched awid, resp OKAY.
    // =========================================================================
    typedef enum logic [1:0] {W_IDLE, W_DATA, W_RESP} wstate_e;
    wstate_e             wstate;
    logic [ID_W-1:0]     awid_q;
    logic [ADDR_W-1:0]   waddr_q;
    logic [7:0]          wlen_q;
    logic [2:0]          wsize_q;
    logic [1:0]          wburst_q;

    assign s_axi_awready = (wstate == W_IDLE);
    assign s_axi_wready  = (wstate == W_DATA);
    assign s_axi_bvalid  = (wstate == W_RESP);
    assign s_axi_bid     = awid_q;
    assign s_axi_bresp   = 2'b00;                              // always OKAY

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wstate   <= W_IDLE;
            awid_q   <= '0;
            waddr_q  <= '0;
            wlen_q   <= '0;
            wsize_q  <= '0;
            wburst_q <= 2'b01;
        end else begin
            case (wstate)
                W_IDLE: if (s_axi_awvalid) begin
                    awid_q   <= s_axi_awid;
                    waddr_q  <= s_axi_awaddr;
                    wlen_q   <= s_axi_awlen;
                    wsize_q  <= s_axi_awsize;
                    wburst_q <= s_axi_awburst;
                    wstate   <= W_DATA;
                end
                W_DATA: if (s_axi_wvalid) begin
                    waddr_q <= next_addr(waddr_q, wburst_q, wsize_q, wlen_q);
                    if (s_axi_wlast) wstate <= W_RESP;
                end
                W_RESP: if (s_axi_bready) wstate <= W_IDLE;
                default: wstate <= W_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Read FSM (do not edit): IDLE -> MEM -> DATA (-> MEM per beat)
    //   IDLE: arready; latch the AR command, beat counter = 0.
    //   MEM : 1 cycle for the registered BRAM read into rdata_q.
    //   DATA: rvalid; rlast on the final beat; on handshake step address and
    //         return to MEM for the next beat. Throughput: 2 cycles/beat.
    // =========================================================================
    typedef enum logic [1:0] {R_IDLE, R_MEM, R_DATA} rstate_e;
    rstate_e             rstate;
    logic [ID_W-1:0]     arid_q;
    logic [ADDR_W-1:0]   raddr_q;
    logic [7:0]          rlen_q;
    logic [7:0]          rbeat_q;
    logic [2:0]          rsize_q;
    logic [1:0]          rburst_q;
    logic [DATA_W-1:0]   rdata_q;      // driven in USER MEMORY below

    assign s_axi_arready = (rstate == R_IDLE);
    assign s_axi_rvalid  = (rstate == R_DATA);
    assign s_axi_rid     = arid_q;
    assign s_axi_rresp   = 2'b00;                              // always OKAY
    assign s_axi_rlast   = (rbeat_q == rlen_q);
    assign s_axi_rdata   = rdata_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rstate   <= R_IDLE;
            arid_q   <= '0;
            raddr_q  <= '0;
            rlen_q   <= '0;
            rbeat_q  <= '0;
            rsize_q  <= '0;
            rburst_q <= 2'b01;
        end else begin
            case (rstate)
                R_IDLE: if (s_axi_arvalid) begin
                    arid_q   <= s_axi_arid;
                    raddr_q  <= s_axi_araddr;
                    rlen_q   <= s_axi_arlen;
                    rsize_q  <= s_axi_arsize;
                    rburst_q <= s_axi_arburst;
                    rbeat_q  <= '0;
                    rstate   <= R_MEM;
                end
                R_MEM: rstate <= R_DATA;   // rdata_q loads at this edge
                R_DATA: if (s_axi_rready) begin
                    if (rbeat_q == rlen_q) rstate <= R_IDLE;
                    else begin
                        raddr_q <= next_addr(raddr_q, rburst_q, rsize_q, rlen_q);
                        rbeat_q <= rbeat_q + 8'd1;
                        rstate  <= R_MEM;
                    end
                end
                default: rstate <= R_IDLE;
            endcase
        end
    end

    // ---- memory port signals (do not edit) ----------------------------------
    // This is the contract between the protocol engines and the USER MEMORY:
    //   mem_we high  : absorb s_axi_wdata under s_axi_wstrb at word w_word.
    //   mem_re high  : present word r_word on rdata_q by the next clock edge.
    logic                  mem_we;
    logic                  mem_re;
    logic [ADDR_W-LSB-1:0] w_word;
    logic [ADDR_W-LSB-1:0] r_word;

    assign mem_we = (wstate == W_DATA) && s_axi_wvalid;
    assign mem_re = (rstate == R_MEM);
    assign w_word = waddr_q[ADDR_W-1:LSB];
    assign r_word = raddr_q[ADDR_W-1:LSB];

    // =========================================================================
    // USER MEMORY START
    // Default backing store: simple-dual-port BRAM, byte write enables,
    // registered read (this is what makes it BRAM-inferable: no reset on the
    // array or on rdata_q, one clocked read).
    // TO SWAP IN YOUR OWN memory or register file: delete the mem array and
    // this always_ff, then honor the contract above (mem_we/w_word writes,
    // mem_re/r_word -> rdata_q one cycle later). Keep rdata_q registered.
    // =========================================================================
    logic [DATA_W-1:0] mem [0:WORDS-1];

    always_ff @(posedge clk) begin
        if (mem_we) begin
            for (int b = 0; b < BYTES; b++)
                if (s_axi_wstrb[b]) mem[w_word][8*b +: 8] <= s_axi_wdata[8*b +: 8];
        end
        if (mem_re)
            rdata_q <= mem[r_word];
    end
    // USER MEMORY END =========================================================

`ifdef SIMULATION
    // Sim-only protocol lint (runner defines SIMULATION; never synthesized).
    always @(posedge clk)
        if (rst_n) begin
            if (s_axi_awvalid && s_axi_awready && s_axi_awburst == 2'b11)
                $display("WARN axi_full_slave: reserved awburst 2'b11 treated as INCR");
            if (s_axi_arvalid && s_axi_arready && s_axi_arburst == 2'b11)
                $display("WARN axi_full_slave: reserved arburst 2'b11 treated as INCR");
        end
`endif

`ifdef EMU_FINISH
    // Emulation/prototyping bring-up aid: Protium tolerates $display/$finish
    // as untimed system tasks. Keep them in this fenced block, never inside
    // datapath always blocks. Compile with -d EMU_FINISH to activate.
    always @(posedge clk)
        if (s_axi_rvalid && s_axi_rready && s_axi_rlast) begin
            $display("axi_full_slave: first read burst complete");
            $finish;
        end
`endif

endmodule
