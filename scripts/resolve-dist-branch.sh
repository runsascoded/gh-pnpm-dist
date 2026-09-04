#!/usr/bin/env bash
# Resolve the effective dist branch name, supporting the optional `dist_prefix`
# convenience for the namespaced `dist/<pkg>` convention.
#
# Precedence:
#   1. An explicit dist_branch always wins (verbatim).
#   2. Else, if dist_prefix is set, derive `<dist_prefix>/<basename>` where
#      <basename> is the package name's last segment (@rdub/treemap -> treemap),
#      falling back to basename(package_dir) when the name is unavailable.
#   3. Else, the default bare `dist`.
#
# Idempotent: calling resolve_dist_branch on an already-resolved (non-empty)
# dist_branch returns it unchanged, so an outer layer and the build script can
# both call it without compounding.

# Pure: pick the branch basename from a package name (preferred) or the package
# directory (fallback).
dist_branch_basename() {
  local pkg_name="$1"
  local package_dir="$2"
  if [ -n "$pkg_name" ] && [ "$pkg_name" != "null" ]; then
    printf '%s\n' "${pkg_name##*/}"
  elif [ -n "$package_dir" ]; then
    printf '%s\n' "${package_dir##*/}"
  else
    printf '%s\n' "dist"
  fi
}

# resolve_dist_branch <dist_branch> <dist_prefix> <package_dir> <pkgs>
# Reads package.json from the working tree to derive the basename when needed.
resolve_dist_branch() {
  local dist_branch="$1"
  local dist_prefix="$2"
  local package_dir="$3"
  local pkgs="$4"

  if [ -n "$dist_branch" ]; then
    printf '%s\n' "$dist_branch"
    return 0
  fi
  if [ -z "$dist_prefix" ]; then
    printf '%s\n' "dist"
    return 0
  fi

  # Derive <prefix>/<basename>. Determine which package.json names the target.
  local pkg_json pdir
  if [ -n "$package_dir" ]; then
    pdir="$package_dir"
    pkg_json="$package_dir/package.json"
  elif [ -n "$pkgs" ]; then
    # Monorepo pkgs list: use the first package.
    pdir=$(printf '%s' "$pkgs" | tr '\n' ',' | sed 's/,,*/,/g; s/^,//; s/,$//' | cut -d',' -f1 | xargs)
    pkg_json="$pdir/package.json"
  else
    pdir=""
    pkg_json="package.json"
  fi

  local name=""
  if [ -f "$pkg_json" ]; then
    name=$(jq -r '.name // ""' "$pkg_json" 2>/dev/null)
  fi

  printf '%s\n' "${dist_prefix%/}/$(dist_branch_basename "$name" "$pdir")"
}
