#!/usr/bin/env bash
# Tests for resolve_dist_branch / dist_branch_basename. Sources
# scripts/resolve-dist-branch.sh from the same repo so test/impl drift is
# structurally prevented.
#
# Run from anywhere:  bash gh/tests/test-resolve-dist-branch.sh
set -e

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/.." && pwd)"

# shellcheck source=../scripts/resolve-dist-branch.sh
source "$REPO_ROOT/scripts/resolve-dist-branch.sh"

WORK=$(mktemp -d -t resolve-dist-branch-test.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

PASS=0
FAIL=0

check_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

# Write a package.json with the given name at the given dir (dir "" = root).
write_pkg() {
  local dir="$1" name="$2"
  local path="package.json"
  [ -n "$dir" ] && { mkdir -p "$dir"; path="$dir/package.json"; }
  printf '{ "name": "%s", "version": "0.1.0" }\n' "$name" > "$path"
}

# ----- dist_branch_basename (pure) -----
check_eq "basename strips scope" "treemap" "$(dist_branch_basename "@rdub/treemap" "packages/treemap")"
check_eq "basename of unscoped name" "foo" "$(dist_branch_basename "foo" "packages/foo")"
check_eq "basename falls back to dir when name empty" "treemap" "$(dist_branch_basename "" "packages/treemap")"
check_eq "basename falls back to dir when name null" "treemap" "$(dist_branch_basename "null" "packages/treemap")"
check_eq "basename final fallback is dist" "dist" "$(dist_branch_basename "" "")"

# ----- resolve_dist_branch: explicit branch always wins -----
check_eq "explicit branch wins over prefix" "custom/x" "$(resolve_dist_branch "custom/x" "dist" "packages/treemap" "")"
check_eq "explicit bare branch wins" "dist" "$(resolve_dist_branch "dist" "" "" "")"

# ----- resolve_dist_branch: no prefix, no branch -> bare dist -----
check_eq "default is bare dist" "dist" "$(resolve_dist_branch "" "" "" "")"

# ----- resolve_dist_branch: prefix + package_dir reads that package.json -----
write_pkg "packages/treemap" "@rdub/treemap"
check_eq "prefix + package_dir derives dist/treemap" "dist/treemap" \
  "$(resolve_dist_branch "" "dist" "packages/treemap" "")"

# ----- prefix trailing slash is normalized -----
check_eq "prefix trailing slash trimmed" "dist/treemap" \
  "$(resolve_dist_branch "" "dist/" "packages/treemap" "")"

# ----- prefix + package_dir with no package.json -> basename(package_dir) -----
check_eq "prefix + package_dir missing pkg.json falls back to dir basename" "dist/widget" \
  "$(resolve_dist_branch "" "dist" "packages/widget" "")"

# ----- prefix + pkgs (monorepo list) uses the first package -----
write_pkg "packages/core" "@rdub/core"
check_eq "prefix + pkgs uses first package name" "dist/core" \
  "$(resolve_dist_branch "" "dist" "" $'packages/core\npackages/treemap')"

# ----- prefix + root package.json (no package_dir/pkgs) -----
write_pkg "" "@acme/root-widget"
check_eq "prefix + root package.json derives from root name" "dist/root-widget" \
  "$(resolve_dist_branch "" "dist" "" "")"

echo ""
echo "================================"
echo "Passed: $PASS / $((PASS + FAIL))"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed: $FAIL"
  exit 1
fi
