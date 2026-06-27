///|
/// Target-name input cell facade over `Signal`.
pub(all) struct Input[T] {
  priv inner : Signal[T]
}

///|
/// Creates an input cell with the given initial value.
pub fn[T] Input::Input(
  rt : Runtime,
  initial : T,
  durability? : Durability = Low,
  label? : String,
) -> Input[T] {
  { inner: Signal(rt, initial, durability~, label?) }
}

///|
/// Returns the current value and records a dependency when tracked.
pub fn[T] Input::get(self : Input[T]) -> T {
  self.inner.get()
}

///|
/// Returns the current value without recording a dependency.
pub fn[T] Input::peek(self : Input[T]) -> T {
  self.inner.peek()
}

///|
/// Sets the input to a new value, skipping same-value updates.
pub fn[T : Eq] Input::set(self : Input[T], new_value : T) -> Unit {
  self.inner.set(new_value)
}

///|
/// Sets the input to a value and always bumps the relevant revision.
pub fn[T] Input::force_set(self : Input[T], new_value : T) -> Unit {
  self.inner.set_unconditional(new_value)
}

///|
/// Returns true. Inputs are directly-set cells and are always fresh.
pub fn[T] Input::is_fresh(self : Input[T]) -> Bool {
  self.inner.is_up_to_date()
}

///|
/// Returns the unique cell identifier for this input. Stable across reads —
/// useful for graph-shape probes and cross-runtime identity checks
/// (`input.id().runtime_id`).
pub fn[T] Input::id(self : Input[T]) -> CellId {
  self.inner.id()
}

///|
/// Creates a new `Derived[U]` from this input by applying `f` to the current
/// value on each read. Uses equality-based backdating: when recomputation
/// produces a value equal to the previous output, downstream dependents skip
/// recomputation.
///
/// Equivalent to `scope.derived(() => f(input.get()))` but without the scope
/// parameter — the input already holds a runtime reference.
pub fn[T, U : Eq] Input::derived(
  self : Input[T],
  f : (T) -> U,
  label? : String,
) -> Derived[U] {
  Derived(self.inner.rt, () => f(self.get()), label?)
}

///|
/// Creates a new `Derived[U]` from this input by applying `f` to the current
/// value on each read, without equality-based backdating. Each recomputation
/// advances the changed-at revision unconditionally, even when the output
/// equals the previous value. Accepts output types that do not implement `Eq`.
///
/// Equivalent to `scope.derived_no_backdate(() => f(input.get()))` but without
/// the scope parameter — the input already holds a runtime reference.
pub fn[T, U] Input::derived_no_backdate(
  self : Input[T],
  f : (T) -> U,
  label? : String,
) -> Derived[U] {
  { inner: Memo::new_no_backdate(self.inner.rt, () => f(self.get()), label?) }
}

///|
/// Target-name field-level input facade over `TrackedCell`.
pub(all) struct InputField[T] {
  priv inner : TrackedCell[T]
}

///|
/// Creates a field-level input cell with the given initial value.
pub fn[T] InputField::InputField(
  rt : Runtime,
  initial : T,
  durability? : Durability = Low,
  label? : String,
) -> InputField[T] {
  { inner: TrackedCell(rt, initial, durability~, label?) }
}

///|
/// Returns the current value and records a dependency when tracked.
pub fn[T] InputField::get(self : InputField[T]) -> T {
  self.inner.get()
}

///|
/// Returns the current value without recording a dependency.
pub fn[T] InputField::peek(self : InputField[T]) -> T {
  self.inner.peek()
}

///|
/// Sets the field to a new value, skipping same-value updates.
pub fn[T : Eq] InputField::set(self : InputField[T], new_value : T) -> Unit {
  self.inner.set(new_value)
}

///|
/// Sets the field to a value and always bumps the relevant revision.
pub fn[T] InputField::force_set(self : InputField[T], new_value : T) -> Unit {
  self.inner.set_unconditional(new_value)
}

///|
/// Returns the unique identifier for this field.
pub fn[T] InputField::id(self : InputField[T]) -> CellId {
  self.inner.id()
}

