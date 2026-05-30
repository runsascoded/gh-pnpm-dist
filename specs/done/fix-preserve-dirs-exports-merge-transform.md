# Fix `preserve_dirs` exports corruption in the merge branch

## Problem

When `preserve_dirs` is set, the **first** dist build produces a correct
`package.json`, but **every subsequent rebuild** corrupts the `exports` map.

Concretely, a source `package.json` with:

```json
"exports": { "./dist/*": "./dist/*" }
```

ends up on the dist branch as:

```json
"exports": { "./dist/*": "./*" }
```

The key (`"./dist/*"`) is preserved but the value is rewritten to `"./*"`,
which points at the package root. Since `preserve_dirs: dist` keeps the
bundles under `dist/` (not flattened to root), `plotly.js/dist/basic.js`
resolves to `./basic.js` (nonexistent) → 404 for any consumer that imports a
`./dist/*` subpath.

### Discovery

Found while auditing consumers of the `runsascoded/plotly.js` fork (built via
this action with `preserve_dirs: dist,lib,src,...`). The fork's `main`
`package.json` correctly has `"./dist/*": "./dist/*"`; only the generated
`dist` branch is corrupted. None of the 7 downstream consumers could use the
`./dist/*` entry — they all fall back to `lib/index-*.js` subpaths (whose
mappings survive because their values contain no `./dist/` prefix).

## Root cause

`scripts/build-dist.sh` has two code paths for producing the dist
`package.json`:

- **First-run branch** (no existing `package.json.dist`, ~lines 187–208):
  correctly gates on `PRESERVE_DIRS` — when set, it does
  `del(.files, .scripts, .devDependencies)` with **no path transformation**.
- **Merge branch** (existing `package.json.dist`, ~lines 162–186): runs on
  every rebuild once the dist branch exists. It **unconditionally** applies
  `transform_paths` to every merged source field, including `exports`:

  ```jq
  def transform_paths:
    walk(
      if type == "string" then
        gsub("\\./\($build_dir)/"; "./") | gsub("\($build_dir)/"; "./")
      else . end
    );
  ```

  `walk` visits object **values** (not keys), so for
  `{ "./dist/*": "./dist/*" }` it rewrites the value `"./dist/*"` → `"./*"`
  while leaving the key untouched. With `$build_dir = "dist"`, that's exactly
  the corruption above.

The merge branch never checks `PRESERVE_DIRS`, so it flattens `./dist/` paths
even though preserve mode is keeping those directories intact.

## Fix

Gate `transform_paths` in the merge branch on `PRESERVE_DIRS`, mirroring the
first-run branch: when `preserve_dirs` is set, no flattening happens, so the
transform must be a no-op.

Implemented by extracting the merge `jq` into a sourceable function in
`scripts/merge-dist-package.sh` (mirrors the `find-dist-parent.sh` pattern,
so tests can exercise the real code without jq drift). The function takes
`<dist_json> <source_json> <build_dir> <fields_csv> <preserve_dirs>` and
makes `transform_paths` identity when `$preserve` is non-empty:

```bash
def transform_paths:
  if ($preserve | length) > 0 then .
  else
    walk(
      if type == "string" then
        gsub("\\./\($build_dir)/"; "./") | gsub("\($build_dir)/"; "./")
      else . end
    )
  end;
```

`build-dist.sh` sources the function and replaces the inline jq block with a
single call. Applied to both gh (passes `$PRESERVE_DIRS`) and gl (passes
`$SOURCE_DIRS` — gl hasn't been renamed yet). `dist.gitlab-ci.yml` now also
downloads `merge-dist-package.sh` alongside the other scripts.

## Acceptance criteria

1. With `preserve_dirs` set, a **rebuild** (where `package.json.dist` already
   exists on the dist branch) preserves `"./dist/*": "./dist/*"` verbatim —
   byte-identical to the first-run output for the same source.
2. Without `preserve_dirs` (default flatten mode), the merge branch still
   flattens `./dist/...` → `./...` as before (no regression).
3. The existing exports-validation step (build-dist.sh ~lines 286–315) is
   unaffected.

## Test

Implemented as `tests/test-merge-dist-package.sh` in both gh and gl. Sources
`scripts/merge-dist-package.sh` and exercises 7 scenarios via fixture JSON
files against the extracted function:

1. preserve mode keeps `./dist/*` exports verbatim (the bug)
2. default flatten `./dist/foo` → `./foo` in exports values (no regression)
3. default flatten rewrites `main`
4. preserve keeps `main` as `./dist/index.js`
5. fields not in include-list are kept from dist as-is
6. missing source field: dist value retained
7. any non-empty preserve_dirs value disables flattening

A full end-to-end build test would be much heavier (requires mocking git
state, `git fetch`/`git checkout` round-trips) and tests the same logic that
the unit test covers; punted unless real-world repros surface gaps.

## Downstream impact

After this lands, bump the dist branch of `runsascoded/plotly.js` (re-run its
`build-dist` workflow). Its 7 known consumers can then optionally import the
pre-built `plotly.js/dist/basic.js` bundles via `pds gh` instead of only the
`lib/index-*.js` src-mode entries. No consumer change is required for those
already on `lib/*` subpaths — this only repairs the broken `./dist/*` entry.
