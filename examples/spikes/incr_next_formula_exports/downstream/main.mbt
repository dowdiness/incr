///|
fn provider_or_abort() -> @feature_provider.FeatureProvider {
  match @feature_provider.FeatureProvider::create() {
    Ok(provider) => provider
    Err(_) => abort("provider")
  }
}

///|
fn derived_or_abort(
  provider : @feature_provider.FeatureProvider,
) -> @derived_provider.DerivedProvider {
  match @derived_provider.DerivedProvider::create(provider) {
    Ok(derived) => derived
    Err(_) => abort("derived provider")
  }
}

///|
fn c_formula_or_abort(
  program : @program.Program,
  exported : @program.ReadExport[Result[Int, @program.ProgramError]],
) -> @program.Formula[Result[Int, @program.ProgramError]] {
  let imported = match program.import_export(exported) {
    Ok(port) => port
    Err(_) => abort("C import")
  }
  let builder = program.builder()
  let declared = match builder.declare_port(imported) {
    Ok(read) => read
    Err(_) => abort("C declaration")
  }
  match builder.build(ctx => {
    match ctx.read(declared) {
      Ok(Ok(value)) => Ok(Ok(value + 1))
      Ok(Err(provider_error)) => Ok(Err(provider_error))
      Err(consumer_error) => Err(consumer_error)
    }
  }) {
    Ok(formula) => formula
    Err(_) => abort("C formula")
  }
}

///|
fn port_free_formula_or_abort(
  program : @program.Program,
  value : Int,
) -> @program.Formula[Int] {
  let builder = program.builder()
  match builder.build(_ctx => Ok(value)) {
    Ok(formula) => formula
    Err(_) => abort("port-free formula")
  }
}

///|
fn provider_and_derived() -> (
  @feature_provider.FeatureProvider,
  @derived_provider.DerivedProvider,
) {
  let provider = provider_or_abort()
  let derived = derived_or_abort(provider)
  (provider, derived)
}

///|
fn a_b_c_updates_and_manifests() -> Bool {
  let (provider, derived) = provider_and_derived()
  let c = derived.consumer_program()
  let formula = c_formula_or_abort(c, derived.export_formula())
  let first = c.read(formula)
  let b_entries = derived.formula().manifest().entries()
  let c_entries = formula.manifest().entries()
  let b_edge = match b_entries.get(0) {
    Some(entry) => match entry.origin {
      @program.PortOrigin::Imported(provider_program~, export_id~) =>
        provider_program == provider.program().id() &&
        export_id == derived.source_export_id()
      @program.PortOrigin::Local => false
    }
    None => false
  }
  let b_export = derived.export_formula()
  let c_edge = match c_entries.get(0) {
    Some(entry) => match entry.origin {
      @program.PortOrigin::Imported(provider_program~, export_id~) =>
        provider_program == b_export.provider_program() &&
        export_id == b_export.export_id()
      @program.PortOrigin::Local => false
    }
    None => false
  }
  let updated = provider.set(20)
  let second = c.read(formula)
  ignore(provider.close())
  first == Ok(Ok(Ok(21))) && updated && second == Ok(Ok(Ok(41))) &&
  b_entries.length() == 1 && c_entries.length() == 1 && b_edge && c_edge
}

///|
fn close_a_propagates_structurally() -> Bool {
  let (provider, derived) = provider_and_derived()
  let b = derived.program()
  let c = derived.consumer_program()
  let b_formula = derived.formula()
  let c_formula = c_formula_or_abort(c, derived.export_formula())
  let b_local = port_free_formula_or_abort(b, 7)
  let c_local = port_free_formula_or_abort(c, 8)
  let closed = provider.close()
  let b_result = b.read(b_formula)
  let c_result = c.read(c_formula)
  let b_local_result = b.read(b_local)
  let c_local_result = c.read(c_local)
  closed && b_result is Err(@program.FormulaReadError::ClosedRegion) &&
  c_result is Err(@program.FormulaReadError::ClosedRegion) &&
  b_local_result == Ok(Ok(7)) && c_local_result == Ok(Ok(8))
}

