// axil_slave_bfm.svh — TB-side AXI4-Lite SLAVE BFM (reactive, dictionary-backed).
// `include inside a TB module that declares: clk, rst plus m_axil_* signals in
// MASTER-port orientation (TB observes valids, drives readys and B/R channels).
// Reset-aware: an asserted rst ABORTS the in-flight transaction and clears drives.
// Knobs (set before/between transactions):
//   bfm_accept      0 = never assert readys (address-phase timeout testing)
//   bfm_respond     0 = accept AW/W/AR but never send B/R (response-phase timeout)
//   bfm_*_dly       cycles before each ready / response valid
//   bfm_bresp_force / bfm_rresp_force  response codes to return
//   bfm_corrupt_mask XORed into the NEXT read data, then self-clears
// Pre-load bfm_mem for ROM-like addresses (e.g. bfm_mem[16'h0000] = ID).

logic [31:0] bfm_mem [logic [15:0]];
int          bfm_awready_dly = 0, bfm_wready_dly = 0, bfm_b_dly = 0;
int          bfm_ar_dly = 0, bfm_r_dly = 0;
bit          bfm_accept  = 1;
bit          bfm_respond = 1;
logic [1:0]  bfm_bresp_force = 2'b00, bfm_rresp_force = 2'b00;
logic [31:0] bfm_corrupt_mask = '0;
int unsigned bfm_writes = 0, bfm_reads = 0;

task automatic bfm_clear_drives();
  m_axil_awready = 0; m_axil_wready = 0; m_axil_bvalid = 0;
  m_axil_arready = 0; m_axil_rvalid = 0;
endtask

// serve exactly one transaction (or return immediately if none requested)
task automatic bfm_serve_one();
  logic [15:0] a;
  logic [31:0] d;
  if (m_axil_awvalid === 1'b1 || m_axil_wvalid === 1'b1) begin
    fork
      begin : take_aw
        repeat (bfm_awready_dly) @(negedge clk);
        m_axil_awready = 1'b1;
        #1;
        while (m_axil_awvalid !== 1'b1) @(negedge clk);
        a = m_axil_awaddr;
        @(posedge clk);            // AW handshake
        @(negedge clk);
        m_axil_awready = 1'b0;
      end
      begin : take_w
        repeat (bfm_wready_dly) @(negedge clk);
        m_axil_wready = 1'b1;
        #1;
        while (m_axil_wvalid !== 1'b1) @(negedge clk);
        d = m_axil_wdata;
        @(posedge clk);            // W handshake
        @(negedge clk);
        m_axil_wready = 1'b0;
      end
    join
    if (bfm_respond) begin
      bfm_mem[a] = d;
      bfm_writes++;
      repeat (bfm_b_dly) @(negedge clk);
      m_axil_bvalid = 1'b1;
      m_axil_bresp  = bfm_bresp_force;
      #1;
      while (m_axil_bready !== 1'b1) @(negedge clk);
      @(posedge clk);              // B handshake
      @(negedge clk);
      m_axil_bvalid = 1'b0;
    end
  end else if (m_axil_arvalid === 1'b1) begin
    repeat (bfm_ar_dly) @(negedge clk);
    m_axil_arready = 1'b1;
    #1;
    while (m_axil_arvalid !== 1'b1) @(negedge clk);
    a = m_axil_araddr;
    @(posedge clk);                // AR handshake
    @(negedge clk);
    m_axil_arready = 1'b0;
    if (bfm_respond) begin
      bfm_reads++;
      repeat (bfm_r_dly) @(negedge clk);
      m_axil_rvalid = 1'b1;
      m_axil_rresp  = bfm_rresp_force;
      m_axil_rdata  = (bfm_mem.exists(a) ? bfm_mem[a] : 32'hDEAD_BEEF)
                      ^ bfm_corrupt_mask;
      bfm_corrupt_mask = '0;
      #1;
      while (m_axil_rready !== 1'b1) @(negedge clk);
      @(posedge clk);              // R handshake
      @(negedge clk);
      m_axil_rvalid = 1'b0;
    end
  end
endtask

initial begin : bfm_server
  bfm_clear_drives();
  m_axil_bresp = 0; m_axil_rdata = 0; m_axil_rresp = 0;
  forever begin
    @(negedge clk);
    if (rst === 1'b1) begin
      bfm_clear_drives();
      continue;
    end
    if (!bfm_accept) continue;
    // abort the in-flight transaction if reset asserts mid-way
    fork
      bfm_serve_one();
      wait (rst === 1'b1);
    join_any
    disable fork;
    if (rst === 1'b1) bfm_clear_drives();
  end
end
