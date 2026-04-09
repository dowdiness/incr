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
  Repr::record(
    {
      "cells": to_repr(self.cells),
      "children": to_repr(self.children),
      "dispose_hooks": Repr::literal(
        "<" + self.dispose_hooks.length().to_string() + " hooks>",
      ),
      "disposed": to_repr(self.disposed),
    },
  )
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
