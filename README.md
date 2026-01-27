# npm-dist

GitHub Action for building and maintaining npm package distribution branches.

## Quick Start

### Option 1: Reusable Workflow (recommended)

```yaml
# .github/workflows/build-dist.yml
name: Build dist branch
on:
  workflow_dispatch:
jobs:
  build-dist:
    permissions:
      contents: write
    uses: runsascoded/npm-dist/.github/workflows/build-dist.yml@v1
```

### Option 2: Composite Action

```yaml
# .github/workflows/build-dist.yml
name: Build dist branch
on:
  workflow_dispatch:
jobs:
  build-dist:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: runsascoded/npm-dist@v1
```

## How It Works

1. Checks out your source code at the specified ref (or repository default branch)
2. **Auto-detects package manager** from lock files (`pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`, `bun.lockb`)
3. Sets up the detected package manager and Node.js, installs dependencies
4. Runs your build command (default: `<detected-pm> run build`)
5. Creates/updates the dist branch with built artifacts at root
6. Creates merge commits linking dist to source (two parents: previous dist + source)
7. Pushes to the dist branch
8. Outputs the dist SHA and install commands (in logs and as workflow annotations)

On first run (no dist branch exists), it auto-generates `package.json` by transforming paths from source (`./dist/index.js` → `./index.js`). On subsequent runs, it preserves the dist branch's `package.json`.

## Using the dist branch

After the workflow runs, you can install the package directly from the dist branch:

```bash
pnpm add github:owner/repo#<dist-sha>
```

Or use [pnpm-dep-source] to manage switching between local, GitHub, and npm sources:

```bash
pds github <dep> dist
```

[pnpm-dep-source]: https://github.com/runsascoded/pnpm-dep-source

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `prebuilt_dir` | Path to pre-built output (skips checkout/setup/build) | `''` |
| `source_ref` | Source ref to build from | Repository default branch |
| `node_version` | Node.js version | `'20'` |
| `pnpm_version` | pnpm version (only if pnpm detected) | `'10'` |
| `build_command` | Build command to run | Auto-detect |
| `dist_branch` | Name of dist branch | `'dist'` |
| `build_dir` | Directory created by build command | `'dist'` |
| `source_dirs` | Comma-separated directories to include (e.g., `"src,types"`) | `''` |
| `extra_files` | Additional files to include (e.g., `"README.md,LICENSE"`) | `''` |
| `version_suffix` | Add `-dist.<sha>` suffix to version | `'true'` |
| `pkg_include` | package.json fields to include from source | (see below) |
| `pkg_exclude` | package.json fields to exclude | `''` |
| `pkg_kvs` | JSON object of package.json overrides | `''` |

Default `pkg_include` fields: `name,description,keywords,repository,author,license,homepage,bugs,exports`

### `prebuilt_dir` mode

For non-JS builds (Rust/WASM, Go, etc.) where you handle the build yourself, use `prebuilt_dir` to skip all setup and just manage the dist branch:

```yaml
# Rust/WASM example
steps:
  - uses: actions/checkout@v4
    with:
      fetch-depth: 0
  - uses: Swatinem/rust-cache@v2
  - uses: jetli/wasm-pack-action@v0.4.0
  - run: wasm-pack build --target web
  - uses: runsascoded/npm-dist@v1
    with:
      prebuilt_dir: pkg
```

When `prebuilt_dir` is set, npm-dist skips checkout, Node.js setup, dependency installation, and build command—it only manages the git operations for the dist branch.

### `source_dirs` mode

For packages that don't use a `dist/` output folder (e.g., pure ESM packages with generated types), use `source_dirs` to specify which directories to include:

```yaml
- uses: runsascoded/npm-dist@v1
  with:
    source_ref: master
    build_command: pnpm run build:types
    source_dirs: src,types
```

This preserves the specified directories as-is instead of moving `dist/*` to root.

## Used By

- [use-url-params] ([workflow][use-url-params-workflow])
- [use-hotkeys] ([workflow][use-hotkeys-workflow])
- [og-lambda] ([workflow][og-lambda-workflow])
- [hyparquet] ([workflow][hyparquet-workflow]) - uses `source_dirs` mode
- [shapes] ([workflow][shapes-workflow]) - Rust/WASM, uses `prebuilt_dir` mode

## See Also

- [npm-dist (GitLab)] - GitLab CI version of this tool
- [pnpm-release] - Sibling action for npm publishing and GitHub releases

[npm-dist (GitLab)]: https://gitlab.com/runsascoded/js/npm-dist
[use-url-params]: https://github.com/runsascoded/use-url-params
[use-url-params-workflow]: https://github.com/runsascoded/use-url-params/blob/main/.github/workflows/build-dist.yml
[use-hotkeys]: https://github.com/runsascoded/use-hotkeys
[use-hotkeys-workflow]: https://github.com/runsascoded/use-hotkeys/blob/main/.github/workflows/build-dist.yml
[og-lambda]: https://github.com/runsascoded/og-lambda
[og-lambda-workflow]: https://github.com/runsascoded/og-lambda/blob/main/.github/workflows/build-dist.yml
[hyparquet]: https://github.com/runsascoded/hyparquet
[hyparquet-workflow]: https://github.com/runsascoded/hyparquet/blob/master/.github/workflows/build-dist.yml
[shapes]: https://github.com/runsascoded/shapes
[shapes-workflow]: https://github.com/runsascoded/shapes/blob/main/.github/workflows/ci.yml
[pnpm-release]: https://github.com/runsascoded/pnpm-release

## License

MIT
