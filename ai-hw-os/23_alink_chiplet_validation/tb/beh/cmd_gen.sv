// TB-ONLY BEHAVIORAL MODEL of cmd_gen (spec 11_alink_axi.md AL-01) — SIMPLIFIED.
// NOT the spec implementation (that is 14B/local-model work): 8 words instead of 64,
// simple arithmetic pattern instead of lfsr32, rotate-XOR compressor instead of misr32,
// 3 directed reg ops instead of 6. Port-compatible with AL-01 so integration sims of
// the frontier-owned chiplet/top RTL can run today. NEVER synthesize this file.
module cmd_gen (
  input  logic        clk,
  input  logic        rst,
  input  logic        go,
  input  logic [31:0] seed,
  output logic        cmd_valid,
  input  logic        cmd_ready,
  output logic        cmd_write,
  output logic [15:0] cmd_addr,
  output logic [31:0] cmd_wdata,
  input  logic        rsp_valid,
  input  logic [31:0] rsp_rdata,
  input  logic        rsp_err,
  output logic        done,
  output logic [7:0]  err_cnt,
  output logic [31:0] chk_sig,
  output logic [2:0]  state_dbg
);
  localparam int unsigned NW = 8;             // spec uses 64; simplified
  localparam logic [31:0] STRIDE = 32'h9E37_79B9;

  typedef enum logic [2:0] {IDLE, P1_WR, P2_RD, P3_REG, DONE_S} st_e;
  st_e st;
  assign state_dbg = st;

  logic [31:0] seed_q;
  logic [3:0]  idx;                            // word / directed-op index
  logic        busy;                           // one command outstanding

  function automatic logic [31:0] pat(input logic [31:0] s, input int i);
    return s ^ (STRIDE * i) ^ 32'h0BAD_F00D;
  endfunction

  // expected read data per phase/idx
  function automatic logic [31:0] p3_exp(input int i);
    case (i)
      1:       return 32'h5A5A_A5A5;           // scratch0 readback
      default: return 32'hA11C_0001;           // ID
    endcase
  endfunction

  always_ff @(posedge clk) begin
    if (rst) begin
      st        <= IDLE;
      cmd_valid <= 1'b0;
      cmd_write <= 1'b0;
      cmd_addr  <= '0;
      cmd_wdata <= '0;
      done      <= 1'b0;
      err_cnt   <= '0;
      chk_sig   <= '0;
      seed_q    <= '0;
      idx       <= '0;
      busy      <= 1'b0;
    end else begin
      // command handshake: drop valid only on ready (valid/ready law)
      if (cmd_valid && cmd_ready) begin
        cmd_valid <= 1'b0;
        busy      <= 1'b1;
      end

      case (st)
        IDLE: begin
          if (go) begin
            st      <= P1_WR;
            seed_q  <= seed;
            idx     <= '0;
            done    <= 1'b0;
            err_cnt <= '0;
            chk_sig <= '0;
            busy    <= 1'b0;
          end
        end

        P1_WR: begin
          if (!busy && !cmd_valid) begin
            cmd_valid <= 1'b1;
            cmd_write <= 1'b1;
            cmd_addr  <= 16'h8000 + 16'(4 * idx);
            cmd_wdata <= pat(seed_q, int'(idx));
          end
          if (rsp_valid) begin
            busy <= 1'b0;
            if (rsp_err) err_cnt <= (err_cnt == 8'hFF) ? err_cnt : err_cnt + 8'd1;
            if (idx == 4'(NW - 1)) begin idx <= '0; st <= P2_RD; end
            else                   idx <= idx + 4'd1;
          end
        end

        P2_RD: begin
          if (!busy && !cmd_valid) begin
            cmd_valid <= 1'b1;
            cmd_write <= 1'b0;
            cmd_addr  <= 16'h8000 + 16'(4 * idx);
          end
          if (rsp_valid) begin
            busy    <= 1'b0;
            chk_sig <= {chk_sig[30:0], chk_sig[31]} ^ rsp_rdata;
            if (rsp_err || (rsp_rdata !== pat(seed_q, int'(idx))))
              err_cnt <= (err_cnt == 8'hFF) ? err_cnt : err_cnt + 8'd1;
            if (idx == 4'(NW - 1)) begin idx <= '0; st <= P3_REG; end
            else                   idx <= idx + 4'd1;
          end
        end

        P3_REG: begin
          // op0: write SCRATCH0=0x5A5AA5A5, op1: read SCRATCH0, op2: read ID
          if (!busy && !cmd_valid) begin
            cmd_valid <= 1'b1;
            cmd_write <= (idx == 0);
            cmd_addr  <= (idx == 2) ? 16'h0000 : 16'h0004;
            cmd_wdata <= 32'h5A5A_A5A5;
          end
          if (rsp_valid) begin
            busy <= 1'b0;
            if (idx != 0) begin
              chk_sig <= {chk_sig[30:0], chk_sig[31]} ^ rsp_rdata;
              if (rsp_err || (rsp_rdata !== p3_exp(int'(idx))))
                err_cnt <= (err_cnt == 8'hFF) ? err_cnt : err_cnt + 8'd1;
            end else if (rsp_err) begin
              err_cnt <= (err_cnt == 8'hFF) ? err_cnt : err_cnt + 8'd1;
            end
            if (idx == 2) begin st <= DONE_S; done <= 1'b1; end
            else          idx <= idx + 4'd1;
          end
        end

        DONE_S: ;                              // hold until next go... rst only

        default: st <= IDLE;
      endcase
    end
  end

endmodule // END cmd_gen (TB behavioral, SIMPLIFIED)
