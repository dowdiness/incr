///|
test "TrackedCell dependency tracking" {
  let rt = @incr.Runtime::Runtime()
  let cell = @incr.TrackedCell::TrackedCell(rt, 10)
  let doubled = @incr.Derived::Derived(rt, () => cell.get() * 2)
  inspect(read_derived_for_test(doubled), content="20")
  cell.set(15)
  inspect(read_derived_for_test(doubled), content="30")
}

///|
test "TrackedCell same-value optimization" {
  let rt = @incr.Runtime::Runtime()
  let cell = @incr.TrackedCell::TrackedCell(rt, 5)
  let mut compute_count = 0
  let memo = @incr.Derived::Derived(rt, () => {
    compute_count = compute_count + 1
    cell.get()
  })
  let _ = read_derived_for_test(memo) // compute_count = 1
  cell.set(5) // same value — no revision bump
  let _ = read_derived_for_test(memo) // should NOT recompute
  inspect(compute_count, content="1")
}

///|
test "TrackedCell on_change callback" {
  let rt = @incr.Runtime::Runtime()
  let cell = @incr.TrackedCell::TrackedCell(rt, 0)
  let mut observed = 0
  cell.on_change(v => observed = v)
  cell.set(42)
  inspect(observed, content="42")
}

///|
test "TrackedCell get_result returns Ok" {
  let rt = @incr.Runtime::Runtime()
  let cell = @incr.TrackedCell::TrackedCell(rt, 99)
  match cell.get_result() {
    Ok(v) => inspect(v, content="99")
    Err(_) => abort("unexpected Err")
  }
}

///|
test "TrackedCell batch integration" {
  let rt = @incr.Runtime::Runtime()
  let a = @incr.TrackedCell::TrackedCell(rt, 1)
  let b = @incr.TrackedCell::TrackedCell(rt, 2)
  let sum = @incr.Derived::Derived(rt, () => a.get() + b.get())
  inspect(read_derived_for_test(sum), content="3")
  rt.batch(() => {
    a.set(10)
    b.set(20)
  })
  inspect(read_derived_for_test(sum), content="30")
}

///|
test "TrackedCell batch revert detection" {
  let rt = @incr.Runtime::Runtime()
  let cell = @incr.TrackedCell::TrackedCell(rt, 0)
  let mut compute_count = 0
  let memo = @incr.Derived::Derived(rt, () => {
    compute_count = compute_count + 1
    cell.get()
  })
  let _ = read_derived_for_test(memo) // compute_count = 1
  rt.batch(() => {
    cell.set(99)
    cell.set(0) // revert to original
  })
  let _ = read_derived_for_test(memo) // should NOT recompute (net change = 0)
  inspect(compute_count, content="1")
}

///|
test "TrackedCell as_input interop" {
  let rt = @incr.Runtime::Runtime()
  let cell = @incr.TrackedCell::TrackedCell(rt, 7)
  let sig = cell.as_input()
  // A Memo using the raw Input still tracks the same dependency
  let memo = @incr.Derived::Derived(rt, () => sig.get() + 1)
  inspect(read_derived_for_test(memo), content="8")
  cell.set(10)
  inspect(read_derived_for_test(memo), content="11")
}

// --- Phase 2: Trackable trait + scoped lifecycle registration ---

///|
/// Test fixture: a tracked struct with three fields
struct TestTracked {
  name : @incr.TrackedCell[String]
  value : @incr.TrackedCell[Int]
  flag : @incr.TrackedCell[Bool]
}

///|
impl @incr.Trackable for TestTracked with fn cell_ids(self) {
  [self.name.id(), self.value.id(), self.flag.id()]
}

///|
fn TestTracked::new(rt : @incr.Runtime) -> TestTracked {
  {
    name: @incr.TrackedCell::TrackedCell(rt, "default", label="name"),
    value: @incr.TrackedCell::TrackedCell(rt, 0, label="value"),
    flag: @incr.TrackedCell::TrackedCell(rt, false, label="flag"),
  }
}

///|
test "Trackable cell_ids returns all field IDs" {
  let rt = @incr.Runtime::Runtime()
  let t = TestTracked::new(rt)
  let ids = t.cell_ids()
  inspect(ids.length(), content="3")
  // IDs are distinct
  inspect(ids[0] == ids[1], content="false")
  inspect(ids[1] == ids[2], content="false")
}

///|
test "Trackable cell_ids ordering is stable" {
  let rt = @incr.Runtime::Runtime()
  let t = TestTracked::new(rt)
  let ids1 = t.cell_ids()
  let ids2 = t.cell_ids()
  inspect(ids1[0] == ids2[0], content="true")
  inspect(ids1[1] == ids2[1], content="true")
  inspect(ids1[2] == ids2[2], content="true")
}

