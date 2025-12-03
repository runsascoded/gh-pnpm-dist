# gh-pnpm-dist

GitHub Action for building and maintaining npm package distribution branches.

## Quick Start

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
      - uses: runsascoded/gh-pnpm-dist@v1
        with:
          source_ref: ${{ inputs.source_ref }}
```

## How It Works

1. Checks out your source code at the specified ref
2. Sets up pnpm and Node.js, installs dependencies
3. Runs your build command (default: `pnpm run build`)
4. Creates/updates the dist branch with built artifacts at root
5. Creates merge commits linking dist to source (two parents: previous dist + source)
6. Pushes to the dist branch

On first run (no dist branch exists), it auto-generates `package.json` by transforming paths from source (`./dist/index.js` → `./index.js`). On subsequent runs, it preserves the dist branch's `package.json`.

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `source_ref` | Source ref to build from | `'main'` |
| `node_version` | Node.js version | `'20'` |
| `pnpm_version` | pnpm version | `'10'` |
| `build_command` | Build command to run | `'pnpm run build'` |
| `dist_branch` | Name of dist branch | `'dist'` |
| `source_dirs` | Comma-separated directories to include (e.g., `"src,types"`) | `''` |

### `source_dirs` mode

For packages that don't use a `dist/` output folder (e.g., pure ESM packages with generated types), use `source_dirs` to specify which directories to include:

```yaml
- uses: runsascoded/gh-pnpm-dist@main
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

## See Also

- [gh-pnpm-release] - Sibling action for npm publishing and GitHub releases

[use-url-params]: https://github.com/runsascoded/use-url-params
[use-url-params-workflow]: https://github.com/runsascoded/use-url-params/blob/main/.github/workflows/build-dist.yml
[use-hotkeys]: https://github.com/runsascoded/use-hotkeys
[use-hotkeys-workflow]: https://github.com/runsascoded/use-hotkeys/blob/main/.github/workflows/build-dist.yml
[og-lambda]: https://github.com/runsascoded/og-lambda
[og-lambda-workflow]: https://github.com/runsascoded/og-lambda/blob/main/.github/workflows/build-dist.yml
[hyparquet]: https://github.com/runsascoded/hyparquet
[hyparquet-workflow]: https://github.com/runsascoded/hyparquet/blob/master/.github/workflows/build-dist.yml
[gh-pnpm-release]: https://github.com/runsascoded/gh-pnpm-release

## License

MIT
