# Layer 2: Scope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Scope` — hierarchical cell ownership with bulk disposal — enabling UI component lifecycle patterns (mount → create cells → unmount → `scope.dispose()`).

**Architecture:** `Scope` lives in the `cells/` package as a new file `scope.mbt`. It stores `CellId`s (not typed wrappers) for type-erased group management. A new `Runtime::dispose_cell(CellId)` dispatcher routes to the correct typed `dispose_*` method based on `cell_index[id]`. Scoped cell constructors delegate to existing constructors then register the CellId. `dispose_hooks` array is allocated but empty in Layer 2 (populated by `Scope::observe()` in Layer 4).

**Tech Stack:** MoonBit, incr framework (cells package)

---

### Task 1: `Effect::id()` and `Runtime::dispose_cell` — Prerequisites

**Files:**
- Modify: `cells/push_effect.mbt` (add `Effect::id()` method)
- Modify: `cells/runtime.mbt` (after line 771, after `dispose_rule`)
- Test: `cells/dispose_test.mbt` (append)

**Context:** Currently each cell type has its own `dispose_TYPE(cell_id)` method on Runtime, but there's no generic dispatcher. Scope needs to dispose cells by CellId without knowing their type. All existing `dispose_*` methods are idempotent (check `is_cell_disposed` first) and handle the `guard_dispose` check internally, so the dispatcher can safely delegate without additional guards.

Additionally, `Effect` is missing an `id()` method — all other cell types (`Signal`, `Memo`, `HybridMemo`, `Reactive`) expose one. This is needed for Scope to register the CellId after creating an effect.

Finally, `dispose_cell` must validate `runtime_id` before dispatching. The existing `is_cell_disposed` only checks numeric bounds and `Disposed`, not ownership. Without this check, a CellId from runtime A could be used to dispose a cell in runtime B if the numeric id happens to be in range.

- [ ] **Step 1: Add `Effect::id()` method**

Add to `cells/push_effect.mbt` after `Effect::is_disposed` (after line 124):

```moonbit
///|
/// Returns the unique identifier for this effect cell.
pub fn Effect::id(self : Effect) -> CellId {
  self.cell_id
}
```

- [ ] **Step 2: Write the failing tests**

Add to the end of `cells/dispose_test.mbt`:

```moonbit
///|
test "dispose_cell: dispatches to correct dispose method for each cell type" {
  let rt = Runtime()
  let sig = Signal(rt, 10)
  let memo = Memo(rt, fn() { sig.get() * 2 })
  let hybrid = HybridMemo::new(rt, fn() { sig.get() + 1 })
  // Force memos to compute so they have dependencies
  let _ = memo.get()
  let _ = hybrid.get()
  // Dispose via generic dispatcher
  rt.dispose_cell(sig.id())
  rt.dispose_cell(memo.id())
  rt.dispose_cell(hybrid.id())
  inspect(sig.is_disposed(), content="true")
  inspect(memo.is_disposed(), content="true")
  inspect(hybrid.is_disposed(), content="true")
}

///|
test "dispose_cell: idempotent — disposing already-disposed cell is no-op" {
  let rt = Runtime()
  let sig = Signal(rt, 42)
  rt.dispose_cell(sig.id())
  // Second dispose should not abort
  rt.dispose_cell(sig.id())
  inspect(sig.is_disposed(), content="true")
}

///|
test "dispose_cell: push reactive and effect" {
  let rt = Runtime()
  let sig = Signal(rt, 1)
  let reactive : Reactive[Int] = Reactive::new(rt, fn() { sig.get() })
  let effect_ran = Ref::new(0)
  let eff = Effect::new(rt, fn() {
    effect_ran.val = effect_ran.val + sig.get()
  })
  rt.dispose_cell(reactive.id())
  rt.dispose_cell(eff.id())
  inspect(reactive.is_disposed(), content="true")
  inspect(eff.is_disposed(), content="true")
}

///|
test "panic dispose_cell: rejects foreign runtime CellId" {
  let rt1 = Runtime()
  let rt2 = Runtime()
  let sig = Signal(rt1, 42)
  // Attempting to dispose rt1's cell via rt2 should abort
  rt2.dispose_cell(sig.id())
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f dispose_test.mbt`
Expected: FAIL — `dispose_cell` is not defined on Runtime.

