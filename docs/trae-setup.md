# Using tdd-agent-skills with Trae

## How Trae loads rules (read this first)

Trae auto-loads exactly one file: **`.trae/rules/project_rules.md`** (a single
plain markdown file, no frontmatter). Earlier versions of this guide suggested
copying every skill into `.trae/rules/` as separate files — that doesn't work,
those files are silently ignored by Trae.

The installer now writes:

```
.trae/
├── rules/
│   └── project_rules.md   # auto-loaded by Trae — bootstraps everything
├── Skills/
│   └── <skill-name>/
│       └── SKILL.md       # full skill bodies, loaded on demand by path reference
└── agents/
    └── <persona>.md       # specialist personas, loaded on demand by path reference
```

`project_rules.md` contains `AGENTS.md` (the universal rules) plus an index of
every skill and agent with their file paths. When you ask Trae to do something
("write a spec", "TDD this bug fix", "review this PR"), Trae reads the index in
`project_rules.md`, then opens the matching skill or persona file on demand.
This keeps Trae's context small while still giving it the full toolkit.

## Setup

### One-click install

```bash
curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash -s -- --tool trae
```

**Install into a specific project:**

```bash
bash install.sh --tool trae --target ~/my-project
```

This also drops `AGENTS.md` at the project root for tools that read it directly.

**Install to your global user config:**

```bash
bash install.sh --tool trae --global
```

Writes to `~/.trae/` so the rules apply in every project. (Note: Trae's user
rules normally live in IDE settings rather than the filesystem, so this path
is most useful when you're invoking Trae's CLI from arbitrary directories.)

### Manual install

```bash
mkdir -p .trae/rules .trae/Skills .trae/agents

# 1. The auto-loaded rules file. Start with AGENTS.md as the seed.
cp /path/to/tdd-agent-skills/AGENTS.md .trae/rules/project_rules.md

# 2. Full skills (referenced from project_rules.md, loaded on demand).
cp -r /path/to/tdd-agent-skills/skills/* .trae/Skills/

# 3. Agent personas (referenced from project_rules.md, loaded on demand).
cp /path/to/tdd-agent-skills/agents/*.md .trae/agents/
```

After copying, append a skill index to `project_rules.md` so Trae knows where
to look — or just run the installer, which does this for you.

## Recommended Configuration

The installer copies all skills and agents. You don't need to hand-pick a
subset because they're loaded on demand — Trae reads only the skill files
relevant to the current task.

If you want to slim things down anyway (slower IDE indexing, smaller repo
footprint), keep these three skills minimum:

1. `test-driven-development` — Red-Green-Refactor, test pyramid, Prove-It pattern
2. `incremental-implementation` — Thin vertical slices, feature flags
3. `code-review-and-quality` — Five-axis review before merge

## Agent Personas

The installer copies all personas under `.trae/agents/`:

| Agent | Role | Best for |
|-------|------|----------|
| `code-reviewer` | Senior Staff Engineer | Five-axis review before merge |
| `test-engineer` | QA Engineer | Test strategy, coverage analysis |
| `security-auditor` | Security Engineer | Vulnerability detection, OWASP audit |
| `tdd-pr-reviewer` | TDD discipline reviewer | Verifying RED-before-GREEN, phase tags |
| `issue-curator` | Issue triage | Cleaning up backlogs |
| `ontology-builder` | Domain modeling | Concept maps, glossaries |

Trae has no filesystem-level "agent" registration (its built-in agents are
GUI-managed), so these personas are read on demand the same way skills are:
ask Trae to "review this PR using `code-reviewer`" and it will open
`.trae/agents/code-reviewer.md` first.

## Usage Tips

1. **Reference skills explicitly.** Tell Trae "follow `test-driven-development`"
   instead of "be careful with tests" — the explicit name triggers the
   skill-index lookup.
2. **One persona at a time.** Loading multiple personas in one turn dilutes
   their voice. Pick the one that matches the task.
3. **Combine with references.** `references/testing-patterns.md`,
   `references/security-checklist.md`, etc. complement the skills. Paste the
   relevant checklist into your session when working on quality-specific work.
4. **Re-run the installer** after pulling updates — it overwrites
   `project_rules.md` with the latest skill/agent index.

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
