# Plan 002: Restore spreadsheet workflow coverage for shared-engine changes

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update this plan's status row in
> `plans/README.md` unless a reviewer told you they maintain the index.
>
> **Drift check (run first)**:
> `rtk git diff --stat 31afb08..HEAD -- .github/workflows/spreadsheet-demo-build.yml .github/workflows/spreadsheet-cloudflare-pages.yml examples/typed_spreadsheet_rabbita_demo/moon.mod examples/typed_spreadsheet_incr_tea_demo/moon.mod`
> If any workflow or manifest file listed by this command changed since this
> plan was written, compare the current-state excerpts with the live files. On
> a mismatch, stop and report.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `31afb08`, 2026-07-13

## Why this matters

The two dedicated spreadsheet workflows watch a directory that no longer
exists. Both built demos import `examples/typed_spreadsheet`, so a change to the
shared spreadsheet engine can currently miss the dedicated browser/build check
on pull requests and fail to trigger a new Cloudflare Pages deployment on
`main`. Correcting the filters restores the validation and deployment boundary
without changing application behavior.

## Current state

- `.github/workflows/spreadsheet-demo-build.yml` — PR-only demo build and DOM
  verification workflow.
- `.github/workflows/spreadsheet-cloudflare-pages.yml` — push-to-main build and
  deploy workflow for the Rabbita site.
- `examples/typed_spreadsheet_rabbita_demo/moon.mod` and
  `examples/typed_spreadsheet_incr_tea_demo/moon.mod` — evidence that both
  checked demos depend directly on the shared spreadsheet module.

Current stale filters:

```yaml
# .github/workflows/spreadsheet-demo-build.yml:15
- 'incr/typed_spreadsheet/**'

# .github/workflows/spreadsheet-cloudflare-pages.yml:14
- 'incr/typed_spreadsheet/**'
```

The actual dependency paths are:

```toml
# examples/typed_spreadsheet_rabbita_demo/moon.mod:11
"examples/typed_spreadsheet@0.1.0",

# examples/typed_spreadsheet_incr_tea_demo/moon.mod:12
"examples/typed_spreadsheet@0.1.0",
```

Repository convention: workflows use explicit `paths` filters and the shared
workspace boundary is checked by `scripts/check-workspace-boundaries.sh`.
Match the existing single-quoted glob style and keep the two workflows aligned.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Locate filters | `rtk rg -n "incr/typed_spreadsheet|examples/typed_spreadsheet" .github/workflows/spreadsheet-*.yml` | only live `examples/typed_spreadsheet/**` filters remain after the edit |
| Workflow syntax | `rtk actionlint .github/workflows/*.yml` | exit 0; no workflow syntax or expression errors |
| Diff hygiene | `rtk git diff --check` | exit 0, no whitespace errors |
| Boundary self-test | `rtk bash scripts/check-workspace-boundaries-selftest.sh` | all fixture checks print `selftest ok`; exit 0 |
| Boundary check | `rtk bash scripts/check-workspace-boundaries.sh` | exit 0, no `FAIL` or `MISSING` output |
| Shared module | `rtk moon check examples/typed_spreadsheet` | exit 0, no errors |
| Rabbita demo | `rtk moon check --target js examples/typed_spreadsheet_rabbita_demo` | exit 0, no errors |
| incr_tea demo | `rtk moon check --target js examples/typed_spreadsheet_incr_tea_demo` | exit 0, no errors |

## Scope

**In scope** (the only files to modify):

- `.github/workflows/spreadsheet-demo-build.yml`
- `.github/workflows/spreadsheet-cloudflare-pages.yml`
- `plans/README.md` (status row only)

**Out of scope**:

- Workflow action versions, installer choice, permissions, and secrets; those
  belong to `plans/006-ci-supply-chain-bootstrap.md`.
- Demo source, manifests, package-lock files, and deployment configuration.
- Adding new workflow jobs or changing which site is deployed.