///|
fn close_b_keeps_c_region_open() -> Bool {
  let (provider, derived) = provider_and_derived()
  let c = derived.consumer_program()
  let c_formula = c_formula_or_abort(c, derived.export_formula())
  let c_local = port_free_formula_or_abort(c, 9)
  let closed = derived.close()
  let imported_result = c.read(c_formula)
  let local_result = c.read(c_local)
  ignore(provider.close())
  closed && imported_result is Err(@program.FormulaReadError::ClosedRegion) &&
  local_result == Ok(Ok(9))
}

///|
fn foreign_formula_rejects_before_export_allocation() -> Bool {
  let (provider, derived) = provider_and_derived()
  let foreign = derived.consumer_program()
  let rejected = foreign.export_formula(derived.formula())
  let own_formula = port_free_formula_or_abort(foreign, 12)
  let own_export = foreign.export_formula(own_formula)
  ignore(provider.close())
  rejected is Err(@program.ExportError::ForeignFormula) &&
  own_export is Ok(exported) && exported.export_id().sequence() == 1
}

///|
fn same_formula_exports_are_distinct() -> Bool {
  let (provider, derived) = provider_and_derived()
  let first = derived.program().export_formula(derived.formula())
  let second = derived.program().export_formula(derived.formula())
  ignore(provider.close())
  match (first, second) {
    (Ok(first_export), Ok(second_export)) =>
      first_export.export_id() != second_export.export_id() &&
      first_export.export_id().sequence() + 1 == second_export.export_id().sequence()
    _ => false
  }
}

///|
fn same_formula_imports_keep_export_id() -> Bool {
  let (provider, derived) = provider_and_derived()
  let exported = derived.export_formula()
  let first_consumer = derived.consumer_program()
  let second_consumer = derived.consumer_program()
  let first = first_consumer.import_export(exported)
  let second = second_consumer.import_export(exported)
  let passed = match (first, second) {
    (Ok(first_port), Ok(second_port)) =>
      first_port.port_id() != second_port.port_id() &&
      first_port.origin() is @program.PortOrigin::Imported(
        provider_program=first_program,
        export_id=first_export,
      ) && second_port.origin() is @program.PortOrigin::Imported(
        provider_program=second_program,
        export_id=second_export,
      ) && first_program == second_program && first_export == second_export
    _ => false
  }
  ignore(provider.close())
  passed
}

///|
fn provider_application_error_is_nested_value() -> Bool {
  let (provider, derived) = provider_and_derived()
  let c = derived.consumer_program()
  let formula = c_formula_or_abort(c, derived.unauthorized_export())
  let reads_before = provider.read_attempts()
  let result = c.read(formula)
  let reads_after = provider.read_attempts()
  ignore(provider.close())
  result is Ok(Ok(Err(@program.ProgramError::UnauthorizedRead(_)))) &&
  reads_before == reads_after
}

///|
fn forwarding_formula_is_exportable() -> Bool {
  let (provider, derived) = provider_and_derived()
  let a_export = match provider.export_value() {
    Ok(exported) => exported
    Err(_) => abort("forwarding source export")
  }
  let b = derived.program()
  let imported = match b.import_export(a_export) {
    Ok(port) => port
    Err(_) => abort("forwarding import")
  }
  let builder = b.builder()
  let declared = match builder.declare_port(imported) {
    Ok(read) => read
    Err(_) => abort("forwarding declaration")
  }
  let forwarding = match builder.build(ctx => ctx.read(declared)) {
    Ok(formula) => formula
    Err(_) => abort("forwarding formula")
  }
  let exported = match b.export_formula(forwarding) {
    Ok(exported) => exported
    Err(_) => abort("forwarding export")
  }
  let c = derived.consumer_program()
  let consumer_formula = c_formula_or_abort(c, exported)
  let manifest = forwarding.manifest().entries()
  let passed = c.read(consumer_formula) == Ok(Ok(Ok(11))) &&
    manifest.length() == 1 &&
    manifest[0].origin is @program.PortOrigin::Imported(
      provider_program=provider_program,
      export_id=export_id,
    ) && provider_program == provider.program().id() &&
    export_id.provider_program() == provider.program().id()
  ignore(provider.close())
  passed
}