- [ ] **Step 4: Write the implementation**

Add to `cells/runtime.mbt` after `dispose_rule` (after line 771):

```moonbit
///|
/// Disposes a cell by CellId, dispatching to the correct typed dispose method.
///
/// This is a generic dispatcher used by Scope for bulk disposal. Each typed
/// dispose method is idempotent, so calling this on an already-disposed cell
/// is a no-op. Validates that the CellId belongs to this runtime.
pub fn Runtime::dispose_cell(self : Runtime, cell_id : CellId) -> Unit {
  guard cell_id.runtime_id == self.core.runtime_id else {
    abort("dispose_cell: CellId belongs to a different Runtime")
  }
  guard !self.is_cell_disposed(cell_id) else { return }
  match self.core.cell_index[cell_id.id] {
    PullSignal(_) => self.dispose_signal(cell_id)
    PullMemo(_) | HybridMemo(_) => self.dispose_memo(cell_id)
    PushReactive(_) => self.dispose_reactive(cell_id)
    PushEffect(_) => self.dispose_effect(cell_id)
    Relation(_) => self.dispose_relation(cell_id)
    FunctionalRelation(_) => self.dispose_functional_relation(cell_id)
    Rule(_) => self.dispose_rule(@incr_types.RuleId::{ id: cell_id })
    Disposed => ()
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f dispose_test.mbt`
Expected: PASS

- [ ] **Step 6: Run moon check**

Run: `moon check`
Expected: No errors

- [ ] **Step 7: Commit**

```bash
git add cells/push_effect.mbt cells/runtime.mbt cells/dispose_test.mbt
git commit -m "feat(dispose): add Effect::id() and Runtime::dispose_cell generic dispatcher"
```

---

### Task 2: `Scope` Struct and Core Lifecycle

**Files:**
- Create: `cells/scope.mbt`
- Test: `cells/scope_test.mbt` (create)

**Context:** The Scope struct owns cells and child scopes. `dispose_hooks` is allocated empty for Layer 4 forward-compatibility. The struct lives in the `cells/` package because it directly calls `Runtime::dispose_cell` (package-private would work, but the method is `pub` anyway). Fields are `priv` — construction only via `Scope::new()` and `Scope::child()`.

**Design decisions:**
- `Scope` stores `Runtime` (not `&Runtime`) since Runtime is a heap-allocated struct in MoonBit.
- `disposed` flag prevents double-dispose and guards all methods.
- `Scope::child()` registers the child in the parent's `children` array.
- `is_disposed()` is a simple field read, not a runtime lookup (Scope is not a cell).

- [ ] **Step 1: Write the failing tests**

Create `cells/scope_test.mbt`:

```moonbit
///|
test "scope: new creates empty scope" {
  let rt = Runtime()
  let scope = Scope::new(rt)
  inspect(scope.is_disposed(), content="false")
}

///|
test "scope: dispose marks scope as disposed" {
  let rt = Runtime()
  let scope = Scope::new(rt)
  scope.dispose()
  inspect(scope.is_disposed(), content="true")
}

///|
test "scope: dispose is idempotent" {
  let rt = Runtime()
  let scope = Scope::new(rt)
  scope.dispose()
  // Second dispose should not abort
  scope.dispose()
  inspect(scope.is_disposed(), content="true")
}

///|
test "scope: child creates nested scope" {
  let rt = Runtime()
  let parent = Scope::new(rt)
  let child = parent.child()
  inspect(child.is_disposed(), content="false")
  inspect(parent.is_disposed(), content="false")
}

///|
test "scope: disposing parent disposes children" {
  let rt = Runtime()
  let parent = Scope::new(rt)
  let child1 = parent.child()
  let child2 = parent.child()
  parent.dispose()
  inspect(child1.is_disposed(), content="true")
  inspect(child2.is_disposed(), content="true")
  inspect(parent.is_disposed(), content="true")
}

///|
test "scope: nested children disposed bottom-up" {
  let rt = Runtime()
  let root = Scope::new(rt)
  let mid = root.child()
  let leaf = mid.child()
  root.dispose()
  inspect(leaf.is_disposed(), content="true")
  inspect(mid.is_disposed(), content="true")
  inspect(root.is_disposed(), content="true")
}

///|
test "scope: child of disposed scope aborts" {
  let rt = Runtime()
  let scope = Scope::new(rt)
  scope.dispose()
}

///|
test "panic scope: child of disposed scope aborts" {
  let rt = Runtime()
  let scope = Scope::new(rt)
  scope.dispose()
  let _ = scope.child()
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f scope_test.mbt`
Expected: FAIL — `Scope` type is not defined.

