# ADR: Workspace layout

**Status:** Accepted  
**Date:** 2026-06-01

## Context

The repository used the module root as both the publishable `dowdiness/incr`
MoonBit module and the place for repository-level docs, scripts, CI, and demos.
That kept demo dependencies, such as Rabbita, attached to the library module and
made repository-root commands less explicit about which files belong to the
published package.

A clearer split is a repository-level workspace, a named library module
directory, and standalone example modules.

## Decision

Adopt a workspace layout for `incr`:

- `moon.work` lives at the repository root.
- The publishable library module `dowdiness/incr` lives under `incr/`.
- Checked documentation examples live under `docs/` as a separate workspace
  member that depends on `dowdiness/incr`.
- Typed-spreadsheet demos and retained spikes live under `examples/` as
  standalone workspace modules.
- The root `README.md` is a workspace pointer; the package README lives at
  `incr/README.mbt.md`.

## Consequences

- Public library imports remain `dowdiness/incr`, `dowdiness/incr/cells`,
  `dowdiness/incr/types`, and so on.
- Demo package imports become `examples/typed_spreadsheet_demo`,
  `examples/typed_spreadsheet_cli_demo`, and
  `examples/typed_spreadsheet_rabbita_demo`, and
  `examples/spikes/ideal_api_rename_phase0`.
- The core library module no longer depends on Rabbita; only the Rabbita demo
  module does.
- Targeted source paths from the repository root gain the `incr/` prefix, for
  example `moon test incr/cells/derived_test.mbt`.
