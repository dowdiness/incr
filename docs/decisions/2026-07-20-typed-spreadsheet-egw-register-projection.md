# ADR: Typed spreadsheet EGW register and projection boundary

**Date:** 2026-07-20

**Status:** Accepted; Plan 013 closed 2026-07-24 as a completed bounded adapter experiment. Performance outcome is inconclusive (pre-registered browser baseline blocked A/B); correctness and application boundary succeeded.

**Current implementation:** The executable browser routes committed single-user commands through the adapter using EGW authority; local and remote projection share one path. Remote transport, room/join lifecycle, and presence remain follow-up work.

**Reconciliation:** The adapter was revalidated against published `dowdiness/event-graph-walker@0.5.0` without an adapter code change beyond the dependency version. It continues to consume EGW `container`; `peer_sync`, payload-opaque runtime/provider work, and room lifecycle remain separate slices.

**Implementation plan:** [Plan 013 reconciliation note](../../plans/README.md)

**Collaboration boundary:** [Parent EGW collaboration responsibility boundary](https://github.com/dowdiness/canopy/blob/d1d30bc27b76dc9bb5cc08e1d1a1569aa4433265/docs/decisions/2026-07-21-egw-collaboration-responsibility-boundary.md)

This record owns spreadsheet register and projection semantics. The parent ADR
owns the target placement of peer-sync, collaboration runtime, and providers.

**Reader:** Maintainers designing or reviewing the first collaborative typed-spreadsheet driver and any later EGW API proposal derived from it.

**Decision:** Represent each committed cell source as one application-tagged atomic LWW register in EGW, route local commands and remote sync through one authoritative-state projection path, and treat the adapter as an evidence-producing application boundary rather than a generic `egw_incr` abstraction.

**Keep until:** Permanently; ADRs are durable and are marked superseded rather than deleted.

**Disposition:** Mark Accepted or Rejected with the bounded experiment result. Supersede this ADR if formula collaboration moves to sequence text, document replacement moves into a different authority, or a reusable adapter boundary is accepted after a second driver.

## Context

The typed-spreadsheet `incr_tea` demo now plans closure-free application
commands that own submitted source text, typed cell identity, a local document
generation, and variant-implied selection or editing admission. The current
interpreter still mutates `Worksheet` directly. A collaborative driver needs a
new authority path:

```text
local application command -----> authoritative EGW document
remote EGW sync message --------> authoritative EGW document
                                      |
                                      v
                              application projection
                                      |
                                      v
                             one incr Runtime batch
```

The adapter is also the first real driver for deciding whether EGW needs a
stronger local/remote change-report boundary. Designing that EGW API first
would make application preference look like a general requirement. The
experiment must therefore establish correctness with EGW's published public
surface, record every workaround, and promote only repeated, measured,
application-independent pressure.

The application currently submits a whole formula or input source at commit
time. Drafts, selection, editing identity, and focus are local UI state. Merging
individual characters from concurrent committed formulas would introduce a new
product behavior and can converge to syntax that neither user submitted.

## Decision

### 1. Store one atomic register per committed cell

One synchronized worksheet node holds one property for each known cell address.
Each property value is a strict, versioned, tagged application payload with one
of two states:

- committed source text;
- deleted cell.

The tag and source are encoded together in one property value. They are not
split across properties, and deletion is not represented by an empty-string
sentinel. This preserves one LWW conflict-resolution point per cell and avoids
torn source/presence state.

Formula and input source use the same register boundary. Formula parsing and
runtime type checking remain application projection concerns. This decision
does not introduce sequence-text formula collaboration.

### 2. Keep local drafts outside the collaborative document

EGW contains committed source only. Selection, editing identity, focus,
viewport, and uncommitted drafts remain local.

After an authoritative projection change:

- a clean draft follows the new committed source;
- a dirty draft remains unchanged;
- selection and editing identity remain unchanged;
- focus remains a local post-render effect.

AI-context publication remains the application's unconditional post-flush
policy and is not an EGW operation.

### 3. Use one projection path after every authoritative mutation

Local commands are admitted by application generation and local UI
preconditions, then parsed before any EGW mutation. An accepted local command
updates EGW first. A remote message is first applied through EGW sync. Both
paths then invoke the same projection pipeline.

The imperative shell reads the known bounded address set from the mutable EGW
document into an owned snapshot. Application projection state separates the
last successfully seen raw register snapshot, the last-good semantic cell
projection installed in `Worksheet`, and current diagnostics. A functional core
strictly decodes a new snapshot and reduces those prior states into candidate
next states plus immutable projection decisions. The shell applies those
decisions to the `Worksheet` and application `InputField`s in one
`Runtime::batch`, then commits the candidate retained states only after the
batch succeeds.

The functional core never reads a mutable EGW `Document`, performs I/O, or
exposes internal mutable arrays.

### 4. Retain last-good spreadsheet semantics for invalid remote payloads

Local source is parsed before publication to EGW, preserving the current
rejection behavior for invalid submissions. Remote data still crosses an
application trust boundary: a structurally valid EGW property can contain an
unknown register version, malformed payload, or invalid formula source.

The application records deterministic projection diagnostics and retains its
local last-good semantic `Worksheet` value for the affected cell. The
authoritative raw register remains in EGW; the adapter does not rewrite remote
history to repair it. Peers derive the same diagnostic from the same merged
register, but this ADR makes no cross-peer computed-Worksheet convergence claim
while the authoritative application payload is invalid: last-good caches can
reflect different delivery histories. When a valid merged register replaces
the invalid value, all peers must project and converge again.

### 5. Bootstrap one shared worksheet node

One authoritative initializer creates the worksheet node, writes initial cell
registers to EGW, derives the initial `Worksheet` through the shared projection
path, and distributes a bootstrap containing the application logical document
identity and synced EGW node identity before peers may edit. Peers do not
independently create candidate worksheet roots, discover roots by scanning, or
resolve duplicate roots in application code. Direct Worksheet seeding is not a
second authority path.

The bootstrap and transport mechanism are outside the first adapter. Tests use
deterministic in-process setup.

### 6. Treat reset as application document replacement

Reset creates a fresh application logical document identity, EGW `Document`,
and worksheet node, writes seed registers to that fresh authority, derives the
spreadsheet projection through the shared path, then advances the local
`DocumentGeneration`. It does not clear properties in the existing CRDT
document or seed `Worksheet` directly.

Identity allocation and cross-peer routing are caller capabilities outside the
command value. The experiment does not invent a clock, random source,
serializer, transport, or replicated replacement protocol.

### 7. Keep identity and time domains distinct

These values are not interchangeable:

- application logical document identity chooses the collaborative document;
- `DocumentGeneration` rejects locally delayed commands across replacement;
- EGW replica and operation identities own causal history;
- EGW `Version` describes CRDT state;
- `incr` `Revision` describes reactive invalidation;
- dataflow `Epoch` describes progress in a separate execution model.

One application command may still lower to multiple EGW operations in a future
schema. Application command IDs, retry, and deduplication remain deferred.

### 8. Start with the current EGW reporting surface

The initial evidence baseline used EGW 0.4.0 public container APIs; Phase 5
revalidated the same boundary against published EGW 0.5.0. It does not use
`Document::transaction` as an atomic commit: that API groups undo history and
does not roll back document mutations when its action raises.

The current remote report gives operation counts rather than changed
properties, and properties are not enumerable. The baseline therefore scans
the known 50x50 address set after local or remote mutation and applies only the
purely computed diff. This bounded scan is an experiment baseline, not evidence
by itself that EGW needs another API.

For local mutation, the adapter preflights node liveness and reads the property
back after `set_property`. An already-equal desired register is success; a
different read-back is a structured application `MutationNotLanded` result.
EGW version movement may be evidence but does not replace value confirmation.
The result is not presented as an EGW receipt.

If Worksheet application fails after EGW has advanced, the application batch
rolls back, retained raw/semantic/diagnostic state remains unchanged, and a
later projection retries from the same authoritative EGW state. Unexpected
Worksheet result values must therefore enter a catchable projection-error path
rather than silently committing a partial frame.

The adapter records that checked property mutation and generic changed-entity
reporting may be candidate pressure points. It does not change EGW in this
plan.

### 9. Require evidence before an EGW proposal

The experiment records correctness outcomes, property-read counts, and release
mode scan/decode/diff/projection/end-to-end timings. A private adapter seam may
compare full scanning with synthetic changed-property hints, but it does not
establish a public generic abstraction.

An EGW API candidate requires all of the following:

1. the current-API adapter works correctly;
2. a reproducible correctness or material performance limitation remains;
3. the proposed shape contains no spreadsheet or `incr` semantics;
4. a second driver, such as Loom, confirms the same need;
5. the same convergence suite passes with and without the candidate;
6. the gain is quantified.

**API-quality checkpoint (2026-07-21, durable conclusions):** The current EGW 0.4
container API is sufficient for a correct adapter when the application supplies
liveness policy, mutation read-back, and full-scan impact discovery. Two narrow
candidates were evaluated and deferred:

- *Error-transparent property mutation:* `set_property` returns `Unit` and
  silently discards internal failure on contained targets. An additive checked
  setter or compatible future signature that exposes not-recorded/internal
  failure is a concrete candidate, but no second container driver confirms the
  same contract. A rich receipt (`Applied | AlreadyEqual | TargetDead`) is not
  advanced because its variants conflate operation recording, LWW, liveness,
  and projection semantics.
- *Conservative post-apply impact reporting:* `SyncReport` exposes operation
  counts, not changed entities. A conservative touched/impact report (node IDs,
  `(node, property-key)` pairs, text block IDs) is a research candidate, but
  its contract must resolve LWW losers, deduplication, pending operations,
  moves, trash, and ownership before proposal.

Neither candidate passes the six-part gate in §9: no second container driver
confirms the contract, and compatibility, convergence, and quantified-gain
evidence remain open. These conclusions are durable; reopening requires a
second driver, compatibility specification, convergence evidence, and
quantified gain.

Issue or API publication requires separate approval.

## Rationale

- Whole-submit commands make an atomic source register match current user
  intent; sequence text would choose new product semantics prematurely.
- One tagged property gives one conflict-resolution unit and avoids inconsistent
  presence/source combinations.
- A single authoritative projection path prevents local optimistic state from
  diverging from remote merged state.
- An owned snapshot creates a clean functional-core boundary around a mutable
  CRDT document.
- A bounded full scan proves current API sufficiency before optimization or API
  expansion.
- Keeping the adapter application-specific prevents two libraries from becoming
  coupled around one demo's schema and lifecycle.

## Considered options

### Store formula source as sequence text — rejected for the first experiment

It enables character-level concurrent editing but conflicts with whole-submit
commands and local-only drafts. It can merge fragments into a formula no user
submitted. Reopening this choice requires a collaborative formula-editor
product decision and a superseding ADR.

### Use one EGW node per cell — rejected

Sparse enumeration would be convenient, but concurrent creation can produce
multiple nodes for one logical address without a generic way to select the LWW
cell register across those nodes. A shared worksheet-node property gives one
register per address.

### Split source and deletion across properties — rejected

Independent LWW resolution can produce a torn combination. One tagged payload
keeps the state atomic.

### Use `Document::transaction` as command commit — rejected

Its contract is undo grouping, not rollback or distributed transaction
visibility. Calling it a commit boundary would overstate its semantics.

### Add changed-property reporting to EGW first — rejected

No benchmark or second driver yet proves that the full scan is material or that
a proposed report is sufficiently general.

### Create a generic `egw_incr` package — rejected

Only one application-shaped driver exists. Extraction remains gated on a
second repeated adapter contract.

## Consequences

- Plan 013 Phase 0 verified published EGW 0.4.0 in the standalone `incr`
  workspace, and Phase 5 revalidated the adapter against published EGW 0.5.0;
  neither result relies on a parent workspace override.
- The command types move to one importable application-domain package; no copy
  remains in the executable package.
- The adapter adds strict application-level register decoding, separate
  last-seen/last-good/diagnostic state, checked local mutation read-back,
  structured application results, and retryable projection failure semantics.
- Remote updates initially perform a bounded 2500-property scan.
- Bulk worksheet projection uses one outer `Runtime::batch` and must not call
  the existing single-operation `run_batched_op` inside it.
- Reset across networked peers remains unimplemented until application document
  routing is designed.
- `incr`, typed-spreadsheet, and EGW public APIs remain unchanged during the
  experiment.
- The experiment may conclude that no EGW improvement is warranted.

## Compatibility and API impact

The proposed packages are application-local and unpublished. Existing
`incr_tea`, `incr`, typed-spreadsheet, and EGW public contracts remain intact.
The command package promotion changes only how the demo's internal packages
share the already-established command vocabulary.

No EGW source, parent Canopy pointer, generic bridge, network protocol, or
published API is changed by this decision.
