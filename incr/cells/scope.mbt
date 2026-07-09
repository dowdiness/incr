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
/// let local = scope.input(42)
/// let derived = scope.derived(fn() { local.get() * 2 })
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
}

///|
/// Contract for types that expose their runtime-tracked cell ids —
/// typically structs that own `InputField` fields, but any cell handle
/// qualifies.
///
/// The ordering of CellIds returned by cell_ids() must be stable across
/// calls (i.e., always return fields in the same order), and the ids must
/// belong to the runtime of any scope they are registered with.
pub(open) trait InputFieldOwner {
  fn cell_ids(Self) -> Array[CellId]
}

///|
/// Manual Debug impl because `Array[() -> Unit]` cannot derive Debug
/// (the `ignore` parameter only filters top-level field types, not nested types).
pub impl Debug for Scope with fn to_repr(self) {
  Repr::record({
    "cells": to_repr(self.cells),
    "children": to_repr(self.children),
    "dispose_hooks": Repr::literal(
      "<" + self.dispose_hooks.length().to_string() + " hooks>",
    ),
    "disposed": to_repr(self.disposed),
  })
}

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
  guard !self.disposed else { abort("Scope::child called on a disposed scope") }
  let child = Scope::new(self.runtime)
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
  // Release references so a long-lived scope handle doesn't retain the subtree.
  self.children.clear()
  self.dispose_hooks.clear()
  self.cells.clear()
  self.disposed = true
}

///|
/// Creates an input facade owned by this scope.
pub fn[T] Scope::input(
  self : Scope,
  initial : T,
  durability? : Durability = Low,
  label? : String,
) -> Input[T] {
  guard !self.disposed else { abort("Scope::input called on a disposed scope") }
  let input = Input(self.runtime, initial, durability~, label?)
  self.cells.push(input.id())
  input
}

///|
/// Creates an input-field facade owned by this scope.
pub fn[T] Scope::input_field(
  self : Scope,
  initial : T,
  durability? : Durability = Low,
  label? : String,
) -> InputField[T] {
  guard !self.disposed else {
    abort("Scope::input_field called on a disposed scope")
  }
  let field = InputField(self.runtime, initial, durability~, label?)
  self.cells.push(field.id())
  field
}

///|
/// Creates a lazy derived facade owned by this scope.
pub fn[T : Eq] Scope::derived(
  self : Scope,
  f : () -> T raise Failure,
  label? : String,
) -> Derived[T] {
  guard !self.disposed else {
    abort("Scope::derived called on a disposed scope")
  }
  let derived = Derived(self.runtime, f, label?)
  self.cells.push(derived.id())
  derived
}

///|
/// Creates a lazy derived facade owned by this scope, without equality-based
/// backdating. Each recomputation advances the changed-at revision
/// unconditionally, even when the output equals the previous value. Accepts
/// output types that do not implement `Eq`.
pub fn[T] Scope::derived_no_backdate(
  self : Scope,
  f : () -> T raise Failure,
  label? : String,
) -> Derived[T] {
  guard !self.disposed else {
    abort("Scope::derived_no_backdate called on a disposed scope")
  }
  let derived : Derived[T] = Derived::derived_no_backdate(
    self.runtime,
    f,
    label?,
  )
  self.cells.push(derived.id())
  derived
}

///|
/// Creates a reachable lazy derived facade owned by this scope.
pub fn[T : Eq] Scope::reachable_derived(
  self : Scope,
  f : () -> T raise Failure,
  label? : String,
) -> ReachableDerived[T] {
  guard !self.disposed else {
    abort("Scope::reachable_derived called on a disposed scope")
  }
  let derived = ReachableDerived(self.runtime, f, label?)
  self.cells.push(derived.id())
  derived
}

///|
/// Materializes an expression as a lazy derived cell owned by this scope.
/// Aborts if `expr` belongs to a different runtime.
pub fn[T : Eq] Scope::derived_expr(
  self : Scope,
  expr : Expr[T],
  label? : String,
) -> Derived[T] {
  guard !self.disposed else {
    abort("Scope::derived_expr called on a disposed scope")
  }
  guard expr.rt.id() == self.runtime.id() else {
    abort(
      "Scope::derived_expr: expression Runtime " +
      expr.rt.id().to_string() +
      " does not match scope Runtime " +
      self.runtime.id().to_string(),
    )
  }
  let derived = expr.derived(label?)
  self.cells.push(derived.id())
  derived
}

///|
/// Creates a keyed derived facade whose cached entries are cleared on dispose.
pub fn[K : Hash + Eq, V] Scope::derived_map(
  self : Scope,
  compute : (K) -> V raise Failure,
  label? : String,
) -> DerivedMap[K, V] {
  guard !self.disposed else {
    abort("Scope::derived_map called on a disposed scope")
  }
  let map = DerivedMap(self.runtime, compute, label?)
  self.dispose_hooks.push(fn() { map.dispose_from_scope() })
  map
}

///|
/// Creates an accumulator owned by this scope. The accumulator is disposed
/// automatically when the scope is disposed (via `dispose_hooks`).
pub fn[T : Eq] Scope::accumulator(
  self : Scope,
  label? : String,
) -> Accumulator[T] {
  guard !self.disposed else {
    abort("Scope::accumulator called on a disposed scope")
  }
  let a : Accumulator[T] = Accumulator(self.runtime, label?)
  self.dispose_hooks.push(() => a.dispose())
  a
}

