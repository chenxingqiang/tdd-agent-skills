#!/usr/bin/env bash
# End-to-end demo: an autonomous TDD agent walks `TDD-1` (slugify) from
# Todo to Done — spec, acceptance test, decompose, RED -> GREEN -> REFACTOR,
# 13-item checklist, PR open, reviewer approve, merge — all via `tdd-cli`,
# every step blessed (or rejected) by Supabase triggers.
#
# Self-contained: spins up a throwaway Postgres on :55432, a throwaway git
# repo under a temp dir, runs the migrations, runs the workflow, prints the
# session replay. Cleans up on exit.
#
# Prereqs: docker, python3 with psycopg2-binary, git, pytest, psql.
#   pip install pytest psycopg2-binary
#
# Usage:
#   bash examples/tdd-1-slugify-walkthrough.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PG_NAME="tdd-demo-pg-$$"
TMP_REPO="$(mktemp -d -t tdd-demo-XXXXXX)"
export TDD_DB_URL='postgresql://postgres:demo@localhost:55432/postgres'
export TDD_REPO_ROOT="$TMP_REPO"
export PGPASSWORD=demo

cleanup() {
  set +e
  docker stop "$PG_NAME" >/dev/null 2>&1
  rm -rf "$TMP_REPO"
}
trap cleanup EXIT

step() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
step "1. start throwaway Postgres + apply migrations"
docker run -d --rm --name "$PG_NAME" \
  -e POSTGRES_PASSWORD=demo -p 55432:5432 postgres:15-alpine >/dev/null
for i in 1 2 3 4 5 6 7 8 9 10; do
  docker exec "$PG_NAME" pg_isready -U postgres >/dev/null 2>&1 && break
  sleep 1
done
for f in "$REPO_ROOT"/supabase/migrations/*.sql; do
  psql -h localhost -p 55432 -U postgres -v ON_ERROR_STOP=1 -q -f "$f" >/dev/null
done
echo "  migrations applied"

# ---------------------------------------------------------------------------
step "2. scaffold throwaway git repo"
cd "$TMP_REPO"
git init -q -b main
git config user.email demo@example.com
git config user.name "TDD Demo"
mkdir -p src tests/acceptance
echo "# slugify project" > README.md
git add README.md && git commit -q -m "chore: bootstrap"

# ---------------------------------------------------------------------------
step "3. agent: claim issue"
TDD_CLI="$REPO_ROOT/bin/tdd-cli"
"$TDD_CLI" claim --issue TDD-1

# ---------------------------------------------------------------------------
step "4. agent: ask DB what's next (expect WRITE_ACCEPTANCE_TEST)"
"$TDD_CLI" step

# ---------------------------------------------------------------------------
step "5. [DESIGN] author acceptance test (must FAIL today)"
cat > tests/acceptance/test_slug.py <<'EOF'
import pytest
import importlib

def test_acceptance_slugify_hello_world():
    mod = importlib.import_module("src.slug")
    assert mod.slugify("  Hello, World!  ") == "hello-world"
EOF
touch tests/__init__.py tests/acceptance/__init__.py src/__init__.py
"$TDD_CLI" set-acceptance --issue TDD-1 --path tests/acceptance/test_slug.py

# ---------------------------------------------------------------------------
step "6. [DESIGN] write spec, commit it via tdd-cli spec"
mkdir -p docs/specs
cat > docs/specs/TDD-1.md <<'EOF'
# TDD-1: slugify()

`slugify(text: str) -> str`:
- lowercases, strips outer whitespace
- replaces every run of non-alphanumeric chars with a single hyphen
- collapses repeats, trims leading/trailing hyphens

Acceptance: `slugify("  Hello, World!  ") == "hello-world"`.
EOF
git add docs/specs/TDD-1.md tests/acceptance/test_slug.py tests/__init__.py \
        tests/acceptance/__init__.py src/__init__.py
"$TDD_CLI" spec --issue TDD-1 --message "[SPEC][TDD-1] slugify contract"

# ---------------------------------------------------------------------------
step "7. [DESIGN] run acceptance test — must be RED baseline"
"$TDD_CLI" test --scope acceptance --issue TDD-1 || true

# ---------------------------------------------------------------------------
step "8. [DESIGN] decompose into one task"
"$TDD_CLI" add-task --issue TDD-1 \
  --title "lowercase + non-alnum to hyphen + collapse" \
  --criteria "slugify('  Hello, World!  ') == 'hello-world'" \
  --test tests/test_slug.py --impl src/slug.py

# ---------------------------------------------------------------------------
step "9. [DEVELOPMENT] write failing unit test (RED)"
# Drop a stub impl on disk (UNSTAGED) so import resolves and the test fails
# on assertion — canonical RED. Without it pytest reports collection error
# (status=error), which the DEV_RED trigger rejects (it requires status=fail).
cat > src/slug.py <<'EOF'
def slugify(text: str) -> str:
    return ""
EOF
cat > tests/test_slug.py <<'EOF'
from src.slug import slugify

def test_slugify_basic():
    assert slugify("  Hello, World!  ") == "hello-world"
EOF
git add tests/test_slug.py   # stub src/slug.py stays unstaged — RED commits only the test
"$TDD_CLI" red --issue TDD-1 --task 1 --message "[RED][TDD-1] failing slugify test"

# ---------------------------------------------------------------------------
step "10. [DEVELOPMENT] minimal implementation (GREEN)"
cat > src/slug.py <<'EOF'
import re

def slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
EOF
git add src/slug.py
"$TDD_CLI" green --issue TDD-1 --task 1 --message "[GREEN][TDD-1] implement slugify"

# ---------------------------------------------------------------------------
step "11. [DEVELOPMENT] cosmetic refactor (tests stay green)"
cat > src/slug.py <<'EOF'
"""Slug utilities."""
import re

_NON_ALNUM = re.compile(r"[^a-z0-9]+")

def slugify(text: str) -> str:
    """Lowercase, replace non-alphanumeric runs with single hyphens, trim."""
    return _NON_ALNUM.sub("-", text.lower()).strip("-")
EOF
git add src/slug.py
"$TDD_CLI" refactor --issue TDD-1 --task 1 --message "[REFACTOR][TDD-1] doc + precompile"

# ---------------------------------------------------------------------------
step "12. [TESTING] re-run acceptance — should now be GREEN"
"$TDD_CLI" test --scope acceptance --issue TDD-1

# ---------------------------------------------------------------------------
step "13. [VERIFICATION] complete the 12 self-checkable checklist items"
for k in acceptance_green all_tasks_done full_suite_green no_skipped_tests \
         coverage_threshold lint_clean type_check_clean security_scan_clean \
         docs_updated changelog_entry migration_safe observability; do
  "$TDD_CLI" check --issue TDD-1 --item "$k" --pass --evidence "demo://$k" >/dev/null
done
echo "  12/13 checklist items recorded (reviewer_approved comes from review)"

# ---------------------------------------------------------------------------
step "14. open PR + reviewer approves (auto-marks reviewer_approved)"
"$TDD_CLI" open-pr --issue TDD-1
"$TDD_CLI" review --pr 1 --verdict approve \
  --summary "Spec, RED before GREEN, refactor green, 13/13 checklist."

# ---------------------------------------------------------------------------
step "15. merge — DB gate must accept"
"$TDD_CLI" merge --pr 1

# ---------------------------------------------------------------------------
step "16. final dashboard + replay"
"$TDD_CLI" status
echo
"$TDD_CLI" replay --issue TDD-1

step "DONE — TDD-1 walked from Todo to Done with full audit trail."
