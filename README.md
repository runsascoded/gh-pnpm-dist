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

- [aws-static-sso] ([usage][aws-static-sso-search]) - monorepo mode (`pkgs`)
- [hyparquet] ([npm][hyparquet-npm], [usage][hyparquet-search]) - `source_dirs` mode
- [og-lambda] ([usage][og-lambda-search])
- [pnpm-dep-source] ([npm][pnpm-dep-source-npm], [usage][pnpm-dep-source-search])
- [shapes] ([usage][shapes-search]) - Rust/WASM, `prebuilt_dir` + monorepo mode
- [slidev] ([usage][slidev-search]) - monorepo mode (`pkgs`)
- [use-kbd] ([npm][use-kbd-npm], [usage][use-kbd-search])
- [use-prms] ([npm][use-prms-npm], [usage][use-prms-search])
- [vite-plugin-dvc] ([usage][vite-plugin-dvc-search])

### GitLab Version

See [npm-dist (GitLab)] for the GitLab CI version and its consumers, e.g.:

- [npm-dist (GitLab)] - GitLab CI version of this tool
- [pnpm-release] - Sibling action for npm publishing and GitHub releases

[npm-dist (GitLab)]: https://gitlab.com/runsascoded/js/npm-dist
[aws-static-sso]: https://github.com/runsascoded/aws-static-sso
[aws-static-sso-search]: https://github.com/search?q=repo%3Arunsascoded%2Faws-static-sso+npm-dist&type=code
[hyparquet]: https://github.com/hyparam/hyparquet
[hyparquet-npm]: https://www.npmjs.com/package/hyparquet
[hyparquet-search]: https://github.com/search?q=repo%3Ahyparam%2Fhyparquet+pnpm-dist&type=code
[og-lambda]: https://github.com/runsascoded/og-lambda
[og-lambda-search]: https://github.com/search?q=repo%3Arunsascoded%2Fog-lambda+pnpm-dist&type=code
[pnpm-dep-source]: https://github.com/runsascoded/pnpm-dep-source
[pnpm-dep-source-npm]: https://www.npmjs.com/package/pnpm-dep-source
[pnpm-dep-source-search]: https://github.com/search?q=repo%3Arunsascoded%2Fpnpm-dep-source+npm-dist&type=code
[shapes]: https://github.com/runsascoded/shapes
[shapes-search]: https://github.com/search?q=repo%3Arunsascoded%2Fshapes+npm-dist&type=code
[slidev]: https://github.com/Open-Athena/slidev
[slidev-search]: https://github.com/search?q=repo%3AOpen-Athena%2Fslidev+npm-dist&type=code
[use-kbd]: https://github.com/runsascoded/use-kbd
[use-kbd-npm]: https://www.npmjs.com/package/use-kbd
[use-kbd-search]: https://github.com/search?q=repo%3Arunsascoded%2Fuse-kbd+npm-dist&type=code
[use-prms]: https://github.com/runsascoded/use-prms
[use-prms-npm]: https://www.npmjs.com/package/use-prms
[use-prms-search]: https://github.com/search?q=repo%3Arunsascoded%2Fuse-prms+npm-dist&type=code
[vite-plugin-dvc]: https://github.com/runsascoded/vite-plugin-dvc
[vite-plugin-dvc-search]: https://github.com/search?q=repo%3Arunsascoded%2Fvite-plugin-dvc+npm-dist&type=code
[pnpm-release]: https://github.com/runsascoded/pnpm-release

## License

MIT
