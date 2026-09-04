#!/usr/bin/env bash
# Tests for dist_branch_conflict (the pure D/F guardrail). Sources
# scripts/check-dist-branch.sh from the same repo so test/impl drift is
# structurally prevented.
#
# Run from anywhere:  bash gh/tests/test-check-dist-branch.sh
set -e

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/.." && pwd)"

# shellcheck source=../scripts/check-dist-branch.sh
source "$REPO_ROOT/scripts/check-dist-branch.sh"

PASS=0
FAIL=0

# Assert dist_branch_conflict's exit status (0 = ok, 1 = conflict) for a given
# branch name against a newline-separated heads list.
check_status() {
  local desc="$1" branch="$2" heads="$3" want="$4"
  local got
  if dist_branch_conflict "$branch" "$heads" > /dev/null 2>&1; then
    got=0
  else
    got=1
  fi
  if [ "$got" = "$want" ]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc (want status $want, got $got)"
    FAIL=$((FAIL + 1))
  fi
}

# Assert the message printed on a conflict equals an expected multi-line string.
check_message() {
  local desc="$1" branch="$2" heads="$3" expected="$4"
  local actual
  actual=$(dist_branch_conflict "$branch" "$heads" 2>&1 || true)
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    echo "  expected: |$expected|"
    echo "  actual:   |$actual|"
    FAIL=$((FAIL + 1))
  fi
}

HEADS_BARE=$'main\ndist\nfeature/x'
HEADS_NS=$'main\ndist/react\ndist/treemap'
HEADS_NONE=$'main\nfeature/x'

# ----- Namespaced target vs. an existing bare `dist` -> conflict -----
check_status "dist/treemap blocked by bare dist" "dist/treemap" "$HEADS_BARE" 1
check_message "dist/treemap conflict message" "dist/treemap" "$HEADS_BARE" \
"ERROR: cannot create 'dist/treemap' — a bare 'dist' branch exists (git dir/file conflict).
  Rename it (e.g. 'dist/<pkg>') or delete it first, then re-run."

# ----- Namespaced target when no bare `dist` exists -> ok -----
check_status "dist/treemap ok when only dist/* exist" "dist/treemap" "$HEADS_NS" 0
check_status "dist/foo ok when heads have no dist at all" "dist/foo" "$HEADS_NONE" 0

# ----- Bare target vs. existing namespaced `dist/*` -> conflict -----
check_status "bare dist blocked by dist/* branches" "dist" "$HEADS_NS" 1
check_message "bare dist conflict message lists both dist/* branches" "dist" "$HEADS_NS" \
"ERROR: cannot create bare 'dist' — namespaced branch(es) exist under 'dist/' (git dir/file conflict):
    dist/react
    dist/treemap
  Use a namespaced dist branch (e.g. 'dist/<pkg>') or delete those branches first."

# ----- Bare target when only a bare `dist` (or nothing) exists -> ok -----
check_status "bare dist ok alongside existing bare dist" "dist" "$HEADS_BARE" 0
check_status "bare dist ok when no dist refs exist" "dist" "$HEADS_NONE" 0

# ----- Empty heads (fresh repo) never conflicts -----
check_status "namespaced ok on empty heads" "dist/treemap" "" 0
check_status "bare ok on empty heads" "dist" "" 0

# ----- Prefix must be a full path segment (dist2 is not under dist/) -----
check_status "bare dist not blocked by unrelated dist2 branch" "dist" $'main\ndist2\ndist2/x' 0

echo ""
echo "================================"
echo "Passed: $PASS / $((PASS + FAIL))"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed: $FAIL"
  exit 1
fi
