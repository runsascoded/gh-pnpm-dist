#!/usr/bin/env bash
# Guard against git's directory/file (D/F) conflict on the dist branch name.
#
# git stores each branch as a file under .git/refs/heads/, so a bare branch
# `dist` (the file refs/heads/dist) and a namespaced branch `dist/treemap`
# (which needs refs/heads/dist to be a *directory*) cannot coexist. Creating
# the second yields a cryptic git error; this detects it up front.
#
# Two sourceable functions:
#   dist_branch_conflict <dist_branch> <heads>  # pure; heads = newline-separated
#     bare branch names. Prints an actionable message and returns 1 on conflict.
#   check_dist_branch <dist_branch> [remote]    # fetches the remote's heads and
#     calls the pure function; returns 1 (message on stderr) on conflict.

# Pure conflict check. `heads` is a newline-separated list of existing bare
# branch names (no refs/heads/ prefix). Case-insensitive-safe exact matching
# via bash `case` globs, so branch names with regex metacharacters are fine.
dist_branch_conflict() {
  local dist_branch="$1"
  local heads="$2"
  local h

  if [[ "$dist_branch" == */* ]]; then
    # Namespaced (e.g. dist/treemap): the first segment must not exist as a
    # bare branch (that file would block the dist/ directory).
    local first="${dist_branch%%/*}"
    while IFS= read -r h; do
      [ -z "$h" ] && continue
      if [ "$h" = "$first" ]; then
        echo "ERROR: cannot create '$dist_branch' — a bare '$first' branch exists (git dir/file conflict)."
        echo "  Rename it (e.g. '$first/<pkg>') or delete it first, then re-run."
        return 1
      fi
    done <<< "$heads"
  else
    # Bare (e.g. dist): no namespaced branch may exist under <dist_branch>/.
    local conflicting=""
    while IFS= read -r h; do
      [ -z "$h" ] && continue
      case "$h" in
        "$dist_branch"/*) conflicting="${conflicting}    ${h}"$'\n' ;;
      esac
    done <<< "$heads"
    if [ -n "$conflicting" ]; then
      echo "ERROR: cannot create bare '$dist_branch' — namespaced branch(es) exist under '$dist_branch/' (git dir/file conflict):"
      printf '%s' "$conflicting"
      echo "  Use a namespaced dist branch (e.g. '$dist_branch/<pkg>') or delete those branches first."
      return 1
    fi
  fi
  return 0
}

# Fetch the remote's branch names and run the pure check. Aborts (returns 1,
# message on stderr) on a D/F conflict.
check_dist_branch() {
  local dist_branch="$1"
  local remote="${2:-origin}"
  local heads msg
  heads=$(git ls-remote --heads "$remote" 2>/dev/null | sed 's#.*refs/heads/##')
  if ! msg=$(dist_branch_conflict "$dist_branch" "$heads"); then
    echo "$msg" >&2
    return 1
  fi
  return 0
}
