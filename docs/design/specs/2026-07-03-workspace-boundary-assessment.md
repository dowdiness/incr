# Workspace Boundary Assessment — 2026-07-03

**Status:** Point-in-time analysis. Proposes work at the workspace seams
(examples/incr, root facade surface); the core library layering is verified
healthy and explicitly left unchanged. Actionable items are tracked as GitHub
issues (linked per section); nothing in this document changes code by itself.

**Read-before-trust rule** (inherited from the
[2026-04-20 assessment](2026-04-20-architecture-assessment.md)): if a
file:line, LOC count, or commit is cited, verify it against the current tree
before quoting it in later work.

---

## Why this document exists

The 2026-04-20 assessment and the
[R2 ADR](../../decisions/2026-04-26-r2-runtime-decomposition-deferred.md)
settled the in-library structural questions: post-R1, `types → shared →
engines → kernel → cells → root` is a healthy, script-enforced layering, and
further core decomposition is rejected without a concrete driver. A fresh
full-tree diagnosis (2026-07-03) confirms that judgment still holds — no
cross-engine coupling, no back-edges, no comment-marked kernel debt.

What has changed since April is *where the pressure lives*. It has moved
outside the core, to seams the existing enforcement does not cover:

1. the `examples/` ↔ library boundary,
2. the dual public API surface on the root facade,
3. drift classes (doc/state, version pins) with no mechanical check.

## Baseline measurements (2026-07-03, `main @ f32505e`)

| Unit | Source LOC | Test LOC |
|---|---|---|
| `incr/` root facade (`incr.mbt` + `traits.mbt`) | 337 | 0 |
| `incr/types` | 573 | 34 |
| `incr/cells` (36 non-test top-level files) | 7,004 | 10,620 |
| `incr/cells/internal/kernel` | 2,676 | 0 |
| `incr/cells/internal/{shared,pull,push,datalog}` | 523 | 0 |
| `incr/tests` (integration) | 0 | 6,022 |
| `examples/incr_tea` | 10,187 | 4,035 |
| other `examples/*` (7 modules) | ~7,000 | ~5,700 |

Reference points against prior records:

- `incr/cells/runtime.mbt` is **776 LOC** — past the R2 ADR's "~600 LOC for a
  non-cosmetic reason" watch threshold. ~140 LOC of that
  (`runtime.mbt:225–364`) is event-listener/hook plumbing added by the
  [composable runtime hooks ADR](../../decisions/2026-06-09-composable-runtime-hooks.md)
  — the first genuinely non-delegator tenant since R1. See §P3.
- `incr/pipeline/` no longer exists in the tree; `docs/todo.md` still carries
  its removal as a pending task. See §P5.
