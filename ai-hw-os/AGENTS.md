# AGENTS.md — instructions for coding agents (Aider, Qwen Code, any agent)

You are working inside **ai-hw-os**, a hardware-engineering scaffolding repo. Follow these rules exactly; they override your defaults.

## Before any task
1. Read `00_profile/task_contract_template.md` — its rules apply to YOU (restate task, no invented signals/params, `MISSING:` when info absent, evidence-based self-check, `// END-OF-ANSWER` sentinel on deliverables).
2. Find your task in the routing table below; **read that skill file and follow its step-by-step process.** Read the paired cheat sheet if the topic is unfamiliar.
3. Files say "paste into a fresh session" — for agents this means: *read the file, apply it, and do not carry assumptions from unrelated earlier turns.*

## Task → files routing
| Task | Skill file (process) | Cheat sheet (facts) |
|---|---|---|
| Write RTL module | 06_rtl_design_patterns/skill_rtl_module_generation.md | 13_cheatsheets/CHEATSHEET_rtl_design_gotchas.md |
| Review RTL | 06.../skill_rtl_review.md | same |
| FSM/pipeline | 06.../skill_fsm_pipeline_design.md | same |
| FIFO/CDC (any 2-clock work) | 06.../skill_fifo_cdc_review.md | same + fpga_emulation |
| Testbench plan/code | 07_validation_patterns/skill_testbench_planning.md | CHEATSHEET_validation_debug.md |
| Assertions | 07.../skill_assertion_planning.md | same |
| Coverage | 07.../skill_coverage_planning.md | same |
| Log triage | 08_protium_vivado_flows/skill_log_triage.md | same |
| Debug failing run | 08.../skill_validation_debug.md | same |
| Arch doc write/review | 01_architecture_mental_models/skill_architecture_doc_*.md | CHEATSHEET_soc_architecture.md |
| Perf/accelerator math | 05_ai_accelerators/skill_* (pick by topic) | CHEATSHEET_ai_accelerators.md |
| Protocol question | 04_protocols/skill_* (pick by protocol) | CHEATSHEET_protocols_*.md |
| Build portfolio project | 10_portfolio_projects/templates/template_*.md | project_template.md + publishing_checklist.md |

## Hard rules
- **Never invent** signal names, parameters, spec behavior, or protocol constants. Quote the spec line you used. Unknown → `MISSING: <what>` and stop that part.
- **CDC gate:** any task touching 2+ clock domains — follow skill_fifo_cdc_review patterns exactly; if the pattern isn't one of the legal four, flag it, don't improvise.
- **Escalation:** when a skill file says ESCALATE, stop and report the reason to the human. Do not attempt the escalated work.
- Run the skill file's **quality checklist** before presenting output; show evidence per item, not checkmarks.
- No proprietary vendor content (Cadence/AMD/Xilinx/customer). Public, generic, synthetic only.
- Do not modify files under `00_profile/` or this file unless explicitly asked.
- RTL style: `always_ff`/`always_comb`, `logic`, enum FSMs, one module per file, module name = file name, `// END <name>` sentinel.

## Repo conventions
Windows repo (paths may appear as `D:\design_plans\ai-hw-os`); write LF line endings; Markdown files ≤ ~900 tokens where marked; toy examples are graded fixtures — change them only with the matching rubric updated (`11_evals_for_local_models/`).
