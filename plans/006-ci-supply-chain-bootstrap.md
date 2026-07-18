# Plan 006: Pin third-party GitHub Actions to immutable commits

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. Never copy a secret value into source, logs, the
> plan index, or a commit. When done, update the status row for this plan in
> `plans/README.md` unless a reviewer told you they maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 23daa60..HEAD -- .github/workflows/ci.yml .github/workflows/spreadsheet-demo-build.yml .github/workflows/spreadsheet-cloudflare-pages.yml`
> If any in-scope workflow changed, compare the current-state excerpts and
> action inventory below with the live files. On a mismatch, treat it as a STOP
> condition and report the drift instead of pinning a stale inventory.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `23daa60`, 2026-07-18
- **Refresh note**: Narrowed from action pinning plus MoonBit bootstrap
  replacement. The bootstrap work is vendor-blocked and recorded as R21 in
  `plans/README.md`; this plan must not claim to solve it.

## Why this matters

All 17 `uses:` entries in the repository's three GitHub Actions workflows point
at mutable release tags. A moved or compromised tag can therefore change code
executed in CI without a repository diff. The highest-risk example is
`cloudflare/wrangler-action@v4`, which runs at the deployment boundary with a
Cloudflare API token and account ID.

Pin every action to the reviewed full commit SHA for its current tag while
preserving a human-readable tag comment. Do not silently upgrade action
families, alter workflow behavior, or broaden permissions.

The original Plan 006 also proposed replacing MoonBit installation with a
repository-owned verified bootstrap. That work is not executable under the
plan's integrity standard: official documentation currently publishes checksum
links only for mutable `latest` native artifacts; the pinned version's native
CLI archive, core archive, and versioned checksum paths are not durably
available; and the official GitHub release for this compiler version contains a
WASM compiler asset, not the native CLI plus core used here. R21 records the
vendor evidence required to reopen that work. Runtime-fetched `latest`
checksums, self-computed digests from the same mutable channel, and the WASM
compiler are not acceptable substitutes.

## Current state

The repository has exactly three workflow files:

- `.github/workflows/ci.yml` — library, docs, examples, boundary, performance
  ratio, and browser checks. Seven checkout steps use `actions/checkout@v5`.
- `.github/workflows/spreadsheet-demo-build.yml` — typed-spreadsheet PR build
  and DOM test. It uses checkout, MoonBit setup, and Node setup actions.
- `.github/workflows/spreadsheet-cloudflare-pages.yml` — site build, artifact
  transfer, and Cloudflare Pages deployment. It uses checkout, MoonBit setup,
  Node setup, upload/download artifact, and Wrangler actions.

There are 17 `uses:` entries and six unique intended tag mappings:

| Current reference | Occurrences | Reviewed commit for this plan |
|---|---:|---|
| `actions/checkout@v5` | 10 | `93cb6efe18208431cddfb8368fd83d5badbf9bfd` |
| `actions/setup-node@v6` | 2 | `249970729cb0ef3589644e2896645e5dc5ba9c38` |
| `actions/upload-artifact@v7` | 1 | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |
| `actions/download-artifact@v8` | 1 | `3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c` |
| `hustcer/setup-moonbit@v1.22` | 2 | `9199da0ab63ea0c0bab1dc15f03d76e17ed4f75f` (peeled annotated tag) |
| `cloudflare/wrangler-action@v4` | 1 | `ebbaa1584979971c8614a24965b4405ff95890e0` |

The occurrence count totals 17: `actions/checkout@v5` appears seven times in
`ci.yml`, once in the demo-build workflow, and twice in the Cloudflare
workflow. Any disagreement between this table and the live inventory is a STOP
condition requiring a plan refresh.

Representative current entries are:

```yaml
# .github/workflows/ci.yml
- name: Checkout
  uses: actions/checkout@v5
```

```yaml
# .github/workflows/spreadsheet-demo-build.yml
- name: Install MoonBit
  uses: hustcer/setup-moonbit@v1.22
  env:
    GITHUB_TOKEN: ${{ github.token }}
```

```yaml
# .github/workflows/spreadsheet-cloudflare-pages.yml
- name: Deploy to Cloudflare Pages
  uses: cloudflare/wrangler-action@v4
```

Security and deployment boundaries that must remain byte-for-byte unchanged
apart from surrounding line numbers:

- Every workflow keeps workflow-level `permissions: contents: read`.
- The deploy job keeps `environment: cloudflare-pages`.
- `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, and
  `CLOUDFLARE_PAGES_PROJECT_NAME` remain referenced only by name at the current
  verification/deployment boundary. Never inspect or reproduce their values.
- Triggers, path filters, concurrency, job structure, action inputs, and action
  environment variables remain unchanged.
- The five official installer blocks in `ci.yml` and the two
  `hustcer/setup-moonbit` steps remain known bootstrap debt. Pinning the setup
  action secures its code identity but does not solve installer provenance or
  the CDN reliability concern documented in `ci.yml`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Inventory actions | `rg -n '^\s*uses:' .github/workflows -g '*.yml'` | exactly 17 entries before and after the edit |
