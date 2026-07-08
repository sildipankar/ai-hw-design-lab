# universal_top — universal HW bring-up top

WHAT: stimulus generator -> plug-in DUT socket -> MISR signature checker, in one
synthesizable module. Drop your DUT in the fenced socket, run N samples, read one
32-bit `signature`. All controls are simple levels/values -> force/deposit friendly
on Protium, no bus master needed. Deterministic: same mode+seed => same signature,
independent of `gap`.

## FILES
| file | role |
|---|---|
| universal_top.sv | synthesizable top; edit only fenced sections |
| tb_universal_top.sv | sim-only self-checking TB (behavioral mirror, 32b+64b instances) |
| HOW_TO_USE.md | this file |

## PARAMS
| param | default | meaning |
|---|---|---|
| DATA_W | 32 | stimulus/response width (32-bit lanes, ceil(DATA_W/32)) |
| LFSR_SEED | 32'hACE1_2026 | base seed, must be nonzero; lane seed = SEED ^ lane*32'h9E3779B9 |
| NUM_SAMPLES | 1024 | samples per run |
| EXPECTED_SIG | 0 | golden signature; 0 = disable pass check |

## PORTS
| port | dir | width | meaning |
|---|---|---|---|
| clk, rst_n | in | 1 | external clock + async active-low reset (no dividers inside) |
| start | in | 1 | level; RISING EDGE clears counters/signature, reseeds, runs |
| stim_mode | in | 2 | 0=LFSR 1=counter(from 0) 2=walking-one(from bit0) 3=const_val |
| const_val | in | DATA_W | data for mode 3 |
| gap | in | 4 | 1 sample per gap+1 cycles (0 = back-to-back) |
| done | out | 1 | sample_cnt == NUM_SAMPLES; signature final |
| pass | out | 1 | done && EXPECTED_SIG!=0 && signature==EXPECTED_SIG |
| signature | out | 32 | MISR over DUT responses (init 32'hFFFF_FFFF at start edge) |
| sample_cnt | out | 32 | responses accumulated |

## PLUG-IN POINTS (edit ONLY between these fences)
- `// === USER DUT SOCKET START/END ===` — replace the example DUT
  (rotl1 XOR identity, latency 1). DUT CONTRACT:
  - in: `stim_valid`/`stim_data[DATA_W-1:0]`; with gap=0 samples are back-to-back —
    set `gap` >= your DUT's initiation interval if it can't take 1/cycle.
  - out: `resp_valid`/`resp_data[DATA_W-1:0]`; exactly ONE resp per stim, in order,
    any fixed latency. Declare new internal signals at the top of the fence,
    before first use (xvlog is strict).
- `// === USER PORTS START/END ===` — extra DUT I/O; prefix each new line with a comma.

## RULES
- Synthesizable RTL only; sim-only code only inside `` `ifdef SIMULATION ``.
- `` `timescale `` in TB only, never in RTL.
- clk/rst_n come from outside (tool-generated clock); NO clock dividers in RTL.
- Do not edit stimulus/MISR machinery — only the fenced sections.
- Restart (new start edge) only after `done`; mid-run restart can catch in-flight
  responses from DUTs with latency > 1.
- Changing the example DUT invalidates TB golden `GOLD32` and mirror `resp` line —
  update both in tb_universal_top.sv.

## SIM
```
powershell -ExecutionPolicy Bypass -File D:\design_plans\pnp_ip\scripts\run_sim.ps1 universal_top
```
Must print `TB PASS`. TB checks: RTL signature vs behavioral mirror for modes 0-3,
gaps {0,3}, DATA_W 32 and 64, re-run determinism, sample_cnt, pass semantics.

## WAVES
`build\universal_top\tb_universal_top.wdb`.
Open: `scripts\run_sim.ps1 universal_top -Gui` or `xsim -gui <wdb>`.

## SYNTH
```
powershell -ExecutionPolicy Bypass -File D:\design_plans\pnp_ip\scripts\run_synth.ps1 universal_top universal_top
```

## HW BRING-UP RECIPE (Protium force/deposit)
1. deposit `stim_mode`, `gap` (and `const_val` for mode 3); `start`=0.
2. deposit `start`=1 (rising edge = clear + run).
3. watch waveform: `done` high, then read `signature`, `sample_cnt`.
4. golden flow: run sim first, note end-of-run `signature`, rebuild with
   `EXPECTED_SIG=<that value>` -> on HW just check the `pass` pin.
5. re-run: deposit `start`=0 then 1.
6. optional: compile with `-d EMU_FINISH` -> on `done` the block $displays
   `universal_top: DONE samples=.. signature=.. pass=..` and $finishes.

## $finish / $display RULES
- RTL: only inside the `` `ifdef EMU_FINISH `` block (untimed, on `done`), never in
  datapath always blocks. Sim-only debug goes in `` `ifdef SIMULATION ``.
- TB: exactly one `TB PASS`/`TB FAIL` then `$finish`; watchdog `#1ms` -> `TB FAIL`.
  Prefer $display at checkpoints over free-running $monitor (log noise).

## PASTE-READY PROMPT (small local models)
```
You are editing universal_top.sv, a bring-up harness: stimulus gen -> USER DUT
SOCKET -> MISR. Edit ONLY between // === USER DUT SOCKET START === and END (and
USER PORTS fence for new I/O). Keep this contract: consume stim_valid/stim_data
[DATA_W-1:0]; produce exactly one resp_valid/resp_data [DATA_W-1:0] per stimulus,
in order, fixed latency. Declare signals before use. Synthesizable SV only: no
initial blocks, no delays, no timescale, no clock dividers; use
always_ff @(posedge clk or negedge rst_n) with async active-low reset. Sim-only
code only inside `ifdef SIMULATION. Task: <describe DUT here>.
```
