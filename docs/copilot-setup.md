# Using tdd-agent-skills with GitHub Copilot

## Setup

### One-click install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash -s -- --tool copilot
```

This copies all skills to `.github/skills/`, all agent personas to `.github/agents/`, and creates `.github/copilot-instructions.md` if it does not already exist.

**Install into a specific project:**

```bash
bash install.sh --tool copilot --target ~/my-project
```

### Manual install

Copilot supports creating agent skills using a `.github/skills/` directory in your repository. Each skill is a single `.md` file:

```bash
mkdir -p .github/skills

# Copy individual skills as flat .md files
cp /path/to/tdd-agent-skills/skills/test-driven-development/SKILL.md .github/skills/test-driven-development.md
cp /path/to/tdd-agent-skills/skills/code-review-and-quality/SKILL.md .github/skills/code-review-and-quality.md
cp /path/to/tdd-agent-skills/skills/incremental-implementation/SKILL.md .github/skills/incremental-implementation.md
```

For more details, refer [Creating agent skills for GitHub Copilot](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/create-skills).

### Agent Personas (agents.md)

Copilot supports specialized agent personas. Use the tdd-agent-skills agents:

```bash
# Copy agent definitions
cp /path/to/tdd-agent-skills/agents/code-reviewer.md .github/agents/code-reviewer.md
cp /path/to/tdd-agent-skills/agents/test-engineer.md .github/agents/test-engineer.md
cp /path/to/tdd-agent-skills/agents/security-auditor.md .github/agents/security-auditor.md
```

Invoke agents in Copilot Chat:
- `@code-reviewer Review this PR`
- `@test-engineer Analyze test coverage for this module`
- `@security-auditor Check this endpoint for vulnerabilities`

### Custom Instructions (User Level)

For skills you want across all repositories:

1. Open VS Code → Settings → GitHub Copilot → Custom Instructions
2. Add your most-used skill summaries

## Recommended Configuration

### .github/copilot-instructions.md

GitHub Copilot supports project-level instructions via `.github/copilot-instructions.md`.

```markdown
# Project Coding Standards

## Testing
- Write tests before code (TDD)
- For bugs: write a failing test first, then fix (Prove-It pattern)
- Test hierarchy: unit > integration > e2e (use the lowest level that captures the behavior)
- Run `npm test` after every change

## Code Quality
- Review across five axes: correctness, readability, architecture, security, performance
- Every PR must pass: lint, type check, tests, build
- No secrets in code or version control

## Implementation
- Build in small, verifiable increments
- Each increment: implement → test → verify → commit
- Never mix formatting changes with behavior changes

## Boundaries
- Always: Run tests before commits, validate user input
- Ask first: Database schema changes, new dependencies
- Never: Commit secrets, remove failing tests, skip verification
```

### Specialized Agents

Use the agents for targeted review workflows in Copilot Chat.

## Usage Tips

1. **Keep instructions concise** — Copilot instructions work best when focused. Summarize the key rules rather than including full skill files.
2. **Use agents for review** — The code-reviewer, test-engineer, and security-auditor agents are designed for Copilot's agent model.
3. **Reference in chat** — When working on a specific phase, paste the relevant skill content into Copilot Chat for context.
4. **Combine with PR reviews** — Set up Copilot to review PRs using the code-reviewer agent persona.

---

## Running under OpenAI Symphony

When this tool is launched by [Symphony](https://github.com/openai/symphony) (autonomous tracker-driven runs spawned per Linear issue inside an isolated workspace), the agent's contract is the repo-owned [`WORKFLOW.md`](../WORKFLOW.md) at the project root. That file pins the same four-phase TDD protocol for every runtime, so behavior is identical regardless of which AI coding tool actually executes the turn.

Two integration paths:

1. **Direct mode** — point Symphony's `codex.command` at the tool's headless/CLI entry point if it already speaks the Codex app-server protocol over stdio.
2. **Adapter mode** — wrap the tool in a thin app-server shim that emits `session_started`, `turn_completed`, token usage, and approval/tool-call events. See the runner table and adapter checklist in [`references/symphony-spec.md`](../references/symphony-spec.md).

Either way, this tool's skills (installed above) plus `WORKFLOW.md` give you the full tdd-agent-skills lifecycle inside Symphony's autonomous runs. Read [`skills/symphony-orchestration/SKILL.md`](../skills/symphony-orchestration/SKILL.md) before authoring or auditing `WORKFLOW.md`.
