// skid_buffer — full-throughput valid/ready pipeline register with one skid slot.
// Spec: 01_common_ip.md C-05 (AXION profile: sync active-high rst).
// Valid/ready law: s_ready is a REGISTERED output (breaks the ready path);
// m_valid is registered and NEVER a function of m_ready. No loss, no duplication.
module skid_buffer #(
  parameter int unsigned WIDTH = 32
) (
  input  logic             clk,
  input  logic             rst,       // sync active-high
  input  logic             s_valid,
  output logic             s_ready,   // registered
  input  logic [WIDTH-1:0] s_data,
  output logic             m_valid,   // registered
  input  logic             m_ready,
  output logic [WIDTH-1:0] m_data     // registered
);

  logic             skid_valid;             // skid slot occupied
  logic [WIDTH-1:0] skid_data;

  // invariant: s_ready == !skid_valid (so an accept can never overrun the skid slot)
  wire s_fire = s_valid && s_ready;
  wire m_adv  = m_ready || !m_valid;         // output register can (re)load this cycle

  always_ff @(posedge clk) begin
    if (rst) begin
      m_valid    <= 1'b0;
      m_data     <= '0;
      skid_valid <= 1'b0;
      skid_data  <= '0;
      s_ready    <= 1'b1;
    end else begin
      if (m_adv) begin
        // skid drains first; s_fire impossible while skid_valid (s_ready==0)
        m_valid    <= skid_valid || s_fire;
        m_data     <= skid_valid ? skid_data : s_data;
        skid_valid <= 1'b0;
      end else if (s_fire) begin
        // output stalled and full: incoming beat lands in the skid slot
        skid_valid <= 1'b1;
        skid_data  <= s_data;
      end
      s_ready <= m_adv ? 1'b1 : !(skid_valid || s_fire);
    end
  end

endmodule // END skid_buffer
