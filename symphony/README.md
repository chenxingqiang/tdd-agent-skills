# Vendored: OpenAI Symphony (Elixir reference implementation)

This directory vendors the [OpenAI Symphony](https://github.com/openai/symphony)
**Elixir reference implementation** so that the repo-owned
[`WORKFLOW.md`](../WORKFLOW.md) contract at the project root can actually be
*run*, not just authored.

> ⚠️ **Upstream warning preserved:** Symphony Elixir is **prototype software
> intended for evaluation only and is presented as-is.** OpenAI recommends
> implementing your own hardened version based on
> [`SPEC.md`](https://github.com/openai/symphony/blob/main/SPEC.md). This
> repository ships the reference impl unchanged for reproducibility — do
> not deploy it to production untouched.

## Provenance

| Field | Value |
|-------|-------|
| Upstream repo | <https://github.com/openai/symphony> |
| Vendored path | `symphony/elixir/` ← upstream `elixir/` |
| Pinned commit | [`58cf97d`](https://github.com/openai/symphony/commit/58cf97da06d556c019ccea20c67f4f77da124bf3) — *fix(elixir): configure Codex app-server model via config* (2026‑04‑27) |
| License | Apache License 2.0 (see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE)) |
| Modifications | **None.** The tree is byte-identical to upstream at the pinned commit, so updates are a clean re-vendor. |

## Why vendor (and not submodule)

- One-step clone-and-run for users (`git clone` of this repo is enough).
- Stable pin — upstream is explicitly labeled prototype software; we want a
  known-good snapshot that does not silently change under users.
- License is permissive (Apache 2.0) and compatible with this repo's MIT
  license, provided `LICENSE` and `NOTICE` remain intact (kept here in
  full).
- No build-time network dependency for `mix deps.get` (still required —
  see Quickstart — but at least the source is local).

## Layout

```
symphony/
├── README.md          ← this file (vendoring policy)
├── LICENSE            ← Apache 2.0 (upstream)
├── NOTICE             ← Apache 2.0 attribution (upstream)
└── elixir/            ← upstream elixir/ tree, unmodified
    ├── README.md      ← upstream README (Elixir-specific)
    ├── WORKFLOW.md    ← upstream sample WORKFLOW.md (NOT the one this repo binds to)
    ├── AGENTS.md      ← upstream Elixir-only agent notes
    ├── lib/           ← Symphony source
    ├── test/          ← Symphony tests
    ├── config/        ← Mix config
    ├── priv/          ← Phoenix dashboard assets
    ├── docs/          ← Elixir-specific docs
    ├── mix.exs        ← Mix project file
    ├── mix.lock       ← Locked Hex deps
    ├── mise.toml      ← Pinned Erlang/Elixir versions
    └── Makefile
```

> **Two `WORKFLOW.md` files exist by design:**
> - **`/WORKFLOW.md`** (repo root) — *this repo's* canonical contract,
>   embedding the four-phase TDD protocol. Bind Symphony to it via
>   `./bin/symphony /absolute/path/to/this-repo/WORKFLOW.md`.
> - **`/symphony/elixir/WORKFLOW.md`** — upstream's *sample* contract,
>   shipped unmodified for reference. Do **not** edit it; copy-and-modify
>   the root `WORKFLOW.md` instead.

## Running it

See [`docs/symphony-elixir-quickstart.md`](../docs/symphony-elixir-quickstart.md)
for the operator-level walkthrough. Short version:

```bash
cd symphony/elixir
mise install                          # provisions Erlang/Elixir per mise.toml
mise exec -- mix setup                # mix deps.get + assets.setup
mise exec -- mix build                # compiles + builds ./bin/symphony
export LINEAR_API_KEY=...             # personal Linear API key
mise exec -- ./bin/symphony ../../WORKFLOW.md   # run with this repo's contract
```

Pass `--port 4000` to enable the optional Phoenix dashboard
(<http://127.0.0.1:4000>) for live observability. Pass `--logs-root` to
relocate per-issue Codex session logs.

## Updating the vendored snapshot

When OpenAI tags a new Symphony release (or you need a newer reference
commit), re-vendor as a single mechanical operation — **never** hand-edit
files under `symphony/elixir/`:

```bash
# 1. Sparse-fetch the upstream tree at the desired ref
NEW_REF=<sha-or-tag>
git clone https://github.com/openai/symphony.git /tmp/symphony-upstream
cd /tmp/symphony-upstream && git checkout "$NEW_REF" && cd -

# 2. Replace the vendored tree atomically
rm -rf symphony/elixir symphony/LICENSE symphony/NOTICE
cp -a /tmp/symphony-upstream/elixir symphony/elixir
cp /tmp/symphony-upstream/LICENSE symphony/LICENSE
cp /tmp/symphony-upstream/NOTICE   symphony/NOTICE

# 3. Update the "Pinned commit" row in symphony/README.md to NEW_REF.
# 4. Re-run validation:
cd symphony/elixir && mise exec -- mix test
```

If you need to fix a bug in the reference impl, **upstream it first**.
Local patches in this repo are explicitly out of scope — this directory
exists only to ship a runnable snapshot.

## See also

- Repo-root [`WORKFLOW.md`](../WORKFLOW.md) — the contract this vendored
  binary will actually orchestrate.
- [`skills/symphony-orchestration/SKILL.md`](../skills/symphony-orchestration/SKILL.md)
  — the runtime contract for agents Symphony spawns.
- [`references/symphony-spec.md`](../references/symphony-spec.md) — full
  SPEC §1–§15 mapping and cross-tool runner table.
- [`docs/symphony-elixir-quickstart.md`](../docs/symphony-elixir-quickstart.md)
  — operator quickstart.
- Upstream SPEC: <https://github.com/openai/symphony/blob/main/SPEC.md>
- Upstream Elixir README: [`elixir/README.md`](elixir/README.md)
