# Symphony Integration Reference

This document maps OpenAI [Symphony](https://github.com/openai/symphony) SPEC
v1 onto the tdd-agent-skills repo and explains how to keep behavior
consistent across every supported AI coding tool. It is a reference, not a
skill — agents should read `skills/symphony-orchestration/SKILL.md` first
and consult this document for SPEC-level detail.

> **Source of truth:** the Symphony SPEC at
> <https://github.com/openai/symphony/blob/main/SPEC.md>. When this document
> and the upstream SPEC disagree, the SPEC controls. Implementations should
> consult the targeted Codex app-server documentation/schema for protocol
> shape (SPEC §10).

---

## 1. What Symphony Is (and Is Not)

Symphony is a **long-running scheduler/runner** that:

- Polls an issue tracker (Linear today; the SPEC is tracker-agnostic).
- Maintains in-memory orchestration state with bounded concurrency.
- Creates one **per-issue workspace** under a configured root.
- Spawns one **coding-agent session** per issue inside that workspace.
- Re-applies the repo-owned `WORKFLOW.md` on change without restart.
- Emits structured logs and an OPTIONAL JSON+HTML observability surface.

Symphony is **not**:

- A tracker write client. Ticket transitions, comments, and PR links are
  performed by the coding agent (SPEC §1, §11.5).
- A general-purpose workflow engine.
- A sandbox or approval policy. Those are pass-through Codex config values
  and operator responsibilities (SPEC §15).
- A durable scheduler. Restart recovery is tracker- and filesystem-driven;
  retry timers and live sessions do not survive process restart (SPEC §14.3).

---

## 2. SPEC Section Map

| SPEC § | Topic | Where it lives in this repo |
|--------|-------|----------------------------|
| §1–§3 | Problem statement, goals, system overview | `skills/symphony-orchestration/SKILL.md` (Overview) |
| §4 | Domain model (Issue, Workspace, RunAttempt, LiveSession, RetryEntry) | This doc, §3 below |
| §5 | Workflow specification (front matter + prompt template) | `WORKFLOW.md` at repo root |
| §6 | Configuration resolution and dynamic reload | `WORKFLOW.md` comments + this doc, §4 |
| §7 | Orchestration state machine | This doc, §5 |
| §8 | Polling, scheduling, reconciliation | This doc, §5 |
| §9 | Workspace management and safety | `WORKFLOW.md` (hooks) + `skills/symphony-orchestration/SKILL.md` (Surfaces 2 and 5) |
| §10 | Agent runner protocol (Codex app-server) | This doc, §6 |
| §11 | Issue tracker integration (Linear) | This doc, §7 |
| §12 | Prompt construction | `WORKFLOW.md` body |
| §13 | Logging, status, observability | This doc, §8 |
| §14 | Failure model and recovery | `skills/symphony-orchestration/SKILL.md` (Surface 5) |
| §15 | Security and operational safety | `skills/security-and-hardening/SKILL.md` + this doc, §9 |

---

## 3. Domain Model Cheat-Sheet (SPEC §4)

| Entity | Key fields | Notes |
|--------|-----------|-------|
| Issue | `id`, `identifier`, `title`, `description`, `priority` (lower = higher), `state`, `branch_name`, `url`, `labels` (lowercased), `blocked_by[]`, `created_at`, `updated_at` | `id` for tracker lookups; `identifier` for humans. |
| Workspace | `path` (absolute), `workspace_key` (sanitized identifier), `created_now` | Path stays under `workspace.root`. |
| Run Attempt | `issue_id`, `issue_identifier`, `attempt` (null on first run), `workspace_path`, `started_at`, `status`, `error?` | `status` ∈ Preparing → Building → Launching → Initializing → Streaming → Finishing → Succeeded/Failed/TimedOut/Stalled/CanceledByReconciliation. |
| Live Session | `session_id = <thread_id>-<turn_id>`, `codex_app_server_pid`, `last_codex_event`, token counters, `turn_count` | Reuse `thread_id` across continuation turns. |
| Retry Entry | `issue_id`, `identifier`, `attempt` (1-based), `due_at_ms`, `timer_handle`, `error?` | Cleared when re-dispatched or released. |
| Orchestrator State | `running` map, `claimed` set, `retry_attempts` map, `completed` set, `codex_totals`, `codex_rate_limits`, current effective `poll_interval_ms` and `max_concurrent_agents` | Single in-memory authority. |

**Workspace key sanitization:** replace any character not in
`[A-Za-z0-9._-]` with `_` (SPEC §4.2, §9.5).

---

## 4. Configuration and Dynamic Reload (SPEC §5–§6)

### Front matter top-level keys

`tracker`, `polling`, `workspace`, `hooks`, `agent`, `codex`. Unknown keys
are ignored for forward compatibility. Extensions (e.g. `server` for the
optional HTTP dashboard, SPEC §13.7) MAY add their own top-level keys.

### Resolution pipeline

1. Select workflow path (CLI arg, otherwise cwd `WORKFLOW.md`).
2. Parse YAML front matter into a raw config map.
3. Apply built-in defaults for missing OPTIONAL fields.
4. Resolve `$VAR_NAME` indirection only for fields that explicitly contain
   `$VAR_NAME` (env values do not globally override YAML).
5. Coerce and validate. Path/command fields support `~` and `$VAR`
   expansion. Relative `workspace.root` resolves relative to the directory
   containing the selected `WORKFLOW.md`.

### Defaults summary (SPEC §6.4)

| Field | Default |
|-------|---------|
| `tracker.endpoint` (linear) | `https://api.linear.app/graphql` |
| `tracker.active_states` | `["Todo", "In Progress"]` |
| `tracker.terminal_states` | `["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]` |
| `polling.interval_ms` | `30000` |
| `workspace.root` | `<system-temp>/symphony_workspaces` |
| `hooks.timeout_ms` | `60000` |
| `agent.max_concurrent_agents` | `10` |
| `agent.max_turns` | `20` |
| `agent.max_retry_backoff_ms` | `300000` |
| `codex.command` | `codex app-server` |
| `codex.turn_timeout_ms` | `3600000` (1h) |
| `codex.read_timeout_ms` | `5000` |
| `codex.stall_timeout_ms` | `300000` (5m) |

### Dynamic reload (SPEC §6.2)

- Symphony detects `WORKFLOW.md` changes and re-applies them at runtime.
- Reloaded config applies to future dispatch, retries, reconciliation,
  hook execution, and agent launches.
- In-flight sessions are not automatically restarted on config change.
- Invalid reloads MUST NOT crash the service — Symphony keeps the last
  known-good effective configuration and emits an operator-visible error.
- Some extensions (e.g. an HTTP listener port change) MAY require restart.

### Dispatch preflight (SPEC §6.3)

Re-validated before each dispatch cycle. Failure skips dispatch for the
tick but keeps reconciliation active. Required checks:

- Workflow file loads and parses.
- `tracker.kind` is present and supported.
- `tracker.api_key` resolves to a non-empty value.
- `tracker.project_slug` present when `tracker.kind == "linear"`.
- `codex.command` present and non-empty.

---

## 5. Orchestration, Scheduling, Retry (SPEC §7–§8)

### Issue claim states

`Unclaimed → Claimed (Running | RetryQueued) → Released`. The orchestrator
is the only mutator. Reconciliation runs **before** dispatch on every tick.

### Candidate selection (SPEC §8.2)

An issue is dispatch-eligible only when **all** are true:

1. It has `id`, `identifier`, `title`, `state`.
2. State is in `active_states` and not in `terminal_states`.
3. Not in `running` and not in `claimed`.
4. Global concurrency slots available.
5. Per-state concurrency slots available.
6. `Todo` blocker rule: if state is `Todo`, no non-terminal blockers.

Sort: `priority ASC` (null last) → `created_at` ASC → `identifier` lex.

### Concurrency

- Global: `max(max_concurrent_agents - running_count, 0)`.
- Per-state: `max_concurrent_agents_by_state[state]` (key normalized to
  lowercase) or fall back to global.

### Backoff

- Continuation after clean exit: fixed 1000 ms.
- Failure-driven retry: `min(10000 * 2^(attempt - 1), agent.max_retry_backoff_ms)`.
- Cap at `max_retry_backoff_ms` (default 5m).

### Reconciliation (every tick, SPEC §8.5)

1. **Stall detection** — if `elapsed_ms` since last event (or `started_at`)
   exceeds `codex.stall_timeout_ms`, kill worker and queue retry. Disable
   when `stall_timeout_ms <= 0`.
2. **Tracker state refresh** — fetch states for all running IDs; terminal
   → kill + clean workspace; non-active → kill without cleanup; active →
   update snapshot. State-refresh failures keep workers running; retry on
   the next tick.

### Startup terminal cleanup (SPEC §8.6)

On boot, query terminal-state issues and remove their workspace
directories. Failure → log warning and continue.

---

## 6. Agent Runner Protocol (SPEC §10)

The Codex app-server protocol is the source of truth for message shapes.
Symphony controls *orchestration*, not protocol.

### Launch

- Command: `codex.command` (default `codex app-server`).
- Invocation: `bash -lc <codex.command>`.
- Working directory: per-issue workspace.
- Recommended max stdio line size: 10 MB.

### Session startup responsibilities

- Initialize app-server session per the targeted Codex version.
- Create or resume thread; supply absolute workspace path as cwd.
- First turn → full rendered prompt. Continuation turns → continuation
  guidance only on the same thread.
- Pass `approval_policy`, `thread_sandbox`, `turn_sandbox_policy` through
  to Codex.
- Advertise client-side tools (e.g. `linear_graphql`).
- Emit `session_id = "<thread_id>-<turn_id>"`. Reuse `thread_id` across
  continuation turns.

### Turn completion conditions

Targeted-protocol completion → success; failure/cancellation → failure;
`turn_timeout_ms` exceeded → failure; subprocess exit → failure.

### Emitted events (subset)

`session_started`, `startup_failed`, `turn_completed`, `turn_failed`,
`turn_cancelled`, `turn_ended_with_error`, `turn_input_required`,
`approval_auto_approved`, `unsupported_tool_call`, `notification`,
`other_message`, `malformed`. Each event SHOULD include `event`,
`timestamp`, `codex_app_server_pid`, optional `usage`, and a payload.

### Approval/tool-call policy (SPEC §10.5)

- Implementations MUST document their approval/sandbox/operator-confirmation
  posture.
- Approval and user-input requests MUST NOT stall a run indefinitely. The
  example "high-trust" posture auto-approves command and file-change
  approvals and treats user-input-required as hard failure.
- Unknown dynamic tool calls return a tool failure response and continue
  the session.

### `linear_graphql` extension (SPEC §10.5)

- Available only when `tracker.kind == "linear"`.
- Input shape: `{ "query": "...", "variables": {...} }`. `query` is
  REQUIRED, non-empty, must contain exactly one GraphQL operation.
- Result semantics: transport success without top-level GraphQL `errors`
  → `success=true`; presence of `errors` → `success=false` (preserve
  body); invalid input/missing auth/transport failure → `success=false`
  with error payload.

### Error mapping (RECOMMENDED)

`codex_not_found`, `invalid_workspace_cwd`, `response_timeout`,
`turn_timeout`, `port_exit`, `response_error`, `turn_failed`,
`turn_cancelled`, `turn_input_required`.

---

## 7. Issue Tracker Integration (SPEC §11)

### Required adapter operations

1. `fetch_candidate_issues()` — issues in active states for the configured
   project.
2. `fetch_issues_by_states(state_names)` — used for startup terminal
   cleanup.
3. `fetch_issue_states_by_ids(issue_ids)` — used for active-run
   reconciliation.

### Linear specifics (`tracker.kind == "linear"`)

- GraphQL endpoint default `https://api.linear.app/graphql`.
- Auth via `Authorization: <token>` header.
- `project_slug` maps to Linear project `slugId` filter.
- Page size default 50, network timeout 30 s, pagination REQUIRED.
- Normalization: `labels` lowercased; `blocked_by` from inverse `blocks`
  relations; `priority` integer-or-null; ISO-8601 timestamps.

### Error categories

`unsupported_tracker_kind`, `missing_tracker_api_key`,
`missing_tracker_project_slug`, `linear_api_request`, `linear_api_status`,
`linear_graphql_errors`, `linear_unknown_payload`,
`linear_missing_end_cursor`.

### Tracker writes (boundary, SPEC §11.5)

Symphony does not write to the tracker. The agent does — via tools
configured by the workflow prompt or the `linear_graphql` client-side
tool. A successful run typically reaches a workflow-defined handoff state
(commonly `Human Review`), not `Done`.

---

## 8. Logging, Status, Observability (SPEC §13)

### Required log context

- Issue logs: `issue_id`, `issue_identifier`.
- Session lifecycle logs: `session_id`.
- Use stable `key=value` phrasing. Never log API tokens.

### OPTIONAL HTTP server extension (SPEC §13.7)

Enabled by `server.port` in front matter or CLI `--port`. Bind loopback by
default. Endpoints (RECOMMENDED minimum):

- `GET /` — human-readable dashboard.
- `GET /api/v1/state` — `running`, `retrying`, `codex_totals`, `rate_limits`.
- `GET /api/v1/<issue_identifier>` — per-issue runtime/debug detail; 404
  with `{"error":{"code":"issue_not_found",...}}` when unknown.
- `POST /api/v1/refresh` — queue an immediate poll + reconciliation; 202
  Accepted with `{queued, coalesced, requested_at, operations}`.

The dashboard/API MUST be observability/control surfaces only; never make
orchestrator correctness depend on them. Errors use
`{"error":{"code":"...","message":"..."}}`.

### Token accounting

Prefer absolute thread totals (`thread/tokenUsage/updated`,
`total_token_usage`). Ignore delta-only payloads (`last_token_usage`).
Track deltas relative to last reported totals to avoid double-counting.

---

## 9. Security and Operational Safety (SPEC §15)

### Mandatory invariants

- Workspace path stays under `workspace.root`.
- Coding-agent cwd is the per-issue workspace path.
- Workspace directory names use sanitized identifiers.

### Recommended hardening

- Run under a dedicated OS user; restrict workspace root permissions;
  consider a dedicated volume.
- Tighten Codex `approval_policy`, `thread_sandbox`,
  `turn_sandbox_policy` rather than running fully permissive.
- Add OS/container/VM sandboxing, network restrictions, separate
  credentials.
- Filter dispatch eligibility by Linear project/team/label so untrusted
  tasks do not auto-reach the agent.
- Narrow `linear_graphql` to read-only when possible.

### Secret handling

- `$VAR` indirection for any secret in `WORKFLOW.md`.
- Never log API tokens or secret env values.
- Validate presence without printing.

### Hook script safety

- Hooks are arbitrary shell from `WORKFLOW.md` — treat them as fully
  trusted configuration.
- Always run with a timeout (`hooks.timeout_ms`).
- Truncate hook output in logs.

---

## 10. Cross-Tool Runner Table (the consistency layer)

Symphony launches `bash -lc <codex.command>` in the workspace and expects
the launched process to speak a Codex-compatible app-server protocol.
That gives any AI coding tool two paths to integrate:

| Tool | Path | What to set in `codex.command` | Notes |
|------|------|--------------------------------|-------|
| **OpenAI Codex CLI** | Direct | `codex app-server` (default) | Reference implementation. No adapter needed. |
| **Claude Code** | Adapter | A wrapper that exposes `claude --print --append-system-prompt $(cat WORKFLOW.md)` over an app-server shim | The shim must emit `session_started`, `turn_completed`, token usage events (SPEC §10.4). |
| **Cursor** (`cursor-agent` headless) | Adapter | Wrap `cursor-agent` in an app-server shim | Mount this repo's skills as `.cursor/rules/`. |
| **GitHub Copilot CLI** (`gh copilot`) | Adapter | Wrap `gh copilot` headless mode | Skills via `.github/skills/`. |
| **Gemini CLI** | Adapter | Wrap `gemini` non-interactive mode | Skills via `.gemini/skills/`. |
| **Windsurf** | Adapter | Wrap Windsurf's CLI/headless mode | Skills via `.windsurfrules`. |
| **OpenCode** | Adapter | Wrap `opencode` with `AGENTS.md` loaded | Skills via `skills/` in target repo. |
| **Kiro** | Adapter | Wrap Kiro's headless mode | Skills via `.kiro/skills/`. |
| **Trae** | Adapter | Wrap Trae's CLI | Skills via `.trae/rules/`. |

### Adapter checklist

A conforming adapter (the "shim") MUST:

1. Accept stdio framing per the targeted Codex app-server version.
2. On startup, emit a `session_started` event with `thread_id`, `turn_id`,
   `codex_app_server_pid`.
3. Execute the rendered prompt as the first turn; subsequent
   continuation-turn requests reuse the same `thread_id`.
4. Stream incremental output as `notification` events; surface tool calls
   as protocol-shaped events; emit `turn_completed` / `turn_failed` /
   `turn_cancelled` on terminal states.
5. Honor `cwd` as the per-issue workspace; reject any cwd outside it.
6. Map `approval_policy`, `thread_sandbox`, `turn_sandbox_policy` onto
   the wrapped runtime's equivalent controls or fail fast.
7. Include token usage in events when available — prefer absolute totals.
8. Treat user-input-required signals according to a documented policy
   (auto-approve, surface to operator, or fail) — never stall.
9. Implement `linear_graphql` (or return a tool failure) when
   `tracker.kind == "linear"`.

Because **the prompt — `WORKFLOW.md` — is the same regardless of tool**,
the tdd-agent-skills four-phase protocol is preserved end-to-end. That is
the consistency guarantee.

---

## 11. Bringing Symphony Up (operator quickstart)

> Use this as a sanity-check checklist when wiring Symphony into a project.
> Detailed setup lives in OpenAI's reference Elixir implementation — see
> the upstream repo's `elixir/README.md`.

1. **Install Symphony** per the upstream README. This repo does not
   redistribute Symphony.
2. **Adopt** `WORKFLOW.md` from this repo's root into your target project
   (or use this repo as the workspace itself).
3. **Set credentials.** Export `LINEAR_API_KEY`. Authenticate the Codex
   CLI (or your adapter's runtime).
4. **Pick a workspace root.** Keep it on a fast local disk. Do not place
   it inside the repo you are editing.
5. **Tighten approval/sandbox.** The defaults in `WORKFLOW.md` assume a
   trusted environment. For untrusted issues, narrow them per SPEC §15.5.
6. **Boot Symphony** with the `--port` flag to enable the OPTIONAL JSON
   API on loopback for monitoring.
7. **Open one issue** in the target Linear project as a smoke test before
   enabling broad dispatch.
8. **Watch the dashboard / `GET /api/v1/state`** for `running`, `retrying`,
   `codex_totals`, and rate-limit health.

If you are not using Linear, build an adapter that fulfills SPEC §11.1
(`fetch_candidate_issues`, `fetch_issues_by_states`,
`fetch_issue_states_by_ids`) and emits the normalized issue shape from
SPEC §4.1.1.

---

## 12. References

- Symphony SPEC v1: <https://github.com/openai/symphony/blob/main/SPEC.md>
- Symphony repo (reference Elixir implementation): <https://github.com/openai/symphony>
- OpenAI Codex app-server: <https://developers.openai.com/codex/app-server/>
- Harness engineering: <https://openai.com/index/harness-engineering/>
- This repo's canonical `WORKFLOW.md`: <../WORKFLOW.md>
- Skill: `skills/symphony-orchestration/SKILL.md`
