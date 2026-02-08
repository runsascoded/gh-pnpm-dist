#!/usr/bin/env bash
set -e

# Monorepo mode: pack specified packages and create dist branch with structure preserved

SOURCE_SHA="${1:-$(git rev-parse HEAD)}"
DIST_BRANCH="${DIST_BRANCH:-dist}"
PKGS="${PKGS:-}"
VERSION_SUFFIX="${VERSION_SUFFIX:-true}"

if [ -z "$PKGS" ]; then
  echo "ERROR: PKGS must be set for monorepo mode"
  exit 1
fi

# Normalize: convert newlines to commas, strip empty entries and whitespace
PKGS=$(echo "$PKGS" | tr '\n' ',' | sed 's/,,*/,/g; s/^,//; s/,$//')

echo "Building $DIST_BRANCH from source commit: $SOURCE_SHA"
echo "Packages: $PKGS"

SHORT_SHA="${SOURCE_SHA:0:7}"

# Use local .tmp directory for staging files across branch switch
TMPDIR=".tmp-npm-dist"
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR/dist-content"

# Pack each package
IFS=',' read -ra PKG_PATHS <<< "$PKGS"
for pkg_path in "${PKG_PATHS[@]}"; do
  pkg_path=$(echo "$pkg_path" | xargs)  # trim whitespace
  if [ ! -d "$pkg_path" ]; then
    echo "ERROR: Package directory not found: $pkg_path"
    exit 1
  fi

  echo "Packing $pkg_path..."
  cd "$pkg_path"
  pnpm pack
  cd - > /dev/null

  # Find the tarball (most recent .tgz file)
  tarball=$(ls -t "$pkg_path"/*.tgz 2>/dev/null | head -1)
  if [ -z "$tarball" ]; then
    echo "ERROR: No tarball created for $pkg_path"
    exit 1
  fi

  # Extract to dist-content preserving path structure
  mkdir -p "$TMPDIR/dist-content/$pkg_path"
  tar -xzf "$tarball" -C "$TMPDIR/dist-content/$pkg_path" --strip-components=1

  # Update version suffix if enabled
  if [ "$VERSION_SUFFIX" = "true" ]; then
    pkg_json="$TMPDIR/dist-content/$pkg_path/package.json"
    if [ -f "$pkg_json" ]; then
      pkg_version=$(jq -r .version "$pkg_json")
      dist_version="${pkg_version}-dist.${SHORT_SHA}"
      jq --arg v "$dist_version" '.version = $v' "$pkg_json" > "$pkg_json.tmp"
      mv "$pkg_json.tmp" "$pkg_json"
      echo "  Version: $dist_version"
    fi
  fi

  # Clean up tarball
  rm -f "$tarball"
done

# Create root package.json for the dist branch
repo_name=$(jq -r .name package.json 2>/dev/null || echo "monorepo")
cat > "$TMPDIR/dist-content/package.json" << EOF
{
  "name": "${repo_name}-dist",
  "private": true,
  "description": "Dist branch with resolved dependencies",
  "repository": $(jq .repository package.json 2>/dev/null || echo '{}')
}
EOF

# Reset any build-generated changes and remove node_modules before checkout
git checkout -- . 2>/dev/null || true
rm -rf node_modules

# Fetch dist branch if it exists
if git fetch origin "$DIST_BRANCH:$DIST_BRANCH" 2>/dev/null; then
  git checkout "$DIST_BRANCH"
else
  git checkout --orphan "$DIST_BRANCH"
fi

# Configure git
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# Remove everything (preserve our tmpdir)
git rm -rf . 2>/dev/null || true
git clean -fdx -e "$TMPDIR"

# Copy dist content to root
cp -r "$TMPDIR/dist-content"/* .

# Clean up tmpdir
rm -rf "$TMPDIR"

# Stage all changes
git add -A

# Get first package info for commit message
first_pkg=$(echo "$PKGS" | cut -d',' -f1 | xargs)
PKG_NAME=$(jq -r .name "$first_pkg/package.json" 2>/dev/null || echo "monorepo")

# Create commit with proper parent(s)
TREE=$(git write-tree)

COMMIT_MSG="dist: ${PKG_NAME} and $(echo "$PKGS" | tr ',' '\n' | wc -l | xargs) packages

Built from ${SOURCE_SHA}"

if DIST_PARENT=$(git rev-parse --verify HEAD 2>/dev/null); then
  COMMIT=$(git commit-tree "$TREE" -p "$DIST_PARENT" -p "$SOURCE_SHA" -m "$COMMIT_MSG")
else
  COMMIT=$(git commit-tree "$TREE" -p "$SOURCE_SHA" -m "$COMMIT_MSG")
fi

git reset --hard "$COMMIT"

echo "$DIST_BRANCH branch built successfully"
