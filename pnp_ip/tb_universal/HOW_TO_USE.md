# tb_universal -- generic self-checking testbench template

## WHAT
Reusable xsim testbench skeleton: clock, reset task, watchdog, in-order
scoreboard (expected-value queue), error counter, PASS/FAIL report. Ships with
`example_dut` (2-stage pipelined adder, latency 2) as the swap-out example.
The TB is simulation-only; the DUT must stay synthesizable.

## FILES
- `tb_universal.sv` -- the template. Module name = file name = sim top. Keep exactly ONE `tb_*.sv` in this folder.
- `example_dut.sv`  -- replace with your DUT file. DUT file must NOT start with `tb_`.

## EDIT POINTS (only between these fence markers)
- `// === USER CONFIG START/END ===`        : W, CLK_PERIOD, TIMEOUT, N_TX, DRAIN_CYC
- `// === USER DUT SIGNALS START/END ===`   : one wire per DUT port (clk/rst_n already exist)
- `// === USER DUT INSTANCE START/END ===`  : instantiate your DUT, keep instance name `dut`
- `// === USER TEST SEQUENCE START/END ===` : stimulus loop + output checker

## RULES
- Never edit outside the fences. Scaffolding (clock/reset/watchdog/scoreboard/report) is fixed.
- Scoreboard API: `sb_push(expected)` when you send; `sb_check(observed)` when DUT output is valid. In-order FIFO.
- End the test sequence with `report_and_finish();` -- it prints `TB PASS` or `TB FAIL: N errors` then `$finish`.
- Do not name any variable `expect` (reserved keyword in SystemVerilog).
- Declare every signal/variable before use (xvlog is strict). Declare locals at the top of the `begin` block.
- `` `timescale 1ns/1ps `` stays at the top of the TB.
- Drive DUT inputs with nonblocking `<=` at `@(posedge clk)`; compute expected values from local copies (`ra`, `rb`).

## SIM
From `D:\design_plans\pnp_ip`:
```
powershell -ExecutionPolicy Bypass -File scripts\run_sim.ps1 tb_universal
```
Success = console shows `TB PASS`, exit code 0.

## WAVES
Waveform database: `build\tb_universal\tb_universal.wdb`.
Open: `powershell -ExecutionPolicy Bypass -File scripts\run_sim.ps1 tb_universal -Gui`
or `xsim -gui build\tb_universal\tb_universal.wdb`.

## $finish / $display / $monitor (TB-only, never in the DUT)
- `$finish`: only inside `report_and_finish()` and the watchdog -- i.e. at the END of the test sequence. Do not add extra `$finish` calls mid-test.
- `$display`: anywhere in the TB for debug; error messages should start with `ERROR:` and bump `errors`.
- `$monitor`: optional; call it ONCE, in its own `initial` block inside the USER TEST SEQUENCE fence, e.g. `initial $monitor("%0t in_v=%b a=%h b=%h out_v=%b sum=%h", $time, in_valid, a, b, out_valid, sum);`

## PASTE-READY PROMPT (for a local 7B-27B model)
```
You are editing tb_universal.sv, a SystemVerilog testbench template.
Edit ONLY the code between these fence pairs, leave everything else byte-identical:
  // === USER CONFIG START/END ===
  // === USER DUT SIGNALS START/END ===
  // === USER DUT INSTANCE START/END ===
  // === USER TEST SEQUENCE START/END ===
Task: replace example_dut with the DUT below. Steps:
1. CONFIG: set widths/counts to match the new DUT.
2. DUT SIGNALS: declare one logic per DUT port (clk, rst_n already exist).
3. DUT INSTANCE: instantiate the new DUT as `dut` with explicit port connects.
4. TEST SEQUENCE: drive inputs with <= at @(posedge clk); call sb_push(expected)
   on every send; keep the always block that calls sb_check(<dut output>) when
   the DUT's output-valid signal is high; end with report_and_finish();
Rules: no variable named `expect`; declare before use; TB must print "TB PASS"
then $finish. Output the complete updated tb_universal.sv file only.
DUT source:
<paste DUT here>
```
