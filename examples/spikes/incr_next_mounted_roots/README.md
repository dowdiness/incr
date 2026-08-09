# Incr Next mounted roots

- **Reader:** Incr maintainers reviewing the active-root seam after #465.
- **Decision:** Evaluate a typed `Store::mount(View[V]) -> Result[Mount[V], MountError]` without adding a production API or an erased dependency registry.
- **Keep until:** The mounted-root direction is accepted, rejected, or superseded.
- **Disposition:** Keep this checked spike as evidence; preserve any durable conclusion in an ADR or remove the spike afterward.

## One question

Can a long-lived typed root observe the same current outcome as Fresh after every
semantic turn while Incremental selectively reruns only roots whose private
transitive wake footprint is touched?

The answer is **provisional until final validation**. This is finite executable
evidence, not a proof of an admissible graph or a production-kernel proposal.
Run:

```bash
bash examples/spikes/incr_next_mounted_roots/run.sh
```

## Boundary and ownership

The functional core is the deterministic pull evaluator: typed `View` recipes,
Region-lifetime validation, Source/Query reads, cycle witnesses, cutoff
backdating, dependency verification, and `(State, Event) -> State/Decision`
transitions. The imperative shell owns clocks, transaction commit/rollback,
Region close, the active runner registry, scheduling, and disposal.

`Fresh` is the oracle. It owns no memo and never verifies or memoizes. A
successful nonempty commit and every first successful close of every Region
rerun **all** active Fresh mounts once. `Incremental` runs selected active
mounts once after a successful nonempty commit and selects Region close using
that Region's pre-seal `RegionLifetime` token. Empty commits, rollback,
poisoned/rejected operations, duplicate/rejected close, and explicit eviction
are quiet.

Each provider owns a private `MountCore[V]` with a typed recipe/current result,
runner, counters, and debug footprint lengths. The allowed erased structure is
only `MountId -> () -> Unit`: an active runner registry owned by the Store.
Incremental additionally owns a private token-to-MountId index for selection.
The forbidden design is an erased Query/memo/key registry or subscriber edge;
no such structure authorizes or identifies a mount.

`Mount` exposes only `id`, `current`, `debug`, and idempotent `dispose`.
Creation validates cross-store ownership, Region lifetime, and global phase
**before** allocation, registration, or evaluation. `current` is
`Result[Result[V, ReadError], MountError]`; disposal clears the runner, the
Mount-owned root View reference, current value, and footprints, and later turns
cannot run it. Query definitions remain Region-owned until Region close. `MountError`
includes `CrossStore`, `ClosedRegion`, `MountDuringEvaluation`,
`MountDuringTransaction`, and `DisposedMount`.

## Wake tokens and proof state

The private `WakeToken` vocabulary is:

- `Source(SourceId)` for a successful Source access;
- `RevisionClock(StoreId)` for `EvalCtx::revision`;
- `RegionLifetime(RegionGeneration)` before every root/nested lifecycle
  validation.

An Incremental memo stores its value, dependency trace, `verified_at`,
`changed_at`, and current transitive wake set. A failed Query recompute
preserves that authority and installs no attempt trace. Separately, the active
Mount retains the last-good tokens and the latest failed attempt; their union
provides wake liveness. A later success replaces the last-good set and clears
the failure set. `RecomputeRequired` never updates memo authority. Fresh records
analogous Mount evidence for parity and debug but never uses it to skip a run.

Dependency verification returns the dependency's **current** transitive
footprint, not the stale footprint captured by the parent. A green parent
therefore replaces `last_successful_footprint` while preserving its value and
`changed_at`. This is required when a child changes dynamic branch from A to B
but cutoff backdates an equivalent result: A no longer wakes the parent, B does.
Direct revision dependencies return `RevisionClock`; the enclosing root or
nested View traversal independently contributes its own Region lifetime.

Cutoff is a direct-observer contract. The declared `Eq`/`CutoffEq` relation may
only say equal when all admissible downstream observations are equivalent. A
successful cutoff-equivalent recompute installs the newest metadata/value while
preserving `changed_at`; it does not license arbitrary predicates.

Eviction forgets only one typed Incremental memo entry. It does not advance a
clock, wake a mount, pin a memo, retain a tombstone, or create a subscriber
edge. A later relevant wake may rematerialize the recipe conservatively. Root
and child eviction are quiet; disposal is the only mount ownership release
operation.

## Caller contracts and non-goals

Values and keys are snapshot-safe, stable under `Eq`/`Hash`, and obey their
provider's declared downstream observer contract. Mutable aliases are an
intentional excluded counterexample. Callers must retain the typed `Mount` and
explicitly dispose it; the spike supplies no weak references or background GC.

Non-goals: production naming or integration, callbacks, passive subscribers,
parallel evaluation, automatic LRU/capacity policy, pins/weak references,
iterative verification, memo persistence, erased Query/key lookup, or a
selective Fresh scheduler.

## Evidence coverage

The consumer's parity workloads compare normalized Fresh/Incremental mount
outcomes after each relevant turn and check initial evaluation; unrelated and
multi-source commits; RevisionClock invalidation; empty/rollback/rejected turns; per-Region close
selectivity and duplicate close; dynamic branch replacement; prior-success
failure/Cycle retry and recovery; direct and child cutoff backdating; root and
child eviction/rematerialization; disposal; and mount creation rejection during
evaluation and transaction. A recipe-triggered disposal probe also verifies
snapshot runner iteration and prevents post-evaluation state resurrection.
Incremental counters assert selectivity; Fresh
counters deliberately show all-root reruns. Native RC evidence separately
checks runner/index removal, View-key/current ownership, the separate
Region-owned Query recipe lifetime, successful and failed footprint state
transitions, quiet eviction, Region close wake, and idempotent disposal. Native external-object finalizers measure ownership paths.
WakeToken arrays contain only values, so private debug counts and interface
guards provide the corresponding array/index release evidence.

## Existing API First

The spike reuses the project/core `Map::get/set/remove/contains/each/to_array`,
`Array::each/fold/filter/dedup/copy`, `Option`, `Result`, `Ref`, `Hash`, and
`Eq` APIs. `Set`/`HashSet` was checked but is unnecessary because the existing
Maps already provide typed deduplication, ownership, and runner selection.
`String`/`StringView` serve evidence formatting only. `Bytes`/`BytesView`,
`Buffer`/`StringBuilder`, and `cmp`/`math` were checked but do not fit a typed
identity scheduler with no byte transformation, builder, ordering, or numeric
algorithm. No new collection abstraction or erased subscriber API is
introduced.
