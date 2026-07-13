# axs_mem — HW Bring-up Pass Criteria (spec 11_alink_axi.md AL-08 + fix a)

Standalone IXCOM compile under `hw_wrap_axs_mem` (includes sram_bank child — real
MI-01 from local models, must have passed ITS row first).

## Spec-file bring-up row (11_alink_axi.md format)
| Module | Force/Deposit stimulus | Trigger (arm capture on) | Monitor signals | Dump to check | PASS criteria |
|---|---|---|---|---|---|
| axs_mem | deposit write 0x8010=0xCAFE, read 0x8010; read 0x8FFC (never written) AFTER full-region init; ALSO drive W before AW | rvalid | rdata, rresp, mem_wr_cnt, ram en/we | hw_axs_mem_run1.fsdb | readback 0xCAFE with OKAY; R comes exactly 3 clks after AR accept; W-before-AW completes; unwritten read X-free only after init run |

## Standalone bring-up procedure (force/deposit)
| Step | Force/deposit | Observe | PASS = |
|---|---|---|---|
| 1 | rst, release | awready, wready, arready | all 1 |
| 2 | W first: wvalid/0xCAFE, 2 clks later awvalid/0x8010 | ram en/we, bvalid | one-cycle en&we pulse after BOTH arrive; B OKAY — fix (a) proof |
| 3 | read 0x8010 | rdata, rvalid | 0xCAFE; rvalid exactly 3 clks after AR accept |
| 4 | mem_wr_cnt | mem_wr_cnt | == accepted writes |
| 5 | hold rready=0 for 4 clks | rvalid, rdata | held and stable until rready |
| 6 | read 0x8FFC only AFTER a full-region write run | rdata | X-free constant (file-11 X-state rule) |

## Simulation gate (before any HW time)
- [ ] `axs_mem_tb` prints `*** PASS`, 0 errors (incl. exact 3-clk latency check)
- [ ] All 10 assertions 0 failures; all 5 covers HIT (cp_w_first proves fix a)
- [ ] Lint clean; Vivado stage: sram_bank maps to 1 RAMB36 (file-11 BRAM check)

## Validation summary (fill after runs)
| Platform | Date | Result | Evidence |
|---|---|---|---|
| sim | 2026-07-11 | PASS (0 errors) | build\axs_mem\xsim.log, axs_mem_tb.wdb |
| HW standalone | | | |

## Known limitations
- Sim used behavioral sram_bank (tb\beh) — rerun after local models deliver MI-01.
- RAM port shared write/read with write priority; guard is unreachable in the
  one-outstanding system (flagged in BUILD_REPORT).
- Never read-before-write (RAM array has no reset — BRAM rule).
