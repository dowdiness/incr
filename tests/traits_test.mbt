///|
using @incr {type Signal, type Runtime, type Memo}

// === Test helpers ===

///|
struct TestDb {
  rt : Runtime

  fn new() -> TestDb
}

///|
suberror TraitBatchError {
  Stop
}

///|
fn TestDb::new() -> TestDb {
  { rt: Runtime() }
}

///|
impl @incr.IncrDb for TestDb with runtime(self) {
  self.rt
}

///|
/// Generic helper to test the Readable trait through trait dispatch.
fn[R : @incr.Readable] check_up_to_date(node : R) -> Bool {
  node.is_up_to_date()
}

// === IncrDb + helper function tests ===

///|
test "trait: create_signal via IncrDb" {
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
test "trait: create_memo via IncrDb" {
  let db = TestDb()
  let sig = @incr.create_signal(db, 10)
  let memo = @incr.create_memo(db, () => sig.get() * 2)
  inspect(memo.get(), content="20")
}

///|
test "trait: batch via IncrDb" {
  let db = TestDb()
  let x = @incr.create_signal(db, 1)
  let y = @incr.create_signal(db, 2)
  let sum = @incr.create_memo(db, () => x.get() + y.get())
  inspect(sum.get(), content="3")
  @incr.batch(db, () => {
    x.set(10)
    y.set(20)
  })
  inspect(sum.get(), content="30")
}

///|
test "trait: batch via IncrDb rolls back on raised error" {
  let db = TestDb()
  let x = @incr.create_signal(db, 1)
  let mut compute_count = 0
  let memo = @incr.create_memo(db, () => {
    compute_count = compute_count + 1
    x.get() * 2
  })
  inspect(memo.get(), content="2")
  inspect(compute_count, content="1")
  let res : Result[Unit, Error] = try? @incr.batch(db, () => {
    x.set(10)
    raise Stop
  })
  inspect(res is Err(_), content="true")
  inspect(x.get(), content="1")
  // Rollback keeps previous committed state, so memo remains cached.
  inspect(memo.get(), content="2")
  inspect(compute_count, content="1")
}

///|
test "trait: batch_result via IncrDb" {
  let db = TestDb()
  let x = @incr.create_signal(db, 1)
  let ok = @incr.batch_result(db, () => x.set(2))
  inspect(ok is Ok(_), content="true")
  inspect(x.get(), content="2")

  let err = @incr.batch_result(db, () => {
    x.set(3)
    raise Stop
  })
  inspect(err is Err(_), content="true")
  inspect(x.get(), content="2")
}

// === Readable tests ===

///|
test "trait: signal is always up-to-date" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 5)
  inspect(sig.is_up_to_date(), content="true")
  sig.set(10)
  inspect(sig.is_up_to_date(), content="true")
}

///|
test "trait: memo is up-to-date after get" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 1)
  let memo = Memo::new(rt, () => input.get() + 1)
  // After get, memo should be up-to-date
  let _ = memo.get()
  inspect(memo.is_up_to_date(), content="true")
  // After input change, memo should be stale
  input.set(2)
  inspect(memo.is_up_to_date(), content="false")
  // After re-get, memo should be up-to-date again
  let _ = memo.get()
  inspect(memo.is_up_to_date(), content="true")
}

///|
test "trait: memo not yet computed is not up-to-date" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 1)
  let memo = Memo::new(rt, () => input.get() + 1)
  // Before any get, memo has no cached value, so it is not up-to-date
  inspect(memo.is_up_to_date(), content="false")
  // After computing, memo is up-to-date
  let _ = memo.get()
  inspect(memo.is_up_to_date(), content="true")
  // After input change, memo becomes stale
  input.set(2)
  inspect(memo.is_up_to_date(), content="false")
}

///|
test "trait: readable trait dispatch for signal" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 5)
  inspect(check_up_to_date(sig), content="true")
  sig.set(10)
  inspect(check_up_to_date(sig), content="true")
}

///|
test "trait: readable trait dispatch for memo" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 1)
  let memo = Memo::new(rt, () => input.get() + 1)
  let _ = memo.get()
  inspect(check_up_to_date(memo), content="true")
  input.set(2)
  inspect(check_up_to_date(memo), content="false")
}

// === Pipeline trait tests ===

///|
struct CalcPipeline {
  rt : Runtime
  source : Signal[String]
  errors : Memo[Array[String]]
  output : Memo[Array[String]]

  fn new() -> CalcPipeline
}

