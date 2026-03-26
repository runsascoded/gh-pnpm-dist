# Force checkout when switching to dist branch

## Problem

`build-dist.sh` line 94 does `git checkout "$DIST_BRANCH"` without `-f`. If the build step produces untracked files that exist on the dist branch (e.g. `build/plotcss.js`), the checkout fails:

```
error: The following untracked working tree files would be overwritten by checkout:
	build/plotcss.js
Please move or remove them before you switch branches.
Aborting
```

## Fix

Change line 94 from `git checkout "$DIST_BRANCH"` to `git checkout -f "$DIST_BRANCH"`.

Safe because build output is already saved to `$TMPDIR` before the checkout.
