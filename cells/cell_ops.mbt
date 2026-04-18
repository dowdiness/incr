///|
using @shared {type CellMeta, trait CellOps, trait Committable}

///|
/// Capability trait: dependency tracking during computation.
///
/// Groups the tracking-stack lifecycle methods on Runtime. These methods
/// manage the `ActiveQuery` stack that records which cells are read during
/// a memo's compute function.
///
/// # Dispatch semantics
///
/// Not used for polymorphic dispatch — purely organizational. All call sites
/// invoke these methods on a concrete `Runtime` value (e.g. `self.push_tracking(id)`),
/// never through a trait object (`&Tracker`). MoonBit resolves `impl Trait for Type
/// with method` calls statically when the receiver type is known at the call site,
/// so there is no vtable overhead. These could equivalently be `fn Runtime::` methods;
/// the trait grouping provides navigability and documents the contract.
priv trait Tracker {
  push_tracking(Self, CellId) -> Unit
  pop_tracking(Self) -> (Array[CellId], @hashset.HashSet[CellId])
  record_dependency(Self, CellId) -> Unit
}

///|
/// Capability trait: revision lifecycle management.
///
/// Groups the revision-bumping methods on Runtime. These methods control
/// the monotonic revision counter and per-durability change tracking.
///
/// # Dispatch semantics
///
/// Same as `Tracker` — purely organizational, no polymorphic dispatch. All
/// call sites use concrete `Runtime` receivers, so calls are resolved statically.
priv trait RevisionManager {
  advance_revision(Self, Durability) -> Unit
  bump_revision(Self, Durability) -> Unit
}

///|
/// Lifecycle operations for cells: disposal, observer notifications.
///
/// Unlike CellOps (read-only metadata), CellLifecycle methods perform
/// mutations and require Runtime access. Stored as `&CellLifecycle` in
/// `RuntimeCore.cell_lifecycle`, indexed by `CellId.id`.
///
/// # Layer 3 status
///
/// `dispose_cell` migrates existing dispose logic into trait impls.
/// `on_observe` and `on_unobserve` are no-ops — Layer 4 fills them in
/// for HybridMemo (push activation/suspension) and PushReactive.
priv trait CellLifecycle {
  dispose_cell(Self, Runtime, CellId) -> Unit
  on_observe(Self, Runtime, CellId) -> Unit = _
  on_unobserve(Self, Runtime, CellId) -> Unit = _
}

///|
/// Default: on_observe is a no-op. Layer 4 overrides for push cells.
impl CellLifecycle with on_observe(_self, _rt, _cell_id) -> Unit {
  ()
}

///|
/// Default: on_unobserve is a no-op. Layer 4 overrides for push cells.
impl CellLifecycle with on_unobserve(_self, _rt, _cell_id) -> Unit {
  ()
}
