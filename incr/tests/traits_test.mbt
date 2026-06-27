///|
using @incr {type Signal, type Runtime, type Derived}

// === Test helpers ===

///|
struct TestDb {
  rt : Runtime
}

///|
suberror TraitBatchError {
  Stop
}

///|
fn TestDb::TestDb() -> TestDb {
  { rt: Runtime() }
}

///|
impl @incr.Database for TestDb with fn runtime(self) {
  self.rt
}

///|
impl @incr.RuntimeContext for TestDb with fn runtime(self) {
  self.rt
}

///|
/// Generic helper to test the Freshness trait through trait dispatch.
fn[R : @incr.Freshness] check_is_fresh(node : R) -> Bool {
  node.is_fresh()
}

///|
/// Generic helper to test the Readable trait through trait dispatch.
fn[R : @incr.Readable] check_up_to_date(node : R) -> Bool {
  node.is_up_to_date()
}

// === Database + helper function tests ===

///|
test "trait: create_signal via Database" {
  let db = TestDb()
  let sig = @incr.create_signal(db, 42)
  inspect(sig.get(), content="42")
}

///|
test "trait: create_signal with High durability" {
  let db = TestDb()
  let sig = @incr.create_signal(db, "hello", durability=High)
  inspect(sig.get(), content="hello")
  inspect(sig.durability(), content="High")
}

///|
test "trait: create_derived via Database" {
  let db = TestDb()
  let sig = @incr.create_signal(db, 10)
  let memo = @incr.create_derived(db, () => sig.get() * 2)
  inspect(read_derived_for_test(memo), content="20")
}

///|
test "trait: batch via Database" {
  let db = TestDb()
  let x = @incr.create_signal(db, 1)
  let y = @incr.create_signal(db, 2)
  let sum = @incr.create_derived(db, () => x.get() + y.get())
  inspect(read_derived_for_test(sum), content="3")
  @incr.batch(db, () => {
    x.set(10)
    y.set(20)
  })
  inspect(read_derived_for_test(sum), content="30")
}

///|
test "trait: batch via Database rolls back on raised error" {
  let db = TestDb()
  let x = @incr.create_signal(db, 1)
  let mut compute_count = 0
  let memo = @incr.create_derived(db, () => {
    compute_count = compute_count + 1
    x.get() * 2
  })
  inspect(read_derived_for_test(memo), content="2")
  inspect(compute_count, content="1")
  let mut stopped = false
  try
    @incr.batch(db, () => {
      x.set(10)
      raise Stop
    })
  catch {
    Stop => stopped = true
  } noraise {
    _ => ()
  }
  inspect(stopped, content="true")
  inspect(x.get(), content="1")
  // Rollback keeps previous committed state, so memo remains cached.
  inspect(read_derived_for_test(memo), content="2")
  inspect(compute_count, content="1")
}

///|
test "trait: batch_result via Database" {
  let db = TestDb()
  let x = @incr.create_signal(db, 1)
  let ok = @incr.batch_result(db, () => x.set(2))
  inspect(ok is Ok(_), content="true")
  inspect(x.get(), content="2")

  let err = @incr.batch_result(db, () => {
    x.set(3)
    raise Stop
  })
  inspect(err is Err(Stop), content="true")
  inspect(x.get(), content="2")
}

// === Readable tests ===

///|
test "trait: signal is always up-to-date" {
  let rt = Runtime::Runtime()
  let sig = Signal::Signal(rt, 5)
  inspect(sig.is_up_to_date(), content="true")
  sig.set(10)
  inspect(sig.is_up_to_date(), content="true")
}

///|
test "trait: memo is up-to-date after get" {
  let rt = Runtime::Runtime()
  let input = Signal::Signal(rt, 1)
  let memo = Derived::Derived(rt, () => input.get() + 1)
  // After get, memo should be up-to-date
  let _ = read_derived_for_test(memo)
  inspect(memo.is_fresh(), content="true")
  // After input change, memo should be stale
  input.set(2)
  inspect(memo.is_fresh(), content="false")
  // After re-get, memo should be up-to-date again
  let _ = read_derived_for_test(memo)
  inspect(memo.is_fresh(), content="true")
}

///|
test "trait: memo not yet computed is not up-to-date" {
  let rt = Runtime::Runtime()
  let input = Signal::Signal(rt, 1)
  let memo = Derived::Derived(rt, () => input.get() + 1)
  // Before any get, memo has no cached value, so it is not up-to-date
  inspect(memo.is_fresh(), content="false")
  // After computing, memo is up-to-date
  let _ = read_derived_for_test(memo)
  inspect(memo.is_fresh(), content="true")
  // After input change, memo becomes stale
  input.set(2)
  inspect(memo.is_fresh(), content="false")
}

///|
test "trait: freshness trait dispatch for derived" {
  let rt = Runtime::Runtime()
  let input = Signal::Signal(rt, 1)
  let memo = Derived::Derived(rt, () => input.get() + 1)
  let _ = read_derived_for_test(memo)
  inspect(check_is_fresh(memo), content="true")
  input.set(2)
  inspect(check_is_fresh(memo), content="false")
}

///|
test "trait: create_signal with label" {
  let db = TestDb()
  let sig = @incr.create_signal(db, 42, label="count")
  match db.rt.cell_info(sig.id()) {
    Some(info) =>
      debug_inspect(
        info.label,
        content=(
          #|Some("count")
        ),
      )
    None => abort("expected cell info")
  }
}

///|
test "trait: create_derived with label" {
  let db = TestDb()
  let x = @incr.create_signal(db, 1)
  let m = @incr.create_derived(db, () => x.get() * 2, label="doubled")
  let _ = read_derived_for_test(m)
  match db.rt.cell_info(m.id()) {
    Some(info) =>
      debug_inspect(
        info.label,
        content=(
          #|Some("doubled")
        ),
      )
    None => abort("expected cell info")
  }
}

///|
test "trait: create_derived_map via Database" {
  let db = TestDb()
  let source = @incr.create_signal(db, 10)
  let by_key = @incr.create_derived_map(
    db,
    (key : Int) => source.get() + key,
    label="by_key",
  )
  inspect(by_key.read_or_abort(1), content="11")
  inspect(by_key.read_or_abort(1), content="11")
  inspect(by_key.read_or_abort(2), content="12")
}
