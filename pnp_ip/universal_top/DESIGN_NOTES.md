# universal_top — design notes (for humans)

## What it is
The universal hardware bring-up top: stimulus generator → your DUT socket → MISR signature compressor. Drop any DUT into the fenced socket, run N samples, and pass/fail collapses to two things you can see in a waveform or read by force/deposit: `done` and `signature[31:0]`. This is the "every module is a standalone HW bring-up" methodology in one reusable wrapper.

## How it works
- Stimulus (mode pin selectable): 0 = LFSR (taps 32/22/2/1, one 32-bit LFSR per 32-bit lane of DATA_W, lane seeds spread by the golden ratio constant so lanes decorrelate), 1 = up-counter, 2 = walking one, 3 = constant `const_val`. Generators advance **only when a sample is emitted**, so the data sequence is identical regardless of pacing — that's what makes signatures reproducible.
- Pacing: `gap[3:0]` emits one sample every gap+1 cycles (lets you throttle a slow DUT without changing the data).
- Control: rising edge of `start` clears counters, reseeds, re-inits the signature to 0xFFFFFFFF, and runs until NUM_SAMPLES responses. Everything is simple levels/pulses — force/deposit friendly.
- DUT socket (fenced): example plugged in is a registered rotate-XOR. Contract: exactly one `resp_valid` per `stim_valid`, any fixed latency.
- MISR: on each response, `signature <= {sig[30:0], feedback} ^ fold32(resp_data)` (wide data XOR-folded to 32 bits). `done` when `sample_cnt == NUM_SAMPLES`; signature freezes after done. If you set the `EXPECTED_SIG` parameter (from a golden sim run), the `pass` pin does the compare in hardware.

## Hardware bring-up recipe
Force `stim_mode`, `gap`, deposit `start` 0→1, wait for `done`, read `signature`. Same sequence in xsim first to harvest the golden signature, then bake it into `EXPECTED_SIG`.

## How it was verified
Testbench contains an independent behavioral mirror (lane LFSRs + example DUT + MISR as plain functions, generic over lane count) and runs two instances — DATA_W=32 and DATA_W=64 — through all 4 modes × gaps {0,3}. Each configuration runs **twice** via fresh start edges to prove determinism (same signature both times). Also checked: sample_cnt==1024, signature frozen after done, and the `pass` pin exercised for real: the 32-bit instance carries the golden `EXPECTED_SIG=0xD5446A1D` (mode 0), cross-checked against the mirror so it can't go stale. 1 ms watchdog. Result: **TB PASS** at 411 µs. Synthesis: **SYNTH_OK**.

## Exact commands (bash-portable)
```sh
VIVADO=D:/AMDDesignTools/2025.2/Vivado/bin
$VIVADO/xvlog.bat --sv -d SIMULATION path/to/universal_top/*.sv
$VIVADO/xelab.bat tb_universal_top -s snap -debug typical -timescale 1ns/1ps
$VIVADO/xsim.bat snap -runall
$VIVADO/vivado.bat -mode batch -source scripts/synth.tcl -tclargs path/to/universal_top universal_top
```
