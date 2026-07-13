# axs_chiplet — HW Bring-up Pass Criteria (spec 11_alink_axi.md AL-10)

Standalone IXCOM compile under `hw_wrap_axs_chiplet`. Children (axs_dec, axs_regs,
axs_mem via axs_bank) must each have passed their own rows first.

## Spec-file bring-up row (11_alink_axi.md format)
| Module | Force/Deposit stimulus | Trigger (arm capture on) | Monitor signals | Dump to check | PASS criteria |
|---|---|---|---|---|---|
| axs_bank / axs_chiplet | replay axs_regs + axs_mem sequences through the top slave port | dbg_sel change | dbg_sel, dbg_scratch0, dbg_wrcnt, dbg_mem_wr_cnt | hw_axs_chiplet_run1.fsdb | same responses as the child-level runs, counters consistent |

## Standalone bring-up procedure (force/deposit)
| Step | Force/deposit | Observe | PASS = |
|---|---|---|---|
| 1 | rst, release | dbg_* | all 0 |
| 2 | write 0x0004=0x11 through top port | dbg_sel[0], bresp | wr_sel=0 during txn; OKAY; dbg_scratch0=0x11, dbg_wrcnt=1 (1 clk lag) |
| 3 | W-first write 0x8010=0xCAFE (W 2 clks before AW) | dbg_sel[0], bresp | W waits at dec, completes after AW; wr_sel=1; dbg_mem_wr_cnt=1 |
| 4 | read 0x8010 then read 0x0000 | dbg_sel[1], rdata | rd_sel flips 1→0; 0xCAFE then 0xA11C_0001 |
| 5 | write 0x0030 | bresp, dbg_wrcnt | SLVERR through the whole stack; dbg_wrcnt unchanged |
| 6 | locks | dbg_sel | never changes mid-transaction (lock holds until B/R) |

## Simulation gate (before any HW time)
- [ ] `axs_chiplet_tb` prints `*** PASS`, 0 errors (routing + fix-a + probes + soak)
- [ ] All 3 assertions 0 failures; all 3 covers HIT (both targets exercised)
- [ ] Lint clean

## Validation summary (fill after runs)
| Platform | Date | Result | Evidence |
|---|---|---|---|
| sim | 2026-07-11 | PASS (0 errors) | build\axs_chiplet\xsim.log, axs_chiplet_tb.wdb |
| HW standalone | | | |

## Known limitations
- Sim used SIMPLIFIED behavioral axs_dec/axs_bank (tb\beh) with the REAL slaves —
  behavioral dec adds 1 lock cycle per direction; retime step-timings after local
  models deliver AL-06/AL-09.
- dbg outputs registered (+1 clk) per global rule 5 — AL-10 is silent on this (flagged).
