# TDD Agent Skills

**Production-grade Test-Driven Development skills for AI coding agents.**

> **Author:** Chen Xingqiang  
> **Repository:** [chenxingqiang/tdd-agent-skills](https://github.com/chenxingqiang/tdd-agent-skills)

TDD Agent Skills encodes Test-Driven Development workflows, quality gates, and best practices that senior engineers use when building software. Skills are packaged so AI agents follow TDD discipline consistently across every phase of development — write tests first, then code, then verify.

```
  DEFINE          PLAN           BUILD          VERIFY         REVIEW          SHIP
 ┌──────┐      ┌──────┐      ┌──────┐      ┌──────┐      ┌──────┐      ┌──────┐
 │ Idea │ ───▶ │ Spec │ ───▶ │ Test │ ───▶ │ Code │ ───▶ │  QA  │ ───▶ │  Go  │
 │Refine│      │  PRD │      │First │      │ Impl │      │ Gate │      │ Live │
 └──────┘      └──────┘      └──────┘      └──────┘      └──────┘      └──────┘
  /spec          /plan          /test         /build        /review       /ship
```

---

## Core TDD Principles

This project is governed by the following principles — all development artifacts, agent behaviors, and skill workflows must adhere to them:

1. **Test-Driven Development (TDD):** Write tests first, then code. This ensures requirements are clear and the code is verifiable.
2. **Phased Development:** The process is strictly divided into Design, Development, Testing, and Verification phases. Each phase has clear objectives to prevent uncontrolled changes.
3. **Design-First Precision:** The initial design must be detailed and precise. Decisions made in the Design phase should not be arbitrarily altered in later phases. Any changes require explicit justification and human confirmation.
4. **Minimal Change Principle:** Modifications during the Verification phase must be minimal and targeted, focusing solely on addressing specific issues identified by tests, not on large-scale refactoring.
5. **Production-Targeted Development:**
   - **English-Only & Professionalism:** All development artifacts (code, comments, documentation, commit messages) must be written in clear, professional English.
   - **No Mocking/Simulation:** Development must be conducted against real components and systems. The use of mocks, stubs, or simulated environments for core logic is prohibited.
   - **Production-Ready Focus:** Every artifact must be designed and implemented to be concise, maintainable, and directly deployable to a production environment.
6. **Real-Environment Validation:** All validation must be performed in the actual target system or a strictly identical environment.
7. **Minimize File Creation:** The default action should be to modify and extend existing code files. Creating new files should be a last resort, only when the existing codebase lacks a logically coherent place for the new functionality.
8. **Lean Documentation:** No superfluous reports. The primary documentation task after any feature completion is to update the project's `README.md`.
9. **Pre-Modification Review:** Before any change, a comprehensive review of existing materials must be performed. Changes must be minimal, necessary, and applied to existing artifacts.
10. **Human Approval Gate:** All critical decisions and modifications require review and approval by the human programmer.
11. **Collaborative Iteration:** Work closely through iterative cycles of Design → Development → Testing → Verification → Refinement.

---

## Commands

7 slash commands that map to the development lifecycle. Each one activates the right skills automatically.

| What you're doing | Command | Key principle |
|-------------------|---------|---------------|
| Define what to build | `/spec` | Spec before code |
| Plan how to build it | `/plan` | Small, atomic tasks |
| Build incrementally | `/build` | One slice at a time |
| Prove it works | `/test` | Tests are proof |
| Review before merge | `/review` | Improve code health |
| Simplify the code | `/code-simplify` | Clarity over cleverness |
| Ship to production | `/ship` | Faster is safer |

Skills also activate automatically based on what you're doing — designing an API triggers `api-and-interface-design`, building UI triggers `frontend-ui-engineering`, and so on.

---

## Quick Start

### One-click install

```bash
curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash
```

The installer fetches the repo automatically, then prompts you to choose a tool. Skip the prompt with `--tool`:

```bash
# Interactive (recommended — works with curl or a local clone)
curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash

# Non-interactive — pick a tool directly
curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash -s -- --tool cursor
curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash -s -- --tool windsurf
curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash -s -- --tool gemini
curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash -s -- --tool copilot
curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash -s -- --tool opencode
curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash -s -- --tool kiro
curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash -s -- --tool claude
curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash -s -- --tool all
```

Or clone first and run locally:

```bash
git clone https://github.com/chenxingqiang/tdd-agent-skills.git
cd tdd-agent-skills
bash install.sh
```

The `--tool` flag table:

| Flag | Installs for |
|------|-------------|
| `--tool cursor` | Cursor — all skills → `.cursor/rules/` |
| `--tool windsurf` | Windsurf — core skills → `.windsurfrules` |
| `--tool gemini` | Gemini CLI — all skills → `.gemini/skills/` |
| `--tool copilot` | GitHub Copilot — skills, agents, `copilot-instructions.md` |
| `--tool opencode` | OpenCode — `AGENTS.md` + `skills/` in your project |
| `--tool kiro` | Kiro — all skills → `.kiro/skills/` |
| `--tool claude` | Claude Code — local plugin layout |
| `--tool all` | Every tool above |

**Common options:**

```bash
# Install into a specific project
bash install.sh --tool cursor --target ~/my-project

# Install to user-level config directories
bash install.sh --tool cursor --global
bash install.sh --tool gemini --global
```

> Run `bash install.sh --help` for the full option reference.

---

### Manual setup per tool

<details>
<summary><b>Claude Code</b></summary>

**Marketplace (recommended):**

```
/plugin marketplace add chenxingqiang/tdd-agent-skills
/plugin install tdd-agent-skills@chen-tdd-agent-skills
```

> **SSH errors?** Switch to HTTPS for fetches:
> ```bash
> git config --global url."https://github.com/".insteadOf "git@github.com:"
> ```

**Local:**

```bash
git clone https://github.com/chenxingqiang/tdd-agent-skills.git
claude --plugin-dir /path/to/tdd-agent-skills
```

</details>

<details>
<summary><b>Cursor</b></summary>

Copy skills into `.cursor/rules/` — Cursor loads them automatically. See [docs/cursor-setup.md](docs/cursor-setup.md).

</details>

<details>
<summary><b>Windsurf</b></summary>

Append skill content to `.windsurfrules`. See [docs/windsurf-setup.md](docs/windsurf-setup.md).

</details>

<details>
<summary><b>Gemini CLI</b></summary>

```bash
gemini skills install https://github.com/chenxingqiang/tdd-agent-skills.git --path skills
```

Or install from a local clone and verify with `/skills list`. See [docs/gemini-cli-setup.md](docs/gemini-cli-setup.md).

</details>

<details>
<summary><b>GitHub Copilot</b></summary>

Copy skills to `.github/skills/`, agents to `.github/agents/`, and add summaries to `.github/copilot-instructions.md`. See [docs/copilot-setup.md](docs/copilot-setup.md).

</details>

<details>
<summary><b>OpenCode</b></summary>

Clone the repo, open it in OpenCode. The agent reads `AGENTS.md` and `skills/` automatically. See [docs/opencode-setup.md](docs/opencode-setup.md).

</details>

<details>
<summary><b>Kiro</b></summary>

Copy skills to `.kiro/skills/` (project) or `~/.kiro/skills/` (global). Kiro also reads `AGENTS.md`. See [Kiro skills docs](https://kiro.dev/docs/skills/).

</details>

<details>
<summary><b>Codex / Other Agents</b></summary>

Skills are plain Markdown — paste any `SKILL.md` into a system prompt, rules file, or conversation. See [docs/getting-started.md](docs/getting-started.md).

</details>

---

## All 20 Skills

The commands above are the entry points. Under the hood, they activate these 20 skills — each one a structured workflow with steps, verification gates, and anti-rationalization tables. You can also reference any skill directly.

### Define - Clarify what to build

| Skill | What It Does | Use When |
|-------|-------------|----------|
| [idea-refine](skills/idea-refine/SKILL.md) | Structured divergent/convergent thinking to turn vague ideas into concrete proposals | You have a rough concept that needs exploration |
| [spec-driven-development](skills/spec-driven-development/SKILL.md) | Write a PRD covering objectives, commands, structure, code style, testing, and boundaries before any code | Starting a new project, feature, or significant change |

### Plan - Break it down

| Skill | What It Does | Use When |
|-------|-------------|----------|
| [planning-and-task-breakdown](skills/planning-and-task-breakdown/SKILL.md) | Decompose specs into small, verifiable tasks with acceptance criteria and dependency ordering | You have a spec and need implementable units |

### Build - Write the code

| Skill | What It Does | Use When |
|-------|-------------|----------|
| [incremental-implementation](skills/incremental-implementation/SKILL.md) | Thin vertical slices - implement, test, verify, commit. Feature flags, safe defaults, rollback-friendly changes | Any change touching more than one file |
| [test-driven-development](skills/test-driven-development/SKILL.md) | Red-Green-Refactor, test pyramid (80/15/5), test sizes, DAMP over DRY, Beyonce Rule, browser testing | Implementing logic, fixing bugs, or changing behavior |
| [context-engineering](skills/context-engineering/SKILL.md) | Feed agents the right information at the right time - rules files, context packing, MCP integrations | Starting a session, switching tasks, or when output quality drops |
| [source-driven-development](skills/source-driven-development/SKILL.md) | Ground every framework decision in official documentation - verify, cite sources, flag what's unverified | You want authoritative, source-cited code for any framework or library |
| [frontend-ui-engineering](skills/frontend-ui-engineering/SKILL.md) | Component architecture, design systems, state management, responsive design, WCAG 2.1 AA accessibility | Building or modifying user-facing interfaces |
| [api-and-interface-design](skills/api-and-interface-design/SKILL.md) | Contract-first design, Hyrum's Law, One-Version Rule, error semantics, boundary validation | Designing APIs, module boundaries, or public interfaces |

### Verify - Prove it works

| Skill | What It Does | Use When |
|-------|-------------|----------|
| [browser-testing-with-devtools](skills/browser-testing-with-devtools/SKILL.md) | Chrome DevTools MCP for live runtime data - DOM inspection, console logs, network traces, performance profiling | Building or debugging anything that runs in a browser |
| [debugging-and-error-recovery](skills/debugging-and-error-recovery/SKILL.md) | Five-step triage: reproduce, localize, reduce, fix, guard. Stop-the-line rule, safe fallbacks | Tests fail, builds break, or behavior is unexpected |

### Review - Quality gates before merge

| Skill | What It Does | Use When |
|-------|-------------|----------|
| [code-review-and-quality](skills/code-review-and-quality/SKILL.md) | Five-axis review, change sizing (~100 lines), severity labels (Nit/Optional/FYI), review speed norms, splitting strategies | Before merging any change |
| [code-simplification](skills/code-simplification/SKILL.md) | Chesterton's Fence, Rule of 500, reduce complexity while preserving exact behavior | Code works but is harder to read or maintain than it should be |
| [security-and-hardening](skills/security-and-hardening/SKILL.md) | OWASP Top 10 prevention, auth patterns, secrets management, dependency auditing, three-tier boundary system | Handling user input, auth, data storage, or external integrations |
| [performance-optimization](skills/performance-optimization/SKILL.md) | Measure-first approach - Core Web Vitals targets, profiling workflows, bundle analysis, anti-pattern detection | Performance requirements exist or you suspect regressions |

### Ship - Deploy with confidence

| Skill | What It Does | Use When |
|-------|-------------|----------|
| [git-workflow-and-versioning](skills/git-workflow-and-versioning/SKILL.md) | Trunk-based development, atomic commits, change sizing (~100 lines), the commit-as-save-point pattern | Making any code change (always) |
| [ci-cd-and-automation](skills/ci-cd-and-automation/SKILL.md) | Shift Left, Faster is Safer, feature flags, quality gate pipelines, failure feedback loops | Setting up or modifying build and deploy pipelines |
| [deprecation-and-migration](skills/deprecation-and-migration/SKILL.md) | Code-as-liability mindset, compulsory vs advisory deprecation, migration patterns, zombie code removal | Removing old systems, migrating users, or sunsetting features |
| [documentation-and-adrs](skills/documentation-and-adrs/SKILL.md) | Architecture Decision Records, API docs, inline documentation standards - document the *why* | Making architectural decisions, changing APIs, or shipping features |
| [shipping-and-launch](skills/shipping-and-launch/SKILL.md) | Pre-launch checklists, feature flag lifecycle, staged rollouts, rollback procedures, monitoring setup | Preparing to deploy to production |

---

## Agent Personas

Pre-configured specialist personas for targeted reviews:

| Agent | Role | Perspective |
|-------|------|-------------|
| [code-reviewer](agents/code-reviewer.md) | Senior Staff Engineer | Five-axis code review with "would a staff engineer approve this?" standard |
| [test-engineer](agents/test-engineer.md) | QA Specialist | Test strategy, coverage analysis, and the Prove-It pattern |
| [security-auditor](agents/security-auditor.md) | Security Engineer | Vulnerability detection, threat modeling, OWASP assessment |

---

## Reference Checklists

Quick-reference material that skills pull in when needed:

| Reference | Covers |
|-----------|--------|
| [testing-patterns.md](references/testing-patterns.md) | Test structure, naming, mocking, React/API/E2E examples, anti-patterns |
| [security-checklist.md](references/security-checklist.md) | Pre-commit checks, auth, input validation, headers, CORS, OWASP Top 10 |
| [performance-checklist.md](references/performance-checklist.md) | Core Web Vitals targets, frontend/backend checklists, measurement commands |
| [accessibility-checklist.md](references/accessibility-checklist.md) | Keyboard nav, screen readers, visual design, ARIA, testing tools |

---

## How Skills Work

Every skill follows a consistent anatomy:

```
┌─────────────────────────────────────────────────┐
│  SKILL.md                                       │
│                                                 │
│  ┌─ Frontmatter ─────────────────────────────┐  │
│  │ name: lowercase-hyphen-name               │  │
│  │ description: Guides agents through [task].│  │
│  │              Use when…                    │  │
│  └───────────────────────────────────────────┘  │                                                                                                
│  Overview         → What this skill does        │
│  When to Use      → Triggering conditions       │
│  Process          → Step-by-step workflow       │
│  Rationalizations → Excuses + rebuttals         │
│  Red Flags        → Signs something's wrong     │
│  Verification     → Evidence requirements       │
└─────────────────────────────────────────────────┘
```

**Key design choices:**

- **Process, not prose.** Skills are workflows agents follow, not reference docs they read. Each has steps, checkpoints, and exit criteria.
- **Anti-rationalization.** Every skill includes a table of common excuses agents use to skip steps (e.g., "I'll add tests later") with documented counter-arguments.
- **Verification is non-negotiable.** Every skill ends with evidence requirements - tests passing, build output, runtime data. "Seems right" is never sufficient.
- **Progressive disclosure.** The `SKILL.md` is the entry point. Supporting references load only when needed, keeping token usage minimal.

---

## Project Structure

```
tdd-agent-skills/
├── install.sh                         # One-click installer for all tools
├── skills/                            # 20 core skills (SKILL.md per directory)
│   ├── idea-refine/                   #   Define
│   ├── spec-driven-development/       #   Define
│   ├── planning-and-task-breakdown/   #   Plan
│   ├── incremental-implementation/    #   Build
│   ├── context-engineering/           #   Build
│   ├── source-driven-development/     #   Build
│   ├── frontend-ui-engineering/       #   Build
│   ├── test-driven-development/       #   Build (Primary TDD skill)
│   ├── api-and-interface-design/      #   Build
│   ├── browser-testing-with-devtools/ #   Verify
│   ├── debugging-and-error-recovery/  #   Verify
│   ├── code-review-and-quality/       #   Review
│   ├── code-simplification/          #   Review
│   ├── security-and-hardening/        #   Review
│   ├── performance-optimization/      #   Review
│   ├── git-workflow-and-versioning/   #   Ship
│   ├── ci-cd-and-automation/          #   Ship
│   ├── deprecation-and-migration/     #   Ship
│   ├── documentation-and-adrs/        #   Ship
│   ├── shipping-and-launch/           #   Ship
│   └── using-agent-skills/            #   Meta: how to use this pack
├── agents/                            # 3 specialist personas
├── references/                        # 4 supplementary checklists
├── hooks/                             # Session lifecycle hooks
├── .claude/commands/                  # 7 slash commands
└── docs/                              # Setup guides per tool
```

---

## Why TDD Agent Skills?

AI coding agents default to the shortest path — which often means skipping tests, specs, security reviews, and the practices that make software reliable. TDD Agent Skills gives agents structured, test-first workflows that enforce the same discipline senior engineers bring to production code.

The TDD-first approach means:
- **Tests define behavior** before implementation begins
- **Red-Green-Refactor** is the mandatory cycle for every code change
- **No skipping verification** — "seems right" is never sufficient
- **Real environments only** — no mocks for core logic
- **Minimal, targeted changes** — especially during verification and bug fixes

Each skill encodes hard-won engineering judgment: *when* to write a spec, *what* to test, *how* to review, and *when* to ship. These aren't generic prompts — they're the kind of opinionated, process-driven workflows that separate production-quality work from prototype-quality work.

Skills bake in best practices from Google's engineering culture — including concepts from [Software Engineering at Google](https://abseil.io/resources/swe-book) and Google's [engineering practices guide](https://google.github.io/eng-practices/). You'll find Hyrum's Law in API design, the Beyonce Rule and test pyramid in testing, change sizing and review speed norms in code review, Chesterton's Fence in simplification, trunk-based development in git workflow, Shift Left and feature flags in CI/CD, and a dedicated deprecation skill treating code as a liability. These aren't abstract principles — they're embedded directly into the step-by-step workflows agents follow.

---

## Contributing

Skills should be **specific** (actionable steps, not vague advice), **verifiable** (clear exit criteria with evidence requirements), **battle-tested** (based on real workflows), and **minimal** (only what's needed to guide the agent).

See [docs/skill-anatomy.md](docs/skill-anatomy.md) for the format specification and [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## License

MIT - use these skills in your projects, teams, and tools.

---

## Author

**Chen Xingqiang** — [chenxingqiang](https://github.com/chenxingqiang)
