# Cheat Sheet: RTL Writing + Gotchas + System-Level Thinking (NEW — fills the gap)

**Related skills:** 06_rtl_design_patterns/* (all four)

## 10 key concepts
1. `always_ff` = nonblocking (`<=`) only; `always_comb` = blocking (`=`) only; mixing = simulation/synthesis divergence.
2. Latch inference: any `always_comb` path that doesn't assign an output → latch. Default-assign everything at the top.
3. One clock, one reset per module unless the spec says otherwise; CDC only via known patterns (see fifo_cdc_review).
4. Reset every flop you write, or document why not (pipeline data regs behind a valid are the legitimate exception).
5. Width discipline: match widths explicitly; know sign rules (any unsigned operand → unsigned comparison); `$clog2` for pointer widths, +1 bit for full/empty counters.
6. `unique case` on enums + default → both safety nets; priority `if/else` only when priority is intended.
7. Synthesis-sim mismatch sources: `initial` blocks (FPGA honors, ASIC doesn't), `#delays` (sim-only), X-optimism (`if(x)` takes else in HW-random), sensitivity-list gaps (use always_comb).
8. Interfaces first: valid/ready or req/ack on every boundary; every counter gets overflow policy; every input gets an illegal-value answer.
9. FPGA vs ASIC idioms: sync-write/sync-read for BRAM inference, no clock gating (use enables), no tri-states internally.
10. System thinking: every module is a future standalone hardware DUT — expose observability (state, counters) and make reset/idle externally recognizable.

## Napkin math + units
Counter width = $clog2(DEPTH)+1 for occupancy. Pipeline depth = latency budget / stage delay. Fanout >~64 loads → think replicate/register.

## 10 common mistakes
1 Blocking assign in always_ff (race). 2 Missing default → latch. 3 Partial reset (some flops). 4 `always @(*)` legacy with missed sensitivity. 5 Off-by-one at pointer wrap. 6 Unsigned/signed comparison surprise. 7 `if (en)` forgotten (free-running counter). 8 Inferred latch celebrated as "it synthesized". 9 initial-block state assumed on ASIC. 10 Interface invented mid-module (signal not in the port table).

## Design-review checklist (any RTL)
- [ ] Assignment discipline: `<=` in ff, `=` in comb, no crossover
- [ ] Every comb output default-assigned; unique case + default
- [ ] Reset audit: every flop reset or justified
- [ ] Widths: no implicit truncation; pointers sized with margin bit
- [ ] Ports match spec table exactly; sentinel comment at end

## Debug checklist (RTL misbehaves)
- [ ] Sim-vs-synth mismatch class? (initial, #delay, X, sensitivity)
- [ ] X in waveform: trace to first X source (uninitialized flop/memory)
- [ ] Off-by-one: check wrap cycle by hand at DEPTH-1→0
- [ ] Handshake: data changed while valid&&!ready? (assertion catches in 1 line)
- [ ] Latch warning in lint = bug until proven intended

## Interview Q&A (short)
1. *Blocking vs nonblocking?* NB samples RHS then updates together (flop semantics); blocking updates immediately (comb); crossing them races the simulator vs silicon.
2. *How do latches sneak in?* Unassigned path in combinational always; kill with top defaults + full case coverage.
3. *When is an unreset flop OK?* Data regs qualified by a reset valid bit — control plane always reset, datapath may free-run behind it.
4. *Why did your design work in sim but not FPGA?* Ranked: initial-block/init assumptions, X-optimism, CDC, sensitivity gaps — difference-list them.
5. *What makes RTL "reviewable"?* Interfaces as tables, one module/file, enum FSMs, assertions co-located, observability ports — write for the reviewer.

## Model routing
7B: module generation from complete spec (its ONLY job — and this sheet is its pre-read). 9B: formatting, port-table extraction. 14B: reviews vs spec. 27B: CDC, arbitration, multi-module.
**Escalate human/frontier:** anything the lint/sim tools should answer first — run tools before asking models.

## Portfolio hook
This checklist enforced across all published RTL = the consistency reviewers notice; cite it in P6 methodology writeup as the 7B contract pre-read.
