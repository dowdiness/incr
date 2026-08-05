///| PROTOTYPE — product-local adapter over an opaque kernel handle.
pub(all) struct ProductLocalView[T] {
  priv handle : @probe.OpaqueView[T]
  priv honest_getter : @probe.HonestGetter[T]
  priv plain_getter : @probe.PlainGetter[T]
}

///| Creates product-local callable getters while retaining the opaque handle.
pub fn[T] ProductLocalView::ProductLocalView(
  handle : @probe.OpaqueView[T],
) -> ProductLocalView[T] {
  {
    handle,
    honest_getter: () => handle.get(),
    plain_getter: () => handle.get_or_abort(),
  }
}

///| Reads through the product-local honest getter.
pub fn[T] ProductLocalView::get(
  self : ProductLocalView[T],
) -> Result[T, @incr.ReadError] {
  (self.honest_getter)()
}

///| Reads through the product-local aborting getter.
pub fn[T] ProductLocalView::get_or_abort(self : ProductLocalView[T]) -> T {
  (self.plain_getter)()
}

///| Returns the retained kernel identity.
pub fn[T] ProductLocalView::id(self : ProductLocalView[T]) -> @incr.CellId {
  self.handle.id()
}

///| Returns the retained Runtime provenance.
pub fn[T] ProductLocalView::runtime_id(
  self : ProductLocalView[T],
) -> @incr.RuntimeId {
  self.handle.runtime_id()
}

///| Returns the retained diagnostic label.
pub fn[T] ProductLocalView::label(self : ProductLocalView[T]) -> String? {
  self.handle.label()
}

///| Runs a UI-shaped callback while preserving graph read errors.
pub fn[T] bind_honest(
  read : @probe.HonestGetter[T],
  render : (T) -> Unit,
) -> Result[Unit, @incr.ReadError] {
  match read() {
    Ok(value) => {
      render(value)
      Ok(())
    }
    Err(error) => Err(error)
  }
}

///| Runs a UI-shaped callback with the aborting getter contract.
pub fn[T] bind_plain(read : @probe.PlainGetter[T], render : (T) -> Unit) -> Unit {
  render(read())
}

///| Probes transparent getter and cell-bound updater syntax.
pub fn probe_transparent_input() -> Int {
  let rt = @incr.Runtime()
  let (read, force_set, update) = @probe.transparent_input(
    rt,
    1,
    label="transparent",
  )
  force_set(2)
  update(value => value + 3)
  read()
}

///| Probes opaque read/write syntax and recoverable-read shape.
pub fn probe_opaque_input() -> Int {
  let rt = @incr.Runtime()
  let (view, writer) = @probe.opaque_input(rt, 1, label="opaque")
  writer.force_set(2)
  writer.update(value => value + 3)
  match view.get() {
    Ok(value) => value
    Err(_) => -1
  }
}

///| Probes product-local callable syntax over a retained opaque handle.
pub fn probe_two_layer_input() -> Int {
  let rt = @incr.Runtime()
  let (handle, writer) = @probe.opaque_input(rt, 1, label="two-layer")
  let view = ProductLocalView(handle)
  writer.force_set(2)
  writer.update(value => value + 3)
  view.get_or_abort()
}

///| Probes label, identity, and Runtime provenance on opaque handles.
pub fn probe_opaque_metadata() -> Bool {
  let left_rt = @incr.Runtime()
  let right_rt = @incr.Runtime()
  let (left, _) = @probe.opaque_input(left_rt, 1, label="left")
  let (same, _) = @probe.opaque_input(left_rt, 2, label="same")
  let (other, _) = @probe.opaque_input(right_rt, 3, label="other")
  left.label() == Some("left") &&
  left.same_runtime(same) &&
  !left.same_runtime(other) &&
  left.runtime_id() == left_rt.id()
}

///| Probes the current recoverable self-cycle behavior through the two layers.
pub fn probe_recoverable_cycle() -> Int {
  let rt = @incr.Runtime()
  let cell_ref : Ref[@incr.Derived[Int]?] = Ref(None)
  let derived = @incr.Derived(rt, () => {
    match cell_ref.val {
      Some(self) =>
        match self.get() {
          Ok(value) => value
          Err(_) => 41
        }
      None => 0
    }
  }, label="cycle")
  cell_ref.val = Some(derived)
  let handle = @probe.opaque_derived(derived, label="cycle")
  let view = ProductLocalView(handle)
  match view.get() {
    Ok(value) => value
    Err(_) => -1
  }
}

///| Probes a UI-shaped adapter without discarding the opaque metadata handle.
pub fn probe_ui_binding() -> Int {
  let rt = @incr.Runtime()
  let (handle, writer) = @probe.opaque_input(rt, 1, label="ui")
  let view = ProductLocalView(handle)
  let rendered = Ref(0)
  writer.force_set(7)
  let result = bind_honest(() => view.get(), value => rendered.val = value)
  match result {
    Ok(_) => rendered.val
    Err(_) => -1
  }
}
