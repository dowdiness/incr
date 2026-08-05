///| PROTOTYPE — throwaway V12.5 interface alternatives probe.
/// A callable view that aborts on graph read errors.
pub type PlainGetter[T] = () -> T

///| A callable view that preserves recoverable graph read errors.
pub type HonestGetter[T] = () -> Result[T, @incr.ReadError]

///| An unconditional write capability created with an input.
pub type ForceSetter[T] = (T) -> Unit

///| A read-modify-write capability created with an input.
pub type Updater[T] = ((T) -> T) -> Unit

///| Adapts a current Derived into both transparent getter contracts.
pub fn[T] transparent_derived(
  derived : @incr.Derived[T],
) -> (PlainGetter[T], HonestGetter[T]) {
  (() => derived.read_or_abort(), () => derived.read())
}

///| Creates transparent read, force-write, and update capabilities together.
/// The updater is a prototype only: it is not safe against re-entrant writes.
pub fn[T] transparent_input(
  rt : @incr.Runtime,
  initial : T,
  label? : String,
) -> (PlainGetter[T], ForceSetter[T], Updater[T]) {
  let input = @incr.Input(rt, initial, label?)
  let read = () => input.get()
  let force_set = value => input.force_set(value)
  let update = transform => input.force_set(transform(input.peek()))
  (read, force_set, update)
}

///| An opaque read handle with provenance and diagnostic metadata.
pub(all) struct OpaqueView[T] {
  priv honest_read : HonestGetter[T]
  priv plain_read : PlainGetter[T]
  priv cell_id : @incr.CellId
  priv label : String?
}

///| Creates an opaque view from its kernel-facing capabilities.
fn[T] OpaqueView::OpaqueView(
  honest_read : HonestGetter[T],
  plain_read : PlainGetter[T],
  cell_id : @incr.CellId,
  label : String?,
) -> OpaqueView[T] {
  { honest_read, plain_read, cell_id, label }
}

///| Wraps a current Derived as an opaque View candidate.
pub fn[T] opaque_derived(
  derived : @incr.Derived[T],
  label? : String,
) -> OpaqueView[T] {
  OpaqueView(
    () => derived.read(),
    () => derived.read_or_abort(),
    derived.id(),
    label,
  )
}

///| Reads while preserving recoverable graph errors.
pub fn[T] OpaqueView::get(self : OpaqueView[T]) -> Result[T, @incr.ReadError] {
  (self.honest_read)()
}

///| Reads and aborts on a graph error.
pub fn[T] OpaqueView::get_or_abort(self : OpaqueView[T]) -> T {
  (self.plain_read)()
}

///| Returns the stable kernel identity carried by this handle.
pub fn[T] OpaqueView::id(self : OpaqueView[T]) -> @incr.CellId {
  self.cell_id
}

///| Returns the optional human-readable label carried by this handle.
pub fn[T] OpaqueView::label(self : OpaqueView[T]) -> String? {
  self.label
}

///| Returns the Runtime provenance carried by the cell identity.
pub fn[T] OpaqueView::runtime_id(self : OpaqueView[T]) -> @incr.RuntimeId {
  self.cell_id.runtime_id
}

///| Returns true when two handles have the same Runtime provenance.
pub fn[A, B] OpaqueView::same_runtime(
  self : OpaqueView[A],
  other : OpaqueView[B],
) -> Bool {
  self.runtime_id() == other.runtime_id()
}

///| Materializes the current read error as a diagnostic string when present.
pub fn[T] OpaqueView::diagnostic(self : OpaqueView[T]) -> String? {
  match self.get() {
    Ok(_) => None
    Err(error) => Some(error.format_path())
  }
}

///| An opaque write handle created alongside its input.
pub(all) struct OpaqueWriter[T] {
  priv force_set_fn : ForceSetter[T]
  priv update_fn : Updater[T]
}

///| Creates an opaque write handle from cell-bound capabilities.
fn[T] OpaqueWriter::OpaqueWriter(
  force_set_fn : ForceSetter[T],
  update_fn : Updater[T],
) -> OpaqueWriter[T] {
  { force_set_fn, update_fn }
}

///| Creates opaque read and write handles for one input.
pub fn[T] opaque_input(
  rt : @incr.Runtime,
  initial : T,
  label? : String,
) -> (OpaqueView[T], OpaqueWriter[T]) {
  let input = @incr.Input(rt, initial, label?)
  let view = OpaqueView(
    () => input.get_result(),
    () => input.get(),
    input.id(),
    label,
  )
  let writer = OpaqueWriter(
    value => input.force_set(value),
    transform => input.force_set(transform(input.peek())),
  )
  (view, writer)
}

///| Writes unconditionally through the cell-bound capability.
pub fn[T] OpaqueWriter::force_set(self : OpaqueWriter[T], value : T) -> Unit {
  (self.force_set_fn)(value)
}

///| Applies the prototype read-modify-write capability.
/// This is not safe against re-entrant writes.
pub fn[T] OpaqueWriter::update(
  self : OpaqueWriter[T],
  transform : (T) -> T,
) -> Unit {
  (self.update_fn)(transform)
}
