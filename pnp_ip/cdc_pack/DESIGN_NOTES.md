# cdc_pack — design notes (for humans)

## What it is
The three CDC primitives you reach for constantly, in one file, plus `cdc_example_top` showing all three wired between two domains (also the synth top). Rule of thumb: level → `cdc_bit_sync`; single event → `cdc_pulse_sync`; a whole word → `cdc_bus_handshake`; a continuous stream → use `async_fifo` instead (the handshake costs several cycles per word).

## How it works
- `cdc_bit_sync #(STAGES=2, WIDTH=1)` — plain flop chain in the destination domain with `ASYNC_REG="TRUE"`. Only for quasi-static levels; independent bits of a bus may arrive skewed (that's why buses go through the handshake, not this).
- `cdc_pulse_sync` — a pulse can't cross domains directly (might be missed or doubled), so the source flips a toggle flop; the toggle is bit-synced; an edge detector in the destination re-creates a 1-cycle pulse. Pulses must be spaced a few destination clocks apart.
- `cdc_bus_handshake #(WIDTH=32)` — 4-phase, toggle-based: source captures data and flips `req`; data stays frozen while in flight (so the bus crosses as quasi-static — safe); destination sees the synced `req` edge, captures data, pulses `dst_valid` for one cycle, flips `ack`; source is ready again when synced `ack` matches `req`.

## How it was verified
7 ns / 13 ns clocks on `cdc_example_top`, three tests running concurrently: 50 random words through the bus handshake (respecting `src_ready`, queue-compared on `dst_valid`); 20 pulses spaced 70 ns through the pulse sync, all 20 counted, none doubled; level toggles through the bit sync each observed within 3 destination clocks. 1 ms watchdog. Result: **TB PASS** at 2.71 µs. Synthesis: **SYNTH_OK** (`cdc_example_top`).

## Exact commands (bash-portable)
```sh
VIVADO=D:/AMDDesignTools/2025.2/Vivado/bin
$VIVADO/xvlog.bat --sv -d SIMULATION path/to/cdc_pack/*.sv
$VIVADO/xelab.bat tb_cdc_pack -s snap -debug typical -timescale 1ns/1ps
$VIVADO/xsim.bat snap -runall
$VIVADO/vivado.bat -mode batch -source scripts/synth.tcl -tclargs path/to/cdc_pack cdc_example_top
```
