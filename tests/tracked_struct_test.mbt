///|
test "TrackedCell dependency tracking" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 10)
  let doubled = @incr.Memo::new(rt, fn() { cell.get() * 2 })
  inspect(doubled.get(), content="20")
  cell.set(15)
  inspect(doubled.get(), content="30")
}

///|
test "TrackedCell same-value optimization" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 5)
  let mut compute_count = 0
  let memo = @incr.Memo::new(rt, fn() {
    compute_count = compute_count + 1
    cell.get()
  })
  let _ = memo.get() // compute_count = 1
  cell.set(5) // same value — no revision bump
  let _ = memo.get() // should NOT recompute
  inspect(compute_count, content="1")
}

///|
test "TrackedCell on_change callback" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 0)
  let mut observed = 0
  cell.on_change(fn(v) { observed = v })
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
  let sum = @incr.Memo::new(rt, fn() { a.get() + b.get() })
  inspect(sum.get(), content="3")
  rt.batch(fn() {
    a.set(10)
    b.set(20)
  })
  inspect(sum.get(), content="30")
}

///|
test "TrackedCell batch revert detection" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 0)
  let mut compute_count = 0
  let memo = @incr.Memo::new(rt, fn() {
    compute_count = compute_count + 1
    cell.get()
  })
  let _ = memo.get() // compute_count = 1
  rt.batch(fn() {
    cell.set(99)
    cell.set(0) // revert to original
  })
  let _ = memo.get() // should NOT recompute (net change = 0)
  inspect(compute_count, content="1")
}

///|
test "TrackedCell as_signal interop" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 7)
  let sig = cell.as_signal()
  // A Memo using the raw Signal still tracks the same dependency
  let memo = @incr.Memo::new(rt, fn() { sig.get() + 1 })
  inspect(memo.get(), content="8")
  cell.set(10)
  inspect(memo.get(), content="11")
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
  let name_len = @incr.Memo::new(rt, fn() {
    name_reads = name_reads + 1
    t.name.get().length()
  })
  let value_doubled = @incr.Memo::new(rt, fn() {
    value_reads = value_reads + 1
    t.value.get() * 2
  })

  // Initial computation
  let _ = name_len.get() // name_reads = 1
  let _ = value_doubled.get() // value_reads = 1

  // Change only `value` — name_len should NOT recompute
  t.value.set(10)
  let _ = name_len.get() // name_reads still 1
  let _ = value_doubled.get() // value_reads = 2
  inspect(name_reads, content="1")
  inspect(value_reads, content="2")

  // Change only `name` — value_doubled should NOT recompute
  t.name.set("hello")
  let _ = name_len.get() // name_reads = 2
  let _ = value_doubled.get() // value_reads still 2
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
test "create_tracked_cell with IncrDb" {
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
  let memo = @incr.Memo::new(rt, fn() {
    compute_count = compute_count + 1
    cell.get()
  })
  let _ = memo.get() // compute_count = 1
  cell.set_unconditional(5) // same value but unconditional — bumps revision
  let _ = memo.get() // should recompute
  inspect(compute_count, content="2")
}

///|
test "TrackedCell clear_on_change stops callback" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 0)
  let mut observed = 0
  cell.on_change(fn(v) { observed = v })
  cell.set(1)
  inspect(observed, content="1") // callback fired
  cell.clear_on_change()
  cell.set(2)
  inspect(observed, content="1") // callback NOT fired (still 1)
}
