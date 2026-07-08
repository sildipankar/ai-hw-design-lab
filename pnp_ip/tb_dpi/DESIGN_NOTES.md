# tb_dpi — design notes (for humans)

## What it is
The DPI-C testbench pattern: RTL checked against a C golden model, cycle by cycle. Use it whenever the reference behavior is easier to write (or already exists) in C — ISA models, math kernels, protocol references. This is the one deliverable style in the library that is sim-only.

## How it works
- `golden.c` — plain C: `int golden_mac(int acc, int a, int b) { return acc + a*b; }`. For scalar int arguments no `svdpi.h` is needed; SV `int` maps directly to C `int`. A `USER C FUNCTIONS` fence marks where to add more.
- `tb_dpi.sv` — `import "DPI-C" function int golden_mac(...)` plus a `mac_cycle()` task that drives the DUT, advances the C mirror, and compares `acc` after every clock edge. Fences: `USER DPI IMPORTS`, `USER TESTS`.
- `mac_dut.sv` — the synthesizable DUT under check: `acc <= 0` on `clr`, else `acc + a*b` when `en`.
The extra build step vs a normal TB: `xsc` compiles the C into a shared library (default name `dpi`), and `xelab` links it with `-sv_lib dpi`. `run_sim.ps1` detects `.c` files and does this automatically.

## How it was verified
300 random en/clr/a/b cycles plus directed corner tests; DUT accumulator compared against the C mirror after every edge. 1 ms watchdog. Result: **TB PASS** at 3096 ns. `mac_dut` synthesized separately: **SYNTH_OK**.

## Exact commands (bash-portable) — note the xsc step
```sh
VIVADO=D:/AMDDesignTools/2025.2/Vivado/bin
$VIVADO/xvlog.bat --sv -d SIMULATION path/to/tb_dpi/*.sv
$VIVADO/xsc.bat path/to/tb_dpi/golden.c            # C -> xsim.dir/xsc/dpi.dll
$VIVADO/xelab.bat tb_dpi -s snap -debug typical -timescale 1ns/1ps -sv_lib dpi
$VIVADO/xsim.bat snap -runall
$VIVADO/vivado.bat -mode batch -source scripts/synth.tcl -tclargs path/to/tb_dpi mac_dut
```
