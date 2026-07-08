# axi_lite_regs — design notes (for humans)

## What it is
A complete AXI4-Lite slave with a small register file. You bolt it onto any AXI-Lite master (VIP, processor, or force/deposit in emulation) and get working registers immediately. The point: the protocol handshaking is already correct and proven, so you (or a small model) only ever add registers and logic inside the fenced sections.

## How it works
Write path: AW and W channels are captured independently into `awaddr_q`/`wdata_q` with `aw_pend`/`w_pend` flags — so the master can send address and data in either order, with any gap. When both are present and the B channel is free, the write "fires" (`wr_fire`): one case-statement row per register applies the data (byte strobes honored via `apply_wstrb`), then BVALID goes up until BREADY.
Read path: single outstanding — ARREADY is simply `!RVALID`. On AR handshake the combinational read mux is registered into RDATA and RVALID rises. All responses are OKAY.
Unmapped reads return `0xDEADBEEF` so a bad address is instantly visible in a waveform.

## Signals in one pass
- `clk/rst_n` — one clock, async active-low reset. No dividers inside (tool-generated clocks per our Protium methodology).
- `s_axil_aw*/w*/b*/ar*/r*` — standard AXI4-Lite; nothing optional, nothing missing.
- `gpio_in[31:0]` — sampled directly by a RO register (assumes same clock domain).
- `gpio_out[31:0]` — driven from a RW register; free "is it alive" output.
Register map is in the file header and HOW_TO_USE.md (ID at 0x00 = 0xCAFE0100 — read that first when bringing up hardware).

## How it was verified
Testbench `tb_axi_lite_regs.sv` acts as an AXI-Lite master with two tasks (`axil_write` with adjustable AW/W skew, `axil_read`). Test order:
1. Read ID (0xCAFE0100) — proves basic read path.
2. SCRATCH write/read-back.
3. Byte-strobe write (wstrb=0100 — only byte 2 changes; merge checked).
4. W sent 3 cycles before AW, then AW 3 cycles before W — proves channel-order independence.
5. GPIO_OUT drives the pin; GPIO_IN pin read back through the register.
6. Example user logic: OPA=7, OPB=6, CTRL.enable → RESULT=42, STATUS.done=1.
7. Unmapped address read = 0xDEADBEEF.
100 µs watchdog. Result: **TB PASS** at 575 ns. Synthesis: **SYNTH_OK**, 0 errors / 0 critical warnings (xc7a35t, out-of-context).

## Exact commands (bash-portable)
```sh
VIVADO=D:/AMDDesignTools/2025.2/Vivado/bin   # .bat wrappers run fine from git-bash
cd build_dir
$VIVADO/xvlog.bat --sv -d SIMULATION path/to/axi_lite_regs/*.sv
$VIVADO/xelab.bat tb_axi_lite_regs -s snap -debug typical -timescale 1ns/1ps
$VIVADO/xsim.bat snap -runall                      # batch; prints TB PASS
# waveform: xsim snap -tclbatch scripts/xsim_run.tcl -wdb out.wdb ; view: xsim -gui out.wdb
$VIVADO/vivado.bat -mode batch -source scripts/synth.tcl -tclargs path/to/axi_lite_regs axi_lite_regs
```