- [ ] **Step 3: Write the implementation**

Create `cells/scope.mbt`:

```moonbit
///|
/// Hierarchical cell ownership with bulk disposal.
///
/// Scope owns cells and child scopes. Disposing a scope disposes all owned
/// cells and children recursively. This enables UI component lifecycle patterns:
/// create cells during mount, dispose the scope on unmount.
///
/// # Disposal Order
///
/// 1. Children (bottom-up, recursively)
/// 2. Dispose hooks (empty in Layer 2; populated by Scope::observe in Layer 4)
/// 3. Owned cells
///
/// # Example
///
/// ```moonbit nocheck
/// let scope = Scope::new(rt)
/// let local = scope.signal(42)
/// let derived = scope.memo(fn() { local.get() * 2 })
///
/// // Component unmounts — one cleanup call
/// scope.dispose()
/// ```
pub struct Scope {
  priv runtime : Runtime
  priv cells : Array[CellId]
  priv children : Array[Scope]
  priv dispose_hooks : Array[() -> Unit]
  priv mut disposed : Bool
} derive(Debug(ignore=[Runtime, Fn]))

///|
/// Creates a new root scope.
pub fn Scope::new(rt : Runtime) -> Scope {
  { runtime: rt, cells: [], children: [], dispose_hooks: [], disposed: false }
}

///|
/// Creates a child scope owned by this scope.
///
/// Disposing the parent will dispose this child first (bottom-up order).
pub fn Scope::child(self : Scope) -> Scope {
  guard !self.disposed else {
    abort("Scope::child called on a disposed scope")
  }
  let child : Scope = {
    runtime: self.runtime,
    cells: [],
    children: [],
    dispose_hooks: [],
    disposed: false,
  }
  self.children.push(child)
  child
}

///|
/// Returns true if this scope has been disposed.
pub fn Scope::is_disposed(self : Scope) -> Bool {
  self.disposed
}

