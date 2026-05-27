///|
/// Integrated static/applicative `Derived` prototype for benchmarking only.
///
/// This creates a real pull-memo SoA entry with fixed dependencies and uses
/// the existing `pull_verify` scheduler, but its recompute closure bypasses
/// dynamic tracking and dependency-list diffing. It is intentionally Int-only
/// and package-private to keep the probe below the public API design line.
struct StaticMap1Probe {
  rt : Runtime
  cell_id : CellId
  value : Ref[Int]
  source : Signal[Int]
}

///|
struct StaticMap2Probe {
  rt : Runtime
  cell_id : CellId
  value : Ref[Int]
  left : Signal[Int]
  right : Signal[Int]
}

///|
struct StaticMap3Probe {
  rt : Runtime
  cell_id : CellId
  value : Ref[Int]
  first : Signal[Int]
  second : Signal[Int]
  third : Signal[Int]
}

///|
fn static_probe_install_memo(
  rt : Runtime,
  deps : Array[CellId],
  initial : Int,
  compute : (CellId) -> Result[Bool, CycleError] raise Failure,
) -> (CellId, Int) {
  let memo_idx = rt.pull.free_memos.pop().unwrap_or(rt.pull.memos.length())
  let cell_id = rt.alloc_cell_id(PullMemo(memo_idx))
  let data : MemoData = {
    meta: {
      cell_id,
      label: Some("static-probe"),
      changed_at: rt.core.revision.current_revision,
      durability: Low,
      subscribers: @hashset.HashSet([]),
      push_reachable_count: 0,
    },
    compute: () => compute(cell_id),
    verified_at: rt.core.revision.current_revision,
    dependencies: deps,
    in_progress: false,
    on_change: None,
    is_hybrid: false,
    accumulator_reads: @hashmap.HashMap([]),
    has_been_computed: true,
  }
  ignore(initial)
  if memo_idx < rt.pull.memos.length() {
    rt.pull.memos[memo_idx] = data
  } else {
    rt.pull.memos.push(data)
  }
  rt.core.cell_ops.push(rt.pull.memos[memo_idx])
  rt.cell_lifecycle.push(rt.pull.memos[memo_idx])
  for dep in deps {
    rt.add_subscriber(dep, cell_id)
  }
  rt.pull.memos[memo_idx].meta.durability = compute_durability(rt, deps)
  (cell_id, memo_idx)
}

///|
fn StaticMap1Probe::StaticMap1Probe(
  rt : Runtime,
  source : Signal[Int],
) -> StaticMap1Probe {
  let value : Ref[Int] = Ref(source.get() + 1)
  let (cell_id, _) = static_probe_install_memo(rt, [source.id()], value.val, cell_id => {
    let next = source.get() + 1
    let changed = value.val != next
    value.val = next
    if changed {
      rt.get_memo_data(cell_id).meta.changed_at = rt.core.revision.current_revision
    }
    Ok(changed)
  })
  { rt, cell_id, value, source }
}

///|
fn StaticMap1Probe::read(self : StaticMap1Probe) -> Int {
  let cell = self.rt.get_memo_data(self.cell_id)
  if cell.verified_at < self.rt.core.revision.current_revision {
    let result = self.rt.pull_verify(self.cell_id) catch {
      e => abort("static prototype compute raised: " + e.to_string())
    }
    match result {
      Ok(_) => ()
      Err(e) => abort(e.format_path())
    }
  }
  self.value.val
}

///|
fn StaticMap2Probe::StaticMap2Probe(
  rt : Runtime,
  left : Signal[Int],
  right : Signal[Int],
) -> StaticMap2Probe {
  let value : Ref[Int] = Ref(left.get() + right.get())
  let (cell_id, _) = static_probe_install_memo(
    rt,
    [left.id(), right.id()],
    value.val,
    cell_id => {
      let next = left.get() + right.get()
      let changed = value.val != next
      value.val = next
      if changed {
        rt.get_memo_data(cell_id).meta.changed_at = rt.core.revision.current_revision
      }
      Ok(changed)
    },
  )
  { rt, cell_id, value, left, right }
}

