# ADR: Documentation Retention Policy

**Date:** 2026-06-02

## Status

Accepted

## Decision

Documentation in this repository follows a retention policy organized around
five principles:

1. **`docs/archive/` is retired, not maintained.** Completed or superseded
   plans, specs, research notes, and obsolete measurement snapshots are
   deleted after triage rather than kept as a maintained historical corpus.
   Git history is the recovery mechanism for any content removed under this
   policy.
2. **Accepted ADRs are durable decision records.** They are marked
   *superseded* rather than deleted when a later decision replaces them.
3. **Documentation is organized by current-reader need and a single source
   of truth.** Stale duplicates and content that no longer matches the code
   are removed rather than preserved for completeness.
4. **READMEs are required at reader-facing entry points.** Specifically: the
   repository root, any public or publishable module, `docs/` and
   `examples/` entry points, and independently runnable workspace packages.
   READMEs are **not** required for implementation-only source packages,
   `internal/` packages, test-only directories, `scripts/`, generated files,
   or `archive/` subdirectories.
5. **`CLAUDE.md` must be a symlink to `AGENTS.md`** rather than a separate
   copy of contributor guidance, so that agent instructions have a single
   source of truth. This ADR records the policy; it does not perform the
   symlink.

When documentation is deleted under this policy, the commit must:

- Update the `docs/README.md` index to remove the entry.
- Fix or remove any incoming links from surviving documents.
- Include a concise commit message explaining that the content is
  recoverable with `git log` / `git show`.

## Context

The repository accumulated completed plans, superseded design specs, older
research notes, and point-in-time measurement snapshots under
`docs/archive/`. The archive grew without a stated retention rule, creating
ambiguity about whether its contents were current guidance or historical
reference. Contributors and agents had no clear signal about when archive
material should be trusted, deleted, or ignored.

Separately, the repository had no written policy on which directories need
a README, whether `CLAUDE.md` and `AGENTS.md` should coexist as separate
files, or how to handle ADRs that are later superseded. These questions
surfaced repeatedly during workspace-layout and module-identity work (see
the [2026-06-01 workspace-layout ADR](2026-06-01-workspace-layout.md)) and
motivated a single decision record covering all of them.

## Non-goals

- **No archive deletion in this ADR.** This document records the policy;
  the actual triage and removal of existing archive material is follow-up
  work (see Follow-up).
- **No CLAUDE.md symlink creation.** The policy is recorded here; the
  mechanical symlink replacement is a separate change.
- **No changes to archive files, plans, CLAUDE.md, AGENTS.md, symlinks, or
  code.** This ADR is documentation-only.

## Considered Options

- **Option: Maintain archive as a curated historical corpus — not chosen.**
  What it means: keep `docs/archive/` as a first-class section of the docs,
  with ongoing maintenance, cross-links, and a freshness guarantee.
  Why not chosen: the archive already contains content that disagrees with
  current code and docs; maintaining it duplicates the single-source-of-truth
  principle and creates a second corpus that drifts. Git history already
  provides recovery without a maintenance burden.

- **Option: Delete everything indiscriminately — not chosen.**
  What it means: remove all archive material immediately with no policy.
  Why not chosen: ADRs are durable decision records with ongoing value;
  deleting them loses the *why* behind past choices. A triage step is
  needed to separate durable records from stale material.

- **Option: Retire archive, keep ADRs, record policy — chosen.**
  What it means: delete completed/superseded non-ADR archive material after
  triage; mark (don't delete) superseded ADRs; record the retention rules so
  future contributors know what belongs where.
  Why chosen: matches the project's "code is the source of truth" principle,
  preserves decision rationale, and reduces docs surface area to what
  current readers need.

## Consequences

- **Archive material will be deleted over time.** Each deletion updates the
  `docs/README.md` index, fixes incoming links, and records in the commit
  message that the content is recoverable via `git log` / `git show`.
- **ADRs are permanent.** Superseded ADRs remain in `docs/decisions/` with
  their status updated; they are never removed.
- **README coverage has a clear boundary.** Root, public modules, docs/examples
  entry points, and runnable workspace packages get READMEs; everything else
  does not need one.
- **Single source of truth for contributor guidance.** `CLAUDE.md` becomes a
  symlink to `AGENTS.md` once the follow-up change lands; until then, the
  two may diverge.

## Compatibility and API Impact

None. This ADR is documentation-only: no MoonBit code, no public API, no
`.mbti`, no module import graph changes, no build configuration changes.

## Follow-up

Deferred work; none of it is performed by this ADR.

- **Archive triage and cleanup.** Walk `docs/archive/`, classify each file
  as (a) superseded plan/spec/research → delete, (b) obsolete measurement
  snapshot → delete, (c) other → delete unless it has surviving link value.
  For each deletion, update `docs/README.md` and fix incoming links. Record
  the policy rationale in each commit message.
- **CLAUDE.md → AGENTS.md symlink.** Replace the `CLAUDE.md` file with a
  symlink to `AGENTS.md` so that contributor guidance has a single source
  of truth. Verify that any tooling or CI referencing `CLAUDE.md` still
  resolves the symlink correctly.
- **README coverage audit.** Verify that all reader-facing entry points
  (root, public modules, docs/examples entries, runnable workspace packages)
  have READMEs, and that exempt directories (implementation-only source,
  `internal/`, test-only, `scripts/`, generated, `archive/`) do not carry
  unnecessary READMEs.
