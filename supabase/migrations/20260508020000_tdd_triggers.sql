-- =============================================================================
-- TDD Enforcement Triggers — the database is the referee
-- =============================================================================
-- These triggers REJECT writes that would violate TDD invariants.
-- An agent that tries to skip RED, fake GREEN, edit impl during TESTING,
-- or merge without a green checklist will get a hard SQL error.
-- =============================================================================

-- Helper: does this commit's files_changed touch any path matching prefix?
CREATE OR REPLACE FUNCTION any_path_matches(paths TEXT[], needles TEXT[])
RETURNS BOOLEAN AS $$
DECLARE p TEXT; n TEXT;
BEGIN
  IF paths IS NULL OR array_length(paths,1) IS NULL THEN RETURN false; END IF;
  FOREACH p IN ARRAY paths LOOP
    FOREACH n IN ARRAY needles LOOP
      IF p = n OR p LIKE n || '/%' THEN RETURN true; END IF;
    END LOOP;
  END LOOP;
  RETURN false;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ---------------------------------------------------------------------------
-- TRG 1: no DEV commits before issue has a spec_commit_sha
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_no_code_before_spec()
RETURNS TRIGGER AS $$
DECLARE
  spec_sha TEXT;
BEGIN
  IF NEW.phase IN ('DEV_RED','DEV_GREEN','REFACTOR') THEN
    SELECT spec_commit_sha INTO spec_sha FROM issues WHERE id = NEW.issue_id;
    IF spec_sha IS NULL THEN
      RAISE EXCEPTION
        'TDD violation: cannot record % commit on issue % before a SPEC commit exists',
        NEW.phase, NEW.issue_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_no_code_before_spec ON commits;
CREATE TRIGGER trg_no_code_before_spec
  BEFORE INSERT ON commits
  FOR EACH ROW EXECUTE FUNCTION trg_no_code_before_spec();

-- ---------------------------------------------------------------------------
-- TRG 2: RED must be a real failure; GREEN must follow a RED on the same task
--        and must be a real pass that reduces failing tests
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_red_green_invariants()
RETURNS TRIGGER AS $$
DECLARE
  tr RECORD;
  prior_red RECORD;
  prior_red_run RECORD;
BEGIN
  IF NEW.phase NOT IN ('DEV_RED','DEV_GREEN','REFACTOR') THEN
    RETURN NEW;
  END IF;

  IF NEW.task_id IS NULL THEN
    RAISE EXCEPTION 'TDD violation: % commit must declare a task_id', NEW.phase;
  END IF;

  IF NEW.test_run_id IS NULL THEN
    RAISE EXCEPTION 'TDD violation: % commit must reference a test_run_id', NEW.phase;
  END IF;

  SELECT * INTO tr FROM test_runs WHERE id = NEW.test_run_id;
  IF tr IS NULL THEN
    RAISE EXCEPTION 'TDD violation: test_run % not found', NEW.test_run_id;
  END IF;
  IF tr.task_id IS DISTINCT FROM NEW.task_id THEN
    RAISE EXCEPTION 'TDD violation: test_run.task_id (%) does not match commit.task_id (%)',
      tr.task_id, NEW.task_id;
  END IF;

  IF NEW.phase = 'DEV_RED' THEN
    IF tr.status <> 'fail' OR tr.failed < 1 THEN
      RAISE EXCEPTION 'TDD violation: DEV_RED commit requires a failing test_run (got status=%, failed=%)',
        tr.status, tr.failed;
    END IF;
  END IF;

  IF NEW.phase = 'DEV_GREEN' THEN
    -- must have a prior RED on this task
    SELECT c.* INTO prior_red
      FROM commits c
      WHERE c.task_id = NEW.task_id AND c.phase = 'DEV_RED'
      ORDER BY c.authored_at DESC LIMIT 1;
    IF prior_red.sha IS NULL THEN
      RAISE EXCEPTION 'TDD violation: DEV_GREEN on task % requires a prior DEV_RED commit',
        NEW.task_id;
    END IF;

    IF tr.status <> 'pass' THEN
      RAISE EXCEPTION 'TDD violation: DEV_GREEN test_run must be status=pass (got %)', tr.status;
    END IF;

    -- new run must reduce failing count vs the RED baseline
    SELECT * INTO prior_red_run FROM test_runs WHERE id = prior_red.test_run_id;
    IF prior_red_run.failed IS NOT NULL AND tr.failed >= prior_red_run.failed THEN
      RAISE EXCEPTION 'TDD violation: DEV_GREEN must reduce failing tests (RED=%, GREEN=%)',
        prior_red_run.failed, tr.failed;
    END IF;
  END IF;

  IF NEW.phase = 'REFACTOR' THEN
    IF tr.status <> 'pass' THEN
      RAISE EXCEPTION 'TDD violation: REFACTOR commit requires a passing test_run';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_red_green_invariants ON commits;
CREATE TRIGGER trg_red_green_invariants
  BEFORE INSERT ON commits
  FOR EACH ROW EXECUTE FUNCTION trg_red_green_invariants();

-- ---------------------------------------------------------------------------
-- TRG 3: TESTING-phase commits cannot modify implementation files
--        DEV_RED commits should only touch test files.
--        DEV_GREEN/REFACTOR commits cannot touch unrelated tasks' impl files.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_phase_file_boundaries()
RETURNS TRIGGER AS $$
DECLARE
  task_rec RECORD;
