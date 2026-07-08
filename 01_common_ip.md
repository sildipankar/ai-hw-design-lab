# 01 — Common Leaf IP (Tier 0)

Nine blocks. Each `### C-xx` section is **self-contained — copy one whole section into a
local model** together with the prompt template from `08_llm_prompt_templates.md`.
Model routing: 7B coder for C-01..C-06, C-09; 14B/27B for C-07, C-08 (CDC-sensitive).

Build + verify order: C-01, C-02 first (they are the stim/check backbone of everything).

---

### C-01: lfsr32 — seeded pseudo-random stimulus generator

**Model:** 7B | **Depends on:** none | **~40 lines**

Parameters: `WIDTH = 32`

| Dir | Width | Port | Description |
|---|---|---|---|
| in | 1 | clk | clock |
| in | 1 | rst | sync active-high reset |
| in | 1 | load | load seed this cycle (priority over enable) |
| in | 32 | seed | seed value loaded on `load` |
| in | 1 | enable | advance one step per cycle when high |
| out | 32 | prdata | current LFSR state (registered) |
| out | 1 | valid | high one cycle per advance (registered enable) |

Function: 32-bit Galois LFSR, polynomial x^32 + x^22 + x^2 + x^1 + 1 (taps 0x80200003).
On `load`, state <= seed (if seed==0 substitute 32'h1 to avoid lockup). On `enable`,
shift right by 1; if lsb was 1, XOR state with taps. Reset state = 32'h1.
**Runtime probe:** prdata, valid.

---

### C-02: misr32 — signature compressor (result checker core)

**Model:** 7B | **Depends on:** none | **~40 lines**

Parameters: `WIDTH = 32`

| Dir | Width | Port | Description |
|---|---|---|---|
| in | 1 | clk | clock |
| in | 1 | rst | sync reset, clears signature to 0 |
| in | 1 | clear | sync clear signature (same as reset for state) |
| in | 1 | valid | compress `data` into signature this cycle |
| in | 32 | data | input word |
| out | 32 | signature | current MISR signature (registered) |

Function: Multiple-Input Signature Register. Each valid cycle:
`sig <= {sig[30:0], feedback} ^ data;` where
`feedback = sig[31] ^ sig[21] ^ sig[1] ^ sig[0]`.
Purely sequential, no memory. **Runtime probe:** signature.

---

### C-03: sync_fifo — single-clock FIFO

**Model:** 7B | **Depends on:** none | **~80 lines**

Parameters: `WIDTH = 32`, `DEPTH = 16` (power of 2), `AW = $clog2(DEPTH)`

| Dir | Width | Port | Description |
|---|---|---|---|
| in | 1 | clk | clock |
| in | 1 | rst | sync reset |
| in | 1 | wr_en | push when high and not full |
| in | WIDTH | wdata | write data |
| in | 1 | rd_en | pop when high and not empty |
| out | WIDTH | rdata | read data, valid when not empty (FWFT/show-ahead) |
| out | 1 | full | registered full flag |
| out | 1 | empty | registered empty flag |
| out | AW+1 | count | current occupancy |

Function: first-word-fall-through FIFO on inferred dual-port RAM
(`logic [WIDTH-1:0] mem [DEPTH];`). Write ignored when full, read ignored when empty
(no error, just gated). Pointers AW+1 bits; full = ptrs equal except MSB; empty = ptrs equal.
**Runtime probe:** full, empty, count.

---

### C-04: rr_arbiter — round-robin arbiter

**Model:** 7B (review with 14B) | **Depends on:** none | **~70 lines**

Parameters: `N = 4` (requesters)

| Dir | Width | Port | Description |
|---|---|---|---|
| in | 1 | clk | clock |
| in | 1 | rst | sync reset, priority pointer to 0 |
| in | N | req | request bitmap |
| out | N | grant | one-hot grant, **registered**, at most one bit set |
| out | 1 | grant_valid | some grant active |
| out | $clog2(N) | grant_id | binary index of grant |

Function: rotating-priority round robin. Search starts from the requester *after* the last
granted one. Implement with the classic double-request-vector trick:
`{req,req} >> (last+1)`, find first set bit, rotate back. Pointer updates only on a cycle
where a grant is issued. If req==0, grant==0, pointer holds.
**Runtime probe:** grant, grant_id.

---

### C-05: skid_buffer — valid/ready pipeline register

**Model:** 7B | **Depends on:** none | **~60 lines**

Parameters: `WIDTH = 32`

| Dir | Width | Port | Description |
|---|---|---|---|
| in | 1 | clk | clock |
| in | 1 | rst | sync reset |
| in | 1 | s_valid | upstream valid |
| out | 1 | s_ready | upstream ready |
| in | WIDTH | s_data | upstream data |
| out | 1 | m_valid | downstream valid (registered) |
| in | 1 | m_ready | downstream ready |
| out | WIDTH | m_data | downstream data (registered) |

Function: full-throughput pipeline stage with one skid slot: breaks the ready path
combinationally (s_ready is a registered signal). No data loss, no duplication, standard
2-register skid buffer. **Runtime probe:** s_ready, m_valid.

---

### C-06: crc16_gen — CRC-16 over parallel data

**Model:** 7B | **Depends on:** none | **~50 lines**

Parameters: `DW = 32` (data width per cycle)

| Dir | Width | Port | Description |
|---|---|---|---|
| in | 1 | clk | clock |
| in | 1 | rst | sync reset, crc <= 16'hFFFF |
| in | 1 | init | reinit crc to 16'hFFFF |
| in | 1 | valid | absorb `data` this cycle |
| in | DW | data | input word |
| out | 16 | crc | current CRC (registered) |

Function: CRC-16-CCITT, poly 0x1021, init 0xFFFF, no reflection, processing DW bits per
cycle via an unrolled combinational next-CRC function (`function automatic [15:0] crc_next`)
applied bit-MSB-first, then registered. Same module used by TX (generate) and RX (check:
absorb payload+crc, result must be a fixed residue / or compare fields — see d2d spec).
**Runtime probe:** crc.

---

### C-07: sync_2ff + pulse_sync — CDC synchronizers (one file, two modules)

**Model:** 14B | **Depends on:** none | **~60 lines**

**sync_2ff** — Parameters: `WIDTH = 1`

| Dir | Width | Port | Description |
|---|---|---|---|
| in | 1 | clk_dst | destination clock |
| in | 1 | rst_dst | sync reset in dst domain |
| in | WIDTH | d | async input (quasi-static or gray-coded only) |
| out | WIDTH | q | 2-flop synchronized output |

Two back-to-back flops, `(* ASYNC_REG = "true" *)` on both.

**pulse_sync** — single-cycle pulse from clk_src domain to one clean single-cycle pulse in
clk_dst domain. Ports: clk_src, rst_src, pulse_in; clk_dst, rst_dst, pulse_out.
Implementation: toggle flop in src domain, sync_2ff the toggle into dst, edge-detect.
**Runtime probe:** q / pulse_out.

---

### C-08: async_fifo — dual-clock gray-pointer FIFO (the CDC workhorse)

**Model:** 27B (this is the highest-risk leaf) | **Depends on:** sync_2ff | **~130 lines**

Parameters: `WIDTH = 40`, `DEPTH = 16` (power of 2), `AW = $clog2(DEPTH)`

| Dir | Width | Port | Description |
|---|---|---|---|
| in | 1 | wclk | write clock |
| in | 1 | wrst | sync reset, wclk domain |
| in | 1 | wr_en | push when !wfull |
| in | WIDTH | wdata | write data |
| out | 1 | wfull | full, wclk domain (registered) |
| in | 1 | rclk | read clock |
| in | 1 | rrst | sync reset, rclk domain |
| in | 1 | rd_en | pop when !rempty |
| out | WIDTH | rdata | read data (registered output OK) |
| out | 1 | rempty | empty, rclk domain (registered) |

Function: Cummings-style async FIFO. Binary+gray pointer pair per side; gray write pointer
crossed into rclk via internal 2-flop sync (instantiate `sync_2ff #(.WIDTH(AW+1))`), gray
read pointer crossed into wclk likewise. `wfull` when synced-rptr-gray equals wptr-gray
with top two bits inverted; `rempty` when synced-wptr-gray == rptr-gray. Memory is inferred
simple dual-port RAM. Both resets must be asserted together at system level (soc handles it).
**Runtime probe:** wfull, rempty.

---

### C-09: clk_div + reset_sync — clock/reset infrastructure (one file, two modules)

**Model:** 14B | **Depends on:** none | **~50 lines**

**clk_div** — Parameters: `DIV = 2` (even)

| Dir | Width | Port | Description |
|---|---|---|---|
| in | 1 | clk_in | input clock |
| in | 1 | rst | sync reset |
| out | 1 | clk_out | divided clock, 50% duty, **driven from a flop** |

Toggle-flop divider (counter compare for DIV>2). **Protium/Palladium clocking rule:
prototype clocks are tool-generated ("fake clocks") declared in the IXCOM clock
specification at compile time — RTL must NEVER derive a design clock from a flop in
Protium builds.** clk_div exists only for a future pure-FPGA port; it is **excluded from
all Protium filelists**. On the X3, clk_a and clk_b are separate primary clocks with
their 2:1 ratio defined in the clock spec (see file 07).

**reset_sync** — async assert / sync de-assert conditioner per domain.
Ports: clk, arst_n_in (async), rst_out (sync active-high, released after 4 clk edges).
Internal 4-flop shift register with async preset. **Runtime probe:** rst_out.

---

## Leaf validation (applies to every C-xx)

Sim: TB per block per `06_verification_plan.md` (directed + 10k random cycles vs DPI golden).
HW: **every leaf is its own hardware DUT** — compiled ALONE through IXCOM under a pin-only
`hw_wrap_<name>`, driven at runtime by **deposit/force on its input ports** (the runtime
tool is the testbench at this level), judged by the waveform criteria below. Only after a
leaf passes its row may it be instantiated one level up.

## Per-module HW bring-up & pass criteria (standalone IXCOM compiles)

| Module | Runtime deposit/force stimulus | Read in waveform | PASS when |
|---|---|---|---|
| lfsr32 | deposit seed=32'h1, pulse load; force enable=1 for 32 clks | prdata, valid | prdata cycle sequence identical to Xcelium run with same seed (compare first 8 + last value); prdata never 0; valid high every enabled clk |
| misr32 | force valid=1; deposit data = 1,2,4,…,32'h8000 over 16 clks | signature | signature after 16 clks == sim-recorded value; pulse clear → 0 |
| sync_fifo | deposit 4 pushes (0xA0..0xA3), then 4 pops | count, full, empty, rdata | count 0→4→0; rdata pops in order A0,A1,A2,A3; empty re-asserts; full never asserts |
| rr_arbiter | force req=4'b1111 for 8 clks; then req=4'b0101 | grant, grant_id | grant_id rotates 0,1,2,3,0…; then alternates 0,2,0,2; grant one-hot every clk |
| skid_buffer | force s_valid=1 with incrementing s_data; toggle m_ready ~50% | m_valid, m_data, s_ready | m_data strictly incrementing — no skipped or repeated value; full throughput while m_ready=1 |
| crc16_gen | pulse init; one valid clk with data=32'hDEADBEEF | crc | crc == value logged from sim dpi_crc16(0xDEADBEEF, 0xFFFF) |
| sync_2ff / pulse_sync | toggle d / pulse pulse_in (both clks in IXCOM clock spec) | q / pulse_out | q follows d after exactly 2 clk_dst edges; exactly one 1-clk pulse_out per pulse_in, never 0 or 2 |
| async_fifo | both clks at 2:1 in clock spec; deposit 4 writes wclk-side; then force rd_en rclk-side | wfull, rempty, rdata | data order preserved exactly; rempty deasserts within 3 rclk of first write; no flag glitching anywhere in the capture |
| reset_sync | release arst_n_in at runtime | rst_out | rst_out deasserts exactly 4 clk edges after release, single clean edge |
