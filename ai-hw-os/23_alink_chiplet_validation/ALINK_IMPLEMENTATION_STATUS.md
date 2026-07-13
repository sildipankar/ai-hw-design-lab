# A-Link implementation status and completion plan

## Restated task

Package the implemented A-Link chiplet-validation RTL and verification collateral, then identify every remaining production module and the self-checking unit tests required to complete it.

## Output

### Current scope

A-Link is a synthetic, single-clock, two-chiplet AXI4-Lite validation design. `alink_top` supervises a master chiplet, two register slices at the chiplet boundary, and a slave chiplet containing register and SRAM targets. The design permits one outstanding transaction.

### Implemented production RTL

| Module | Source | Responsibility | Present test |
|---|---|---|---|
| `axm_engine` | `rtl/alink/axm_engine.sv` | Master transaction FSM and timeout | `tb/axm_engine_tb.sv` + SVA |
| `axs_regs` | `rtl/alink/axs_regs.sv` | ID, scratch, and write-counter registers | `tb/axs_regs_tb.sv` + SVA |
| `axs_mem` | `rtl/alink/axs_mem.sv` | AXI wrapper for 1024 x 32 SRAM | `tb/axs_mem_tb.sv` + SVA |
| `axil_reg_slice` | `rtl/alink/axil_reg_slice.sv` | Five-channel elastic boundary slice | `tb/axil_reg_slice_tb.sv` + SVA |
| `axm_chiplet` | `rtl/alink/axm_chiplet.sv` | Master-chiplet integration | `tb/axm_chiplet_tb.sv` + SVA |
| `axs_chiplet` | `rtl/alink/axs_chiplet.sv` | Slave-chiplet integration | `tb/axs_chiplet_tb.sv` + SVA |
| `alink_top` | `rtl/alink/alink_top.sv` | Supervisor, watchdog, result latch, LEDs | `tb/alink_top_tb.sv` + SVA |
| `skid_buffer` | `rtl/common_ip/skid_buffer.sv` | Shared ready/valid storage | Exercised by slice test |

The source regression recorded on 2026-07-11 passed, but the chiplet and top-level tests still use behavioral stand-ins from `tb/beh`. Therefore the passing result is an integration milestone, not final production completion.

### Remaining production implementations

| Priority | Module | Required implementation | Completion evidence |
|---|---|---|---|
| P0 | `cmd_gen` | Full 64-write, 64-read, directed-register test; stable command under backpressure; saturating errors; final MISR | Unit TB passes seeds 1/2/3 and negative tests |
| P0 | `lfsr32` | Synthesizable seeded 32-bit pattern generator with explicit zero-seed policy | Sequence matches software golden model |
| P0 | `misr32` | Synthesizable 32-bit response signature accumulator | Known streams match software goldens |
| P0 | `axil_pmon` | Handshake/error counters and sticky valid-drop, orphan-response, and stall checks | Violation-injection TB + SVA passes |
| P0 | `axs_dec` | Locked 1-to-2 AXI router selected by address bit 15 | Routing/backpressure/reset TB + SVA passes |
| P1 | `sram_bank` | Synthesis-ready 1024 x 32 single-port memory with documented read latency | Full address/data test and memory-inference report |
| P1 | `reset_sync` | Defined reset assertion/deassertion synchronizer | Reset phase/pulse test and CDC review |
| P1 | `axm_core` | Reviewed production structural wrapper | Production-only elaboration and connectivity test |
| P1 | `axs_bank` | Reviewed production structural wrapper | Production-only elaboration and connectivity test |

### Testbench components

| Component | Role | Drives or monitors | 7B-able? |
|---|---|---|---|
| Clock/reset generator | Deterministic startup and reset-during-traffic | `clk`, reset | Y |
| Command sink/source | Backpressure and response timing for `cmd_gen` | `cmd_*`, `rsp_*` | Y |
| AXI master BFM | Directed register/memory requests | Slave-side AXI inputs | Y |
| AXI slave BFM | Independent channel stalls and responses | Master-side AXI inputs | Y |
| AXI monitor | Records accepted channel beats | All five AXI channels | Y |
| Scoreboard | Checks order, count, payload, response, and signature | Monitor transactions and DUT status | Y |
| Software LFSR/MISR model | Independent expected pattern/signature | Seed and response stream | Y |
| Test sequencer | Runs small named tests and injection cases | All drivers and reset | Y |

