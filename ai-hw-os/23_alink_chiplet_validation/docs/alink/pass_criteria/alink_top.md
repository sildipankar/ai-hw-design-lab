# alink_top — HW Bring-up Pass Criteria (spec 11_alink_axi.md AL-11 + fix b)

Full-design IXCOM compile (this IS the top). All children passed their rows first.
The chiplet cut now contains the axil_reg_slice bridge pair (fix b) — pin budget at
the partition is 17 signals per face of each slice.

## Spec-file bring-up row (11_alink_axi.md format)
| Module | Force/Deposit stimulus | Trigger (arm capture on) | Monitor signals | Dump to check | PASS criteria |
|---|---|---|---|---|---|
| alink_top | deposit seed=1, force run=1 — nothing else | test_done rise; 2nd armed trigger on pmon_err rise | led, err_cnt, chk_sig, test_pass, chiplet dbg buses | hw_alink_top_run1.fsdb | test_pass=1, err_cnt=0, chk_sig==sim golden; repeat seeds 2,3; negative: runtime-force axs-side arready=0 permanently → tmo_sticky → test_pass=0 and pmon err_stall=1 |

## Standalone bring-up procedure (force/deposit)
| Step | Force/deposit | Observe | PASS = |
|---|---|---|---|
| 1 | release arst_n | led | heartbeat bit (led[1]) blinking; rest 0 |
| 2 | deposit seed=1, force run=1 | test_done | rises well before the 2^26 watchdog |
| 3 | after done | test_pass, err_cnt, chk_sig | 1 / 0 / == sim golden for seed 1 |
| 4 | repeat seeds 2, 3 (arst_n toggle between runs — top holds results until reset) | chk_sig | each matches its sim golden |
| 5 | NEGATIVE: force AXS-side arready=0, run | tmo led (led[2]), pmon_err, test_pass | tmo=1, pmon err bits set, test_pass=0; test still terminates (no hang) |
| 6 | release force, arst_n toggle, rerun | test_pass | 1 again (clean recovery) |

## Simulation gate (before any HW time)
- [ ] `alink_top_tb` prints `*** PASS`, 0 errors — includes the sim version of step 5
      (force dut.b_arready=0) and reset-during-traffic rerun
- [ ] All 6 assertions 0 failures; all 3 covers HIT
- [ ] Lint clean; record partition pin count at the slice cut (file-11 pin-budget task)

## Validation summary (fill after runs)
| Platform | Date | Result | Evidence |
|---|---|---|---|
| sim | 2026-07-11 | PASS (0 errors) | build\alink_top\xsim.log, alink_top_tb.wdb |
| HW standalone | | | |

## Known limitations
- Sim ran with behavioral stand-ins for ALL local-model blocks (reset_sync, cmd_gen,
  axil_pmon, axs_dec, axm_core, axs_bank, sram_bank) around the REAL frontier RTL
  (engine, slaves, slices, chiplet tops, supervisor). chk_sig goldens are for the
  behavioral cmd_gen pattern — RE-BASELINE when the real AL-01 lands.
- After test_done, results hold until arst_n (no re-arm; SPEC GAP flagged).
- Heartbeat = free-running 24-bit counter MSB (SPEC GAP: spec doesn't say which counter).
