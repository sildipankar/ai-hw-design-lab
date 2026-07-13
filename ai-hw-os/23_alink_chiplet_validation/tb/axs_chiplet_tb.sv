// axs_chiplet_tb — integration smoke: REAL axs_regs/axs_mem/axs_chiplet RTL with
// TB-only behavioral axs_dec/axs_bank/sram_bank (blackbox stand-ins); TB is the
// master chiplet via the master BFM. Routing to both targets, W-before-AW through
// the decoder, SLVERR path, registered dbg probes, reset-during-traffic, soak.
// Single PASS/FAIL banner.
`timescale 1ns/1ps
module axs_chiplet_tb;

  logic        clk = 0, rst;
  logic        s_axil_awvalid, s_axil_awready;
  logic [15:0] s_axil_awaddr;
  logic        s_axil_wvalid, s_axil_wready;
  logic [31:0] s_axil_wdata;
  logic [3:0]  s_axil_wstrb;
  logic        s_axil_bvalid, s_axil_bready;
  logic [1:0]  s_axil_bresp;
  logic        s_axil_arvalid, s_axil_arready;
  logic [15:0] s_axil_araddr;
  logic        s_axil_rvalid, s_axil_rready;
  logic [31:0] s_axil_rdata;
  logic [1:0]  s_axil_rresp;
  logic [1:0]  dbg_sel;
  logic [31:0] dbg_scratch0;
  logic [15:0] dbg_wrcnt, dbg_mem_wr_cnt;

  int unsigned errors = 0;

  axs_chiplet dut (.*);
  bind axs_chiplet axs_chiplet_sva u_sva (.*);

  always #5 clk = ~clk;

  `include "axil_master_bfm.svh"

  // golden model across BOTH targets
  logic [31:0] g_s0 = '0, g_s1 = '0;
  logic [31:0] g_mem [logic [15:0]];
  int unsigned g_wrcnt = 0, g_memwr = 0;

  task automatic gwrite(input logic [15:0] a, input logic [31:0] d,
                        input int awl, input int wl, input string tag);
    logic [1:0] resp, eresp;
    if (a[15]) begin
      eresp = 2'b00;
    end else begin
      eresp = ((a[7:0] == 8'h04) || (a[7:0] == 8'h08)) ? 2'b00 : 2'b10;
    end
    @(negedge clk);
    axi_write(a, d, awl, wl, $urandom_range(2), resp);
    if (a[15]) begin
      g_mem[{a[15], 3'h0, a[11:2], 2'b00}] = d;
      g_memwr++;
    end else if (eresp == 2'b00) begin
      if (a[7:0] == 8'h04) g_s0 = d; else g_s1 = d;
      g_wrcnt++;
    end
    if (resp !== eresp) begin
      $error("[%s] write %h: bresp=%b expected=%b", tag, a, resp, eresp); errors++;
    end
  endtask

  task automatic gread(input logic [15:0] a, input string tag);
    logic [31:0] data, exp;
    logic [1:0]  resp, eresp;
    if (a[15]) begin
      exp = g_mem[{a[15], 3'h0, a[11:2], 2'b00}]; eresp = 2'b00;
    end else begin
      case (a[7:0])
        8'h00:   begin exp = 32'hA11C_0001;          eresp = 2'b00; end
        8'h04:   begin exp = g_s0;                   eresp = 2'b00; end
        8'h08:   begin exp = g_s1;                   eresp = 2'b00; end
        8'h0C:   begin exp = {16'h0, 16'(g_wrcnt)};  eresp = 2'b00; end
        default: begin exp = 32'hDEAD_BEEF;          eresp = 2'b10; end
      endcase
    end
    @(negedge clk);
    axi_read(a, $urandom_range(2), data, resp);
    if (data !== exp || resp !== eresp) begin
      $error("[%s] read %h: data=%h/%h resp=%b/%b", tag, a, data, exp, resp, eresp);
      errors++;
    end
  endtask

  task automatic check_probes(string tag);
    repeat (2) @(posedge clk);   // boundary registers settle
    #1;
    if (dbg_scratch0 !== g_s0 || dbg_wrcnt !== 16'(g_wrcnt) ||
        dbg_mem_wr_cnt !== 16'(g_memwr)) begin
      $error("[%s] probes: s0=%h/%h wrcnt=%0d/%0d memwr=%0d/%0d", tag,
             dbg_scratch0, g_s0, dbg_wrcnt, g_wrcnt, dbg_mem_wr_cnt, g_memwr);
      errors++;
    end
  endtask

  initial begin
    rst = 1;
    s_axil_awvalid = 0; s_axil_awaddr = '0;
    s_axil_wvalid = 0;  s_axil_wdata = '0; s_axil_wstrb = '0;
    s_axil_bready = 0;
    s_axil_arvalid = 0; s_axil_araddr = '0;
    s_axil_rready = 0;
    repeat (3) @(posedge clk);
    rst = 0;
    repeat (2) @(posedge clk);

    // t_route_regs: write scratch0 through dec target 0, read back
    gwrite(16'h0004, 32'h0000_0011, 0, 2, "t_route_regs");
    gread (16'h0004, "t_route_regs_rd");

    // t_route_mem: W-before-AW through the decoder into the memory slave (fix a
    // must survive the routing layer: W stalls at the dec until AW locks it)
    gwrite(16'h8010, 32'h0000_CAFE, 3, 0, "t_route_mem_wfirst");
    gread (16'h8010, "t_route_mem_rd");

    // t_directed: ID read, WRCNT read, unmapped SLVERR both ways
    gread (16'h0000, "t_read_id");
    gread (16'h000C, "t_read_wrcnt");
    gwrite(16'h0030, 32'h0BAD_0BAD, 0, 0, "t_unmapped_wr");
    gread (16'h0040, "t_unmapped_rd");

    // t_probes: registered debug outputs match golden
    check_probes("t_probes");

    // t_reset_during_traffic: AW parked at the dec, reset, clean ops after
    @(negedge clk);
    s_axil_awvalid = 1; s_axil_awaddr = 16'h8000;
    repeat (2) @(negedge clk);
    rst = 1;
    s_axil_awvalid = 0;
    repeat (2) @(posedge clk);
    @(negedge clk) rst = 0;
    g_s0 = '0; g_s1 = '0; g_wrcnt = 0; g_memwr = 0;  // register state cleared
    repeat (2) @(posedge clk);
    gwrite(16'h0004, 32'h2222_3333, 0, 0, "t_reset_during_traffic");
    gread (16'h0004, "t_reset_during_traffic_rd");

    // t_soak: 30 random ops alternating targets, random AW/W order
    begin
      logic [15:0] mem_pool [8];
      for (int i = 0; i < 8; i++) begin
        mem_pool[i] = 16'h8100 + 16'(4 * i);
        gwrite(mem_pool[i], $urandom, $urandom_range(3), $urandom_range(3), "t_soak_init");
      end
      repeat (30) begin
        if ($urandom_range(1)) begin       // memory target
          automatic int k = $urandom_range(7);
          if ($urandom_range(1)) gwrite(mem_pool[k], $urandom, $urandom_range(3),
                                        $urandom_range(3), "t_soak_mem_wr");
          else                   gread(mem_pool[k], "t_soak_mem_rd");
        end else begin                     // regs target
          automatic logic [15:0] a = ($urandom_range(1)) ? 16'h0004 : 16'h0008;
          if ($urandom_range(1)) gwrite(a, $urandom, $urandom_range(3),
                                        $urandom_range(3), "t_soak_reg_wr");
          else                   gread(a, "t_soak_reg_rd");
        end
      end
      check_probes("t_soak_probes");
    end

    if (errors == 0) $display("*** PASS: axs_chiplet_tb, 0 errors ***");
    else             $display("*** FAIL: axs_chiplet_tb, %0d errors ***", errors);
    $finish;
  end

endmodule // END axs_chiplet_tb
