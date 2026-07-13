// axs_regs — register-file AXI4-Lite slave.
// Spec: 11_alink_axi.md AL-07 (AXION profile: sync active-high rst).
//
// MANDATORY REVIEW FIX APPLIED (15_bin_link_contract.md §4, ALINK row):
// AW and W are accepted INDEPENDENTLY via separate capture flags — never
// wait-for-both. This SUPERSEDES the AL-07 architecture note "wait for BOTH
// awvalid and wvalid" (which deadlocks behind a per-channel-lane bin cut).
//
// Memory map (decode on addr[7:0] per spec):
//   0x00 ID     RO 32'hA11C_0001      0x04 SCRATCH0 RW
//   0x08 SCRATCH1 RW                  0x0C WRCNT    RO
// Other write addr -> SLVERR, no state change (conservative reading: writes to the
// RO registers 0x00/0x0C are also SLVERR — flagged in BUILD_REPORT).
// Other read addr  -> rdata 32'hDEAD_BEEF, SLVERR.
module axs_regs (
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
  // live probes
  output logic [31:0] scratch0,
  output logic [31:0] scratch1,
  output logic [15:0] wrcnt
);

  localparam logic [31:0] ID_VALUE = 32'hA11C_0001;

  // ------------------------- write path: independent AW / W -------------------------
  logic        aw_got, w_got;            // captured-but-not-yet-executed flags
  logic [15:0] aw_addr_q;
  logic [31:0] w_data_q;

  // ready = "my capture slot is free and no response pending" — a function of local
  // registers only, never of the opposite channel's valid (fix a)
  assign s_axil_awready = !aw_got && !s_axil_bvalid;
  assign s_axil_wready  = !w_got  && !s_axil_bvalid;

  wire aw_fire = s_axil_awvalid && s_axil_awready;
  wire w_fire  = s_axil_wvalid  && s_axil_wready;
  wire aw_have = aw_got || aw_fire;      // includes an arrival this very cycle
  wire w_have  = w_got  || w_fire;
  wire do_write = aw_have && w_have && !s_axil_bvalid;

  // effective address/data: captured earlier, or arriving right now
  wire [15:0] wa = aw_got ? aw_addr_q : s_axil_awaddr;
  wire [31:0] wd = w_got  ? w_data_q  : s_axil_wdata;
  wire        wr_ok = (wa[7:0] == 8'h04) || (wa[7:0] == 8'h08);

  always_ff @(posedge clk) begin
    if (rst) begin
      aw_got        <= 1'b0;
      w_got         <= 1'b0;
      aw_addr_q     <= '0;
      w_data_q      <= '0;
      s_axil_bvalid <= 1'b0;
      s_axil_bresp  <= 2'b00;
      scratch0      <= '0;
      scratch1      <= '0;
      wrcnt         <= '0;
    end else begin
      if (aw_fire) begin
        aw_addr_q <= s_axil_awaddr;
        aw_got    <= 1'b1;
      end
      if (w_fire) begin
        w_data_q <= s_axil_wdata;
        w_got    <= 1'b1;
      end
      if (do_write) begin                // overrides the captures above (last write wins)
        aw_got        <= 1'b0;
        w_got         <= 1'b0;
        s_axil_bvalid <= 1'b1;
        s_axil_bresp  <= wr_ok ? 2'b00 : 2'b10;   // OKAY / SLVERR
        if (wr_ok) begin
          if (wa[7:0] == 8'h04) scratch0 <= wd;
          else                  scratch1 <= wd;
          wrcnt <= wrcnt + 16'd1;        // counts OKAY writes only (spec)
        end
      end else if (s_axil_bvalid && s_axil_bready) begin
        s_axil_bvalid <= 1'b0;
      end
    end
  end

  // ------------------------------- read path ---------------------------------------
  assign s_axil_arready = !s_axil_rvalid;
  wire ar_fire = s_axil_arvalid && s_axil_arready;

  always_ff @(posedge clk) begin
    if (rst) begin
      s_axil_rvalid <= 1'b0;
      s_axil_rdata  <= '0;
      s_axil_rresp  <= 2'b00;
    end else begin
      if (ar_fire) begin
        s_axil_rvalid <= 1'b1;
        s_axil_rresp  <= 2'b00;
        case (s_axil_araddr[7:0])
          8'h00:   s_axil_rdata <= ID_VALUE;
          8'h04:   s_axil_rdata <= scratch0;
          8'h08:   s_axil_rdata <= scratch1;
          8'h0C:   s_axil_rdata <= {16'h0000, wrcnt};
          default: begin
            s_axil_rdata <= 32'hDEAD_BEEF;
            s_axil_rresp <= 2'b10;       // SLVERR
          end
        endcase
      end else if (s_axil_rvalid && s_axil_rready) begin
        s_axil_rvalid <= 1'b0;
      end
    end
  end

endmodule // END axs_regs
