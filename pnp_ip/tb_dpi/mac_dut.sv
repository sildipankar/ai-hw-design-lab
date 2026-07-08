// =============================================================================
// mac_dut -- multiply-accumulate, plug-and-play DUT for the DPI-C TB template.
//
// Fully synthesizable.
//   clr = 1          : acc <= 0            (sync clear, highest priority)
//   en  = 1, clr = 0 : acc <= acc + a * b  (product truncated to W bits)
//   else             : acc holds
// =============================================================================
module mac_dut #(
    parameter int W = 32
)(
    input  logic         clk,
    input  logic         rst_n,
    input  logic         clr,
    input  logic         en,
    input  logic [W-1:0] a,
    input  logic [W-1:0] b,
    output logic [W-1:0] acc
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)   acc <= '0;
        else if (clr) acc <= '0;
        else if (en)  acc <= acc + a * b;
    end

endmodule
