///|
/// Private fixed-dependency derived prototype used by benchmark probes.
///
/// This is deliberately not a public API. It keeps the target-facing name
/// (`Derived`) while reusing the existing pull backend (`MemoData` /
/// `PullMemo`, still the internal storage names) so the probe measures one
/// engine-path change at a time.
priv struct StaticDerivedProbe[T] {
  rt : Runtime
  cell_id : CellId
  compute : (CellId) -> T raise Failure
  backdate_eq : (T, T) -> Bool
  mut value : T?
}

///|
fn Runtime::enter_static_recompute(self : Runtime) -> Unit {
  let previous_runtime_id = if self.core.tracking.stack.is_empty() &&
    self.static_recompute_depth == 0 {
    -1
  } else {
    @kernel.get_current_computing_runtime_id()
  }
  self.static_recompute_depth = self.static_recompute_depth + 1
  self.static_recompute_tracking_floors.push(self.core.tracking.stack.length())
  self.static_recompute_previous_runtime_ids.push(previous_runtime_id)
  @kernel.set_current_computing_runtime_id(self.core.runtime_id)
}

///|
fn Runtime::leave_static_recompute(self : Runtime) -> Unit {
  guard self.static_recompute_depth > 0 &&
    !self.static_recompute_tracking_floors.is_empty() &&
    !self.static_recompute_previous_runtime_ids.is_empty() else {
    abort("static recompute state underflow")
  }
  ignore(self.static_recompute_tracking_floors.pop())
  let previous_runtime_id = self.static_recompute_previous_runtime_ids.pop().unwrap()
  @kernel.set_current_computing_runtime_id(previous_runtime_id)
  self.static_recompute_depth = self.static_recompute_depth - 1
}

///|
fn Runtime::normalize_static_derived_deps(
  self : Runtime,
  deps : Array[CellId],
) -> Array[CellId] {
  let seen : @hashset.HashSet[CellId] = @hashset.HashSet([])
  let normalized : Array[CellId] = []
  for dep in deps {
    self.validate_cell(dep, "static derived dependency")
    if !seen.contains(dep) {
      seen.add(dep)
      normalized.push(dep)
    }
  }
  normalized
}

///|
fn[T] install_static_derived_probe(
  rt : Runtime,
  deps : Array[CellId],
  compute : (CellId) -> T raise Failure,
  backdate_eq : (T, T) -> Bool,
  label? : String,
) -> StaticDerivedProbe[T] {
  let fixed_deps = rt.normalize_static_derived_deps(deps)
  let memo_idx = rt.pull.free_memos.pop().unwrap_or(rt.pull.memos.length())
  let cell_id = rt.alloc_cell_id(PullMemo(memo_idx))
  let derived : StaticDerivedProbe[T] = {
    rt,
    cell_id,
    compute,
    backdate_eq,
    value: None,
  }
  let data : MemoData = {
    meta: {
      cell_id,
      label,
      changed_at: Revision::initial(),
      durability: compute_durability(rt, fixed_deps),
      subscribers: @hashset.HashSet([]),
      push_reachable_count: 0,
    },
    compute: () => derived.recompute_inner(),
    verified_at: Revision::initial(),
    dependencies: fixed_deps,
    in_progress: false,
    on_change: None,
    is_hybrid: false,
    accumulator_reads: @hashmap.HashMap([]),
    has_been_computed: false,
  }
  if memo_idx < rt.pull.memos.length() {
    rt.pull.memos[memo_idx] = data
  } else {
    rt.pull.memos.push(data)
  }
  rt.core.cell_ops.push(rt.pull.memos[memo_idx])
  rt.cell_lifecycle.push(rt.pull.memos[memo_idx])
  for dep in fixed_deps {
    rt.add_subscriber(dep, cell_id)
  }
  derived
}

