-- =============================================================================
-- Supabase Tracker Schema — run once in Supabase SQL Editor
-- =============================================================================
-- Replaces Linear as the issue tracker for Symphony.
-- The PostgREST API auto-exposes these tables at /rest/v1/<table>.
-- RLS note: service_role key bypasses policies; this schema is designed
-- to be accessed only by Symphony, not directly by end users.
-- =============================================================================

-- 1. Issues table -----------------------------------------------------------

CREATE TABLE IF NOT EXISTS issues (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  identifier  TEXT NOT NULL UNIQUE,          -- e.g. "SYM-1", "PROJ-42"
  title       TEXT NOT NULL,
  description TEXT,
  priority    INTEGER,                       -- 1=urgent, 2=high, 3=medium, 4=low, NULL=none
  state       TEXT NOT NULL DEFAULT 'Todo',  -- Todo, In Progress, Human Review, Done, etc.
  branch_name TEXT,
  url         TEXT,                          -- PR or issue URL for cross-reference
  labels      TEXT[] NOT NULL DEFAULT '{}', -- lowercase label names
  blocked_by  JSONB NOT NULL DEFAULT '[]',  -- [{id, identifier, state}, ...]
  assignee_id TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Comments table ---------------------------------------------------------

CREATE TABLE IF NOT EXISTS comments (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  issue_id   UUID NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  body       TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Indexes ----------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_issues_state ON issues(state);
CREATE INDEX IF NOT EXISTS idx_issues_identifier ON issues(identifier);
CREATE INDEX IF NOT EXISTS idx_issues_priority ON issues(priority);
CREATE INDEX IF NOT EXISTS idx_comments_issue_id ON comments(issue_id);

-- 4. Auto-update updated_at -------------------------------------------------

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_issues_updated_at ON issues;
CREATE TRIGGER trg_issues_updated_at
  BEFORE UPDATE ON issues
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =============================================================================
-- Sample seed data (remove for production)
-- =============================================================================

-- INSERT INTO issues (identifier, title, description, priority, state, labels)
-- VALUES
--   ('DEMO-1', 'Add user authentication', 'Implement OAuth 2.0 login flow', 2, 'Todo', '{feature,auth}'),
--   ('DEMO-2', 'Fix pagination bug', 'Page 3 returns empty results when total is exactly 50', 1, 'Todo', '{bug}'),
--   ('DEMO-3', 'Update README', 'Document the new API endpoints', 4, 'Done', '{docs}');

-- =============================================================================
-- Enable realtime (optional — for live dashboard updates)
-- =============================================================================
-- ALTER PUBLICATION supabase_realtime ADD TABLE issues;
-- ALTER PUBLICATION supabase_realtime ADD TABLE comments;
