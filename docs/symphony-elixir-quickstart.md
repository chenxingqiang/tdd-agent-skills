# Symphony Elixir Reference Implementation — Operator Quickstart

This guide walks an operator through bringing up the vendored
[OpenAI Symphony](https://github.com/openai/symphony) Elixir reference
implementation against this repository's canonical
[`WORKFLOW.md`](../WORKFLOW.md). For background on what Symphony is and
how it maps onto the four-phase TDD protocol, read
[`skills/symphony-orchestration/SKILL.md`](../skills/symphony-orchestration/SKILL.md)
and [`references/symphony-spec.md`](../references/symphony-spec.md) first.

> ⚠️ Symphony Elixir is **prototype software intended for evaluation
> only**, presented as-is. Do not deploy it untouched to production. See
> [`symphony/README.md`](../symphony/README.md) for the vendoring policy.

## Prerequisites

| Dependency | Purpose | Recommended install |
|------------|---------|---------------------|
| [mise](https://mise.jdx.dev/) | Pins the Erlang/Elixir versions used by Symphony (`symphony/elixir/mise.toml`) | `curl https://mise.run \| sh` |
| Linear personal API key | Tracker auth (SPEC §11.2). Settings → Security & access → Personal API keys | `export LINEAR_API_KEY=lin_api_...` |
| OpenAI Codex CLI | Default `codex.command` runtime. See <https://developers.openai.com/codex/app-server/> | per Codex docs |
| Linear project slug | The slug segment of your project's URL (e.g. `api-platform-d8ac9c6f0a3b`) | from Linear UI |

## 1. Configure the workflow

The repo root [`WORKFLOW.md`](../WORKFLOW.md) is the contract Symphony
will execute. **Edit only that file** — never the upstream sample at
`symphony/elixir/WORKFLOW.md`.

Required edits:

```yaml
tracker:
  project_slug: <your-linear-project-slug>   # SPEC §11.2
workspace:
  root: ~/symphony_workspaces                 # local fast disk recommended
hooks:
  after_create: |                             # bootstrap a fresh workspace
    git clone git@github.com:your-org/your-repo.git .
```

Keep `tracker.api_key: $LINEAR_API_KEY` as `$VAR` indirection (SPEC §15.3).
Tighten `codex.approval_policy` / `thread_sandbox` / `turn_sandbox_policy`
for untrusted environments per SPEC §15.5.

## 2. Provision the toolchain

```bash
cd symphony/elixir
mise trust              # whitelist the pinned mise.toml
mise install            # downloads Erlang/Elixir versions
mise exec -- elixir --version
```

## 3. Build Symphony

```bash
mise exec -- mix setup  # mix deps.get + assets.setup
mise exec -- mix build  # compiles + emits ./bin/symphony
```

## 4. Smoke test against one issue

```bash
export LINEAR_API_KEY=lin_api_<your-token>

# Bind Symphony to THIS repo's WORKFLOW.md (absolute path is safest):
mise exec -- ./bin/symphony "$(pwd)/../../WORKFLOW.md"
```

Watch the logs for:

- `[symphony][before_run]` — the hook from `WORKFLOW.md` fired (proves
  reload + hooks are wired).
- `session_started` / `turn_completed` events — Codex app-server is alive
  (SPEC §10.4).
- `issue_identifier=...` — Symphony picked up your test ticket.

To enable the optional Phoenix dashboard at <http://127.0.0.1:4000> for
the SPEC §13.7 JSON API plus an HTML status page:

```bash
mise exec -- ./bin/symphony "$(pwd)/../../WORKFLOW.md" --port 4000
```

To redirect per-issue Codex session logs:

```bash
mise exec -- ./bin/symphony "$(pwd)/../../WORKFLOW.md" --logs-root /var/log/symphony
```

## 5. Verify the four-phase TDD protocol is active

In a Symphony-spawned turn against your test issue, check that the agent:

1. **Declares a phase tag** (`[DESIGN]` / `[DEVELOPMENT]` / `[TESTING]` /
   `[VERIFICATION]`) as the first line of every turn.
2. Stays inside the per-issue workspace
   `<workspace.root>/<sanitized_issue_identifier>` (SPEC §9.5).
3. Moves the Linear issue from `Todo` to `In Progress` on first activity
   (Symphony does **not** do this — the agent must, see SPEC §11.5).
4. Comments on the issue with spec/plan/PR/CI evidence per phase.
5. Reaches the team's handoff state (commonly `Human Review`) before
   declaring success — *not* `Done`.
6. Runs the 13-item Production-Readiness Checklist
   ([`shipping-and-launch`](../skills/shipping-and-launch/SKILL.md))
   before any merge.

If any of these fail, the issue is in the agent's prompt, not Symphony.
Re-read [`WORKFLOW.md`](../WORKFLOW.md) and the
[`symphony-orchestration`](../skills/symphony-orchestration/SKILL.md)
skill.

## 6. Common operational checks

| Symptom | Likely cause | Reference |
|---------|--------------|-----------|
| `missing_tracker_api_key` on boot | `LINEAR_API_KEY` not exported | SPEC §6.3 |
| `missing_tracker_project_slug` | `tracker.project_slug` left as the placeholder | SPEC §6.3 |
| Worker killed after 5 minutes of silence | Stall detector fired (`codex.stall_timeout_ms`) — agent is not emitting progress | SPEC §8.5 |
| Retries pile up with `no available orchestrator slots` | `agent.max_concurrent_agents` too low for the active queue | SPEC §8.4 |
| Workspace under `/tmp` keeps reappearing after `Done` | Startup terminal cleanup ran but issue went terminal mid-run | SPEC §8.6 |
| Dashboard returns 404 for an issue you "just saw" | The orchestrator state is in-memory only — restart cleared it | SPEC §14.3 |
| Phoenix dashboard refuses connections | `--port` not passed *or* listener is bound to loopback (default) | SPEC §13.7 |

## 7. Updating the vendored snapshot

Follow the procedure in [`symphony/README.md`](../symphony/README.md) —
re-vendor mechanically from upstream and bump the pinned commit row. Do
**not** edit files under `symphony/elixir/` locally.

## See also

- [`symphony/README.md`](../symphony/README.md) — vendoring policy and
  upstream provenance.
- [`symphony/elixir/README.md`](../symphony/elixir/README.md) — upstream
  Elixir-specific README.
- [`WORKFLOW.md`](../WORKFLOW.md) — the contract Symphony executes.
- [`references/symphony-spec.md`](../references/symphony-spec.md) — SPEC
  reference, defaults cheat-sheet, error categories.
- Upstream SPEC: <https://github.com/openai/symphony/blob/main/SPEC.md>
