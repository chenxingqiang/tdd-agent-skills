# Getting Started with tdd-agent-skills

tdd-agent-skills works with any AI coding agent that accepts Markdown instructions. This guide covers the universal approach. For tool-specific setup, see the dedicated guides.

## TDD Development Protocol Workflow

All agents using this skill set — regardless of tool — follow the same four-phase development protocol. This section describes the universal workflow and the rules that apply in every phase.

### The Four Phases

```
DESIGN ──▶ DEVELOPMENT ──▶ TESTING ──▶ VERIFICATION
   ▲                            │            │
   └────────────────────────────┘            │  (approved design change)
   ▲                                         │
   └─────────────────────────────────────────┘  (cycle repeats)
```

| Phase | Skill | What the agent does |
|-------|-------|---------------------|
| **Design** | `spec-driven-development` | Clarifies requirements, generates a detailed design including production-readiness sections, drafts test-case outlines, commits the design doc. Waits for human approval before proceeding. |
| **Development** | `incremental-implementation` + `test-driven-development` | Implements code and executable unit tests strictly per the approved design. No scope deviation without human sign-off. Commits code + tests after human sign-off. |
| **Testing** | `test-driven-development` | Runs tests. Reports results in structured format (test name, expected, actual, design reference). **Makes no code changes.** Commits test results. |
| **Verification** | `spec-driven-development` | Reviews test failures. Suggests the *minimal* design change supported by evidence. Obtains human approval, then re-enters Development with the updated design. |

### Universal Rules for All Agents

Regardless of tool, every agent MUST:

1. **Declare the current phase** at the start of each interaction: `[DESIGN]`, `[DEVELOPMENT]`, `[TESTING]`, or `[VERIFICATION]`.
2. **Stop and ask** before advancing to the next phase. Never assume approval.
3. **Never modify code during Testing.** Record and report only.
4. **Apply Minimal Change Principle** before modifying any artifact — check whether the content already exists, and change only what is strictly necessary.
5. **Back all design changes with evidence** — cite the specific failing test and smallest fix.
6. **Commit after each phase** — design docs, then code, then test results, then refined design.
7. **Issue a Production Acceptance Declaration** before any merge to `main` — complete the 13-item checklist in `shipping-and-launch` and get human sign-off.

See `AGENTS.md` (in the repository root) for the authoritative rule set that applies to all agents.

## How Skills Work

Each skill is a Markdown file (`SKILL.md`) that describes a specific engineering workflow. When loaded into an agent's context, the agent follows the workflow — including verification steps, anti-patterns to avoid, and exit criteria.

**Skills are not reference docs.** They're step-by-step processes the agent follows.

## Quick Start (Any Agent)

### 1. Clone the repository

```bash
git clone https://github.com/chenxingqiang/tdd-agent-skills.git
```

### 2. Choose a skill

Browse the `skills/` directory. Each subdirectory contains a `SKILL.md` with:
- **When to use** — triggers that indicate this skill applies
- **Process** — step-by-step workflow
- **Verification** — how to confirm the work is done
- **Common rationalizations** — excuses the agent might use to skip steps
- **Red flags** — signs the skill is being violated

### 3. Load the skill into your agent

Copy the relevant `SKILL.md` content into your agent's system prompt, rules file, or conversation. The most common approaches:

**System prompt:** Paste the skill content at the start of the session.

**Rules file:** Add skill content to your project's rules file (CLAUDE.md, .cursorrules, etc.).

**Conversation:** Reference the skill when giving instructions: "Follow the test-driven-development process for this change."

### 4. Use the meta-skill for discovery

Start with the `using-agent-skills` skill loaded. It contains a flowchart that maps task types to the appropriate skill.

## Recommended Setup

### Minimal (Start here)

Load three essential skills into your rules file:

1. **spec-driven-development** — For defining what to build
2. **test-driven-development** — For proving it works
3. **code-review-and-quality** — For verifying quality before merge

These three cover the most critical quality gaps in AI-assisted development.

### Full Lifecycle

For comprehensive coverage, load skills by phase:

```
Starting a project:  spec-driven-development → planning-and-task-breakdown
During development:  incremental-implementation + test-driven-development
Before merge:        code-review-and-quality + security-and-hardening
Before deploy:       shipping-and-launch
```

### Context-Aware Loading

Don't load all skills at once — it wastes context. Load skills relevant to the current task:

- Working on UI? Load `frontend-ui-engineering`
- Debugging? Load `debugging-and-error-recovery`
- Setting up CI? Load `ci-cd-and-automation`

## Skill Anatomy

Every skill follows the same structure:

```
YAML frontmatter (name, description)
├── Overview — What this skill does
├── When to Use — Triggers and conditions
├── Core Process — Step-by-step workflow
├── Examples — Code samples and patterns
├── Common Rationalizations — Excuses and rebuttals
├── Red Flags — Signs the skill is being violated
└── Verification — Exit criteria checklist
```

See [skill-anatomy.md](skill-anatomy.md) for the full specification.

## Using Agents

The `agents/` directory contains pre-configured agent personas:

| Agent | Purpose |
|-------|---------|
| `code-reviewer.md` | Five-axis code review |
| `test-engineer.md` | Test strategy and writing |
| `security-auditor.md` | Vulnerability detection |

Load an agent definition when you need specialized review. For example, ask your coding agent to "review this change using the code-reviewer agent persona" and provide the agent definition.

## Using Commands

The `.claude/commands/` directory contains slash commands for Claude Code:

| Command | Skill Invoked |
|---------|---------------|
| `/spec` | spec-driven-development |
| `/plan` | planning-and-task-breakdown |
| `/build` | incremental-implementation + test-driven-development |
| `/test` | test-driven-development |
| `/review` | code-review-and-quality |
| `/ship` | shipping-and-launch |

## Using References

The `references/` directory contains supplementary checklists:

| Reference | Use With |
|-----------|----------|
| `testing-patterns.md` | test-driven-development |
| `performance-checklist.md` | performance-optimization |
| `security-checklist.md` | security-and-hardening |
| `accessibility-checklist.md` | frontend-ui-engineering |

Load a reference when you need detailed patterns beyond what the skill covers.

## Spec and task artifacts

The `/spec` and `/plan` commands create working artifacts (`SPEC.md`, `tasks/plan.md`, `tasks/todo.md`). Treat them as **living documents** while the work is in progress:

- Keep them in version control during development so the human and the agent have a shared source of truth.
- Update them when scope or decisions change.
- If your repo doesn’t want these files long‑term, delete them before merge or add the folder to `.gitignore` — the workflow doesn’t require them to be permanent.

## Tips

1. **Start with spec-driven-development** for any non-trivial work
2. **Always load test-driven-development** when writing code
3. **Don't skip verification steps** — they're the whole point
4. **Load skills selectively** — more context isn't always better
5. **Use the agents for review** — different perspectives catch different issues