///|
fn defensive_formula_snapshots() -> Bool {
  let (provider, derived) = provider_and_derived()
  let c = derived.consumer_program()
  let formula = c_formula_or_abort(c, derived.export_formula())
  ignore(c.read(formula))
  let entries = formula.manifest().entries()
  let debug = formula.debug()
  let original_id = entries[0].local_port_id
  entries[0] = @program.ManifestEntry::{
    local_port_id: original_id,
    origin: @program.PortOrigin::Local,
  }
  debug.manifest[0] = @program.ManifestEntry::{
    local_port_id: original_id,
    origin: @program.PortOrigin::Local,
  }
  let preserved = formula.manifest().entries()[0].origin is
    @program.PortOrigin::Imported(..) &&
    formula.debug().manifest[0].origin is @program.PortOrigin::Imported(..) &&
    formula.debug().observations.length() == 1
  ignore(provider.close())
  preserved
}

///|
fn consumer_application_error_is_own_value() -> Bool {
  let (provider, derived) = provider_and_derived()
  let c = derived.consumer_program()
  let imported = match c.import_export(derived.export_formula()) {
    Ok(port) => port
    Err(_) => abort("consumer auth import")
  }
  let first_builder = c.builder()
  let foreign_declared = match first_builder.declare_port(imported) {
    Ok(read) => read
    Err(_) => abort("consumer auth declaration")
  }
  ignore(match first_builder.build(ctx => ctx.read(foreign_declared)) {
    Ok(formula) => formula
    Err(_) => abort("consumer auth setup")
  })
  let second_builder = c.builder()
  let formula = match second_builder.build(ctx => ctx.read(foreign_declared)) {
    Ok(formula) => formula
    Err(_) => abort("consumer auth formula")
  }
  let result = c.read(formula)
  ignore(provider.close())
  result is Ok(Err(@program.ProgramError::UnauthorizedRead(_)))
}

///|
fn nested_first_structural_error_wins() -> Bool {
  let (provider, derived) = provider_and_derived()
  let c = derived.consumer_program()
  let imported = match c.import_export(derived.export_formula()) {
    Ok(port) => port
    Err(_) => abort("structural import")
  }
  let builder = c.builder()
  let declared = match builder.declare_port(imported) {
    Ok(read) => read
    Err(_) => abort("structural declaration")
  }
  let formula = match builder.build(ctx => {
    ignore(ctx.read(declared))
    ctx.read(declared)
  }) {
    Ok(formula) => formula
    Err(_) => abort("structural formula")
  }
  ignore(provider.close())
  c.read(formula) is Err(@program.FormulaReadError::ClosedRegion)
}

///|
fn reexport_remains_forbidden() -> Bool {
  let (provider, derived) = provider_and_derived()
  let consumer = derived.consumer_program()
  let imported = match consumer.import_export(derived.export_formula()) {
    Ok(port) => port
    Err(_) => abort("reexport import")
  }
  let rejected = consumer.export_port(imported)
  ignore(provider.close())
  rejected is Err(@program.ExportError::ReexportForbidden)
}

///|
fn all_workloads() -> Bool {
  a_b_c_updates_and_manifests() &&
  close_a_propagates_structurally() &&
  close_b_keeps_c_region_open() &&
  foreign_formula_rejects_before_export_allocation() &&
  same_formula_exports_are_distinct() &&
  same_formula_imports_keep_export_id() &&
  provider_application_error_is_nested_value() &&
  forwarding_formula_is_exportable() &&
  defensive_formula_snapshots() &&
  consumer_application_error_is_own_value() &&
  nested_first_structural_error_wins() &&
  reexport_remains_forbidden()
}

///|
test "formula export workloads" {
  assert_true(all_workloads())
}

///|
fn main {
  let passed = all_workloads()
  println(
    if passed {
      "formula_exports workloads=true"
    } else {
      "formula_exports workloads=false"
    },
  )
  if !passed {
    abort("formula export workload failed")
  }
}
