# axm_engine — HW Bring-up Pass Criteria (spec 11_alink_axi.md AL-02)

Standalone IXCOM compile under `hw_wrap_axm_engine`.

## Spec-file bring-up row (11_alink_axi.md format)
| Module | Force/Deposit stimulus | Trigger (arm capture on) | Monitor signals | Dump to check | PASS criteria |
|---|---|---|---|---|---|
| axm_engine | act as slave: deposit cmd (write 0x8004 data 0x55); force awready/wready 2 clks late, bvalid with bresp=00; then a read with rvalid data 0xAA; then a cmd where you never respond | tmo_sticky rise (3rd case) | m_axil_* all valids/readys, state_dbg, rsp_valid/rdata/err | hw_axm_engine_run1.fsdb | awvalid&wvalid held until each ready (no drop); bready then rsp_valid pulse; read returns 0xAA; no-response case: rsp_err=1 + tmo_sticky exactly at 0xFFF clks |

## Standalone bring-up procedure (force/deposit)
| Step | Force/deposit | Observe | PASS = |
|---|---|---|---|
| 1 | rst 2 clks, release | state_dbg, valids | state_dbg=0 (IDLE), all valids 0, cmd_ready=1 |
| 2 | deposit cmd_valid=1, write 0x8004/0x55 | awvalid, wvalid | both rise together next clk; cmd_ready pulses low |
| 3 | force awready=1 for 1 clk (wready still 0) | awvalid, wvalid | awvalid drops, wvalid STAYS (independent retirement) |
| 4 | force wready=1 for 1 clk, then bvalid=1 bresp=00 | bready, rsp_valid | bready high before bvalid; rsp_valid 1-clk pulse, rsp_err=0 |
| 5 | read cmd, rvalid with 0xAA after 2 clks | rsp_rdata | 0xAA latched, rsp_err=0 |
| 6 | write cmd, NEVER respond | tmo_sticky | rsp_err=1 + tmo_sticky at exactly 0xFFF clks after leaving IDLE; all valids dropped |
| 7 | rst 1 clk | tmo_sticky | clears; step 2 works again |

## Simulation gate (before any HW time)
- [ ] `axm_engine_tb` prints `*** PASS`, 0 errors (incl. real 4096-clk timeout test)
- [ ] All 9 assertions 0 failures; all 6 covers HIT (incl. cp_timeout_fired)
- [ ] Lint clean

## Validation summary (fill after runs)
| Platform | Date | Result | Evidence |
|---|---|---|---|
| sim | 2026-07-11 | PASS (0 errors) | build\axm_engine\xsim.log, axm_engine_tb.wdb |
| HW standalone | | | |

## Known limitations
- Timeout abort drops valids mid-handshake — a deliberate AXI violation per spec;
  axil_pmon WILL log err_vdrop on every timeout (expected interaction, see BUILD_REPORT).
- One outstanding transaction by design.