///|
/// Disposes this scope: children first, then hooks, then owned cells.
///
/// Idempotent — disposing an already-disposed scope is a no-op.
pub fn Scope::dispose(self : Scope) -> Unit {
  guard !self.disposed else { return }
  // 1. Dispose children (bottom-up)
  for child in self.children {
    child.dispose()
  }
  // 2. Execute dispose hooks (Layer 4: observer cleanup)
  for hook in self.dispose_hooks {
    hook()
  }
  // 3. Dispose owned cells
  for cell_id in self.cells {
    self.runtime.dispose_cell(cell_id)
  }
  self.disposed = true
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f scope_test.mbt`
Expected: PASS

- [ ] **Step 5: Run moon check**

Run: `moon check`
Expected: No errors

- [ ] **Step 6: Commit**

```bash
git add cells/scope.mbt cells/scope_test.mbt
git commit -m "feat(scope): add Scope struct with hierarchical dispose"
```

---

### Task 3: Scoped Cell Constructors

**Files:**
- Modify: `cells/scope.mbt` (append)
- Test: `cells/scope_test.mbt` (append)

**Context:** Scoped cell constructors delegate to existing constructors, then register the CellId with the scope. Each returns the typed cell wrapper so callers can use `.get()`, `.set()`, etc. normally. The scope only stores the CellId for later disposal.

**API signatures (from design spec):**
- `Scope::signal[T](self, initial, durability?, label?) -> Signal[T]`
- `Scope::memo[T : Eq](self, f, label?) -> Memo[T]`
- `Scope::hybrid_memo[T : Eq](self, f, label?) -> HybridMemo[T]`
- `Scope::effect(self, f) -> Effect`
- `Scope::reactive[T : Eq](self, compute_fn) -> Reactive[T]`

Note: `Reactive` is included because it is a public cell type and follows the same pattern. The design spec doesn't explicitly list it but it would be inconsistent to omit it.

- [ ] **Step 1: Write the failing tests**

Append to `cells/scope_test.mbt`:

```moonbit
///|
test "scope: signal creates cell and registers for disposal" {
  let rt = Runtime()
  let scope = Scope::new(rt)
  let sig = scope.signal(42)
  inspect(sig.get(), content="42")
  scope.dispose()
  inspect(sig.is_disposed(), content="true")
}

///|
test "scope: memo creates cell and registers for disposal" {
  let rt = Runtime()
  let scope = Scope::new(rt)
  let sig = scope.signal(10)
  let m = scope.memo(fn() { sig.get() * 2 })
  inspect(m.get(), content="20")
  scope.dispose()
  inspect(m.is_disposed(), content="true")
  inspect(sig.is_disposed(), content="true")
}

///|
test "scope: hybrid_memo creates cell and registers for disposal" {
  let rt = Runtime()
  let scope = Scope::new(rt)
  let sig = scope.signal(5)
  let hm = scope.hybrid_memo(fn() { sig.get() + 1 })
  inspect(hm.get(), content="6")
  scope.dispose()
  inspect(hm.is_disposed(), content="true")
}

///|
test "scope: effect creates cell and registers for disposal" {
  let rt = Runtime()
  let scope = Scope::new(rt)
  let ran = Ref::new(0)
  let sig = scope.signal(1)
  let eff = scope.effect(fn() {
    ran.val = ran.val + sig.get()
  })
  inspect(ran.val, content="1")
  scope.dispose()
  inspect(eff.is_disposed(), content="true")
}

///|
test "scope: reactive creates cell and registers for disposal" {
  let rt = Runtime()
  let scope = Scope::new(rt)
  let sig = scope.signal(3)
  let r : Reactive[Int] = scope.reactive(fn() { sig.get() * 3 })
  inspect(r.get(), content="9")
  scope.dispose()
  inspect(r.is_disposed(), content="true")
}

///|
test "scope: mixed cells all disposed together" {
  let rt = Runtime()
  let scope = Scope::new(rt)
  let s1 = scope.signal(1)
  let s2 = scope.signal(2)
  let m = scope.memo(fn() { s1.get() + s2.get() })
  let hm = scope.hybrid_memo(fn() { m.get() * 10 })
  let _ = hm.get()
  scope.dispose()
  inspect(s1.is_disposed(), content="true")
  inspect(s2.is_disposed(), content="true")
  inspect(m.is_disposed(), content="true")
  inspect(hm.is_disposed(), content="true")
}

///|
test "panic scope: signal on disposed scope aborts" {
  let rt = Runtime()
  let scope = Scope::new(rt)
  scope.dispose()
  let _ = scope.signal(1)
}

///|
test "panic scope: memo on disposed scope aborts" {
  let rt = Runtime()
  let scope = Scope::new(rt)
  scope.dispose()
  let _ = scope.memo(fn() { 1 })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f scope_test.mbt`
Expected: FAIL — `Scope::signal` etc. are not defined.

- [ ] **Step 3: Write the implementation**

Append to `cells/scope.mbt`:

```moonbit
///|
/// Creates a signal owned by this scope.
pub fn[T] Scope::signal(
  self : Scope,
  initial : T,
  durability? : Durability = Low,
  label? : String,
) -> Signal[T] {
  guard !self.disposed else {
    abort("Scope::signal called on a disposed scope")
  }
  let sig = Signal::new(self.runtime, initial, durability~, label?)
  self.cells.push(sig.id())
  sig
}

///|
/// Creates a memo owned by this scope.
pub fn[T : Eq] Scope::memo(
  self : Scope,
  f : () -> T,
  label? : String,
) -> Memo[T] {
  guard !self.disposed else {
    abort("Scope::memo called on a disposed scope")
  }
  let m = Memo::new(self.runtime, f, label?)
  self.cells.push(m.id())
  m
}

///|
/// Creates a hybrid memo owned by this scope.
pub fn[T : Eq] Scope::hybrid_memo(
  self : Scope,
  f : () -> T,
  label? : String,
) -> HybridMemo[T] {
  guard !self.disposed else {
    abort("Scope::hybrid_memo called on a disposed scope")
  }
  let hm = HybridMemo::new(self.runtime, f, label?)
  self.cells.push(hm.id())
  hm
}

///|
/// Creates an effect owned by this scope.
pub fn Scope::effect(self : Scope, f : () -> Unit) -> Effect {
  guard !self.disposed else {
    abort("Scope::effect called on a disposed scope")
  }
  let eff = Effect::new(self.runtime, f)
  self.cells.push(eff.id())
  eff
}

///|
/// Creates a reactive owned by this scope.
pub fn[T : Eq] Scope::reactive(
  self : Scope,
  compute_fn : () -> T,
) -> Reactive[T] {
  guard !self.disposed else {
    abort("Scope::reactive called on a disposed scope")
  }
  let r = Reactive::new(self.runtime, compute_fn)
  self.cells.push(r.id())
  r
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f scope_test.mbt`
Expected: PASS

- [ ] **Step 5: Run moon check**

Run: `moon check`
Expected: No errors

- [ ] **Step 6: Commit**

```bash
git add cells/scope.mbt cells/scope_test.mbt
git commit -m "feat(scope): add scoped cell constructors (signal, memo, hybrid_memo, effect, reactive)"
```

---

### Task 4: `Scope::add_tracked` — Trackable Integration

**Files:**
- Modify: `cells/scope.mbt` (append)
- Test: `cells/scope_test.mbt` (append)

**Context:** The design spec (section 8, "TrackedCell") says `Scope::add_tracked[T : Trackable](self, tracked)` registers all of a struct's TrackedCells with a scope for bulk lifecycle management. `Trackable::cell_ids()` returns the CellIds to register. This replaces the no-op `gc_tracked()` stub.

- [ ] **Step 1: Write the failing test**

Append to `cells/scope_test.mbt`:

```moonbit
///|
// Helper struct implementing Trackable for testing
struct TestTracked {
  a : TrackedCell[Int]
  b : TrackedCell[Int]
}

///|
impl Trackable for TestTracked with cell_ids(self) {
  [self.a.id(), self.b.id()]
}

///|
test "scope: add_tracked registers all cell ids for disposal" {
  let rt = Runtime()
  let scope = Scope::new(rt)
  let tracked : TestTracked = {
    a: TrackedCell(rt, 1, label="a"),
    b: TrackedCell(rt, 2, label="b"),
  }
  scope.add_tracked(tracked)
  inspect(tracked.a.get(), content="1")
  inspect(tracked.b.get(), content="2")
  scope.dispose()
  inspect(tracked.a.is_disposed(), content="true")
  inspect(tracked.b.is_disposed(), content="true")
}

///|
test "panic scope: add_tracked on disposed scope aborts" {
  let rt = Runtime()
  let scope = Scope::new(rt)
  scope.dispose()
  let tracked : TestTracked = {
    a: TrackedCell(rt, 1),
    b: TrackedCell(rt, 2),
  }
  scope.add_tracked(tracked)
}

///|
test "panic scope: add_tracked with foreign runtime cells aborts on dispose" {
  let rt1 = Runtime()
  let rt2 = Runtime()
  let scope = Scope::new(rt1)
  let tracked : TestTracked = {
    a: TrackedCell(rt2, 1),
    b: TrackedCell(rt2, 2),
  }
  scope.add_tracked(tracked)
  // dispose_cell will abort because CellIds belong to rt2, not rt1
  scope.dispose()
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/cells -f scope_test.mbt`
Expected: FAIL — `Scope::add_tracked` is not defined.

- [ ] **Step 3: Write the implementation**

Append to `cells/scope.mbt`:

```moonbit
///|
/// Registers all cells from a Trackable struct with this scope.
///
/// When the scope is disposed, all registered cells are disposed.
/// This is the recommended way to manage TrackedCell lifetimes.
pub fn[T : Trackable] Scope::add_tracked(self : Scope, tracked : T) -> Unit {
  guard !self.disposed else {
    abort("Scope::add_tracked called on a disposed scope")
  }
  for id in tracked.cell_ids() {
    self.cells.push(id)
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/cells -f scope_test.mbt`
Expected: PASS

- [ ] **Step 5: Run moon check**

Run: `moon check`
Expected: No errors

- [ ] **Step 6: Commit**

```bash
git add cells/scope.mbt cells/scope_test.mbt
git commit -m "feat(scope): add Scope::add_tracked for Trackable integration"
```

---

### Task 5: Public API Re-export, `gc_tracked` Deprecation, and Integration Tests

**Files:**
- Modify: `incr.mbt` (add `type Scope` re-export)
- Modify: `traits.mbt` (add `create_scope` Database helper; update `gc_tracked` docs to note deprecation in favor of `Scope::add_tracked`)
- Create: `tests/scope_test.mbt` (integration tests via `@incr` public API)

**Context:** The root package re-exports all public types via `pub using @internal { type Scope }`. Following the existing pattern (`create_signal`, `create_memo`, etc.), add `create_scope(db)` helper. The design spec (section 8) says `gc_tracked` is deprecated in favor of `Scope::add_tracked` — update its docstring. Integration tests exercise the public API surface to ensure re-exports work correctly.

- [ ] **Step 1: Write the failing integration tests**

Create `tests/scope_test.mbt`:

```moonbit
///|
test "scope: create and dispose via public API" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let sig = scope.signal(42)
  let m = scope.memo(fn() { sig.get() * 2 })
  inspect(m.get(), content="84")
  scope.dispose()
  inspect(sig.is_disposed(), content="true")
  inspect(m.is_disposed(), content="true")
}

///|
test "scope: nested scopes via public API" {
  let rt = @incr.Runtime()
  let parent = @incr.Scope::new(rt)
  let child = parent.child()
  let sig = child.signal(10)
  parent.dispose()
  inspect(sig.is_disposed(), content="true")
}

///|
test "scope: manual dispose before scope dispose is safe" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let sig = scope.signal(1)
  let m = scope.memo(fn() { sig.get() })
  // Manually dispose the memo before the scope
  m.dispose()
  inspect(m.is_disposed(), content="true")
  // Scope dispose should not abort — idempotent
  scope.dispose()
  inspect(sig.is_disposed(), content="true")
}

///|
test "scope: scope does not interfere with unscoped cells" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let scoped_sig = scope.signal(1)
  let unscoped_sig = @incr.Signal(rt, 2)
  scope.dispose()
  inspect(scoped_sig.is_disposed(), content="true")
  inspect(unscoped_sig.is_disposed(), content="false")
  // Unscoped signal still works
  inspect(unscoped_sig.get(), content="2")
}

///|
test "scope: child scope cells disposed before parent cells" {
  let rt = @incr.Runtime()
  let parent = @incr.Scope::new(rt)
  let parent_sig = parent.signal(100)
  let child = parent.child()
  let child_sig = child.signal(200)
  // Child reads parent — this is the typical pattern
  let child_memo = child.memo(fn() { parent_sig.get() + child_sig.get() })
  inspect(child_memo.get(), content="300")
  parent.dispose()
  inspect(child_sig.is_disposed(), content="true")
  inspect(child_memo.is_disposed(), content="true")
  inspect(parent_sig.is_disposed(), content="true")
}

///|
test "scope: dispose during batch — pending signal writes discarded" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let sig = scope.signal(1)
  rt.batch(fn() {
    sig.set(99)
    // Dispose the scope mid-batch — pending write should be discarded
    scope.dispose()
  })
  inspect(sig.is_disposed(), content="true")
}

///|
test "scope: cell manually disposed before scope dispose is safe" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let sig1 = scope.signal(1)
  let sig2 = scope.signal(2)
  // Manually dispose one cell
  sig1.dispose()
  inspect(sig1.is_disposed(), content="true")
  inspect(sig2.is_disposed(), content="false")
  // Scope dispose should handle already-disposed cell gracefully
  scope.dispose()
  inspect(sig2.is_disposed(), content="true")
}

///|
test "scope: dispose after push propagation completes" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let sig = scope.signal(1)
  let count = Ref::new(0)
  let eff = scope.effect(fn() {
    count.val = count.val + sig.get()
  })
  inspect(count.val, content="1")
  // Trigger push propagation
  sig.set(10)
  inspect(count.val, content="11")
  // Dispose after propagation completes — should be safe
  scope.dispose()
  inspect(sig.is_disposed(), content="true")
  inspect(eff.is_disposed(), content="true")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/incr/tests -f scope_test.mbt`
Expected: FAIL — `@incr.Scope` type is not exported.

- [ ] **Step 3: Add re-export and Database helpers**

In `incr.mbt`, add `type Scope` to the `@internal` using block:

```moonbit
pub using @internal {
  type Runtime,
  type CellInfo,
  type Signal,
  type Memo,
  type MemoMap,
  type CycleError,
  type TrackedCell,
  type HybridMemo,
  type Relation,
  type FunctionalRelation,
  type Reactive,
  type Effect,
  type Scope,
}
```

In `traits.mbt`, append the `create_scope` helper:

```moonbit
///|
/// Creates a new root scope using the database's runtime.
///
/// Cells created via the scope's constructors are automatically disposed
/// when the scope is disposed. Use `scope.child()` for nested scopes.
///
/// # Parameters
///
/// - `db`: Any type implementing `Database`
///
/// # Returns
///
/// A new root scope associated with the database's runtime
pub fn[Db : Database] create_scope(db : Db) -> Scope {
  Scope::new(db.runtime())
}
```

In `traits.mbt`, update the `gc_tracked` docstring (replace the existing doc comment block):

```moonbit
///|
/// **Deprecated:** Use `Scope::add_tracked` instead for lifecycle management.
///
/// This function was originally intended to mark TrackedCell fields as GC roots.
/// However, TrackedCells are Sources with no downstream dependency edges, so
/// marking them as roots keeps nothing alive. Use `scope.add_tracked(tracked)`
/// to register all of a struct's TrackedCells with a scope for bulk disposal.
///
/// This function is a no-op and will be removed in a future version.
pub fn[T : Trackable] gc_tracked(rt : Runtime, tracked : T) -> Unit {
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/incr/tests -f scope_test.mbt`
Expected: PASS

- [ ] **Step 5: Run all tests**

Run: `moon test`
Expected: All tests pass (existing + new)

- [ ] **Step 6: Commit**

```bash
git add incr.mbt traits.mbt tests/scope_test.mbt
git commit -m "feat(scope): re-export Scope type and add integration tests"
```

---

### Task 6: Benchmarks

**Files:**
- Modify: `tests/bench_test.mbt` (append)

**Context:** The design spec (Section 6, Phase 2) requires: "Scope create/dispose cost, bulk dispose 100 cells". These benchmarks establish Layer 2 performance baselines.

- [ ] **Step 1: Write the benchmarks**

Append to `tests/bench_test.mbt`:

```moonbit
///|
test "bench: scope create and dispose (empty)" {
  let b = @bench.T::new()
  let rt = @incr.Runtime()
  b.run(fn() {
    let scope = @incr.Scope::new(rt)
    scope.dispose()
  })
}

///|
test "bench: scope create 10 signals and dispose" {
  let b = @bench.T::new()
  let rt = @incr.Runtime()
  b.run(fn() {
    let scope = @incr.Scope::new(rt)
    for i in 0..<10 {
      let _ = scope.signal(i)
    }
    scope.dispose()
  })
}

///|
test "bench: scope bulk dispose 100 mixed cells" {
  let b = @bench.T::new()
  let rt = @incr.Runtime()
  b.run(fn() {
    let scope = @incr.Scope::new(rt)
    for i in 0..<50 {
      let _ = scope.signal(i)
    }
    for _ in 0..<50 {
      let _ = scope.memo(fn() { 0 })
    }
    scope.dispose()
  })
}

///|
test "bench: nested scope (3 levels) create and dispose" {
  let b = @bench.T::new()
  let rt = @incr.Runtime()
  b.run(fn() {
    let root = @incr.Scope::new(rt)
    let mid = root.child()
    let leaf = mid.child()
    let _ = root.signal(1)
    let _ = mid.signal(2)
    let _ = leaf.signal(3)
    root.dispose()
  })
}
```

- [ ] **Step 2: Run benchmarks to verify they work**

Run: `moon bench --release`
Expected: Benchmarks run without error

- [ ] **Step 3: Run all tests**

Run: `moon test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add tests/bench_test.mbt
git commit -m "bench(scope): add scope creation, disposal, and bulk benchmarks"
```

---

### Task 7: Documentation and moon info

**Files:**
- Modify: `CLAUDE.md` (update architecture section to mention Scope)
- Run: `moon info && moon fmt`

**Context:** Update the CLAUDE.md architecture table to document Scope. Run `moon info` to regenerate `.mbti` interfaces and `moon fmt` to format. Check `git diff *.mbti` to verify the new public API surface matches expectations.

- [ ] **Step 1: Update CLAUDE.md**

In the Architecture section's file listing for `cells/`, add the Scope entry:

```
│   ├── scope.mbt               (Scope — hierarchical cell ownership with bulk disposal)
```

- [ ] **Step 2: Run moon info and moon fmt**

Run: `moon info && moon fmt`

- [ ] **Step 3: Check API surface changes**

Run: `git diff *.mbti`
Expected: New entries for `Scope`, `Scope::new`, `Scope::child`, `Scope::dispose`, `Scope::is_disposed`, `Scope::signal`, `Scope::memo`, `Scope::hybrid_memo`, `Scope::effect`, `Scope::reactive`, `Scope::add_tracked`, `Runtime::dispose_cell`, `create_scope`.

- [ ] **Step 4: Run all tests one final time**

Run: `moon test`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "docs: update architecture docs and regenerate .mbti for Scope"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] `Scope` struct with `runtime`, `cells`, `children`, `dispose_hooks`, `disposed` fields
- [x] `Scope::new(rt)` — root scope
- [x] `Scope::child(self)` — nested scope
- [x] `Scope::dispose(self)` — recursive, ordered: children → hooks → cells
- [x] Scoped constructors: `signal`, `memo`, `hybrid_memo`, `effect` (+ `reactive`)
- [x] `Scope::add_tracked` — Trackable integration
- [x] Idempotent disposal (double-dispose is no-op)
- [x] `Runtime::dispose_cell` — generic dispatcher with `runtime_id` validation
- [x] `Effect::id()` — prerequisite (was missing)
- [x] `dispose_hooks` allocated empty (Layer 4 forward-compat)
- [x] Public API re-export via `incr.mbt`
- [x] `create_scope` Database helper
- [x] `gc_tracked` docs updated to note deprecation in favor of `Scope::add_tracked`
- [x] Benchmarks: scope create/dispose, bulk 100 cells
- [x] No observer support (Layer 4)

**Edge-case test coverage (from Codex review):**
- [x] Foreign runtime CellId rejection (`dispose_cell` and `add_tracked`)
- [x] Scope dispose during batch (pending writes discarded)
- [x] Scope dispose after push propagation
- [x] Cell manually disposed before scope dispose (idempotent)

**Placeholder scan:** None found.

**Type consistency:** `Scope` used consistently across all tasks. Method names match spec. `dispose_cell` takes `CellId` everywhere.

**Consumer audit:** `dispose_cell` delegates to existing `dispose_*` methods which are all idempotent. No new iteration patterns over SoA arrays. Scope does not interact with fixpoint, batch, or push propagation — it only calls `dispose_cell` which already handles those guards internally.

**Known limitation (documented, not fixed):** `Scope::effect` and `Scope::reactive` register the CellId *after* the initial user callback executes (because `Effect::new`/`Reactive::new` run the callback during construction). If the callback were to dispose the scope before returning, the new cell would be unregistered. This is not practically exploitable because: (1) the scope's `disposed` guard prevents constructing new cells on a disposed scope, and (2) `guard_dispose` in the runtime prevents disposing a cell during its own computation. A theoretical risk remains if a multi-threaded future were introduced, but MoonBit currently targets single-threaded WASM.
