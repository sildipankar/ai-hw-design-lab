// =============================================================================
// tb_axi_lite_regs -- self-checking TB for the AXI4-Lite register template.
// Sim only. Run: powershell -File scripts\run_sim.ps1 axi_lite_regs
// Prints "TB PASS" and $finishes on success, "TB FAIL" otherwise.
// =============================================================================
`timescale 1ns/1ps
module tb_axi_lite_regs;

    localparam int ADDR_W = 8;
    localparam int DATA_W = 32;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;                                // 100 MHz

    logic [ADDR_W-1:0]   awaddr;  logic awvalid; logic awready;
    logic [DATA_W-1:0]   wdata;   logic [DATA_W/8-1:0] wstrb;
    logic wvalid, wready;
    logic [1:0] bresp;   logic bvalid, bready;
    logic [ADDR_W-1:0]   araddr;  logic arvalid; logic arready;
    logic [DATA_W-1:0]   rdata;   logic [1:0] rresp;
    logic rvalid, rready;
    logic [DATA_W-1:0]   gpio_in, gpio_out;

    int errors = 0;

    axi_lite_regs #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) dut (
        .clk, .rst_n,
        .s_axil_awaddr(awaddr), .s_axil_awvalid(awvalid), .s_axil_awready(awready),
        .s_axil_wdata(wdata), .s_axil_wstrb(wstrb), .s_axil_wvalid(wvalid), .s_axil_wready(wready),
        .s_axil_bresp(bresp), .s_axil_bvalid(bvalid), .s_axil_bready(bready),
        .s_axil_araddr(araddr), .s_axil_arvalid(arvalid), .s_axil_arready(arready),
        .s_axil_rdata(rdata), .s_axil_rresp(rresp), .s_axil_rvalid(rvalid), .s_axil_rready(rready),
        .gpio_in, .gpio_out
    );

    // ---- AXI-Lite master tasks ---------------------------------------------
    // aw_delay / w_delay skew the two channels to prove order independence.
    task automatic axil_write(input logic [ADDR_W-1:0] addr,
                              input logic [DATA_W-1:0] data,
                              input logic [DATA_W/8-1:0] strb = '1,
                              input int aw_delay = 0,
                              input int w_delay  = 0);
        fork
            begin
                repeat (aw_delay) @(posedge clk);
                awaddr  <= addr;
                awvalid <= 1'b1;
                @(posedge clk);
                while (!awready) @(posedge clk);
                awvalid <= 1'b0;
            end
            begin
                repeat (w_delay) @(posedge clk);
                wdata  <= data;
                wstrb  <= strb;
                wvalid <= 1'b1;
                @(posedge clk);
                while (!wready) @(posedge clk);
                wvalid <= 1'b0;
            end
        join
        bready <= 1'b1;
        @(posedge clk);
        while (!bvalid) @(posedge clk);
        if (bresp != 2'b00) begin
            $display("ERROR: bresp=%b for write addr %h", bresp, addr);
            errors++;
        end
        bready <= 1'b0;
    endtask

    task automatic axil_read(input  logic [ADDR_W-1:0] addr,
                             output logic [DATA_W-1:0] data);
        araddr  <= addr;
        arvalid <= 1'b1;
        @(posedge clk);
        while (!arready) @(posedge clk);
        arvalid <= 1'b0;
        rready  <= 1'b1;
        @(posedge clk);
        while (!rvalid) @(posedge clk);
        data = rdata;
        if (rresp != 2'b00) begin
            $display("ERROR: rresp=%b for read addr %h", rresp, addr);
            errors++;
        end
        rready <= 1'b0;
    endtask

    task automatic check_read(input logic [ADDR_W-1:0] addr,
                              input logic [DATA_W-1:0] expected,
                              input string name);
        logic [DATA_W-1:0] got;
        axil_read(addr, got);
        if (got !== expected) begin
            $display("ERROR: %s @%h  got %h  expected %h", name, addr, got, expected);
            errors++;
        end else begin
            $display("  ok: %s = %h", name, got);
        end
    endtask

    // ---- watchdog ----------------------------------------------------------
    initial begin
        #100us;
        $display("TB FAIL: watchdog timeout");
        $finish;
    end

    // ---- test sequence -----------------------------------------------------
    initial begin
        awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
        awaddr = '0; wdata = '0; wstrb = '1; araddr = '0;
        gpio_in = 32'h5A5A_00FF;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // 1. ID register
        check_read('h00, 32'hCAFE_0100, "ID");

        // 2. scratch RW
        axil_write('h04, 32'h1234_5678);
        check_read('h04, 32'h1234_5678, "SCRATCH");

        // 3. byte strobes: overwrite only byte1 of scratch
        axil_write('h04, 32'hFFAB_FFFF, 4'b0100);
        check_read('h04, 32'h12AB_5678, "SCRATCH wstrb");

        // 4. AW/W skew tolerance: W arrives 3 cycles before AW, then reverse
        axil_write('h04, 32'hA0A0_A0A0, '1, 3, 0);      // AW late
        check_read('h04, 32'hA0A0_A0A0, "SCRATCH w-first");
        axil_write('h04, 32'h0B0B_0B0B, '1, 0, 3);      // W late
        check_read('h04, 32'h0B0B_0B0B, "SCRATCH aw-first");

        // 5. GPIO out + in
        axil_write('h0C, 32'hF00D_BEEF);
        if (gpio_out !== 32'hF00D_BEEF) begin
            $display("ERROR: gpio_out=%h", gpio_out); errors++;
        end
        check_read('h10, 32'h5A5A_00FF, "GPIO_IN");

        // 6. example user logic: RESULT = OPA*OPB when CTRL[0]
        axil_write('h14, 32'd7);
        axil_write('h18, 32'd6);
        axil_write('h08, 32'h1);                         // CTRL.enable
        repeat (3) @(posedge clk);
        check_read('h1C, 32'd42, "RESULT");
        check_read('h20, 32'h1,  "STATUS.done");

        // 7. unmapped address
        check_read('hF0, 32'hDEAD_BEEF, "unmapped");

        if (errors == 0) $display("TB PASS");
        else             $display("TB FAIL: %0d errors", errors);
        $finish;
    end

endmodule