- Legacy `Signal`/`Memo`/`HybridMemo` are gone as public types; the internal
  engine rename (#335/#336) is complete. Three compatibility handle types
  remain public (`TrackedCell`, `Reactive`, `FunctionalRelation` —
  `incr.mbt:37,40,42`) alongside the compatibility traits and helpers. See
  §CP2. *(Corrected 2026-07-03 after Codex review: an earlier revision claimed
  the residue was "traits and helpers, not handle types".)*
  *(Status update, 2026-07-03 post-#345: resolved — the remaining handle
  types, compatibility traits, and helpers were removed directly as v0.13.0,
  with no deprecation stage.)*

## Confirmed change pressures

**CP1 — The TEA framework outgrew its "example" container.**
`examples/incr_tea` (10.2k src LOC) is larger than all of `incr/cells`. Six
open issues (#268, #286, #288, #256, #252, #190) are feature work on it. It
has three in-repo consumers (`incr_tea_7guis`,
`typed_spreadsheet_incr_tea_demo`, browser benches) and has already exerted
design pressure on the core (the composable-hooks ADR exists because the TEA
renderer was the two-consumer case). Its `moon.mod` identity is nominal and
example-scoped (`examples/incr_tea` v0.1.0, unpublished): it has no published
library identity, no consumer-facing version contract, no owner document, and
no rule preventing it from importing library internals.

**CP2 — Dual public API surface with an unscheduled sunset.** Compatibility
traits (`Database`/`RuntimeContext`, `Readable`/`Freshness`,
`Trackable`/`InputFieldOwner`) coexist in `incr/traits.mbt` (277 LOC);
`target_facade.mbt` (907 LOC) wraps impl files with delegation-only structs;
`scripts/migrate-to-target-facades.py` still exists. Every new API pays a
"which surface gets this?" decision tax, re-adjudicated per PR (e.g. #303–305
recorded "compatibility handles do not get bridge methods" as a per-PR call).
The [ideal-naming ADR](../../decisions/2026-05-21-public-api-ideal-naming.md)
planned a migration window but never scheduled it; the cost of the window
grows monotonically as the library approaches external adoption.
*(Status update, 2026-07-03 post-#345: executed — the dual surface was
removed as v0.13.0 in a single breaking release; the codemod script was
deleted with it. This pressure is closed.)*

**CP3 — Coordinator concern accretion in `runtime.mbt`.** Not a god object —
but observability plumbing (listener registries, hook dispatch, broadcast
phases) is a *new responsibility category* accreting on the facade, and it is
the one growth trend that, unchecked, recreates the pre-R1 problem.

**CP4 — Drift classes with no mechanical check.** `examples/incr_tea` pins
`dowdiness/incr@0.9.0` while the library is at 0.12.0 (masked by workspace
resolution — invisible until someone builds outside the workspace).
`docs/todo.md` carries at least one dead entry (`incr/pipeline` removal).
In-library invariants are scripted
(`scripts/check-engine-isolation.sh`); cross-module contracts are not.

**CP5 — Test topology contradicts package topology.** Kernel (2,676 LOC) and
all engine packages carry zero in-package tests; their whitebox tests live as
`cells/*_wbtest.mbt`, calling `@kernel` directly. Kernel refactors therefore
churn test files in a different package. *(Corrected 2026-07-03 after Codex
review: `cells/kernel_using.mbt` is a package-scoped production convenience
import for `cells/*.mbt` source — not a test-only re-export, and not deletable
on test migration alone.)*

## Non-findings (checked and dismissed)

- No cross-engine imports, no back-edges, no kernel→cells edges — the four
  isolation-script invariants hold.
- No driver for service decomposition; the R2 ADR's rejection stands. The
  776-LOC breach of its watch threshold is adjudicated in the ADR's addendum
  (see below) rather than reopening decomposition.
- `AcceptedDerived`/`BackdateEq` surface (~490 LOC): recently merged, still
  evolving — deliberately not assessed for restructuring.

## Target structure and dependency rules

Core library: **unchanged**. New rules, all mechanically checkable:

1. `examples/*` modules (and a future promoted TEA module) import
   `dowdiness/incr` **root facade only** — never `dowdiness/incr/cells` or
   `dowdiness/incr/types` directly. Whatever the facade cannot express becomes
   an explicit core feature request (codifying the pattern the
   composable-hooks ADR already followed).
2. Demos/benches import the TEA framework module; the framework never imports
   a demo.
3. Workspace members' registry pins for sibling modules must equal the
   sibling's current version.
4. (Opportunistic, long-horizon) kernel whitebox tests migrate into the kernel
   package per-file when kernel files are touched anyway. (`kernel_using.mbt`
   stays — it serves production `cells/*.mbt` code, not tests.)
5. Placement law, written down: code that takes `Runtime` lives in `cells/`;
   algorithms that take state structs live in `kernel/`.

## Staged plan (each stage independently shippable and reversible)

- **Stage 0 — contracts before movement:** boundary/pin check script
  (validated with a known-positive control before its pass is trusted), fix
  the `incr_tea` pin, purge dead `todo.md` entries.
- **Stage 1 — split `incr_tea` framework from demos:** framework, demo, and
  bench `.mbt` files are currently co-mingled in the package root (`src/`
  holds only JS/CSS web assets), so Stage 1 starts with a file-level
  classification pass, then moves the framework files to their own workspace
  module; byte-equivalent move, no API redesign in the same PR; demo/bench
  imports repointed.
- **Stage 2 — TEA identity:** an ADR naming the module's scope, its
  facade-only import contract, and its own backlog; retarget open TEA issues
  to it. Gated on a naming/identity decision (in-workspace module vs eventual
  own repository — in-workspace preferred to keep the core-feedback loop
  cheap).
- **Stage 3 — API convergence window (breaking):** one release marking
  compatibility traits/helpers `#deprecated` so loom/canopy see warnings; then
  remove compat traits, deprecated aliases, and the migrate script; collapse
  facade/impl file pairs where the wrapper adds no logic. Verify via `.mbti`
  diffs, checked `.mbt.md` docs, and loom/canopy CI against the release
  candidate **before** publish. Execute before external users arrive.
- **Stage 4 — gated, may never fire:** extract observability plumbing from
  `runtime.mbt` into a same-package concern file **only if** a second
  event-surface family lands (push/effect/fixpoint events) or another
  non-delegator concern accretes. Below the trigger, do nothing. Recorded as
  an addendum on the R2 ADR.

## Risks

- Stages 0–2 touch no engine/kernel code: zero performance/correctness risk
  beyond move mechanics (full workspace `moon test` + boundary script gate).
- Stage 3 is intentionally breaking (major/minor bump per the current semver
  policy); the deprecation release converts unknown downstream usage into
  compiler warnings before removal. Run `moon bench --release` before/after
  the facade/impl collapse as a guard.

## Open decisions (user-owned)

1. TEA module identity: name, in-workspace vs own-repo trajectory (Stage 2).
2. The date/version for the Stage 3 breaking window.