///|
fn StaticMap2Probe::read(self : StaticMap2Probe) -> Int {
  let cell = self.rt.get_memo_data(self.cell_id)
  if cell.verified_at < self.rt.core.revision.current_revision {
    let result = self.rt.pull_verify(self.cell_id) catch {
      e => abort("static prototype compute raised: " + e.to_string())
    }
    match result {
      Ok(_) => ()
      Err(e) => abort(e.format_path())
    }
  }
  self.value.val
}

///|
fn StaticMap3Probe::StaticMap3Probe(
  rt : Runtime,
  first : Signal[Int],
  second : Signal[Int],
  third : Signal[Int],
) -> StaticMap3Probe {
  let value : Ref[Int] = Ref(first.get() + second.get() + third.get())
  let (cell_id, _) = static_probe_install_memo(
    rt,
    [first.id(), second.id(), third.id()],
    value.val,
    cell_id => {
      let next = first.get() + second.get() + third.get()
      let changed = value.val != next
      value.val = next
      if changed {
        rt.get_memo_data(cell_id).meta.changed_at = rt.core.revision.current_revision
      }
      Ok(changed)
    },
  )
  { rt, cell_id, value, first, second, third }
}

///|
fn StaticMap3Probe::read(self : StaticMap3Probe) -> Int {
  let cell = self.rt.get_memo_data(self.cell_id)
  if cell.verified_at < self.rt.core.revision.current_revision {
    let result = self.rt.pull_verify(self.cell_id) catch {
      e => abort("static prototype compute raised: " + e.to_string())
    }
    match result {
      Ok(_) => ()
      Err(e) => abort(e.format_path())
    }
  }
  self.value.val
}

///|
test "integrated-applicative-probe: map1 dynamic Memo stale" (b : @bench.T) {
  let rt = Runtime()
  let input = Signal(rt, 0)
  let memo = Memo(rt, () => input.get() + 1)
  ignore(memo.read_permissive())
  let mut v = 0
  b.bench(fn() {
    v += 1
    input.set(v)
    b.keep(memo.read_permissive())
  })
}

///|
test "integrated-applicative-probe: map1 static prototype stale" (b : @bench.T) {
  let rt = Runtime()
  let input = Signal(rt, 0)
  let probe = StaticMap1Probe(rt, input)
  let mut v = 0
  b.bench(fn() {
    v += 1
    input.set(v)
    b.keep(probe.read())
  })
}

///|
test "integrated-applicative-probe: map2 dynamic Memo stale" (b : @bench.T) {
  let rt = Runtime()
  let left = Signal(rt, 0)
  let right = Signal(rt, 10)
  let memo = Memo(rt, () => left.get() + right.get())
  ignore(memo.read_permissive())
  let mut v = 0
  b.bench(fn() {
    v += 1
    left.set(v)
    b.keep(memo.read_permissive())
  })
}

///|
test "integrated-applicative-probe: map2 static prototype stale" (b : @bench.T) {
  let rt = Runtime()
  let left = Signal(rt, 0)
  let right = Signal(rt, 10)
  let probe = StaticMap2Probe(rt, left, right)
  let mut v = 0
  b.bench(fn() {
    v += 1
    left.set(v)
    b.keep(probe.read())
  })
}

///|
test "integrated-applicative-probe: map3 dynamic Memo stale" (b : @bench.T) {
  let rt = Runtime()
  let first = Signal(rt, 0)
  let second = Signal(rt, 10)
  let third = Signal(rt, 100)
  let memo = Memo(rt, () => first.get() + second.get() + third.get())
  ignore(memo.read_permissive())
  let mut v = 0
  b.bench(fn() {
    v += 1
    first.set(v)
    b.keep(memo.read_permissive())
  })
}

///|
test "integrated-applicative-probe: map3 static prototype stale" (b : @bench.T) {
  let rt = Runtime()
  let first = Signal(rt, 0)
  let second = Signal(rt, 10)
  let third = Signal(rt, 100)
  let probe = StaticMap3Probe(rt, first, second, third)
  let mut v = 0
  b.bench(fn() {
    v += 1
    first.set(v)
    b.keep(probe.read())
  })
}
