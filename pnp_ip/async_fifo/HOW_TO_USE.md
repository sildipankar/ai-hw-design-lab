# async_fifo -- dual-clock FIFO (Cummings gray-pointer style)

WHAT: moves a data stream between two unrelated clock domains. Gray-coded
pointers cross through 2-flop ASYNC_REG synchronizers; full/empty registered
per domain. FWFT read: `rd_data` shows the head word whenever `empty=0`;
assert `rd_en` one `rd_clk` cycle to pop. Depth = 2**DEPTH_LOG2.

## FILES
| file | role |
|---|---|
| async_fifo.sv | synthesizable RTL |
| tb_async_fifo.sv | sim-only self-checking TB (top = tb_async_fifo) |

## PARAMS
| param | default | meaning |
|---|---|---|
| WIDTH | 32 | data width |
| DEPTH_LOG2 | 4 | depth = 2**DEPTH_LOG2 entries (min 2) |

## PORTS
| port | dir | domain | meaning |
|---|---|---|---|
| wr_clk, wr_rst_n | in | write | clock + async active-low reset |
| wr_en | in | write | push wr_data this cycle (ignored when full) |
| wr_data[WIDTH-1:0] | in | write | data in |
| full | out | write | 1 = no space; do not push |
| rd_clk, rd_rst_n | in | read | clock + async active-low reset |
| rd_en | in | read | pop head word this cycle (ignored when empty) |
| rd_data[WIDTH-1:0] | out | read | head word, valid whenever empty=0 (FWFT) |
| empty | out | read | 1 = nothing to read |

## RULES
- Edit ONLY inside the `// === USER PARAMS ===` fence (WIDTH, DEPTH_LOG2).
- NEVER edit: gray-code pointer math, 2-flop synchronizers, `ASYNC_REG`
  attributes, the full/empty equations. They are metastability-safe as is.
- Clocks are inputs. No clock generation or dividers in RTL (Protium rule:
  clocks are tool-generated).
- Release both resets before traffic; each reset is async, per its domain.
- full/empty are pessimistic by ~2 sync cycles. Safe, not a bug.
- Which block for which job: 1-bit level -> cdc_pack/cdc_bit_sync; one-shot
  event -> cdc_pack/cdc_pulse_sync; occasional multi-bit value ->
  cdc_pack/cdc_bus_handshake; STREAMS of words -> this async_fifo.
- FWFT read uses distributed RAM (LUTRAM) on FPGA; keep DEPTH_LOG2 modest.

## SIM
```
powershell -ExecutionPolicy Bypass -File D:\design_plans\pnp_ip\scripts\run_sim.ps1 async_fifo
```
Success = prints `TB PASS`, exit 0.

## WAVES
`build\async_fifo\tb_async_fifo.wdb`
Open: `scripts\run_sim.ps1 async_fifo -Gui` or `xsim -gui build\async_fifo\tb_async_fifo.wdb`

## SYNTH
```
powershell -ExecutionPolicy Bypass -File D:\design_plans\pnp_ip\scripts\run_synth.ps1 async_fifo async_fifo
```

## $finish / $display / $monitor
TB only. Never in RTL, except inside `` `ifdef SIMULATION `` fences
(run_sim.ps1 compiles with `-d SIMULATION`; synthesis does not define it).

## PASTE-READY PROMPT
```
Use D:\design_plans\pnp_ip\async_fifo\async_fifo.sv UNCHANGED. Instantiate:
  async_fifo #(.WIDTH(<W>), .DEPTH_LOG2(<D>)) u_fifo (
    .wr_clk(<src_clk>), .wr_rst_n(<src_rst_n>), .wr_en(<push>),
    .wr_data(<din>), .full(<full>),
    .rd_clk(<dst_clk>), .rd_rst_n(<dst_rst_n>), .rd_en(<pop>),
    .rd_data(<dout>), .empty(<empty>));
Rules: push only when full=0. rd_data is valid whenever empty=0 (FWFT);
assert rd_en one rd_clk cycle to advance. Depth = 2**DEPTH_LOG2 (min
DEPTH_LOG2=2). Do not modify the module internals. Do not generate clocks
in RTL; clocks and per-domain async active-low resets are inputs.
```
