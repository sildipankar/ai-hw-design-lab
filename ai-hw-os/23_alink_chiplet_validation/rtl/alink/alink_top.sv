// alink_top — DESIGN TOP: supervisor FSM + AXM chiplet + AXS chiplet.
// Spec: 11_alink_axi.md AL-11 (27B-routed -> frontier-owned integration).
//
// MANDATORY REVIEW FIX (b) APPLIED (15_bin_link_contract.md §4, ALINK row):
// the chiplet-to-chiplet AXI bus is NOT wired directly (AL-11's original wording);
// it crosses the cut through a MASTER-SIDE + SLAVE-SIDE axil_reg_slice pair, each
// channel an independent lane with its own state. u_slice_m belongs to bin A
// (master side of the cut), u_slice_s to bin B (slave side).
//
// AXION profile: clk is a tool clock (IXCOM clock spec); arst_n conditioned by
// reset_sync into the sync active-high rst used everywhere.
module alink_top (
  input  logic        clk,
  input  logic        arst_n,      // board reset, async assert
  input  logic        run,         // rising edge starts the test
  input  logic [31:0] seed,
  output logic        test_done,
  output logic        test_pass,
  output logic [7:0]  err_cnt,
  output logic [31:0] chk_sig,
  output logic [7:0]  led          // {test_pass, test_done, pmon_err[2:0], tmo, heartbeat, run}
);

  // ------------------------------ reset conditioning -------------------------------
  logic rst;
  reset_sync u_rst_sync (
    .clk       (clk),
    .arst_n_in (arst_n),
    .rst_out   (rst)
  );

  // ------------------------------ chiplet 1: AXM ----------------------------------
  logic        go;
  logic        axm_done;
  logic [7:0]  axm_err;
  logic [31:0] axm_sig;
  logic [2:0]  pmon_err;
  logic [15:0] pmon_cnt_r;
  logic [7:0]  dbg_bus;
  wire         tmo = dbg_bus[7];   // tmo_sticky per AL-05 dbg_bus packing

  // AXM master bus (bin A side of the cut)
  logic        a_awvalid, a_awready, a_wvalid, a_wready, a_bvalid, a_bready;
  logic        a_arvalid, a_arready, a_rvalid, a_rready;
  logic [15:0] a_awaddr, a_araddr;
  logic [31:0] a_wdata, a_rdata;
  logic [3:0]  a_wstrb;
  logic [1:0]  a_bresp, a_rresp;

  axm_chiplet u_axm (
    .clk            (clk),
    .rst            (rst),
    .go             (go),
    .seed           (seed),
    .m_axil_awvalid (a_awvalid),
    .m_axil_awready (a_awready),
    .m_axil_awaddr  (a_awaddr),
    .m_axil_wvalid  (a_wvalid),
    .m_axil_wready  (a_wready),
    .m_axil_wdata   (a_wdata),
    .m_axil_wstrb   (a_wstrb),
    .m_axil_bvalid  (a_bvalid),
    .m_axil_bready  (a_bready),
    .m_axil_bresp   (a_bresp),
    .m_axil_arvalid (a_arvalid),
    .m_axil_arready (a_arready),
    .m_axil_araddr  (a_araddr),
    .m_axil_rvalid  (a_rvalid),
    .m_axil_rready  (a_rready),
    .m_axil_rdata   (a_rdata),
    .m_axil_rresp   (a_rresp),
    .done           (axm_done),
    .err_cnt        (axm_err),
    .chk_sig        (axm_sig),
    .pmon_err       (pmon_err),
    .pmon_cnt_r     (pmon_cnt_r),
    .dbg_bus        (dbg_bus)
  );

  // --------------------- the cut: register-slice bridge pair -----------------------
  // mid bus: between the two slice endpoints (this netlist IS the die-to-die boundary)
  logic        x_awvalid, x_awready, x_wvalid, x_wready, x_bvalid, x_bready;
  logic        x_arvalid, x_arready, x_rvalid, x_rready;
  logic [15:0] x_awaddr, x_araddr;
  logic [31:0] x_wdata, x_rdata;
  logic [3:0]  x_wstrb;
  logic [1:0]  x_bresp, x_rresp;

  // bin B side of the cut
  logic        b_awvalid, b_awready, b_wvalid, b_wready, b_bvalid, b_bready;
  logic        b_arvalid, b_arready, b_rvalid, b_rready;
  logic [15:0] b_awaddr, b_araddr;
  logic [31:0] b_wdata, b_rdata;
  logic [3:0]  b_wstrb;
  logic [1:0]  b_bresp, b_rresp;

  axil_reg_slice u_slice_m (   // master-side endpoint (bin A)
    .clk(clk), .rst(rst),
    .s_axil_awvalid(a_awvalid), .s_axil_awready(a_awready), .s_axil_awaddr(a_awaddr),
    .s_axil_wvalid (a_wvalid),  .s_axil_wready (a_wready),  .s_axil_wdata (a_wdata),
    .s_axil_wstrb  (a_wstrb),
    .s_axil_bvalid (a_bvalid),  .s_axil_bready (a_bready),  .s_axil_bresp (a_bresp),
    .s_axil_arvalid(a_arvalid), .s_axil_arready(a_arready), .s_axil_araddr(a_araddr),
    .s_axil_rvalid (a_rvalid),  .s_axil_rready (a_rready),  .s_axil_rdata (a_rdata),
    .s_axil_rresp  (a_rresp),
    .m_axil_awvalid(x_awvalid), .m_axil_awready(x_awready), .m_axil_awaddr(x_awaddr),
    .m_axil_wvalid (x_wvalid),  .m_axil_wready (x_wready),  .m_axil_wdata (x_wdata),
    .m_axil_wstrb  (x_wstrb),
    .m_axil_bvalid (x_bvalid),  .m_axil_bready (x_bready),  .m_axil_bresp (x_bresp),
    .m_axil_arvalid(x_arvalid), .m_axil_arready(x_arready), .m_axil_araddr(x_araddr),
    .m_axil_rvalid (x_rvalid),  .m_axil_rready (x_rready),  .m_axil_rdata (x_rdata),
    .m_axil_rresp  (x_rresp)
  );

  axil_reg_slice u_slice_s (   // slave-side endpoint (bin B)
    .clk(clk), .rst(rst),
    .s_axil_awvalid(x_awvalid), .s_axil_awready(x_awready), .s_axil_awaddr(x_awaddr),
    .s_axil_wvalid (x_wvalid),  .s_axil_wready (x_wready),  .s_axil_wdata (x_wdata),
    .s_axil_wstrb  (x_wstrb),
    .s_axil_bvalid (x_bvalid),  .s_axil_bready (x_bready),  .s_axil_bresp (x_bresp),
    .s_axil_arvalid(x_arvalid), .s_axil_arready(x_arready), .s_axil_araddr(x_araddr),
    .s_axil_rvalid (x_rvalid),  .s_axil_rready (x_rready),  .s_axil_rdata (x_rdata),
    .s_axil_rresp  (x_rresp),
    .m_axil_awvalid(b_awvalid), .m_axil_awready(b_awready), .m_axil_awaddr(b_awaddr),
    .m_axil_wvalid (b_wvalid),  .m_axil_wready (b_wready),  .m_axil_wdata (b_wdata),
    .m_axil_wstrb  (b_wstrb),
    .m_axil_bvalid (b_bvalid),  .m_axil_bready (b_bready),  .m_axil_bresp (b_bresp),
    .m_axil_arvalid(b_arvalid), .m_axil_arready(b_arready), .m_axil_araddr(b_araddr),
    .m_axil_rvalid (b_rvalid),  .m_axil_rready (b_rready),  .m_axil_rdata (b_rdata),
    .m_axil_rresp  (b_rresp)
  );

  // ------------------------------ chiplet 2: AXS ----------------------------------
  logic [1:0]  dbg_sel;
  logic [31:0] dbg_scratch0;
  logic [15:0] dbg_wrcnt, dbg_mem_wr_cnt;

  axs_chiplet u_axs (
    .clk            (clk),
    .rst            (rst),
    .s_axil_awvalid (b_awvalid),
    .s_axil_awready (b_awready),
    .s_axil_awaddr  (b_awaddr),
    .s_axil_wvalid  (b_wvalid),
    .s_axil_wready  (b_wready),
    .s_axil_wdata   (b_wdata),
    .s_axil_wstrb   (b_wstrb),
    .s_axil_bvalid  (b_bvalid),
    .s_axil_bready  (b_bready),
    .s_axil_bresp   (b_bresp),
    .s_axil_arvalid (b_arvalid),
    .s_axil_arready (b_arready),
    .s_axil_araddr  (b_araddr),
    .s_axil_rvalid  (b_rvalid),
    .s_axil_rready  (b_rready),
    .s_axil_rdata   (b_rdata),
    .s_axil_rresp   (b_rresp),
    .dbg_sel        (dbg_sel),
    .dbg_scratch0   (dbg_scratch0),
    .dbg_wrcnt      (dbg_wrcnt),
    .dbg_mem_wr_cnt (dbg_mem_wr_cnt)
  );

  // ------------------------------ supervisor FSM ----------------------------------
  typedef enum logic [1:0] {S_IDLE, S_GO, S_WAIT, S_DONE} sup_e;
  sup_e sup;

  logic        run_q;
  wire         run_rise = run && !run_q;
  logic [25:0] wd_cnt;                    // 2^26-clk watchdog
  logic [23:0] hb_cnt;                    // heartbeat (SPEC GAP: counter unspecified —
                                          // free-running 24-bit chosen, MSB blinks)

  always_ff @(posedge clk) begin
    if (rst) begin
      sup       <= S_IDLE;
      run_q     <= 1'b0;
      go        <= 1'b0;
      wd_cnt    <= '0;
      hb_cnt    <= '0;
      test_done <= 1'b0;
      test_pass <= 1'b0;
      err_cnt   <= '0;
      chk_sig   <= '0;
    end else begin
      run_q  <= run;
      hb_cnt <= hb_cnt + 24'd1;
      case (sup)
        S_IDLE: begin
          if (run_rise) begin
            go        <= 1'b1;            // 1-clk go pulse
            test_done <= 1'b0;
            test_pass <= 1'b0;
            sup       <= S_GO;
          end
        end
        S_GO: begin
          go     <= 1'b0;
          wd_cnt <= '0;
          sup    <= S_WAIT;
        end
        S_WAIT: begin
          wd_cnt <= wd_cnt + 26'd1;
          if (axm_done || (&wd_cnt)) begin
            // latch the verdict (done=0 on watchdog expiry -> automatic fail)
            test_pass <= axm_done && (axm_err == '0) && (pmon_err == '0) && !tmo;
            test_done <= 1'b1;
            err_cnt   <= axm_err;
            chk_sig   <= axm_sig;
            sup       <= S_DONE;
          end
        end
        // SPEC GAP (11_alink_axi.md:307): behavior after completion unspecified —
        // conservative: hold results until rst (no re-arm on a second run edge).
        S_DONE: ;
        default: sup <= S_IDLE;
      endcase
    end
  end

  assign led = {test_pass, test_done, pmon_err, tmo, hb_cnt[23], run};

endmodule // END alink_top
