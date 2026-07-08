# axis_src_sink — design notes (for humans)

## What it is
An AXI-Stream traffic generator and a signature-checking sink. Drop them on either side of any streaming block and it self-tests in hardware: run, wait for `done`, compare `signature` against the golden from simulation. `axis_example_top` wires source straight to sink and has a fenced splice point where your DUT goes in between.

## How it works
- `axis_lfsr_src` — data LFSR (per-32-bit lane, taps 32/22/2/1) advances **only on a completed handshake**, so the data sequence is independent of backpressure — the property that makes signatures reproducible. A second, free-running throttle LFSR randomizes `tvalid`, but AXIS-compliantly: once `tvalid` is up it holds until `tready` (throttling is only reconsidered after a beat completes). `tlast` marks each PKT_BEATS-th beat; `done` after NUM_PKTS packets. Rising `start` reseeds and reruns — every run identical.
- `axis_sig_sink` — registered `s_tready`, LFSR-throttled when enabled (AXIS lets ready toggle freely). On each accepted beat: MISR update (`{sig[30:0],fb} ^ fold32(tdata)`, init 0xFFFFFFFF on `clear`), beat counter, packet counter on `tlast`.
- No `tkeep` (word-aligned payloads); the HOW_TO_USE notes how to add it.

## How it was verified
Both throttles on — random valid gaps against random ready backpressure, the worst-case handshake soup. A behavioral mirror of the data LFSR + MISR predicts the signature for 8 packets × 16 beats = 128 beats: `0xBE7E00B1`, matched by the DUT. An SVA assertion checks the AXIS hold rule the whole time (`tvalid && !tready |=> tvalid && $stable(tdata) && $stable(tlast)`). Counters checked (128 beats, 8 packets). Then a second `start`+`clear` run reproduces the exact signature — determinism proven. 1 ms watchdog. Result: **TB PASS** at 7865 ns. Synthesis: **SYNTH_OK** (`axis_example_top`, zero warnings).

## Exact commands (bash-portable)
```sh
VIVADO=D:/AMDDesignTools/2025.2/Vivado/bin
$VIVADO/xvlog.bat --sv -d SIMULATION path/to/axis_src_sink/*.sv
$VIVADO/xelab.bat tb_axis_src_sink -s snap -debug typical -timescale 1ns/1ps
$VIVADO/xsim.bat snap -runall
$VIVADO/vivado.bat -mode batch -source scripts/synth.tcl -tclargs path/to/axis_src_sink axis_example_top
```
