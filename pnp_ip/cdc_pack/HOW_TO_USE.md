# cdc_pack -- clock-domain-crossing primitives (bit / pulse / bus)

WHAT: one file, four modules for safe signal crossing between unrelated
clock domains: `cdc_bit_sync` (level), `cdc_pulse_sync` (strobe),
`cdc_bus_handshake` (multi-bit word), `cdc_example_top` (synth top wiring
all three, use it as the instantiation example).

## FILES
| file | role |
|---|---|
| cdc_pack.sv | synthesizable RTL, 4 modules |
| tb_cdc_pack.sv | sim-only self-checking TB (top = tb_cdc_pack) |

## WHICH PRIMITIVE
| you need to cross | use | latency/throughput |
|---|---|---|
| 1-bit level, slow status | cdc_bit_sync | STAGES dst clks |
| 1-cycle event/strobe | cdc_pulse_sync | ~3 dst clks; space pulses > 3 dst periods |
| multi-bit value, occasional | cdc_bus_handshake | one word per ~(3 src + 3 dst) clks |
| multi-bit STREAM | ../async_fifo | 1 word/clk sustained |

`cdc_bus_handshake` takes several cycles in BOTH domains per word. NEVER use
it for streaming data -- use async_fifo.

## PORTS / PARAMS
cdc_bit_sync `#(STAGES=2, WIDTH=1)`
| port | dir | meaning |
|---|---|---|
| dst_clk | in | destination clock (no reset by design) |
| din[WIDTH-1:0] | in | async input from other domain |
| dout[WIDTH-1:0] | out | din synced to dst_clk (STAGES cycles later) |

WIDTH>1 only for quasi-static or gray-coded buses (bits can skew).

cdc_pulse_sync (no params)
| port | dir | meaning |
|---|---|---|
| src_clk, src_rst_n, src_pulse | in | 1-cycle strobe in src domain |
| dst_clk, dst_rst_n | in | dst domain clock/reset |
| dst_pulse | out | 1-cycle strobe in dst domain |

cdc_bus_handshake `#(WIDTH=32)`
| port | dir | meaning |
|---|---|---|
| src_clk, src_rst_n | in | src domain clock/reset |
| src_valid | in | request send; fires when src_ready=1 |
| src_ready | out | 1 = idle; word accepted on valid&ready |
| src_data[WIDTH-1:0] | in | word to send (captured on accept) |
| dst_clk, dst_rst_n | in | dst domain clock/reset |
| dst_valid | out | 1-cycle strobe: dst_data is fresh |
| dst_data[WIDTH-1:0] | out | received word (held until next one) |

cdc_example_top: clk_a/rst_a_n -> clk_b/rst_b_n; a_level->b_level (bit_sync),
a_pulse->b_pulse (pulse_sync), a_valid/a_ready/a_data->b_valid/b_data
(bus_handshake, 32-bit).

## RULES
- Edit ONLY inside `// === USER PARAMS ===` fences (STAGES, WIDTH).
- NEVER edit: synchronizer stages, `ASYNC_REG` attributes, toggle/edge-detect
  logic, req/ack handshake. They are metastability-safe as is.
- Clocks are inputs. No clock generation or dividers in RTL (Protium rule).
- Async active-low reset per domain; release both before traffic.
- bus_handshake: hold rules are built in (data_hold stays stable in flight);
  just respect src_ready.
- pulse_sync: pulses closer than ~3 dst periods merge/get lost by design.

## SIM
```
powershell -ExecutionPolicy Bypass -File D:\design_plans\pnp_ip\scripts\run_sim.ps1 cdc_pack
```
Success = prints `TB PASS`, exit 0.

## WAVES
`build\cdc_pack\tb_cdc_pack.wdb`
Open: `scripts\run_sim.ps1 cdc_pack -Gui` or `xsim -gui build\cdc_pack\tb_cdc_pack.wdb`

## SYNTH
```
powershell -ExecutionPolicy Bypass -File D:\design_plans\pnp_ip\scripts\run_synth.ps1 cdc_pack cdc_example_top
```

## $finish / $display / $monitor
TB only. Never in RTL, except inside `` `ifdef SIMULATION `` fences
(run_sim.ps1 compiles with `-d SIMULATION`; synthesis does not define it).

## PASTE-READY PROMPT
```
Use D:\design_plans\pnp_ip\cdc_pack\cdc_pack.sv UNCHANGED. Pick ONE primitive
per crossing: 1-bit level -> cdc_bit_sync #(.STAGES(2), .WIDTH(1))
(.dst_clk, .din, .dout); 1-cycle strobe -> cdc_pulse_sync (.src_clk,
.src_rst_n, .src_pulse, .dst_clk, .dst_rst_n, .dst_pulse); occasional
multi-bit word -> cdc_bus_handshake #(.WIDTH(32)) (.src_clk, .src_rst_n,
.src_valid, .src_ready, .src_data, .dst_clk, .dst_rst_n, .dst_valid,
.dst_data) -- drive src_valid only when src_ready=1; throughput is one word
per several cycles, so use async_fifo for streams. Copy wiring style from
cdc_example_top. Do not modify module internals, sync stages, or ASYNC_REG.
Do not generate clocks in RTL; clocks and per-domain async active-low resets
are inputs.
```
