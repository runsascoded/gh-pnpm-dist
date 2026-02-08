#!/usr/bin/env bash
set -e

SOURCE_SHA="${1:-$(git rev-parse HEAD)}"
DIST_BRANCH="${DIST_BRANCH:-dist}"
BUILD_DIR="${BUILD_DIR:-dist}"
SOURCE_DIRS="${SOURCE_DIRS:-}"
EXTRA_FILES="${EXTRA_FILES:-}"
VERSION_SUFFIX="${VERSION_SUFFIX:-true}"
PKG_INCLUDE="${PKG_INCLUDE:-}"
PKG_EXCLUDE="${PKG_EXCLUDE:-}"
PKG_KVS="${PKG_KVS:-}"

# Default fields to include from source package.json
DEFAULT_PKG_FIELDS="name,description,type,bin,main,keywords,repository,author,license,homepage,bugs,exports,dependencies,peerDependencies,optionalDependencies"

echo "Building $DIST_BRANCH from source commit: $SOURCE_SHA"

# Compute short SHA for version suffix
SHORT_SHA="${SOURCE_SHA:0:7}"

# Use local .tmp directory for staging files across branch switch
TMPDIR=".tmp-npm-dist"
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"

# Save source package.json before switching branches (for initial setup and version)
# For prebuilt mode (no root package.json), we use BUILD_DIR's package.json as-is
if [ -f package.json ]; then
  cp package.json package.json.source
  SOURCE_VERSION=$(jq -r .version package.json)
  PREBUILT_MODE=false
elif [ -f "$BUILD_DIR/package.json" ]; then
  # Prebuilt mode: caller provides complete package.json, we only add version suffix
  SOURCE_VERSION=$(jq -r .version "$BUILD_DIR/package.json")
  PREBUILT_MODE=true
else
  echo "ERROR: No package.json found in root or $BUILD_DIR"
  exit 1
fi

# Save build output dir before checkout (git clean would remove it)
if [ -d "$BUILD_DIR" ]; then
  cp -r "$BUILD_DIR" "$TMPDIR/build-output"
fi

# If SOURCE_DIRS is set, save those directories
if [ -n "$SOURCE_DIRS" ]; then
  mkdir -p "$TMPDIR/source-dirs"
  IFS=',' read -ra DIRS <<< "$SOURCE_DIRS"
  for dir in "${DIRS[@]}"; do
    dir=$(echo "$dir" | xargs)  # trim whitespace
    if [ -d "$dir" ]; then
      cp -r "$dir" "$TMPDIR/source-dirs/"
    fi
  done
fi

# If EXTRA_FILES is set, save those files (preserving directory structure)
if [ -n "$EXTRA_FILES" ]; then
  mkdir -p "$TMPDIR/extra-files"
  IFS=',' read -ra FILES <<< "$EXTRA_FILES"
  for file in "${FILES[@]}"; do
    file=$(echo "$file" | xargs)  # trim whitespace
    if [ -f "$file" ]; then
      # Preserve directory structure
      mkdir -p "$TMPDIR/extra-files/$(dirname "$file")"
      cp "$file" "$TMPDIR/extra-files/$file"
    elif [ -d "$file" ]; then
      mkdir -p "$TMPDIR/extra-files/$(dirname "$file")"
      cp -r "$file" "$TMPDIR/extra-files/$file"
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

# Remove everything (preserve our tmpdir and package.json backups)
git rm -rf . 2>/dev/null || true
git clean -fdx -e "$TMPDIR" -e package.json.dist -e package.json.source

