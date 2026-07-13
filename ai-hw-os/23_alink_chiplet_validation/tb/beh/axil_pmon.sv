// TB-ONLY BEHAVIORAL MODEL of axil_pmon (spec 11_alink_axi.md AL-03) — SIMPLIFIED.
// NOT the spec implementation (14B/local-model work). Handshake counters, valid-drop,
// orphan and stall detection are functional; payload-stability check (spec "v2") absent.
// Port-compatible with AL-03 so axm_chiplet integration sims run. NEVER synthesize.
module axil_pmon (
  input  logic        clk,
  input  logic        rst,
  input  logic        t_axil_awvalid, t_axil_awready,
  input  logic [15:0] t_axil_awaddr,
  input  logic        t_axil_wvalid, t_axil_wready,
  input  logic [31:0] t_axil_wdata,
  input  logic [3:0]  t_axil_wstrb,
  input  logic        t_axil_bvalid, t_axil_bready,
  input  logic [1:0]  t_axil_bresp,
  input  logic        t_axil_arvalid, t_axil_arready,
  input  logic [15:0] t_axil_araddr,
  input  logic        t_axil_rvalid, t_axil_rready,
  input  logic [31:0] t_axil_rdata,
  input  logic [1:0]  t_axil_rresp,
  output logic [15:0] cnt_aw, cnt_ar, cnt_b, cnt_r,
  output logic [7:0]  cnt_errresp,
  output logic        err_vdrop,
  output logic        err_orphan,
  output logic        err_stall
);
  // 1-flop history per channel for drop detection
  logic awv_q, awr_q, wv_q, wr_q, bv_q, br_q, arv_q, arr_q, rv_q, rr_q;
  // outstanding tracking
  logic [1:0]  outs_wr, outs_rd;
  logic        aw_done, w_done;
  logic [11:0] stall_cnt;

  wire aw_hs = t_axil_awvalid && t_axil_awready;
  wire w_hs  = t_axil_wvalid  && t_axil_wready;
  wire b_hs  = t_axil_bvalid  && t_axil_bready;
  wire ar_hs = t_axil_arvalid && t_axil_arready;
  wire r_hs  = t_axil_rvalid  && t_axil_rready;
  wire any_wait = (t_axil_awvalid && !t_axil_awready) || (t_axil_wvalid && !t_axil_wready) ||
                  (t_axil_arvalid && !t_axil_arready) || (t_axil_bvalid && !t_axil_bready) ||
                  (t_axil_rvalid  && !t_axil_rready);

  always_ff @(posedge clk) begin
    if (rst) begin
      {cnt_aw, cnt_ar, cnt_b, cnt_r} <= '0;
      cnt_errresp <= '0;
      err_vdrop   <= 1'b0;
      err_orphan  <= 1'b0;
      err_stall   <= 1'b0;
      {awv_q, awr_q, wv_q, wr_q, bv_q, br_q, arv_q, arr_q, rv_q, rr_q} <= '0;
      outs_wr <= '0; outs_rd <= '0;
      aw_done <= 1'b0; w_done <= 1'b0;
      stall_cnt <= '0;
    end else begin
      awv_q <= t_axil_awvalid; awr_q <= t_axil_awready;
      wv_q  <= t_axil_wvalid;  wr_q  <= t_axil_wready;
      bv_q  <= t_axil_bvalid;  br_q  <= t_axil_bready;
      arv_q <= t_axil_arvalid; arr_q <= t_axil_arready;
      rv_q  <= t_axil_rvalid;  rr_q  <= t_axil_rready;

      if (aw_hs) cnt_aw <= cnt_aw + 16'd1;
      if (ar_hs) cnt_ar <= cnt_ar + 16'd1;
      if (b_hs)  cnt_b  <= cnt_b  + 16'd1;
      if (r_hs)  cnt_r  <= cnt_r  + 16'd1;
      if ((b_hs && t_axil_bresp != 2'b00) || (r_hs && t_axil_rresp != 2'b00))
        cnt_errresp <= (cnt_errresp == 8'hFF) ? cnt_errresp : cnt_errresp + 8'd1;

      // sticky: any *valid deasserted before its ready (rule break)
      if ((awv_q && !awr_q && !t_axil_awvalid) || (wv_q && !wr_q && !t_axil_wvalid) ||
          (arv_q && !arr_q && !t_axil_arvalid) || (bv_q && !br_q && !t_axil_bvalid) ||
          (rv_q  && !rr_q  && !t_axil_rvalid))
        err_vdrop <= 1'b1;

      // outstanding write: inc when BOTH AW and W have completed
      if ((aw_done || aw_hs) && (w_done || w_hs)) begin
        aw_done <= 1'b0;
        w_done  <= 1'b0;
        outs_wr <= outs_wr + (b_hs ? 2'd0 : 2'd1);
      end else begin
        if (aw_hs) aw_done <= 1'b1;
        if (w_hs)  w_done  <= 1'b1;
        if (b_hs) begin
          if (outs_wr == 0) err_orphan <= 1'b1;
          else              outs_wr    <= outs_wr - 2'd1;
        end
      end
      if (ar_hs && !r_hs)      outs_rd <= outs_rd + 2'd1;
      else if (r_hs && !ar_hs) begin
        if (outs_rd == 0) err_orphan <= 1'b1;
        else              outs_rd    <= outs_rd - 2'd1;
      end

      // shared stall detector: any valid waiting > 4094 consecutive clks
      if (any_wait) begin
        stall_cnt <= stall_cnt + 12'd1;
        if (stall_cnt == 12'hFFE) err_stall <= 1'b1;
      end else begin
        stall_cnt <= '0;
      end
    end
  end
endmodule // END axil_pmon (TB behavioral, SIMPLIFIED)
