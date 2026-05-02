# Bump bundled actions to Node 24-compatible versions

`action.yml` currently pins three nested actions to versions that run on Node.js 20:

```
action.yml:75   actions/checkout@v4
action.yml:124  pnpm/action-setup@v4
action.yml:130  pnpm/action-setup@v4
action.yml:134  actions/setup-node@v4
```

GitHub deprecated Node 20 actions: forced to Node 24 starting **2026-06-02**, removed **2026-09-16**. Every workflow that uses `runsascoded/npm-dist@v1` currently surfaces an annotation like:

> Node.js 20 actions are deprecated. The following actions are running on Node.js 20 and may not work as expected: `actions/checkout@v4`, `actions/setup-node@v4`, `pnpm/action-setup@v4`.

(Observed downstream in `runsascoded/hyparquet` run [25251556245](https://github.com/runsascoded/hyparquet/actions/runs/25251556245).)

## Plan

Bump each pin to the minimum tag that ships Node 24:

| Action | Old | New | Notes |
|---|---|---|---|
| `actions/checkout` | `@v4` | `@v5` | v5.0.0 added Node 24. v6.0.2 is current latest; v5 chosen for consistency with `hyparquet`'s `ci.yml` and minimum-change rationale. |
| `actions/setup-node` | `@v4` | `@v5` | v5.0.0 added Node 24 *and* a breaking change: "Enhance caching with automatic package manager detection." Verify the `cache: ${{ steps.info.outputs.pm }}` input still behaves as expected (pm detection is already explicit, so should be fine). v6.4.0 is current latest. |
| `pnpm/action-setup` | `@v4` | `@v5` | v5.0.0 is the GitHub-marked "latest"; v6.x exists but is not yet promoted to latest. Two call sites (lines 124, 130). |

## Steps

1. Update the four `uses:` lines in `action.yml`.
2. Smoke-test by running `Build dist branch` in any consumer repo (e.g. `runsascoded/hyparquet`) — confirm the deprecation annotation is gone and the dist branch still builds correctly.
3. Move `action.yml`'s major-version tag (`v1`) forward to the new commit (this is what consumers pin).

## Out of scope

- Bumping major versions further (v6 for checkout/setup-node, v6 for action-setup) — defer until needed.
- Changing the `v1` major-tag policy itself.
