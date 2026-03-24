# Rewrite `exports` map for dist branches

## Problem
When a library has an `exports` map pointing to source files (`./lib/*`, `./src/*`), those files don't exist on the dist branch (which only ships built `dist/` output). Consumers using the dist branch via `pds gh <name>` get broken imports.

Example — plotly.js source `package.json`:
```json
{
  "exports": {
    ".": "./lib/index.js",
    "./basic": "./lib/index-basic.js",
    "./lib/*": "./lib/*",
    "./dist/*": "./dist/*"
  }
}
```

On the dist branch, `lib/` doesn't exist. `import('plotly.js/basic')` fails.

## Solution
After copying `package.json` to the dist branch, rewrite `exports` entries that reference missing files/dirs to point at `dist/` equivalents.

### Heuristic
For each export entry:
1. If the target file/dir exists on the dist branch → keep as-is
2. If not, and a plausible `dist/` equivalent exists → rewrite
3. If no equivalent found → remove the entry (with a warning)

### Mapping rules
- `"./lib/index.js"` → `"./dist/<pkg-name>.min.js"` (or `"./dist/<pkg-name>.js"`)
- `"./lib/index-<variant>.js"` → `"./dist/<pkg-name>-<variant>.min.js"`
- `"./lib/<name>.js"` → `"./dist/<name>.min.js"` (fallback: `"./dist/<name>.js"`)
- `"./src/*"` → remove (source not shipped)
- `"./lib/*"` → remove (source not shipped)
- `"./dist/*"` → keep

Also rewrite `main` field if it points to a missing file.

### Configuration
New optional input: `rewrite_exports` (default: `true`)
- `true`: auto-rewrite missing exports
- `false`: copy exports as-is (current behavior)
- A JSON mapping for explicit overrides

### Example output
For plotly.js dist branch:
```json
{
  "main": "./dist/plotly.min.js",
  "exports": {
    ".": "./dist/plotly.min.js",
    "./basic": "./dist/plotly-basic.min.js",
    "./cartesian": "./dist/plotly-cartesian.min.js",
    "./dist/*": "./dist/*"
  }
}
```

## Interaction with `pds`
This makes `pds [l|g] <dep>` seamless: consumers always `import('plotly.js/basic')`, and it resolves to:
- Local: `./lib/index-basic.js` (CJS source, Vite pre-bundles it)
- GH dist: `./dist/plotly-basic.min.js` (UMD bundle, works directly)

The `pds` Vite plugin may still need to handle `optimizeDeps` for CJS source imports in local mode, but the import paths stay the same.

## Scope
This benefits any library that:
- Has an `exports` map with clean subpath imports (`./basic`, `./core`, etc.)
- Builds to `dist/` bundles with predictable names
- Uses `npm-dist` for dist branch management

Not just plotly.js — any multi-bundle library (e.g. `d3`, icon packs, etc.).