///|
/// Returns the durability level configured at construction.
pub fn[T] InputField::durability(self : InputField[T]) -> Durability {
  self.inner.durability()
}

///|
/// Registers a callback that fires whenever this field's value changes.
pub fn[T] InputField::on_change(self : InputField[T], f : (T) -> Unit) -> Unit {
  self.inner.on_change(f)
}

///|
/// Removes this field's `on_change` callback.
pub fn[T] InputField::clear_on_change(self : InputField[T]) -> Unit {
  self.inner.clear_on_change()
}

///|
/// Returns true. Input fields are directly-set cells and are always fresh.
pub fn[T] InputField::is_fresh(self : InputField[T]) -> Bool {
  self.inner.is_up_to_date()
}

///|
/// Disposes this field by disposing its underlying tracked cell.
pub fn[T] InputField::dispose(self : InputField[T]) -> Unit {
  self.inner.dispose()
}

///|
/// Returns true if this field has been disposed.
pub fn[T] InputField::is_disposed(self : InputField[T]) -> Bool {
  self.inner.is_disposed()
}

///|
/// Returns the compatibility tracked-cell handle for interop.
pub fn[T] InputField::as_tracked_cell(self : InputField[T]) -> TrackedCell[T] {
  self.inner
}

///|
/// Target-name lazy derived cell facade over `Memo`.
pub(all) struct Derived[T] {
  priv inner : Memo[T]
}

///|
/// Creates a lazy derived value.
pub fn[T : Eq] Derived::Derived(
  rt : Runtime,
  compute : () -> T raise Failure,
  label? : String,
) -> Derived[T] {
  { inner: Memo(rt, compute, label?) }
}

///|
/// Creates a fallible lazy derived value: a recoverable, domain-specific
/// failure is expressed in the value as `Result[V, E]`, never raised. The
/// compute is `noraise`, so the domain error is *forced* into the value, where
/// it is cached, change-detected (`Eq`), and replayed like any other value;
/// reads surface only graph failures (cycles), never an uncatchable abort.
/// A `raise Failure` from a plain `Derived` compute is a defect, not a domain
/// error. See docs/design/specs/2026-05-28-honest-read-error-ownership.md.
pub fn[V : Eq, E : Eq] Derived::fallible(
  rt : Runtime,
  compute : () -> Result[V, E],
  label? : String,
) -> Derived[Result[V, E]] {
  // The public `compute` is noraise (domain errors are forced into the value);
  // the base ctor wants `raise Failure`, so wrap in a fresh lambda checked
  // against that raising type. The wrapper never actually raises.
  Derived::Derived(rt, fn() { compute() }, label?)
}

///|
/// Creates a lazy derived value without equality-based backdating. Each
/// recomputation advances the changed-at revision unconditionally, even when
/// the output equals the previous value. Accepts output types that do not
/// implement `Eq`.
pub fn[T] Derived::derived_no_backdate(
  rt : Runtime,
  compute : () -> T raise Failure,
  label? : String,
) -> Derived[T] {
  { inner: Memo::new_no_backdate(rt, compute, label?) }
}

///|
/// Transforms this derived value into another derived value on the same runtime.
///
/// The mapped value never backdates, so `U` does not need to implement `Eq`.
pub fn[T, U] Derived::map_no_backdate(
  self : Derived[T],
  f : (T) -> U,
  label? : String,
) -> Derived[U] {
  {
    inner: Memo::new_no_backdate(
      self.inner.rt,
      () => f(self.get_or_abort()),
      label?,
    ),
  }
}

///|
/// Transforms this derived value into another `Eq`-backdated derived value on
/// the same runtime.
///
/// When recomputation produces a mapped value equal to the previous mapped
/// value, the returned cell preserves its `changed_at` timestamp so downstream
/// dependents can skip recomputation.
pub fn[T, U : Eq] Derived::map(
  self : Derived[T],
  f : (T) -> U,
  label? : String,
) -> Derived[U] {
  Derived(self.inner.rt, () => f(self.get_or_abort()), label?)
}

