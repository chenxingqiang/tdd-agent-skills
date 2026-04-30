# Using tdd-agent-skills with Cursor

## Setup

### One-click install

```bash
curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash -s -- --tool cursor
```

This copies all skills as `.md` files into `.cursor/rules/` in your current directory. Cursor loads them automatically.

**Install into a specific project:**

```bash
bash install.sh --tool cursor --target ~/my-project
```

### Option 1: Rules Directory (Manual)

Cursor supports a `.cursor/rules/` directory for project-specific rules:

```bash
# Create the rules directory
mkdir -p .cursor/rules

# Copy skills you want as rules
cp /path/to/tdd-agent-skills/skills/test-driven-development/SKILL.md .cursor/rules/test-driven-development.md
cp /path/to/tdd-agent-skills/skills/code-review-and-quality/SKILL.md .cursor/rules/code-review-and-quality.md
cp /path/to/tdd-agent-skills/skills/incremental-implementation/SKILL.md .cursor/rules/incremental-implementation.md
```

Rules in this directory are automatically loaded into Cursor's context.

### Option 2: .cursorrules File

Create a `.cursorrules` file in your project root with the essential skills inlined:

```bash
# Generate a combined rules file
cat /path/to/tdd-agent-skills/skills/test-driven-development/SKILL.md > .cursorrules
echo "\n---\n" >> .cursorrules
cat /path/to/tdd-agent-skills/skills/code-review-and-quality/SKILL.md >> .cursorrules
```

### Option 3: Notepads

Cursor's Notepads feature lets you store reusable context. Create a notepad for each skill you use frequently:

1. Open Cursor → Settings → Notepads
2. Create a new notepad named "swe: Test-Driven Development"
3. Paste the content of `skills/test-driven-development/SKILL.md`
4. Reference it in chat with `@notepad swe: Test-Driven Development`

## Recommended Configuration

### Essential Skills (Always Load)

Add these to `.cursor/rules/`:

1. `test-driven-development.md` — TDD workflow and Prove-It pattern
2. `code-review-and-quality.md` — Five-axis review
3. `incremental-implementation.md` — Build in small verifiable slices

### Phase-Specific Skills (Load as Notepads)

Create notepads for skills you use contextually:

- "swe: Spec Development" → `spec-driven-development/SKILL.md`
- "swe: Frontend UI" → `frontend-ui-engineering/SKILL.md`
- "swe: Security" → `security-and-hardening/SKILL.md`
- "swe: Performance" → `performance-optimization/SKILL.md`

Reference them with `@notepad` when working on relevant tasks.

## Usage Tips

1. **Don't load all skills at once** — Cursor has context limits. Load 2-3 skills as rules and keep others as notepads.
2. **Reference skills explicitly** — Tell Cursor "Follow the test-driven-development rules for this change" to ensure it reads the loaded rules.
3. **Use agents for review** — Copy `agents/code-reviewer.md` content and tell Cursor to "review this diff using this code review framework."
4. **Load references on demand** — When working on performance, reference `@notepad performance-checklist` or paste the checklist content.

---

## Running under OpenAI Symphony

When this tool is launched by [Symphony](https://github.com/openai/symphony) (autonomous tracker-driven runs spawned per Linear issue inside an isolated workspace), the agent's contract is the repo-owned [`WORKFLOW.md`](../WORKFLOW.md) at the project root. That file pins the same four-phase TDD protocol for every runtime, so behavior is identical regardless of which AI coding tool actually executes the turn.

Two integration paths:

1. **Direct mode** — point Symphony's `codex.command` at the tool's headless/CLI entry point if it already speaks the Codex app-server protocol over stdio.
2. **Adapter mode** — wrap the tool in a thin app-server shim that emits `session_started`, `turn_completed`, token usage, and approval/tool-call events. See the runner table and adapter checklist in [`references/symphony-spec.md`](../references/symphony-spec.md).

Either way, this tool's skills (installed above) plus `WORKFLOW.md` give you the full tdd-agent-skills lifecycle inside Symphony's autonomous runs. Read [`skills/symphony-orchestration/SKILL.md`](../skills/symphony-orchestration/SKILL.md) before authoring or auditing `WORKFLOW.md`.
