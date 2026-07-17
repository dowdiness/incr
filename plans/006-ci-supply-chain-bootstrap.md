# Plan 006: Make CI bootstrap reproducible and pin third-party actions

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. Never copy a secret value into source, logs, the
> plan index, or a commit. When done, update this plan's status row in
> `plans/README.md` unless a reviewer told you they maintain the index.
>
> **Drift check (run first)**:
> `rtk git diff --stat 31afb08..HEAD -- .github/workflows scripts`
> If any workflow or prospective bootstrap path changed, compare the
> current-state excerpts with the live files. On a mismatch, stop and report.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/002-spreadsheet-workflow-paths.md
- **Category**: security
- **Planned at**: commit `31afb08`, 2026-07-13

## Why this matters

CI currently trusts mutable GitHub Action tags, including an action that
receives the Cloudflare deployment credential, and repeatedly downloads and
executes a mutable installer script without independent verification. The two
spreadsheet workflows also use an unpinned setup action that primary CI
explicitly rejected for reliability. This plan creates one reviewed,
version-and-integrity-pinned MoonBit bootstrap and pins every third-party action
to an immutable commit while retaining human-readable release comments.

## Current state

Primary CI pins the resulting toolchain but not its installer:

```yaml
# .github/workflows/ci.yml:44-50
- name: Install MoonBit
  env:
    MOONBIT_INSTALL_VERSION: 0.10.3+16975d007
  run: |
    curl -fsSL https://cli.moonbitlang.com/install/unix.sh -o /tmp/moonbit-install.sh \
      && bash /tmp/moonbit-install.sh
```

The demo workflows use the setup path rejected by the primary workflow's
comment:

```yaml
# .github/workflows/spreadsheet-demo-build.yml:40-43
- name: Install MoonBit
  uses: hustcer/setup-moonbit@v1.22
  env:
    GITHUB_TOKEN: ${{ github.token }}
```

Current unique mutable action references include `actions/checkout@v5`,
`actions/setup-node@v6`, `actions/upload-artifact@v7`,
`actions/download-artifact@v8`, `hustcer/setup-moonbit@v1.22`, and
`cloudflare/wrangler-action@v4`.

Security boundaries that must remain unchanged:

- Workflow-level permissions stay `contents: read`.
- `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` remain referenced only by
  name at the deployment boundary; never inspect or reproduce their values.
- The Cloudflare deploy job retains its `environment: cloudflare-pages` gate.
- PR workflows must not gain deployment credentials.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Inventory actions | `rtk rg -n '^\\s*uses:' .github/workflows -g '*.yml'` | every result ends in a 40-hex SHA plus a release-tag comment after step 3 |
| Resolve tag | `rtk git ls-remote https://github.com/OWNER/REPO.git refs/tags/TAG 'refs/tags/TAG^{}'` | a reviewed commit for the intended release; annotated tags use the peeled `^{}` commit |
| Script syntax | `rtk bash -n scripts/install-moonbit-ci.sh` | exit 0, no output |
| Fail-closed probe | `rtk bash scripts/install-moonbit-ci.sh --self-test` | exit 0; valid digest accepted and wrong digest rejected before execution |
| Workflow diff | `rtk git diff --check` | exit 0, no whitespace errors |
| Boundaries | `rtk bash scripts/check-workspace-boundaries-selftest.sh` | exit 0; all fixture checks pass |
| Workspace | `rtk moon check` | exit 0, no errors after bootstrap is installed |
| Tests | `rtk moon test` | all test blocks pass |

## Suggested executor toolkit

- Use only official MoonBit release/install documentation and official GitHub
  repositories when establishing a verifiable artifact and checksum source.
- Use GitHub's action repository and release tag as the two sources for each
  action SHA. Do not copy a SHA from an unaffiliated blog or generated snippet.

## Scope

**In scope**:

- `.github/workflows/ci.yml`
- `.github/workflows/spreadsheet-demo-build.yml`
- `.github/workflows/spreadsheet-cloudflare-pages.yml`
- `scripts/install-moonbit-ci.sh` (create only after verification design passes)

**Out of scope**:

- Changing job structure, matrix size, triggers, concurrency, or deployment
  destinations.
- Broadening GitHub permissions or Cloudflare token scope.
- Reading, rotating, printing, or relocating secret values.
- Adding caching, consolidating jobs, or optimizing runner minutes.
- Updating MoonBit, Node, Playwright, Vite, or application dependencies beyond
  the versions already intended by the workflows.
- Adding Dependabot/Renovate configuration; action-update automation requires a
  separate maintainer decision.

## Git workflow

- Branch: `advisor/006-ci-supply-chain-bootstrap`
- Prefer two reviewable commits:
  1. `chore(ci): verify MoonBit bootstrap`
  2. `chore(ci): pin third-party actions`
- Do not push or open a PR unless instructed by the operator.

## Steps

### Step 1: Establish an independently verifiable MoonBit artifact

Using official MoonBit sources, identify a versioned installer or toolchain
artifact for the already-pinned version `0.10.3+16975d007` and an integrity
value published through an independent release channel: an official checksum
file, signature, provenance attestation, or immutable release asset digest.
Record the authoritative URLs and verification method in the new script's
comments. A checksum calculated from the same mutable `unix.sh` download during
the CI run is not independent verification and is unacceptable.

**Verify**: record the official immutable artifact identifier, source URL(s), and
verification method in the executor handoff and in comments beside the pinned
constants; a reviewer must be able to fetch the artifact and verification
source independently and reproduce the integrity check. Do not require a PR
description, because opening a PR is outside this plan.

### Step 2: Create one fail-closed repository-owned bootstrap

Create `scripts/install-moonbit-ci.sh` with `set -euo pipefail`. It must:

1. Hold the intended MoonBit version and reviewed integrity value in one place.
2. Download only the versioned official artifact into a temporary path.
3. Verify integrity before executing or extracting anything.
4. Fail before execution on any mismatch.
5. Install the toolchain and expose `$HOME/.moon/bin` to later GitHub Actions
   steps using the existing `$GITHUB_PATH` contract.
6. Retain the bounded retry behavior only around download failures; an integrity
   mismatch must never retry into success.
7. Provide a `--self-test` mode that uses local temporary fixtures only: prove a
   known-good digest passes, prove a wrong digest fails, and prove the failed
   case never creates an execution marker. The self-test must not use network or
   install a toolchain.

Replace every duplicated installer block and both `hustcer/setup-moonbit`
steps with `bash scripts/install-moonbit-ci.sh`. Keep the existing `moon version
--all` verification immediately afterward.

**Verify**:

- `rtk bash -n scripts/install-moonbit-ci.sh` → exit 0.
- `rtk bash scripts/install-moonbit-ci.sh --self-test` → exit 0 after printing
  one good-digest pass and one fail-closed wrong-digest pass.
- `rtk rg -n 'setup-moonbit|cli.moonbitlang.com/install/unix.sh' .github/workflows scripts` → no workflow duplicates and no mutable installer execution path.

### Step 3: Resolve and pin every third-party action

For each unique `uses:` reference, resolve the intended existing release tag to
its reviewed 40-character commit. For annotated tags, pin the peeled commit,
not the tag-object SHA. Replace the tag with the full SHA and retain the tag in
an end-of-line comment, for example `owner/action@<40-hex> # vX`.

Do not silently upgrade release families while pinning. Remove
`hustcer/setup-moonbit` rather than pinning it, because step 2 replaces it.

**Verify**:

- `rtk rg -n '^\\s*uses:.*@v' .github/workflows -g '*.yml'` → no matches.
- `rtk rg -n '^\\s*uses:.*@[0-9a-f]{40}(\\s+#\\s+v[^ ]+)?$' .github/workflows -g '*.yml'` → one match for every remaining `uses:` line.
- Manually cross-check each pinned SHA against the intended action repository
  and tag; record the mapping in the executor handoff for the operator and
  reviewer.

### Step 4: Preserve deployment and permission boundaries

Compare the workflow diff and confirm only installer/action references changed.
The deploy job must still require `cloudflare-pages`; secret names and their
`with:`/`env:` placement must remain unchanged; workflow permissions remain
`contents: read`.

**Verify**:

- `rtk rg -n 'permissions:|contents: read|environment: cloudflare-pages|CLOUDFLARE_' .github/workflows/*.yml` → the existing boundary markers remain.
- `rtk git diff -- .github/workflows` → no secret value, permission expansion,
  job consolidation, or trigger change.

### Step 5: Run repository verification

Run script syntax, whitespace, architecture boundaries, workspace checks, and
the full suite after installing through the new bootstrap in a clean CI-like
environment.

**Verify**:

- `rtk bash -n scripts/install-moonbit-ci.sh` → exit 0.
- `rtk git diff --check` → exit 0.
- `rtk bash scripts/check-engine-isolation.sh` → exit 0.
- `rtk bash scripts/check-workspace-boundaries-selftest.sh` → exit 0.
- `rtk bash scripts/check-workspace-boundaries.sh` → exit 0.
- `rtk moon check` → exit 0.
- `rtk moon test` → all tests pass.

## Test plan

- Implement the script's local-only `--self-test` mode with the same checksum
  helper used by the production path. It must assert both a valid fixture and a
  deliberately wrong digest, and assert that the wrong-digest case never writes
  an execution marker. Do not mock or bypass the real checksum command.
- Exercise the normal bootstrap in all three workflows through the existing
  `moon version --all` step.
- Review the Cloudflare job separately: artifact download and deployment remain
  pinned and the environment gate remains intact.
- Verification: all checks in step 5 pass. If the operator later runs a PR,
  confirm one GitHub Actions run completes with the pinned actions and verified
  bootstrap; that external run is not a prerequisite for this plan's local
  handoff.

## Done criteria

- [ ] Every remaining `uses:` reference is a full 40-hex commit with a tag comment.
- [ ] No workflow uses `hustcer/setup-moonbit` or executes the mutable installer URL.
- [ ] The MoonBit artifact is versioned and independently verified before execution.
- [ ] A wrong integrity value fails closed before installation.
- [ ] `rtk bash scripts/install-moonbit-ci.sh --self-test` exits 0.
- [ ] Workflow permissions, environment gate, secret names, triggers, and job structure are unchanged.
- [ ] Boundary scripts, `moon check`, and `moon test` pass.
- [ ] `rtk git diff --check` exits 0.
- [ ] Only in-scope files and `plans/README.md` are modified.
- [ ] The status row for plan 006 is updated in `plans/README.md`.

## STOP conditions

Stop and report instead of improvising if:

- Official MoonBit sources do not publish a stable artifact plus independently
  verifiable checksum, signature, attestation, or immutable digest for the
  pinned version.
- Resolving an action tag produces ambiguous or conflicting commits.
- A pinned action requires broader permissions or a changed secret boundary.
- Replacing the setup action requires a toolchain version upgrade.
- Verification requires reading or printing any secret value.
- An unrelated workflow or test failure persists after two reasonable retries.

## Maintenance notes

- Every future action upgrade must update both the full SHA and its release-tag
  comment after reviewing release notes and repository ownership.
- Every MoonBit upgrade must update the version and integrity value atomically,
  then exercise the wrong-digest probe.
- Reviewers should focus on provenance, fail-closed behavior, and unchanged
  permission/secret boundaries—not just whether CI turns green.
- Runner caching and duplicate-install performance remain recorded for later
  revisit; they are deliberately outside this security plan.