if [ -n "$SOURCE_DIRS" ]; then
  # SOURCE_DIRS mode: restore saved directories
  cp -r "$TMPDIR/source-dirs"/* .
else
  # Default mode: restore build output and move contents to root
  if [ -d "$TMPDIR/build-output" ]; then
    cp -r "$TMPDIR/build-output"/* .
  else
    echo "ERROR: No $BUILD_DIR/ directory found"
    exit 1
  fi
fi

# Restore extra files (if any)
if [ -d "$TMPDIR/extra-files" ] && [ -n "$(ls -A "$TMPDIR/extra-files" 2>/dev/null)" ]; then
  cp -r "$TMPDIR/extra-files"/* .
fi

# Clean up tmpdir
rm -rf "$TMPDIR"

# Restore or create package.json
if [ "$PREBUILT_MODE" = "true" ]; then
  # Prebuilt mode: package.json already in build output, use as-is
  echo "Prebuilt mode: using package.json from $BUILD_DIR"
else
  # Standard mode: merge/transform package.json

  # Compute effective field list (include - exclude)
  if [ -n "$PKG_INCLUDE" ]; then
    FIELDS_TO_INCLUDE="$PKG_INCLUDE"
  else
    FIELDS_TO_INCLUDE="$DEFAULT_PKG_FIELDS"
  fi

  # Remove excluded fields
  if [ -n "$PKG_EXCLUDE" ]; then
    IFS=',' read -ra EXCLUDE_ARR <<< "$PKG_EXCLUDE"
    for exclude in "${EXCLUDE_ARR[@]}"; do
      exclude=$(echo "$exclude" | xargs)
      FIELDS_TO_INCLUDE=$(echo "$FIELDS_TO_INCLUDE" | sed "s/$exclude//g" | sed 's/,,/,/g' | sed 's/^,//' | sed 's/,$//')
    done
  fi

  echo "Fields to include from source: $FIELDS_TO_INCLUDE"

  if [ -f package.json.dist ]; then
    # Merge: use dist structure but update key fields from source
    jq -s --arg build_dir "$BUILD_DIR" --arg fields "$FIELDS_TO_INCLUDE" '
      .[0] as $dist | .[1] as $src |
      # Transform exports paths: ./$build_dir/... -> ./...
      ($src.exports // {} | walk(
        if type == "string" then
          gsub("\\./\($build_dir)/"; "./") | gsub("\($build_dir)/"; "./")
        else
          .
        end
      )) as $transformed_exports |
      # Split fields into array and build merge object
      ($fields | split(",") | map(gsub("^\\s+|\\s+$"; ""))) as $field_list |
      (reduce $field_list[] as $field ({}; . + (
        if $field == "exports" then
          {exports: $transformed_exports}
        elif $src[$field] != null then
          {($field): $src[$field]}
        else
          {}
        end
      ))) as $merge_obj |
      $dist * $merge_obj | with_entries(select(.value != null))
    ' package.json.dist package.json.source > package.json
    rm -f package.json.dist package.json.source
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
fi

# Update version with dist suffix if enabled
if [ "$VERSION_SUFFIX" = "true" ]; then
  DIST_VERSION="${SOURCE_VERSION}-dist.${SHORT_SHA}"
  echo "Setting version to $DIST_VERSION"
  jq --arg v "$DIST_VERSION" '.version = $v' package.json > package.json.tmp
  mv package.json.tmp package.json
fi

# Apply key-value overrides if specified
if [ -n "$PKG_KVS" ]; then
  echo "Applying package.json overrides: $PKG_KVS"
  jq --argjson kvs "$PKG_KVS" '. * $kvs' package.json > package.json.tmp
  mv package.json.tmp package.json
fi

# Stage all changes
git add -A

# Get package info for commit message
PKG_NAME=$(jq -r .name package.json)
PKG_VERSION=$(jq -r .version package.json)

# Create commit with proper parent(s)
TREE=$(git write-tree)

COMMIT_MSG="${PKG_NAME}@${PKG_VERSION}

Built from ${SOURCE_SHA}"

if DIST_PARENT=$(git rev-parse --verify HEAD 2>/dev/null); then
  # dist branch exists: create merge commit with two parents
  # Parent 1: previous dist commit
  # Parent 2: source commit from main
  COMMIT=$(git commit-tree "$TREE" -p "$DIST_PARENT" -p "$SOURCE_SHA" -m "$COMMIT_MSG")
else
  # First dist commit: single parent (source commit)
  COMMIT=$(git commit-tree "$TREE" -p "$SOURCE_SHA" -m "$COMMIT_MSG")
fi

git reset --hard "$COMMIT"

echo "$DIST_BRANCH branch built successfully"
