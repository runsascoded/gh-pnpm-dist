# Namespaced dist branches: a `dist/<pkg>` convention for multi-target repos

## Motivation

A monorepo can publish more than one package to its own dist branch (via
`package_dir` mode — one workflow per package). Today each picks an ad-hoc flat
name (`dist`, `treemap-dist`, `foo-dist`), so a repo's dist branches don't group
or sort together. Nicer: **namespace them under `dist/`** — `dist/treemap`,
`dist/react`, … — so `git branch --list 'dist/*'` enumerates every dist target
and they cluster in listings.

Live driver: `runsascoded/disk-tree` just split its widget package into
`@rdub/treemap` (core) + `@disk-tree/react` (disk widgets); it wants
`dist/treemap` now and possibly `dist/react` later.

## What already works (no change needed)

The `dist_branch` input already accepts any valid ref name, and slashes are
valid, so **`dist_branch: dist/treemap` works today** end to end:

- **Producing**: `build-dist.sh` only does `git fetch/checkout/orphan
  "$DIST_BRANCH"` — all accept slashed refs.
- **Consuming**: consumers pin the **resolved SHA** (`github:owner/repo#<sha>`),
  never the branch name — `pds gh` resolves via `gh api repos/{o}/{r}/commits/
  dist/treemap` → SHA. The slash never reaches `package.json` / `pnpm install`.

So this spec is **not** about enabling slashed branches — it's about (1) a
guardrail for the one way they bite, (2) documenting the convention, and (3) an
optional convenience so callers don't hand-write `dist/<pkg>`.

## The one hard constraint: git's directory/file (D/F) rule

A ref `dist/treemap` requires `dist` to be a **directory** under
`refs/heads/`, but a bare `dist` branch is a **file** there. **`dist` and
`dist/<anything>` cannot coexist.** So a repo currently on the default bare
`dist` branch cannot add `dist/<x>` without first renaming/deleting `dist`.

This is exactly why **the namespaced form cannot become a silent default**:
flipping the default from `dist` to `dist/<pkg>` would break every existing
single-target repo — their next build would try to create `dist/<pkg>` while
their bare `dist` exists → D/F failure — and would break anyone who pinned the
branch *name* `#dist` (rare, but real). The default must stay `dist`.

## Asks (#1 + #2 shipped; #3 built then dropped as low-value)

### 1. D/F guardrail (highest value) — done

Before creating a dist branch, the build scripts detect the conflict and fail
with an actionable message instead of a cryptic git error.

Implemented as a new sourceable, unit-tested script rather than inline (mirrors
`find-dist-parent.sh` / `merge-dist-package.sh`), so the logic can be tested in
isolation and shared across `build-dist.sh` + `build-dist-monorepo.sh` (gh) and
their gl copies:

- **`scripts/check-dist-branch.sh`**:
  - `dist_branch_conflict <dist_branch> <heads>` — pure (heads = newline-separated
    bare branch names); prints an actionable message and returns 1 on conflict.
    Both directions: a namespaced `dist/treemap` blocked by a bare `dist`; a bare
    `dist` blocked by any `dist/*`. Uses bash `case`-glob exact matching so a
    prefix like `dist` never matches an unrelated `dist2`.
  - `check_dist_branch <dist_branch> [remote]` — thin wrapper: `git ls-remote
    --heads <remote>` → pure check; aborts on conflict.
- Both build scripts `source` it and call `check_dist_branch "$DIST_BRANCH" origin`
  right before the dist-branch fetch/checkout.
- Deviation from the spec's original sketch (`ls-remote --exit-code
  refs/heads/dist`): the list-all-heads + pure-function form is equivalent but
  testable and covers both conflict directions in one place.

### 2. Document the convention — done

New **“Namespaced dist branches (`dist/<pkg>`)”** section in both `gh/README.md`
and `gl/README.md` (under `package_dir` / monorepo mode), pointing at
`dist_branch: dist/treemap`. Explains the D/F rule, that a legacy bare `dist`
must be renamed (old SHA pins keep resolving), and that the default stays bare
`dist`.

### 3. Optional convenience: derive `dist/<pkg>` — implemented, then reverted

Built as `resolve-dist-branch.sh` (a `dist_prefix` input deriving
`<prefix>/<basename>` from the package name) with a resolve step in `action.yml`
and a resolve block in the gl template, plus a 13-case unit test — then **removed**
before final release.

Reason: for a single package it gains nothing over `dist_branch: dist/treemap` —
it splits one known string (`dist/treemap`) into a prefix input + a basename
auto-derived from the package name, in exchange for added surface (a script, a
resolve step, and a `dist_branch` default flip `'dist'`→`''` to distinguish unset
from explicit). It would only pay off in a matrix/templated workflow building N
packages from one file, but npm-dist consumers write one workflow per package and
just set `dist_branch` inline. The spec flagged #3 as optional and the disk-tree
driver needed only #1–2; the explicit `dist_branch` (which already accepts
slashes — pre-existing) fully covers the use case.

Net of this spec: **#1 (guardrail) + #2 (docs) only.** `dist_branch` keeps its
`'dist'` default; slashed names remain supported as they always were.

### Tests

- `tests/test-check-dist-branch.sh` (11 cases): both conflict directions, exact
  messages, empty heads, `dist` vs unrelated `dist2`. Copied to gl; passes in
  both. Existing `merge`/`find-dist-parent` tests still green.

## Non-goals

- No change to the default branch (`dist`) or its handling — `dist_branch`
  keeps its `'dist'` default; the guardrail only fires on a real D/F conflict.
- No change to how consumers pin (still resolved SHAs).

## Consumer note (disk-tree side, already done)

disk-tree's `build-dist.yml` sets `dist_branch: dist/treemap` explicitly and
renamed its legacy `dist` branch → `dist/react` to clear the D/F conflict. That
one field is the whole story — it worked against the pre-existing npm-dist (no
change needed to unblock disk-tree); this spec only adds the guardrail + docs
around it.
