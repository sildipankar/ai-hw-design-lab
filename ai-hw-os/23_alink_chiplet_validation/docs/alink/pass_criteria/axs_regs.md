# axs_regs — HW Bring-up Pass Criteria (spec 11_alink_axi.md AL-07 + fix a)

Standalone IXCOM compile under `hw_wrap_axs_regs`.

## Spec-file bring-up row (11_alink_axi.md format)
| Module | Force/Deposit stimulus | Trigger (arm capture on) | Monitor signals | Dump to check | PASS criteria |
|---|---|---|---|---|---|
| axs_regs | deposit AXI writes/reads: SCRATCH0=0x11 then read; read ID; write 0x30 (unmapped); ALSO: drive W one clk BEFORE AW (fix-a check) | s_axil_bvalid & bresp!=0 | scratch0, wrcnt, bresp/rresp, rdata, awready/wready | hw_axs_regs_run1.fsdb | readbacks exact; ID=0xA11C0001; unmapped write → SLVERR and wrcnt unchanged; W-before-AW completes normally (wready=1 with awvalid still 0) |

## Standalone bring-up procedure (force/deposit)
| Step | Force/deposit | Observe | PASS = |
|---|---|---|---|
| 1 | rst, release | awready, wready, arready | all 1 (both write channels open INDEPENDENTLY) |
| 2 | W first: wvalid/0x11, 2 clks later awvalid/0x0004 | wready, bvalid | W accepted immediately (awvalid still 0!); B OKAY after AW arrives — fix (a) proof |
| 3 | read 0x0004 | rdata | 0x11, OKAY |
| 4 | read 0x0000 | rdata | 0xA11C_0001 |
| 5 | write 0x0030 = anything | bresp, wrcnt | SLVERR (10), wrcnt UNCHANGED |
| 6 | read 0x000C | rdata | == number of OKAY writes so far |
| 7 | read 0x0040 | rdata, rresp | 0xDEAD_BEEF, SLVERR |
| 8 | hold bready=0 for 5 clks after a write | bvalid, bresp | bvalid held, bresp stable (no drop) |

## Simulation gate (before any HW time)
- [ ] `axs_regs_tb` prints `*** PASS`, 0 errors (t_w_first is the headline test)
- [ ] All 10 assertions 0 failures; all 6 covers HIT (cp_w_first proves fix a exercised)
- [ ] Lint clean

## Validation summary (fill after runs)
| Platform | Date | Result | Evidence |
|---|---|---|---|
| sim | 2026-07-11 | PASS (0 errors) | build\axs_regs\xsim.log, axs_regs_tb.wdb |
| HW standalone | | | |

## Known limitations
- Writes to RO registers (0x00 ID, 0x0C WRCNT) return SLVERR — conservative reading
  of "any other address" (flagged in BUILD_REPORT).
- Decode uses addr[7:0] only (per spec): addresses alias across addr[14:8].
- wstrb ignored (design always drives 4'hF per bus table).
