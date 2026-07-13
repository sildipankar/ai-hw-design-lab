// axs_mem — SRAM-backed AXI4-Lite slave (1024x32, always OKAY).
// Spec: 11_alink_axi.md AL-08 (AXION profile: sync active-high rst).
//
// MANDATORY REVIEW FIX APPLIED (15_bin_link_contract.md §4, ALINK row):
// AW and W are accepted INDEPENDENTLY via separate capture flags — never
// wait-for-both (supersedes the "accept AW+W together" wording in AL-08).
//
// Read latency (pass-criteria row): AR accept -> R_FETCH (RAM en) -> R_WAIT (RAM
// rvalid) -> R_RESP: rvalid exactly 3 clks after AR accept.
// Word address into RAM = a*addr[11:2] (4 KB region fully backed).
module axs_mem (
  input  logic        clk,
  input  logic        rst,
  // AXI4-Lite SLAVE port (all 17 bus-table signals)
  input  logic        s_axil_awvalid,
  output logic        s_axil_awready,
  input  logic [15:0] s_axil_awaddr,
  input  logic        s_axil_wvalid,
  output logic        s_axil_wready,
  input  logic [31:0] s_axil_wdata,
  input  logic [3:0]  s_axil_wstrb,     // always 4'hF in this design (spec) — unused
  output logic        s_axil_bvalid,
  input  logic        s_axil_bready,
  output logic [1:0]  s_axil_bresp,
  input  logic        s_axil_arvalid,
  output logic        s_axil_arready,
  input  logic [15:0] s_axil_araddr,
  output logic        s_axil_rvalid,
  input  logic        s_axil_rready,
  output logic [31:0] s_axil_rdata,
  output logic [1:0]  s_axil_rresp,
  // probe
  output logic [15:0] mem_wr_cnt
);

  // single sram_bank instance, one shared port (one-outstanding system; a write-priority
  // guard below keeps it safe even if read and write ever overlapped)
  logic        ram_en, ram_we;
  logic [9:0]  ram_addr;
  logic [31:0] ram_wdata, ram_rdata;
  logic        ram_rvalid;

  sram_bank #(.DW(32), .DEPTH(1024)) u_ram (
    .clk    (clk),
    .en     (ram_en),
    .we     (ram_we),
    .addr   (ram_addr),
    .wdata  (ram_wdata),
    .rdata  (ram_rdata),
    .rvalid (ram_rvalid)
  );

  // ------------------------- write path: independent AW / W -------------------------
  typedef enum logic [1:0] {W_COLLECT, W_MEM, W_RESP} wstate_e;
  wstate_e wstate;

  logic        aw_got, w_got;
  logic [15:0] aw_addr_q;
  logic [31:0] w_data_q;

  assign s_axil_awready = (wstate == W_COLLECT) && !aw_got;
  assign s_axil_wready  = (wstate == W_COLLECT) && !w_got;

  wire aw_fire = s_axil_awvalid && s_axil_awready;
  wire w_fire  = s_axil_wvalid  && s_axil_wready;
  wire aw_have = aw_got || aw_fire;
  wire w_have  = w_got  || w_fire;
  wire wr_launch = (wstate == W_COLLECT) && aw_have && w_have;   // RAM pulse next cycle

  wire [15:0] wa = aw_got ? aw_addr_q : s_axil_awaddr;
  wire [31:0] wd = w_got  ? w_data_q  : s_axil_wdata;

  assign s_axil_bresp = 2'b00;             // full 4KB range is backed: always OKAY

  // ------------------------------- read path ---------------------------------------
  typedef enum logic [1:0] {R_IDLE, R_FETCH, R_WAIT, R_RESP} rstate_e;
  rstate_e rstate;

  logic [15:0] ar_addr_q;

  assign s_axil_arready = (rstate == R_IDLE);
  wire ar_fire = s_axil_arvalid && s_axil_arready;
  assign s_axil_rresp = 2'b00;             // always OKAY

  // ------------------------- shared RAM port + both FSMs ---------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      wstate        <= W_COLLECT;
      rstate        <= R_IDLE;
      aw_got        <= 1'b0;
      w_got         <= 1'b0;
      aw_addr_q     <= '0;
      w_data_q      <= '0;
      s_axil_bvalid <= 1'b0;
      s_axil_rvalid <= 1'b0;
      s_axil_rdata  <= '0;
      ar_addr_q     <= '0;
      mem_wr_cnt    <= '0;
      ram_en        <= 1'b0;
      ram_we        <= 1'b0;
      ram_addr      <= '0;
      ram_wdata     <= '0;
    end else begin
      ram_en <= 1'b0;                      // default: RAM idle; pulses are 1 cycle
      ram_we <= 1'b0;

      // ---- write FSM ----
      case (wstate)
        W_COLLECT: begin
          if (aw_fire) begin
            aw_addr_q <= s_axil_awaddr;
            aw_got    <= 1'b1;
          end
          if (w_fire) begin
            w_data_q <= s_axil_wdata;
            w_got    <= 1'b1;
          end
          if (wr_launch) begin             // both halves present: 1-cycle RAM write pulse
            aw_got    <= 1'b0;
            w_got     <= 1'b0;
            ram_en    <= 1'b1;
            ram_we    <= 1'b1;
            ram_addr  <= wa[11:2];
            ram_wdata <= wd;
            wstate    <= W_MEM;
          end
        end
        W_MEM: begin                       // RAM write happening this cycle
          mem_wr_cnt    <= mem_wr_cnt + 16'd1;
          s_axil_bvalid <= 1'b1;
          wstate        <= W_RESP;
        end
        W_RESP: begin
          if (s_axil_bready) begin         // bvalid is high
            s_axil_bvalid <= 1'b0;
            wstate        <= W_COLLECT;
          end
        end
        default: wstate <= W_COLLECT;
      endcase

      // ---- read FSM (write has RAM-port priority via wr_launch guard) ----
      // RAM en fires on the transition out of R_IDLE so rvalid lands exactly
      // 3 clks after the AR accept cycle (pass-criteria row). R_FETCH is only
      // the retry state for a RAM-port conflict (unreachable one-outstanding).
      case (rstate)
        R_IDLE: begin
          if (ar_fire) begin
            ar_addr_q <= s_axil_araddr;
            if (!wr_launch) begin          // never fight the write pulse for the port
              ram_en   <= 1'b1;            // ram_we stays 0: read
              ram_addr <= s_axil_araddr[11:2];
              rstate   <= R_WAIT;
            end else begin
              rstate <= R_FETCH;
            end
          end
        end
        R_FETCH: begin
          if (!wr_launch) begin
            ram_en   <= 1'b1;
            ram_addr <= ar_addr_q[11:2];
            rstate   <= R_WAIT;
          end                              // else hold: retry next cycle
        end
        R_WAIT: begin
          if (ram_rvalid) begin
            s_axil_rdata  <= ram_rdata;
            s_axil_rvalid <= 1'b1;
            rstate        <= R_RESP;
          end
        end
        R_RESP: begin
          if (s_axil_rready) begin         // rvalid is high
            s_axil_rvalid <= 1'b0;
            rstate        <= R_IDLE;
          end
        end
        default: rstate <= R_IDLE;
      endcase
    end
  end

endmodule // END axs_mem
