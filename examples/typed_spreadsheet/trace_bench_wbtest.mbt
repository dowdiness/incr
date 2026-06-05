///|
/// Benchmarks for the current full-sheet `Worksheet::trace` scan and a
/// benchmark-only bounded lower bound for issue #179.

///|
struct TraceBenchFixture {
  sheet : Worksheet
  source_ids : Array[CellId]
  formula_ids : Array[CellId]
}

///|
fn TraceBenchFixture::dispose(self : TraceBenchFixture) -> Unit {
  self.sheet.dispose()
}

///|
fn trace_bench_address(prefix : String, index : Int) -> String {
  prefix + index.to_string()
}

///|
fn trace_bench_formula(source : CellId, offset : Int) -> Formula {
  Formula::add(
    Formula::cell_ref(source),
    Formula::literal(CellValue::from_int(offset)),
  )
}

///|
fn trace_bench_install_formula(
  sheet : Worksheet,
  target : CellId,
  formula : Formula,
) -> Unit {
  match sheet.set_formula_ast(target, CellType::t_int(), formula) {
    Ok(_) => ()
    Err(_) => abort("trace bench formula install should succeed")
  }
}

///|
fn trace_bench_prime(sheet : Worksheet, formula_ids : Array[CellId]) -> Unit {
  formula_ids.each(id => {
    let _ = sheet.read(id)
  })
}

///|
fn trace_bench_sparse_affected_fixture(
  formula_count : Int,
  sheet_number : Int,
) -> TraceBenchFixture {
  let rt = @incr.Runtime()
  let sheet = Worksheet(rt, SheetId(sheet_number))
  let source = CellId(sheet.sheet_id(), "S0")
  let source_ids : Array[CellId] = [source]
  let formula_ids : Array[CellId] = []
  ignore(sheet.set_input(source, CellValue::from_int(0)))
  for i in 0..<formula_count {
    let target = CellId(sheet.sheet_id(), trace_bench_address("F", i))
    formula_ids.push(target)
    let formula = if i == 0 {
      trace_bench_formula(source, i)
    } else {
      Formula::literal(CellValue::from_int(i))
    }
    trace_bench_install_formula(sheet, target, formula)
  }
  trace_bench_prime(sheet, formula_ids)
  { sheet, source_ids, formula_ids }
}

///|
fn trace_bench_shared_source_fixture(
  formula_count : Int,
  sheet_number : Int,
) -> TraceBenchFixture {
  let rt = @incr.Runtime()
  let sheet = Worksheet(rt, SheetId(sheet_number))
  let source = CellId(sheet.sheet_id(), "S0")
  let source_ids : Array[CellId] = [source]
  let formula_ids : Array[CellId] = []
  ignore(sheet.set_input(source, CellValue::from_int(0)))
  for i in 0..<formula_count {
    let target = CellId(sheet.sheet_id(), trace_bench_address("F", i))
    formula_ids.push(target)
    trace_bench_install_formula(sheet, target, trace_bench_formula(source, i))
  }
  trace_bench_prime(sheet, formula_ids)
  { sheet, source_ids, formula_ids }
}

///|
fn trace_bench_visible_formula_ids(
  formula_ids : Array[CellId],
  visible_count : Int,
) -> Array[CellId] {
  let visible : Array[CellId] = []
  for i in 0..<visible_count {
    visible.push(formula_ids[i])
  }
  visible
}

///|
fn trace_bench_global_noop(
  b : @bench.T,
  formula_count : Int,
  sheet_number : Int,
) -> Unit {
  let fixture = trace_bench_sparse_affected_fixture(formula_count, sheet_number)
  let source = fixture.source_ids[0]
  b.bench(fn() {
    let (_, trace) = fixture.sheet.trace(() => {
      fixture.sheet.set_input(source, CellValue::from_int(0))
    })
    b.keep(trace)
  })
  fixture.dispose()
}

///|
fn trace_bench_global_one_affected(
  b : @bench.T,
  formula_count : Int,
  sheet_number : Int,
) -> Unit {
  let fixture = trace_bench_sparse_affected_fixture(formula_count, sheet_number)
  let source = fixture.source_ids[0]
  let mut step = 0
  b.bench(fn() {
    step += 1
    let (_, trace) = fixture.sheet.trace(() => {
      fixture.sheet.set_input(source, CellValue::from_int(step))
    })
    b.keep(trace)
  })
  fixture.dispose()
}

