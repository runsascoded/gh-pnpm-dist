# Force-push resilience for dist branch

## Problem

When the source branch (e.g. `main`) is force-pushed (commit amended, rebased, etc.), the next dist build still chains onto the previous dist commit unconditionally. The previous dist commit's 2nd parent points at the now-abandoned source commit, so the dist branch silently accumulates references to zombie main commits.

Scenario:

1. main: `… — m0 — m1`; dist: `… — d0 — d1`, where `d1` has parents `(d0, m1)` and `d0` has parents `(…, m0)`.
2. User amends `m1` → `m2`, force-pushes main.
3. Next dist build today: produces `d2` with parents `(d1, m2)`. `d1` still references `m1`, so `git log --graph dist` shows edges into the abandoned `m1`.

Desired (PoLS): `d2` should have parents `(d0, m2)` — replacing `d1` (the dist commit for the abandoned `m1`) rather than chaining onto it. Dist ancestry mirrors source ancestry.

## Proposed behavior

New input/env var: `on_source_rewrite` with values `rewrite` (default), `preserve`, `error`.

- **`rewrite`** (new default): walk dist commits backward starting from the current dist tip. For each, check if its source-parent (2nd parent) is `--is-ancestor` of the new source SHA. Use the most recent such dist commit as the new dist parent. If none qualifies (no shared ancestry), behave as `error`.
- **`preserve`** (old behavior): always chain onto current dist tip. Useful if a user has hand-edited dist commits that should not be dropped.
- **`error`**: if the previous dist commit's source-parent is not an ancestor of new source SHA, fail loudly.

### Walk details

Given new source SHA `S` and current dist tip `D`:

```
node = D
while node has a 2nd parent (i.e. is a merge commit from a prior build):
  src_parent = $(git rev-parse "$node^2")
  if git merge-base --is-ancestor "$src_parent" "$S"; then
    use $node as the new dist parent; exit loop
  fi
  node = $(git rev-parse "$node^1")  # walk to previous dist commit
done
# if we walked to a 1st-parent that isn't a merge (the initial orphan or single-parent first commit),
# treat that as the new parent (its source ancestry is by construction the root)
```

The first dist commit (no prior dist) has a single parent (the source commit) — see `build-dist.sh:335`. So the walk terminates when we hit a non-merge ancestor; that ancestor's only parent is a source commit that may or may not be an ancestor of `S`. If it is, use it as parent. If not, no shared ancestry → error/orphan.

### Fallback when no shared ancestry

If the walk finds nothing (e.g. force-push to completely unrelated history): default to `error` rather than silently orphan-restarting, since "we didn't recognize any of this" is more likely a user mistake than an intended workflow. `preserve` users opting out is the escape hatch.

## Implementation

`find_dist_parent` lives in `scripts/find-dist-parent.sh` and is sourced by both `build-dist.sh` and `build-dist-monorepo.sh`. Each repo (gh, gl) carries its own copy of the file — gh and gl scripts diverge in other ways already, so cross-repo sharing is deferred.

Call site (replacing the current `if DIST_PARENT=$(git rev-parse --verify HEAD 2>/dev/null); then` block at `build-dist.sh:328`):

```bash
if DIST_TIP=$(git rev-parse --verify HEAD 2>/dev/null); then
  DIST_PARENT=$(find_dist_parent "$DIST_TIP" "$SOURCE_SHA" "$ON_SOURCE_REWRITE")
  COMMIT=$(git commit-tree "$TREE" -p "$DIST_PARENT" -p "$SOURCE_SHA" -m "$COMMIT_MSG")
else
  COMMIT=$(git commit-tree "$TREE" -p "$SOURCE_SHA" -m "$COMMIT_MSG")
fi
```

`find_dist_parent` returns the SHA to use as 1st parent (may equal `DIST_TIP` if no rewrite needed), or exits non-zero with a clear message in the `error` case.

### GH wiring

- Add `on_source_rewrite` input to `gh/action.yml` (default `rewrite`).
- Plumb into env var for the "Commit to dist branch" steps.

### GL wiring

- Add `ON_SOURCE_REWRITE` variable to `gl/dist.gitlab-ci.yml` `.build-dist` `variables:` block (default `rewrite`).

### Monorepo mode

`build-dist-monorepo.sh` should get the same treatment. Same function, same call site.

## Out of scope

- **Truly shared library across gh/gl**: `build-dist.sh` is duplicated across the two repos today (with drift — gh has `preserve_dirs`, `exports_map` that gl lacks). A real shared-lib refactor (single canonical source, both repos pull at runtime) would be valuable but is a separate, larger change.

## Testing

`tests/test-find-dist-parent.sh` sources `scripts/find-dist-parent.sh` and exercises 9 scenarios against a scratch git repo: normal forward push (rewrite/error), amend force-push (rewrite walks back / error fails / preserve unchanged), multi-step rebase (walks back further), force-push to unrelated history (errors), invalid mode rejected. Run with `bash tests/test-find-dist-parent.sh`.

End-to-end smoke test against a real consumer:

1. Pick a consumer repo with a dist branch (e.g. `use-url-params`).
2. Push a commit `m1`, trigger build → check dist has `d1` with parents `(d0, m1)`.
3. Amend `m1` → `m2`, force-push, trigger build → check `d2` parents.
   - With `on_source_rewrite=rewrite`: should be `(d0, m2)`.
   - With `on_source_rewrite=preserve`: should be `(d1, m2)` (old behavior).
   - With `on_source_rewrite=error`: should fail with a clear message.
