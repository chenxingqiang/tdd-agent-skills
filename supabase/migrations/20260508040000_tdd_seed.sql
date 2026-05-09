-- =============================================================================
-- Seed: one demo issue so the agent loop has work the moment Supabase is up.
-- Safe to re-run (uses ON CONFLICT).
-- =============================================================================

INSERT INTO agents (id, name, role, model)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'claude-code', 'developer', 'claude-opus-4-7'),
  ('00000000-0000-0000-0000-000000000002', 'reviewer-bot', 'reviewer',  'claude-sonnet-4-6')
ON CONFLICT (id) DO NOTHING;

INSERT INTO issues (identifier, title, description, priority, state, labels)
VALUES
  ('TDD-1',
   'Add slugify() utility',
   E'Provide a `slugify(text)` helper that lowercases, trims, replaces non-alphanumerics with single hyphens, and collapses repeats.\n\nAcceptance: passing the string `"  Hello, World!  "` returns `"hello-world"`.',
   2, 'Todo', ARRAY['utility','demo'])
ON CONFLICT (identifier) DO NOTHING;
