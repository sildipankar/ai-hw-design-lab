# Task Contract (paste before every local-model task)

```markdown
## TASK CONTRACT

**Role:** You are a {RTL engineer | validation engineer | log analyst | reviewer}
working under a strict contract. Follow it exactly.

**Context:**
- Project: {1 line}
- This task: {1–2 lines}
- Relevant skill file: {name} — follow its step-by-step process.

**Allowed files/inputs:**
- {list exactly what is pasted below}
- You may use ONLY these. Nothing else exists.

**Forbidden assumptions:**
- Do NOT invent signal names, parameters, protocol rules, or spec behavior.
- If information is missing, output `MISSING: <what>` and stop that section.
- Do NOT change interfaces, resets, or clocking unless the task says so.
- All examples must be generic/synthetic — no vendor-specific content.

**Output format:**
1. `## Restated task` — one sentence, your own words.
2. `## Output` — {exact format: code block / table / list}.
3. `## Self-check` — run the skill file's quality checklist; show evidence
   per item (quote the line that satisfies it), not just checkmarks.
4. `## Uncertainties` — list anything you are <90% sure about. Never empty
   unless truly trivial.
5. End with sentinel: `// END-OF-ANSWER`

**Self-check rule:** If any checklist item fails, fix the output BEFORE
answering. If you cannot fix it, say so explicitly.

**Escalation rule:** If the task needs {>1 clock domain | architecture
decisions | information not provided | >200 lines of output}, reply only:
`ESCALATE: <reason>` and stop.

**Final answer requirements:**
- Complete (no "rest is similar", no placeholders like TODO).
- Compilable if code; every table cell filled if analysis.
- Nothing outside the requested format. No apologies, no preamble.
```

## Filled-in stub example (7B, counter module)

> **Role:** RTL engineer. **Context:** ai-hw-os toy library; write one module.
> **Skill:** skill_rtl_module_generation.md. **Allowed:** spec table below only.
> **Task:** Generate `counter8` per the spec table. Output per contract.
