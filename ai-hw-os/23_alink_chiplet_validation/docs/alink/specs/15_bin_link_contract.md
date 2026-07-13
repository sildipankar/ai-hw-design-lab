# 15 — Bin-Link / Lane Adapter Contract (+ external review punch list)

**Why this file:** external review verdict (2026-07, logged below): all five architectures have plausible cut points, but cuts were *logical protocol boundaries*, not physical bin-link specs — "none should connect to a delayed inter-bin link without an explicit adapter contract." This IS that contract. Applies to every cut: ALINK, AXION d2d, SLINK byte stream, NEXA links, EQD boundary.

## 1. The lane model
A bin cut is implemented by an IP endpoint on EACH side (never raw wires). The pair provides N **lanes**; each lane has two modes:
- **Streaming OFF:** handshake-per-transfer through the lane. Slow, quiet, near-deterministic timing. Bring-up/debug mode.
- **Streaming ON:** pipelined continuous transport. Full throughput; latency varies with lane scheduling/buffering → **cycle-nondeterministic between runs. This is expected and acceptable** — see §3.

## 2. The four promises (verify per lane IP, before ANY design crosses it)
| # | Promise | If broken |
|---|---|---|
| P1 | Per-lane order: a lane is a FIFO, always | sequence corruption — disqualifying |
| P2 | Cross-lane alignment: split buses realigned, OR rule enforced: **one logical channel = one lane** | bin-level multi-bit-CDC bug: skewed halves recombine into values that never existed |
| P3 | End-to-end backpressure (credits/ready) with streaming ON, far side stalled: zero drops | silent data loss under load |
| P4 | Nothing time-based crosses: no tick enables, no fixed-latency expectations, no cycle-calibrated timeouts | works stream-OFF, fails stream-ON, "intermittent" |

## 3. Determinism policy (WHAT vs WHEN)
Streaming ON may change WHEN, never WHAT. All our designs are latency-insensitive (valid/ready at every cut) → latency jitter is functionally benign IF P1–P4 hold.
- **Determinism gate (mandatory per design × mode):** same build, same seeds, run twice, SEQCHECK the logs. Identical → jitter is benign, proven. Different → real bug (timing dependence or lane reorder), stop and debug.
- **Three-way EQD experiment:** mono vs chiplet-streamOFF vs chiplet-streamON — sequences must match 3-way; three latency histograms quantify each mode's cost (the publishable plot).
- **Debug rule:** trigger captures on token identity (self-ID seq), never cycle counts — cycles differ per run with streaming ON, tokens don't.

## 4. Adapter requirements per design (from review + contract)
| Design | Requirement |
|---|---|
| ALINK | Transport 5 AXI-Lite channels as independent lanes; **slave must accept AW and W independently** (fix: no wait-for-both); master/slave **register-slice bridge pair** at the cut, preserving per-channel state |
| AXION d2d | Define endpoint ownership: d2d_tx = bin A's endpoint, d2d_rx = bin B's; the async FIFO is CDC *inside* the link, not the bin transport itself — what crosses the lane is the flit stream. **Fix D2D RX spec wording:** pop into an output/skid register so m_valid = data-present, never a function of m_ready (valid-depends-on-ready = deadlock risk) |
| SLINK | The bin cut is the **byte stream** (valid/ready), not the serial wire; if the UART wire itself should cross bins later: uart_tx in bin 1, uart_rx in bin 2, each with its **own local baud_tick** — tick16 never crosses (P4) |
| NEXA | Each mesh edge crossing bins = **two directional link adapters** with elastic buffer/credits (v2 spec to write before any bin build) |
| EQD | AXION d2d is unidirectional → **b2a needs its own second link instance** (or defined reverse lane); update 13_equiv_dut.md boundary section when building |

## 5. Model-routing corrections (review-confirmed, adopt now)
- **27B writes complex modules** (FSM, arbiter, AXI slave, integration) with contract-grade specs (invariants + interface manifest + forbidden list). 9B: fenced pnp_ip templates, simple leaves, scripts, mechanical wiring only. CDC implementation: 27B draft + human sign-off, never trusted.
- **Description scales WITH model size:** rich contracts to 27B; small scope (not more text) to 9B.
- **rst-convention conflict (real bug in our prompts):** AXION = sync active-high `rst`; pnp_ip = async active-low `rst_n`. Keep as separate prompt profiles; NEVER mix AXION specs with pnp_ip/gold-standard exemplars in one paste without stating which convention wins in the task line.
- Spec hygiene: purge "choose / simplest / add as output" phrasing from any section a model will implement (02:184, 05:59 flagged) — every choice made by the human, in the spec, before the prompt.
- **Eval debt:** results log still unpopulated — routing claims are estimates until E1–E10 run. (Week-1 script already schedules this.)

## 6. Review provenance
External frontier review of github.com/sildipankar/ai-hw-design-lab, 2026-07. Verdicts: ALINK closest to implementation-ready; EQD best-defined experimental cut; sequence-compare-ignore-timestamps approach explicitly endorsed as correct.