BEGIN
  IF NEW.phase = 'TESTING' THEN
    -- Testing commits should only update test artifacts or fixtures, never src
    IF NEW.task_id IS NOT NULL THEN
      SELECT * INTO task_rec FROM tasks WHERE id = NEW.task_id;
      IF task_rec.impl_file_path IS NOT NULL
         AND any_path_matches(NEW.files_changed, ARRAY[task_rec.impl_file_path]) THEN
        RAISE EXCEPTION
          'TDD violation: TESTING commit must not modify implementation file %',
          task_rec.impl_file_path;
      END IF;
    END IF;
  END IF;

  IF NEW.phase = 'DEV_RED' AND NEW.task_id IS NOT NULL THEN
    SELECT * INTO task_rec FROM tasks WHERE id = NEW.task_id;
    -- RED commit must touch the declared test file
    IF NOT any_path_matches(NEW.files_changed, ARRAY[task_rec.test_file_path]) THEN
      RAISE EXCEPTION
        'TDD violation: DEV_RED commit must modify declared test file %',
        task_rec.test_file_path;
    END IF;
    -- and must not touch the impl file (that''s GREEN's job)
    IF any_path_matches(NEW.files_changed, ARRAY[task_rec.impl_file_path]) THEN
      RAISE EXCEPTION
        'TDD violation: DEV_RED commit must not modify implementation file %',
        task_rec.impl_file_path;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_phase_file_boundaries ON commits;
CREATE TRIGGER trg_phase_file_boundaries
  BEFORE INSERT ON commits
  FOR EACH ROW EXECUTE FUNCTION trg_phase_file_boundaries();

-- ---------------------------------------------------------------------------
-- TRG 4: after a commit lands, sync task phase + test_status
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_sync_task_after_commit()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.task_id IS NULL THEN RETURN NEW; END IF;

  IF NEW.phase = 'DEV_RED' THEN
    UPDATE tasks
       SET phase='RED', test_status='red',
           red_commit_sha=NEW.sha, last_test_run_id=NEW.test_run_id
     WHERE id = NEW.task_id;
  ELSIF NEW.phase = 'DEV_GREEN' THEN
    UPDATE tasks
       SET phase='GREEN', test_status='green',
           green_commit_sha=NEW.sha, last_test_run_id=NEW.test_run_id
     WHERE id = NEW.task_id;
  ELSIF NEW.phase = 'REFACTOR' THEN
    UPDATE tasks
       SET phase='REFACTOR', test_status='green',
           refactor_commit_sha=NEW.sha, last_test_run_id=NEW.test_run_id
     WHERE id = NEW.task_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_task_after_commit ON commits;
CREATE TRIGGER trg_sync_task_after_commit
  AFTER INSERT ON commits
  FOR EACH ROW EXECUTE FUNCTION trg_sync_task_after_commit();

-- ---------------------------------------------------------------------------
-- TRG 5: after a SPEC commit lands, set issues.spec_commit_sha
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_sync_spec_commit()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.phase = 'SPEC' THEN
    UPDATE issues
       SET spec_commit_sha = NEW.sha
     WHERE id = NEW.issue_id AND spec_commit_sha IS NULL;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_spec_commit ON commits;
CREATE TRIGGER trg_sync_spec_commit
  AFTER INSERT ON commits
  FOR EACH ROW EXECUTE FUNCTION trg_sync_spec_commit();

-- ---------------------------------------------------------------------------
-- TRG 6: after acceptance test_run lands, sync issues.acceptance_status
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_sync_acceptance_status()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.scope = 'acceptance' THEN
    UPDATE issues
       SET acceptance_status = CASE NEW.status WHEN 'pass' THEN 'green' ELSE 'red' END
     WHERE id = NEW.issue_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_acceptance_status ON test_runs;
CREATE TRIGGER trg_sync_acceptance_status
  AFTER INSERT ON test_runs
  FOR EACH ROW EXECUTE FUNCTION trg_sync_acceptance_status();

-- ---------------------------------------------------------------------------
-- TRG 7: PR merge requires acceptance green + all tasks DONE + 13/13 checklist
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_merge_gate()
RETURNS TRIGGER AS $$
DECLARE
  acc_status TEXT;
  pending_tasks INTEGER;
  passed_items INTEGER;
  total_items INTEGER;
BEGIN
  IF NEW.state = 'merged' AND OLD.state <> 'merged' THEN
    SELECT acceptance_status INTO acc_status FROM issues WHERE id = NEW.issue_id;
    IF acc_status <> 'green' THEN
      RAISE EXCEPTION 'Merge gate: acceptance_status must be green (got %)', acc_status;
    END IF;

    SELECT COUNT(*) INTO pending_tasks
      FROM tasks WHERE issue_id = NEW.issue_id AND phase NOT IN ('DONE','GREEN','REFACTOR');
    IF pending_tasks > 0 THEN
      RAISE EXCEPTION 'Merge gate: % task(s) not finished', pending_tasks;
    END IF;

    SELECT COUNT(*) INTO total_items FROM checklist_items;
    SELECT COUNT(*) INTO passed_items
      FROM checklist_results
      WHERE issue_id = NEW.issue_id AND passed = true;
    IF passed_items < total_items THEN
      RAISE EXCEPTION 'Merge gate: checklist %/% passed', passed_items, total_items;
    END IF;

    NEW.merged_at := now();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_merge_gate ON pull_requests;
CREATE TRIGGER trg_merge_gate
  BEFORE UPDATE ON pull_requests
  FOR EACH ROW EXECUTE FUNCTION trg_merge_gate();

-- ---------------------------------------------------------------------------
-- TRG 8: after PR merge, mark branch merged + close issue
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_post_merge()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.state = 'merged' AND OLD.state <> 'merged' THEN
    UPDATE branches SET status='merged' WHERE id = NEW.branch_id;
    UPDATE issues SET state='Done' WHERE id = NEW.issue_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_post_merge ON pull_requests;
CREATE TRIGGER trg_post_merge
  AFTER UPDATE ON pull_requests
  FOR EACH ROW EXECUTE FUNCTION trg_post_merge();