| Resolve lightweight tag | `git ls-remote https://github.com/OWNER/REPO.git refs/tags/TAG 'refs/tags/TAG^{}'` | one tag commit; no peeled line for a lightweight tag |
| Resolve annotated tag | same command for `hustcer/setup-moonbit` `v1.22` | tag object plus peeled `^{}` commit; pin the peeled commit |
| Reject mutable refs | `rg -n '^\s*uses:.*@v' .github/workflows -g '*.yml'` | zero matches |
| Count immutable refs | `rg -n '^\s*uses:.*@[0-9a-f]{40}\s+#\s+v[^ ]+$' .github/workflows -g '*.yml'` | exactly 17 matches |
| Workflow syntax | `actionlint .github/workflows/*.yml` | exit 0, no diagnostics |
| Whitespace | `git diff --check` | exit 0 |
| Engine boundaries | `bash scripts/check-engine-isolation.sh` | exit 0 |
| Boundary self-test | `bash scripts/check-workspace-boundaries-selftest.sh` | all known-positive controls pass |
| Workspace boundaries | `bash scripts/check-workspace-boundaries.sh` | exit 0 |
| Documentation boundaries | `python3 scripts/check-documentation-boundaries.py` | exit 0 |
| Workspace check | `moon check` | exit 0 |
| Full tests | `moon test` | all workspace tests pass |

## Suggested executor toolkit

- Resolve action tags only from each action's official GitHub repository.
- Use GitHub's secure-use guidance for the rationale behind full-length commit
  pins; do not copy SHAs from blogs or generated snippets.
- Treat the mapping table as a reviewed baseline, not permission to skip the
  live `git ls-remote` checks.

## Scope

**In scope** (the only workflow files to modify):

- `.github/workflows/ci.yml`
- `.github/workflows/spreadsheet-demo-build.yml`
- `.github/workflows/spreadsheet-cloudflare-pages.yml`
- `plans/README.md` (status row only when execution completes)

**Out of scope** (do not touch, even though related):

- Creating `scripts/install-moonbit-ci.sh`, a composite action, a checksum file,
  or any other MoonBit bootstrap path. R21 owns the evidence gate.
- Replacing or deduplicating the five `unix.sh` installer blocks.
- Removing `hustcer/setup-moonbit`; pin its existing `v1.22` implementation.
- Fetching a checksum from `binaries/latest` during CI, computing a digest from
  the same mutable channel, vendoring a toolchain, or substituting the WASM
  compiler release.
- Changing MoonBit, Node, Playwright, Vite, Wrangler, or action release
  families.
- Changing job structure, matrices, triggers, path filters, concurrency,
  deployment destinations, action inputs, or environment variables.
- Broadening GitHub permissions or Cloudflare token scope.
- Reading, rotating, printing, or relocating secret values.
- Adding Dependabot/Renovate configuration, caching, job consolidation, or
  runner-minute optimization.

## Git workflow

- Branch: `advisor/006-pin-github-actions`
- One reviewable commit: `chore(ci): pin third-party actions`
- Do not push or open a PR unless the operator separately instructs it.

## Steps

### Step 1: Re-resolve every intended tag and confirm the inventory

Run the inventory command and confirm there are exactly 17 `uses:` entries.
Resolve all six tags from their official repositories with `git ls-remote`.
Compare the results with the mapping table above. For an annotated tag, use the
peeled `refs/tags/TAG^{}` commit; `hustcer/setup-moonbit` `v1.22` is annotated
in the reviewed baseline. Lightweight tags use their direct tag commit.

Do not accept a moved tag silently. A result different from the reviewed table
may be a legitimate release-tag update or a compromise; either case requires a
fresh review and plan refresh before editing workflows.

**Verify**:

1. `rg -n '^\s*uses:' .github/workflows -g '*.yml' | wc -l` → `17`.
2. Each `git ls-remote` result matches the reviewed table, including the peeled
   `setup-moonbit` commit.

### Step 2: Replace all mutable action tags with full commit pins

Replace each `uses: OWNER/REPO@TAG` with the reviewed 40-character commit and an
end-of-line tag comment:

```yaml
uses: OWNER/REPO@0123456789abcdef0123456789abcdef01234567 # vX
```

Apply the same pin consistently to every occurrence. Preserve names, inputs,
environment variables, indentation, step order, and all other workflow text.
Do not upgrade any tag or remove the MoonBit setup action.

**Verify**:

1. `rg -n '^\s*uses:.*@v' .github/workflows -g '*.yml'` → zero matches.
2. `rg -n '^\s*uses:.*@[0-9a-f]{40}\s+#\s+v[^ ]+$' .github/workflows -g '*.yml' | wc -l` → `17`.
3. `rg -n '^\s*uses:' .github/workflows -g '*.yml'` → every occurrence uses
   the expected SHA and tag comment.

