# Scope-owned post-GC maintenance

**Date:** 2026-08-03
**Status:** Accepted — implementation tracked by [#444](https://github.com/dowdiness/incr/issues/444)
**Driver:** Loom's keyed Markdown projection attachment ([dowdiness/loom#332](https://github.com/dowdiness/loom/issues/332))

## Context

A long-lived reactive attachment has one essential maintenance decision: when
its terminal `Watch` has been read and the runtime is idle, the caller may
choose to collect graph state that is no longer reachable. The current
mechanism makes the caller reproduce an implementation sequence instead:

```text
terminal Watch read
  -> Runtime::gc()
  -> DerivedMap::sweep_cache() for every participating map
```

`Runtime::gc()` correctly owns runtime-wide reachability and cell disposal,
but a live `DerivedMap` can still retain a handle to a per-key `Derived` that
GC disposed. Requiring every attachment to enumerate maps and preserve the
sequence leaks cache implementation into downstream interfaces. Registering
maps with `Runtime` would hide the enumeration, but a callback registry would
make the runtime strongly retain generic maps and their compute closures until
perfect explicit deregistration. That undermines collection and couples
independent attachments sharing one runtime.

## Decision

Ownership is split along the information each owner actually has:

- **The caller owns timing.** Collection remains explicit and happens after a
  terminal `Watch` read at an application-selected idle point. It is never an
  automatic cost of an edit or read.
- **`Runtime` owns graph GC.** Marking, runtime-wide reachability, cell
  disposal, and phase legality remain inside `Runtime::gc()`.
- **`Scope` owns the maintenance cohort.** A scope already owns its child
  scopes, watches, cells, and maps. It exposes one composite operation and
  privately retires disposed map entries in its subtree after runtime GC.
- **`DerivedMap` owns read safety.** A live map treats a cached, GC-disposed
  per-key entry as a cache miss and recreates it before reading. Disposal of
  the map itself remains `ReadError::Disposed`.

The only new public entry point is:

```moonbit
/// Runs runtime-wide graph GC, then retires GC-disposed DerivedMap entries
/// owned by this scope and its live descendants.
///
/// Call after reading the attachment's terminal Watch at a caller-selected
/// idle point. Aborts if the scope is disposed or runtime collection is not
/// legal. Repeated calls are idempotent.
pub fn Scope::collect(self : Scope) -> Unit
```

`collect` is deliberately not named `Scope::gc`: the graph collection it
invokes is runtime-wide, not scope-local. The scope-local part is ownership of
the post-GC maintenance cohort.

Canonical usage is:

```moonbit
let scope = @incr.Scope::new(rt)
let by_key = scope.derived_map(key => lower(source.get(), key))
let terminal = scope.watch(
  scope.derived(() => render(by_key.get_or_abort(active_key.get()))),
)

fn Attachment::snapshot(self : Attachment) -> Result[View, @incr.ReadError] {
  let result = self.terminal.read()
  self.scope.collect()
  result
}
```

`Scope::collect()` does not read or prime the terminal watch. Reading first is
part of the caller's interface contract because it settles the current
dependency graph before collection. `Scope::watch(...)` remains the canonical
way to create and prime the persistent root.

## Operation contract

The implementation preserves this order:

1. reject a disposed scope;
2. verify that the runtime is between operations;
3. run the existing runtime-wide mark-and-sweep once;
4. after GC succeeds, visit live child scopes and then the receiver's private
   map-maintenance hooks;
5. remove only entries whose internal cells are already disposed.

No map hook runs if runtime GC aborts. Map sweep order is not a semantic
contract: every hook only removes an entry already disposed by the completed
runtime sweep. The child-first traversal is deterministic and mirrors scope
ownership, but callers cannot observe or depend on it.

Collection is legal only between runtime operations. It aborts, rather than
adding a new `Failure` channel, for the same programming errors as GC: active
tracked or static recomputation, an open batch, a callback/event drain, or a
non-`Idle` runtime phase. Calling `collect` on a disposed scope also aborts,
matching other scope operations. Repeated calls on a live scope are
idempotent, although each call still pays the explicit scan cost.

## Shared runtimes and raw maps

GC remains runtime-wide when independent scopes share one runtime. If scope A
collects, an unrooted entry cached by scope B may be disposed. Scope A retires
only its own subtree's entries; it neither enumerates nor retains scope B.
Scope B remains correct because its next keyed read recreates the disposed
entry, and B can retire its other stale entries at B's own collection point.
All primed watches in both scopes remain ordinary runtime GC roots.

A `DerivedMap(rt, ...)` constructed without a scope is not bulk-maintained by
`Scope::collect()`. It still self-heals on a read after `Runtime::gc()`.
`DerivedMap::sweep_cache()` remains as a compatible explicit operation for raw
maps and diagnostics, but is no longer part of the canonical attachment
interface.

## Implementation constraints

- `Scope::derived_map` privately registers a retirement closure in the owning
  scope in addition to its existing disposal closure.
- Parent collection includes maps owned by live descendants. Scope disposal
  clears both closure collections and never registers anything with Runtime.
- `DerivedMap::get_or_create_entry` replaces a disposed cached entry before
  delegating to the normal read path.
- Runtime must not gain a map registry, maintenance participant trait, weak
  reference requirement, public registration token, or map ordering contract.
- The idle guard should be a single Runtime-owned predicate/guard shared by GC
  and the composite operation rather than duplicated in Scope.
- No maintenance work is added to ordinary input writes, recomputation, keyed
  reads with a live entry, or terminal watch reads.

## Required verification

Implementation is not complete until tests demonstrate:

- one scope collection retires stale entries from multiple owned maps without
  caller enumeration;
- a watched live key remains cached and readable;
- a parent collection includes maps in live child scopes;
- repeated collection is idempotent;
- a raw map recreates a per-key entry after direct `Runtime::gc()`;
- when one of two independent scopes collects, the other scope's watch stays
  live and its disposed keyed entry self-heals on the next read;
- scope disposal clears maintenance ownership and collection after disposal
  aborts;
- recomputation, batch, callback/drain, static recomputation, and non-idle
  phase calls abort before any map hook runs.

Benchmarks on wasm-gc and JavaScript must separately bound the explicit
collection cost for live entries, stale entries, multiple maps, and shared
scopes. A steady-state edit/read control must show that merely owning the
maintenance hooks adds no per-edit map scan. Deterministic work assertions are
primary; wall-time gates require stable A/A calibration before entering CI.

## Rejected alternatives

- **Runtime-owned map registry:** rejected because the runtime would strongly
  retain maps or require a new weak-reference/finalizer protocol. Explicit
  deregistration tokens merely move lifecycle ordering back to callers.
- **Public maintenance participant/trait:** rejected as a hypothetical seam
  with one implementation. It exposes registration and ordering rather than
  deepening the existing Scope interface.
- **Scope-local graph GC:** rejected because roots, dependencies, and cells can
  cross scope ownership; runtime-wide reachability is the source of truth.
- **Automatic GC after every terminal read:** rejected because the library
  does not know the caller's safe point or latency budget.
- **Lazy self-healing alone:** necessary for shared-runtime correctness but
  insufficient for bounded retention of keys that are never read again.
- **A Loom `settle()` method:** rejected because it would encode incr's current
  cache implementation and ordering in every downstream attachment.

## Consequences

The canonical long-lived attachment interface becomes `Scope` + terminal
`Watch` + one explicit `Scope::collect()` call. Runtime stays a deep graph
module, Scope becomes the deep lifecycle module, and `DerivedMap` no longer
surfaces disposal of its private per-key wrapper as if the live map itself had
been disposed. Loom can keep keyed-cache GC and sweep sequencing private and
Canopy does not need to learn it when the parser attachment is integrated.
