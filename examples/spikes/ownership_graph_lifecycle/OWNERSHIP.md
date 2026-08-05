# V12.4 field-level ownership argument

**Issue:** [incr #451](https://github.com/dowdiness/incr/issues/451)

**Reader:** Maintainers deciding whether the retention redesign's ownership
placement is viable under MoonBit reference counting.

**Decision:** Preserve as the field-level argument attached to the throwaway
ownership prototype. It evaluates the candidate object graph; it does not
change the current engine or close V12.4.

**Keep until:** #451 reaches a final `Pass`, `Pass with constraints`, or `Fail`
verdict and the durable result is absorbed into the canonical retention brief.

**Disposition:** Prototype-branch evidence. Do not merge this file as a
production design specification.

---

## Status

**Current verdict: Pass with constraints for library-controlled edges.**

The target placement can keep its ordinary passive graph acyclic if
dependencies point only upstream and StoreCore owns no passive state. This is
not a global acyclicity proof: user compute captures and cached values are
opaque ownership sources that can introduce cycles the library cannot inspect.
Active resources also require their teardown capability to remain externally
reachable throughout the intended active lifetime.

V12.4 remains open for a production-shaped compile probe and native-RC
evidence.

---

## Edge vocabulary

| Term | Meaning in this argument |
|---|---|
| Strong edge | A MoonBit reference that contributes to RC ownership |
| Logical edge | An ID or revision relation used by the incremental algorithm; not an RC reference to the target object |
| External root | A capability or value held outside the Store implementation |
| Active owner edge | A Store-owned edge that keeps an Effect, command, listener, or adapter running |
| Breaker transition | An idempotent operation that removes enough active owner edges to break every cycle in its SCC |
| Opaque edge | Ownership introduced by a user closure or generic cached value whose captures cannot be enumerated by the library |

The current arena and the target candidate use different edge shapes. A
current `CellId` dependency is logical because Runtime already owns every slot.
The target dependency collection must strongly own upstream state because no
arena owns all passive nodes.

---

## Current implementation audit

This section records current facts only. It is not the target layout.

| Current owner | Field | Edge kind | Consequence | Evidence |
|---|---|---|---|---|
| `Derived[T]` | `rt : Runtime` | strong | A user handle keeps the whole Runtime alive | `incr/cells/derived_facade.mbt:3-10` |
| `Derived[T]` | `compute`, `backdate_eq`, `value` | strong / opaque | Closures and cached `T` may retain arbitrary MoonBit values | `incr/cells/derived_facade.mbt:3-10` |
| `Runtime.pull` | `memos : Array[MemoData]` | strong arena ownership | Runtime owns every allocated or reusable memo slot | `incr/cells/internal/kernel/state.mbt:168-173` |
| `MemoData` | `compute` | strong closure | The runtime slot owns the recompute closure | `incr/cells/internal/pull/memo_data.mbt:7-25` |
| `MemoData` | `dependencies : Array[CellId]` | logical IDs | Verification and GC traversal use IDs, not RC references to upstream handles | `incr/cells/internal/pull/memo_data.mbt:7-25` |
| `CellMeta` | `subscribers : HashSet[CellId]` | logical reverse IDs | Push routing is a reverse graph, but IDs do not own target handles | `incr/cells/internal/shared/cell_meta.mbt:7-14` |
| `RuntimeCore` | `cell_index`, `cell_ops`, `gc_root_counts` | arena/trait refs and logical IDs | Runtime coordinates all current cells and Watch root counts | `incr/cells/internal/kernel/state.mbt:203-224` |
| `Effect` | `rt`, `cell_id` | strong Runtime + logical ID | Dropping the handle does not call `dispose`; teardown is explicit | `incr/cells/push_effect.mbt:6-68` |
| `PushEffectData` | `execute`, `sources` | strong closure + logical IDs | Runtime owns user Effect code until slot clearing | `incr/cells/internal/push/push_effect_data.mbt:6-16,71-78` |
| `Watch[T]` | `runtime`, `getter`, `target_id` | strong refs + logical ID | `dispose` removes the read-root count but the Watch value can still retain its closure and Runtime | `incr/cells/watch.mbt:26-58` |
| `Scope` | `children`, `dispose_hooks`, `maintenance_hooks` | strong values and closures | Scope owns teardown order and releases these collections on dispose | `incr/cells/scope.mbt:24-30,86-116` |
| `DerivedMap` | `compute`, `entries` | opaque closure + strong map values | The map strongly owns each per-key `Derived` handle | `incr/cells/derived_map_facade.mbt:5-11` |
| `Accumulator` | typed maps; Runtime `SlotMeta` closures | strong cached values and closures | Runtime closures retain typed accumulator state; per-memo IDs remain logical | `incr/cells/accumulator.mbt:7-18,131-149` |
| Listener registries | callback entries | strong closures | Runtime-global callbacks remain until token removal, singleton clearing, or Runtime release | `incr/cells/internal/kernel/listener_registry.mbt:17-26,42-60` |
| `BatchState` | `pending`, frame rollback closures | strong trait refs and closures | Normal completion commits; catchable raised failure rolls back. Uncatchable `abort()` is outside the guarantee | `incr/cells/internal/kernel/state.mbt:118-150`; `incr/cells/batch.mbt:42-45` |

### Current feedback path

`Derived::_create` installs this closure in the Runtime-owned memo slot:

```text
Runtime
  -> PullState.memos[memo]
  -> MemoData.compute
  -> captured Derived handle
  -> Derived.rt
  -> Runtime
```

The installation is visible at `incr/cells/derived_impl.mbt:128-170`, including
`compute: () => derived.recompute_inner()` at line 154. Memo disposal clears
logical dependencies, subscribers, and callbacks but does not replace
`MemoData.compute` (`incr/cells/pull_memo_lifecycle.mbt:8-38`); the slot keeps
that closure until reuse.

The redesign must not copy this arena feedback path into passive ViewState.

---

## Target candidate objects

These are candidate fields, not implemented MoonBit declarations. Fields are
split even where the first logic prototype used one node.

### Passive and capability fields

| Owner | Candidate field | Strong target | Layer | Required invariant |
|---|---|---|---|---|
| `Store` façade | `core` | `StoreCore` | capability | The façade enables writes/close but does not own passive state through Core |
| `View` closure | captured `state` | `ViewState[T]` | passive root | Calling the closure is the only ordinary read interface |
| `ViewState[T]` | `compute` | compute closure | passive | User captures are opaque; no hidden Store-owned reverse edge |
| `ViewState[T]` | `cache` | `CachedValue[T]` | passive | Cache is released with state; mutable internals are not exposed directly |
| `ViewState[T]` | `dependencies` | `DependencyCollection` | passive | Replacement is transactional after successful recomputation |
| `ViewState[T]` | `store` | `StoreCore` | passive→core | Core does not point back to passive state |
| `DependencyCollection` | entries | upstream `InputState` / `ViewState` values | passive | Strong edges point upstream only |
| `Input` View closure | captured `state` | `InputState[T]` | passive root | Read and write capabilities may share state without Store ownership |
| `InputState[T]` | `store` | `StoreCore` | passive→core | Core does not point back to InputState |
| `Write[T]` | captured `state`, `store` | `InputState[T]`, `StoreCore` | capability | Write semantics stay nominal; dropping it must not affect readers |
| `CachedValue[T]` | payload | user `T` | opaque | Library guarantee excludes cycles wholly or partly created inside `T` |
| Compute closure | captures | user values, possibly Views | opaque | Library cannot claim global acyclicity for arbitrary captures |
| `KeyedOwner[K,V]` | entries | keyed `EntryState[V]` values | passive | Membership is the only owner edge from the family to an entry |
| Surviving getter | captured `entry` | `EntryState[V]` | passive root | Entry may outlive membership without reverse ownership |
| Diagnostic frame | ephemeral roots | caller-supplied Views | shell | Frame is discarded; no persistent all-Views registry |

### Active fields

| Owner | Candidate field | Strong target | Edge removed by |
|---|---|---|---|
| `StoreCore` | `mounts` | mount records | `Stop` for one record; `store.close()` for all |
| Mount record | Effect callback / getter set | user closure and Views | Successful Stop/close teardown |
| `Stop` capability | core + mount identity | `StoreCore` and logical mount key | Invocation removes `StoreCore -> mount`; dropping Stop alone removes nothing |
| `StoreCore` | deferred-write queue | deferred commands | dispatch flush, rollback, or close |
| Deferred command | write capability / payload | `Write[T]`, user value | queue drain, rollback, or close |
| `StoreCore` | listener registry | listener closures | registration-token removal or close |
| Listener token | core + listener identity | `StoreCore` and logical listener key | Invocation removes the registry entry |
| `StoreCore` | active adapter records | adapter cleanup closures | adapter Stop/dispose or close |

`StoreCore` may own active records because their lifetime is intentionally
imperative. It must not own passive ViewState, InputState, keyed entries, or a
global View registry.

---

## SCC argument

### Passive theorem for library-controlled edges

Ignoring opaque edges temporarily, every library-controlled passive path has
this form:

```text
external View
  -> ViewState
  -> DependencyCollection
  -> upstream state
  -> StoreCore
```

There is no `StoreCore -> passive state` edge and no upstream-to-downstream
edge. Therefore the library-controlled passive graph is acyclic if dependency
sets themselves are cycle-free.

The target must replace dependencies only after a recomputation returns a
value. If a raised Cycle escapes the target compute closure, the active query
is abandoned and the previous dependency set remains unchanged. If user code
catches Cycle and returns normally, successful reads may commit, while the
failed read edge remains absent.

The current engine directly evidences only the second case: it records into a
fresh `ActiveQuery`, swaps after a normal compute return, and records a nested
`Derived` dependency only after that read succeeds
(`incr/cells/internal/kernel/state.mbt:84-112` and
`incr/cells/derived_impl.mbt:25-68,240-282`). The caught self-cycle test commits
its successful source read but not the failed self edge
(`incr/cells/current_model_wbtest.mbt:101-126`). Current Cycle is a `Result`
channel and `get_or_abort()` aborts, so raised-Cycle query abandonment is a new
target obligation for V12.10 rather than a current semantic oracle.

### Opaque-edge limit

The theorem above cannot cover arbitrary user ownership:

```text
ViewState A -> compute closure -> Ref -> View A
ViewState A -> cached T -> user object -> View A
ViewState A -> compute closure -> View B -> ViewState B
ViewState B -> compute closure -> View A -> ViewState A
```

These are constructible ownership shapes even when reactive dependency
recording rejects cycles. The public contract must choose one of two claims:

1. **Scoped guarantee:** Incr introduces no passive cycle through its own
   fields; cycles introduced by user captures or cached values remain caller
   ownership.
2. **Global guarantee:** no passive cycle can occur. This is not supportable by
   a structural callable closure over unrestricted user compute and `T`.

This argument selects the scoped guarantee. If maintainers require the global
guarantee, the callable-View design fails V12.4.

### Active SCC coverage

| Shape | Feedback path | Required reachable capability | Required cut set |
|---|---|---|---|
| Mounted Effect | Core → mount → Effect closure → View → state → Core | Stop or open Store | Remove Core → mount |
| Deferred write | Core → queue → command → Write → Core | open Store | Drain/rollback queue or close |
| Runtime listener | Core → registry → callback → View/state → Core | listener token or open Store | Remove registry entry or close |
| Effect + deferred write | union of the first two cycles | open Store, or Stop plus queue-flush capability | Cut both feedback paths |
| Effect + listener | union of Effect and listener cycles | open Store, or Stop plus listener token | Cut both feedback paths |
| Active adapter | Core → adapter record → cleanup closure → Core/View | adapter Stop or open Store | Remove adapter owner edge |

A breaker is an externally reachable capability whose transition cuts every
feedback path it is responsible for; SCC membership is irrelevant. Returning
Stop once is insufficient when every teardown capability can later be dropped
without invocation, leaving an intentional active-resource leak.

---

## Keyed and multi-instance cases

| Case | Required conclusion |
|---|---|
| Membership owns entry; no surviving getter | Removing membership cuts owner → entry and permits RC reclamation |
| Membership removed; getter survives | Getter keeps entry and its upstream dependencies alive without creating a reverse edge |
| Downstream reactive dependency survives disposal | F7 remains semantic, not merely an RC question; do not dispose an entry while a live downstream dependency still names it |
| Two Views depend on each other reactively | Failed recomputation must not commit either new dependency set |
| Two compute closures capture each other's Views | Opaque user cycle; outside the scoped library-edge guarantee |
| Accumulator producer/consumer spans keys | Slot buffers and synthetic revision IDs require V12.3/F7 semantic treatment; IDs are not target RC edges by themselves |
| Scope hook captures DerivedMap | Current lifecycle fact, not a target passive pattern; target mapping must classify the hook as active or eliminate it |
| Rule stores relation IDs | Logical lifetime pin in the arena; V12.3 must decide the target mapping before treating it as an RC edge |

The current `DerivedMap` strongly owns per-key handles and recreates disposed
entries (`incr/cells/derived_map_facade.mbt:5-11` and
`incr/cells/derived_map_impl.mbt:3-62`). Its current F7 problem is
about surviving logical dependencies that name a disposed cell, not a direct
MoonBit reference cycle. The target must solve that semantic problem before
selecting keyed retirement.

---

## Comparison with the first prototype

| First-prototype node | Production-shaped expansion | Status |
|---|---|---|
| `StoreCore` | Store façade + StoreCore | façade capability was conflated with internal core |
| `View closure` | callable View closure | represented directly |
| `ViewState` | ViewState + CachedValue + DependencyCollection | cache and dependency owner were collapsed |
| `compute closure` | compute closure + opaque capture graph | hidden user edges were not enumerated |
| `upstream state` | multiple InputState/ViewState instances | one node could not express cross-instance cycles |
| `mount record` / `Effect record` | mount registry entry + Effect callback/getters | represented at the right conceptual layer |
| `Stop handle` | external teardown capability + logical identity | prototype correctly modeled capability loss |
| `deferred write` | queue + command + Write capability + payload | queue contents were collapsed |
| `keyed owner` / `entry` / `getter` | keyed family + many entry states + surviving roots | one-key case only |
| absent | listener registry/token; active adapters; diagnostic frame | must be covered by V12.3/V12.6 |

The prototype's `Pass with constraints` remains valid only for the collapsed
model. This table adds the principal missing fields and narrows the ownership
claim.

---

## Required constraints

1. **No passive Core registry.** StoreCore has no strong collection of passive
   ViewState, InputState, or keyed entries.
2. **Upstream-only committed dependencies.** DependencyCollection owns upstream
   states; no passive reverse subscriber edge is stored.
3. **Transactional dependency swap.** Failed computation, Cycle, CrossStore,
   or close detection commits no dependency ownership changes.
4. **Scoped RC promise.** The library promises no cycle introduced by
   library-controlled passive fields, not global acyclicity of arbitrary user
   closures and values.
5. **Opaque ownership documentation.** Compute captures, custom backdating
   closures, and cached `T` are caller-owned retention sources.
6. **Cache encapsulation.** Internal cached mutable collections are not exposed;
   adapters receive immutable views or defensive copies where ownership could
   otherwise mutate cached state.
7. **Reachable active teardown.** Each active owner edge has an idempotent Stop,
   token removal, dispatch drain, rollback, or close transition that remains
   reachable for the intended active lifetime.
8. **Close coverage.** `store.close()` removes every Store-owned active owner
   edge, including mounts, deferred commands, listeners, and adapters.
9. **Breaker coverage, not presence.** For a combined SCC, the available
   transitions must cut every independent feedback path.
10. **Keyed retirement remains gated.** Membership removal alone does not
    authorize entry disposal while a downstream logical dependency survives.
11. **Rooted diagnostics only.** Diagnostic traversal never creates a
    persistent all-Views owner.

---

## Verdict and remaining evidence

**Field-level verdict: Pass with constraints.** The selected placement is
structurally viable for library-controlled edges under the eleven constraints
above. The most important qualification is that callable Views cannot provide
a global no-cycle guarantee over arbitrary compute captures and cached values.

This does not close V12.4. Remaining work:

1. compile-probe private target skeletons for Store façade/Core, ViewState,
   CachedValue, DependencyCollection, InputState, Write, mount, Stop, queue,
   listener token, and keyed entries;
2. construct explicit late-bound capture and cached-value cycle probes to pin
   the scoped-guarantee wording;
3. exercise multiple View, Effect, listener, deferred-command, and keyed-entry
   instances rather than one node per kind;
4. run native-RC stress only after the production-shaped field skeleton exists;
5. feed the final ownership guarantee and breaker definition back into the
   canonical retention brief.

No replacement-kernel implementation is authorized by this result.
