# Expose `pkgs` input in reusable workflow

## Problem

The `action.yml` supports a `pkgs` input for monorepo mode (using `pnpm pack` to resolve workspace/catalog refs, preserving directory structure on dist branch). However, the reusable workflow at `.github/workflows/build-dist.yml` doesn't expose this input, so monorepo consumers can't use the convenient `uses:` form:

```yaml
# This doesn't work for monorepos today:
build-dist:
  uses: runsascoded/npm-dist/.github/workflows/build-dist.yml@v1
  with:
    pkgs: client  # ← not available
```

They have to call the action directly instead, losing the convenience of the reusable workflow.

## Fix

Add `pkgs` to the `workflow_call` inputs in `.github/workflows/build-dist.yml` and pass it through to the action step:

```yaml
# In on.workflow_call.inputs:
pkgs:
  description: 'Monorepo mode: package paths, one per line'
  type: string
  default: ''

# In the action step's `with:`:
pkgs: ${{ inputs.pkgs }}
```

## Context

Came up while setting up https://github.com/runsascoded/aws-static-sso — a pnpm monorepo with `worker/` (CF Worker, private) and `client/` (npm-publishable as `aws-static-sso`). Only `client` needs a dist branch.
