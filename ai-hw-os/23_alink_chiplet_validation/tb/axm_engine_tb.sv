// axm_engine_tb — self-checking: reactive slave BFM + golden memory mirror.
// Named tests: delayed/reordered readys (independent AW/W retirement), error
// responses, TIMEOUT (tmo_sticky at 0xFFF), backpressure, reset-during-traffic,
// random soak. Single PASS/FAIL banner.
`timescale 1ns/1ps
module axm_engine_tb;

  logic        clk = 0, rst;
  logic        cmd_valid, cmd_ready, cmd_write;
  logic [15:0] cmd_addr;
  logic [31:0] cmd_wdata;
  logic        rsp_valid, rsp_err;
  logic [31:0] rsp_rdata;
  logic        m_axil_awvalid, m_axil_awready;
  logic [15:0] m_axil_awaddr;
  logic        m_axil_wvalid, m_axil_wready;
  logic [31:0] m_axil_wdata;
  logic [3:0]  m_axil_wstrb;
  logic        m_axil_bvalid, m_axil_bready;
  logic [1:0]  m_axil_bresp;
  logic        m_axil_arvalid, m_axil_arready;
  logic [15:0] m_axil_araddr;
  logic        m_axil_rvalid, m_axil_rready;
  logic [31:0] m_axil_rdata;
  logic [1:0]  m_axil_rresp;
  logic        tmo_sticky;
  logic [2:0]  state_dbg;

  int unsigned errors = 0;

  axm_engine dut (.*);
  bind axm_engine axm_engine_sva u_sva (.*);

  always #5 clk = ~clk;

  // reactive AXI4-Lite slave with dictionary memory + delay/corrupt/mute knobs
  `include "axil_slave_bfm.svh"

  // golden mirror of what the slave memory must contain
  logic [31:0] g_mem [logic [15:0]];

  task automatic issue_cmd(input bit wr, input logic [15:0] a, input logic [31:0] d);
    @(negedge clk);
    cmd_valid = 1'b1;
    cmd_write = wr;
    cmd_addr  = a;
    cmd_wdata = d;
    forever begin
      #1;
      if (cmd_ready === 1'b1) break;
      @(negedge clk);
    end
    @(posedge clk);
    @(negedge clk);
    cmd_valid = 1'b0;
  endtask

  task automatic wait_rsp(input bit exp_err, input logic [31:0] exp_data,
                          input bit chk_data, input string tag);
    int guard = 0;
    forever begin
      @(posedge clk);
      #1;
      if (rsp_valid === 1'b1) break;
      guard++;
      if (guard > 8000) begin
        $error("[%s] no rsp_valid within 8000 clks (engine hang)", tag);
        errors++;
        return;
      end
    end
    if (rsp_err !== exp_err) begin
      $error("[%s] rsp_err=%b expected=%b @%0t", tag, rsp_err, exp_err, $time);
      errors++;
    end
    if (chk_data && (rsp_rdata !== exp_data)) begin
      $error("[%s] rsp_rdata=%h expected=%h @%0t", tag, rsp_rdata, exp_data, $time);
      errors++;
    end
  endtask

  task automatic wr_and_check(input logic [15:0] a, input logic [31:0] d, string tag);
    issue_cmd(1, a, d);
    wait_rsp(0, '0, 0, tag);
    g_mem[a] = d;
    if (bfm_mem[a] !== d) begin
      $error("[%s] slave stored %h expected %h", tag, bfm_mem[a], d);
      errors++;
    end
  endtask

  task automatic rd_and_check(input logic [15:0] a, string tag);
    logic [31:0] exp = g_mem.exists(a) ? g_mem[a] : 32'hDEAD_BEEF;
    issue_cmd(0, a, '0);
    wait_rsp(0, exp, 1, tag);
  endtask

  initial begin
    // t_reset
    rst = 1; cmd_valid = 0; cmd_write = 0; cmd_addr = '0; cmd_wdata = '0;
    repeat (3) @(posedge clk);
    rst = 0;
    #1;
    if (cmd_ready !== 1'b1 || m_axil_awvalid !== 1'b0 || m_axil_arvalid !== 1'b0) begin
      $error("[t_reset] bad idle state after reset"); errors++;
    end

    // t_write_basic: everything ready immediately
    wr_and_check(16'h8004, 32'h0000_0055, "t_write_basic");

    // t_write_aw_late: awready 3 clks late -> W channel retires FIRST (independence)
    bfm_awready_dly = 3; bfm_wready_dly = 0;
    wr_and_check(16'h8008, 32'h1111_2222, "t_write_aw_late");

    // t_write_w_late: wready 3 clks late -> AW channel retires first
    bfm_awready_dly = 0; bfm_wready_dly = 3;
    wr_and_check(16'h800C, 32'h3333_4444, "t_write_w_late");

    // t_write_b_backpressure: B response delayed 5 clks
    bfm_awready_dly = 0; bfm_wready_dly = 0; bfm_b_dly = 5;
    wr_and_check(16'h8010, 32'h5555_6666, "t_write_b_backpressure");
    bfm_b_dly = 0;

    // t_read_basic
    rd_and_check(16'h8004, "t_read_basic");

    // t_read_delayed: arready 2 late, R data 4 late
    bfm_ar_dly = 2; bfm_r_dly = 4;
    rd_and_check(16'h8008, "t_read_delayed");
    bfm_ar_dly = 0; bfm_r_dly = 0;

    // t_resp_slverr: slave returns SLVERR on both directions -> rsp_err
    bfm_bresp_force = 2'b10;
    issue_cmd(1, 16'h8020, 32'h7777_8888);
    wait_rsp(1, '0, 0, "t_resp_slverr_wr");
    bfm_bresp_force = 2'b00;
    bfm_rresp_force = 2'b10;
    issue_cmd(0, 16'h8020, '0);
    wait_rsp(1, '0, 0, "t_resp_slverr_rd");
    bfm_rresp_force = 2'b00;

    // t_timeout: slave never asserts readys -> abort at 0xFFF, tmo_sticky latches
    bfm_accept = 0;
    issue_cmd(1, 16'h8030, 32'h9999_AAAA);
    wait_rsp(1, '0, 0, "t_timeout");
    #1;
    if (tmo_sticky !== 1'b1) begin
      $error("[t_timeout] tmo_sticky not latched after timeout"); errors++;
    end
    if (m_axil_awvalid !== 1'b0 || m_axil_wvalid !== 1'b0) begin
      $error("[t_timeout] valids not dropped after timeout abort"); errors++;
    end
    bfm_accept = 1;

    // t_reset_during_traffic: engine mid-transaction (slave mute), reset, clean rerun
    bfm_accept = 0;
    issue_cmd(1, 16'h8040, 32'hBBBB_CCCC);
    repeat (10) @(posedge clk);          // engine parked in WR_REQ
    @(negedge clk) rst = 1;
    repeat (2) @(posedge clk);
    @(negedge clk) rst = 0;
    bfm_accept = 1;
    #1;
    if (tmo_sticky !== 1'b0) begin
      $error("[t_reset_during_traffic] tmo_sticky survived rst"); errors++;
    end
    wr_and_check(16'h8040, 32'hDDDD_EEEE, "t_reset_during_traffic");

    // t_soak: 20 random transactions with random slave delays
    repeat (20) begin
      automatic bit          wr = $urandom_range(1);
      automatic logic [15:0] a  = 16'h8000 + 16'(4 * $urandom_range(15));
      automatic logic [31:0] d  = $urandom;
      bfm_awready_dly = $urandom_range(3);
      bfm_wready_dly  = $urandom_range(3);
      bfm_b_dly       = $urandom_range(3);
      bfm_ar_dly      = $urandom_range(3);
      bfm_r_dly       = $urandom_range(3);
      if (wr) wr_and_check(a, d, "t_soak_wr");
      else    rd_and_check(a, "t_soak_rd");
    end

    if (errors == 0) $display("*** PASS: axm_engine_tb, 0 errors ***");
    else             $display("*** FAIL: axm_engine_tb, %0d errors ***", errors);
    $finish;
  end

endmodule // END axm_engine_tb
