# gh-pnpm-dist

Reusable GitHub Actions workflow for building and maintaining npm package distribution branches.

## Overview

This repo provides a reusable GitHub Actions workflow that automates building npm packages and maintaining a separate `dist` branch containing the compiled artifacts. This pattern is useful for:

- Publishing pre-built packages directly from GitHub (e.g., via `github:user/repo#dist`)
- Avoiding the need to commit build artifacts to the main branch
- Maintaining a clean separation between source and built code

## Architecture

### Key Components

1. **Composite Action** (`action.yml`)
   - Single-file action that other repos can call via `uses: runsascoded/gh-pnpm-dist@main`
   - Handles checkout, setup, build, commit, and push to dist branch
   - Configurable: node version, pnpm version, build command, dist branch name
   - Build script inlined in the action (no separate script file needed)

### Dist Branch Pattern

The dist branch:
- Contains **built artifacts** at the root (e.g., `index.js`, `index.cjs`, `index.d.ts`)
- Maintains its own `package.json` with **adjusted paths** (`./index.js` not `./dist/index.js`)
- Has a **parallel lineage** with occasional merges from main
- Can receive **direct commits** when metadata needs updating

Example commit structure:
```
main:  A --- B --- C --- D
                \       \
dist:            X --- Y --- Z
```

Where X, Y, Z are merge commits with two parents:
1. Previous dist commit (or orphan for first commit)
2. Source commit from main

### Package.json Management

**Important**: The script does NOT auto-generate `package.json` for the dist branch. Initial setup requires:

1. Manually create dist branch with correct `package.json`:
   ```json
   {
     "name": "@scope/package",
     "version": "1.0.0",
     "main": "./index.cjs",      // NOT ./dist/index.cjs
     "module": "./index.js",     // NOT ./dist/index.js
     "types": "./index.d.ts",    // NOT ./dist/index.d.ts
     "exports": {
       ".": {
         "types": "./index.d.ts",
         "import": "./index.js",
         "require": "./index.cjs"
       }
     }
   }
   ```

2. Subsequent builds preserve this `package.json`
3. Update `package.json` directly on dist branch when needed

## Usage

```yaml
# .github/workflows/build-dist.yml
name: Build dist branch

on:
  workflow_dispatch:
    inputs:
      source_ref:
        description: 'Source ref to build from'
        default: 'main'

jobs:
  build-dist:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: runsascoded/gh-pnpm-dist@main
        with:
          source_ref: ${{ inputs.source_ref }}
```

### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `source_ref` | Source ref to build from (commit SHA, branch, or tag) | `'main'` |
| `node_version` | Node.js version | `'20'` |
| `pnpm_version` | pnpm version | `'10'` |
| `build_command` | Build command to run | `'pnpm run build'` |
| `dist_branch` | Name of dist branch | `'dist'` |

## Implementation Tasks

### Phase 1: Core Functionality
- [x] Create composite action with inlined build script
- [x] Create initial README with usage instructions
- [x] Document initial dist branch setup process
- [ ] Test with use-url-params as the first consumer

### Phase 2: Parameterization
- [ ] Add `dist_dir` parameter (currently hardcoded to `dist/`)
- [ ] Consider `include_files` / `exclude_files` patterns
- [ ] Support other package managers (npm, yarn)?
- [ ] Add validation for required parameters

### Phase 3: Polish
- [ ] Add comprehensive error messages
- [ ] Document edge cases and troubleshooting
- [ ] Create example repos demonstrating usage

## Design Decisions

### Why preserve dist branch package.json?

The `package.json` on dist has different paths than main (`./index.js` vs `./dist/index.js`). Rather than auto-transforming paths (brittle), we:
1. Let dist branch manage its own `package.json`
2. Require manual initial setup
3. Update via direct commits to dist when needed

This makes the "parallel lineage" pattern more explicit and maintainable.

### Why inline the script in action.yml?

The build script is inlined in `action.yml` because:
1. Single-file distribution - callers just need `uses: runsascoded/gh-pnpm-dist@main`
2. No bootstrap problem - callers don't need to set up a script on their dist branch first
3. Script updates automatically available to all consumers using `@main`

### Why use merge commits?

Merge commits create explicit connections between dist builds and source commits:
- Enables `git log --graph` visualization of the relationship
- Makes it easy to see which source commit produced a dist build
- Allows dist branch to have its own commits (package.json updates)

## Related Projects

- [use-url-params](https://github.com/runsascoded/use-url-params) - First consumer of this pattern
- [npm-dist-workflow](https://github.com/conventional-actions/npm-dist-workflow) - Similar but npm-focused (if exists)

## Notes for Future Sessions

- The action currently hardcodes `dist/` as the build output directory
- Consider whether to support multiple build outputs (e.g., both ESM and CJS in separate dirs)
- Investigate if GitHub's artifact retention could be used instead of dist branches
- Consider adding support for `package.json` path transformation as an option
