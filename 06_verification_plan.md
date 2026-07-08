# 06 — Verification Plan: SV Testbench + DPI-C (Xcelium, sim-only)

DPI runs **only in Xcelium simulation**. Nothing in this file is compiled by IXCOM.
The hardware equivalents are the synthesizable `stim_gen`/`soc_seq`/`monitor_unit`
blocks plus runtime force/monitor (file 07). Sim and HW run **the same test from the same
seed** because the C golden models implement the identical LFSR/MISR polynomials as C-01/C-02.

## TB architecture (all levels share this shape)

```
tb_<dut>.sv
├── clk/rst gen                    (only place # delays are allowed)
├── dut instance
├── stimulus: class-based or task-based driver, seeded ($urandom(seed) + DUT seed port)
├── monitors: bind-free, hierarchical refs to dbg buses
├── scoreboard: compares DUT outputs vs DPI golden C model
└── report: dpi_log() + $fatal on mismatch, $display PASS summary
```

Conventions: one `tb_pkg.sv` with the DPI imports + common tasks (csr_write, csr_read,
wait_done_timeout). Timeout every wait (`fork/join_any` + $fatal) — no hanging regressions.
Assertions: SVA in TB scope only (keep RTL assertion-free for IXCOM simplicity in v1).

## DPI-C import surface (golden.c — one C file, ~400 lines)

| Import | Signature | Used by |
|---|---|---|
| dpi_lfsr32_next | `int dpi_lfsr32_next(int state)` | every stim check |
| dpi_misr32_next | `int dpi_misr32_next(int sig, int data)` | every signature check |
| dpi_golden_mac | `longint dpi_golden_mac(longint acc, byte a, byte b)` | tb_pe_mac |
| dpi_ccx_golden | `int dpi_ccx_golden(int seed)` → expected checksum | tb_ccx_top |
| dpi_mem_model_wr / _rd | `void dpi_mem_model_wr(int addr,int data)` / `int dpi_mem_model_rd(int addr)` | tb_bank_arb, tb_mio |
| dpi_mio_golden | `int dpi_mio_golden(int seed,int base,int len)` → expected signature | tb_mio_top |
| dpi_sb_push / dpi_sb_check | scoreboard FIFO in C: push expected, check actual, returns pass | tb_d2d |
| dpi_crc16 | `shortint dpi_crc16(int data, shortint crc_in)` | tb_d2d |
| dpi_soc_golden | `void dpi_soc_golden(int seed, output int d2d_sig, output int mio_sig)` | tb_soc |
| dpi_log | `void dpi_log(string msg)` → timestamped file log | all |

Export (optional, phase 2): `dpi_cb_error(string src)` called from C to force a TB flag —
demonstrates bidirectional DPI for the portfolio.

## Test matrix per level

| TB | DUT | Tests | Pass criterion |
|---|---|---|---|
| tb_lfsr_misr | C-01+C-02 | 3 seeds x 10k steps vs dpi_lfsr32_next/dpi_misr32_next | exact match every cycle |
| tb_sync_fifo | C-03 | random push/pop, full/empty stress | data order + flags vs SV queue model |
| tb_rr_arbiter | C-04 | all req patterns, fairness count over 10k | no starvation, one-hot always (SVA) |
| tb_skid | C-05 | random valid/ready, back-to-back | no drop/dup (scoreboard) |
| tb_async_fifo | C-08 | ratios 2.0x, 3.7x, 0.3x; reset staggering | order preserved, no flag glitch |
| tb_pe_mac / tb_pe_array | CX-01/02 | random operands vs dpi_golden_mac / C matrix ref | acc exact |
| tb_ccx_top | CX-08 | CSR flow, 5 seeds vs dpi_ccx_golden; res stream scoreboarded | checksum + stream match |
| tb_bank_arb / tb_move_engine | MI-02/05 | collisions vs dpi_mem_model; injected bit-flip | routing correct; err_cnt==1 on inject |
| tb_mio_top | MI-07 | CSR flow vs dpi_mio_golden; rx-ingress test | signature match |
| tb_d2d_tx | D2-01 | framing fields vs dpi_crc16; credit starvation + return | flit fields exact; s_ready gates at 0 credits |
| tb_d2d_rx | D2-02 | good stream; corrupt crc4; skipped seq | payloads exact; sticky flags fire once each |
| tb_d2d | D2-03 | 100k words, backpressure, corrupt/drop via force | sb clean; err flags fire on inject |
| tb_accum | CX-03 | random acc_flat snapshots | drain order + checksum vs C ref |
| tb_seq_fsm | CX-04 | go storms, drain_busy timing sweeps | state walk + dwell counts exact (SVA) |
| tb_csr | CX-05 / MI csr | full map R/W, W1C, self-clear GO, unmapped | per register map spec |
| tb_sram_bank / tb_addr_gen | MI-01/04 | all-addr R/W; base/len/stride sweeps | exact |
| tb_soc_seq | SC-02 | emulated CSR slaves (SV tasks respond) | bus write sequence order/data exact |
| tb_csr_cdc_bridge | SC-02 | 1k writes at 2.0x and 3.7x ratios | no lost/duplicated/corrupted write |
| tb_monitor_unit | SC-03 | event pulses both domains; stage timeout | counts exact; trig_err on err rise + timeout |
| tb_soc | SC-04 | seeds 1..5 end-to-end vs dpi_soc_golden; **records GOLDEN_SIG_D2D** | test_pass=1, fail_info=0 |

**Coverage rule: every module in files 01–05 has a `tb_<name>` — no exceptions.**
Hierarchy/wiring modules (ccx_core, ccx_ctrl, mio_mem, mio_dma, the tops) get thin
structural TBs: one full pass through, results compared to the child-level goldens
(catches miswiring, which is the only bug class a wiring module can have).

## Error-injection methodology (the sim↔HW bridge)

In sim, inject with `force`/`release` on hierarchical paths (e.g.
`force tb.dut.u_d2d.fifo_wdata[7] = ~...`). Keep a single `inject_pkg.sv` listing every
injection point as a task — **the same signal list becomes the Protium runtime
force/monitor list** in file 07. This 1:1 mapping (sim force ↔ HW runtime force) is the
core methodology claim of the whole project.
