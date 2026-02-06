// === Test helpers ===

///|
struct TestDb {
  rt : Runtime
}

///|
fn TestDb::new() -> TestDb {
  { rt: Runtime::new() }
}

///|
impl IncrDb for TestDb with runtime(self) {
  self.rt
}

///|
/// Generic helper to test the Readable trait through trait dispatch.
fn[R : Readable] check_up_to_date(node : R) -> Bool {
  node.is_up_to_date()
}

// === IncrDb + helper function tests ===

///|
test "trait: create_signal via IncrDb" {
  let db = TestDb::new()
  let sig = create_signal(db, 42)
  inspect(sig.get(), content="42")
}

///|
test "trait: create_signal_durable via IncrDb" {
  let db = TestDb::new()
  let sig = create_signal_durable(db, "hello", High)
  inspect(sig.get(), content="hello")
}

///|
test "trait: create_memo via IncrDb" {
  let db = TestDb::new()
  let sig = create_signal(db, 10)
  let memo = create_memo(db, fn() { sig.get() * 2 })
  inspect(memo.get(), content="20")
}

///|
test "trait: batch via IncrDb" {
  let db = TestDb::new()
  let x = create_signal(db, 1)
  let y = create_signal(db, 2)
  let sum = create_memo(db, fn() { x.get() + y.get() })
  inspect(sum.get(), content="3")
  batch(db, fn() {
    x.set(10)
    y.set(20)
  })
  inspect(sum.get(), content="30")
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
  let memo = Memo::new(rt, fn() { input.get() + 1 })
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
  let memo = Memo::new(rt, fn() { input.get() + 1 })
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
  let memo = Memo::new(rt, fn() { input.get() + 1 })
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
}

///|
fn CalcPipeline::new() -> CalcPipeline {
  let rt = Runtime::new()
  let source = Signal::new(rt, "")
  let errors = Memo::new(rt, fn() {
    let src = source.get()
    if src == "" {
      ["empty source"]
    } else {
      []
    }
  })
  let output = Memo::new(rt, fn() {
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
impl IncrDb for CalcPipeline with runtime(self) {
  self.rt
}

///|
impl Sourceable for CalcPipeline with set_source_text(self, text) {
  self.source.set(text)
}

///|
impl Sourceable for CalcPipeline with source_text(self) {
  self.source.get()
}

///|
impl Parseable for CalcPipeline with parse_errors(_) {
  []
}

///|
impl Checkable for CalcPipeline with check_errors(self) {
  self.errors.get()
}

///|
impl Executable for CalcPipeline with run(self) {
  self.output.get()
}

///|
test "trait: pipeline sourceable" {
  let db = CalcPipeline::new()
  db.set_source_text("hello")
  inspect(db.source_text(), content="hello")
}

///|
test "trait: all_diagnostics with errors" {
  let db = CalcPipeline::new()
  let diags = all_diagnostics(db)
  inspect(diags.length(), content="1")
  inspect(diags[0], content="empty source")
}

///|
test "trait: all_diagnostics after fix" {
  let db = CalcPipeline::new()
  db.set_source_text("hello")
  let diags = all_diagnostics(db)
  inspect(diags.length(), content="0")
}

///|
test "trait: compile_and_run with errors" {
  let db = CalcPipeline::new()
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
  let db = CalcPipeline::new()
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
  let db = CalcPipeline::new()
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