///|
/// Creates an effect owned by this scope.
pub fn Scope::effect(self : Scope, f : () -> Unit) -> Effect {
  guard !self.disposed else {
    abort("Scope::effect called on a disposed scope")
  }
  let eff = Effect(self.runtime, f)
  self.cells.push(eff.id())
  eff
}

///|
/// Creates an eager derived facade owned by this scope.
pub fn[T : Eq] Scope::eager_derived(
  self : Scope,
  compute_fn : () -> T,
) -> EagerDerived[T] {
  guard !self.disposed else {
    abort("Scope::eager_derived called on a disposed scope")
  }
  let derived = EagerDerived(self.runtime, compute_fn)
  self.cells.push(derived.id())
  derived
}

///|
/// Registers an observer with this scope for automatic disposal.
///
/// When the scope is disposed, the observer is disposed in the dispose_hooks
/// phase (step 2 of disposal order — after children, before owned cells).
/// This ensures observers are cleaned up before their potential targets.
///
/// Returns the observer for immediate use.
pub fn[T] Scope::add_observer(self : Scope, obs : Observer[T]) -> Observer[T] {
  guard !self.disposed else {
    abort("Scope::add_observer called on a disposed scope")
  }
  self.dispose_hooks.push(fn() { obs.dispose() })
  obs
}

///|
/// Registers a watch with this scope for automatic disposal.
///
/// When the scope is disposed, the watch is disposed in the dispose_hooks
/// phase (step 2 of disposal order — after children, before owned cells).
///
/// Returns the watch for immediate use.
pub fn[T] Scope::add_watch(self : Scope, watch : Watch[T]) -> Watch[T] {
  guard !self.disposed else {
    abort("Scope::add_watch called on a disposed scope")
  }
  self.dispose_hooks.push(fn() { watch.dispose() })
  watch
}

///|
/// Creates a GC-safe watch on a derived value, owned by this scope.
///
/// Folds three steps into one call: creates `derived.watch()`, registers it
/// with this scope for automatic disposal, and performs one priming read.
/// The priming read computes the target so its upstream `gc_dependencies`
/// are recorded — on return the watch is a GC root AND the upstream graph
/// survives a `Runtime::gc()` that runs before the first consumer read.
/// (An uncomputed watched terminal has empty gc_dependencies, so a bare
/// `scope.add_watch(derived.watch())` without a priming read loses its
/// upstream to gc; see the contrast test in `incr/tests/scope_test.mbt`.)
///
/// Aborts if the priming read fails (cycle or disposed target) — note this
/// is structurally unreachable today: a cycle is always mediated inside the
/// compute that observes it (the compute must produce a `T`, and a raising
/// compute aborts in `read_honest_impl`), and a disposed target already
/// aborts at `derived.watch()` creation. The abort is the honest signature
/// for "priming cannot fail", not a live error channel.
pub fn[T] Scope::watch(self : Scope, derived : Derived[T]) -> Watch[T] {
  guard !self.disposed else { abort("Scope::watch called on a disposed scope") }
  let watch = self.add_watch(derived.watch())
  ignore(watch.read_or_abort())
  watch
}

///|
/// Creates a GC-safe watch on a reachable derived value, owned by this scope.
///
/// Folds watch creation, scope registration, and the priming read performed by
/// `ReachableDerived::watch()` into one call. MoonBit does not allow a second
/// `Scope::watch` overload; use this for `ReachableDerived` and `Scope::watch`
/// for `Derived`.
pub fn[T : Eq] Scope::watch_reachable(
  self : Scope,
  derived : ReachableDerived[T],
) -> Watch[T] {
  guard !self.disposed else {
    abort("Scope::watch_reachable called on a disposed scope")
  }
  self.add_watch(derived.watch())
}

///|
/// Registers an array of CellIds with this scope for bulk disposal.
///
/// When the scope is disposed, all registered cells are disposed.
/// This is the low-level building block for `add_input_fields(scope, owner)`.
pub fn Scope::add_cell_ids(self : Scope, ids : Array[CellId]) -> Unit {
  guard !self.disposed else {
    abort("Scope::add_cell_ids called on a disposed scope")
  }
  let runtime_id = self.runtime.core.runtime_id
  for id in ids {
    guard id.runtime_id == runtime_id else {
      abort("Scope::add_cell_ids: CellId belongs to a different Runtime")
    }
    self.cells.push(id)
  }
}

///|
/// Adopts all cells from an `InputFieldOwner` into this scope for bulk disposal.
///
/// This is the method-style version of `add_input_fields(scope, owner)`. Use it
/// to register cells that were created outside a scope (e.g. via `map` or
/// raw constructors) with a scope's lifecycle.
///
/// Returns the trackable value for convenient chaining.
///
/// # Example
///
/// ```moonbit nocheck
/// let scope = Scope::new(rt)
/// let base = scope.derived(fn() { 42 })
/// let d = base.map(fn(v) { v + 1 })
/// scope.adopt(d)
/// scope.dispose()   // d is disposed
/// ```
pub fn[T : InputFieldOwner] Scope::adopt(self : Scope, tracked : T) -> T {
  guard !self.disposed else { abort("Scope::adopt called on a disposed scope") }
  self.add_cell_ids(tracked.cell_ids())
  tracked
}
