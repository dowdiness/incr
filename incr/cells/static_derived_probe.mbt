///|
/// Package-private fixed-dependency `Derived` fast path.
///
/// This is deliberately not a public API. Static derived cells reuse the
/// existing pull backend (`MemoData` / `PullMemo`) and target facade handle, but
/// install their fixed dependency list once and recompute without opening a
/// dynamic tracking frame or diffing dependencies.

///|
priv struct StaticDerivedSource[T] {
  rt : Runtime
  id : CellId
  read_declared : (CellId) -> T raise Failure
}

///|
fn Runtime::enter_static_recompute(self : Runtime) -> Unit {
  let previous_runtime_id = if self.core.tracking.stack.is_empty() &&
    self.static_recompute_depth == 0 {
    None
  } else {
    @kernel.get_current_computing_runtime_id()
  }
  self.static_recompute_depth = self.static_recompute_depth + 1
  self.static_recompute_tracking_floors.push(self.core.tracking.stack.length())
  self.static_recompute_previous_runtime_ids.push(previous_runtime_id)
  @kernel.set_current_computing_runtime_id(Some(self.core.runtime_id))
}

///|
fn Runtime::leave_static_recompute(self : Runtime) -> Unit {
  guard self.static_recompute_depth > 0 &&
    !self.static_recompute_tracking_floors.is_empty() &&
    !self.static_recompute_previous_runtime_ids.is_empty() else {
    abort("static recompute state underflow")
  }
  ignore(self.static_recompute_tracking_floors.pop())
  let previous_runtime_id = self.static_recompute_previous_runtime_ids
    .pop()
    .unwrap()
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
fn[T] Memo::_create_static(
  rt : Runtime,
  deps : Array[CellId],
  compute : (CellId) -> T raise Failure,
  label? : String,
  backdate_eq : (T, T) -> Bool,
) -> Memo[T] {
  let fixed_deps = rt.normalize_static_derived_deps(deps)
  let memo_idx = rt.pull.free_memos.pop().unwrap_or(rt.pull.memos.length())
  let cell_id = rt.alloc_cell_id(PullMemo(memo_idx))
  let memo : Memo[T] = {
    label,
    rt,
    cell_id,
    compute: () => compute(cell_id),
    is_static: true,
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
    compute: () => memo.recompute_inner(),
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
  let ops : &CellOps = rt.pull.memos[memo_idx]
  rt.core.cell_ops.push(ops)
  let lifecycle : &CellLifecycle = rt.pull.memos[memo_idx]
  rt.cell_lifecycle.push(lifecycle)
  for dep in fixed_deps {
    rt.add_subscriber(dep, cell_id)
  }
  memo
}

///|
fn[T] Runtime::install_static_derived(
  self : Runtime,
  deps : Array[CellId],
  compute : (CellId) -> T raise Failure,
  backdate_eq : (T, T) -> Bool,
  label? : String,
) -> Derived[T] {
  { inner: Memo::_create_static(self, deps, compute, label?, backdate_eq) }
}

///|
fn[T] static_derived(
  rt : Runtime,
  deps : Array[CellId],
  compute : () -> T raise Failure,
  backdate_eq : (T, T) -> Bool,
  label? : String,
) -> Derived[T] {
  rt.install_static_derived(deps, _dependent => compute(), backdate_eq, label?)
}

///|
fn[T] static_source_input(source : Input[T]) -> StaticDerivedSource[T] {
  {
    rt: source.inner.rt,
    id: source.inner.id(),
    read_declared: _dependent => source.peek(),
  }
}

///|
fn[T] static_source_input_field(
  source : InputField[T],
) -> StaticDerivedSource[T] {
  {
    rt: source.inner.signal.rt,
    id: source.inner.id(),
    read_declared: _dependent => source.peek(),
  }
}

///|
fn[T] static_source_derived(source : Derived[T]) -> StaticDerivedSource[T] {
  {
    rt: source.inner.rt,
    id: source.id(),
    read_declared: dependent => {
      source.inner.read_declared_fixed_dep_or_abort(dependent)
    },
  }
}

///|
fn[A, T : Eq] static_derived_map_source1(
  source : StaticDerivedSource[A],
  f : (A) -> T raise Failure,
  label? : String,
) -> Derived[T] {
  source.rt.install_static_derived(
    [source.id],
    dependent => f((source.read_declared)(dependent)),
    (a, b) => a == b,
    label?,
  )
}

///|
fn[A, B, T : Eq] static_derived_map_sources2(
  left : StaticDerivedSource[A],
  right : StaticDerivedSource[B],
  f : (A, B) -> T raise Failure,
  label? : String,
) -> Derived[T] {
  left.rt.install_static_derived(
    [left.id, right.id],
    dependent => {
      f((left.read_declared)(dependent), (right.read_declared)(dependent))
    },
    (a, b) => a == b,
    label?,
  )
}

///|
fn[A, B, C, T : Eq] static_derived_map_sources3(
  first : StaticDerivedSource[A],
  second : StaticDerivedSource[B],
  third : StaticDerivedSource[C],
  f : (A, B, C) -> T raise Failure,
  label? : String,
) -> Derived[T] {
  first.rt.install_static_derived(
    [first.id, second.id, third.id],
    dependent => {
      f(
        (first.read_declared)(dependent),
        (second.read_declared)(dependent),
        (third.read_declared)(dependent),
      )
    },
    (a, b) => a == b,
    label?,
  )
}

///|
fn[A, T : Eq] static_derived_map1(
  source : Input[A],
  f : (A) -> T raise Failure,
  label? : String,
) -> Derived[T] {
  static_derived_map_source1(static_source_input(source), f, label?)
}

///|
fn[A, T : Eq] static_derived_map_input_field1(
  source : InputField[A],
  f : (A) -> T raise Failure,
  label? : String,
) -> Derived[T] {
  static_derived_map_source1(static_source_input_field(source), f, label?)
}

///|
fn[A, T : Eq] static_derived_map_derived1(
  source : Derived[A],
  f : (A) -> T raise Failure,
  label? : String,
) -> Derived[T] {
  static_derived_map_source1(static_source_derived(source), f, label?)
}

///|
fn[A, B, T : Eq] static_derived_map2(
  left : Input[A],
  right : Input[B],
  f : (A, B) -> T raise Failure,
  label? : String,
) -> Derived[T] {
  static_derived_map_sources2(
    static_source_input(left),
    static_source_input(right),
    f,
    label?,
  )
}

///|
fn[A, B, C, T : Eq] static_derived_map3(
  first : Input[A],
  second : Input[B],
  third : Input[C],
  f : (A, B, C) -> T raise Failure,
  label? : String,
) -> Derived[T] {
  static_derived_map_sources3(
    static_source_input(first),
    static_source_input(second),
    static_source_input(third),
    f,
    label?,
  )
}
