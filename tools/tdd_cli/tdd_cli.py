#!/usr/bin/env python3
"""tdd-cli — git + Supabase wrapper that drives the autonomous TDD loop.

Every action mutates BOTH the local git repo AND the Supabase tables.
Schema enforcement triggers reject TDD violations, so the CLI cannot
let an agent (or human) skip RED, fake GREEN, or merge a half-baked PR.

Configuration (env):
  TDD_DB_URL         Postgres connection URL
                     (default: postgresql://postgres:postgres@localhost:54322/postgres
                      — the local-supabase default)
  TDD_AGENT_ID       UUID of the acting agent (default: claude-code seed UUID)
  TDD_RUNNER         Test runner command template, e.g. "pytest {path}"
                     (default: pytest {path})
  TDD_REPO_ROOT      Override repo root (default: git rev-parse --show-toplevel)

Usage:
  tdd-cli status
  tdd-cli queue
  tdd-cli claim          --issue TDD-1
  tdd-cli set-acceptance --issue TDD-1 --path tests/acceptance/test_slug.py
  tdd-cli spec           --issue TDD-1 [--message ...]
  tdd-cli add-task       --issue TDD-1 --title "..." --criteria "..." \
                         --test PATH --impl PATH
  tdd-cli test           --scope acceptance|task|full_suite [--task IDX|UUID] \
                         [--runner CMD]
  tdd-cli red            --task IDX|UUID [--message ...]
  tdd-cli green          --task IDX|UUID [--message ...]
  tdd-cli refactor       --task IDX|UUID [--message ...]
  tdd-cli check          --issue TDD-1 --item KEY --pass/--fail [--evidence ...]
  tdd-cli open-pr        --issue TDD-1 [--title ...] [--body ...]
  tdd-cli review         --pr N --verdict approve|request_changes [--summary ...]
  tdd-cli merge          --pr N
  tdd-cli replay         --issue TDD-1
  tdd-cli turn-log       --session UUID --phase ... --action ... --prompt ...

The script speaks Postgres directly via psycopg2 so triggers run inline
and TDD-violating writes raise SQL errors that surface as exit-code 2.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Optional

try:
    import psycopg2
    import psycopg2.extras
except ImportError:
    sys.stderr.write(
        "tdd-cli requires psycopg2. Install with:\n"
        "  pip install psycopg2-binary\n"
    )
    sys.exit(127)


DEFAULT_DB_URL = "postgresql://postgres:postgres@localhost:54322/postgres"
DEFAULT_AGENT_ID = "00000000-0000-0000-0000-000000000001"
DEFAULT_RUNNER = "pytest {path}"


# ---------------------------------------------------------------------------
# Plumbing
# ---------------------------------------------------------------------------

def db():
    url = os.environ.get("TDD_DB_URL", DEFAULT_DB_URL)
    conn = psycopg2.connect(url)
    conn.autocommit = False
    return conn


def repo_root() -> Path:
    override = os.environ.get("TDD_REPO_ROOT")
    if override:
        return Path(override)
    out = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True)
    return Path(out.strip())


def git(*args: str, cwd: Optional[Path] = None, check: bool = True,
        capture: bool = True) -> subprocess.CompletedProcess:
    cwd = cwd or repo_root()
    return subprocess.run(
        ["git", *args], cwd=cwd, check=check,
        capture_output=capture, text=True,
    )


def head_sha(cwd: Optional[Path] = None) -> str:
    return git("rev-parse", "HEAD", cwd=cwd).stdout.strip()


def slugify(text: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return s or "task"


def fail(msg: str, code: int = 2) -> None:
    sys.stderr.write(f"tdd-cli: {msg}\n")
    sys.exit(code)


def fetch_issue(cur, identifier: str) -> dict:
    cur.execute(
        "SELECT * FROM issues WHERE identifier=%s",
        (identifier,),
    )
    row = cur.fetchone()
    if not row:
        fail(f"issue {identifier} not found")
    return dict(row)


def fetch_task(cur, issue_id: str, ref: str) -> dict:
    """ref: integer index (1-based, ordered by ordering/created_at) or UUID."""
    try:
        uuid.UUID(ref)
        cur.execute("SELECT * FROM tasks WHERE id=%s", (ref,))
    except ValueError:
        cur.execute(
            "SELECT * FROM tasks WHERE issue_id=%s ORDER BY ordering, created_at",
            (issue_id,),
        )
        rows = cur.fetchall()
        idx = int(ref) - 1
        if idx < 0 or idx >= len(rows):
            fail(f"task index {ref} out of range (1..{len(rows)})")
        return dict(rows[idx])
    row = cur.fetchone()
    if not row:
        fail(f"task {ref} not found")
    return dict(row)


def fetch_branch_for_issue(cur, issue_id: str) -> Optional[dict]:
    cur.execute(
        "SELECT * FROM branches WHERE issue_id=%s AND status='active' "
        "ORDER BY created_at DESC LIMIT 1",
        (issue_id,),
    )
    row = cur.fetchone()
    return dict(row) if row else None


def ensure_branch(cur, issue: dict) -> dict:
    existing = fetch_branch_for_issue(cur, issue["id"])
    if existing:
        return existing
    base = head_sha()
    name = f"feat/{issue['identifier']}-{slugify(issue['title'])[:40]}"
    git("checkout", "-b", name)
    cur.execute(
        "INSERT INTO branches(issue_id, name, base_sha, head_sha) "
        "VALUES (%s,%s,%s,%s) RETURNING *",
        (issue["id"], name, base, base),
    )
    return dict(cur.fetchone())


def update_branch_head(cur, branch_id: str, sha: str):
    cur.execute("UPDATE branches SET head_sha=%s WHERE id=%s", (sha, branch_id))


# ---------------------------------------------------------------------------
# Test running
# ---------------------------------------------------------------------------

@dataclass
class TestResult:
    status: str          # 'pass' | 'fail' | 'error'
    test_count: int
    passed: int
    failed: int
    errored: int
    failing: list[str]
    output: str
    duration_ms: int


def run_tests(path: str, runner_template: Optional[str] = None) -> TestResult:
    template = runner_template or os.environ.get("TDD_RUNNER", DEFAULT_RUNNER)
    cmd = template.format(path=shlex.quote(path))
    start = datetime.now(timezone.utc)
    proc = subprocess.run(
        cmd, shell=True, cwd=repo_root(),
        capture_output=True, text=True,
    )
    end = datetime.now(timezone.utc)
    out = (proc.stdout or "") + (proc.stderr or "")
    duration_ms = int((end - start).total_seconds() * 1000)
    # Best-effort pytest summary parsing; falls back to exit-code semantics.
    test_count = passed = failed = errored = 0
    m = re.search(r"=+\s*(?:(\d+)\s+failed[, ]+)?(?:(\d+)\s+passed[, ]*)?"
                  r"(?:(\d+)\s+error[s]?)?.*?in [\d.]+s", out)
    if m:
        failed = int(m.group(1) or 0)
        passed = int(m.group(2) or 0)
        errored = int(m.group(3) or 0)
        test_count = failed + passed + errored
    failing = re.findall(r"^FAILED\s+(\S+)", out, flags=re.MULTILINE)
    if proc.returncode == 0:
        status = "pass"
        if not test_count:
            test_count = passed = max(passed, 1)
    elif failed > 0 or failing:
        status = "fail"
        if not test_count:
            test_count = failed = max(failed, len(failing) or 1)
    else:
        status = "error"
        if not test_count:
            test_count = errored = 1
    return TestResult(status, test_count, passed, failed, errored,
                      failing, out, duration_ms)


def insert_test_run(cur, *, issue_id: str, task_id: Optional[str],
                    scope: str, result: TestResult,
                    runner: str, commit_sha: Optional[str]) -> str:
    cur.execute(
        "INSERT INTO test_runs(task_id, issue_id, scope, commit_sha, status, "
        "test_count, passed, failed, errored, failing_tests, output_log, "
        "runner, duration_ms) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) "
        "RETURNING id",
        (task_id, issue_id, scope, commit_sha, result.status,
         result.test_count, result.passed, result.failed, result.errored,
         result.failing, result.output[-20000:], runner, result.duration_ms),
    )
    return str(cur.fetchone()["id"])


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_status(args):
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SELECT * FROM v_issue_dashboard ORDER BY identifier")
        rows = cur.fetchall()
        if not rows:
            print("(no issues)")
            return
        for r in rows:
            print(
                f"{r['identifier']:<8} {r['state']:<14} "
                f"acc={r['acceptance_status']:<9} "
                f"tasks={r['tasks_done']}/{r['tasks_total']:<3} "
                f"chk={r['checklist_passed']}/{r['checklist_total']:<3} "
                f"next={r['next_action']:<25} "
                f"{r['title']}"
            )


def cmd_queue(args):
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SELECT * FROM work_queue")
        rows = cur.fetchall()
        if not rows:
            print("(queue empty)")
            return
        for r in rows:
            focus = f" focus={r['focus_task_action']}" if r["focus_task_action"] else ""
            print(f"{r['identifier']:<8} {r['next_action']:<25}{focus}  {r['title']}")


def cmd_claim(args):
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        issue = fetch_issue(cur, args.issue)
        cur.execute(
            "UPDATE issues SET state='In Progress', assignee_id=%s WHERE id=%s",
            (os.environ.get("TDD_AGENT_ID", DEFAULT_AGENT_ID), issue["id"]),
        )
        branch = ensure_branch(cur, issue)
        conn.commit()
        print(f"claimed {issue['identifier']} on branch {branch['name']}")


def cmd_set_acceptance(args):
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        issue = fetch_issue(cur, args.issue)
        cur.execute(
            "UPDATE issues SET acceptance_test_path=%s WHERE id=%s",
            (args.path, issue["id"]),
        )
        conn.commit()
    print(f"acceptance_test_path={args.path} on {args.issue}")


def cmd_spec(args):
    """Stage + commit current diff as the SPEC commit for this issue."""
    msg = args.message or f"[SPEC][{args.issue}] design"
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        issue = fetch_issue(cur, args.issue)
        branch = ensure_branch(cur, issue)
        # commit whatever is staged; require staged changes
        if not git("diff", "--cached", "--name-only", check=False).stdout.strip():
            fail("no staged changes — `git add` your spec first")
        files = [l for l in git("diff", "--cached", "--name-only").stdout.splitlines() if l]
        git("commit", "-m", msg, capture=True)
        sha = head_sha()
        cur.execute(
            "INSERT INTO commits(sha, branch_id, issue_id, task_id, parent_sha, "
            "message, phase, files_changed) VALUES (%s,%s,%s,NULL,%s,%s,'SPEC',%s)",
            (sha, branch["id"], issue["id"],
             git("rev-parse", "HEAD~1", check=False).stdout.strip() or None,
             msg, files),
        )
        update_branch_head(cur, branch["id"], sha)
        conn.commit()
    print(f"SPEC commit {sha[:8]} recorded")


def cmd_add_task(args):
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        issue = fetch_issue(cur, args.issue)
        cur.execute(
            "SELECT COALESCE(MAX(ordering),0)+1 AS o FROM tasks WHERE issue_id=%s",
            (issue["id"],),
        )
        ordering = cur.fetchone()["o"]
        cur.execute(
            "INSERT INTO tasks(issue_id, title, acceptance_criteria, "
            "test_file_path, impl_file_path, ordering) "
            "VALUES (%s,%s,%s,%s,%s,%s) RETURNING id",
            (issue["id"], args.title, args.criteria, args.test, args.impl, ordering),
        )
        tid = cur.fetchone()["id"]
        conn.commit()
    print(f"task #{ordering} {tid} on {args.issue}: {args.title}")


def cmd_test(args):
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        issue = fetch_issue(cur, args.issue) if args.issue else None
        task = None
        if args.task:
            if not issue:
                fail("--issue required when --task is given")
            task = fetch_task(cur, issue["id"], args.task)
        if args.scope == "acceptance":
            if not issue or not issue["acceptance_test_path"]:
                fail("set acceptance_test_path first via set-acceptance")
            path = issue["acceptance_test_path"]
        elif args.scope == "task":
            if not task:
                fail("--task required for scope=task")
            path = task["test_file_path"]
        else:
            path = args.path or "."
        runner = args.runner or os.environ.get("TDD_RUNNER", DEFAULT_RUNNER)
        result = run_tests(path, runner)
        run_id = insert_test_run(
            cur,
            issue_id=(issue["id"] if issue else None) or (task["issue_id"] if task else None),
            task_id=task["id"] if task else None,
            scope=args.scope, result=result, runner=runner,
            commit_sha=head_sha(),
        )
        conn.commit()
    print(
        f"test_run {run_id} scope={args.scope} status={result.status} "
        f"passed={result.passed} failed={result.failed} errored={result.errored}"
    )
    if args.show_log:
        print(result.output)


def _commit_phase(args, phase: str, default_msg_tag: str):
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        issue = fetch_issue(cur, args.issue)
        task = fetch_task(cur, issue["id"], args.task)
        branch = ensure_branch(cur, issue)
        # 1. run the task test
        runner = args.runner or os.environ.get("TDD_RUNNER", DEFAULT_RUNNER)
        result = run_tests(task["test_file_path"], runner)
        # 2. require staged diff
        if not git("diff", "--cached", "--name-only", check=False).stdout.strip():
            fail("no staged changes — `git add` your work first")
        files = [l for l in git("diff", "--cached", "--name-only").stdout.splitlines() if l]
        # 3. record test_run BEFORE commit so commit FK passes
        run_id = insert_test_run(
            cur, issue_id=issue["id"], task_id=task["id"],
            scope="task", result=result, runner=runner,
            commit_sha=None,  # commit not made yet
        )
        # 4. make the git commit
        msg = args.message or f"[{default_msg_tag}][{issue['identifier']}] {task['title']}"
        git("commit", "-m", msg, capture=True)
        sha = head_sha()
        # 5. insert commit row (triggers fire here)
        try:
            cur.execute(
                "INSERT INTO commits(sha, branch_id, issue_id, task_id, parent_sha, "
                "message, phase, test_run_id, files_changed) "
                "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                (sha, branch["id"], issue["id"], task["id"],
                 git("rev-parse", "HEAD~1", check=False).stdout.strip() or None,
                 msg, phase, run_id, files),
            )
        except psycopg2.Error as e:
            git("reset", "--hard", "HEAD~1", capture=True)
            conn.rollback()
            fail(f"DB rejected {phase}: {e.pgerror or e}")
        update_branch_head(cur, branch["id"], sha)
        conn.commit()
    print(f"{phase} {sha[:8]} test={result.status} ({result.passed}/{result.test_count})")


def cmd_red(args):       _commit_phase(args, "DEV_RED", "RED")
def cmd_green(args):     _commit_phase(args, "DEV_GREEN", "GREEN")
def cmd_refactor(args):  _commit_phase(args, "REFACTOR", "REFACTOR")


def cmd_check(args):
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        issue = fetch_issue(cur, args.issue)
        cur.execute(
            "INSERT INTO checklist_results(issue_id, item_key, passed, evidence_url, "
            "checked_by) VALUES (%s,%s,%s,%s,%s) "
            "ON CONFLICT (issue_id, item_key) DO UPDATE SET "
            "passed=EXCLUDED.passed, evidence_url=EXCLUDED.evidence_url, "
            "checked_at=now()",
            (issue["id"], args.item, args.pass_, args.evidence,
             os.environ.get("TDD_AGENT_ID", DEFAULT_AGENT_ID)),
        )
        conn.commit()
    print(f"checklist {args.item}={'pass' if args.pass_ else 'fail'} on {args.issue}")


def cmd_open_pr(args):
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        issue = fetch_issue(cur, args.issue)
        branch = fetch_branch_for_issue(cur, issue["id"])
        if not branch:
            fail("no active branch for issue — claim first")
        diff = subprocess.check_output(
            ["git", "diff", f"{branch['base_sha']}..{branch['head_sha']}", "--stat"],
            cwd=repo_root(), text=True,
        )
        title = args.title or f"{issue['identifier']}: {issue['title']}"
        body = args.body or issue["description"] or ""
        cur.execute(
            "INSERT INTO pull_requests(issue_id, branch_id, title, body, state, "
            "base_sha, head_sha, diff_summary) VALUES "
            "(%s,%s,%s,%s,'open',%s,%s,%s) RETURNING id, number",
            (issue["id"], branch["id"], title, body,
             branch["base_sha"], branch["head_sha"], diff),
        )
        pr = cur.fetchone()
        conn.commit()
    print(f"PR #{pr['number']} opened ({pr['id']})")


def cmd_review(args):
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SELECT * FROM pull_requests WHERE number=%s", (args.pr,))
        pr = cur.fetchone()
        if not pr:
            fail(f"PR #{args.pr} not found")
        cur.execute(
            "INSERT INTO pr_reviews(pr_id, reviewer_agent_id, verdict, summary) "
            "VALUES (%s,%s,%s,%s) RETURNING id",
            (pr["id"], args.reviewer, args.verdict, args.summary),
        )
        new_state = {
            "approve": "approved",
            "request_changes": "changes_requested",
            "comment": pr["state"],
        }[args.verdict]
        cur.execute(
            "UPDATE pull_requests SET state=%s WHERE id=%s",
            (new_state, pr["id"]),
        )
        if args.verdict == "approve":
            cur.execute(
                "INSERT INTO checklist_results(issue_id, item_key, passed, "
                "checked_by) VALUES (%s,'reviewer_approved',true,%s) "
                "ON CONFLICT (issue_id, item_key) DO UPDATE SET passed=true, "
                "checked_at=now()",
                (pr["issue_id"], args.reviewer),
            )
        conn.commit()
    print(f"PR #{args.pr} → {new_state}")


def cmd_merge(args):
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SELECT * FROM pull_requests WHERE number=%s", (args.pr,))
        pr = cur.fetchone()
        if not pr:
            fail(f"PR #{args.pr} not found")
        cur.execute("SELECT name FROM branches WHERE id=%s", (pr["branch_id"],))
        branch_name = cur.fetchone()["name"]
        # do the local git merge first; if DB rejects, undo the merge
        git("checkout", "main", check=False)
        git("checkout", "master", check=False)  # try either
        git("merge", "--no-ff", "-m", f"Merge {branch_name}", branch_name)
        merged_sha = head_sha()
        try:
            cur.execute(
                "UPDATE pull_requests SET state='merged', head_sha=%s WHERE id=%s",
                (merged_sha, pr["id"]),
            )
        except psycopg2.Error as e:
            git("reset", "--hard", "HEAD~1", capture=True)
            conn.rollback()
            fail(f"merge rejected by DB: {e.pgerror or e}")
        conn.commit()
    print(f"PR #{args.pr} merged at {merged_sha[:8]}")


def cmd_replay(args):
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        issue = fetch_issue(cur, args.issue)
        cur.execute(
            "SELECT ts, kind, summary FROM v_session_replay WHERE issue_id=%s "
            "ORDER BY ts",
            (issue["id"],),
        )
        for r in cur.fetchall():
            print(f"{r['ts'].strftime('%H:%M:%S')} {r['kind']:<9} {r['summary']}")


_HINTS: dict[str, str] = {
    "WRITE_ACCEPTANCE_TEST": (
        "[DESIGN] Author the executable acceptance test that captures the "
        "issue's done-condition. It must FAIL today. Then run "
        "`tdd-cli set-acceptance --issue {id} --path <path>`."
    ),
    "WRITE_SPEC": (
        "[DESIGN] Write the spec doc. `git add` it, then "
        "`tdd-cli spec --issue {id}`. No code yet."
    ),
    "RUN_ACCEPTANCE_EXPECT_RED": (
        "[DESIGN] Run the acceptance test to record its baseline failure: "
        "`tdd-cli test --scope acceptance --issue {id}`. Status MUST be 'fail'."
    ),
    "DECOMPOSE_INTO_TASKS": (
        "[DESIGN] Split the spec into atomic TDD tasks. For each: "
        "`tdd-cli add-task --issue {id} --title ... --criteria ... "
        "--test PATH --impl PATH`."
    ),
    "WRITE_RED_TEST": (
        "[DEVELOPMENT] Write ONE failing test in {test_path}. "
        "`git add {test_path}` then `tdd-cli red --issue {id} --task {tidx}`. "
        "Do not edit {impl_path} in this turn."
    ),
    "MAKE_GREEN": (
        "[DEVELOPMENT] Implement the minimum in {impl_path} to turn the test "
        "green. `git add {impl_path}` then "
        "`tdd-cli green --issue {id} --task {tidx}`."
    ),
    "CONSIDER_REFACTOR": (
        "[DEVELOPMENT] Optional refactor while keeping tests green. "
        "If you change anything, `git add` then "
        "`tdd-cli refactor --issue {id} --task {tidx}`. Otherwise advance."
    ),
    "DEBUG_ACCEPTANCE_GAP": (
        "[VERIFICATION] All tasks done but acceptance still red. Diagnose "
        "the gap; usually means a missing task. Add it via add-task. Do NOT "
        "weaken the acceptance test."
    ),
    "COMPLETE_CHECKLIST": (
        "[VERIFICATION] Fill the missing checklist items: "
        "`tdd-cli check --issue {id} --item KEY --pass --evidence URL`."
    ),
    "OPEN_PR": (
        "[VERIFICATION] All gates met. `tdd-cli open-pr --issue {id}`."
    ),
    "AWAIT_OR_REQUEST_REVIEW": (
        "[VERIFICATION] Run reviewer agent or self-review: "
        "`tdd-cli review --pr N --verdict approve|request_changes`."
    ),
    "MERGE_PR": (
        "[VERIFICATION] `tdd-cli merge --pr N`. The DB will reject if any "
        "gate is red."
    ),
    "BLOCKED": (
        "[STOP] Issue is blocked. Record reason in decisions and hand off."
    ),
}

# Pure deterministic actions step --auto can execute itself.
_AUTO_RUNNABLE = {"RUN_ACCEPTANCE_EXPECT_RED"}


def cmd_step(args):
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        if args.issue:
            cur.execute(
                "SELECT * FROM work_queue WHERE identifier=%s", (args.issue,)
            )
        else:
            cur.execute("SELECT * FROM work_queue LIMIT 1")
        row = cur.fetchone()
        if not row:
            print(json.dumps({"done": True, "message": "queue empty"}))
            return

        issue_action = row["next_action"]
        action = issue_action
        focus_tidx = None
        test_path = impl_path = None

        if action == "WORK_NEXT_TASK":
            action = row["focus_task_action"] or "BLOCKED"
            if row["focus_task_id"]:
                cur.execute(
                    "SELECT t.*, "
                    "  (SELECT COUNT(*)+1 FROM tasks t2 "
                    "    WHERE t2.issue_id=t.issue_id "
                    "      AND (t2.ordering, t2.created_at) < (t.ordering, t.created_at) "
                    "  ) AS tidx "
                    "FROM tasks t WHERE t.id=%s",
                    (row["focus_task_id"],),
                )
                t = cur.fetchone()
                if t:
                    focus_tidx = t["tidx"]
                    test_path = t["test_file_path"]
                    impl_path = t["impl_file_path"]

        hint = _HINTS.get(action, "(no hint — consult docs)").format(
            id=row["identifier"], tidx=focus_tidx,
            test_path=test_path, impl_path=impl_path,
        )

        plan = {
            "issue_id":          str(row["issue_id"]),
            "issue":             row["identifier"],
            "title":             row["title"],
            "issue_next_action": issue_action,
            "task_action":       row["focus_task_action"],
            "focus_task_id":     str(row["focus_task_id"]) if row["focus_task_id"] else None,
            "focus_task_index":  focus_tidx,
            "test_path":         test_path,
            "impl_path":         impl_path,
            "phase_tag":         _phase_tag_for(action),
            "hint":              hint,
        }

    if args.auto and action in _AUTO_RUNNABLE:
        if action == "RUN_ACCEPTANCE_EXPECT_RED":
            sub_argv = ["test", "--scope", "acceptance", "--issue", row["identifier"]]
            print(json.dumps({**plan, "auto_executed": " ".join(sub_argv)}))
            main(sub_argv)
            return

    print(json.dumps(plan, indent=2))


def _phase_tag_for(action: str) -> str:
    if action in {
        "WRITE_ACCEPTANCE_TEST", "WRITE_SPEC", "RUN_ACCEPTANCE_EXPECT_RED",
        "DECOMPOSE_INTO_TASKS",
    }:
        return "DESIGN"
    if action in {"WRITE_RED_TEST", "MAKE_GREEN", "CONSIDER_REFACTOR"}:
        return "DEVELOPMENT"
    if action in {"DEBUG_ACCEPTANCE_GAP", "COMPLETE_CHECKLIST", "OPEN_PR",
                  "AWAIT_OR_REQUEST_REVIEW", "MERGE_PR"}:
        return "VERIFICATION"
    return "TESTING"


def cmd_turn_log(args):
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            "INSERT INTO agent_turns(session_id, issue_id, task_id, phase, "
            "next_action, prompt, response, tool_calls, tokens_in, tokens_out) "
            "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id",
            (args.session, args.issue_id, args.task_id, args.phase,
             args.action, args.prompt, args.response or "",
             args.tool_calls or "[]", args.tokens_in, args.tokens_out),
        )
        tid = cur.fetchone()["id"]
        conn.commit()
    print(tid)


def cmd_session_start(args):
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        issue_id = None
        if args.issue:
            issue_id = fetch_issue(cur, args.issue)["id"]
        cur.execute(
            "INSERT INTO sessions(agent_id, issue_id) VALUES (%s,%s) RETURNING id",
            (args.agent, issue_id),
        )
        sid = cur.fetchone()["id"]
        conn.commit()
    print(sid)


def cmd_session_end(args):
    with db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            "UPDATE sessions SET ended_at=now(), status=%s WHERE id=%s "
            "AND ended_at IS NULL",
            (args.status, args.session),
        )
        conn.commit()
    print(f"session {args.session} → {args.status}")


# ---------------------------------------------------------------------------
# argparse wiring
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="tdd-cli")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status").set_defaults(func=cmd_status)
    sub.add_parser("queue").set_defaults(func=cmd_queue)

    s = sub.add_parser("step",
        help="Print the next allowed action as JSON; --auto runs deterministic ones")
    s.add_argument("--issue")
    s.add_argument("--auto", action="store_true")
    s.set_defaults(func=cmd_step)

    s = sub.add_parser("claim")
    s.add_argument("--issue", required=True)
    s.set_defaults(func=cmd_claim)

    s = sub.add_parser("set-acceptance")
    s.add_argument("--issue", required=True)
    s.add_argument("--path", required=True)
    s.set_defaults(func=cmd_set_acceptance)

    s = sub.add_parser("spec")
    s.add_argument("--issue", required=True)
    s.add_argument("--message")
    s.set_defaults(func=cmd_spec)

    s = sub.add_parser("add-task")
    s.add_argument("--issue", required=True)
    s.add_argument("--title", required=True)
    s.add_argument("--criteria", required=True)
    s.add_argument("--test", required=True, dest="test")
    s.add_argument("--impl", required=True)
    s.set_defaults(func=cmd_add_task)

    s = sub.add_parser("test")
    s.add_argument("--scope", choices=["acceptance", "task", "full_suite"], required=True)
    s.add_argument("--issue")
    s.add_argument("--task")
    s.add_argument("--path")
    s.add_argument("--runner")
    s.add_argument("--show-log", action="store_true")
    s.set_defaults(func=cmd_test)

    for name, fn, tag in [
        ("red", cmd_red, "RED"),
        ("green", cmd_green, "GREEN"),
        ("refactor", cmd_refactor, "REFACTOR"),
    ]:
        s = sub.add_parser(name)
        s.add_argument("--issue", required=True)
        s.add_argument("--task", required=True)
        s.add_argument("--message")
        s.add_argument("--runner")
        s.set_defaults(func=fn)

    s = sub.add_parser("check")
    s.add_argument("--issue", required=True)
    s.add_argument("--item", required=True)
    s.add_argument("--evidence")
    grp = s.add_mutually_exclusive_group(required=True)
    grp.add_argument("--pass", dest="pass_", action="store_true")
    grp.add_argument("--fail", dest="pass_", action="store_false")
    s.set_defaults(func=cmd_check)

    s = sub.add_parser("open-pr")
    s.add_argument("--issue", required=True)
    s.add_argument("--title")
    s.add_argument("--body")
    s.set_defaults(func=cmd_open_pr)

    s = sub.add_parser("review")
    s.add_argument("--pr", type=int, required=True)
    s.add_argument("--verdict", choices=["approve", "request_changes", "comment"],
                   required=True)
    s.add_argument("--summary")
    s.add_argument("--reviewer", default="00000000-0000-0000-0000-000000000002")
    s.set_defaults(func=cmd_review)

    s = sub.add_parser("merge")
    s.add_argument("--pr", type=int, required=True)
    s.set_defaults(func=cmd_merge)

    s = sub.add_parser("replay")
    s.add_argument("--issue", required=True)
    s.set_defaults(func=cmd_replay)

    s = sub.add_parser("turn-log")
    s.add_argument("--session", required=True)
    s.add_argument("--issue-id")
    s.add_argument("--task-id")
    s.add_argument("--phase")
    s.add_argument("--action")
    s.add_argument("--prompt", required=True)
    s.add_argument("--response")
    s.add_argument("--tool-calls")
    s.add_argument("--tokens-in", type=int)
    s.add_argument("--tokens-out", type=int)
    s.set_defaults(func=cmd_turn_log)

    s = sub.add_parser("session-start")
    s.add_argument("--agent", default=DEFAULT_AGENT_ID)
    s.add_argument("--issue")
    s.set_defaults(func=cmd_session_start)

    s = sub.add_parser("session-end")
    s.add_argument("--session", required=True)
    s.add_argument("--status", default="done", choices=["done", "aborted"])
    s.set_defaults(func=cmd_session_end)

    return p


def main(argv: Optional[list[str]] = None) -> None:
    args = build_parser().parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