///|
fn[T] static_derived_probe(
  rt : Runtime,
  deps : Array[CellId],
  compute : () -> T raise Failure,
  backdate_eq : (T, T) -> Bool,
  label? : String,
) -> StaticDerivedProbe[T] {
  install_static_derived_probe(
    rt,
    deps,
    _dependent => compute(),
    backdate_eq,
    label?,
  )
}

///|
fn[A, T : Eq] static_derived_map1_probe(
  source : Input[A],
  f : (A) -> T raise Failure,
  label? : String,
) -> StaticDerivedProbe[T] {
  static_derived_probe(
    source.inner.rt,
    [source.inner.id()],
    () => f(source.peek()),
    (a, b) => a == b,
    label?,
  )
}

///|
fn[A, B, T : Eq] static_derived_map2_probe(
  left : Input[A],
  right : Input[B],
  f : (A, B) -> T raise Failure,
  label? : String,
) -> StaticDerivedProbe[T] {
  static_derived_probe(
    left.inner.rt,
    [left.inner.id(), right.inner.id()],
    () => f(left.peek(), right.peek()),
    (a, b) => a == b,
    label?,
  )
}

///|
fn[A, B, C, T : Eq] static_derived_map3_probe(
  first : Input[A],
  second : Input[B],
  third : Input[C],
  f : (A, B, C) -> T raise Failure,
  label? : String,
) -> StaticDerivedProbe[T] {
  static_derived_probe(
    first.inner.rt,
    [first.inner.id(), second.inner.id(), third.inner.id()],
    () => f(first.peek(), second.peek(), third.peek()),
    (a, b) => a == b,
    label?,
  )
}

///|
fn[A, T : Eq] static_derived_map_static1_probe(
  source : StaticDerivedProbe[A],
  f : (A) -> T raise Failure,
  label? : String,
) -> StaticDerivedProbe[T] {
  install_static_derived_probe(
    source.rt,
    [source.id()],
    dependent => f(source.read_declared_fixed_dep_or_abort(dependent)),
    (a, b) => a == b,
    label?,
  )
}

///|
fn[T] StaticDerivedProbe::id(self : StaticDerivedProbe[T]) -> CellId {
  self.cell_id
}

///|
fn[T] StaticDerivedProbe::dependencies(
  self : StaticDerivedProbe[T],
) -> Array[CellId] {
  self.rt.get_memo_data(self.cell_id).dependencies.copy()
}

///|
fn[T] StaticDerivedProbe::changed_at(self : StaticDerivedProbe[T]) -> Revision {
  self.rt.get_memo_data(self.cell_id).meta.changed_at
}

///|
fn[T] StaticDerivedProbe::dispose(self : StaticDerivedProbe[T]) -> Unit {
  self.rt.dispose_cell(self.cell_id)
  self.value = None
}

///|
fn[T] StaticDerivedProbe::read(
  self : StaticDerivedProbe[T],
) -> Result[T, CycleError] {
  self.read_impl(record_dependency=true)
}

