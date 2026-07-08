# AI_GUIDE — pnp_ip (paste this + one block's HOW_TO_USE.md as model context)

Library of verified SystemVerilog templates. Protocol/infra code is correct and tested; the model edits ONLY fenced regions.

## Hard rules
1. Edit only between `// === USER ... START/END ===` markers. Everything else is read-only.
2. Synthesizable code: no `#delay`, no `initial`, no clock dividers, no bare $display/$finish (only inside `ifdef SIMULATION or `ifdef EMU_FINISH).
3. Declare every signal before first use. `expect` is a reserved word.
4. Reset = async active-low `rst_n`. Clocks are input ports only.
5. always_ff for state, always_comb for muxes. One driver per signal.
6. Testbenches: one tb_*.sv per folder, module name = file name, must print "TB PASS" then $finish.

## Blocks (folder → purpose → main plug point)
- axi_lite_regs → AXI4-Lite register slave → add reg decl + write-case row + read-case row (copy SCRATCH); logic in USER LOGIC
- axi_full_slave → AXI4 burst memory slave (FIXED/INCR/WRAP) → swap BRAM for user memory in USER MEMORY fence
- universal_top → stimulus(LFSR/counter/walking/const) → DUT socket → MISR signature → replace example DUT; contract: exactly 1 resp_valid per stim_valid, fixed latency
- tb_universal → generic self-checking TB template → edit CONFIG / DUT SIGNALS / DUT INSTANCE / TEST SEQUENCE fences
- tb_dpi → TB + DPI-C golden model → add imports in USER DPI IMPORTS, C funcs in golden.c USER C FUNCTIONS
- async_fifo → CDC-safe async FIFO → instantiate only; never edit gray/sync logic
- cdc_pack → cdc_bit_sync / cdc_pulse_sync / cdc_bus_handshake → instantiate only; pick by: level→bit_sync, event→pulse_sync, word→bus_handshake, stream→async_fifo
- axis_src_sink → AXIS LFSR source + MISR sink → splice your stream DUT between src and sink in axis_example_top

## Verify (run after every change)
```
powershell -ExecutionPolicy Bypass -File scripts\run_sim.ps1 <folder>   # must print TB PASS
powershell -ExecutionPolicy Bypass -File scripts\run_synth.ps1 <folder> <top>   # must print SYNTH_OK
```
