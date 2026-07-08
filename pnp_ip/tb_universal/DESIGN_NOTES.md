# tb_universal — design notes (for humans)

## What it is
A generic self-checking testbench skeleton, delivered working against a small example DUT. When you write a new module, copy this folder, swap the DUT, and edit only the four fenced regions — clocking, watchdog, scoreboard, and reporting are already done and known-good.

## How it works
Fixed scaffolding (don't edit): clock generator, `do_reset` task, timeout watchdog (`TIMEOUT`, default 1 ms → prints TB FAIL instead of hanging), an in-order scoreboard (push expected values into a queue when you drive, pop+compare when the DUT responds), an error counter, and `report_and_finish` which prints `TB PASS` / `TB FAIL: N errors` then `$finish`.
Editable fences: `USER CONFIG` (widths, clock period, transaction count), `USER DUT SIGNALS`, `USER DUT INSTANCE`, `USER TEST SEQUENCE`.
The example DUT (`example_dut.sv`, synthesizable) is a 2-stage pipelined adder — latency 2, valid pipelined alongside — chosen so the scoreboard pattern for a pipelined DUT is visible by imitation.

## How it was verified
The template runs as-is: 200 random a/b pairs with random 0–3 cycle gaps between transactions; expected `a+b` pushed on send, popped and compared on each `out_valid`. Result: **TB PASS** at 5265 ns (200/200 checked). `example_dut` also synthesized: **SYNTH_OK**. (The TB itself is sim-only by nature.)

## Exact commands (bash-portable)
```sh
VIVADO=D:/AMDDesignTools/2025.2/Vivado/bin
$VIVADO/xvlog.bat --sv -d SIMULATION path/to/tb_universal/*.sv
$VIVADO/xelab.bat tb_universal -s snap -debug typical -timescale 1ns/1ps
$VIVADO/xsim.bat snap -runall
$VIVADO/vivado.bat -mode batch -source scripts/synth.tcl -tclargs path/to/tb_universal example_dut
```