///|
fn trace_bench_global_shared_source(
  b : @bench.T,
  formula_count : Int,
  sheet_number : Int,
) -> Unit {
  let fixture = trace_bench_shared_source_fixture(formula_count, sheet_number)
  let source = fixture.source_ids[0]
  let mut step = 0
  b.bench(fn() {
    step += 1
    let (_, trace) = fixture.sheet.trace(() => {
      fixture.sheet.set_input(source, CellValue::from_int(step))
    })
    b.keep(trace)
  })
  fixture.dispose()
}

///|
fn trace_bench_bounded_one_affected(
  b : @bench.T,
  formula_count : Int,
  visible_count : Int,
  sheet_number : Int,
) -> Unit {
  let fixture = trace_bench_sparse_affected_fixture(formula_count, sheet_number)
  let source = fixture.source_ids[0]
  let visible = trace_bench_visible_formula_ids(
    fixture.formula_ids,
    visible_count,
  )
  let mut step = 0
  b.bench(fn() {
    step += 1
    let (_, trace) = fixture.sheet.trace_observed_formulas(visible, () => {
      fixture.sheet.set_input(source, CellValue::from_int(step))
    })
    b.keep(trace)
  })
  fixture.dispose()
}

///|
fn trace_bench_bounded_shared_source(
  b : @bench.T,
  formula_count : Int,
  visible_count : Int,
  sheet_number : Int,
) -> Unit {
  let fixture = trace_bench_shared_source_fixture(formula_count, sheet_number)
  let source = fixture.source_ids[0]
  let visible = trace_bench_visible_formula_ids(
    fixture.formula_ids,
    visible_count,
  )
  let mut step = 0
  b.bench(fn() {
    step += 1
    let (_, trace) = fixture.sheet.trace_observed_formulas(visible, () => {
      fixture.sheet.set_input(source, CellValue::from_int(step))
    })
    b.keep(trace)
  })
  fixture.dispose()
}

///|
test "trace bench: global no-op edit scans 100 formulas" (b : @bench.T) {
  trace_bench_global_noop(b, 100, 179100)
}

///|
test "trace bench: global no-op edit scans 1000 formulas" (b : @bench.T) {
  trace_bench_global_noop(b, 1000, 179101)
}

///|
test "trace bench: global no-op edit scans 2500 formulas" (b : @bench.T) {
  trace_bench_global_noop(b, 2500, 179102)
}

///|
test "trace bench: global one affected formula scans 100 formulas" (
  b : @bench.T,
) {
  trace_bench_global_one_affected(b, 100, 179110)
}

///|
test "trace bench: global one affected formula scans 1000 formulas" (
  b : @bench.T,
) {
  trace_bench_global_one_affected(b, 1000, 179111)
}

///|
test "trace bench: global one affected formula scans 2500 formulas" (
  b : @bench.T,
) {
  trace_bench_global_one_affected(b, 2500, 179112)
}

///|
test "trace bench: global shared source scans 100 formulas" (b : @bench.T) {
  trace_bench_global_shared_source(b, 100, 179120)
}

///|
test "trace bench: global shared source scans 1000 formulas" (b : @bench.T) {
  trace_bench_global_shared_source(b, 1000, 179121)
}

///|
test "trace bench: global shared source scans 2500 formulas" (b : @bench.T) {
  trace_bench_global_shared_source(b, 2500, 179122)
}

///|
test "trace bench: bounded one affected in 2500 formulas reads 1 formula" (
  b : @bench.T,
) {
  trace_bench_bounded_one_affected(b, 2500, 1, 179130)
}

///|
test "trace bench: bounded one affected in 2500 formulas reads 10 formulas" (
  b : @bench.T,
) {
  trace_bench_bounded_one_affected(b, 2500, 10, 179131)
}

///|
test "trace bench: bounded one affected in 2500 formulas reads 100 formulas" (
  b : @bench.T,
) {
  trace_bench_bounded_one_affected(b, 2500, 100, 179132)
}

///|
test "trace bench: bounded shared source in 2500 formulas reads 1 formula" (
  b : @bench.T,
) {
  trace_bench_bounded_shared_source(b, 2500, 1, 179140)
}

///|
test "trace bench: bounded shared source in 2500 formulas reads 10 formulas" (
  b : @bench.T,
) {
  trace_bench_bounded_shared_source(b, 2500, 10, 179141)
}

///|
test "trace bench: bounded shared source in 2500 formulas reads 100 formulas" (
  b : @bench.T,
) {
  trace_bench_bounded_shared_source(b, 2500, 100, 179142)
}
