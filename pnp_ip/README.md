# pnp_ip — plug-and-play SystemVerilog blocks

Verified templates: drop in, connect, plug your logic into fenced `USER` sections. Every block simulates to `TB PASS` with xsim and (except TB templates) synthesizes clean before it lands here. Built so 7B–27B local models can fill the fenced regions without breaking the protocol logic around them.

## Blocks
| Folder | What | Synth top |
|---|---|---|
| `axi_lite_regs` | AXI4-Lite slave register block; add regs + logic in fences | `axi_lite_regs` |
| `axi_full_slave` | AXI4 (full) burst slave, FIXED/INCR/WRAP, BRAM-backed | `axi_full_slave` |
| `universal_top` | HW bring-up harness: LFSR/counter/walking/const stimulus → your DUT → MISR signature | `universal_top` |
| `tb_universal` | Generic self-checking TB template (+ example_dut) | sim-only (dut: `example_dut`) |
| `tb_dpi` | TB template with DPI-C golden model (+ mac_dut) | sim-only (dut: `mac_dut`) |
| `async_fifo` | Gray-pointer async FIFO (CDC-safe, Cummings) | `async_fifo` |
| `cdc_pack` | bit sync / pulse sync / bus handshake + example top | `cdc_example_top` |
| `axis_src_sink` | AXI-Stream LFSR source + signature sink; self-tests any stream DUT | `axis_example_top` |

Each folder: `<name>.sv` (synthesizable), one `tb_*.sv` (sim-only), `HOW_TO_USE.md` (for AI — small-model-ready, paste-ready prompt), `DESIGN_NOTES.md` (for humans — how it works, signal walkthrough, what the TB tested, bash-portable commands).

## Conventions
- clk/rst_n are inputs (async active-low reset). No clock dividers in RTL — clocks come from the tool.
- Edit only between `// === USER ... START/END ===` fences.
- Sim-only code in RTL: only inside `` `ifdef SIMULATION `` (sim runner defines it) or `` `ifdef EMU_FINISH `` ($display/$finish bring-up aid, Protium-tolerated).
- One `tb_*.sv` per folder; its module name = file basename = sim top.

## Run
Tools: Vivado 2025.2 at `D:\AMDDesignTools\2025.2\Vivado\bin` (edit path at top of `scripts\run_sim.ps1` / `run_synth.ps1` if it moves).
```powershell
# simulate one block (from pnp_ip\)
powershell -ExecutionPolicy Bypass -File scripts\run_sim.ps1 <folder>
# synthesize one block (out-of-context, construct check)
powershell -ExecutionPolicy Bypass -File scripts\run_synth.ps1 <folder> <top>
# everything
powershell -ExecutionPolicy Bypass -File scripts\run_all.ps1
```
One reusable script each: `run_sim.ps1` globs the folder's `*.sv` (+ `*.c` via xsc for DPI); `synth.tcl` globs and excludes `tb_*.sv`. Default part xc7a35t (construct check only — part-independent); pass a third arg for another part.

## Waveforms
Every batch sim writes `build\<folder>\<tb>.wdb` (all signals logged).
- Interactive: `scripts\run_sim.ps1 <folder> -Gui` (compile + open xsim GUI, then `run all`).
- View a finished run: `D:\AMDDesignTools\2025.2\Vivado\bin\xsim.bat -gui build\<folder>\<tb>.wdb`.
- Stimulus = numbered tests in each TB's final `initial` block; pass criteria = `TB PASS` line and per-check `ok:` lines.

## $finish / $display / $monitor
- TB: `$finish` ends the test sequence; `$display` freely; `$monitor` once per sim in an initial block.
- Synthesizable RTL: never bare. Use the `ifdef fences above. For emulation/prototyping bring-up, `EMU_FINISH`-style blocks ($display + $finish on a done flag) are accepted by Protium as untimed system tasks — keep them out of datapath always blocks.

## For AI use
`AI_GUIDE.md` is the token-optimized index — paste it plus one block's `HOW_TO_USE.md` into a local model as context.
