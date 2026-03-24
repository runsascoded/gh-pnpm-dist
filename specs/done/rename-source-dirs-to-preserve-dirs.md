# Rename `source_dirs` → `preserve_dirs`

## Problem

`source_dirs` is confusing — it sounds like "directories containing source code", but it actually means "directories to preserve as-is on the dist branch (instead of flattening to root)". These are typically build output directories like `dist/`, not source directories.

## Change

1. Add `preserve_dirs` input as the new name, same behavior as `source_dirs`
2. Keep `source_dirs` as a deprecated alias
3. When `source_dirs` is used (and `preserve_dirs` is not), log a deprecation warning to the GitHub Actions job summary:
   ```
   ⚠️ `source_dirs` is deprecated, use `preserve_dirs` instead.
   ```
4. If both are set, `preserve_dirs` takes precedence and a warning is logged

## Implementation

In `action.yml`:
```yaml
inputs:
  preserve_dirs:
    description: 'Comma-separated list of directories to preserve as-is on the dist branch (e.g., "dist,types"). By default, build output is flattened to the root.'
    required: false
    default: ''
  source_dirs:
    description: 'Deprecated: use preserve_dirs instead.'
    required: false
    default: ''
```

In `build-dist.sh`, resolve the effective value:
```bash
PRESERVE_DIRS="${PRESERVE_DIRS:-}"
if [ -z "$PRESERVE_DIRS" ] && [ -n "$SOURCE_DIRS" ]; then
    PRESERVE_DIRS="$SOURCE_DIRS"
    echo "::warning::source_dirs is deprecated, use preserve_dirs instead"
    echo "⚠️ \`source_dirs\` is deprecated, use \`preserve_dirs\` instead." >> "$GITHUB_STEP_SUMMARY"
fi
```

Then replace all internal uses of `SOURCE_DIRS` with `PRESERVE_DIRS`.
