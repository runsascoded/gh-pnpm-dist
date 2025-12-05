#!/usr/bin/env bash
set -e

SOURCE_SHA="${1:-$(git rev-parse HEAD)}"
DIST_BRANCH="${DIST_BRANCH:-dist}"
BUILD_DIR="${BUILD_DIR:-dist}"
SOURCE_DIRS="${SOURCE_DIRS:-}"

echo "Building $DIST_BRANCH from source commit: $SOURCE_SHA"

# Save source package.json before switching branches (for initial setup)
cp package.json package.json.source

# Save build output dir to /tmp before checkout (git clean would remove it)
if [ -d "$BUILD_DIR" ]; then
  cp -r "$BUILD_DIR" /tmp/build-output
fi

# If SOURCE_DIRS is set, save those directories
if [ -n "$SOURCE_DIRS" ]; then
  mkdir -p /tmp/source-dirs
  IFS=',' read -ra DIRS <<< "$SOURCE_DIRS"
  for dir in "${DIRS[@]}"; do
    dir=$(echo "$dir" | xargs)  # trim whitespace
    if [ -d "$dir" ]; then
      cp -r "$dir" /tmp/source-dirs/
    fi
  done
fi

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

# Remove everything
git rm -rf . 2>/dev/null || true
git clean -fdx -e package.json.dist -e package.json.source

if [ -n "$SOURCE_DIRS" ]; then
  # SOURCE_DIRS mode: restore saved directories
  cp -r /tmp/source-dirs/* .
else
  # Default mode: restore build output from /tmp and move contents to root
  if [ -d /tmp/build-output ]; then
    cp -r /tmp/build-output/* .
    rm -rf /tmp/build-output
  else
    echo "ERROR: No $BUILD_DIR/ directory found"
    exit 1
  fi
fi

# Restore or create package.json
if [ -f package.json.dist ]; then
  # Use existing dist branch package.json
  mv package.json.dist package.json
  rm -f package.json.source
elif [ -f package.json.source ]; then
  # First run: transform source package.json for dist branch
  echo "Creating initial package.json for $DIST_BRANCH branch..."
  if [ -n "$SOURCE_DIRS" ]; then
    # SOURCE_DIRS mode: just remove dev fields, no path transformation
    jq 'del(.files, .scripts, .devDependencies)' package.json.source > package.json
  else
    # Default mode: remove dev fields and transform build_dir paths
    jq --arg build_dir "$BUILD_DIR" '
      # Remove fields not needed on dist branch
      del(.files, .scripts, .devDependencies) |
      # Transform paths: ./$build_dir/... -> ./...
      walk(
        if type == "string" then
          gsub("\\./\($build_dir)/"; "./") | gsub("\($build_dir)/"; "./")
        else
          .
        end
      )
    ' package.json.source > package.json
  fi
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
