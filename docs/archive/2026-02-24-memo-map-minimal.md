# Minimal MemoMap (Parameterized Queries) Implementation Plan

**Goal:** Add a minimal keyed-query API (`MemoMap[K, V]`) so callers can memoize `K -> V` computations with one cached `Memo[V]` per key.

**Architecture:** Implement `MemoMap` as a thin API layer over existing primitives:
- storage: `HashMap[K, Memo[V]]`
- evaluation: lazily create per-key `Memo` on first access
- verification/backdating/cycle behavior: delegated entirely to existing `Memo` and runtime internals

No runtime algorithm changes in this phase.

**Tech Stack:** MoonBit. Validate with `moon check`, `moon test`, and refresh API summaries with `moon info`.

---

### Scope (MVP)

In scope:
- New public type `MemoMap[K, V]`
- Minimal methods for keyed memo access and inspection
- Root helper `create_memo_map(db, f, label?)`
- Focused tests for caching and invalidation semantics

Out of scope:
- Eviction policies (LRU/TTL/manual generation)
- Interning
- Subscriber links / push-pull invalidation
- Runtime-level GC integration

---

### Task 1: Add internal `MemoMap` type and core methods

**Files:**
- Create: `internal/memo_map.mbt`

**Implementation details:**
- Define:
  - `pub(all) struct MemoMap[K, V]`
  - fields:
    - `priv rt : Runtime`
    - `priv compute : (K) -> V`
    - `priv label : String?`
    - `priv entries : @hashmap.HashMap[K, Memo[V]]`
- Type constraints:
  - `K : Hash + Eq`
  - `V : Eq`
- Add methods:
  - `MemoMap::new(rt, compute, label?)`
  - `MemoMap::get(self, key) -> V`
  - `MemoMap::get_result(self, key) -> Result[V, CycleError]`
  - `MemoMap::contains(self, key) -> Bool`
  - `MemoMap::length(self) -> Int`

**Behavior:**
- `get/get_result` should create and cache a per-key memo on first access only.
- The per-key memo compute closure should call `self.compute(key)`.
- Repeated reads of the same key should hit that memo cache.

---

### Task 2: Wire dependencies and package exports

**Files:**
- Modify: `internal/moon.pkg`
- Modify: `incr.mbt`

**Steps:**
- Add `moonbitlang/core/hashmap` import in `internal/moon.pkg`.
- Re-export `type MemoMap` from the internal re-export block in `incr.mbt`.

---

### Task 3: Add ergonomic root helper in traits API

**Files:**
- Modify: `traits.mbt`

**Steps:**
- Add:
  - `pub fn[Db : Database, K : Hash + Eq, V : Eq] create_memo_map(db : Db, f : (K) -> V, label? : String) -> MemoMap[K, V]`
- Keep style aligned with existing helpers:
  - `create_signal`
  - `create_memo`
  - `create_tracked_cell`

---

### Task 4: Add tests for minimal keyed-query semantics

**Files:**
- Create: `internal/memo_map_test.mbt`

**Tests to include:**
- `memo_map: cache hit for same key`
  - count compute calls; second `get(key)` does not recompute
- `memo_map: independent caching per key`
  - two keys produce two independent memo entries
- `memo_map: source signal change triggers lazy recompute`
  - after input change, recompute occurs when key is read again
- `memo_map: contains and length reflect created entries`
  - creation happens on demand
- `memo_map: get_result mirrors get with cycle-safe API`
  - normal path returns `Ok(value)`

---

### Task 5: Add documentation example

**Files:**
- Modify: `docs/cookbook.md`

**Steps:**
- Add a short recipe showing:
  - constructing `MemoMap`
  - reading two keys
  - mutation of source `Signal`
  - key-local cache behavior

---

### Task 6: Validate and refresh generated API summaries

Run:

```bash
moon check
moon test
moon info
```

Expected:
- Type-check passes
- All existing tests plus new `memo_map_test.mbt` pass
- `pkg.generated.mbti` updates include `MemoMap` and `create_memo_map`

---

### Acceptance Criteria

- Public API includes `MemoMap` and `create_memo_map`.
- Keyed memoization works with one memo instance per key.
- Existing runtime behavior (verification, backdating, cycle handling) remains unchanged.
- No modifications required in:
  - `internal/runtime.mbt`
  - `internal/verify.mbt`
  - `internal/memo.mbt`
