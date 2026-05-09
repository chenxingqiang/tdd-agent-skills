# TDD Autonomous Loop on Supabase

This is the **system-of-record + referee** that turns the four-phase TDD
protocol from a prompt-level convention into a database-enforced contract.
The agent cannot skip RED, fake GREEN, edit implementation during TESTING,
or merge a PR with an incomplete checklist — the database rejects the write.

## Why this exists

`WORKFLOW.md` defines four phases (DESIGN → DEVELOPMENT → TESTING →
VERIFICATION). On its own that's prompt-level guidance an agent can drift
from. This schema makes the same rules **non-negotiable at the data layer**
so an autonomous agent can drive itself end-to-end without supervision.

## Layers

| Migration | Role |
|---|---|
| `20260508000000_init_issues.sql` | base `issues`/`comments` (Symphony tracker) |
| `20260508010000_tdd_core.sql`    | `tasks`, `test_runs`, `commits`, `branches`, `pull_requests`, `pr_reviews`, `checklist_*`, `agent_turns`, `phase_transitions`, `decisions` |
| `20260508020000_tdd_triggers.sql`| 8 enforcement triggers (the referee) |
| `20260508030000_tdd_views.sql`   | `v_task_next_action`, `v_issue_next_action`, `work_queue`, dashboards, replay |
| `20260508040000_tdd_seed.sql`    | demo agents + one starter issue |

## The autonomous agent loop

```python
while True:
    work = db.fetch_one("SELECT * FROM work_queue LIMIT 1")
    if not work:
        break
    execute(work["next_action"], work)   # the DB tells you what to do
```

`work_queue.next_action` is one of:

```
WRITE_ACCEPTANCE_TEST   WRITE_SPEC               RUN_ACCEPTANCE_EXPECT_RED
DECOMPOSE_INTO_TASKS    WORK_NEXT_TASK           DEBUG_ACCEPTANCE_GAP
COMPLETE_CHECKLIST      OPEN_PR                  AWAIT_OR_REQUEST_REVIEW
MERGE_PR                CLOSE_ISSUE              BLOCKED
```

When `next_action='WORK_NEXT_TASK'`, the row also carries
`focus_task_action`, which is one of:

```
WRITE_RED_TEST   MAKE_GREEN   CONSIDER_REFACTOR   TASK_DONE   BLOCKED
```

## Enforcement summary (the 8 triggers)

| # | Trigger | Rejects |
|---|---|---|
| 1 | `trg_no_code_before_spec` | DEV/REFACTOR commits when `issues.spec_commit_sha IS NULL` |
| 2 | `trg_red_green_invariants` | RED without a failing `test_run`; GREEN without a prior RED, without a passing `test_run`, or that doesn't reduce failing tests |
| 3 | `trg_phase_file_boundaries` | TESTING commit touching impl file; RED commit touching impl file or skipping declared test file |
| 4 | `trg_sync_task_after_commit` | (sync) updates `tasks.phase` and `tasks.test_status` |
| 5 | `trg_sync_spec_commit` | (sync) sets `issues.spec_commit_sha` from first SPEC commit |
| 6 | `trg_sync_acceptance_status` | (sync) updates `issues.acceptance_status` from acceptance test_runs |
| 7 | `trg_merge_gate` | PR merge unless acceptance is green, all tasks done, and 13/13 checklist passed |
| 8 | `trg_post_merge` | (sync) marks branch merged, closes issue |

## Running locally

```bash
# from the repo root
supabase start                 # local Postgres + PostgREST on :54321
supabase db reset              # applies all migrations in order, including seed
psql "$(supabase status -o env | grep DB_URL | cut -d= -f2-)" \
  -c "SELECT * FROM work_queue;"
```

## Running on cloud Supabase

```bash
supabase link --project-ref YOUR_REF
supabase db push
```

Then point the agent's `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` at the
cloud project. Same schema, same rules.

## The CLI: `tdd-cli`

`bin/tdd-cli` (source: `tools/tdd_cli/tdd_cli.py`) is the wrapper agents
use. Every command mutates **both** the local git repo and Supabase, in a
single transaction; if the DB triggers reject the write, the git commit is
rolled back so the two stores never diverge.

Install:
```bash
pip install -r tools/tdd_cli/requirements.txt
export PATH="$PWD/bin:$PATH"
export TDD_DB_URL=postgresql://postgres:postgres@localhost:54322/postgres
```

Typical happy-path session:
```bash
tdd-cli queue                                   # what does the DB say to do?
tdd-cli step                                    # same, but as a JSON plan with hints
tdd-cli claim --issue TDD-1                     # state=In Progress, branch created
tdd-cli set-acceptance --issue TDD-1 \
        --path tests/acceptance/test_slug.py    # declare the goal function
git add docs/specs/TDD-1.md
tdd-cli spec --issue TDD-1                      # SPEC commit; unlocks DEV phase
tdd-cli add-task --issue TDD-1 \
        --title "lower+trim" --criteria "..." \
        --test tests/test_slug.py --impl src/slug.py
git add tests/test_slug.py
tdd-cli red --issue TDD-1 --task 1              # must produce a failing run
git add src/slug.py
tdd-cli green --issue TDD-1 --task 1            # must reduce failures to 0
tdd-cli refactor --issue TDD-1 --task 1         # tests must stay green
tdd-cli test --scope acceptance --issue TDD-1   # flips acceptance_status
for k in acceptance_green all_tasks_done full_suite_green no_skipped_tests \
         coverage_threshold lint_clean type_check_clean security_scan_clean \
         docs_updated changelog_entry migration_safe observability; do
  tdd-cli check --issue TDD-1 --item $k --pass --evidence ...
done
tdd-cli open-pr --issue TDD-1
tdd-cli review --pr 1 --verdict approve         # writes reviewer_approved
tdd-cli merge --pr 1                            # trigger refuses if any gate is red
tdd-cli replay --issue TDD-1                    # full timeline
```

Anywhere TDD is violated, the DB raises and `tdd-cli` exits non-zero with
the specific rule that fired (e.g. "DEV_GREEN must reduce failing tests").
The agent's main loop is meant to be:

```python
while True:
    work = next_row("SELECT * FROM work_queue LIMIT 1")
    if not work: break
    run_cli_for(work["next_action"], work)      # raises on TDD violation
```
