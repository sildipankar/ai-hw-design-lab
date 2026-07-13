# 11 — ALINK: AXI4-Lite Two-Chiplet Link (small working design #1)

**Chain:** `alink_top` (supervisor logic) → **AXM chiplet** (AXI master) → *AXI4-Lite bus*
→ **AXS chiplet** (AXI slaves). Single tool clock (IXCOM clock spec). This is backlog D3
made real, sized so every module fits a 7B model.

```
alink_top                      (supervisor FSM + result latch + timeout + LEDs)
└── axm_chiplet     CHIPLET 1  (AXI master side)
    ├── axm_core               (traffic + protocol engine)
    │   ├── cmd_gen            (3-phase self-test command generator, lfsr32 + misr32)
    │   └── axm_engine         (AXI4-Lite master FSM with timeout)
    └── axil_pmon              (passive synthesizable protocol monitor)
        │
        ═ AXI4-Lite bus ═ (the chiplet-to-chiplet boundary)
        │
└── axs_chiplet     CHIPLET 2  (AXI slave side)
    ├── axs_dec                (1→2 address decoder + response mux)
    └── axs_bank               (slave container)
        ├── axs_regs           (register-file slave)
        └── axs_mem            (1024x32 SRAM slave, wraps sram_bank MI-01)
```

**Copy-paste unit for local models = the bus table below + one AL-xx section.**

## AXI4-Lite bus (ADDR_W=16, DATA_W=32) — paste with every AL spec

Directions shown for the MASTER; a slave port has them reversed. Prefix per port name in
each spec (`m_` master port, `s_` slave port).

| Ch | Signal | W | Dir(M) | Function |
|---|---|---|---|---|
| AW | awvalid | 1 | out | master presents a write address; MUST stay high until awready is seen |
| AW | awready | 1 | in | slave accepts the address in the cycle both are high |
| AW | awaddr | 16 | out | byte address of the write (word aligned, [1:0]=0) |
| W | wvalid | 1 | out | master presents write data; hold until wready |
| W | wready | 1 | in | slave accepts data |
| W | wdata | 32 | out | write data |
| W | wstrb | 4 | out | byte enables; this design always drives 4'hF |
| B | bvalid | 1 | in | slave's write response is valid; hold until bready |
| B | bready | 1 | out | master accepts response |
| B | bresp | 2 | in | 00=OKAY, 10=SLVERR, 11=DECERR |
| AR | arvalid | 1 | out | master presents read address; hold until arready |
| AR | arready | 1 | in | slave accepts read address |
| AR | araddr | 16 | out | byte address of the read |
| R | rvalid | 1 | in | read data valid; hold until rready |
| R | rready | 1 | out | master accepts read data |
| R | rdata | 32 | in | read data |
| R | rresp | 2 | in | response code, as bresp |

**Golden protocol rule (repeat to the model):** once a `*valid` is 1 it must stay 1 with
stable payload until its `*ready` is 1. `ready` may come before, with, or after `valid`.
One outstanding transaction at a time in this whole design (keeps everything simple).

**Memory map:** addr[15]=0 → regs block (0x0000: ID RO=32'hA11C_0001, 0x0004: SCRATCH0 RW,
0x0008: SCRATCH1 RW, 0x000C: WRCNT RO = count of accepted reg writes, others → SLVERR).
addr[15]=1 → mem block, 0x8000–0x8FFF = 1024 words.

---

### AL-01: cmd_gen — 3-phase self-test command generator

**Model:** 14B | **Depends on:** lfsr32, misr32 (paste C-01/C-02 port lists) | **~180 lines**

