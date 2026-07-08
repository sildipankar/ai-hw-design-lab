# axis_src_sink

## WHAT
Synthesizable AXI-Stream traffic generator (LFSR data) + signature sink (MISR + counters) for FPGA-prototype bring-up. Drop them around any streaming DUT; the 32-bit `signature` proves data integrity without storing or comparing payloads. Data advances only on handshakes, so the signature is throttle/backpressure-independent: a golden sim and hardware always agree.

## FILES
| file | role |
|---|---|
| `axis_src_sink.sv` | synthesizable: `axis_lfsr_src`, `axis_sig_sink`, `axis_example_top` |
| `tb_axis_src_sink.sv` | sim-only self-checking TB (top = file basename) |
| `HOW_TO_USE.md` | this file |

## PARAMS
| param | default | applies to | meaning |
|---|---|---|---|
| `DATA_W` | 32 | src, sink, top | stream width, must be multiple of 32 |
| `SEED` | 32'h1EDC_2026 | src, top | data LFSR base seed, nonzero; lane i seed = `SEED ^ i*32'h9E3779B9` |
| `PKT_BEATS` | 16 | src, top | beats per packet (`tlast` on last) |
| `NUM_PKTS` | 8 | src, top | packets per run |
| `THROTTLE` | 1 | src, sink, top | 1 = LFSR-gated valid/ready (~50%), 0 = full rate |
| `TSEED` | 32'hBEEF_0107 | sink | ready-throttle LFSR seed, nonzero |

## PORTS
All modules: `clk`, `rst_n` (async active-low) are inputs — clock comes from outside (tool-generated on Protium), no dividers/gen inside.

`axis_lfsr_src`: `start` (rising edge = reset counters+seeds, run), master `m_tvalid/m_tready/m_tdata/m_tlast`, `busy` (sending), `done` (set after last beat, cleared by next start).

`axis_sig_sink`: `clear` (sync level: signature<=32'hFFFF_FFFF, counters<=0), slave `s_tvalid/s_tready/s_tdata/s_tlast`, `signature[31:0]`, `beat_cnt[31:0]`, `pkt_cnt[31:0]`. `s_tready` is registered; LFSR-throttled when `THROTTLE=1`.

`axis_example_top`: `clk, rst_n, start, done, signature, beat_cnt, pkt_cnt`. Src wired straight to sink; a start rising edge internally pulses the sink's `clear`, so every start gives a fresh deterministic signature.

Signature math (for mirrors): per handshake `fb = sig[31]^sig[21]^sig[1]^sig[0]; sig <= {sig[30:0],fb} ^ fold32(tdata)`; data LFSR taps 32,22,2,1 XOR per 32-bit lane.

## TYPICAL USE
1. Splice your streaming DUT into `axis_example_top` at the `// === USER DUT ... ===` fence (replace the 4 pass-through assigns: `src_*` -> DUT slave, DUT master -> `snk_*`).
2. Golden sim first: run the TB (or your own) and note EXPECTED `signature`, `beat_cnt`, `pkt_cnt`.
3. In hardware: force `start` 0->1 (deposit/force), wait for `done`, read `signature/beat_cnt/pkt_cnt` in waves. Match vs golden = pass.
4. Re-run anytime: new `start` edge re-seeds src and clears sink — same numbers every run.

## RULES
- AXIS invariants (src obeys, SVA-checked in TB): once `tvalid=1` it stays 1 with stable `tdata/tlast` until `tready=1`; valid must not wait for ready. Sink `tready` may toggle freely.
- No `tkeep/tstrb/tid/tuser`: all beats are full-width. To add `tkeep`, add the port on src (`assign m_tkeep = '1;`), pass it through the USER DUT fence, and on the sink fold it into the MISR next to `fold32(s_tdata)` (e.g. `^ 32'(s_tkeep)`) if your DUT modifies it.
- `DATA_W % 32 == 0`; `SEED`/`TSEED` nonzero (all-zero LFSR locks).
- Edit only inside `// === USER ... ===` fences (throttle profile, ready profile, DUT splice).
- Sim-only code must sit inside `` `ifdef SIMULATION ``; don't name anything `expect` (reserved in xvlog); declare before use.

## SIM
```
powershell -ExecutionPolicy Bypass -File D:\design_plans\pnp_ip\scripts\run_sim.ps1 axis_src_sink
```
Passes when it prints `TB PASS` then `$finish`.

## WAVES
`build\axis_src_sink\tb_axis_src_sink.wdb`. Open: `scripts\run_sim.ps1 axis_src_sink -Gui`, or `xsim -gui build\axis_src_sink\tb_axis_src_sink.wdb`.

## SYNTH
```
powershell -ExecutionPolicy Bypass -File D:\design_plans\pnp_ip\scripts\run_synth.ps1 axis_src_sink axis_example_top
```
Reports in `build\synth_axis_src_sink\`.

## $finish / $monitor RULES
- TB must print `TB PASS` (0 errors) or `TB FAIL: ...` and then call `$finish` exactly once; keep the `#1ms` watchdog that also `$finish`es.
- No `$monitor` — use targeted `$display` per check ("  ok: ..." / "ERROR: ...", bump `errors`).
- RTL: `$display/$finish` only inside `` `ifdef `` fences (see `EMU_FINISH` pattern in `axi_lite_regs`), never in datapath always blocks.

## PASTE-READY PROMPT (small models)
```
You are editing D:\design_plans\pnp_ip\axis_src_sink\axis_src_sink.sv (SystemVerilog, Vivado xsim/synth).
Rules: edit ONLY inside // === USER ... === fences; keep everything synthesizable;
clk/rst_n are inputs (async active-low reset, no clock generation); AXIS invariant:
once tvalid=1 hold tvalid/tdata/tlast stable until tready=1; declare signals before
use; never use the name "expect"; sim-only code goes inside `ifdef SIMULATION.
Task: replace the 4 pass-through assigns in the USER DUT fence of axis_example_top
with my streaming DUT <module> (src_* feed its slave port, its master port feeds snk_*).
Then verify: powershell -ExecutionPolicy Bypass -File scripts\run_sim.ps1 axis_src_sink
must print "TB PASS". If it fails, fix and rerun until it passes.
```