///|
test "field-level dependency isolation" {
  let rt = @incr.Runtime::Runtime()
  let t = TestTracked::new(rt)
  let mut name_reads = 0
  let mut value_reads = 0
  let name_len = @incr.Derived::Derived(rt, () => {
    name_reads = name_reads + 1
    t.name.get().length()
  })
  let value_doubled = @incr.Derived::Derived(rt, () => {
    value_reads = value_reads + 1
    t.value.get() * 2
  })

  // Initial computation
  let _ = read_derived_for_test(name_len) // name_reads = 1
  let _ = read_derived_for_test(value_doubled) // value_reads = 1

  // Change only `value` — name_len should NOT recompute
  t.value.set(10)
  let _ = read_derived_for_test(name_len) // name_reads still 1
  let _ = read_derived_for_test(value_doubled) // value_reads = 2
  inspect(name_reads, content="1")
  inspect(value_reads, content="2")

  // Change only `name` — value_doubled should NOT recompute
  t.name.set("hello")
  let _ = read_derived_for_test(name_len) // name_reads = 2
  let _ = read_derived_for_test(value_doubled) // value_reads still 2
  inspect(name_reads, content="2")
  inspect(value_reads, content="2")
}

///|
test "Trackable fields register with scope" {
  let rt = @incr.Runtime::Runtime()
  let scope = @incr.Scope::new(rt)
  let t = TestTracked::new(rt)
  @incr.add_tracked(scope, t)
  inspect(t.name.is_disposed(), content="false")
  inspect(t.value.is_disposed(), content="false")
  inspect(t.flag.is_disposed(), content="false")
  scope.dispose()
  inspect(t.name.is_disposed(), content="true")
  inspect(t.value.is_disposed(), content="true")
  inspect(t.flag.is_disposed(), content="true")
}

///|
test "create_tracked_cell with Database" {
  // TestDb is defined at the top level of traits_test.mbt (same package)
  let db = TestDb()
  let cell = @incr.create_tracked_cell(db, 42, label="db_cell")
  inspect(cell.get(), content="42")
}

///|
test "TrackedCell introspection via Runtime::cell_info" {
  let rt = @incr.Runtime::Runtime()
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
  let rt = @incr.Runtime::Runtime()
  let cell = @incr.TrackedCell::TrackedCell(rt, 0)
  // check_up_to_date is defined at the top level of traits_test.mbt (same package)
  inspect(check_up_to_date(cell), content="true")
}

///|
test "TrackedCell force_set always recomputes" {
  let rt = @incr.Runtime::Runtime()
  let cell = @incr.TrackedCell::TrackedCell(rt, 5)
  let mut compute_count = 0
  let memo = @incr.Derived::Derived(rt, () => {
    compute_count = compute_count + 1
    cell.get()
  })
  let _ = read_derived_for_test(memo) // compute_count = 1
  cell.force_set(5) // same value but unconditional — bumps revision
  let _ = read_derived_for_test(memo) // should recompute
  inspect(compute_count, content="2")
}

///|
test "TrackedCell clear_on_change stops callback" {
  let rt = @incr.Runtime::Runtime()
  let cell = @incr.TrackedCell::TrackedCell(rt, 0)
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
impl @incr.Trackable for TwoFieldTracked with fn cell_ids(self) {
  [self.a.id(), self.b.id()]
}

///|
test "scope: add_tracked registers all cell ids for disposal" {
  let rt = @incr.Runtime::Runtime()
  let scope = @incr.Scope::new(rt)
  let tracked : TwoFieldTracked = {
    a: @incr.TrackedCell::TrackedCell(rt, 1, label="a"),
    b: @incr.TrackedCell::TrackedCell(rt, 2, label="b"),
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
  let rt = @incr.Runtime::Runtime()
  let scope = @incr.Scope::new(rt)
  scope.dispose()
  let tracked : TwoFieldTracked = {
    a: @incr.TrackedCell::TrackedCell(rt, 1),
    b: @incr.TrackedCell::TrackedCell(rt, 2),
  }
  @incr.add_tracked(scope, tracked)
}

///|
test "panic scope: add_tracked with foreign runtime cells aborts at registration" {
  let rt1 = @incr.Runtime::Runtime()
  let rt2 = @incr.Runtime::Runtime()
  let scope = @incr.Scope::new(rt1)
  let tracked : TwoFieldTracked = {
    a: @incr.TrackedCell::TrackedCell(rt2, 1),
    b: @incr.TrackedCell::TrackedCell(rt2, 2),
  }
  // Aborts at registration time, not at dispose time
  @incr.add_tracked(scope, tracked)
}
