# Incr Retention Redesign — First-Principles Decision Record

**Date:** 2026-08-05

**Reader:** Maintainers deciding whether to commission the retention redesign
proposed in the companion proposal; implementers of any later prototype, who
must treat the D-decisions as binding for that track and the V-items as open
evidence obligations.

**Decision:** Preserve as the decision record of the design session that
reviewed the companion proposal. These decisions bind the redesign track only;
they do not commission a kernel replacement and do not change the current
public API.

**Keep until:** The redesign track is commissioned (distill the durable
decisions into ADRs and retire this note) or rejected (record the rejection
rationale in an ADR and delete this note).

**Disposition:** Gated design-session record. Supersedes the "blocking design
findings" section of the
[session handoff](2026-08-05-retention-redesign-session-handoff.md) by
resolving or converting each finding into a decision (D) or verification
obligation (V).

**Amended:** 2026-08-05 — independent review by `openai-codex/gpt-5.6-sol`
(fresh session, read-only, no prior context). Several decisions below are
reopened or amended by that review; each carries an explicit status marker.
The full review text is ephemeral (`/tmp/sol-independent-review-retention.md`);
its substantive findings are inlined where they changed a decision.

**V12.5 resolved:** 2026-08-05 — compile evidence is preserved on the
throwaway branch
[`spike/v12-5-view-alternatives`](https://github.com/dowdiness/incr/tree/spike/v12-5-view-alternatives/examples/spikes/v12_5_view_alternatives),
commit [`a48bdc9`](https://github.com/dowdiness/incr/commit/a48bdc9). The probe
selects the two-layer alternative and keeps Cycle recoverable at the opaque
kernel boundary; see D2 and V12.5.

**Provenance:** English translation (2026-08-05) of
`/tmp/incr-retention-first-principles-decisions-2026-08-05.md` (original
SHA-256:
`32ec8267815cd23276f03d9db21710c2d8db8e6d06abdbf606b84be6f2183ab3`). The
translation replaces the earlier verbatim Japanese repository copy; content
is unchanged apart from language.

**Related documents:**
[retention API redesign proposal](2026-08-05-retention-api-redesign-proposal.md),
[session handoff](2026-08-05-retention-redesign-session-handoff.md)

---

- Date: 2026-08-05 (JST)
- Positioning: a record that derives and settles, from first principles, the
  open questions raised by the critical review of the
  [proposal](2026-08-05-retention-api-redesign-proposal.md). The proposal
  itself is not modified.
- Related artifacts:
  - Proposal: [2026-08-05-retention-api-redesign-proposal.md](2026-08-05-retention-api-redesign-proposal.md)
  - Handoff: [2026-08-05-retention-redesign-session-handoff.md](2026-08-05-retention-redesign-session-handoff.md)
- Verification basis: actual code in `deps/loom/incr/incr/` (read_error.mbt /
  scope.mbt / runtime.mbt / internal/pull/memo_data.mbt /
  internal/shared/cell_meta.mbt / traits.mbt / derived_facade.mbt) and the
  official MoonBit docs (operator overloading).

This record has three layers.

1. **Decision (D)**: judgments settled in this session. They are not changed
   unless counterevidence appears. Items the independent sol review reopened
   or amended carry an explicit **Status: reopened** / **Status: amended** /
   **Status: provisional** marker; unmarked items stand as settled.
2. **Rationale (P)**: the principles from which the decisions were derived.
   Objections to a decision must first be addressed to this layer.
3. **Verification obligation (V)**: obligations to confirm a decision's
   premises by measurement or tests. Until evidence exists, the decision is
   not "accepted".

---

## 0. Immovable premises

- **P0.1 Execution environment**: the memory model differs by target — the
  native/C backend uses reference counting; wasm-gc uses the host garbage
  collector (evidence:
  `docs/performance/2026-07-15-retention-cost-attribution.md` treats wasm-gc
  and native as distinct targets). There are no weak references or
  finalizers in the public API. Single-threaded. Retention arguments must be
  designed for the RC lower bound (native), and benchmarks must cover both
  native and wasm-gc. *(Amended by the sol review: the original wording
  "MoonBit uses RC" overgeneralized.)*
- **P0.2 Purpose**: when an input changes, the values you read become correct
  on their own. Callers neither need nor have the authority to know the
  machinery (graph, revision, root, GC).
- **P0.3 Minimum correctness requirements**: a read returns a snapshot of one
  revision. At most one **successful** recomputation of the same computation
  per revision. Subscriptions run exactly once, glitch-free.
- **P0.4 Dominant load shape (Canopy)**: one hot input (the source being
  edited) + many views + keystroke-frequency writes.

Facts verified in code (during the review):

- The current `Scope::collect()` → `Runtime::gc()` is a runtime-wide
  mark-and-sweep (`scope.mbt:151`, `runtime.mbt:785`). The proposal's §13
  motivation is real.
- The current kernel gives every cell a reverse edge
  `subscribers : HashSet[CellId]` (`internal/shared/cell_meta.mbt`). Removing
  these from passive nodes is a kernel change.
- The current pull verification (`verified_at` + deep verification of
  dependencies) is already implemented
  (`internal/pull/memo_data.mbt`). The proposal's §9 is not new machinery but
  a restatement of what exists.
- The current `Runtime::gc` is not triggered from the read path. The only
  call sites are `Scope::collect` and tests. The proposal's §12 example of "a
  getter that runs GC" is not the current behavior.
- The current `create_input` / `Input::Input` has no `Eq` bound. The
  proposal's §16 `Store::input[T : Eq]` is a regression.
- The current `Derived::fallible` caches domain failures as `Result[V, E]`
  values. This is the design already settled by
  `docs/design/specs/2026-05-28-honest-read-error-ownership.md`.
- The current `Runtime::batch` rolls back pending writes when the closure
  raises.
- `Lifetime::expose()` does not exist in this checkout of incr/loom. The
  proposal's final-direction section depends on an undefined reference.

Additional facts verified by the independent review (sol, 2026-08-05):

- `Input::set` requires `T : Eq` and suppresses equal writes; `force_set` is
  the non-`Eq` always-write path (`incr/cells/input.mbt`). Input creation
  has no Eq bound, but the write path does.
- Cycle reads are currently **recoverable**:
  `incr/cells/current_model_wbtest.mbt` contains a test where a self-cycle
  returns `Err` and the computation catches it and continues.
- The F7 keyed-retirement problem (entries vs surviving dependents) is
  already documented as open in
  `docs/decisions/2026-07-14-retention-followup-tracks-gated.md` and
  `docs/research/2026-07-14-bonsai-informed-incr-core-direction.md`.
- Custom backdating (`BackdateEq`, `Derived::with_backdate`) exists and is
  part of the equality-cutoff surface
  (`docs/design/comparison-with-salsa.md`).

---

## 1. Root decision: where value identity lives

### D1. Identity in the passive layer is "computation" (a closure owns the state). Identity in the active layer is "record" (the Store holds the record).

**Status: provisional** — retained as the working direction, but the sol
review recorded unresolved objections (below) and the RC proof obligation
V12.4.

**P1.1** Under RC, "alive" means reachable from a root. A value visible to
callers should live exactly as long as it can be observed, and die the moment
it can no longer be observed.

**Derivation**: there are only two ways to place value identity.

- (A) Registration (an ID in a table inside the Store / Jotai atom / Salsa
  memo): addressable, but the Store has no choice but to retain it, and under
  RC without weak references, reclamation collapses into manual GC or LRU.
  This is exactly the problem the current incr suffers from today.
- (B) Computation (a closure owning the state): retention aligns with
  reachability automatically. Addressability is lost.

Covering everything with only one of the two breaks. Passive values only need
to live while they may be read, so (B) satisfies the requirement; Effects,
subscriptions, and keyed families have continuing activity and need records
per (A). No other placement satisfies both requirements at once.

**Consequence**: the proposal's two-layer split is promoted from "assertion"
to "derivation". Every later decision derives from D1.

**Objections recorded (sol review)**:

- The derivation conflates identity, addressability, and ownership. A
  closure-owned state can still carry an internal ID; a Store-managed record
  need not imply permanent Store ownership. "Only two placements" is a false
  dichotomy: opaque handles with explicit release, scope/epoch ownership,
  and active-overlay records are additional designs.
- P1.1's equivalence of liveness and reachability holds only for acyclic
  owned graphs. Under RC, an unreachable cycle can remain allocated, and the
  acyclicity of the owned graph is asserted, not proven. Candidate cycles:
  state → cached value → getter → state; mutually recursive getters through
  `Ref`; deferred-write records capturing Store-owned capabilities.
- Lexical captures in compute closures retain inactive branches even after
  dependency diffing (handoff finding #2), so "dropping the getter releases
  the state" holds only for the state itself, not for everything the compute
  closure mentions.
- Transparent closures erase provenance from the public type, making
  identity-based update, dump, labeling, and composition harder (see D2, D8,
  and V12.5).

---

## 2. The error channel

### D2. The kernel-facing View is opaque and returns `Result[T, ReadError]`; product modules may adapt it to local callable closures. Cycle remains recoverable, and domain failures remain values.

**Status: resolved by V12.5** — compile evidence is on
`spike/v12-5-view-alternatives` at `a48bdc9`; an independent
`moonbit-reviewer` passed the scoped verdict.

**P2.1** Error ownership is chosen by the caller that can act on the error:

domain failures are cached inside `T` as `Result[V, E]`; graph mechanism
errors such as Cycle remain in the kernel read result; a product-local
aborting convenience is explicit and opt-in.

**V12.5 evidence**:

- A transparent `() -> T` is callable, but the compiler confirms it has no
  `id()`/provenance/label seam and cannot be distinguished from an arbitrary
  thunk.
- An opaque handle retains `CellId`, `RuntimeId`, labels, diagnostics, and
  `get() -> Result[T, ReadError]`, but the compiler confirms it is not
  callable (error 4014: wanted function type).
- The two-layer alternative retains the opaque handle and creates local
  closures for product composition. It therefore supports both an honest
  `() -> Result[T, ReadError]` and an explicitly aborting `() -> T` without
  weakening the kernel contract.
- A setter closure alone cannot recover its cell or current value (error
  4015); write/update capabilities must be created alongside the input or
  attached to an opaque input token.
- The existing recoverable self-cycle behavior compiles and passes through
  the opaque handle and product-local honest getter.

**Decision**:

1. The public kernel contract is a nominal/opaque View with
   `get() -> Result[T, ReadError]`, stable identity, Runtime provenance,
   labels, and diagnostic access. It is not callable.
2. Cycle remains recoverable. `ReadError::Cycle` stays in the kernel read
   result. The redesign does not replace it with unconditional abort.
3. Domain failures remain value-level `Result[V, E]`, separate from
   `ReadError`.
4. Product modules and UI adapters may create local callable closures:
   honest `() -> Result[T, ReadError]` by default at quarantine boundaries,
   or an explicit `() -> T` aborting convenience where that policy is
   intentional.
5. Product code retains the opaque handle whenever it needs diagnostics,
   teardown, update, or cross-Store checks. Cross-Store policy remains a
   separate V12.8 decision; the handle preserves enough provenance to
   diagnose or reject composition before invoking the current aborting
   kernel path.
6. Input creation returns write/update capabilities together. V12.5 proves
   the representation; atomic and re-entrant update semantics remain open.

**Consequences**:

- Reject `View[T] = () -> T` as the sole public kernel interface.
- The proposal's `document()` syntax becomes a product-local adapter, not
  the kernel type.
- No `raise` effect is required for graph reads; recoverability is represented
  as an ordinary `Result` return value.
- D1 remains provisional: V12.5 selects an interface seam, not the ownership
  or retention implementation behind the opaque handle.

---

## 3. The model of time

### D3.1 A batch is "one revision step", and a failed batch leaves no step behind (rollback).

**Status: amended** — rollback holds, but only in a narrower sense than the
original wording implied (see correction below).

**P3.1** A Store is a single timeline. A write means advancing the timeline
by one. A batch folds multiple writes into one step.

**Derivation**: if a batch whose closure raised left a step behind, that
contradicts the definition of "one step". Rollback is not a feature but the
definition. If rollback is not implemented, it must not be called a batch.
The current `Runtime::batch` already implements rollback, so this is
preservation, not new implementation.

**Reflection into the proposal**: add rollback semantics to the batch
description in §16 ("treat multiple updates as one revision").

**Correction (sol review)**:

- Rollback covers **staged Store input writes only**. External side effects
  performed inside the batch closure, mutation through aliased values, and
  `abort()` (uncatchable) are not rolled back; `incr/cells/batch.mbt`
  documents this. The claim must be worded as "failed batches roll back
  staged writes", never as transactional.
- The proposal's `batch(action : () -> Unit)` signature is non-raising,
  which makes catchable failure — the trigger for rollback — unreachable.
  The API must use a polymorphic raise signature like the current
  `Runtime::batch` (`() -> Unit raise?`).

### D3.2 A setter during compute aborts. A setter inside an Effect body is allowed but deferred until the dispatch completes.

**P3.2** A passive computation is the act of "reading the snapshot of
revision N". Advancing the timeline mid-computation would make one
computation mix two revisions, breaking P0.3.

**Derivation**: keep the passive layer as pure functions and put the deferred
handling of writes in the active layer (the shell). This is a direct
application of Functional Core / Imperative Shell.

**Reflection into the proposal**: add "a setter during compute aborts" to the
invariants in §17.

---

## 4. Retention: cleanup and breakers

### D4.1 Cleanup exists only for "acts that carry information". Passive values are never asked to dispose.

**P4.1** The only justification for cleanup is stopping something that keeps
running or keeps holding external resources after it is no longer read. A
value that is merely read is reclaimed by RC the moment it is no longer read
— the user action demanded there carries zero information, and demanding it
is wrong.

**Consequence**: the proposal's principle 7 is grounded by this principle.

### D4.2 Every reference cycle the design creates must have exactly one "breaker". The breaker must be an explicit handle held by the user.

**P4.2** Under RC without finalizers, a cycle reachable from a root lives
forever.

**Derivation (checking the existing cycles)**:

- The Effect cycle (`Stop → Store → mount table → effect → getter → state →
  StoreCore`): the breaker is `Stop`. As in the proposal.
- The whole-Store cycle: dropping the Store handle still keeps the entire
  island alive as long as one mounted effect remains. The current proposal
  has no Store-level breaker.

**Reflection into the proposal**: the problem that the new design silently
removes the retreat route equivalent to `Scope::dispose` is solved by D4.3.

### D4.3 Introduce `store.close()`. It stops all Effects and freezes the revision. Afterwards setters abort and getters keep returning the final values.

**Derivation**: reads keep working after close because the passive layer is
pull-only and verification holds as long as the frozen revision exists (a
consequence of D1). This achieves teardown without breaking the proposal's
invariant 1 (a live getter does not become Disposed). A closed Store has the
clear semantics of a "read-only snapshot".

**Refinements recorded (sol review)**:

- "Exactly one breaker" (D4.2) conflicts with both `Stop` and `store.close()`
  being able to break the same Store/effect cycle. The rule should read "at
  least one designated breaker, with a defined precedence".
- `Stop` must specify which fields are cleared; removing only the table
  entry can leave callback/Stop self-capture cycles alive.
- "Getters return final values after close" needs precision: an uncomputed
  getter may still compute lazily after close. `close()` freezes inputs and
  revision; it does not materialize a complete snapshot.
- Effect cleanup is underspecified: `() -> Unit` cannot express cleanup that
  runs before re-run or on stop (contrast Jotai's mount cleanup). The Effect
  contract is obligated in V12.6.

### D4.4 State explicitly that forgetting to stop an Effect is a permanent leak of the whole Store, and make mount-record balance tests a CI obligation.

**P4.3** In an environment without finalizer rescue, leaking an active
resource is never partial.

**Reflection into the proposal**: pin invariant 8 as a CI test (create/destroy
stress).

---

## 5. The wake-up model

### D5. The mount table holds, per Effect, **the transitive set of input leaves reached by the last run — including through cached views**. On an input change, wake via that set and re-run only what pull confirms changed. After each re-run, diff-update the set.

**Status: amended** — the wake-up set definition is corrected below after a
counterexample from the sol review; the strategy choice (wake by registered
set rather than poll-all or passive reverse edges) stands.

**P5.1** Wake-up cost must be proportional to the actual invalidation, not to
the size of the store.

**Derivation (choosing the strategy)**: three candidates.

- P1 = poll every Effect on every revision: under P0.4's dominant pattern
  this means "verify the dependency closure of every Effect on every
  keystroke" = linear degradation. Rejected.
- P2 = wake via the set of inputs read last time: wake-up is O(subscribers
  of X). Adopted.
- P3 = reverse edges on passive nodes: forbidden by D1.

**Sound Wake-up Theorem (corrected)**: let S be the transitive set of input
leaves reached by the previous run — collected by traversing the verified
dependency metadata of every getter the run touched, **including cached
views that returned without re-executing**. Then S is a complete propagation
path for any change that can alter the output of the next run.

**Counterexample that forced the correction (sol review)**:

```moonbit
let v = store.computed(() => x())
ignore(v())                          // v is now cached
let stop = store.effect(() => render(v()))
```

If the wake-up set recorded only inputs *physically called during the effect
run*, the run calls `v`, gets the cached value, never touches `x` — the set
is empty and a change to `x` can never wake the effect. The snapshot must be
built by recursive traversal of cached dependency metadata (or by forced
re-evaluation), not by the tracking log alone.

Grounds (unchanged): passive getters are pure (D3.2). The values read next
time, and the control flow, are a function of the values read this time. For
an input x not in S to affect the output, a getter reading x must be called,
but the control-flow change leading to that call can only be caused by a
value change delivered through S.

**Premises the theorem depends on (sol review; each must be enforced or
tested)**:

1. every reactive influence enters through a Store input;
2. view computation is pure, deterministic, terminating, and reads no hidden
   mutable state;
3. input values cannot be mutated through aliases without a setter (see the
   mutable-return-value trade-off, §13 item 12);
4. the snapshot contains transitive input leaves, including through cached
   views (the correction above);
5. cached dependency metadata is current and traversable;
6. the mount record also retains direct view dependencies needed for
   equality cutoff;
7. effect dependency discovery and edge replacement are atomic under abort;
8. effect callbacks cannot observe output changes before dependency
   verification completes.

**Note: this theorem depends on getter purity.** "Getters perform no I/O,
callbacks, or writes" (the proposal's invariant 10) is not etiquette but a
correctness condition, and the invariant's status should be upgraded.

**Dynamic dependencies**: the dependency set changes only during a re-run;
diffing and re-registering after each re-run keeps the registration exact.

**Glitch-freedom and ordering**: Effects cannot read each other's outputs (if
they want to, it should be a view) = there is no functional dependency
between Effects. Running each Effect once, in registration order, each
reading a verified snapshot, is deterministic and glitch-free.

**Additional objections recorded (sol review)**:

- "The only implementation" was overstated. An active-only reverse overlay
  stored in mount records (reverse edges between active records, none on
  passive nodes) is compatible with D1 and preserves shared topology; many
  Effects over one deep shared view can make flattened input→effect sets
  proportional to the transitive closure, trading update scans for larger
  mount tables. The strategy choice remains P2 vs active-overlay, to be
  decided by V12.1 measurements.
- "Re-run only what pull confirms changed" cannot be implemented from the
  leaf set alone; the scheduler also needs the previous direct getter states
  (or must run the effect to rediscover them).
- Registration-order execution does not by itself prove glitch-freedom when
  deferred effect writes trigger subsequent revisions (see D3.2 and V12.6).

**Reflection into the proposal**: concretize §10's "dirty-propagate only
mounted edges" with this snapshot strategy, using the corrected transitive
wake-up set.

### V5.1 Write differential-oracle tests for the wake-up theorem and the mount-table diff updates.

Compare old and new using the current kernel as the semantic oracle. Minimum
scenario set:

- dynamic branch switch (a mode switch removes old dependencies from the
  wake-up set)
- wake-up order by Effect registration order
- mount-record balance after stop
- diamond, chain, many independent roots
- one hot input + many unrelated inputs
- the pre-cached nested-view counterexample (an effect subscribing through
  an already-cached view must still be woken by the view's inputs)

---

## 6. Keyed derivation and advanced APIs

### D6.1 The key set is an ordinary value returned by a view. A family retains entries only for keys contained in the key-set view; entries whose key falls out of the set are released at the next recompute.

**Status: reopened** — membership-as-data is retained as the direction, but
it does not by itself solve the retirement problem it claimed to solve (see
below).

**P6.1** Entry liveness must match the liveness of whatever can observe the
entry (re-application of D1).

**Derivation**: "who owns the current key set" becomes a hard question only
when the key set is treated as a managed resource. If the key set is data,
bounded retention is decided declaratively by data instead of by an LRU
heuristic. In Canopy the block set is data anyway.

```moonbit
let blocks = store.computed(() => block_ids_of(document()))
let previews = store.family(blocks, key => render_block(key))
```

LRU is demoted to an auxiliary means for externally sourced key streams
(logs, etc.) whose membership cannot be expressed as data.

**Correction (sol review)**: membership loss does not decide what happens
when an entry's getter — or a downstream computation built on it — is still
live. Either the entry stays alive (membership removal releases nothing), or
it is forcibly retired (violating the live-getter guarantee). This is the
already-documented open F7 problem
(`docs/decisions/2026-07-14-retention-followup-tracks-gated.md`,
`docs/research/2026-07-14-bonsai-informed-incr-core-direction.md`). A valid
family API must either restrict exposure of per-entry handles or define
tombstone/aggregate retirement semantics. D6.1 cannot be accepted before F7
is resolved.

### D6.2 Accumulator and Relation (datalog) remain named-handle advanced APIs; they are not folded into the getter layer.

**P6.2** Reducibility to getters is decided by the essential shape of the
feature. An accumulator is essentially a graph-shaped aggregation and cannot
be reduced to getters.

**Constraint**: during the kernel replacement, do not shape `DerivedState`
such that accumulated queries cannot be added later. Only this is decided
now; the detailed design is deferred.

### D6.3 The proposal's §16 covers only input/view/effect/batch. Without a mapping for the current facades `InputField` / `InputFieldOwner` / `EagerDerived` / `ReachableDerived` / `DerivedMap` / `Accumulator` / `on_change` / evaluation hooks, Canopy adoption is impossible.

**Grounds**: what Canopy/loom actually use are DerivedMap and Accumulator.
The missing mapping is a design blocker.

---

## 7. Verification cost

### D7.1 Port durability to the new kernel. Do not build a change journal / revision summary until benchmarks demand it.

**P7.1** A read should cost O(changes), not O(graph). But no new machinery is
built before measurement (perf-investigation principle).

**Derivation**: durability is the existing implementation of "skip
verification for unrelated input changes" and is orthogonal to retention.
There is no reason not to port it. The proposal's "add a journal after
measurement" actually means "throw away the existing durability and rebuild
it later" — the order is reversed.

**Caveats recorded (sol review)**: durability is not wholly orthogonal or
free — dynamic dependencies determine memo durability, synthetic accumulator
dependencies disable the shortcut, and durability distinguishes change
classes rather than arbitrary unrelated inputs at the same durability level.
The redesign must also preserve custom backdating (`BackdateEq`,
`Derived::with_backdate`), not merely `Eq` plus a no-backdate escape hatch.

---

## 8. Observability

### D8.1 Debug information is not maintained continuously; it is generated on demand by traversing from live anchors (the mount table + handles passed by the user). Labels are stored in state as optional creation-time arguments.

**P8.1** Under RC without weak references, a "registry of all views" makes
the registry itself a root and reintroduces the retention problem that was
just solved.

**Derivation**: `store.dump()` = a reachability traversal from the mount set.
Traversal starts at "live anchors", consistent with the breaker concept of
D4.2.

**Reflection into the proposal**: add a `label?` optional argument and a
dump-family observation API to the §16 API. Replace the functionality
corresponding to the current `Derived::id` / `dependencies` / `gc_root_count`
/ introspection in a form that does not break retention.

**Scope correction (sol review)**: D8 covers snapshots of the mounted graph
only. A Store cannot extract hidden state from an arbitrary user-held
`() -> T`, so unmounted passive getters are invisible to `store.dump()`;
invoking user getters to discover them is unsafe because purity is not
enforced. Without passive reverse edges, traversal cannot reproduce
`Runtime::dependents`. And snapshot traversal does not replace the current
event-observability contract (derived-event listeners expose ordering,
timing, aborts, and backdating, and are consumed by
`examples/incr_tea/renderer_js.mbt`). Event observability needs its own
decision.

---

## 9. Minor decisions

| Item | Derivation | Decision |
|---|---|---|
| `input` Eq bound | Input **creation** has no Eq bound, but `Input::set` requires `T : Eq` (equal-write suppression) and `force_set` is the always-write path | **Amended**: creation stays unbounded; the returned setter must declare which write semantic it carries — equality-suppressing `set` (needs Eq) or `force_set`. A bare `(T) -> Unit` hides this choice |
| `view` Eq | Cutoff is a meaningful optimization, but not every T has Eq | Eq by default + an escape hatch equivalent to the current `derived_no_backdate` from day one |
| cross-store | Opaque handles preserve RuntimeId provenance; current kernel misuse aborts dynamically | **Open (V12.8)**: decide prohibition/bridges/coordinated batches/shared Store. V12.5 proves the handle can diagnose or reject before invoking the current aborting path |
| naming | In a projectional-editor codebase `view` is an overloaded word. The proposal itself criticizes the overloading of `Node` | `computed` as the first candidate (`derived` collides with the old facade name and causes migration confusion) |
| setter read-modify-write | `(T) -> Unit` structurally permits races with stale reads. In CRDT-style remote updates the update shape is essential | **Representation resolved by V12.5; semantics open**: `store.update(setter, f)` is infeasible because the Store cannot recover cell identity/current value from a closure. Return `update : ((T) -> T) -> Unit` alongside input creation or attach it to an opaque input token; atomic and re-entrant semantics remain for production design |

---

## 10. Decision dependencies

```
D1 value identity (passive=computation / active=record)
 ├─ D2 opaque kernel View + product-local callable adapters
 ├─ D3 time model → batch rollback / setter-during-compute aborts
 ├─ D4 breaker principle → Stop / store.close()
 ├─ D5 wake-up theorem → mount table = set of inputs read last time
 ├─ D6 keyed = membership is data / Accumulator is an advanced API
 ├─ D7 keep durability, defer the journal
 └─ D8 observability by traversal
```

The order of implementation judgments follows this order too. If
counterevidence overturns D1, everything downstream is re-examined. As of
the 2026-08-05 amendment, D2 is resolved by V12.5, D6.1 remains reopened,
and D3.1/D5/D8 are amended, so only the downstream edges through unresolved
or provisional items remain conditional.

---

## 11. What is not decided now (legitimately deferred)

Only what does not constrain the kernel is legitimately deferred:

- **Change journal** (D7): waiting for benchmarks. Leaves no trace in the
  API.
- **Persistence / rehydration**: essentially incompatible with the
  closure-handle model, but also a feature that does not exist today. Ignore
  until a requirement appears.
- **Multi-Store bridging**: with cross-store aborting, crossing stores can
  only mean "mirror an input into the other Store" by manual
  synchronization. **Escalated by the sol review**: product modules that
  each hide a Store cannot compose transparently under
  abort-on-cross-store; the composition model (prohibition / bridges /
  coordinated batches / shared Store) must be decided before such modules
  are written. See V12.8.
- **Accumulator / datalog detailed design** (D6.2): only the "can be added
  later" shape is decided now.

---

## 12. Verification obligations (V) list

These confirm the premises of the decisions with evidence. Until evidence
exists, they are not "accepted".

- **V5.1**: differential-oracle tests for the wake-up theorem and the
  mount-table diff updates (see §5).
- **V12.1**: release benchmarks for hot input + many mounted views. Confirm
  by measurement the very premise (P0.4) on which D5 chose P2. Minimum set:
  chain / diamond / many independent roots / hot + unrelated inputs /
  2500-block Markdown / getter churn, run with `moon bench --release`.
- **V12.2**: leak detection for the Store ↔ mounted-effect cycle. Stress
  tests pinning that mount-record counts and reachability balance in the
  forgotten-stop scenario (D4.4).
- **V12.3**: semantic parity matrix against the old kernel. Before Phase 2
  (kernel replacement), build the differential-comparison harness with the
  current kernel as oracle (addresses handoff finding #6). **Scope extended
  by the sol review**: the matrix must cover every current facade and hook —
  `AcceptedDerived`, `Expr`, `InputView`, `Freshness`, `RuntimeContext`,
  Accumulator, DerivedMap, push cells, Datalog, custom backdating, listener
  registries, introspection, and event ordering — not just scalar
  `Derived`/`ReachableDerived` value correctness.
- **V12.4**: complete ownership graph + RC argument (sol review question 1).
  Enumerate compute captures, cached values, dependency arrays, StoreCore,
  mount records, Stop, close, deferred-write queues, and keyed entries;
  prove or test acyclicity of the owned passive graph. D1 stays provisional
  until this exists.
- **V12.5 — RESOLVED 2026-08-05**: interface-alternative compile probes.
  Evidence: throwaway branch `spike/v12-5-view-alternatives`, commit
  `a48bdc9`; positive probes passed `moon check`, wasm-gc release tests
  (1151/1151), and JS tests (256/256); three negative compiler probes pinned
  opaque-call, closure-metadata, and setter-only-update limitations. Verdict:
  two-layer interface; opaque kernel View with recoverable
  `Result[T, ReadError]`, plus product-local callable adapters. See D2.
- **V12.6**: full Effect contract scenario tests (sol review question 5):
  initial-run failure, cleanup before re-run and on stop, deferred-write
  queue ordering and self-trigger limits, nested batches, cancellation
  during dispatch, stop/close idempotence.
- **V12.7**: benchmarks on **both** native (RC) and wasm-gc (host GC)
  targets — extends V12.1, which must not be run on a single target.
- **V12.8**: explicit multi-Store composition decision (prohibition /
  bridges / coordinated batches / shared Store) before product modules
  encapsulate independent Stores.
- **V12.9**: pin external comparison evidence — exact Jotai and Duplix
  commits and source excerpts — before using either as architectural
  justification (the current citations are moving URLs without pinned
  revisions).

---

## 13. Reflection list into the proposal (diff)

The changes this decision record requires in the
[proposal](2026-08-05-retention-api-redesign-proposal.md):

1. §16 API: replace `View[T] = () -> T raise ReadError` with an opaque
   kernel View whose `get()` returns `Result[T, ReadError]`; document
   product-local callable adapters separately (D2/V12.5). Do not claim the
   opaque type itself supports `view()`. Keep input creation unconstrained,
   make the write semantic explicit, preserve a no-backdate escape hatch,
   consider `computed` naming, add `label?` and `store.close()`, and state
   staged-write rollback for `batch`.
2. §9: state that the "pull verification algorithm" is a restatement of the
   current kernel, and write down the real diff (moving state ownership /
   abolishing passive reverse edges / abolishing GC). Keep durability in
   DerivedState.
3. §10: rewrite the mount table with D5's snapshot strategy. State the
   wake-up theorem and its dependency on purity.
4. §11: rewrite keyed caches with D6.1's membership approach.
5. §12: note that the "getter runs GC" example is not the current behavior.
6. §14: delete the duplicated row (Effect ×2).
7. §15: rewrite per D2/V12.5. Domain failures are value-level `Result`s;
   kernel reads return `Result[T, ReadError]` so Cycle remains recoverable;
   product-local aborting closures are explicit conveniences, not the kernel
   contract.
8. §17: add invariants — setter-during-compute aborts / setter-in-Effect
   deferral, upgrading getter purity to a correctness condition, the
   post-close read guarantee, the CI obligation for mount-record balance.
9. §18: insert the V12.3 oracle phase before Phase 2 of the phase plan. Note
   that Phase 1's stopgap implementation (getters owning internal Watches)
   temporarily makes every getter a GC root + push subscriber.
10. Final direction: resolve the `Lifetime::expose()` reference to either an
    existing artifact or explicitly "hypothetical migration vehicle".
11. §16 API: `batch` must take a polymorphic raise closure (`() -> Unit
    raise?`) for rollback to be reachable (D3.1 amendment).
12. Add an ownership contract for mutable returned values: a getter
    returning an owning `Array`/`Map` lets callers mutate cached state with
    no setter, no revision bump, and no wake-up. Require immutable views,
    defensive copies, or a documented ownership rule.
13. §16 API: the setter returned by `input` must declare its write semantic
    (equality-suppressing vs force), per the §9 amendment.
14. Keyed caches: reference the open F7 problem and require its resolution
    before D6.1's membership approach is presented as a solution.
15. State the single-threaded premise explicitly and whether it is permanent
    (the current global computation sentinel is explicitly single-thread
    dependent, `internal/kernel/state.mbt`).
16. Migration: an incremental path needs one tracking protocol across old
    `CellId` cells and new closure-owned states; note that a simple wrapper
    over old Watches makes every getter a GC root and changes push/retention
    costs.

---

## 14. Correspondence with the handoff's blocking findings

| Handoff finding | Treatment in this record |
|---|---|
| #1 transparent aliases cannot enforce View invariants | Resolved by V12.5: use an opaque kernel View for invariants/provenance and product-local closures for callable DX. Transparent `() -> T` is rejected as the sole public kernel interface. |
| #2 closures do not release inactive branches | Confirmed. The example in proposal §11 only shows "no longer a dependency", not "released by RC". True branch release requires a factory/switch combinator. Consistent with D6.1's membership approach. |
| #3 error ownership unresolved | Resolved by D2/V12.5: domain failures are cached value-level `Result`s; kernel reads return `Result[T, ReadError]`; Cycle remains recoverable; product-local aborting adapters are opt-in. |
| #4 Effect semantics undecided | Partially resolved. Initial synchronous run / at most one re-run after a batch / deferred setters / idempotent stop are decided in D3.2/D5. Error quarantine stays adapter-owned. Details are pinned by the V5.1 scenario tests. |
| #5 pull-only performance unmeasured | Obligated as V12.1. D7 keeps durability from day one. |
| #6 Phase 2 is a kernel replacement | V12.3 obligates the parity matrix + oracle before the phase. |
| #7 secondary open items | `view_by` → Eq + escape hatch, plus preserving `BackdateEq` (§9, D7 caveat). read-modify-write representation resolved by V12.5 (capability created alongside the cell); atomic/re-entrant semantics remain open. batch → rollback narrowed to staged writes, signature must allow raise (D3.1). at-most-once → keep "successful recomputation". cross-store policy remains V12.8. |

---

## 15. Next steps

Reordered after V12.5 resolution — remaining blockers come first:

1. V12.4 ownership graph + RC argument (unblocks D1's provisional status).
2. Resolve the F7 keyed-retirement problem (unblocks D6.1).
3. V12.6 Effect contract (unblocks D4.3's close/stop semantics and D5
   scheduling).
4. Reflect the amended decision list, including the V12.5 verdict, into the
   proposal (the §13 diff list) in a separate session.
5. Concretize the V5.1 scenario tests, including the pre-cached nested-view
   counterexample.
6. Decide V12.8 multi-Store composition before product modules encapsulate
   independent Stores.
7. If implementation proceeds, use a prototype worktree separated from the
   #1145 worktree, per the handoff's constraints. The kernel replacement
   comes after V12.3 with its extended scope.

---

## Appendix: terms

- **Breaker**: the single explicit handle held by the user that breaks a
  reference cycle intentionally created by the design. `Stop` for an Effect,
  `store.close()` for the whole Store.
- **Sound Wake-up Theorem (corrected)**: the *transitive* set of input
  leaves reached by the previous run — including through cached views — is a
  complete propagation path for any change that can alter the output of the
  next run. Depends on getter purity and the eight premises listed in §5.
- **Passive layer / active layer**: the layer of values that are merely read
  (pull-only, no dispose) / the layer of resources that keep running
  (mounted, stop capability required).
- **Membership is data**: the principle that the retained key set of a keyed
  cache is expressed as an ordinary value returned by a view.