///|
fn[T1, T2] Derived::check_same_runtime(
  self : Derived[T1],
  other : Derived[T2],
  caller : String,
) -> Unit {
  let expected = self.inner.id().runtime_id
  let actual = other.inner.id().runtime_id
  if actual != expected {
    abort(
      caller +
      ": input belongs to Runtime " +
      actual.to_string() +
      ", expected Runtime " +
      expected.to_string(),
    )
  }
}

///|
/// Combines two derived values on the same runtime.
///
/// The mapped value never backdates, so `U` does not need to implement `Eq`.
/// Aborts if `other` belongs to a different runtime.
pub fn[T1, T2, U] Derived::map2_no_backdate(
  self : Derived[T1],
  other : Derived[T2],
  f : (T1, T2) -> U,
  label? : String,
) -> Derived[U] {
  self.check_same_runtime(other, "Derived::map2_no_backdate")
  {
    inner: Memo::new_no_backdate(
      self.inner.rt,
      () => f(self.get_or_abort(), other.get_or_abort()),
      label?,
    ),
  }
}

///|
/// Combines two derived values into another `Eq`-backdated derived value.
///
/// Aborts if `other` belongs to a different runtime. When recomputation
/// produces a mapped value equal to the previous mapped value, the returned
/// cell preserves its `changed_at` timestamp so downstream dependents can skip
/// recomputation.
pub fn[T1, T2, U : Eq] Derived::map2(
  self : Derived[T1],
  other : Derived[T2],
  f : (T1, T2) -> U,
  label? : String,
) -> Derived[U] {
  self.check_same_runtime(other, "Derived::map2")
  Derived(
    self.inner.rt,
    () => f(self.get_or_abort(), other.get_or_abort()),
    label?,
  )
}

///|
/// Combines three derived values on the same runtime.
///
/// The mapped value never backdates, so `U` does not need to implement `Eq`.
/// Aborts if any input belongs to a different runtime.
pub fn[T1, T2, T3, U] Derived::map3_no_backdate(
  self : Derived[T1],
  second : Derived[T2],
  third : Derived[T3],
  f : (T1, T2, T3) -> U,
  label? : String,
) -> Derived[U] {
  self.check_same_runtime(second, "Derived::map3_no_backdate")
  self.check_same_runtime(third, "Derived::map3_no_backdate")
  {
    inner: Memo::new_no_backdate(
      self.inner.rt,
      () => f(self.get_or_abort(), second.get_or_abort(), third.get_or_abort()),
      label?,
    ),
  }
}

///|
/// Combines three derived values into another `Eq`-backdated derived value.
///
/// Aborts if any input belongs to a different runtime. When recomputation
/// produces a mapped value equal to the previous mapped value, the returned
/// cell preserves its `changed_at` timestamp so downstream dependents can skip
/// recomputation.
pub fn[T1, T2, T3, U : Eq] Derived::map3(
  self : Derived[T1],
  second : Derived[T2],
  third : Derived[T3],
  f : (T1, T2, T3) -> U,
  label? : String,
) -> Derived[U] {
  self.check_same_runtime(second, "Derived::map3")
  self.check_same_runtime(third, "Derived::map3")
  Derived(
    self.inner.rt,
    () => f(self.get_or_abort(), second.get_or_abort(), third.get_or_abort()),
    label?,
  )
}

///|
/// Internal: build a `Derived` with an explicit backdate comparator, for the
/// non-`Eq` construction paths (`BackdateEq` / custom-predicate tiers) that
/// cannot use the `Eq`-bound `Derived::Derived` / `Derived::fallible`. Threads
/// the comparator straight into `Memo::_create`, mirroring how
/// `Memo::new_memo` / `Memo::new_no_backdate` differ from `Memo::new` only in
/// the comparator. Package-internal: no `T` bound, so it must not be exposed
/// publicly without a deliberate API decision.
fn[T] Derived::with_backdate(
  rt : Runtime,
  compute : () -> T raise Failure,
  backdate_eq : (T, T) -> Bool,
  label? : String,
) -> Derived[T] {
  { inner: Memo::_create(rt, compute, label?, backdate_eq) }
}

///|
/// Strict graph read. Requires an active tracked context.
pub fn[T] Derived::get(self : Derived[T]) -> Result[T, ReadError] {
  self.inner.get_strict_honest()
}

