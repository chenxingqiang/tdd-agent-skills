# Using tdd-agent-skills with Windsurf

## Setup

### One-click install

```bash
curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash -s -- --tool windsurf
```

This appends the core skills to `.windsurfrules` in your current directory (or creates the file if it does not exist). Windsurf loads `.windsurfrules` automatically.

**Install into a specific project:**

```bash
bash install.sh --tool windsurf --target ~/my-project
```

### Manual setup

Windsurf uses `.windsurfrules` for project-specific agent instructions:

```bash
# Create a combined rules file from your most important skills
cat /path/to/tdd-agent-skills/skills/test-driven-development/SKILL.md > .windsurfrules
echo "\n---\n" >> .windsurfrules
cat /path/to/tdd-agent-skills/skills/incremental-implementation/SKILL.md >> .windsurfrules
echo "\n---\n" >> .windsurfrules
cat /path/to/tdd-agent-skills/skills/code-review-and-quality/SKILL.md >> .windsurfrules
```

### Global Rules

For skills you want across all projects, add them to Windsurf's global rules:

1. Open Windsurf → Settings → AI → Global Rules
2. Paste the content of your most-used skills

## Recommended Configuration

Keep `.windsurfrules` focused on 2-3 essential skills to stay within context limits:

```
# .windsurfrules
# Essential tdd-agent-skills for this project

[Paste test-driven-development SKILL.md]

---

[Paste incremental-implementation SKILL.md]

---

[Paste code-review-and-quality SKILL.md]
```

## Usage Tips

1. **Be selective** — Windsurf's context is limited. Choose skills that address your biggest quality gaps.
2. **Reference in conversation** — Paste additional skill content into the chat when working on specific phases (e.g., paste `security-and-hardening` when building auth).
3. **Use references as checklists** — Paste `references/security-checklist.md` and ask Windsurf to verify each item.

---

## Running under OpenAI Symphony

When this tool is launched by [Symphony](https://github.com/openai/symphony) (autonomous tracker-driven runs spawned per Linear issue inside an isolated workspace), the agent's contract is the repo-owned [`WORKFLOW.md`](../WORKFLOW.md) at the project root. That file pins the same four-phase TDD protocol for every runtime, so behavior is identical regardless of which AI coding tool actually executes the turn.

Two integration paths:

1. **Direct mode** — point Symphony's `codex.command` at the tool's headless/CLI entry point if it already speaks the Codex app-server protocol over stdio.
2. **Adapter mode** — wrap the tool in a thin app-server shim that emits `session_started`, `turn_completed`, token usage, and approval/tool-call events. See the runner table and adapter checklist in [`references/symphony-spec.md`](../references/symphony-spec.md).

Either way, this tool's skills (installed above) plus `WORKFLOW.md` give you the full tdd-agent-skills lifecycle inside Symphony's autonomous runs. Read [`skills/symphony-orchestration/SKILL.md`](../skills/symphony-orchestration/SKILL.md) before authoring or auditing `WORKFLOW.md`.
