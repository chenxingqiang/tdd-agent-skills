# tdd-agent-skills

This is the tdd-agent-skills project — a collection of production-grade Test-Driven Development skills for **all AI coding agents** (Claude Code, Cursor, GitHub Copilot, Gemini CLI, Windsurf, OpenCode, Kiro, and any agent that accepts Markdown instructions). Authored by Chen Xingqiang.

## Project Structure

```
skills/       → Core skills (SKILL.md per directory)
agents/       → Reusable agent personas (code-reviewer, test-engineer, security-auditor)
hooks/        → Session lifecycle hooks
.claude/commands/ → Slash commands (/spec, /plan, /build, /test, /review, /code-simplify, /ship, /symphony)
references/   → Supplementary checklists (testing, performance, security, accessibility, symphony-spec)
docs/         → Setup guides for different tools
WORKFLOW.md   → OpenAI Symphony orchestrator contract (per-issue runs)
symphony/     → Vendored Symphony Elixir reference implementation (Apache-2.0)
```

## TDD Development Protocol Phases

All agents — regardless of tool — follow a four-phase gated workflow:

```
DESIGN ──▶ DEVELOPMENT ──▶ TESTING ──▶ VERIFICATION
   ▲                            │            │
   └────────────────────────────┘            │  (approved design changes)
   ▲                                         │
   └─────────────────────────────────────────┘  (cycle repeats until done)
```

| Phase | Maps to | Non-negotiable rule |
|-------|---------|---------------------|
| **Design** | `spec-driven-development` | No code until the human approves the design |
| **Development** | `incremental-implementation` + `test-driven-development` | Follow approved design strictly; declare `[DEVELOPMENT]` |
| **Testing** | `test-driven-development` (Testing Phase Independence) | Run tests, report results — **do not modify code** |
| **Verification** | `spec-driven-development` (Iterative Refinement) | Propose minimal evidence-backed design changes; get human approval |

Before any merge to `main` complete the 13-item Production-Readiness Checklist in `shipping-and-launch` and declare completion to the human. See `AGENTS.md` for the full universal rule set.

## Skills by Phase

**Define:** spec-driven-development
**Plan:** planning-and-task-breakdown
**Build:** incremental-implementation, test-driven-development, context-engineering, source-driven-development, frontend-ui-engineering, api-and-interface-design
**Verify:** browser-testing-with-devtools, debugging-and-error-recovery
**Review:** code-review-and-quality, code-simplification, security-and-hardening, performance-optimization
**Ship:** git-workflow-and-versioning, ci-cd-and-automation, deprecation-and-migration, documentation-and-adrs, shipping-and-launch, symphony-orchestration

## Conventions

- Every skill lives in `skills/<name>/SKILL.md`
- YAML frontmatter with `name` and `description` fields
- Description starts with what the skill does (third person), followed by trigger conditions ("Use when...")
- Every skill has: Overview, When to Use, Process, Common Rationalizations, Red Flags, Verification
- References are in `references/`, not inside skill directories
- Supporting files only created when content exceeds 100 lines

## Commands

- `npm test` — Not applicable (this is a documentation project)
- Validate: Check that all SKILL.md files have valid YAML frontmatter with name and description

## Boundaries

- Always: Follow the skill-anatomy.md format for new skills
- Never: Add skills that are vague advice instead of actionable processes
- Never: Duplicate content between skills — reference other skills instead
