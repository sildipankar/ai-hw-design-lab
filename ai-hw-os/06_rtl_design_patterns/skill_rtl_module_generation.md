# Skill: RTL Module Generation

**Purpose:** Generate one clean, lint-safe SystemVerilog module from a complete spec table.
**Target model:** 7B (14B if spec has any ambiguity).
**When to use:** Single module, spec table complete, ≤150 lines expected, one clock domain.
**When not to use:** Multi-clock, missing spec fields, architecture choices needed, >1 module → ESCALATE.

## Required input
1. Filled interface table: `signal | dir | width | description`.
2. Behavior bullets (reset value, per-cycle behavior, corner cases).
3. Parameters table (name, default, legal range).

## Process
1. Restate the module's job in one sentence.
2. Echo the interface table back (catches misreads).
3. Write module skeleton: params → ports → typedefs → declarations.
4. Implement combinational logic (`always_comb` only).
5. Implement sequential logic (`always_ff`, async-reset-active-low unless spec says otherwise).
6. Add `// END <module_name>` sentinel.

## Output format
One ` ```systemverilog ` block, then Self-check, then Uncertainties.

## Quality checklist
- [ ] Every spec signal appears with exact name/width
- [ ] No latches: every `always_comb` output assigned on all paths
- [ ] Reset initializes every flop written in `always_ff`
- [ ] No blocking assigns in `always_ff`, no nonblocking in `always_comb`
- [ ] Widths match everywhere (no implicit truncation)
- [ ] Sentinel present

## Common mistakes
- Inventing extra ports (e.g., adding `clear` because "counters usually have one").
- `if (en)` forgotten around increment → free-running counter.
- Reset only some flops.
- Using `always @(*)` + `reg` old style instead of `always_comb`/`logic`.

## Toy example
Spec: `counter8` — `clk, rst_n` in; `en` in; `count[7:0]` out; wraps at max; reset→0.
```systemverilog
module counter8 (
  input  logic clk, rst_n, en,
  output logic [7:0] count
);
  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n)   count <= '0;
    else if (en)  count <= count + 8'd1;
endmodule // END counter8
```

## Self-check
Run the quality checklist; for each item quote the satisfying line.

## Escalation rule
`ESCALATE` if: 2+ clock domains; any spec field missing; behavior needs interpretation; output would exceed ~200 lines.
