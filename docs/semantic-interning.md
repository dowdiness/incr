# Semantic Interning for incr

Reference document capturing design exploration for a revision-aware semantic interner.

## Context

The [Incremental Hylomorphism pipeline](../../../docs/architecture/Incremental-Hylomorphism.md) has two boundaries that need interning:

- **Boundary ②** (Document → CST): seam's `Interner` + `NodeInterner` — structural hash-consing for position-independent CST subtree reuse
- **Boundary ③** (CST → Typed AST): incr's semantic interner — stable identity for semantic entities (definitions, types, names) across revisions

These serve different purposes and should remain separate systems. Seam's interner is session-scoped, structural, and optimized for bottom-up tree construction. Incr's interner is revision-aware, identity-based, and optimized for cross-revision cache stability.

This matches how rust-analyzer operates: Rowan's `NodeCache` (CST dedup), Salsa's `#[salsa::interned]` (semantic IDs), and a custom `crates/intern` (high-churn solver types) are three independent systems. They tried to unify and learned it doesn't work — different churn rates, equality semantics, and GC requirements.

## Design: `InternTable[T]`

A generic, standalone interning table. `T : Hash + Eq` defines the key — the framework doesn't care what fields comprise the key. Users define the key type for their domain.

### Core API

```
struct InternId {
  index : Int
  generation : Int   // bumps when slot is reused for a different value
}

struct InternTable[T] {
  to_id : HashMap[T, InternId]   // value → id (dedup lookup)
  values : Array[T]              // id → value (reverse lookup)
  generations : Array[Int]       // per-slot generation counter
}
```

Four operations:

1. **`intern(value : T) -> InternId`** — lookup or insert. Same value → same ID across calls.
2. **`get(id : InternId) -> T`** — reverse lookup. Validates generation.
3. **`InternId : Eq`** — integer comparison, O(1).
4. **`InternId : Hash`** — integer hash, O(1).

### Generational Index Design

The `InternId { index, generation }` pattern is taken from the [dowdiness/arena](https://github.com/dowdiness/arena) library's `Ref` type. Arena is a generational bump allocator for audio/DSP workloads — its `Ref { index, generation }` design is the right shape for `InternId`, but its byte-level storage and lack of value dedup make it unsuitable as a direct dependency. We reference the design, build independently.

### User-Defined Key Fields

The framework is generic over `T`. The user defines what constitutes identity:

```
// Compiler: identity by name + scope
struct FunctionKey { name: String, module: ModuleId }

// IDE: identity by file position (survives renames)
struct FunctionKey { file: FileId, position: Int }
```

Different applications choose different key strategies. `InternTable` only provides: same `T` value → same `InternId`, across revisions.

## What Revision-Aware Interning Unlocks

### Stable MemoMap keys

Without stable IDs, `MemoMap[FunctionId, Type]` can't persist across revisions — keys change even when the entity doesn't. With stable IDs, unchanged entities hit the cache.

### Automatic invalidation via generation counters

When an entity is deleted and its slot reused, the generation bumps. Any memo that cached a result for the old generation detects the mismatch — no manual invalidation needed.

### Field-level tracking on interned entities

If arena entries have independently tracked fields (via `TrackedCell`), changing only a function's body doesn't invalidate memos that only read its name.

### O(1) Datalog fact equality

`Relation[(FunctionId, TypeId)]` with `InternId` keys means fixpoint convergence checks are integer comparison, not structural comparison of rich domain types.

### Incremental Datalog maintenance (future)

With stable IDs, facts from previous revisions can persist. Only re-derive facts whose inputs changed. Generation counters signal which inputs changed.

### Demand-driven semantic analysis via HybridMemo

Per-entity `HybridMemo` keyed by stable `InternId` — dirty-flagged when the entity's arena entry changes, lazily recomputed only when viewed.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Unified with seam's interner? | No | Different churn rates, equality semantics, and GC needs. rust-analyzer learned this the hard way. |
| Runtime-integrated vs. standalone? | Standalone first | Avoids coupling overhead. Can register with Runtime later for GC. |
| GC strategy | Grow-only initially | Add `clear()` for short-lived sessions. Defer LRU/refcount until long-lived sessions need it. |
| Package location | `incr/types/` or new `incr/intern/` | Zero deps, usable independently. |
| Backing store | `HashMap[T, InternId]` + `Array[T]` | Not the arena library — arena lacks value dedup (its core purpose is byte-level bump allocation for DSP). |
| Generation counter | Start with `InternId { index: Int }` only | Grow-only tables never reuse slots, so the generation counter is vestigial until GC/slot-reuse is implemented. Adding it now costs struct size, a second comparison in `Eq`, and a second field to hash — for zero benefit. Add `generation: Int` when implementing slot reuse. |

## Relationship to Other Planned Features

| Feature | How interning helps |
|---------|-------------------|
| Accumulators | Accumulated diagnostics keyed by `InternId` — stable collection across revisions |
| Tracked functions | `InternId` as natural query key — `typecheck(FunctionId) -> Type` |
| GC | Generation counters enable slot reuse; grow-only defers the complexity |
| Persistent caching (Phase 5) | `InternId` stability across revisions is prerequisite for serializing the dep graph |
