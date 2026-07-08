# tb_dpi -- DPI-C testbench template (RTL vs C golden model)

## WHAT
Testbench pattern where a C function (`golden.c`) is the reference model.
Every cycle the TB drives random `en/clr/a/b` into `mac_dut` AND into the C
model, then compares the DUT accumulator against the C result after the edge.
300 random cycles + directed tests. NOTE: this DPI TB is the ONLY deliverable
style that is not synthesizable; `mac_dut.sv` itself IS synthesizable.

## FILES
- `tb_dpi.sv`   -- TB + DPI imports. Module name = file name = sim top. Keep exactly ONE `tb_*.sv`.
- `mac_dut.sv`  -- synthesizable MAC: `acc <= 0` on `clr`, else `acc <= acc + a*b` when `en`.
- `golden.c`    -- C model: `int golden_mac(int acc, int a, int b)`. SV `int` <-> C `int` by value; no `svdpi.h` needed for scalar ints.

## EDIT POINTS (only between these fence markers)
- `tb_dpi.sv`  `// === USER DPI IMPORTS START/END ===` : one `import "DPI-C" function ...;` per new C function
- `tb_dpi.sv`  `// === USER TESTS START/END ===`       : directed tests via `mac_cycle(clr, en, a, b)`
- `golden.c`   `/* === USER C FUNCTIONS START/END === */` : new C reference functions

## RULES
- Never edit outside the fences. Clock, watchdog, `mac_cycle` task, compare logic are fixed.
- Keep `W = 32`: the C model uses 32-bit `int`. Wider needs svdpi.h open arrays -- out of scope here.
- Do not name any variable `expect` (reserved keyword). Declare before use (xvlog is strict).
- `` `timescale 1ns/1ps `` stays at the top of the TB.
- Every added C function needs a matching `import "DPI-C"` line before first call.

## SIM
One-liner, from `D:\design_plans\pnp_ip`:
```
powershell -ExecutionPolicy Bypass -File scripts\run_sim.ps1 tb_dpi
```
Raw xsim commands (run from an empty build dir, files copied/pathed in):
```
xvlog --sv -d SIMULATION *.sv
xsc golden.c
xelab tb_dpi -s tb_dpi_snap -debug typical -timescale 1ns/1ps -sv_lib dpi
xsim tb_dpi_snap -runall
```
Success = console shows `TB PASS`, exit code 0.

## WAVES
Waveform database: `build\tb_dpi\tb_dpi.wdb`.
Open: `powershell -ExecutionPolicy Bypass -File scripts\run_sim.ps1 tb_dpi -Gui`
or `xsim -gui build\tb_dpi\tb_dpi.wdb`.

## $finish / $display / $monitor (TB-only, never in the DUT)
- `$finish`: at the END of the test sequence, right after the `TB PASS`/`TB FAIL` print (plus the fixed watchdog). No extra `$finish` mid-test.
- `$display`: anywhere in the TB; error prints start with `ERROR:` and bump `errors`.
- `$monitor`: optional; call ONCE in its own `initial` block inside the USER TESTS fence, e.g. `initial $monitor("%0t clr=%b en=%b a=%h b=%h acc=%h", $time, clr, en, a, b, acc);`

## PASTE-READY PROMPT (for a local 7B-27B model)
```
You are editing tb_dpi.sv and golden.c, a SystemVerilog + DPI-C testbench pair.
Edit ONLY code between these fence pairs, leave everything else byte-identical:
  tb_dpi.sv : // === USER DPI IMPORTS START/END ===
  tb_dpi.sv : // === USER TESTS START/END ===
  golden.c  : /* === USER C FUNCTIONS START/END === */
Task: <describe the new checks or reference functions>.
Rules:
- New C functions use plain int args/returns (SV int <-> C int, no svdpi.h).
- Each new C function gets one line in USER DPI IMPORTS:
  import "DPI-C" function int <name>(input int ...);
- Directed tests call mac_cycle(clr, en, a, b); it drives the DUT, updates the
  C mirror, and self-checks after the clock edge.
- No variable named `expect`; declare before use; keep the final TB PASS /
  TB FAIL prints and $finish unchanged.
Output the complete updated file(s) only.
```
