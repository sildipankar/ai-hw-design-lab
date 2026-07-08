# axi_lite_regs

WHAT: AXI4-Lite slave register block. Protocol engine is done and verified — you only add registers and your logic in the fenced sections.

FILES: `axi_lite_regs.sv` (synthesizable) · `tb_axi_lite_regs.sv` (sim only)

## Edit points (only these)
- `USER PORTS START/END` — your I/O ports
- `USER REGISTERS START/END` — declare storage, add one `case` row for write, one for read
- `USER LOGIC START/END` — your function (example: RESULT = OPA*OPB when CTRL[0])

## Register map (byte offsets, 32-bit)
| Off | Name | RW | Meaning |
|---|---|---|---|
| 0x00 | ID | RO | 0xCAFE0100, read first to prove access |
| 0x04 | SCRATCH | RW | free register |
| 0x08 | CTRL | RW | bit0 = enable example logic |
| 0x0C | GPIO_OUT | RW | drives `gpio_out` |
| 0x10 | GPIO_IN | RO | reflects `gpio_in` |
| 0x14 | OPA | RW | example operand A |
| 0x18 | OPB | RW | example operand B |
| 0x1C | RESULT | RO | OPA*OPB registered |
| 0x20 | STATUS | RO | bit0 = done |
Unmapped read = 0xDEADBEEF, unmapped write ignored, all resp OKAY.

## Params
`ADDR_W=8` (byte addr window), `DATA_W=32`.

## Rules
- Never edit the protocol engine (marked "do not edit"): AW/W skew handling, bvalid/rvalid logic.
- clk/rst_n are inputs; no clock dividers inside.
- Declare every signal BEFORE first use (xvlog errors otherwise). `expect` is a reserved keyword.
- New register = 3 edits: declaration, write-case row, read-case row. Copy the SCRATCH pattern.
- RO register: read-case row only.

## Sim
```
powershell -ExecutionPolicy Bypass -File scripts\run_sim.ps1 axi_lite_regs
```
(raw: `xvlog --sv -d SIMULATION *.sv` → `xelab tb_axi_lite_regs -s snap -debug typical -timescale 1ns/1ps` → `xsim snap -runall`)
Passes when it prints `TB PASS`.

## Waves
Batch run writes `build\axi_lite_regs\tb_axi_lite_regs.wdb`.
Interactive: `scripts\run_sim.ps1 axi_lite_regs -Gui` or `xsim -gui <wdb>`.
Stimulus = the numbered tests in the TB initial block (ID read at ~50ns, then scratch/strobe/skew/gpio/MAC in order).

## Synth
```
powershell -ExecutionPolicy Bypass -File scripts\run_synth.ps1 axi_lite_regs axi_lite_regs
```

## $finish / $display / $monitor
- TB: `$finish` at end of the test sequence (already there); `$monitor` once in an `initial` block if wanted. TB-only.
- RTL: only inside `` `ifdef SIMULATION `` (sim defines it) or `` `ifdef EMU_FINISH `` (see end of axi_lite_regs.sv — Protium-tolerated $display/$finish on done; enable with `-d EMU_FINISH`). Never inside datapath always blocks.

## Paste-ready prompt for a small model
```
You are editing axi_lite_regs.sv, a verified AXI4-Lite register template.
Rules: modify ONLY the code between "USER PORTS", "USER REGISTERS" and
"USER LOGIC" START/END markers. Do not touch the protocol engine. Declare
signals before use. A new RW register needs: a declaration, one case row in
the write decode, one case row in the read mux (copy the SCRATCH pattern);
RO needs only a read row. Registers are 32-bit at 4-byte offsets; next free
offset is 0x24. Keep everything synthesizable (no delays, no initial blocks).
TASK: <describe your registers and logic here>
```