| Dir | Width | Port | Function |
|---|---|---|---|
| in | 1 | clk | single design clock |
| in | 1 | rst | sync active-high reset; returns FSM to IDLE, clears all counters |
| in | 1 | go | 1-clk pulse starts the 3-phase test from the beginning |
| in | 32 | seed | pattern seed, sampled on go |
| out | 1 | cmd_valid | a command is presented; held until cmd_ready |
| in | 1 | cmd_ready | axm_engine accepts the command this cycle |
| out | 1 | cmd_write | 1=write command, 0=read command |
| out | 16 | cmd_addr | target byte address |
| out | 32 | cmd_wdata | write payload (don't-care for reads) |
| in | 1 | rsp_valid | one response per command: for writes after B, for reads after R |
| in | 32 | rsp_rdata | read data returned (don't-care for writes) |
| in | 1 | rsp_err | 1 if bresp/rresp was nonzero OR engine timed out |
| out | 1 | done | latched: all 3 phases finished |
| out | 8 | err_cnt | data mismatches + protocol errors, saturating |
| out | 32 | chk_sig | MISR signature over every rsp_rdata (the sequence-correctness proof) |
| out | 3 | state_dbg | FSM state for probing |

**Architecture.** Two lfsr32 instances: `pat` (drives write data) and `mir` (mirror,
re-seeded identically at phase 2 start, produces expected readback). One misr32 absorbs
every rsp_rdata. Registers: `word_idx[6:0]` (0..63), `exp_word[31:0]`, per-phase compare
flags. FSM (enum, one-hot friendly): `IDLE → P1_WR (issue 64 writes to 0x8000+4*i, data
= pat.prdata, advance pat only on cmd accept) → P2_RD (issue 64 reads same addrs; on each
rsp_valid compare rsp_rdata vs mir.prdata, advance mir; absorb into MISR; err_cnt++ on
mismatch or rsp_err) → P3_REG (fixed directed list: write SCRATCH0=32'h5A5A_A5A5, read
compare; write SCRATCH1=32'hC3C3_3C3C, read compare; read ID compare 32'hA11C_0001; read
WRCNT compare 32'd2) → DONE (latch done)`. All outputs registered.

**Runtime probe:** state_dbg, err_cnt, chk_sig, done.

---

### AL-02: axm_engine — AXI4-Lite master FSM with timeout

**Model:** 14B | **Depends on:** none (bus table only) | **~170 lines**

| Dir | Width | Port | Function |
|---|---|---|---|
| in | 1 | clk, rst | clock / sync reset |
| in | 1 | cmd_valid | command available from cmd_gen |
| out | 1 | cmd_ready | asserted for 1 clk when engine latches the command (only in IDLE) |
| in | 1 | cmd_write | command direction |
| in | 16 | cmd_addr | command address |
| in | 32 | cmd_wdata | command write data |
| out | 1 | rsp_valid | 1-clk pulse: transaction finished (B or R received, or timeout) |
| out | 32 | rsp_rdata | latched rdata for reads |
| out | 1 | rsp_err | latched: nonzero resp code OR timeout |
| out | — | m_axil_* | full AXI4-Lite MASTER port — all 17 signals of the bus table |
| out | 1 | tmo_sticky | latches on first timeout, cleared only by rst (bring-up trigger) |
| out | 3 | state_dbg | FSM state |

**Architecture.** Latch the command into `q_write/q_addr/q_wdata` regs on accept. FSM:
`IDLE → (write) WR_REQ: assert awvalid AND wvalid together, drop each independently as
its ready arrives (two "seen" flags awdone/wdone) → WR_RESP: bready=1, wait bvalid,
capture bresp → RESP` and `IDLE → (read) RD_REQ: arvalid until arready → RD_RESP:
rready=1, wait rvalid, capture rdata/rresp → RESP`. RESP: pulse rsp_valid, back to IDLE.
Timeout: 12-bit counter `tmo_cnt` cleared in IDLE, ticks in every waiting state; at
0xFFF, abort to RESP with rsp_err=1 and set tmo_sticky (drop all valids first).
Valid signals are registered — never combinational from ready (avoids the classic
Vivado timing-loop / IXCOM combinational-cycle report).

**Runtime probe:** state_dbg, tmo_sticky, m_axil_awvalid/arvalid/bvalid/rvalid.

---

### AL-03: axil_pmon — passive synthesizable protocol monitor

**Model:** 14B | **Depends on:** none (bus table only) | **~130 lines**

Taps the bus (all 17 AXI signals are INPUTS here) and checks rules in silicon — this is
the block that replaces SVA on hardware.

| Dir | Width | Port | Function |
|---|---|---|---|
| in | 1 | clk, rst | |
| in | — | t_axil_* | all 17 bus signals as inputs (tap) |
| out | 16 | cnt_aw, cnt_ar | accepted AW / AR handshakes (valid&ready) |
| out | 16 | cnt_b, cnt_r | accepted B / R handshakes |
| out | 8 | cnt_errresp | responses with bresp/rresp != 0 |
| out | 1 | err_vdrop | sticky: any `*valid` deasserted before its ready (rule break) |
| out | 1 | err_orphan | sticky: bvalid seen with no outstanding write, or rvalid with no outstanding read |
| out | 1 | err_stall | sticky: any valid high > 4096 clks without ready (hang detector) |

**Architecture.** Per channel: 1-flop history of valid/ready to detect drop
(`valid_q & ~ready_q & ~valid`); payload-stability check optional v2. Outstanding
tracking: 2-bit up/down counters `outs_wr` (inc on AW&W both done, dec on B) and `outs_rd`
(inc on AR, dec on R); orphan = dec when zero. One shared 12-bit stall counter per
direction. All sticky flags are set-only flops cleared by rst.

**Runtime probe (this block IS a probe):** all outputs; **trigger candidates:**
err_vdrop|err_orphan|err_stall rise, cnt_errresp increment.

---

### AL-04: axm_core — traffic + engine wrapper (structural)

**Model:** 7B | **Depends on:** cmd_gen, axm_engine (paste AL-01, AL-02 port lists) | **~90 lines**

Pure wiring: cmd_* and rsp_* buses connect AL-01 ↔ AL-02 one-to-one. External ports:
clk, rst, go, seed[32] in; done, err_cnt[8], chk_sig[32], tmo_sticky, the m_axil_* master
port, and both state_dbg buses (rename `gen_state[2:0]`, `eng_state[2:0]`) out.
No logic at all. **Runtime probe:** gen_state, eng_state.

---

### AL-05: axm_chiplet — CHIPLET 1 TOP (exactly 2 submodules)

**Model:** 27B | **Depends on:** axm_core, axil_pmon (paste AL-03, AL-04 port lists) | **~120 lines**

axm_core drives the bus; axil_pmon taps the same wires. Boundary-register the status
outputs (not the AXI bus itself — it must pass through combinationally to the pins).

| Dir | Width | Port | Function |
|---|---|---|---|
| in | 1 | clk, rst | |
| in | 1 | go | from alink_top supervisor |
| in | 32 | seed | test seed |
| out | — | m_axil_* | chiplet AXI master port (17 signals, to axs_chiplet) |
| out | 1 | done | test finished |
| out | 8 | err_cnt | data/protocol error count |
| out | 32 | chk_sig | readback MISR signature |
| out | 3 | pmon_err | {err_stall, err_orphan, err_vdrop} |
| out | 16 | pmon_cnt_r | R-handshake count (traffic liveness probe) |
| out | 8 | dbg_bus | {tmo_sticky, done, gen_state[2:0], eng_state[2:0]} |

**Runtime probe:** dbg_bus, pmon_err, chk_sig.

---

### AL-06: axs_dec — 1→2 address decoder + response mux

**Model:** 14B | **Depends on:** none (bus table only) | **~150 lines**

| Dir | Width | Port | Function |
|---|---|---|---|
| in | 1 | clk, rst | |
| in | — | s_axil_* | slave port facing the master chiplet (17 signals) |
| out | — | m0_axil_* | master port to axs_regs (addr[15]==0) |
| out | — | m1_axil_* | master port to axs_mem (addr[15]==1) |
| out | 2 | dbg_sel | {rd_sel, wr_sel} currently-locked target (probe) |

**Architecture.** Because the system is one-outstanding, the decoder is a routed switch,
not a full crossbar: on awvalid, latch `wr_sel = awaddr[15]` and lock the write channels
(AW/W/B) to target wr_sel until B completes; on arvalid latch `rd_sel = araddr[15]` and
lock AR/R until R completes. Route = AND valid toward selected target, AND ready back,
mux B/R payloads by the lock register. Locks are registered → no combinational
valid↔ready loop. No DECERR needed (both addr[15] values are mapped).

**Runtime probe:** dbg_sel.

---

### AL-07: axs_regs — register-file AXI slave

**Model:** 14B | **Depends on:** none (bus table only) | **~150 lines**

| Dir | Width | Port | Function |
|---|---|---|---|
| in | 1 | clk, rst | |
| in | — | s_axil_* | AXI4-Lite slave port (17 signals) |
| out | 32 | scratch0, scratch1 | live register values (probe) |
| out | 16 | wrcnt | accepted-write counter (probe) |

**Architecture.** Slave write FSM: `W_IDLE (awready=wready=1... simplest: wait for BOTH
awvalid and wvalid high, then accept both in one cycle with awready&wready=1, latch addr
and data) → W_RESP (bvalid=1, bresp per decode, until bready)`. Read FSM: `R_IDLE
(arready=1; on arvalid latch araddr) → R_RESP (rvalid=1 with muxed rdata until rready)`.
Register decode on addr[7:0]: 0x00 ID (RO 32'hA11C_0001), 0x04/0x08 scratch RW, 0x0C
WRCNT RO; write to any other address → bresp=SLVERR (2'b10) and no state change; read of
unmapped → rdata=32'hDEAD_BEEF, rresp=SLVERR. WRCNT increments only on OKAY writes.

**Runtime probe:** scratch0, wrcnt.

---

### AL-08: axs_mem — SRAM-backed AXI slave

**Model:** 14B | **Depends on:** sram_bank (paste MI-01 ports: clk, en, we, addr[10],
wdata[32], rdata[32], rvalid) | **~140 lines**

| Dir | Width | Port | Function |
|---|---|---|---|
| in | 1 | clk, rst | |
| in | — | s_axil_* | AXI4-Lite slave port; word address into RAM = araddr/awaddr[11:2] |
| out | 16 | mem_wr_cnt | accepted memory writes (probe) |

**Architecture.** One `sram_bank #(.DW(32), .DEPTH(1024))` instance. Write FSM identical
shape to AL-07 (accept AW+W together → 1-cycle en&we pulse into RAM → B OKAY). Read FSM:
`R_IDLE (accept AR) → R_FETCH (en=1 we=0 one cycle) → R_WAIT (RAM latency: rvalid from
sram_bank) → R_RESP (rvalid out with captured rdata until rready)`. Always OKAY resp
(full 4KB range is backed).

**Runtime probe:** mem_wr_cnt, internal ram en/we (mark `(* keep *)`).

---

### AL-09: axs_bank — slave container (structural)

**Model:** 7B | **Depends on:** axs_regs, axs_mem (paste AL-07, AL-08 ports) | **~80 lines**

Feed-through hierarchy level: exposes two slave ports `s0_axil_*` (→ axs_regs) and
`s1_axil_*` (→ axs_mem), plus clk, rst, and the probe outputs of both children
(scratch0[32], wrcnt[16], mem_wr_cnt[16]). Zero logic — exists to prove deep-hierarchy
compile and per-level bring-up. **Runtime probe:** child probes passed up.

---

### AL-10: axs_chiplet — CHIPLET 2 TOP (exactly 2 submodules)

**Model:** 27B | **Depends on:** axs_dec, axs_bank (paste AL-06, AL-09 ports) | **~110 lines**

| Dir | Width | Port | Function |
|---|---|---|---|
| in | 1 | clk, rst | |
| in | — | s_axil_* | chiplet AXI slave port (from axm_chiplet) |
| out | 2 | dbg_sel | from axs_dec |
| out | 32 | dbg_scratch0 | live scratch0 |
| out | 16 | dbg_wrcnt, dbg_mem_wr_cnt | write counters |

Wiring: s_axil → axs_dec; dec m0 → bank s0, dec m1 → bank s1. **Runtime probe:** all dbg.

---

### AL-11: alink_top — DESIGN TOP (supervisor logic + 2 chiplets)

**Model:** 27B | **Depends on:** axm_chiplet, axs_chiplet (paste AL-05, AL-10 ports) | **~150 lines**

| Dir | Width | Port | Function |
|---|---|---|---|
| in | 1 | clk | tool clock (IXCOM clock spec) |
| in | 1 | arst_n | board reset → internal reset_sync (paste C-09 reset_sync ports) |
| in | 1 | run | rising edge starts test |
| in | 32 | seed | test seed |
| out | 1 | test_done, test_pass | results |
| out | 8 | err_cnt | from AXM |
| out | 32 | chk_sig | signature (compare vs sim golden) |
| out | 8 | led | {test_pass, test_done, pmon_err[2:0], tmo, heartbeat, run} |

**Supervisor logic (the "some logic" at top):** small FSM — IDLE → edge-detect run →
pulse go → WAIT (done OR 2^26-clk watchdog) → LATCH: test_pass = done & (err_cnt==0) &
(pmon_err==0) & ~tmo_sticky; test_done=1. AXI bus wires connect the two chiplet ports
directly (this net list IS the die-to-die boundary; in a future v2 it becomes d2d_link).
Heartbeat = counter MSB. **Runtime probe:** everything on the port list.

---

## Per-module HW bring-up (standalone IXCOM compiles)

Waveform dump convention: sim = `waves/sim_<module>.shm`, hardware capture =
`waves/hw_<module>_run<N>.fsdb` (one per bring-up run, N in the run log). "Trigger" =
the runtime capture-trigger expression to arm before forcing stimulus.

| Module | Force/Deposit stimulus | Trigger (arm capture on) | Monitor signals | Dump to check | PASS criteria |
|---|---|---|---|---|---|
| cmd_gen | deposit seed=1, pulse go; act as engine: force cmd_ready=1, and for each command deposit rsp_valid with correct rsp_rdata (from sim log); then rerun with ONE wrong rsp_rdata | state_dbg change; 2nd run: err_cnt[0] rise | cmd_valid/write/addr/wdata sequence, state_dbg, err_cnt, chk_sig, done | hw_cmd_gen_run1.fsdb | command sequence = 64 writes 0x8000..0x80FC (LFSR data), 64 reads, then the 6 directed P3 ops, exact order; clean run: err_cnt=0, chk_sig==sim, done=1; poisoned run: err_cnt==1 exactly |
| axm_engine | act as slave: deposit cmd (write 0x8004 data 0x55); force awready/wready 2 clks late, bvalid with bresp=00; then a read with rvalid data 0xAA; then a cmd where you never respond | tmo_sticky rise (3rd case) | m_axil_* all valids/readys, state_dbg, rsp_valid/rdata/err | hw_axm_engine_run1.fsdb | awvalid&wvalid held until each ready (no drop); bready then rsp_valid pulse; read returns 0xAA; no-response case: rsp_err=1 + tmo_sticky exactly at 0xFFF clks |
| axil_pmon | deposit legal handshake sequences on the tap inputs; then a valid-drop (awvalid 1 clk without awready); then bvalid with no prior AW/W | err_vdrop rise; err_orphan rise | all counters + 3 sticky errs | hw_axil_pmon_run1.fsdb | counters match number of deposited handshakes exactly; each sticky fires only on its violation and stays |
| axm_core | as cmd_gen row but respond on the m_axil_* pins instead (deposit slave-side signals) | done rise | gen_state, eng_state, chk_sig | hw_axm_core_run1.fsdb | identical result to cmd_gen row through the wiring |
| axm_chiplet | same as axm_core (you are the slave chiplet via deposit); pmon now watching live | pmon_err any rise (must NOT fire on clean run) | dbg_bus, pmon_err, pmon_cnt_r, chk_sig | hw_axm_chiplet_run1.fsdb | clean run: done=1, err_cnt=0, pmon_err=000, pmon_cnt_r==65 (64 mem reads + ID/WRCNT/scratch reads = per sim log); chk_sig==sim |
| axs_dec | act as master AND both slaves: deposit one write to 0x0004 and one read to 0x8000; deposit child-side readys/resps | dbg_sel change | dbg_sel, both m*_axil valids | hw_axs_dec_run1.fsdb | write routed to m0 only, read routed to m1 only; locks hold until B/R; no cross-talk cycle |
| axs_regs | deposit AXI writes/reads: SCRATCH0=0x11 then read; read ID; write 0x30 (unmapped) | s_axil_bvalid & bresp!=0 | scratch0, wrcnt, bresp/rresp, rdata | hw_axs_regs_run1.fsdb | readbacks exact; ID=0xA11C0001; unmapped write → SLVERR and wrcnt unchanged (stays 1) |
| axs_mem | deposit write 0x8010=0xCAFE, read 0x8010; read 0x8FFC (never written) | rvalid | rdata, rresp, mem_wr_cnt, ram en/we | hw_axs_mem_run1.fsdb | readback 0xCAFE with OKAY; R comes exactly 3 clks after AR accept (FSM+RAM latency per sim); unwritten read returns X-free constant after a full-region init run (see note below table) |
| axs_bank / axs_chiplet | replay axs_regs + axs_mem sequences through the top slave port | dbg_sel change | dbg_sel, dbg_scratch0, dbg_wrcnt, dbg_mem_wr_cnt | hw_axs_chiplet_run1.fsdb | same responses as the child-level runs, counters consistent |
| alink_top | deposit seed=1, force run=1 — nothing else | test_done rise; keep a 2nd armed trigger on pmon_err rise | led, err_cnt, chk_sig, test_pass, chiplet dbg buses | hw_alink_top_run1.fsdb | test_pass=1, err_cnt=0, chk_sig==sim golden (dpi_alink_golden(1)); repeat seeds 2,3; negative: runtime-force axs side arready=0 permanently → tmo_sticky → test_pass=0 and pmon err_stall=1 |

**X-state note (the #1 sim-vs-HW trap):** cmd_gen phase 1 writes the entire region it
later reads — never read-before-write on HW. The 0x8FFC directed read above is done
AFTER a full-region write run, purely to check the read path.

## Compile / Vivado P&R / hardware issues this design is designed to surface

- **Combinational valid↔ready loops:** axm_engine and axs_dec keep valids/locks
  registered; if a model generates a combinational ready path, IXCOM/Vivado reports a
  combinational cycle or a huge timing arc — the review checklist (Template D) catches it
  first. This is the AXI-specific lesson of the design.
- **BRAM inference:** axs_mem's sram_bank must map to BRAM in the Vivado stage — check
  the utilization report (1 RAMB36); if it mapped to LUTRAM/FF, the read pattern in the
  generated RTL broke the template.
- **Wide fanout at the boundary:** the 17-signal AXI bundle crossing the chiplet
  partition is the practice case for partition-pin budgeting on the X3 (see 07) — record
  the pin count the tool reports.
- **Hang debuggability:** everything that can wait has a watchdog (engine tmo, pmon
  err_stall, top watchdog) — a hang on HW always leaves a sticky breadcrumb + trigger.
