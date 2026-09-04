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

## Asks

### 1. D/F guardrail (highest value)

Before creating a dist branch, `build-dist.sh` should detect the conflict and
fail with an actionable message instead of a cryptic git error:

- When `DIST_BRANCH` contains a `/` (e.g. `dist/treemap`): check whether the
  first segment exists as a bare branch (`git ls-remote --exit-code
  origin refs/heads/dist`). If so, abort:
  `ERROR: cannot create 'dist/treemap' — a bare 'dist' branch exists (git
  dir/file conflict). Rename it (e.g. 'dist/react') or delete it first.`
- When `DIST_BRANCH` is a bare name (e.g. `dist`): check whether any
  `refs/heads/<name>/*` exists and abort symmetrically.

### 2. Document the convention

In the README / workflow docs: recommend `dist/<pkg>` for repos that build more
than one dist branch; note the D/F rule and that a legacy bare `dist` must be
renamed (its old SHA pins keep resolving — SHAs are immutable, and nobody pins
the branch name). Single-target repos keep the `dist` default.

### 3. Optional convenience: derive `dist/<pkg>`

So multi-target callers don't hand-write the branch per package, add a
`dist_prefix` input (default empty):

- When `dist_prefix` is set **and** `dist_branch` is unset, the branch becomes
  `<dist_prefix>/<basename>`, where `<basename>` is the package name's last
  segment (`@rdub/treemap` → `treemap`) — falling back to `basename(package_dir)`
  when the name is unavailable.
- When both are set, `dist_branch` wins (explicit override).
- Default stays `dist` when neither is set. **No behavior change unless
  `dist_prefix` is opted into.**

`dist_prefix: dist` then yields `dist/treemap` from
`package_dir: packages/treemap` with no hard-coded branch name.

## Non-goals

- No change to the default branch (`dist`), for the back-compat reason above.
- No change to how consumers pin (still resolved SHAs).

## Consumer note (disk-tree side, already done)

disk-tree's `build-dist.yml` sets `dist_branch: dist/treemap` explicitly (so it
needs only asks #1–2, not #3), and renames its legacy `dist` branch → `dist/react`
to clear the D/F conflict. If #3 lands, disk-tree can drop the explicit
`dist_branch` for `dist_prefix: dist`.