### Reference-model inputs and outputs

| Reference model | Inputs | Outputs checked |
|---|---|---|
| LFSR model | Seed and accepted-command enables | Write data and expected read data |
| Memory model | Accepted writes and reads | Read response data and access order |
| Register model | Address, write data, accepted operation | ID, scratch values, WRCNT, response code |
| MISR model | Ordered response data stream | Final `chk_sig` |
| AXI accounting model | Five channel handshakes | Outstanding counts, orphan detection, counters |

### Required unit-test list

| Test | Stimulus | Machine-checkable checks | Bug classes |
|---|---|---|---|
| `cmd_clean_seeds` | Complete runs for seeds 1, 2, 3 | Exact 64 writes, 64 reads, directed operations, zero errors, golden signature | loss, duplication, ordering, wrong data |
| `cmd_backpressure` | Burst `cmd_ready=0` and delayed responses | Stable command, no skipped/repeated address, one response per command | stability, loss, duplication |
| `cmd_negative` | Corrupt one read and inject one response error | Each injection increments error count exactly once | error accounting |
| `cmd_reset_phase` | Reset during every command-generator phase | IDLE state, cleared counters, clean restart | reset recovery |
| `lfsr_misr_vectors` | Zero, one, maximum, and random seeds/streams | Bit-exact match to independent software models | corner values, polynomial error |
| `pmon_legal` | Legal AW/W orderings plus read/write backpressure | Exact handshake/error counters; no sticky error | false positives, ordering |
| `pmon_violations` | Valid withdrawal, orphan B/R, long stall | Correct sticky flag on exact boundary; remains set until reset | protocol violation detection |
| `decoder_routes` | Alternating register/memory reads and writes | Only selected downstream port active; correct response returned | misroute, cross-talk |
| `decoder_channel_order` | AW-before-W, W-before-AW, simultaneous AW/W | Address/data paired once and selection held through B | ordering, duplication |
| `decoder_reset` | Reset with read/write outstanding | Defined idle outputs and clean next transaction | reset recovery |
| `sram_address_walk` | Write/read every location with multiple patterns | Exact data, address, and response latency | aliasing, corruption, corner values |
| `wrapper_connectivity` | Toggle every child interface independently | Port-by-port equality with documented status latency | wiring error |
| `top_random_soak` | Random legal stalls across all channels and seeds | Scoreboard empty, zero unexpected errors, golden signature | loss, duplication, ordering, deadlock |

### Completion pass criteria

- No functional child is compiled from `tb/beh` or an elaboration-only stub.
- Every test reports zero `$error`/`$fatal` events and a named PASS marker.
- Every ready/valid interface is tested with ready low before, with, and after valid.
- All DUT outputs are checked by a scoreboard, assertion, or explicit expected-value comparison.
- Production-only unit, chiplet, and full-top elaboration succeeds.
- Seeds 1, 2, and 3 match independent LFSR/MISR software goldens.
- Negative tests terminate within a bound and leave the expected sticky diagnostic.
- Lint, assertions, reset/CDC review, synthesis, timing, and memory inference complete without unexplained failures.

## Self-check

- Every current production output is covered by the existing module SVA/TB pairing or the listed wrapper/top scoreboards.
- Data loss, duplication, ordering, backpressure, corner values, reset during traffic, protocol violations, and deadlock each map to at least one named test above.
- The command, master AXI, slave AXI, decoder, register slice, and top-level ready/valid paths all have explicit backpressure tests.
- Each proposed testbench component is marked as 7B-able.
- Pass criteria require automated comparisons and zero `$error`/`$fatal`; waveform inspection is not the acceptance criterion.

## Uncertainties

- The specification lists 64 memory reads plus four directed register reads, implying 68 accepted R transactions; one existing pass criterion says 65. Resolve before freezing the monitor-count check.
- Timeout currently withdraws an outstanding valid, intentionally triggering the monitor but violating the AXI valid-hold rule. A production-safe recovery policy is not specified.
- `run` synchronization is required only if `run` is asynchronous to `clk`; its source clock relationship is not specified.
- Re-arming after `test_done` without reset is not specified.

// END-OF-ANSWER
