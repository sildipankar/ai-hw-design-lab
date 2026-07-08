module lfsr32 (
    input  logic        clk,
    input  logic        rst,
    input  logic        load,
    input  logic [31:0] seed,
    input  logic        enable,
    output logic [31:0] prdata,
    output logic        valid
);

    logic [31:0] prdata_next;
    logic        valid_next;

    always_comb begin
        if (rst) begin
            prdata_next = 32'h1;
            valid_next  = 1'b0;
        end else if (load) begin
            prdata_next = (seed == 32'h0) ? 32'h1 : seed;
            valid_next  = 1'b0;
        end else if (enable) begin
            logic [31:0] shifted = prdata >> 1;
            prdata_next = prdata[0] ? (shifted ^ 32'h80200003) : shifted;
            valid_next  = 1'b1;
        end else begin
            prdata_next = prdata;
            valid_next  = 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        prdata <= prdata_next;
        valid  <= valid_next;
    end

endmodule
