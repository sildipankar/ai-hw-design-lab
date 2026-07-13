// axil_master_bfm.svh — TB-side AXI4-Lite MASTER BFM tasks.
// `include inside a TB module that declares: clk plus s_axil_* signals in SLAVE-port
// orientation (TB drives valids/payloads/readys of the master role).
// Call every task from a @(negedge clk) boundary.
// aw_lead / w_lead let tests exercise INDEPENDENT AW/W ordering (review fix a):
// the channel with the smaller lead starts first.

task automatic axi_write(input  logic [15:0] addr,
                         input  logic [31:0] data,
                         input  int         aw_lead,
                         input  int         w_lead,
                         input  int         bready_dly,
                         output logic [1:0] resp);
  fork
    begin : send_aw
      repeat (aw_lead) @(negedge clk);
      s_axil_awvalid = 1'b1;
      s_axil_awaddr  = addr;
      forever begin
        #1;
        if (s_axil_awready === 1'b1) break;
        @(negedge clk);
      end
      @(posedge clk);              // AW handshake completes here
      @(negedge clk);
      s_axil_awvalid = 1'b0;
    end
    begin : send_w
      repeat (w_lead) @(negedge clk);
      s_axil_wvalid = 1'b1;
      s_axil_wdata  = data;
      s_axil_wstrb  = 4'hF;
      forever begin
        #1;
        if (s_axil_wready === 1'b1) break;
        @(negedge clk);
      end
      @(posedge clk);              // W handshake completes here
      @(negedge clk);
      s_axil_wvalid = 1'b0;
    end
  join
  repeat (bready_dly) @(negedge clk);
  s_axil_bready = 1'b1;
  forever begin
    #1;
    if (s_axil_bvalid === 1'b1) break;
    @(negedge clk);
  end
  resp = s_axil_bresp;
  @(posedge clk);                  // B handshake completes here
  @(negedge clk);
  s_axil_bready = 1'b0;
endtask

task automatic axi_read(input  logic [15:0] addr,
                        input  int          rready_dly,
                        output logic [31:0] data,
                        output logic [1:0]  resp);
  s_axil_arvalid = 1'b1;
  s_axil_araddr  = addr;
  forever begin
    #1;
    if (s_axil_arready === 1'b1) break;
    @(negedge clk);
  end
  @(posedge clk);                  // AR handshake completes here
  @(negedge clk);
  s_axil_arvalid = 1'b0;
  repeat (rready_dly) @(negedge clk);
  s_axil_rready = 1'b1;
  forever begin
    #1;
    if (s_axil_rvalid === 1'b1) break;
    @(negedge clk);
  end
  data = s_axil_rdata;
  resp = s_axil_rresp;
  @(posedge clk);                  // R handshake completes here
  @(negedge clk);
  s_axil_rready = 1'b0;
endtask
