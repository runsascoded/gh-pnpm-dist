#!/usr/bin/env bash
set -e

SOURCE_SHA="${1:-$(git rev-parse HEAD)}"
DIST_BRANCH="${DIST_BRANCH:-dist}"

echo "Building $DIST_BRANCH from source commit: $SOURCE_SHA"

# Save source package.json before switching branches (for initial setup)
cp package.json package.json.source

# Remove node_modules before checkout (it would conflict)
rm -rf node_modules

# Fetch dist branch if it exists
DIST_EXISTS=false
if git fetch origin "$DIST_BRANCH:$DIST_BRANCH" 2>/dev/null; then
  git checkout "$DIST_BRANCH"
  DIST_EXISTS=true
  # Save existing package.json from dist branch
  if [ -f package.json ]; then
    cp package.json package.json.dist
  fi
else
  git checkout --orphan "$DIST_BRANCH"
fi

# Configure git
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# Remove everything except dist/
git rm -rf . 2>/dev/null || true
git clean -fdx -e dist -e package.json.dist -e package.json.source

# Move dist contents to root
mv dist/* . 2>/dev/null || true
rmdir dist 2>/dev/null || true

# Restore or create package.json
if [ -f package.json.dist ]; then
  # Use existing dist branch package.json
  mv package.json.dist package.json
  rm -f package.json.source
elif [ -f package.json.source ]; then
  # First run: transform source package.json by removing "dist/" from paths
  echo "Creating initial package.json for $DIST_BRANCH branch..."
  jq '
    walk(
      if type == "string" then
        gsub("\\./dist/"; "./") | gsub("dist/"; "./")
      else
        .
      end
    )
  ' package.json.source > package.json
  rm -f package.json.source
else
  echo "ERROR: No package.json found"
  exit 1
fi

# Stage all changes
git add -A

# Create commit with proper parent(s)
TREE=$(git write-tree)

if DIST_PARENT=$(git rev-parse --verify HEAD 2>/dev/null); then
  # dist branch exists: create merge commit with two parents
  # Parent 1: previous dist commit
  # Parent 2: source commit from main
  COMMIT=$(git commit-tree "$TREE" -p "$DIST_PARENT" -p "$SOURCE_SHA" -m "Build $DIST_BRANCH from $SOURCE_SHA")
else
  # First dist commit: single parent (source commit)
  COMMIT=$(git commit-tree "$TREE" -p "$SOURCE_SHA" -m "Initial $DIST_BRANCH build from $SOURCE_SHA")
fi

git reset --hard "$COMMIT"

echo "$DIST_BRANCH branch built successfully"
