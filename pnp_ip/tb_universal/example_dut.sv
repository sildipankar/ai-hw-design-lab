// =============================================================================
// example_dut -- placeholder DUT for the universal testbench template.
//
// Fully synthesizable. 2-stage pipeline adder:
//   cycle 0: in_valid + a,b sampled
//   cycle 1: stage-1 registers hold a+b
//   cycle 2: out_valid=1, sum = a+b        (latency = 2 clocks)
//
// This file is meant to be REPLACED: drop your own DUT .sv into this folder,
// delete this file, and update the fenced sections in tb_universal.sv.
// Your DUT file must NOT be named tb_*.sv (the sim runner treats tb_* as top).
// =============================================================================
module example_dut #(
    parameter int W = 32
)(
    input  logic         clk,
    input  logic         rst_n,
    input  logic         in_valid,
    input  logic [W-1:0] a,
    input  logic [W-1:0] b,
    output logic         out_valid,
    output logic [W-1:0] sum
);

    // stage 1
    logic         v1;
    logic [W-1:0] s1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1        <= 1'b0;
            s1        <= '0;
            out_valid <= 1'b0;
            sum       <= '0;
        end else begin
            v1        <= in_valid;
            s1        <= a + b;
            out_valid <= v1;      // stage 2
            sum       <= s1;
        end
    end

endmodule
