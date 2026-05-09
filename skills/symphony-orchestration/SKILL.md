---
name: symphony-orchestration
description: Operates under OpenAI Symphony, the autonomous agent orchestrator that spawns one coding-agent session per tracker issue inside an isolated per-issue workspace. Use when the run was launched by Symphony, when editing or creating the repo's WORKFLOW.md contract, when a tracker issue (Linear) drives the work instead of a human prompt, or whenever phrases like "Symphony", "WORKFLOW.md", "per-issue workspace", "linear_graphql tool", or "app-server agent" appear. Maps Symphony SPEC sections 1 through 15 onto the four-phase TDD protocol so behavior is identical across Codex, Claude Code, Cursor, Copilot, Gemini CLI, Windsurf, OpenCode, Kiro, and Trae.
---

# Symphony Orchestration

## Overview

[Symphony](https://github.com/openai/symphony) is OpenAI's reference
orchestrator for autonomous coding-agent runs. It polls an issue tracker
(currently Linear), spawns one coding-agent session per eligible issue
inside an isolated per-issue workspace, and re-applies the repo-owned
`WORKFLOW.md` contract on every change without restart. **Symphony is a
scheduler/runner — it does not write to the tracker, edit the repo, or
make engineering decisions.** All of that is the agent's job.

This skill binds Symphony's lifecycle to the tdd-agent-skills four-phase
protocol so that *any* runtime spawned by Symphony — Codex app-server,
Claude Code, Cursor, GitHub Copilot, Gemini CLI, Windsurf, OpenCode, Kiro,
Trae — exhibits identical TDD discipline. The contract surface is a single
file (`WORKFLOW.md`) and the runtime contract is a single skill (this one).

## When to Use

- The run was launched by Symphony (you can detect this from `cwd` matching
  `<workspace.root>/<sanitized_issue_identifier>`, the presence of
  `LINEAR_API_KEY` in env, or an explicit `[symphony]` log line from the
  `before_run` hook).
- A user asks you to create, edit, validate, or migrate the repo's
  `WORKFLOW.md`.
- A tracker issue (Linear) is the source of truth for the task and there is
  no human in the loop for the current turn.
- The user mentions Symphony concepts: per-issue workspace, app-server,
  `linear_graphql` tool, continuation turn, retry backoff, stall timeout,
  reconciliation, dispatch preflight.
- You need to keep behavior consistent across multiple AI coding tools and
  Symphony is the chosen orchestrator.

**When NOT to use:**
- Interactive sessions where a human is driving turn-by-turn — use the
  normal `/spec` → `/plan` → `/build` lifecycle directly.
- Symphony-unrelated CI/CD orchestration — see `ci-cd-and-automation`.
- Generic agent prompt engineering — see `context-engineering`.

## How Symphony Maps to the Four-Phase Protocol

```
Symphony lifecycle              tdd-agent-skills phase           Skill(s)
────────────────────            ──────────────────────           ──────────────────────────────
Issue picked up (Todo)    ──▶   [DESIGN]                         spec-driven-development
First turn (active)       ──▶   [DESIGN] → [DEVELOPMENT]         spec → planning-and-task-breakdown
                                                                   → incremental-implementation
                                                                   → test-driven-development
Continuation turn         ──▶   [DEVELOPMENT] or [TESTING]       (resume from prior state)
Worker exit (clean)       ──▶   [TESTING]                        test-driven-development
Retry (failure)           ──▶   [VERIFICATION]                   debugging-and-error-recovery
                                                                   → spec-driven-development (refine)
Reaches handoff state     ──▶   ship gate                        shipping-and-launch (13-item checklist)
```

The four-phase tags (`[DESIGN]` / `[DEVELOPMENT]` / `[TESTING]` /
`[VERIFICATION]`) are declared as the first line of every turn — Symphony
itself does not enforce them, this skill does.

## The Seven Surfaces You Own

When a project adopts Symphony, this skill governs work across exactly
seven surfaces. Read each one carefully when you touch it.

### 1. `WORKFLOW.md` (the contract)

- Lives at the repo root. Version-controlled. **Never** contains literal
  secrets — use `$VAR` indirection per SPEC §15.3.
- Front matter is a YAML map. Top-level keys: `tracker`, `polling`,
  `workspace`, `hooks`, `agent`, `codex`. Unknown keys are ignored for
  forward compatibility (SPEC §5.3).
- Body is a Liquid-strict template with `issue` and `attempt` variables
  (SPEC §5.4). Unknown variables/filters MUST fail rendering.
- Edits are detected and re-applied at runtime (SPEC §6.2). Invalid edits
  do not crash the service — Symphony keeps the last known-good config and
  emits an operator-visible error.
- The repo's canonical `WORKFLOW.md` lives at the root of this repository
  and embeds the four-phase protocol. Use it as the starting template.

### 2. The per-issue workspace

- Path: `<workspace.root>/<sanitized_issue_identifier>` (SPEC §9.1).
- Reused across runs — successful runs do **not** auto-delete (SPEC §9.1).
  Reconcile previous-attempt state before mutating.
- Invariants you must respect (SPEC §9.5):
  1. cwd MUST equal the per-issue workspace path.
  2. Workspace path MUST stay under `workspace.root`.
  3. Workspace key MUST be sanitized (`[A-Za-z0-9._-]` only, others → `_`).
- Hooks (`after_create`, `before_run`, `after_run`, `before_remove`) live
  in `WORKFLOW.md`. Keep them idempotent and short — `hooks.timeout_ms`
  defaults to 60s.

### 3. Tracker writes (Linear)

Symphony reads the tracker but does **not** write to it. You must:

- Transition state on first activity (`Todo` → `In Progress`).
- Comment with: spec link, plan summary, PR URL, CI status, walkthrough.
- Reach the team's handoff state (commonly `Human Review`) — that counts
  as a successful Symphony run (SPEC §1, §11.5). You do **not** need to
  push the issue to `Done`.
- If the runtime advertises the `linear_graphql` client-side tool
  (SPEC §10.5), prefer it over reading `LINEAR_API_KEY` directly. Each call
  must be a single GraphQL operation; multi-operation documents are
  rejected as invalid input.

### 4. Continuation turns (SPEC §7.1, §10.3)

- The same coding-agent thread persists across continuation turns inside
  one worker session (up to `agent.max_turns`).
- The **first** turn receives the full rendered prompt. Continuation turns
  receive *continuation guidance only* — do not resend the original prompt.
- After a clean worker exit Symphony schedules a ~1s continuation retry to
  re-check whether the issue is still active.
- If `attempt` is non-null on entry, this is a retry/continuation: read
  prior turn output, tracker comments, and workspace state first.

### 5. Retry, stall, and reconciliation (SPEC §7, §8)

- Exponential backoff: `delay = min(10000 * 2^(attempt − 1), max_retry_backoff_ms)`.
- Stall detector: kills the worker after `codex.stall_timeout_ms` of
  silence (default 5m). Emit progress at least every few minutes.
- Reconciliation runs every tick and stops workers whose tracker state
  became terminal (workspace cleaned) or non-active (workspace preserved).
- Failure recovery is in-memory only — restart does not restore retry
  timers (SPEC §14.3). Do not assume durable scheduler state.

### 6. Approval, sandbox, and trust (SPEC §10.5, §15)

- `approval_policy`, `thread_sandbox`, `turn_sandbox_policy` are pass-
  through Codex config values. Tighten them for untrusted environments
  (SPEC §15.5). Do not assume permissive defaults.
- Approval/user-input requests MUST NOT stall the run. If you cannot
  satisfy a request, fail fast with a diagnostic (the implementation's
  policy may auto-approve, surface to operator, or fail — your job is to
  not hang).
- Workspace isolation is a baseline, not a substitute for sandbox/approval
  policy. See `security-and-hardening`.

### 7. The ship gate

A successful Symphony run does **not** imply production-ready. Before
declaring the run done (handoff state, PR ready for review, merge), run
the 13-item checklist in `shipping-and-launch` and record the result in
the tracker. The Production-Readiness Declaration is non-negotiable —
Symphony is a transport, not an exemption.

## Cross-Tool Consistency

Symphony's launch contract is `bash -lc <codex.command>` in the workspace
directory; the launched process must speak a Codex-compatible app-server
protocol over stdio. To use a runtime other than the OpenAI Codex CLI,
either:

1. **Direct mode** — point `codex.command` at a binary that already speaks
   the app-server protocol.
2. **Adapter mode** — wrap the runtime in a thin adapter that translates
   stdio app-server messages into the runtime's native protocol. The
   adapter is responsible for `thread_id`/`turn_id`, `session_started`,
   `turn_completed`, token usage, and approval/tool call events
   (SPEC §10.2, §10.4).

See `references/symphony-spec.md` for the per-tool runner table and
adapter checklist.

Regardless of runtime, the tdd-agent-skills lifecycle is preserved because
the *prompt* — `WORKFLOW.md` — is the same. That is the integration point.

## Process

1. **Detect Symphony context.** First line of any turn under Symphony must
   declare the phase. Confirm `cwd == workspace_path` and that you are
   inside `<workspace.root>/<sanitized_issue_identifier>`.
2. **Read the issue.** Pull `issue.identifier`, `issue.title`,
   `issue.description`, `issue.state`, `issue.labels`, `issue.blocked_by`,
   and `attempt` from the rendered prompt or continuation context.
3. **Walk the lifecycle in order.** DEFINE → PLAN → BUILD → VERIFY →
   REVIEW → SHIP. Each step maps to a skill. Skip a step only when its
   output already exists and is current.
4. **Move the tracker.** State transition on first activity; comment with
   evidence on each phase boundary.
5. **Honor stop conditions.** If you would otherwise violate a Universal
   Agent Rule, stop and leave a clear handoff in the tracker (see
   "Stop Conditions" in the canonical `WORKFLOW.md`).
6. **Run the ship gate.** No success declaration without the 13-item
   Production-Readiness Checklist.

## Driver Mode (Claude Code as the orchestrator)

When the user invokes `/symphony` with no Symphony runtime present —
i.e., **Claude Code itself plays the scheduler** — run the loop natively.
No Elixir, no Codex shim, no subprocess: one Claude session walks every
issue. Trade-off: serial (one issue at a time), no crash-resilience, no
multi-worker scaling. Acceptable for small queues, demos, and single-dev
projects; reach for the vendored Elixir runtime when you need parallelism
or durability.

### When to use Driver mode

- The user says "run Symphony", "process the queue", "drive the tracker",
  or `/symphony` with no live Elixir runtime.
- The repo has `WORKFLOW.md` at the root and a reachable tracker (Linear
  GraphQL or Supabase PostgREST).
- The user accepts that Claude itself is the loop (visible turn-by-turn,
  stoppable with Ctrl-C, no parallelism).

### Driver loop

The phase tag for the *driver itself* (between issues) is `[DESIGN]` —
you are scheduling, not coding. Each per-issue inner walk re-tags as it
enters DEFINE/PLAN/BUILD/etc.

1. **Boot.** Read `WORKFLOW.md` from repo root. Parse `tracker.kind`,
   `tracker.endpoint`, `tracker.api_key` (resolve `$VAR`), `tracker.active_states`,
   `workspace.root`, `agent.max_turns`. Refuse to run if any are missing
   or if literal secrets are inlined.
2. **Poll for next issue.** Query the tracker for issues whose state ∈
   `active_states`, ordered by `priority asc, created_at asc`, limit 1.
   - **Supabase**: `GET {endpoint}/rest/v1/issues?state=in.(Todo,...)&order=priority.asc.nullslast,created_at.asc&limit=1`
     with headers `apikey`, `Authorization: Bearer ...`.
   - **Linear**: GraphQL `issues(filter:{state:{name:{in:[...]}}})` —
     one operation per call.
   - If empty, exit cleanly with a summary. Do not busy-poll.
3. **Claim.** Transition the issue's state to the project's "in progress"
   label (commonly `In Progress`) via PATCH/mutation. Post a comment:
   `Symphony driver claimed at <ISO ts> — Claude Code session <session_id>`.
   Stop the run if the claim fails (another worker may hold it).
4. **Create or reconcile workspace.** Path = `{workspace.root}/{sanitized_id}`.
   If it doesn't exist: `git worktree add` from `main` (preferred) or
   `mkdir + git init`. If it does: respect SPEC §9.1 (no auto-delete),
   read prior state and continue.
5. **`cd` into the workspace** and run the per-issue inner walk:
   - `[DESIGN]` — `spec-driven-development` → write `SPEC.md`, commit.
   - `[DEVELOPMENT]` — `planning-and-task-breakdown` then
     `incremental-implementation` + `test-driven-development` (RED →
     GREEN → REFACTOR per task). Commit after each green.
   - `[TESTING]` — `test-driven-development` Testing Phase Independence:
     run the suite, report results, do not edit code.
   - `[VERIFICATION]` — `debugging-and-error-recovery` if red; otherwise
     proceed. Get human sign-off only if a *design* change is needed.
   - `[REVIEW]` — `code-review-and-quality` self-review.
   - **Ship gate** — `shipping-and-launch` 13-item checklist. Record each
     item as a tracker comment with evidence link.

   When the project ships `bin/tdd-cli` (Postgres-trigger-enforced TDD),
   prefer it over raw `git commit` for phase boundaries:
   `tdd-cli claim --issue X`, `tdd-cli spec`, `tdd-cli red`, `tdd-cli green`,
   `tdd-cli refactor`, `tdd-cli check`, `tdd-cli open-pr`, `tdd-cli merge`.
   The triggers reject out-of-order phase transitions, so they double as
   self-enforcement of the four-phase protocol.
6. **Hand off.** Open a PR (`git-workflow-and-versioning`), then transition
   the issue to the team's handoff state (commonly `Human Review`). Post a
   final comment with PR URL + checklist summary.
7. **Loop.** Return to step 2. Stop conditions:
   - No active issues remain.
   - User interrupts (Ctrl-C / explicit stop).
   - A Universal Agent Rule was about to be violated — stop and leave a
     handoff comment on the current issue.
   - You hit `agent.max_turns`-equivalent work without convergence: post
     a `[blocked]` comment, transition to `Needs Human` (or back to
     `Todo`), and continue to the next issue.

### Driver invariants

- One issue at a time. Never claim a second before the first reaches a
  terminal or handoff state.
- `cd` discipline: every shell command after step 5 runs inside the
  per-issue workspace. Verify with `pwd` after any tool that might reset
  cwd.
- Tracker writes are the *only* cross-issue state. Do not keep an
  in-memory queue snapshot — re-poll every iteration so external edits
  (humans reprioritizing, blocking, closing) take effect immediately.
- Secrets stay in env. Never echo `$LINEAR_API_KEY` or `$SUPABASE_KEY`
  into logs, commit messages, comments, or the conversation transcript.
- Resume-safety: if the driver is restarted mid-issue, on next boot the
  in-progress issue should be detected (state ≠ active_states but ≠
  terminal) and either resumed or handed off — do not silently re-claim.

### Driver red flags

- You're iterating step 2 without a state filter — that returns
  everything, including `Done`.
- You skipped the claim PATCH and started editing code. Tracker still
  shows `Todo` to other workers.
- Two workspaces exist for two different issues but you're editing in
  the wrong one. Re-check `pwd`.
- You opened a PR but forgot to transition the issue out of
  `In Progress`.
- The poll loop has been running for >10 iterations without claiming
  anything — the filter is wrong, or there's truly nothing to do (exit).


## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "Symphony said the run succeeded, so it's shippable." | Symphony only confirms the worker exited normally. The 13-item ship gate still applies. |
| "I don't need a phase tag — Symphony handles state." | Symphony tracks claim/run state, not TDD phase. The tag is how *you* enforce protocol on yourself across turns. |
| "I'll resend the full prompt on every continuation turn." | Continuation turns share thread history (SPEC §10.3). Resending wastes tokens and confuses context. Send only continuation guidance. |
| "I can edit code in `[TESTING]` to make this pass." | Forbidden by Universal Agent Rule #3. Switch to `[VERIFICATION]`, justify the change with evidence, then re-enter `[DEVELOPMENT]`. |
| "Just write to the tracker through Linear's API directly." | Use `linear_graphql` if it's advertised. Otherwise, mutate via tools the workflow exposes — never embed raw API tokens in agent context. |
| "The issue stayed in `In Progress`, but I'm done." | The team's handoff state (commonly `Human Review`) is the success condition. Move the issue. |
| "I need to cd out to fix something in a sibling workspace." | No. That violates SPEC §9.5 invariants. Stop and surface the cross-workspace concern as a separate tracker issue. |
| "The hook timed out, but the run looks fine — ignore it." | `after_create` and `before_run` failures are fatal (SPEC §9.4). Don't paper over them. |

## Red Flags

- You started writing code without declaring `[DESIGN]` or `[DEVELOPMENT]`.
- You modified files outside the per-issue workspace.
- You issued more than one GraphQL operation in a single `linear_graphql`
  tool call.
- You went silent for longer than `codex.stall_timeout_ms` without
  emitting progress.
- You declared success without running `shipping-and-launch`.
- The tracker still shows `Todo` after meaningful work happened.
- You added a literal secret to `WORKFLOW.md` instead of `$VAR`.
- You assumed retry timers survived a Symphony restart.
- You re-sent the full rendered prompt on a continuation turn.

## Verification

Before ending any Symphony-driven turn, verify:

- [ ] First line of the turn declared a phase tag.
- [ ] cwd is the per-issue workspace; no writes happened outside it.
- [ ] Tracker state and comments reflect what just happened.
- [ ] If approving a tool call required user input, you either satisfied
      it or failed fast — you did not stall.
- [ ] If this is a continuation turn, you used continuation guidance only.
- [ ] If declaring success, the 13-item ship checklist is recorded in the
      tracker with links to evidence.
- [ ] No secrets entered logs, comments, or commit messages.

For changes to `WORKFLOW.md` itself:

- [ ] YAML front matter parses as a map.
- [ ] Required tracker fields are present (`tracker.kind`, and
      `tracker.project_slug` when `kind == linear`).
- [ ] Liquid template renders against a sample `issue` + `attempt` without
      unknown-variable or unknown-filter errors.
- [ ] Hook scripts are idempotent and respect `hooks.timeout_ms`.
- [ ] Concurrency caps (`agent.max_concurrent_agents`,
      `max_concurrent_agents_by_state`) are positive integers.

## See Also

- `references/symphony-spec.md` — full SPEC §1–§15 reference, cross-tool
  runner table, adapter checklist, security guidance.
- `WORKFLOW.md` (repo root) — the canonical contract template.
- `spec-driven-development`, `planning-and-task-breakdown`,
  `incremental-implementation`, `test-driven-development`,
  `debugging-and-error-recovery`, `code-review-and-quality`,
  `shipping-and-launch` — the skills you walk through on every Symphony run.
- `security-and-hardening` — for tightening approval/sandbox posture
  beyond defaults.
- **Vendored Elixir reference impl:** [`symphony/elixir/`](../../symphony/elixir/)
  with [vendoring policy](../../symphony/README.md) and
  [operator quickstart](../../docs/symphony-elixir-quickstart.md).
- OpenAI Symphony SPEC v1: <https://github.com/openai/symphony/blob/main/SPEC.md>
- OpenAI Codex app-server: <https://developers.openai.com/codex/app-server/>