///|
/// Strict graph read that aborts on invalid context or any read error.
pub fn[T] Derived::get_or_abort(self : Derived[T]) -> T {
  match self.get() {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Permissive read. Works outside the graph and records a dependency if tracked.
pub fn[T] Derived::read(self : Derived[T]) -> Result[T, ReadError] {
  self.inner.read_honest()
}

///|
/// Permissive read that aborts on any read error.
pub fn[T] Derived::read_or_abort(self : Derived[T]) -> T {
  match self.read() {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Creates a long-lived outside-graph reader that returns read errors.
pub fn[T] Derived::watch(self : Derived[T]) -> Watch[T] {
  self.inner.watch_result()
}

///|
/// Returns whether this derived value is verified at the current revision.
pub fn[T] Derived::is_fresh(self : Derived[T]) -> Bool {
  self.inner.is_up_to_date()
}

///|
/// Returns the unique cell identifier for this derived value. Stable
/// across reads — useful for graph-shape probes (gc anchoring, edge
/// inspection) where a cell needs an identity independent of its value.
pub fn[T] Derived::id(self : Derived[T]) -> CellId {
  self.inner.id()
}

///|
/// Returns the array of cell IDs that this derived value depends on.
pub fn[T] Derived::dependencies(self : Derived[T]) -> Array[CellId] {
  self.inner.dependencies()
}

///|
/// Returns the revision at which this derived value was last verified.
pub fn[T] Derived::verified_at(self : Derived[T]) -> Revision {
  self.inner.verified_at()
}

///|
/// Registers a callback that fires whenever this derived value's output changes.
pub fn[T] Derived::on_change(self : Derived[T], f : (T) -> Unit) -> Unit {
  self.inner.on_change(f)
}

///|
/// Removes the `on_change` callback for this derived value.
pub fn[T] Derived::clear_on_change(self : Derived[T]) -> Unit {
  self.inner.clear_on_change()
}

///|
/// Acquires an `Observer` that roots this derived cell against gc. The
/// caller must `dispose()` the returned observer when done; otherwise
/// the cell (and its dependency cone) stays pinned indefinitely. See
/// `Memo::observe` for the underlying semantics.
pub fn[T] Derived::observe(self : Derived[T]) -> Observer[T] {
  self.inner.observe()
}

///|
/// Revision at which this derived value's content last actually changed.
/// Backdated by structural equality: when a recomputation produces a
/// value equal to the previous one, `changed_at` is preserved rather than
/// advanced. See `Memo::changed_at`.
pub fn[T] Derived::changed_at(self : Derived[T]) -> Revision {
  self.inner.changed_at()
}

///|
/// Returns true if this derived value has been disposed.
pub fn[T] Derived::is_disposed(self : Derived[T]) -> Bool {
  self.inner.is_disposed()
}

///|
/// Tracked accumulator read intended for use inside a compute closure.
/// Returns a defensive copy of the values `self` pushed during its last
/// successful compute, forces verification of `self`, and stages a
/// synthetic dep on the current frame. See `Memo::accumulated`.
pub fn[T, A] Derived::accumulated(
  self : Derived[T],
  acc : Accumulator[A],
) -> Result[Array[A], ReadError] raise Failure {
  let rt = self.inner.rt
  rt.check_cross_runtime(rt.core.runtime_id, "Derived::accumulated")
  rt.check_cross_runtime(
    acc.slot_id.runtime_id,
    "Derived::accumulated (Accumulator)",
  )
  if rt.static_recompute_depth > 0 {
    fail("Derived::accumulated is unsupported inside static Derived recompute")
  }
  let slot = rt.accumulator_slots[acc.slot_id.id]
  if slot.disposed {
    fail("Derived::accumulated called on disposed Accumulator")
  }
  if rt.is_cell_disposed(self.inner.cell_id) {
    return Err(ReadError::disposed(self.inner.cell_id))
  }
  let verified = rt.ensure_computed_untracked(self.inner.cell_id) catch {
    e => {
      rt.drain_pending_events_direct()
      abort("Derived::accumulated target compute raised: " + e.to_string())
    }
  }
  let result = match verified {
    Err(e) => Err(ReadError::cycle(e))
    Ok(_) => {
      let current_rev = (slot.push_revised_at_for)(self.inner.cell_id)
      match rt.top_active_query() {
        Some(frame) =>
          match rt.core.cell_index[frame.cell_id.id] {
            PullMemo(_) | HybridMemo(_) =>
              rt.accumulator_commit_hook
              .ensure_for_cell(frame.cell_id)
              .ensure_reads()
              .set((acc.slot_id, self.inner.cell_id), current_rev)
            _ => ()
          }
        None => ()
      }
      let vs = match acc.per_memo.get(self.inner.cell_id) {
        Some(arr) => arr.copy()
        None => []
      }
      Ok(vs)
    }
  }
  if rt.has_pending_events() {
    rt.drain_pending_events_if_idle()
  }
  result
}

///|
pub fn[T, A] Derived::accumulated_or_abort(
  self : Derived[T],
  acc : Accumulator[A],
) -> Array[A] raise Failure {
  match self.accumulated(acc) {
    Ok(vs) => vs
    Err(e) => abort(e.format_path())
  }
}

///|
/// Untracked accumulator read. Returns `[]` when the accumulator or
/// target derived value is disposed; otherwise a defensive copy.
/// Permissive on disposal: returns `[]` if the accumulator or target memo
/// is disposed. Matches Signal::peek semantics.
pub fn[T, A] Derived::accumulated_peek(
  self : Derived[T],
  acc : Accumulator[A],
) -> Array[A] {
  let rt = self.inner.rt
  rt.check_cross_runtime(rt.core.runtime_id, "Derived::accumulated_peek")
  rt.check_cross_runtime(
    acc.slot_id.runtime_id,
    "Derived::accumulated_peek (Accumulator)",
  )
  if rt.static_recompute_depth > 0 {
    abort(
      "Derived::accumulated_peek is unsupported inside static Derived recompute",
    )
  }
  let slot = rt.accumulator_slots[acc.slot_id.id]
  if slot.disposed {
    return []
  }
  if rt.is_cell_disposed(self.inner.cell_id) {
    return []
  }
  match acc.per_memo.get(self.inner.cell_id) {
    Some(vs) => vs.copy()
    None => []
  }
}

///|
/// Compatibility alias: Result-style accumulator read on `Derived`.
pub fn[T, A] Derived::accumulated_result(
  self : Derived[T],
  acc : Accumulator[A],
) -> Result[Array[A], ReadError] raise Failure {
  self.accumulated(acc)
}

///|
/// Target-name reachable lazy derived cell facade over `HybridMemo`.
pub(all) struct ReachableDerived[T] {
  priv inner : HybridMemo[T]
}

///|
/// Creates a reachable lazy derived value.
pub fn[T : Eq] ReachableDerived::ReachableDerived(
  rt : Runtime,
  compute : () -> T raise Failure,
  label? : String,
) -> ReachableDerived[T] {
  { inner: HybridMemo(rt, compute, label?) }
}

///|
/// Strict graph read. Requires an active tracked context.
pub fn[T : Eq] ReachableDerived::get(
  self : ReachableDerived[T],
) -> Result[T, ReadError] {
  self.inner.get_strict_honest()
}

///|
/// Strict graph read that aborts on invalid context or any read error.
pub fn[T : Eq] ReachableDerived::get_or_abort(self : ReachableDerived[T]) -> T {
  match self.get() {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Permissive read. Works outside the graph and records a dependency if tracked.
pub fn[T : Eq] ReachableDerived::read(
  self : ReachableDerived[T],
) -> Result[T, ReadError] {
  self.inner.read_honest()
}

///|
/// Permissive read that aborts on any read error.
pub fn[T : Eq] ReachableDerived::read_or_abort(self : ReachableDerived[T]) -> T {
  match self.read() {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Creates a long-lived outside-graph reader that returns read errors.
pub fn[T : Eq] ReachableDerived::watch(self : ReachableDerived[T]) -> Watch[T] {
  self.inner.watch_result()
}

///|
/// Returns whether this reachable derived value is verified at the current revision.
pub fn[T] ReachableDerived::is_fresh(self : ReachableDerived[T]) -> Bool {
  self.inner.is_up_to_date()
}

///|
/// Returns the unique cell identifier for this reachable derived value.
/// Stable across reads — useful for graph-shape probes (gc anchoring, edge
/// inspection) where a cell needs an identity independent of its value.
pub fn[T] ReachableDerived::id(self : ReachableDerived[T]) -> CellId {
  self.inner.id()
}

///|
/// Acquires an `Observer` that roots this reachable derived cell against
/// gc. The caller must `dispose()` the returned observer when done.
pub fn[T : Eq] ReachableDerived::observe(
  self : ReachableDerived[T],
) -> Observer[T] {
  self.inner.observe()
}

///|
/// Returns true if this reachable derived cell has been disposed.
pub fn[T] ReachableDerived::is_disposed(self : ReachableDerived[T]) -> Bool {
  self.inner.is_disposed()
}

///|
/// Target-name eager derived cell facade over `Reactive`.
pub(all) struct EagerDerived[T] {
  priv inner : Reactive[T]
}

///|
/// Creates an eager derived value.
pub fn[T : Eq] EagerDerived::EagerDerived(
  rt : Runtime,
  compute : () -> T,
) -> EagerDerived[T] {
  { inner: Reactive::new(rt, compute) }
}

///|
/// Strict graph read. Requires an active tracked context.
pub fn[T] EagerDerived::get(self : EagerDerived[T]) -> T {
  self.inner.get()
}

///|
/// Permissive read. Works outside the graph and records a dependency if tracked.
pub fn[T] EagerDerived::read(self : EagerDerived[T]) -> T {
  self.inner.read_permissive()
}

///|
/// Creates a long-lived outside-graph reader for this eager derived value.
pub fn[T] EagerDerived::watch(self : EagerDerived[T]) -> Watch[T] {
  self.inner.watch_result()
}

///|
/// Returns the unique cell identifier for this eager derived value. Stable
/// across reads — useful for graph-shape probes (gc anchoring, edge
/// inspection) where a cell needs an identity independent of its value.
pub fn[T] EagerDerived::id(self : EagerDerived[T]) -> CellId {
  self.inner.id()
}

///|
/// Target-name keyed derived facade over `MemoMap`.
pub(all) struct DerivedMap[K, V] {
  priv inner : MemoMap[K, V]
  priv disposed : Ref[CellId?]
}

///|
/// Creates a keyed derived map.
pub fn[K : Hash + Eq, V] DerivedMap::DerivedMap(
  rt : Runtime,
  compute : (K) -> V raise Failure,
  label? : String,
) -> DerivedMap[K, V] {
  { inner: MemoMap(rt, compute, label?), disposed: { val: None } }
}

///|
/// Creates a fallible keyed derived map: a per-key recoverable domain failure
/// is expressed in the value as `Result[V, E]`, never raised. The compute is
/// `noraise`. See `Derived::fallible` and
/// docs/design/specs/2026-05-28-honest-read-error-ownership.md.
pub fn[K : Hash + Eq, V, E] DerivedMap::fallible(
  rt : Runtime,
  compute : (K) -> Result[V, E],
  label? : String,
) -> DerivedMap[K, Result[V, E]] {
  // See `Derived::fallible`: wrap the noraise compute for the base ctor.
  DerivedMap::DerivedMap(rt, fn(k) { compute(k) }, label?)
}

///|
fn[K, V] DerivedMap::guard_live(
  self : DerivedMap[K, V],
) -> Result[Unit, ReadError] {
  match self.disposed.val {
    None => Ok(())
    Some(id) => Err(ReadError::disposed(id))
  }
}

///|
fn[K, V] DerivedMap::dispose_from_scope(self : DerivedMap[K, V]) -> Unit {
  guard self.disposed.val is None else { return }
  let mut disposed_id : CellId? = None
  for _, memo in self.inner.entries {
    if disposed_id is None {
      disposed_id = Some(memo.id())
    }
  }
  let id = match disposed_id {
    Some(id) => id
    None => {
      let tombstone = Memo::new(
        self.inner.rt,
        () => (),
        label="derived_map_disposed",
      )
      tombstone.dispose()
      tombstone.id()
    }
  }
  self.disposed.val = Some(id)
  self.inner.clear()
}

///|
/// Strict graph read for `key`. Requires an active tracked context.
pub fn[K : Hash + Eq, V : Eq] DerivedMap::get(
  self : DerivedMap[K, V],
  key : K,
) -> Result[V, ReadError] {
  match self.guard_live() {
    Ok(_) => self.inner.get_strict_honest(key)
    Err(e) => Err(e)
  }
}

///|
/// Strict graph read for `key` that aborts on invalid context or any read error.
pub fn[K : Hash + Eq, V : Eq] DerivedMap::get_or_abort(
  self : DerivedMap[K, V],
  key : K,
) -> V {
  match self.get(key) {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Permissive read for `key`. Records a dependency if tracked.
pub fn[K : Hash + Eq, V : Eq] DerivedMap::read(
  self : DerivedMap[K, V],
  key : K,
) -> Result[V, ReadError] {
  match self.guard_live() {
    Ok(_) => self.inner.read_honest(key)
    Err(e) => Err(e)
  }
}

///|
/// Permissive read for `key` that aborts on any read error.
pub fn[K : Hash + Eq, V : Eq] DerivedMap::read_or_abort(
  self : DerivedMap[K, V],
  key : K,
) -> V {
  match self.read(key) {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
/// Returns the value for `key`, or `fallback` if a read error is detected.
pub fn[K : Hash + Eq, V : Eq] DerivedMap::read_or(
  self : DerivedMap[K, V],
  key : K,
  fallback : V,
) -> V {
  match self.read(key) {
    Ok(value) => value
    Err(_) => fallback
  }
}

///|
/// Returns the value for `key`, or computes a fallback from the read error.
pub fn[K : Hash + Eq, V : Eq] DerivedMap::read_or_else(
  self : DerivedMap[K, V],
  key : K,
  fallback : (ReadError) -> V,
) -> V {
  match self.read(key) {
    Ok(value) => value
    Err(e) => fallback(e)
  }
}

///|
/// Returns whether a cached entry exists for `key`.
pub fn[K : Hash + Eq, V] DerivedMap::has_cached(
  self : DerivedMap[K, V],
  key : K,
) -> Bool {
  match self.guard_live() {
    Ok(_) => self.inner.contains(key)
    Err(e) => abort(e.format_path())
  }
}

///|
/// Returns the number of cached entries.
pub fn[K, V] DerivedMap::cache_len(self : DerivedMap[K, V]) -> Int {
  match self.guard_live() {
    Ok(_) => self.inner.length()
    Err(e) => abort(e.format_path())
  }
}

///|
/// Removes cached entries whose underlying cells have been disposed.
pub fn[K : Hash + Eq, V] DerivedMap::sweep_cache(
  self : DerivedMap[K, V],
) -> Int {
  match self.guard_live() {
    Ok(_) => self.inner.sweep()
    Err(e) => abort(e.format_path())
  }
}

///|
/// Clears all cached entries.
pub fn[K, V] DerivedMap::clear_cache(self : DerivedMap[K, V]) -> Unit {
  match self.guard_live() {
    Ok(_) => self.inner.clear()
    Err(e) => abort(e.format_path())
  }
}

///|
/// Trackable implementation for input cells.
pub impl[T] Trackable for Input[T] with fn cell_ids(self) -> Array[CellId] {
  [self.id()]
}

///|
/// Trackable implementation for input field cells.
pub impl[T] Trackable for InputField[T] with fn cell_ids(self) -> Array[CellId] {
  [self.id()]
}

///|
/// Trackable implementation for derived cells (lazy recomputation).
pub impl[T] Trackable for Derived[T] with fn cell_ids(self) -> Array[CellId] {
  [self.id()]
}

///|
/// Trackable implementation for reachable derived cells (lazy with GC-alive).
pub impl[T] Trackable for ReachableDerived[T] with fn cell_ids(self) -> Array[
  CellId,
] {
  [self.id()]
}

///|
/// Trackable implementation for eager derived cells.
pub impl[T] Trackable for EagerDerived[T] with fn cell_ids(self) -> Array[
  CellId,
] {
  [self.id()]
}
