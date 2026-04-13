///|
test "TrackedCell dependency tracking" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 10)
  let doubled = @incr.Memo::new(rt, () => cell.get() * 2)
  inspect(rt.read(doubled), content="20")
  cell.set(15)
  inspect(rt.read(doubled), content="30")
}

///|
test "TrackedCell same-value optimization" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 5)
  let mut compute_count = 0
  let memo = @incr.Memo::new(rt, () => {
    compute_count = compute_count + 1
    cell.get()
  })
  let _ = rt.read(memo) // compute_count = 1
  cell.set(5) // same value — no revision bump
  let _ = rt.read(memo) // should NOT recompute
  inspect(compute_count, content="1")
}

///|
test "TrackedCell on_change callback" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 0)
  let mut observed = 0
  cell.on_change(v => observed = v)
  cell.set(42)
  inspect(observed, content="42")
}

///|
test "TrackedCell get_result returns Ok" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 99)
  match cell.get_result() {
    Ok(v) => inspect(v, content="99")
    Err(_) => abort("unexpected Err")
  }
}

///|
test "TrackedCell batch integration" {
  let rt = @incr.Runtime::new()
  let a = @incr.TrackedCell::new(rt, 1)
  let b = @incr.TrackedCell::new(rt, 2)
  let sum = @incr.Memo::new(rt, () => a.get() + b.get())
  inspect(rt.read(sum), content="3")
  rt.batch(() => {
    a.set(10)
    b.set(20)
  })
  inspect(rt.read(sum), content="30")
}

///|
test "TrackedCell batch revert detection" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 0)
  let mut compute_count = 0
  let memo = @incr.Memo::new(rt, () => {
    compute_count = compute_count + 1
    cell.get()
  })
  let _ = rt.read(memo) // compute_count = 1
  rt.batch(() => {
    cell.set(99)
    cell.set(0) // revert to original
  })
  let _ = rt.read(memo) // should NOT recompute (net change = 0)
  inspect(compute_count, content="1")
}

///|
test "TrackedCell as_signal interop" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 7)
  let sig = cell.as_signal()
  // A Memo using the raw Signal still tracks the same dependency
  let memo = @incr.Memo::new(rt, () => sig.get() + 1)
  inspect(rt.read(memo), content="8")
  cell.set(10)
  inspect(rt.read(memo), content="11")
}

// --- Phase 2: Trackable trait + gc_tracked ---

///|
/// Test fixture: a tracked struct with three fields
struct TestTracked {
  name : @incr.TrackedCell[String]
  value : @incr.TrackedCell[Int]
  flag : @incr.TrackedCell[Bool]
}

///|
impl @incr.Trackable for TestTracked with cell_ids(self) {
  [self.name.id(), self.value.id(), self.flag.id()]
}

///|
fn TestTracked::new(rt : @incr.Runtime) -> TestTracked {
  {
    name: @incr.TrackedCell::new(rt, "default", label="name"),
    value: @incr.TrackedCell::new(rt, 0, label="value"),
    flag: @incr.TrackedCell::new(rt, false, label="flag"),
  }
}

///|
test "Trackable cell_ids returns all field IDs" {
  let rt = @incr.Runtime::new()
  let t = TestTracked::new(rt)
  let ids = t.cell_ids()
  inspect(ids.length(), content="3")
  // IDs are distinct
  inspect(ids[0] == ids[1], content="false")
  inspect(ids[1] == ids[2], content="false")
}

///|
test "Trackable cell_ids ordering is stable" {
  let rt = @incr.Runtime::new()
  let t = TestTracked::new(rt)
  let ids1 = t.cell_ids()
  let ids2 = t.cell_ids()
  inspect(ids1[0] == ids2[0], content="true")
  inspect(ids1[1] == ids2[1], content="true")
  inspect(ids1[2] == ids2[2], content="true")
}

