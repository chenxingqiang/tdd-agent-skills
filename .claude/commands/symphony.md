---
description: Run or validate work under OpenAI Symphony — bind WORKFLOW.md to the four-phase TDD protocol
---

Invoke the tdd-agent-skills:symphony-orchestration skill.

`/symphony` is the entry point for any work that involves OpenAI
[Symphony](https://github.com/openai/symphony): autonomous agent runs
spawned per tracker issue inside per-issue workspaces, governed by a
repo-owned `WORKFLOW.md`.

## When to use

- You are running **inside** a Symphony-spawned workspace and need to know
  how the four-phase TDD protocol applies to autonomous turns.
- You are **adopting** Symphony into a project and need to author or
  validate `WORKFLOW.md`.
- You are **migrating** an existing repo to Symphony and need the
  cross-tool runner table.
- You are **debugging** a Symphony run (stalled session, retry storm,
  reconciliation surprise, tracker write failure).

## What this command does

1. Loads the `symphony-orchestration` skill, which maps SPEC §1–§15 onto
   the four-phase TDD protocol (DESIGN → DEVELOPMENT → TESTING →
   VERIFICATION).
2. Walks the user through one of three branches:
   - **Run mode** — you are inside a workspace; declare the phase tag,
     read the issue, walk the lifecycle (DEFINE → PLAN → BUILD → VERIFY →
     REVIEW → SHIP), and respect the seven Symphony surfaces.
   - **Author mode** — generate or update `WORKFLOW.md` at the repo root
     using the canonical template. Validate front matter (YAML map with
     `tracker`, `polling`, `workspace`, `hooks`, `agent`, `codex`) and
     prompt template (Liquid-strict, `issue` and `attempt` variables,
     unknown variables/filters fail).
   - **Audit mode** — review an existing `WORKFLOW.md` for SPEC
     conformance, secret hygiene (`$VAR` indirection only), hook
     idempotence, and approval/sandbox posture.
3. References `references/symphony-spec.md` for the full SPEC mapping,
   per-tool runner table, and adapter checklist.

## Hard rules (non-negotiable)

1. The first line of every Symphony-driven turn declares one of
   `[DESIGN]`, `[DEVELOPMENT]`, `[TESTING]`, `[VERIFICATION]`.
2. `WORKFLOW.md` never contains literal secrets — use `$VAR` indirection.
3. The 13-item Production-Readiness Checklist (`shipping-and-launch`) is
   required before any success declaration. Symphony is a transport, not
   a ship gate exemption.
4. `[TESTING]` turns must not modify implementation code. Switch to
   `[VERIFICATION]` first.
5. Continuation turns receive continuation guidance only — never resend
   the original rendered prompt.
6. Cross-workspace writes are forbidden. cwd MUST equal the per-issue
   workspace path (SPEC §9.5).

## See also

- `skills/symphony-orchestration/SKILL.md`
- `references/symphony-spec.md`
- `WORKFLOW.md` at the repo root (canonical template)
- Symphony SPEC: <https://github.com/openai/symphony/blob/main/SPEC.md>
