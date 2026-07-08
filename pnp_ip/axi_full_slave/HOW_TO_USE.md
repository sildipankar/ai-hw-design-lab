# axi_full_slave

WHAT: AXI4 (full) burst memory slave — FIXED/INCR/WRAP bursts into an internal BRAM; swap the BRAM for your own memory/registers in one fenced region.

## FILES
- `axi_full_slave.sv` — synthesizable RTL (protocol engine + fenced USER MEMORY)
- `tb_axi_full_slave.sv` — sim-only self-checking TB (prints `TB PASS`)
- `HOW_TO_USE.md` — this file

## PARAMS
| name | default | meaning |
|---|---|---|
| ID_W | 4 | AXI ID width |
| ADDR_W | 12 | byte address width (4KB window) |
| DATA_W | 32 | data bus width; memory = 2^(ADDR_W-2) x 32b words |

## PORTS (all AXI ports prefixed `s_axi_`)
| name | dir | width | desc |
|---|---|---|---|
| clk | in | 1 | clock (tool-generated, from outside) |
| rst_n | in | 1 | async active-low reset |
| awid | in | ID_W | write burst ID (echoed on bid) |
| awaddr | in | ADDR_W | write start byte address |
| awlen | in | 8 | beats-1 |
| awsize | in | 3 | bytes/beat = 2^awsize (use 3'd2 for 32b) |
| awburst | in | 2 | 00 FIXED, 01 INCR, 10 WRAP |
| awlock / awcache / awprot | in | 1/4/3 | accepted, ignored |
| awvalid / awready | in/out | 1 | AW handshake |
| wdata | in | DATA_W | write data |
| wstrb | in | DATA_W/8 | byte lane enables |
| wlast | in | 1 | final beat marker (ends the burst) |
| wvalid / wready | in/out | 1 | W handshake |
| bid | out | ID_W | = latched awid |
| bresp | out | 2 | always 00 OKAY |
| bvalid / bready | out/in | 1 | B handshake |
| ar* | in | — | mirror of aw* (arid araddr arlen arsize arburst arlock arcache arprot arvalid arready) |
| rid | out | ID_W | = latched arid |
| rdata | out | DATA_W | read data |
| rresp | out | 2 | always 00 OKAY |
| rlast | out | 1 | high on final beat |
| rvalid / rready | out/in | 1 | R handshake |

## PLUG-IN POINTS
Edit ONLY between these exact markers in `axi_full_slave.sv`:
- `// USER MEMORY START` ... `// USER MEMORY END` — the backing store. Contract (signals declared above the fence, do not redeclare): when `mem_we`=1 absorb `s_axi_wdata` under `s_axi_wstrb` at word `w_word`; when `mem_re`=1 drive `rdata_q` with word `r_word` by the next clock edge (registered read, exactly 1 cycle).

## RULES (do not touch)
- Write FSM: IDLE(awready) -> DATA(wready, wstrb-masked write per beat) -> RESP(bvalid, OKAY). `wlast` ends the data phase.
- Read FSM: IDLE(arready) -> MEM(1-cycle registered BRAM read) -> DATA(rvalid, rlast on final beat). Throughput is 2 cycles/beat by design.
- One response per beat; single outstanding transaction per direction; write and read FSMs are independent/concurrent.
- WRAP: base = addr & ~(total_bytes-1); len+1 must be a power of 2 (AXI rule).
- clk/rst_n are inputs; NO clock dividers or generated clocks in RTL.
- Keep `rdata_q` registered or read data timing breaks.

## SIM
```
powershell -ExecutionPolicy Bypass -File D:\design_plans\pnp_ip\scripts\run_sim.ps1 axi_full_slave
```
Raw equivalent (from `build\axi_full_slave\`):
```
xvlog --sv -d SIMULATION ..\..\axi_full_slave\axi_full_slave.sv ..\..\axi_full_slave\tb_axi_full_slave.sv
xelab tb_axi_full_slave -s tb_axi_full_slave_snap -debug typical -timescale 1ns/1ps
xsim tb_axi_full_slave_snap -tclbatch ..\..\scripts\xsim_run.tcl -wdb tb_axi_full_slave.wdb
```
Pass = `TB PASS` printed, then `$finish`. Iterate until exit 0.

## WAVES
`build\axi_full_slave\tb_axi_full_slave.wdb`
Open: `powershell -File scripts\run_sim.ps1 axi_full_slave -Gui` or `xsim -gui <wdb>`.

## SYNTH
```
powershell -File scripts\run_synth.ps1 axi_full_slave axi_full_slave
```

## $finish / $display / $monitor RULES
- TB: `$finish` only at the end of the test sequence (after PASS/FAIL print) and in the watchdog. `$display` anywhere in TB. `$monitor` TB-only, never RTL.
- RTL: `$display`/`$finish` ONLY inside `` `ifdef SIMULATION `` (runner defines it) or `` `ifdef EMU_FINISH `` (bring-up aid; Protium tolerates it). Never in datapath always blocks.

## PASTE-READY PROMPT
Copy this into a local model together with `axi_full_slave.sv` when requesting changes:

```
You are editing axi_full_slave.sv, an AXI4 full memory slave template.
CONTRACT — violating any rule makes the design fail:
1. Edit ONLY code between "// USER MEMORY START" and "// USER MEMORY END".
   Everything else (FSMs, handshakes, next_addr) is frozen.
2. Interface to your code: mem_we=1 -> write s_axi_wdata under s_axi_wstrb
   byte enables at word index w_word. mem_re=1 -> rdata_q must hold the word
   at r_word after exactly one clock edge (registered read, no combinational
   bypass).
3. One clock (clk), async active-low reset (rst_n). Do NOT add clock
   dividers, generated clocks, latches, or #delays.
4. Do NOT re-declare mem_we/mem_re/w_word/r_word/rdata_q — they exist above
   the fence.
5. The slave returns exactly one response per beat (rvalid/rlast handled
   outside the fence) — do not add extra handshake logic.
6. $display/$finish only inside `ifdef SIMULATION or `ifdef EMU_FINISH.
7. Declare every signal before first use; do not name anything "expect"
   (reserved keyword in this toolchain).
Output the complete modified fenced region only.
TASK: <describe your memory/register change here>
```