### Step 3: Prove workflow behavior and security boundaries did not change

Review the workflow diff line by line. Every changed line must be a `uses:`
reference. Confirm that permissions, environment gate, secret/variable names,
action inputs, installer blocks, triggers, path filters, job structure, and
concurrency are unchanged.

Do not print secret values. The source contains only expressions naming secrets
and variables; validation must inspect names and placement only.

**Verify**:

1. `git diff --unified=0 -- .github/workflows` → every hunk changes only a
   `uses:` line.
2. `rg -n 'permissions:|contents: read|environment: cloudflare-pages|CLOUDFLARE_' .github/workflows/*.yml` → the existing boundary markers remain.
3. `actionlint .github/workflows/*.yml` → exit 0 with no diagnostics.
4. `git diff --check` → exit 0.

### Step 4: Run repository validation

Run the repository's architecture, workspace, documentation, typecheck, and
full-test gates. These checks do not prove remote action execution, but they
confirm the narrow workflow edit did not accompany source or documentation
breakage. A later PR must also complete one GitHub Actions run before merge.

**Verify**:

1. `bash scripts/check-engine-isolation.sh` → exit 0.
2. `bash scripts/check-workspace-boundaries-selftest.sh` → exit 0.
3. `bash scripts/check-workspace-boundaries.sh` → exit 0.
4. `python3 scripts/check-documentation-boundaries.py` → exit 0.
5. `moon check` → exit 0.
6. `moon test` → all workspace tests pass.
7. `git status --short` → only the three workflow files and the permitted
   `plans/README.md` status update are modified.

## Test plan

- Static inventory proves every `uses:` line moved from a mutable tag to one
  full SHA plus its readable tag comment.
- Live `git ls-remote` checks prove each SHA belongs to the intended official
  repository/tag; the annotated MoonBit setup tag uses its peeled commit.
- `actionlint` validates workflow syntax after comments and SHAs are inserted.
- A zero-context diff review proves no trigger, permission, secret boundary,
  input, installer, or job behavior changed.
- Existing architecture/workspace/documentation checks and the full MoonBit
  suite remain green.
- Before merge, GitHub-hosted CI must run the pinned actions successfully. Do
  not weaken a failed remote check or replace a pin merely to make CI green;
  investigate against the official action repository and release first.

## Done criteria

- [ ] Exactly 17 `uses:` entries remain across the three workflows.
- [ ] Every `uses:` entry is pinned to the reviewed full 40-hex commit and has
      the original release tag in an end-of-line comment.
- [ ] `hustcer/setup-moonbit` uses the peeled `v1.22` commit.
- [ ] `rg -n '^\s*uses:.*@v' .github/workflows -g '*.yml'` returns no matches.
- [ ] The immutable-reference regex returns exactly 17 matches.
- [ ] The workflow diff changes only `uses:` lines.
- [ ] Permissions, the `cloudflare-pages` environment gate, secret/variable
      names and placement, triggers, path filters, action inputs, installer
      blocks, and job structure are unchanged.
- [ ] `actionlint .github/workflows/*.yml` exits 0.
- [ ] `git diff --check`, all boundary checks, `moon check`, and `moon test`
      exit 0.
- [ ] GitHub-hosted CI passes before merge.
- [ ] No MoonBit bootstrap replacement or unsupported provenance claim is
      introduced; R21 remains the source for that blocked work.
- [ ] `git status --short` lists only in-scope files.
- [ ] The Plan 006 row in `plans/README.md` is updated when execution completes.

## STOP conditions

Stop and report instead of improvising if:

- The drift check reports an in-scope workflow change or the live inventory is
  not exactly 17 entries.
- Any live tag resolution differs from the reviewed mapping table.
- A tag is annotated but the direct tag-object SHA is about to be pinned instead
  of the peeled commit.
- Pinning an action requires changed inputs, broader permissions, a changed
  secret/environment boundary, or a release-family upgrade.
- Any diff hunk changes something other than a `uses:` line.
- Verification requires reading or printing any secret value.
- A GitHub-hosted check fails because the pinned commit is unsupported or
  incompatible; investigate and refresh the plan rather than moving the pin.
- Any validation command fails twice after one reasonable retry for transient
  infrastructure.
- Any out-of-scope file must be modified.

## Maintenance notes

- Every future action upgrade must update both the full SHA and release-tag
  comment after reviewing release notes and repository ownership.
- Major tags may move. Dependabot/Renovate policy for action pins remains a
  separate maintainer decision.
- Pinning `hustcer/setup-moonbit` fixes code identity only. It does not solve
  the Nu-binary CDN reliability concern or native toolchain/core provenance.
- R21 may reopen only when the vendor publishes durable versioned native CLI
  and core artifacts with immutable digests, signatures, or attestations.
- Reviewers should scrutinize the Wrangler deployment pin, the peeled
  `setup-moonbit` tag, unchanged secret boundaries, and the exact 17-entry
  inventory.
