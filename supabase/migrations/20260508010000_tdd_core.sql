-- =============================================================================
-- TDD Autonomous Loop — core schema
-- =============================================================================
-- Turns Supabase into the system-of-record AND the referee for an
-- autonomous TDD agent. The database refuses to record progress that
-- violates TDD invariants, so the agent cannot cheat its way forward.
--
-- Layered on top of 20260508000000_init_issues.sql (issues, comments).
-- =============================================================================

-- 0. Extend issues with TDD goal fields ---------------------------------------

ALTER TABLE issues
  ADD COLUMN IF NOT EXISTS spec_commit_sha       TEXT,
  ADD COLUMN IF NOT EXISTS acceptance_test_path  TEXT,
  ADD COLUMN IF NOT EXISTS acceptance_status     TEXT NOT NULL DEFAULT 'undefined'
    CHECK (acceptance_status IN ('undefined','red','green','stale')),
  ADD COLUMN IF NOT EXISTS blocked_reason        TEXT,
  ADD COLUMN IF NOT EXISTS strikes               INTEGER NOT NULL DEFAULT 0;

-- 1. Agents and sessions ------------------------------------------------------

CREATE TABLE IF NOT EXISTS agents (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,                 -- 'claude-code', 'codex', etc.
  role        TEXT NOT NULL DEFAULT 'developer', -- 'developer'|'reviewer'
  model       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sessions (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id     UUID NOT NULL REFERENCES agents(id),
  issue_id     UUID REFERENCES issues(id),
  started_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at     TIMESTAMPTZ,
  turn_count   INTEGER NOT NULL DEFAULT 0,
  status       TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','done','aborted'))
);

-- 2. Tasks: the TDD unit (RED -> GREEN -> REFACTOR) ---------------------------

CREATE TABLE IF NOT EXISTS tasks (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  issue_id             UUID NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  title                TEXT NOT NULL,
  acceptance_criteria  TEXT NOT NULL,
  test_file_path       TEXT NOT NULL,        -- declared boundary
  impl_file_path       TEXT NOT NULL,        -- declared boundary
  phase                TEXT NOT NULL DEFAULT 'PENDING'
    CHECK (phase IN ('PENDING','RED','GREEN','REFACTOR','DONE','BLOCKED')),
  red_commit_sha       TEXT,
  green_commit_sha     TEXT,
  refactor_commit_sha  TEXT,
  last_test_run_id     UUID,
  test_status          TEXT NOT NULL DEFAULT 'unknown'
    CHECK (test_status IN ('unknown','red','green','stale')),
  ordering             INTEGER NOT NULL DEFAULT 0,
  blocked_reason       TEXT,
  strikes              INTEGER NOT NULL DEFAULT 0,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tasks_issue ON tasks(issue_id);
CREATE INDEX IF NOT EXISTS idx_tasks_phase ON tasks(phase);

-- 3. Branches (local git mirror) ----------------------------------------------

CREATE TABLE IF NOT EXISTS branches (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  issue_id    UUID NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  name        TEXT NOT NULL UNIQUE,
  base_sha    TEXT NOT NULL,
  head_sha    TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','merged','abandoned')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. Test runs: the only source of truth for red/green ------------------------

CREATE TABLE IF NOT EXISTS test_runs (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id      UUID REFERENCES tasks(id) ON DELETE CASCADE,
  issue_id     UUID NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  scope        TEXT NOT NULL CHECK (scope IN ('task','acceptance','full_suite')),
  commit_sha   TEXT,                         -- which commit was tested (may be HEAD pre-commit)
  status       TEXT NOT NULL CHECK (status IN ('pass','fail','error')),
  test_count   INTEGER NOT NULL DEFAULT 0,
  passed       INTEGER NOT NULL DEFAULT 0,
  failed       INTEGER NOT NULL DEFAULT 0,
  errored      INTEGER NOT NULL DEFAULT 0,
  failing_tests TEXT[] NOT NULL DEFAULT '{}',
  output_log   TEXT,
  runner       TEXT NOT NULL,                -- 'pytest', 'mix test', 'go test', ...
  duration_ms  INTEGER,
  started_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_test_runs_task ON test_runs(task_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_test_runs_issue ON test_runs(issue_id, started_at DESC);

-- 5. Commits (with phase + test_run binding) ----------------------------------

CREATE TABLE IF NOT EXISTS commits (
  sha            TEXT PRIMARY KEY,
  branch_id      UUID NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  issue_id       UUID NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  task_id        UUID REFERENCES tasks(id),
  parent_sha     TEXT,
  message        TEXT NOT NULL,
  phase          TEXT NOT NULL CHECK (phase IN
    ('SPEC','DEV_RED','DEV_GREEN','REFACTOR','TESTING','DOCS','CHORE')),
  test_run_id    UUID REFERENCES test_runs(id),
  files_changed  TEXT[] NOT NULL DEFAULT '{}',
  agent_turn_id  UUID,
  authored_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_commits_issue ON commits(issue_id, authored_at);
CREATE INDEX IF NOT EXISTS idx_commits_task ON commits(task_id, authored_at);

-- Now that commits exist, FK tasks.*_commit_sha -> commits.sha is wired implicitly
-- (we keep them as TEXT for ergonomics; trigger validates existence).

-- 6. Pull requests + reviews (simulated locally) ------------------------------

CREATE TABLE IF NOT EXISTS pull_requests (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  number        SERIAL UNIQUE,
  issue_id      UUID NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  branch_id     UUID NOT NULL REFERENCES branches(id),
  title         TEXT NOT NULL,
  body          TEXT,
  state         TEXT NOT NULL DEFAULT 'draft'
    CHECK (state IN ('draft','open','changes_requested','approved','merged','closed')),
  base_sha      TEXT NOT NULL,
  head_sha      TEXT NOT NULL,
  diff_summary  TEXT,
  opened_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  merged_at     TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS pr_reviews (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pr_id       UUID NOT NULL REFERENCES pull_requests(id) ON DELETE CASCADE,
  reviewer_agent_id UUID NOT NULL REFERENCES agents(id),
  verdict     TEXT NOT NULL CHECK (verdict IN ('approve','request_changes','comment')),
  summary     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pr_review_comments (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id   UUID NOT NULL REFERENCES pr_reviews(id) ON DELETE CASCADE,
  file        TEXT NOT NULL,
  line        INTEGER,
  body        TEXT NOT NULL,
  resolved    BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 7. Production-readiness checklist (13 items) --------------------------------

CREATE TABLE IF NOT EXISTS checklist_items (
  key          TEXT PRIMARY KEY,
  description  TEXT NOT NULL,
  ordering     INTEGER NOT NULL
);

INSERT INTO checklist_items(key, description, ordering) VALUES
  ('acceptance_green',     'Acceptance test is green',                       1),
  ('all_tasks_done',       'All tasks reached DONE phase',                   2),
  ('full_suite_green',     'Full test suite passes on PR head',              3),
  ('no_skipped_tests',     'No skipped or xfail tests introduced',           4),
  ('coverage_threshold',   'Coverage meets project threshold',               5),
  ('lint_clean',           'Lint / formatter clean',                         6),
  ('type_check_clean',     'Type checker clean',                             7),
  ('security_scan_clean',  'Security scan: no new high/critical findings',   8),
  ('docs_updated',         'User-facing docs updated where behavior changed',9),
  ('changelog_entry',      'Changelog entry added',                          10),
  ('migration_safe',       'Schema/data migrations are reversible',          11),
  ('observability',        'Logs/metrics/traces added for new flows',        12),
  ('reviewer_approved',    'At least one reviewer agent approve verdict',    13)
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS checklist_results (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  issue_id      UUID NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  item_key      TEXT NOT NULL REFERENCES checklist_items(key),
  passed        BOOLEAN NOT NULL,
  evidence_url  TEXT,
  evidence_ref  TEXT,                        -- e.g. test_run uuid
  checked_by    UUID REFERENCES agents(id),
  checked_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (issue_id, item_key)
);

-- 8. Phase transitions (audit) ------------------------------------------------

CREATE TABLE IF NOT EXISTS phase_transitions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  issue_id      UUID NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  task_id       UUID REFERENCES tasks(id) ON DELETE CASCADE,
  from_phase    TEXT,
  to_phase      TEXT NOT NULL,
  evidence_type TEXT NOT NULL CHECK (evidence_type IN
    ('spec_commit','test_run','review','checklist','manual')),
  evidence_id   TEXT,
  agent_turn_id UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 9. Agent turns (the conversation log) ---------------------------------------

CREATE TABLE IF NOT EXISTS agent_turns (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id    UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  issue_id      UUID REFERENCES issues(id),
  task_id       UUID REFERENCES tasks(id),
  phase         TEXT,                        -- DESIGN/DEVELOPMENT/TESTING/VERIFICATION
  next_action   TEXT,                        -- the work_queue command driving this turn
  prompt        TEXT NOT NULL,
  response      TEXT,
  tool_calls    JSONB NOT NULL DEFAULT '[]',
  tokens_in     INTEGER,
  tokens_out    INTEGER,
  tdd_violation BOOLEAN NOT NULL DEFAULT false,
  violation_reason TEXT,
  started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_turns_session ON agent_turns(session_id, started_at);
CREATE INDEX IF NOT EXISTS idx_turns_issue ON agent_turns(issue_id, started_at);

-- 10. Decisions (key reasoning pinpoints) ------------------------------------

CREATE TABLE IF NOT EXISTS decisions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  issue_id    UUID NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  turn_id     UUID REFERENCES agent_turns(id),
  question    TEXT NOT NULL,
  chosen      TEXT NOT NULL,
  rejected    TEXT,
  rationale   TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 11. updated_at triggers ----------------------------------------------------

DROP TRIGGER IF EXISTS trg_tasks_updated_at ON tasks;
CREATE TRIGGER trg_tasks_updated_at
  BEFORE UPDATE ON tasks
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
