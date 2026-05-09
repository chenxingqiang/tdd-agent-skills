-- =============================================================================
-- Self-driving views — the agent reads next_action from here, that''s it
-- =============================================================================
-- The agent loop is literally:
--   while (work := SELECT * FROM work_queue LIMIT 1) is not None:
--       execute(work.next_action)
-- =============================================================================

-- v_task_next_action: per-task instruction, derived purely from state
CREATE OR REPLACE VIEW v_task_next_action AS
SELECT
  t.id              AS task_id,
  t.issue_id,
  t.title           AS task_title,
  t.phase           AS task_phase,
  t.test_status,
  t.blocked_reason,
  t.strikes,
  CASE
    WHEN t.blocked_reason IS NOT NULL                      THEN 'BLOCKED'
    WHEN t.phase = 'PENDING'                                THEN 'WRITE_RED_TEST'
    WHEN t.phase = 'RED'     AND t.test_status = 'red'      THEN 'MAKE_GREEN'
    WHEN t.phase = 'GREEN'                                  THEN 'CONSIDER_REFACTOR'
    WHEN t.phase = 'REFACTOR'                               THEN 'TASK_DONE'
    WHEN t.phase = 'DONE'                                   THEN 'NOOP'
    ELSE 'UNKNOWN'
  END AS next_action
FROM tasks t;

-- v_issue_next_action: issue-level instruction (covers pre-task work)
CREATE OR REPLACE VIEW v_issue_next_action AS
SELECT
  i.id                     AS issue_id,
  i.identifier,
  i.title,
  i.state,
  i.priority,
  i.acceptance_status,
  i.spec_commit_sha,
  i.acceptance_test_path,
  i.blocked_reason,
  i.strikes,
  (SELECT COUNT(*) FROM tasks WHERE issue_id = i.id) AS task_count,
  (SELECT COUNT(*) FROM tasks
     WHERE issue_id = i.id AND phase NOT IN ('DONE','GREEN','REFACTOR')) AS open_tasks,
  (SELECT COUNT(*) FROM checklist_results
     WHERE issue_id = i.id AND passed = true) AS checklist_passed,
  (SELECT COUNT(*) FROM checklist_items)        AS checklist_total,
  CASE
    WHEN i.blocked_reason IS NOT NULL              THEN 'BLOCKED'
    WHEN i.state = 'Done'                          THEN 'NOOP'
    WHEN i.acceptance_test_path IS NULL            THEN 'WRITE_ACCEPTANCE_TEST'
    WHEN i.spec_commit_sha IS NULL                 THEN 'WRITE_SPEC'
    WHEN i.acceptance_status = 'undefined'         THEN 'RUN_ACCEPTANCE_EXPECT_RED'
    WHEN (SELECT COUNT(*) FROM tasks WHERE issue_id = i.id) = 0
                                                    THEN 'DECOMPOSE_INTO_TASKS'
    WHEN (SELECT COUNT(*) FROM tasks
            WHERE issue_id = i.id
              AND phase NOT IN ('DONE','GREEN','REFACTOR')) > 0
                                                    THEN 'WORK_NEXT_TASK'
    WHEN i.acceptance_status <> 'green'             THEN 'DEBUG_ACCEPTANCE_GAP'
    WHEN (SELECT COUNT(*) FROM checklist_results
            WHERE issue_id = i.id AND passed = true)
       < (SELECT COUNT(*) FROM checklist_items)     THEN 'COMPLETE_CHECKLIST'
    WHEN NOT EXISTS (SELECT 1 FROM pull_requests
                       WHERE issue_id = i.id AND state IN ('open','draft','approved','merged'))
                                                    THEN 'OPEN_PR'
    WHEN EXISTS (SELECT 1 FROM pull_requests
                   WHERE issue_id = i.id AND state IN ('draft','open','changes_requested'))
                                                    THEN 'AWAIT_OR_REQUEST_REVIEW'
    WHEN EXISTS (SELECT 1 FROM pull_requests
                   WHERE issue_id = i.id AND state = 'approved')
                                                    THEN 'MERGE_PR'
    ELSE 'CLOSE_ISSUE'
  END AS next_action
FROM issues i;

-- work_queue: prioritized list of issues with their immediate next action
CREATE OR REPLACE VIEW work_queue AS
SELECT
  v.issue_id,
  v.identifier,
  v.title,
  v.next_action,
  v.priority,
  i.state AS issue_state,
  -- pick first open task to focus on for WORK_NEXT_TASK
  (SELECT t.id FROM tasks t
     WHERE t.issue_id = v.issue_id
       AND t.phase NOT IN ('DONE','GREEN','REFACTOR')
     ORDER BY t.ordering, t.created_at LIMIT 1) AS focus_task_id,
  (SELECT tn.next_action FROM v_task_next_action tn
     WHERE tn.task_id = (
       SELECT t.id FROM tasks t
        WHERE t.issue_id = v.issue_id
          AND t.phase NOT IN ('DONE','GREEN','REFACTOR')
        ORDER BY t.ordering, t.created_at LIMIT 1)
  ) AS focus_task_action,
  COALESCE(v.priority, 4) * -1 AS priority_score
FROM v_issue_next_action v
JOIN issues i ON i.id = v.issue_id
WHERE v.next_action <> 'NOOP'
  AND v.blocked_reason IS NULL
  AND i.state <> 'Done'
ORDER BY priority_score DESC, v.identifier;

-- v_issue_dashboard: one-row summary for monitoring
CREATE OR REPLACE VIEW v_issue_dashboard AS
SELECT
  i.identifier,
  i.title,
  i.state,
  i.acceptance_status,
  (SELECT COUNT(*) FROM tasks WHERE issue_id = i.id) AS tasks_total,
  (SELECT COUNT(*) FROM tasks WHERE issue_id = i.id
     AND phase IN ('DONE','GREEN','REFACTOR')) AS tasks_done,
  (SELECT COUNT(*) FROM checklist_results
     WHERE issue_id = i.id AND passed = true) AS checklist_passed,
  (SELECT COUNT(*) FROM checklist_items) AS checklist_total,
  (SELECT COUNT(*) FROM commits WHERE issue_id = i.id) AS commit_count,
  (SELECT COUNT(*) FROM agent_turns WHERE issue_id = i.id) AS turn_count,
  i.blocked_reason,
  v.next_action
FROM issues i
LEFT JOIN v_issue_next_action v ON v.issue_id = i.id;

-- v_session_replay: chronological joinable timeline for one issue
CREATE OR REPLACE VIEW v_session_replay AS
SELECT
  evt.issue_id,
  evt.ts,
  evt.kind,
  evt.summary
FROM (
  SELECT issue_id, started_at AS ts, 'turn'::TEXT AS kind,
         COALESCE(phase,'?') || ' / ' || COALESCE(next_action,'?') ||
         ' :: ' || LEFT(COALESCE(prompt,''), 80) AS summary
    FROM agent_turns
  UNION ALL
  SELECT issue_id, authored_at AS ts, 'commit'::TEXT,
         phase || ' ' || LEFT(sha, 8) || ' ' || LEFT(message, 60)
    FROM commits
  UNION ALL
  SELECT issue_id, started_at AS ts, 'test_run'::TEXT,
         scope || ' ' || status || ' (' || passed || '/' || test_count || ')'
    FROM test_runs
  UNION ALL
  SELECT issue_id, created_at AS ts, 'phase'::TEXT,
         COALESCE(from_phase,'∅') || ' -> ' || to_phase
    FROM phase_transitions
) evt
ORDER BY evt.issue_id, evt.ts;