///|
test "field-level dependency isolation" {
  let rt = @incr.Runtime::new()
  let t = TestTracked::new(rt)
  let mut name_reads = 0
  let mut value_reads = 0
  let name_len = @incr.Memo::new(rt, () => {
    name_reads = name_reads + 1
    t.name.get().length()
  })
  let value_doubled = @incr.Memo::new(rt, () => {
    value_reads = value_reads + 1
    t.value.get() * 2
  })

  // Initial computation
  let _ = rt.read(name_len) // name_reads = 1
  let _ = rt.read(value_doubled) // value_reads = 1

  // Change only `value` — name_len should NOT recompute
  t.value.set(10)
  let _ = rt.read(name_len) // name_reads still 1
  let _ = rt.read(value_doubled) // value_reads = 2
  inspect(name_reads, content="1")
  inspect(value_reads, content="2")

  // Change only `name` — value_doubled should NOT recompute
  t.name.set("hello")
  let _ = rt.read(name_len) // name_reads = 2
  let _ = rt.read(value_doubled) // value_reads still 2
  inspect(name_reads, content="2")
  inspect(value_reads, content="2")
}

///|
test "gc_tracked compiles and runs (no-op)" {
  let rt = @incr.Runtime::new()
  let t = TestTracked::new(rt)
  @incr.gc_tracked(rt, t)
  // No crash, no effect — just verifying call compiles
}

///|
test "create_tracked_cell with Database" {
  // TestDb is defined at the top level of traits_test.mbt (same package)
  let db = TestDb::new()
  let cell = @incr.create_tracked_cell(db, 42, label="db_cell")
  inspect(cell.get(), content="42")
}

///|
test "TrackedCell introspection via Runtime::cell_info" {
  let rt = @incr.Runtime::new()
  let t = TestTracked::new(rt)
  let ids = t.cell_ids()
  for i = 0; i < ids.length(); i = i + 1 {
    let info = rt.cell_info(ids[i])
    inspect(info is None, content="false")
    // All fields should have labels
    inspect(info.unwrap().label is None, content="false")
  }
}

///|
test "TrackedCell Readable trait" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 0)
  // check_up_to_date is defined at the top level of traits_test.mbt (same package)
  inspect(check_up_to_date(cell), content="true")
}

///|
test "TrackedCell set_unconditional always recomputes" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 5)
  let mut compute_count = 0
  let memo = @incr.Memo::new(rt, () => {
    compute_count = compute_count + 1
    cell.get()
  })
  let _ = rt.read(memo) // compute_count = 1
  cell.set_unconditional(5) // same value but unconditional — bumps revision
  let _ = rt.read(memo) // should recompute
  inspect(compute_count, content="2")
}

///|
test "TrackedCell clear_on_change stops callback" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 0)
  let mut observed = 0
  cell.on_change(v => observed = v)
  cell.set(1)
  inspect(observed, content="1") // callback fired
  cell.clear_on_change()
  cell.set(2)
  inspect(observed, content="1") // callback NOT fired (still 1)
}

// --- Phase 3: add_tracked ---

///|
/// Helper struct for add_tracked tests (2-field variant)
struct TwoFieldTracked {
  a : @incr.TrackedCell[Int]
  b : @incr.TrackedCell[Int]
}

///|
impl @incr.Trackable for TwoFieldTracked with cell_ids(self) {
  [self.a.id(), self.b.id()]
}

///|
test "scope: add_tracked registers all cell ids for disposal" {
  let rt = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt)
  let tracked : TwoFieldTracked = {
    a: @incr.TrackedCell::new(rt, 1, label="a"),
    b: @incr.TrackedCell::new(rt, 2, label="b"),
  }
  @incr.add_tracked(scope, tracked)
  inspect(tracked.a.get(), content="1")
  inspect(tracked.b.get(), content="2")
  scope.dispose()
  inspect(tracked.a.is_disposed(), content="true")
  inspect(tracked.b.is_disposed(), content="true")
}

///|
test "panic scope: add_tracked on disposed scope aborts" {
  let rt = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt)
  scope.dispose()
  let tracked : TwoFieldTracked = {
    a: @incr.TrackedCell::new(rt, 1),
    b: @incr.TrackedCell::new(rt, 2),
  }
  @incr.add_tracked(scope, tracked)
}

///|
test "panic scope: add_tracked with foreign runtime cells aborts at registration" {
  let rt1 = @incr.Runtime::new()
  let rt2 = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt1)
  let tracked : TwoFieldTracked = {
    a: @incr.TrackedCell::new(rt2, 1),
    b: @incr.TrackedCell::new(rt2, 2),
  }
  // Aborts at registration time, not at dispose time
  @incr.add_tracked(scope, tracked)
}
