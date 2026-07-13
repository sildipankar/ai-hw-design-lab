# axil_reg_slice — HW Bring-up Pass Criteria (NEW module, review fix b)

Mandated by 15_bin_link_contract.md §4 (ALINK row); no spec row exists in file 11 —
this row is the proposed addition (SPEC GAP, see BUILD_REPORT).
Standalone IXCOM compile under `hw_wrap_axil_reg_slice`.

## Proposed bring-up row (11_alink_axi.md format)
| Module | Force/Deposit stimulus | Trigger (arm capture on) | Monitor signals | Dump to check | PASS criteria |
|---|---|---|---|---|---|
| axil_reg_slice | act as master AND slave: deposit one write (AW+W, then bready) and one read through the slice; then repeat holding each m-side ready low 4 clks | any m-side valid rise | all 10 valid/ready pairs + payloads both faces | hw_axil_reg_slice_run1.fsdb | every beat exits with identical payload, 1–2 clk lane latency; under stall each lane holds valid with stable payload and upstream ready drops after 2 absorbed beats; zero drops/duplicates |

## Standalone bring-up procedure (force/deposit)
| Step | Force/deposit | Observe | PASS = |
|---|---|---|---|
| 1 | rst, release | all valids | 0 both faces, upstream readys 1 |
| 2 | deposit AW beat s-side (addr 0x1234) | m_axil_awvalid/awaddr | appears 1 clk later, addr identical |
| 3 | hold m_axil_awready=0, push 2 more AW beats | s_axil_awready | drops after the 2nd absorbed beat (skid depth 2); payloads held stable |
| 4 | release awready | m side | both parked beats exit in order, none lost/duplicated |
| 5 | repeat steps 2–4 per channel: W, AR (forward), B, R (backward) | per-channel | same behavior — every channel has INDEPENDENT state (fix b) |
| 6 | mid-stall: rst 1 clk | all valids | clear; traffic clean afterward |

## Simulation gate (before any HW time)
- [ ] `axil_reg_slice_tb` prints `*** PASS`, 0 errors (end-to-end dict compare under stalls)
- [ ] All 11 assertions 0 failures; all 5 per-lane stall covers HIT
- [ ] Lint clean

## Validation summary (fill after runs)
| Platform | Date | Result | Evidence |
|---|---|---|---|
| sim | 2026-07-11 | PASS (0 errors) | build\axil_reg_slice\xsim.log, axil_reg_slice_tb.wdb |
| HW standalone | | | |

## Known limitations
- Ports/behavior are this implementation's definition (no spec exists) — review the
  header of rtl\alink\axil_reg_slice.sv before treating as frozen.
- Adds 1–2 cycles latency per direction per instance (2 instances at the cut).
