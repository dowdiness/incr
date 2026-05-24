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
}

///|
/// Manual Debug impl because `Array[() -> Unit]` cannot derive Debug
/// (the `ignore` parameter only filters top-level field types, not nested types).
pub impl Debug for Scope with to_repr(self) {
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
/// Creates an input facade owned by this scope.
pub fn[T] Scope::input(
  self : Scope,
  initial : T,
  durability? : Durability = Low,
  label? : String,
) -> Input[T] {
  guard !self.disposed else { abort("Scope::input called on a disposed scope") }
  let input = Input(self.runtime, initial, durability~, label?)
  self.cells.push(input.inner.id())
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
  self.cells.push(field.inner.id())
  field
}

///|
/// Creates a memo owned by this scope.
pub fn[T : Eq] Scope::memo(
  self : Scope,
  f : () -> T raise Failure,
  label? : String,
) -> Memo[T] {
  guard !self.disposed else { abort("Scope::memo called on a disposed scope") }
  let m = Memo::new(self.runtime, f, label?)
  self.cells.push(m.id())
  m
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
  self.cells.push(derived.inner.id())
  derived
}

///|
/// Creates a hybrid memo owned by this scope.
pub fn[T : Eq] Scope::hybrid_memo(
  self : Scope,
  f : () -> T raise Failure,
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
  self.cells.push(derived.inner.id())
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
  let a : Accumulator[T] = Accumulator::new(rt=self.runtime, label?)
  self.dispose_hooks.push(() => a.dispose())
  a
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
  self.cells.push(derived.inner.id())
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
/// Registers an array of CellIds with this scope for bulk disposal.
///
/// When the scope is disposed, all registered cells are disposed.
/// This is the low-level building block for `add_tracked(scope, tracked)`.
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