///|
fn CalcPipeline::new() -> CalcPipeline {
  let rt = Runtime::new()
  let source = Signal::new(rt, "")
  let errors = Memo::new(rt, () => {
    let src = source.get()
    if src == "" {
      ["empty source"]
    } else {
      []
    }
  })
  let output = Memo::new(rt, () => {
    let src = source.get()
    if src == "" {
      []
    } else {
      [src]
    }
  })
  { rt, source, errors, output }
}

///|
impl @incr.IncrDb for CalcPipeline with runtime(self) {
  self.rt
}

///|
impl @pipeline.Sourceable for CalcPipeline with set_source_text(self, text) {
  self.source.set(text)
}

///|
impl @pipeline.Sourceable for CalcPipeline with source_text(self) {
  self.source.get()
}

///|
impl @pipeline.Parseable for CalcPipeline with parse_errors(_) {
  []
}

///|
impl @pipeline.Checkable for CalcPipeline with check_errors(self) {
  self.errors.get()
}

///|
impl @pipeline.Executable for CalcPipeline with run(self) {
  self.output.get()
}

///|
fn[D : @pipeline.Parseable + @pipeline.Checkable] all_diagnostics(
  db : D,
) -> Array[String] {
  let parse_errs = db.parse_errors()
  let check_errs = db.check_errors()
  let result : Array[String] = []
  for i = 0; i < parse_errs.length(); i = i + 1 {
    result.push(parse_errs[i])
  }
  for i = 0; i < check_errs.length(); i = i + 1 {
    result.push(check_errs[i])
  }
  result
}

///|
fn[D : @pipeline.Parseable + @pipeline.Checkable + @pipeline.Executable] compile_and_run(
  db : D,
) -> Result[Array[String], Array[String]] {
  let diags = all_diagnostics(db)
  if diags.length() > 0 {
    Err(diags)
  } else {
    Ok(db.run())
  }
}

///|
test "trait: pipeline sourceable" {
  let db = CalcPipeline()
  let _ = db.runtime()
  db.set_source_text("hello")
  inspect(db.source_text(), content="hello")
}

///|
test "trait: all_diagnostics with errors" {
  let db = CalcPipeline()
  let diags = all_diagnostics(db)
  inspect(diags.length(), content="1")
  inspect(diags[0], content="empty source")
}

///|
test "trait: all_diagnostics after fix" {
  let db = CalcPipeline()
  db.set_source_text("hello")
  let diags = all_diagnostics(db)
  inspect(diags.length(), content="0")
}

///|
test "trait: compile_and_run with errors" {
  let db = CalcPipeline()
  match compile_and_run(db) {
    Err(errs) => {
      inspect(errs.length(), content="1")
      inspect(errs[0], content="empty source")
    }
    Ok(_) => abort("expected errors")
  }
}

///|
test "trait: compile_and_run success" {
  let db = CalcPipeline()
  db.set_source_text("hello")
  match compile_and_run(db) {
    Ok(output) => {
      inspect(output.length(), content="1")
      inspect(output[0], content="hello")
    }
    Err(_) => abort("expected success")
  }
}

///|
test "trait: pipeline incrementality" {
  let db = CalcPipeline()
  db.set_source_text("first")
  match compile_and_run(db) {
    Ok(output) => inspect(output[0], content="first")
    Err(_) => abort("expected success")
  }
  // Update source and verify incremental recomputation
  db.set_source_text("second")
  match compile_and_run(db) {
    Ok(output) => inspect(output[0], content="second")
    Err(_) => abort("expected success")
  }
}

///|
test "trait: create_signal with label" {
  let db = TestDb()
  let sig = @incr.create_signal(db, 42, label="count")
  match db.rt.cell_info(sig.id()) {
    Some(info) => inspect(info.label, content="Some(\"count\")")
    None => abort("expected cell info")
  }
}

///|
test "trait: create_memo with label" {
  let db = TestDb()
  let x = @incr.create_signal(db, 1)
  let m = @incr.create_memo(db, () => x.get() * 2, label="doubled")
  let _ = m.get()
  match db.rt.cell_info(m.id()) {
    Some(info) => inspect(info.label, content="Some(\"doubled\")")
    None => abort("expected cell info")
  }
}

///|
test "trait: create_memo_map via IncrDb" {
  let db = TestDb()
  let source = @incr.create_signal(db, 10)
  let by_key = @incr.create_memo_map(
    db,
    (key : Int) => source.get() + key,
    label="by_key",
  )
  inspect(by_key.get(1), content="11")
  inspect(by_key.get(1), content="11")
  inspect(by_key.get(2), content="12")
}
