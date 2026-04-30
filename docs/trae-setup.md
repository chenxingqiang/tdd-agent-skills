# Using tdd-agent-skills with Trae

## Setup

### One-click install

```bash
curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash -s -- --tool trae
```

This copies all skills as `.md` files into `.trae/rules/` in your current directory. Trae loads them automatically.

**Install into a specific project:**

```bash
bash install.sh --tool trae --target ~/my-project
```

**Install to global user config:**

```bash
bash install.sh --tool trae --global
```

The `--global` flag installs skills to `~/.trae/rules/` so they are available in every project.

### Manual install

```bash
# Create the rules directory
mkdir -p .trae/rules

# Copy individual skills
cp /path/to/tdd-agent-skills/skills/test-driven-development/SKILL.md .trae/rules/test-driven-development.md
cp /path/to/tdd-agent-skills/skills/incremental-implementation/SKILL.md .trae/rules/incremental-implementation.md
cp /path/to/tdd-agent-skills/skills/code-review-and-quality/SKILL.md .trae/rules/code-review-and-quality.md
```

Skills are plain Markdown files. Trae discovers them automatically from `.trae/rules/` — no extra configuration required.

## Recommended Configuration

### Essential skills (always load)

Copy these three into `.trae/rules/`:

1. `test-driven-development.md` — Red-Green-Refactor, test pyramid, Prove-It pattern
2. `incremental-implementation.md` — Thin vertical slices, feature flags, rollback-friendly changes
3. `code-review-and-quality.md` — Five-axis review before merge

### Phase-specific skills (load as needed)

Copy additional skills into `.trae/rules/` based on your current work:

| Task | Skill |
|------|-------|
| Starting a new feature | `spec-driven-development.md` |
| Breaking down a spec | `planning-and-task-breakdown.md` |
| Building UI | `frontend-ui-engineering.md` |
| Designing an API | `api-and-interface-design.md` |
| Debugging | `debugging-and-error-recovery.md` |
| Security review | `security-and-hardening.md` |
| Performance work | `performance-optimization.md` |
| Deploying | `shipping-and-launch.md` |

## Agent Personas

Copy the specialist agent personas into your project's rules directory so Trae can apply them during reviews:

```bash
mkdir -p .trae/rules
cp /path/to/tdd-agent-skills/agents/code-reviewer.md .trae/rules/
cp /path/to/tdd-agent-skills/agents/test-engineer.md .trae/rules/
cp /path/to/tdd-agent-skills/agents/security-auditor.md .trae/rules/
```

| Agent | Role | Best for |
|-------|------|----------|
| `code-reviewer` | Senior Staff Engineer | Five-axis review before merge |
| `test-engineer` | QA Engineer | Test strategy, coverage analysis |
| `security-auditor` | Security Engineer | Vulnerability detection, OWASP audit |

## AGENTS.md

Copy `AGENTS.md` to your project root so Trae's AI agent respects the TDD Development Protocol, four-phase workflow, and universal agent rules:

```bash
cp /path/to/tdd-agent-skills/AGENTS.md ./AGENTS.md
```

## Usage Tips

1. **Don't load all skills at once** — Trae's context window is limited. Load the 2-3 skills most relevant to your current phase.
2. **Reference skills explicitly** — Tell Trae "Follow the test-driven-development rules for this change" to ensure it reads and applies the loaded skill.
3. **Use agents for review** — Invoke the `code-reviewer` or `security-auditor` persona when you need a structured review perspective.
4. **Combine with references** — The `references/` directory contains supplementary checklists (`testing-patterns.md`, `security-checklist.md`, etc.) that complement the skills. Paste relevant checklists into your session when working on specific quality areas.

## Further Reading

- [tdd-agent-skills getting started guide](getting-started.md)
- [Skill anatomy](skill-anatomy.md) — how each skill is structured

---

## Running under OpenAI Symphony

When this tool is launched by [Symphony](https://github.com/openai/symphony) (autonomous tracker-driven runs spawned per Linear issue inside an isolated workspace), the agent's contract is the repo-owned [`WORKFLOW.md`](../WORKFLOW.md) at the project root. That file pins the same four-phase TDD protocol for every runtime, so behavior is identical regardless of which AI coding tool actually executes the turn.

Two integration paths:

1. **Direct mode** — point Symphony's `codex.command` at the tool's headless/CLI entry point if it already speaks the Codex app-server protocol over stdio.
2. **Adapter mode** — wrap the tool in a thin app-server shim that emits `session_started`, `turn_completed`, token usage, and approval/tool-call events. See the runner table and adapter checklist in [`references/symphony-spec.md`](../references/symphony-spec.md).

Either way, this tool's skills (installed above) plus `WORKFLOW.md` give you the full tdd-agent-skills lifecycle inside Symphony's autonomous runs. Read [`skills/symphony-orchestration/SKILL.md`](../skills/symphony-orchestration/SKILL.md) before authoring or auditing `WORKFLOW.md`.
