# axm_chiplet — HW Bring-up Pass Criteria (spec 11_alink_axi.md AL-05)

Standalone IXCOM compile under `hw_wrap_axm_chiplet`. Children (cmd_gen, axm_engine,
axil_pmon via axm_core) must each have passed their own rows first.

## Spec-file bring-up row (11_alink_axi.md format)
| Module | Force/Deposit stimulus | Trigger (arm capture on) | Monitor signals | Dump to check | PASS criteria |
|---|---|---|---|---|---|
| axm_chiplet | same as axm_core (you are the slave chiplet via deposit); pmon now watching live | pmon_err any rise (must NOT fire on clean run) | dbg_bus, pmon_err, pmon_cnt_r, chk_sig | hw_axm_chiplet_run1.fsdb | clean run: done=1, err_cnt=0, pmon_err=000, pmon_cnt_r matches sim read count; chk_sig==sim |

## Standalone bring-up procedure (force/deposit)
| Step | Force/deposit | Observe | PASS = |
|---|---|---|---|
| 1 | rst, release | dbg_bus, pmon_err | all 0, no X |
| 2 | deposit seed=1, pulse go; act as slave on m_axil_* pins (respond per sim log) | dbg_bus | gen_state/eng_state walk the phases; dbg_bus[6] (done) rises |
| 3 | after done | err_cnt, chk_sig, pmon_err | err_cnt=0, chk_sig == sim-recorded value, pmon_err=000 |
| 4 | pmon_cnt_r | pmon_cnt_r | == read count from the sim log for the same seed |
| 5 | rerun, respond ONE read with wrong data | err_cnt | exactly 1; pmon_err still 000 (data errors are not protocol errors) |
| 6 | status timing | done vs core | chiplet outputs lag internals by exactly 1 clk (boundary registers) |

## Simulation gate (before any HW time)
- [ ] `axm_chiplet_tb` prints `*** PASS`, 0 errors (clean + poisoned + reset-during)
- [ ] All 5 assertions 0 failures; both covers HIT
- [ ] Lint clean

## Validation summary (fill after runs)
| Platform | Date | Result | Evidence |
|---|---|---|---|
| sim | 2026-07-11 | PASS (0 errors) | build\axm_chiplet\xsim.log, axm_chiplet_tb.wdb |
| HW standalone | | | |

## Known limitations
- Sim used SIMPLIFIED behavioral cmd_gen/axil_pmon (tb\beh) with the REAL axm_engine —
  pmon_cnt_r expectation (10) and chk_sig golden are for the behavioral pattern; rerun
  and re-baseline after local models deliver AL-01/AL-03/AL-04.
