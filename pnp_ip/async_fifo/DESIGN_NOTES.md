# async_fifo — design notes (for humans)

## What it is
The classic Cummings dual-clock FIFO — the workhorse for moving data streams between clock domains (D2D links, chiplet boundaries, any CDC with throughput). Instantiate it; never edit the pointer logic.

## How it works
- Binary write/read pointers of width DEPTH_LOG2+1 (the extra MSB distinguishes full from empty), converted to Gray code so only one bit changes per increment — safe to synchronize.
- Each Gray pointer crosses into the other domain through a 2-flop synchronizer carrying `(* ASYNC_REG="TRUE" *)` so Vivado packs the flops together and timing analysis treats them as synchronizers.
- `full` (write domain): next write-Gray equals the synced read-Gray with the top two bits inverted — registered, pessimistic-safe. `empty` (read domain): next read-Gray equals synced write-Gray.
- Read side is first-word-fall-through: `rd_data` is combinational `mem[rbin]`, valid whenever `!empty`; `rd_en` consumes.
- Independent async active-low resets per domain; both clocks are inputs (no generation inside). DEPTH_LOG2 minimum is 2.

## How it was verified
7 ns write clock vs 11 ns read clock (odd ratio, so every phase relationship gets exercised). TB drives on negedge and samples/models on posedge — a deliberately race-free pattern. Phase 1: burst fill with reader stalled — `full` asserted after exactly 16 pushes (= depth). Phase 2: 500 pushes at random rate vs pops at random rate, every popped word compared against a queue model. Final checks: popped==500, FIFO and model both empty, `full` was observed. 1 ms watchdog. Result: **TB PASS** at 9.29 µs. Synthesis: **SYNTH_OK**.

## Exact commands (bash-portable)
```sh
VIVADO=D:/AMDDesignTools/2025.2/Vivado/bin
$VIVADO/xvlog.bat --sv -d SIMULATION path/to/async_fifo/*.sv
$VIVADO/xelab.bat tb_async_fifo -s snap -debug typical -timescale 1ns/1ps
$VIVADO/xsim.bat snap -runall
$VIVADO/vivado.bat -mode batch -source scripts/synth.tcl -tclargs path/to/async_fifo async_fifo
```
