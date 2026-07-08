// =============================================================================
// axi_lite_regs -- AXI4-Lite slave register block, plug-and-play template.
//
// HOW THIS TEMPLATE WORKS
//   - The AXI4-Lite protocol machinery is complete and correct. DO NOT EDIT it.
//   - You only touch the three fenced sections:
//       USER PORTS      : your signals to/from the outside world
//       USER REGISTERS  : add register storage + address decode rows
//       USER LOGIC      : your actual function (an A*B example is plugged in)
//   - clk / rst_n come from outside (tool-generated clock, no dividers here).
//   - Fully synthesizable. Sim-only code must sit inside `ifdef SIMULATION.
//
// REGISTER MAP (byte offsets, all 32-bit)
//   0x00  ID        RO  constant 0xCAFE0100 (read this first to prove access)
//   0x04  SCRATCH   RW  free read/write register, no side effects
//   0x08  CTRL      RW  bit0 = enable for the example user logic
//   0x0C  GPIO_OUT  RW  drives gpio_out port
//   0x10  GPIO_IN   RO  reflects gpio_in port
//   0x14  OPA       RW  example operand A
//   0x18  OPB       RW  example operand B
//   0x1C  RESULT    RO  example result = OPA * OPB (registered, when CTRL[0])
//   0x20  STATUS    RO  bit0 = done flag from example user logic
//   unmapped reads return 0xDEADBEEF, unmapped writes are ignored (resp OKAY)
// =============================================================================
module axi_lite_regs #(
    parameter int ADDR_W = 8,          // byte address width: 256B window = 64 regs
    parameter int DATA_W = 32          // AXI4-Lite supports 32 (default) or 64
)(
    input  logic                clk,
    input  logic                rst_n,

    // ---- AXI4-Lite slave interface (complete, do not edit) -----------------
    input  logic [ADDR_W-1:0]   s_axil_awaddr,
    input  logic                s_axil_awvalid,
    output logic                s_axil_awready,

    input  logic [DATA_W-1:0]   s_axil_wdata,
    input  logic [DATA_W/8-1:0] s_axil_wstrb,
    input  logic                s_axil_wvalid,
    output logic                s_axil_wready,

    output logic [1:0]          s_axil_bresp,
    output logic                s_axil_bvalid,
    input  logic                s_axil_bready,

    input  logic [ADDR_W-1:0]   s_axil_araddr,
    input  logic                s_axil_arvalid,
    output logic                s_axil_arready,

    output logic [DATA_W-1:0]   s_axil_rdata,
    output logic [1:0]          s_axil_rresp,
    output logic                s_axil_rvalid,
    input  logic                s_axil_rready,

    // ======================= USER PORTS START ===============================
    input  logic [DATA_W-1:0]   gpio_in,
    output logic [DATA_W-1:0]   gpio_out
    // ======================= USER PORTS END =================================
);

    // ---- register byte offsets ---------------------------------------------
    localparam logic [ADDR_W-1:0] A_ID       = 'h00;
    localparam logic [ADDR_W-1:0] A_SCRATCH  = 'h04;
    localparam logic [ADDR_W-1:0] A_CTRL     = 'h08;
    localparam logic [ADDR_W-1:0] A_GPIO_OUT = 'h0C;
    localparam logic [ADDR_W-1:0] A_GPIO_IN  = 'h10;
    localparam logic [ADDR_W-1:0] A_OPA      = 'h14;
    localparam logic [ADDR_W-1:0] A_OPB      = 'h18;
    localparam logic [ADDR_W-1:0] A_RESULT   = 'h1C;
    localparam logic [ADDR_W-1:0] A_STATUS   = 'h20;

    localparam logic [31:0] ID_VALUE = 32'hCAFE_0100;

    // ---- byte-strobe merge helper (do not edit) ----------------------------
    function automatic logic [DATA_W-1:0] apply_wstrb(
        input logic [DATA_W-1:0]   oldval,
        input logic [DATA_W-1:0]   newval,
        input logic [DATA_W/8-1:0] strb);
        for (int b = 0; b < DATA_W/8; b++)
            apply_wstrb[8*b +: 8] = strb[b] ? newval[8*b +: 8] : oldval[8*b +: 8];
    endfunction

    // =========================================================================
    // AXI4-Lite protocol engine (do not edit)
    // - AW and W are accepted independently (any arrival order, any skew)
    // - one write applies when both have arrived and B channel is free
    // - single outstanding read
    // =========================================================================
    logic [ADDR_W-1:0]   awaddr_q;
    logic                aw_pend;
    logic [DATA_W-1:0]   wdata_q;
    logic [DATA_W/8-1:0] wstrb_q;
    logic                w_pend;

    assign s_axil_awready = ~aw_pend;
    assign s_axil_wready  = ~w_pend;
    assign s_axil_bresp   = 2'b00;                       // always OKAY
    assign s_axil_rresp   = 2'b00;                       // always OKAY
    assign s_axil_arready = ~s_axil_rvalid;              // single outstanding

    wire wr_fire = aw_pend & w_pend & (~s_axil_bvalid | s_axil_bready);
    wire rd_fire = s_axil_arvalid & s_axil_arready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_pend       <= 1'b0;
            w_pend        <= 1'b0;
            awaddr_q      <= '0;
            wdata_q       <= '0;
            wstrb_q       <= '0;
            s_axil_bvalid <= 1'b0;
        end else begin
            if (s_axil_awvalid & s_axil_awready) begin
                awaddr_q <= s_axil_awaddr;
                aw_pend  <= 1'b1;
            end
            if (s_axil_wvalid & s_axil_wready) begin
                wdata_q <= s_axil_wdata;
                wstrb_q <= s_axil_wstrb;
                w_pend  <= 1'b1;
            end
            if (wr_fire) begin
                aw_pend       <= 1'b0;
                w_pend        <= 1'b0;
                s_axil_bvalid <= 1'b1;
            end else if (s_axil_bvalid & s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // USER REGISTERS START
    // To add a register: 1) declare storage  2) add a write row  3) add a read
    // row. Copy the SCRATCH pattern. RO registers need only a read row.
    // =========================================================================
    logic [DATA_W-1:0] scratch_q, ctrl_q, gpio_out_q, opa_q, opb_q;
    logic [DATA_W-1:0] result_q;   // driven in USER LOGIC below
    logic              done_q;     // driven in USER LOGIC below

    // write decode (fires once per AXI write, wstrb already honored)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scratch_q  <= '0;
            ctrl_q     <= '0;
            gpio_out_q <= '0;
            opa_q      <= '0;
            opb_q      <= '0;
        end else if (wr_fire) begin
            case (awaddr_q)
                A_SCRATCH  : scratch_q  <= apply_wstrb(scratch_q,  wdata_q, wstrb_q);
                A_CTRL     : ctrl_q     <= apply_wstrb(ctrl_q,     wdata_q, wstrb_q);
                A_GPIO_OUT : gpio_out_q <= apply_wstrb(gpio_out_q, wdata_q, wstrb_q);
                A_OPA      : opa_q      <= apply_wstrb(opa_q,      wdata_q, wstrb_q);
                A_OPB      : opb_q      <= apply_wstrb(opb_q,      wdata_q, wstrb_q);
                default    : ;                           // unmapped: ignore
            endcase
        end
    end

    // read decode (combinational mux, registered into rdata on AR handshake)
    logic [DATA_W-1:0] rd_mux;
    always_comb begin
        case (s_axil_araddr)
            A_ID       : rd_mux = DATA_W'(ID_VALUE);
            A_SCRATCH  : rd_mux = scratch_q;
            A_CTRL     : rd_mux = ctrl_q;
            A_GPIO_OUT : rd_mux = gpio_out_q;
            A_GPIO_IN  : rd_mux = gpio_in;
            A_OPA      : rd_mux = opa_q;
            A_OPB      : rd_mux = opb_q;
            A_RESULT   : rd_mux = result_q;
            A_STATUS   : rd_mux = DATA_W'({done_q});
            default    : rd_mux = DATA_W'(32'hDEAD_BEEF); // unmapped
        endcase
    end
    // USER REGISTERS END =====================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_rvalid <= 1'b0;
            s_axil_rdata  <= '0;
        end else if (rd_fire) begin
            s_axil_rdata  <= rd_mux;
            s_axil_rvalid <= 1'b1;
        end else if (s_axil_rvalid & s_axil_rready) begin
            s_axil_rvalid <= 1'b0;
        end
    end

    assign gpio_out = gpio_out_q;

    // =========================================================================
    // USER LOGIC START -- replace this example with your function.
    // Example: registered multiply OPA*OPB while CTRL[0] is set; done flag.
    // (result_q / done_q are declared up in USER REGISTERS -- declare your
    //  outputs there too, xvlog requires declaration before first use.)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_q <= '0;
            done_q   <= 1'b0;
        end else if (ctrl_q[0]) begin
            result_q <= opa_q * opb_q;                   // truncated to DATA_W
            done_q   <= 1'b1;
        end
    end
    // USER LOGIC END =========================================================

`ifdef EMU_FINISH
    // Emulation/prototyping bring-up aid: Protium tolerates $display/$finish
    // as untimed system tasks. Keep them in this fenced block, never inside
    // datapath always blocks. Compile with -d EMU_FINISH to activate.
    always @(posedge clk)
        if (done_q) begin
            $display("axi_lite_regs: done, result=%h", result_q);
            $finish;
        end
`endif

endmodule
