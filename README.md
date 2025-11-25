# gh-pnpm-dist

Reusable GitHub Actions workflow for building and maintaining npm package distribution branches.

## Quick Start

```yaml
# .github/workflows/build-dist.yml in your repo
name: Build dist branch
on:
  workflow_dispatch:
    inputs:
      source_ref:
        description: 'Source ref to build from'
        default: 'main'

jobs:
  build-dist:
    uses: runsascoded/gh-pnpm-dist/.github/workflows/build-dist.yml@main
    with:
      source_ref: ${{ inputs.source_ref }}
      pnpm_version: '10'
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

- Checks out your source code
- Runs your build command (`pnpm run build`)
- Fetches the build script from the dist branch
- Commits build artifacts to dist branch with merge commits
- Preserves dist branch's package.json (does not auto-generate)

## License

MIT
