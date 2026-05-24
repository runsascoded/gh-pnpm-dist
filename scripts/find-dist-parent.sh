#!/usr/bin/env bash
# Source this file to define find_dist_parent. Safe to source multiple times.
#
# find_dist_parent <dist_tip> <source_sha> <mode>
#   <mode>: rewrite | preserve | error
#
# Echoes the SHA to use as the 1st parent of the new dist commit, or exits non-zero.
# - preserve: always returns dist_tip (old behavior).
# - error:    returns dist_tip iff its source-parent is an ancestor of source_sha; else fails.
# - rewrite:  walks dist commits (via 1st parent) and returns the most recent whose
#             source-parent is an ancestor of source_sha. Lets dist ancestry mirror source
#             ancestry after a force-push of the source ref.
#
# A "dist commit" here is either:
#   - a 2-parent merge commit (built dist commit): source-parent is ^2
#   - the initial 1-parent dist commit: source-parent is ^1
#
# Anything else (e.g. hand-edited single-parent commit between builds) is not currently
# handled — the walk stops when it hits a non-merge that isn't the initial dist commit.

find_dist_parent() {
  local dist_tip="$1"
  local source_sha="$2"
  local mode="${3:-rewrite}"

  case "$mode" in
    preserve)
      echo "$dist_tip"
      return 0
      ;;
    error)
      local src
      if src=$(git rev-parse --verify "$dist_tip^2" 2>/dev/null) || src=$(git rev-parse --verify "$dist_tip^1" 2>/dev/null); then
        if git merge-base --is-ancestor "$src" "$source_sha"; then
          echo "$dist_tip"
          return 0
        fi
        echo "ERROR: dist tip $dist_tip's source-parent ($src) is not an ancestor of source $source_sha." >&2
        echo "       Source ref appears force-pushed. Set on_source_rewrite=rewrite to rebuild on a shared ancestor, or =preserve to chain onto dist tip anyway." >&2
        return 1
      fi
      echo "ERROR: dist tip $dist_tip has no parent — cannot determine source ancestry." >&2
      return 1
      ;;
    rewrite)
      ;;
    *)
      echo "ERROR: invalid on_source_rewrite=$mode (expected: rewrite|preserve|error)" >&2
      return 1
      ;;
  esac

  local node="$dist_tip"
  while [ -n "$node" ]; do
    local src
    if src=$(git rev-parse --verify "$node^2" 2>/dev/null); then
      if git merge-base --is-ancestor "$src" "$source_sha"; then
        if [ "$node" != "$dist_tip" ]; then
          echo "note: source ref appears force-pushed; rebuilding dist on top of $node (skipped intermediate dist commits whose source-parents are no longer reachable from $source_sha)" >&2
        fi
        echo "$node"
        return 0
      fi
      node=$(git rev-parse "$node^1")
    else
      if src=$(git rev-parse --verify "$node^1" 2>/dev/null); then
        if git merge-base --is-ancestor "$src" "$source_sha"; then
          if [ "$node" != "$dist_tip" ]; then
            echo "note: source ref appears force-pushed; rebuilding dist on top of initial dist commit $node" >&2
          fi
          echo "$node"
          return 0
        fi
      fi
      break
    fi
  done

  echo "ERROR: no dist commit's source-parent is an ancestor of $source_sha (force-push to unrelated history?)." >&2
  echo "       Set on_source_rewrite=preserve to chain onto dist tip anyway." >&2
  return 1
}
