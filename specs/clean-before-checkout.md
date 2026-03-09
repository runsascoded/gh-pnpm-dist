# Fix: clean untracked build artifacts before dist branch checkout

## Problem

`build-dist-monorepo.sh` fails at line 87 (`git checkout "$DIST_BRANCH"`) when prior CI steps create untracked files that also exist on the dist branch.

Example: shapes CI runs `cd client && pnpm build` which creates `client/dist/*.js`. These are untracked on main but tracked on the dist branch. The checkout fails:

```
error: The following untracked working tree files would be overwritten by checkout:
    client/dist/client.d.ts
    ...
```

## Root Cause

Line 82 (`git checkout -- .`) only resets tracked files. Untracked build outputs survive. The script already handles this pattern on line 98 (`git clean -fdx -e "$TMPDIR"`) but only *after* the checkout succeeds.

## Fix

Add `git clean -fd -e "$TMPDIR"` between lines 83 and 85, before the checkout:

```bash
# Reset any build-generated changes and remove node_modules before checkout
git checkout -- . 2>/dev/null || true
git clean -fd -e "$TMPDIR" 2>/dev/null || true
rm -rf node_modules
```

`$TMPDIR` is `.tmp-npm-dist` (relative path, set on line 25), so the `-e` exclude works correctly. The packed dist content is already safely stored there.

## Affected repo

- `runsascoded/shapes` CI (`build-dist` job) — uses `pkgs` mode with `prebuilt_dir: .`
