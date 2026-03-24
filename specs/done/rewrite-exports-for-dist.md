# Rewrite `exports` map for dist branches

## Problem

Repos keep `exports` in `package.json` pointing at source files (e.g. `./lib/index.js`) for local dev and `pds local` usage. But on the dist branch, consumers need exports pointing at built files (e.g. `./dist/plotly.min.js`). Previously the calling workflow had to manually rewrite exports with a `jq` script or hardcode them in `pkg_kvs`, which was fragile and verbose.

## Solution: `exports_map` input

Implemented Option A from the original spec. New `exports_map` input: a JSON mapping from source export values to dist export values.

### Usage

```yaml
- uses: runsascoded/npm-dist@v1
  with:
    build_command: npm run build
    source_dirs: dist
    exports_map: >-
      {
        "./lib/index.js": "./dist/plotly.min.js",
        "./lib/index-basic.js": "./dist/plotly-basic.min.js",
        "./lib/index-lite.js": "./dist/plotly-lite.min.js"
      }
```

### Behavior

1. Rewrites `main` if its value matches a key in the map
2. Rewrites each `exports` entry whose value matches a key in the map
3. Handles conditional exports objects (`{ "import": ..., "require": ... }`)
4. After rewriting, drops any exports whose targets don't exist on the dist branch:
   - File exports: dropped if the file doesn't exist
   - Glob exports (e.g. `./lib/*`): dropped if the base directory doesn't exist
5. The existing exports validation step then catches any remaining broken entries

### Example: plotly.js fork

Source `package.json`:
```json
{
  "main": "./lib/index.js",
  "exports": {
    ".": "./lib/index.js",
    "./basic": "./lib/index-basic.js",
    "./lite": "./lib/index-lite.js",
    "./lib/*": "./lib/*",
    "./src/*": "./src/*",
    "./dist/*": "./dist/*"
  }
}
```

After `exports_map` rewriting on dist branch:
```json
{
  "main": "./dist/plotly.min.js",
  "exports": {
    ".": "./dist/plotly.min.js",
    "./basic": "./dist/plotly-basic.min.js",
    "./lite": "./dist/plotly-lite.min.js",
    "./dist/*": "./dist/*"
  }
}
```

- `./lib/*` and `./src/*` dropped (directories don't exist on dist)
- Named exports remapped via the map
- `./dist/*` kept as-is

### Files changed

- `action.yml`: added `exports_map` input
- `.github/workflows/build-dist.yml`: exposed `exports_map` in reusable workflow
- `scripts/build-dist.sh`: exports rewriting logic + improved validation (now checks glob base dirs too)