## Git workflow

- Branch: `advisor/002-spreadsheet-workflow-paths`
- One conventional commit: `fix(ci): restore spreadsheet workflow path coverage`
- Do not push or open a PR unless instructed by the operator.

## Steps

### Step 1: Replace both dead dependency globs

In both in-scope workflows, replace exactly
`'incr/typed_spreadsheet/**'` with `'examples/typed_spreadsheet/**'`.
Keep the existing filters for the demos, core `incr`, manifests, and workflow
files unchanged. Do not broaden either workflow to all of `examples/**`.

**Verify**:
`rtk rg -n "incr/typed_spreadsheet|examples/typed_spreadsheet" .github/workflows/spreadsheet-*.yml`
→ exactly two live shared-module filter matches, both
`examples/typed_spreadsheet/**`; zero `incr/typed_spreadsheet` matches.

### Step 2: Confirm the filters match the dependency graph

Read the two demo `moon.mod` files and confirm that the PR workflow covers both
consumers and the deploy workflow covers the deployed Rabbita consumer. Do not
add the incr_tea demo to the deployment workflow: it is validated by the PR
workflow but is not the site deployed by this workflow.

**Verify**:
`rtk rg -n 'examples/typed_spreadsheet@' examples/typed_spreadsheet_rabbita_demo/moon.mod examples/typed_spreadsheet_incr_tea_demo/moon.mod`
→ one dependency match in each manifest.

### Step 3: Run repository boundary and targeted checks

Run `actionlint` before the boundary checks so the edited workflow files are
validated as GitHub Actions configuration, not only as text.
Run the boundary self-test before the real checker, then type-check the shared
module and its two browser consumers.

**Verify**:

- `rtk actionlint .github/workflows/*.yml` → exit 0; no workflow syntax or expression errors.
- `rtk bash scripts/check-workspace-boundaries-selftest.sh` → exit 0.
- `rtk bash scripts/check-workspace-boundaries.sh` → exit 0.
- `rtk moon check examples/typed_spreadsheet` → exit 0.
- `rtk moon check --target js examples/typed_spreadsheet_rabbita_demo` → exit 0.
- `rtk moon check --target js examples/typed_spreadsheet_incr_tea_demo` → exit 0.

## Test plan

This is a trigger-configuration correction; no MoonBit behavior test is needed.
The regression is pinned by the exact-path search in the done criteria, while
the existing workflow jobs remain the behavioral checks once GitHub evaluates
the corrected filters. Review the PR's changed-files list with a change under
`examples/typed_spreadsheet/**` and confirm the `Spreadsheet demo build` check
is selected by GitHub before merging.

## Done criteria

- [ ] Both workflows contain `'examples/typed_spreadsheet/**'`.
- [ ] `rtk rg -n 'incr/typed_spreadsheet' .github/workflows` returns no matches.
- [ ] Boundary self-test and boundary check exit 0.
- [ ] All three targeted `moon check` commands exit 0.
- [ ] `rtk git diff --check` exits 0.
- [ ] `rtk actionlint .github/workflows/*.yml` exits 0.
- [ ] Only the two in-scope workflow files and `plans/README.md` are modified.
- [ ] The status row for plan 002 is updated in `plans/README.md`.

## STOP conditions

Stop and report if:

- Either demo no longer imports `examples/typed_spreadsheet`.
- GitHub's paths-filter semantics require a broader change than replacing the
  two exact globs.
- The deployed site has changed away from the Rabbita demo.
- A verification failure indicates an existing workspace problem unrelated to
  these two filters; do not fix unrelated source or manifests in this plan.

## Maintenance notes

- Future workspace moves must update dependency manifests and workflow filters
  atomically.
- Reviewers should verify both PR-check selection and push-to-main deploy
  selection, not just YAML syntax.
- Supply-chain hardening and workflow bootstrap consolidation are intentionally
  deferred to plan 006.

