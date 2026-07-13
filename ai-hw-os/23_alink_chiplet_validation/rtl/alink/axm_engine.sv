// axm_engine — AXI4-Lite master FSM with timeout.
// Spec: 11_alink_axi.md AL-02 (AXION profile: sync active-high rst).
// Valid/ready law: every m_axil_*valid below is a REGISTERED flop (or a decode of the
// state register alone) — never a combinational function of a ready. This designs out
// the classic combinational valid<->ready loop (the AXI lesson of this design).
module axm_engine (
  input  logic        clk,
  input  logic        rst,
  // command side (from cmd_gen)
  input  logic        cmd_valid,
  output logic        cmd_ready,        // 1 clk: engine latches the command (IDLE only)
  input  logic        cmd_write,
  input  logic [15:0] cmd_addr,
  input  logic [31:0] cmd_wdata,
  // response side (to cmd_gen)
  output logic        rsp_valid,        // 1-clk pulse: B or R received, or timeout
  output logic [31:0] rsp_rdata,        // latched rdata for reads
  output logic        rsp_err,          // latched: nonzero resp code OR timeout
  // AXI4-Lite MASTER port (all 17 bus-table signals)
  output logic        m_axil_awvalid,
  input  logic        m_axil_awready,
  output logic [15:0] m_axil_awaddr,
  output logic        m_axil_wvalid,
  input  logic        m_axil_wready,
  output logic [31:0] m_axil_wdata,
  output logic [3:0]  m_axil_wstrb,
  input  logic        m_axil_bvalid,
  output logic        m_axil_bready,
  input  logic [1:0]  m_axil_bresp,
  output logic        m_axil_arvalid,
  input  logic        m_axil_arready,
  output logic [15:0] m_axil_araddr,
  input  logic        m_axil_rvalid,
  output logic        m_axil_rready,
  input  logic [31:0] m_axil_rdata,
  input  logic [1:0]  m_axil_rresp,
  // bring-up
  output logic        tmo_sticky,       // latches on first timeout, cleared only by rst
  output logic [2:0]  state_dbg
);

  typedef enum logic [2:0] {
    S_IDLE    = 3'd0,
    S_WR_REQ  = 3'd1,
    S_WR_RESP = 3'd2,
    S_RD_REQ  = 3'd3,
    S_RD_RESP = 3'd4,
    S_RESP    = 3'd5
  } state_e;
  state_e state;

  // latched command
  logic [15:0] q_addr;
  logic [31:0] q_wdata;

  // per-channel "seen" flags: AW and W complete INDEPENDENTLY
  logic awdone, wdone;

  logic [11:0] tmo_cnt;
  wire         tmo_hit = (tmo_cnt == 12'hFFF);

  // decodes of the state register only (registered-equivalent, glitch-free)
  assign cmd_ready = (state == S_IDLE);
  assign rsp_valid = (state == S_RESP);      // S_RESP lasts exactly one cycle
  assign state_dbg = state;

  // payload held stable from IDLE latch until the transaction retires
  assign m_axil_awaddr = q_addr;
  assign m_axil_araddr = q_addr;
  assign m_axil_wdata  = q_wdata;
  assign m_axil_wstrb  = 4'hF;               // this design always writes all bytes

  always_ff @(posedge clk) begin
    if (rst) begin
      state          <= S_IDLE;
      m_axil_awvalid <= 1'b0;
      m_axil_wvalid  <= 1'b0;
      m_axil_arvalid <= 1'b0;
      m_axil_bready  <= 1'b0;
      m_axil_rready  <= 1'b0;
      awdone         <= 1'b0;
      wdone          <= 1'b0;
      rsp_rdata      <= '0;
      rsp_err        <= 1'b0;
      tmo_sticky     <= 1'b0;
      tmo_cnt        <= '0;
      q_addr         <= '0;
      q_wdata        <= '0;
    end else begin
      case (state)
        S_IDLE: begin
          tmo_cnt <= '0;                     // timeout budget is per transaction
          awdone  <= 1'b0;
          wdone   <= 1'b0;
          rsp_err <= 1'b0;
          if (cmd_valid) begin               // cmd_ready==1 here by construction
            q_addr  <= cmd_addr;
            q_wdata <= cmd_wdata;
            if (cmd_write) begin
              m_axil_awvalid <= 1'b1;        // AW and W presented together...
              m_axil_wvalid  <= 1'b1;
              state          <= S_WR_REQ;
            end else begin
              m_axil_arvalid <= 1'b1;
              state          <= S_RD_REQ;
            end
          end
        end

        S_WR_REQ: begin
          tmo_cnt <= tmo_cnt + 12'd1;
          // ...but each drops INDEPENDENTLY as its own ready arrives
          if (m_axil_awvalid && m_axil_awready) begin
            m_axil_awvalid <= 1'b0;
            awdone         <= 1'b1;
          end
          if (m_axil_wvalid && m_axil_wready) begin
            m_axil_wvalid <= 1'b0;
            wdone         <= 1'b1;
          end
          if ((awdone || (m_axil_awvalid && m_axil_awready)) &&
              (wdone  || (m_axil_wvalid  && m_axil_wready))) begin
            m_axil_bready <= 1'b1;
            state         <= S_WR_RESP;
          end else if (tmo_hit) begin
            m_axil_awvalid <= 1'b0;          // drop all valids first (spec)
            m_axil_wvalid  <= 1'b0;
            rsp_err        <= 1'b1;
            tmo_sticky     <= 1'b1;
            state          <= S_RESP;
          end
        end

        S_WR_RESP: begin
          tmo_cnt <= tmo_cnt + 12'd1;
          if (m_axil_bvalid) begin           // bready is already high
            m_axil_bready <= 1'b0;
            rsp_err       <= (m_axil_bresp != 2'b00);
            state         <= S_RESP;
          end else if (tmo_hit) begin
            m_axil_bready <= 1'b0;
            rsp_err       <= 1'b1;
            tmo_sticky    <= 1'b1;
            state         <= S_RESP;
          end
        end

        S_RD_REQ: begin
          tmo_cnt <= tmo_cnt + 12'd1;
          if (m_axil_arvalid && m_axil_arready) begin
            m_axil_arvalid <= 1'b0;
            m_axil_rready  <= 1'b1;
            state          <= S_RD_RESP;
          end else if (tmo_hit) begin
            m_axil_arvalid <= 1'b0;
            rsp_err        <= 1'b1;
            tmo_sticky     <= 1'b1;
            state          <= S_RESP;
          end
        end

        S_RD_RESP: begin
          tmo_cnt <= tmo_cnt + 12'd1;
          if (m_axil_rvalid) begin           // rready is already high
            m_axil_rready <= 1'b0;
            rsp_rdata     <= m_axil_rdata;
            rsp_err       <= (m_axil_rresp != 2'b00);
            state         <= S_RESP;
          end else if (tmo_hit) begin
            m_axil_rready <= 1'b0;
            rsp_err       <= 1'b1;
            tmo_sticky    <= 1'b1;
            state         <= S_RESP;
          end
        end

        S_RESP: state <= S_IDLE;             // rsp_valid pulses this cycle

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule // END axm_engine