///|
fn[T] StaticDerivedProbe::read_or_abort(self : StaticDerivedProbe[T]) -> T {
  match self.read() {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
fn[T] StaticDerivedProbe::get_or_abort(self : StaticDerivedProbe[T]) -> T {
  guard self.rt.core.tracking.stack.length() > 0 else {
    abort("StaticDerivedProbe::get_or_abort called outside tracked context")
  }
  match self.read_impl(record_dependency=true) {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
fn[T] StaticDerivedProbe::read_declared_fixed_dep_or_abort(
  self : StaticDerivedProbe[T],
  dependent : CellId,
) -> T {
  self.rt.validate_cell(dependent, "static derived dependent")
  let dependent_data = self.rt.get_memo_data(dependent)
  guard dependent_data.in_progress else {
    abort("StaticDerivedProbe fixed-source read outside dependent recompute")
  }
  let deps = dependent_data.dependencies
  guard deps.contains(self.cell_id) else {
    abort("StaticDerivedProbe fixed-source read without a declared dependency")
  }
  match self.read_impl(record_dependency=false) {
    Ok(value) => value
    Err(e) => abort(e.format_path())
  }
}

///|
fn[T] StaticDerivedProbe::read_impl(
  self : StaticDerivedProbe[T],
  record_dependency~ : Bool,
) -> Result[T, CycleError] {
  self.rt.check_cross_runtime(self.rt.core.runtime_id, "StaticDerivedProbe")
  let result = self.read_inner(record_dependency~) catch {
    e => {
      self.rt.drain_pending_events_direct()
      abort("StaticDerivedProbe compute raised: " + e.to_string())
    }
  }
  if self.rt.has_pending_events() {
    self.rt.drain_pending_events_if_idle()
  }
  result
}

///|
fn[T] StaticDerivedProbe::read_inner(
  self : StaticDerivedProbe[T],
  record_dependency~ : Bool,
) -> Result[T, CycleError] raise Failure {
  guard !self.rt.is_cell_disposed(self.cell_id) else {
    abort("StaticDerivedProbe::read called on a disposed derived")
  }
  match self.value {
    None =>
      match self.force_recompute() {
        Ok(value) => {
          if record_dependency {
            self.rt.record_dependency(self.cell_id)
          }
          Ok(value)
        }
        Err(e) => Err(e)
      }
    Some(cached) => {
      let cell = self.rt.get_memo_data(self.cell_id)
      if cell.verified_at >= self.rt.core.revision.current_revision {
        if record_dependency {
          self.rt.record_dependency(self.cell_id)
        }
        return Ok(cached)
      }
      match self.rt.pull_verify(self.cell_id) {
        Ok(_) => {
          if record_dependency {
            self.rt.record_dependency(self.cell_id)
          }
          match self.value {
            Some(value) => Ok(value)
            None =>
              abort(
                "unreachable: value is always Some after successful static verification",
              )
          }
        }
        Err(e) => Err(e)
      }
    }
  }
}

///|
fn[T] StaticDerivedProbe::force_recompute(
  self : StaticDerivedProbe[T],
) -> Result[T, CycleError] raise Failure {
  let cell = self.rt.get_memo_data(self.cell_id)
  if cell.in_progress {
    return Err(
      @kernel.construct_cycle_error(
        self.rt.core,
        @kernel.collect_in_progress_path(self.rt.pull),
        self.cell_id,
      ),
    )
  }
  cell.in_progress = true
  self.rt.dispatch_before_recompute_hooks(self.cell_id)
  self.rt.enter_static_recompute()
  let new_value = (self.compute)(self.cell_id) catch {
    e => {
      self.rt.leave_static_recompute()
      self.rt.dispatch_after_abort_hooks(self.cell_id, e)
      cell.in_progress = false
      raise e
    }
  }
  self.rt.leave_static_recompute()
  let value_changed = match self.value {
    None => true
    Some(old) => !(self.backdate_eq)(old, new_value)
  }
  if value_changed {
    cell.meta.changed_at = self.rt.core.revision.current_revision
  }
  cell.verified_at = self.rt.core.revision.current_revision
  cell.has_been_computed = true
  cell.in_progress = false
  self.rt.dispatch_after_success_hooks(self.cell_id)
  self.value = Some(new_value)
  Ok(new_value)
}

///|
fn[T] StaticDerivedProbe::recompute_inner(
  self : StaticDerivedProbe[T],
) -> Result[Bool, CycleError] raise Failure {
  let cell = self.rt.get_memo_data(self.cell_id)
  let old_changed_at = cell.meta.changed_at
  match self.force_recompute() {
    Ok(_) => {
      let changed = cell.meta.changed_at != old_changed_at
      if changed {
        match cell.on_change {
          Some(f) => @kernel.run_callback(self.rt.core, f)
          None => ()
        }
      }
      Ok(changed)
    }
    Err(e) => Err(e)
  }
}
