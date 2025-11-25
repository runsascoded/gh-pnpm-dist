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
      - uses: runsascoded/gh-pnpm-dist@main
        with:
          source_ref: ${{ inputs.source_ref }}
```

## Initial Setup

1. **Build your project locally** and verify output in `dist/`

2. **Create and setup the dist branch**:
```bash
git checkout --orphan dist
git rm -rf .
# Copy built files to root
mv dist/* .
rmdir dist

# Create package.json with ADJUSTED PATHS
cat > package.json << 'EOF'
{
  "name": "@scope/package",
  "version": "1.0.0",
  "main": "./index.cjs",
  "module": "./index.js",
  "types": "./index.d.ts",
  "exports": {
    ".": {
      "types": "./index.d.ts",
      "import": "./index.js",
      "require": "./index.cjs"
    }
  }
}
EOF

git add -A
git commit -m "Initial dist build"
git push origin dist
```

3. **Add the workflow** (see Quick Start above)

4. **Test it**: Run the workflow manually from GitHub Actions tab

## What It Does

- Checks out your source code at the specified ref
- Sets up pnpm and Node.js
- Installs dependencies and runs your build command
- Commits build artifacts to dist branch with merge commits
- Preserves dist branch's `package.json` (does not auto-generate)
- Pushes to the dist branch

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `source_ref` | Source ref to build from | `'main'` |
| `node_version` | Node.js version | `'20'` |
| `pnpm_version` | pnpm version | `'10'` |
| `build_command` | Build command to run | `'pnpm run build'` |
| `dist_branch` | Name of dist branch | `'dist'` |

## License

MIT
