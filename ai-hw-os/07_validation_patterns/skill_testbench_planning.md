# Skill: Testbench Planning

**Purpose:** Produce a testbench plan (architecture + test list) that a 7B can then implement one piece at a time.
**Target model:** 14B plans; 7B implements each planned component later.
**When to use:** Before writing any TB code for a module with a spec.
**When not to use:** UVM class-library architecture (overkill here); no spec exists; system-level multi-module TB → 27B.

## Required input
- Module interface table + behavior bullets.
- Bug classes you care about (default: data loss, dup, ordering, corner values).

## Process
1. Restate DUT function and list its interfaces by protocol type (valid/ready, req/ack, plain).
2. Choose TB style: directed (≤3 interfaces, simple) vs constrained-random light (data-mover DUTs).
3. Define components table: `component | role | drives/monitors | complexity (7B-able? Y/N)`.
   Standard set: clock/reset gen, driver per input if, monitor per output if, scoreboard (reference model), test sequencer.
4. Define reference model: golden behavior in plain code (queue, counter, function).
5. Write test list: `test | stimulus | checks | covers which bug class`.
   Mandatory rows: reset behavior; single transaction; back-to-back; backpressure (ready=0 bursts); corner values (0, max, wrap); randomized soak.
6. Define pass criteria per test (self-checking — no waveform eyeballing as the *criterion*).

## Output format
Three tables (components, reference model I/O, test list) + pass criteria bullets. No TB code in this skill.

## Quality checklist
- [ ] Every DUT output is monitored and checked by something
- [ ] Every bug class maps to ≥1 test
- [ ] Backpressure test present for every ready/valid interface
- [ ] Each component marked 7B-able or not (drives later routing)
- [ ] Pass criteria are machine-checkable (`$error` on mismatch)

## Common mistakes
- Planning stimulus but no checker (tests that can't fail).
- Reference model duplicating RTL bugs (copy-pasting DUT logic as the model).
- Skipping reset-during-traffic test.
- One giant test instead of small named tests (undebuggable).

## Toy example (FIFO DUT)
| test | stimulus | check | bug class |
|---|---|---|---|
| t_fill_drain | push to full, pop to empty | data order via queue model; full/empty flags | data loss/order |
| t_backpressure | push while pop stalled 20 cyc | no overwrite; full asserts at depth | overflow |
| t_simultaneous | push+pop same cycle at half-full | count stable; order kept | ptr corner |

## Self-check
For each bug class in input: name the test that catches it. Any unmapped class → add a test or declare gap.

## Escalation rule
`ESCALATE` if: DUT has config registers changing behavior mid-traffic; multi-clock TB needed; reference model itself needs architecture decisions.
