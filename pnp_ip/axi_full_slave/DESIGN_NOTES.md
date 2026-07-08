# axi_full_slave — design notes (for humans)

## What it is
A full AXI4 (not Lite) memory slave: bursts, IDs, all three burst types, backed by a 4 KB BRAM. Use it wherever you need "some AXI4 memory on the other side" — DMA bring-up, interconnect checkout, or as the template when your own block must present a burst-capable slave port.

## How it works
Two completely independent FSMs, so a write burst and a read burst can be in flight at the same time (one outstanding transaction per direction — simple on purpose).
- Write FSM: `IDLE` (AWREADY high, capture id/addr/len/size/burst) → `DATA` (WREADY high; each WVALID beat writes memory honoring per-byte WSTRB, address advances by `next_addr()`) → on WLAST → `RESP` (BVALID with captured BID, OKAY) → back to IDLE.
- Read FSM: `IDLE` (ARREADY) → `MEM` (one cycle for the registered BRAM read — that's what lets Vivado infer block RAM) → `DATA` (RVALID; RLAST when beat==len) → next beat back to `MEM`. So reads run at 2 cycles/beat; fine for bring-up, and the notes say where to add a skid stage if you ever need full throughput.
- `next_addr()` handles FIXED (same address), INCR (+bytes), WRAP (wraps at the aligned boundary: base = addr & ~(total_bytes−1)).
- `awlock/awcache/awprot` (and AR equivalents) are accepted and ignored — commented as such.
- The `USER MEMORY` fence marks exactly where to rip out the BRAM and connect your own memory or register file (contract: `mem_we/w_word` in, `r_word→rdata_q` out).

## How it was verified
Testbench drives a real AXI master with a mirror model memory. Tests: INCR bursts len 0/7/15; WRAP len 3 starting mid-boundary at 0x308 (wrap order additionally double-checked with a linear INCR read-back); FIXED len 3; partial-WSTRB write (lanes 0 and 2 only); random data throughout; random WVALID gaps and RREADY backpressure; and a fork/join concurrent write+read burst to prove the two FSMs really are independent. 100 µs watchdog. Result: **TB PASS** at 3125 ns. Synthesis: **SYNTH_OK**, memory mapped to block RAM (visible in the utilization report).

## Exact commands (bash-portable)
```sh
VIVADO=D:/AMDDesignTools/2025.2/Vivado/bin
$VIVADO/xvlog.bat --sv -d SIMULATION path/to/axi_full_slave/*.sv
$VIVADO/xelab.bat tb_axi_full_slave -s snap -debug typical -timescale 1ns/1ps
$VIVADO/xsim.bat snap -runall
$VIVADO/vivado.bat -mode batch -source scripts/synth.tcl -tclargs path/to/axi_full_slave axi_full_slave
```
