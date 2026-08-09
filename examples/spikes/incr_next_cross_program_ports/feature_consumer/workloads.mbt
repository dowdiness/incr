///|
fn provider_or_abort() -> @feature_provider.FeatureProvider {
  match @feature_provider.FeatureProvider::create() {
    Ok(provider) => provider
    Err(_) => abort("provider")
  }
}

///|
fn export_or_abort(
  provider : @feature_provider.FeatureProvider,
) -> @program.ReadExport[Int] {
  match provider.export_value() {
    Ok(exported) => exported
    Err(_) => abort("exported")
  }
}

///|
fn local_or_abort(
  provider : @feature_provider.FeatureProvider,
  consumer : @program.Program,
) -> @program.ReadPort[Int] {
  match provider.local_port(consumer) {
    Ok(port) => port
    Err(_) => abort("local_port port")
  }
}

///|
fn import_or_abort(
  consumer : @program.Program,
  exported : @program.ReadExport[Int],
) -> @program.ReadPort[Int] {
  match consumer.import_export(exported) {
    Ok(port) => port
    Err(_) => abort("import")
  }
}

///|
fn declare_or_abort(
  builder : @program.FormulaBuilder,
  port : @program.ReadPort[Int],
) -> @program.DeclaredRead[Int] {
  match builder.declare_port(port) {
    Ok(declared) => declared
    Err(_) => abort("declare")
  }
}

///|
fn formula_or_abort(
  builder : @program.FormulaBuilder,
  compute : (@program.ProgramEvalCtx) -> Result[Int, @program.ProgramError],
) -> @program.Formula[Int] {
  match builder.build(compute) {
    Ok(formula) => formula
    Err(_) => abort("build")
  }
}

///|
fn local_origin_manifest() -> Bool {
  let provider = provider_or_abort()
  let consumer = provider.local_consumer_program()
  let local_port = local_or_abort(provider, consumer)
  let builder = consumer.builder()
  let declared = declare_or_abort(builder, local_port)
  let formula = formula_or_abort(builder, ctx => ctx.read(declared))
  let result = consumer.read(formula)
  let entries = formula.manifest().entries()
  let debug = formula.debug()
  let preserved_entries = formula.manifest().entries()
  let replacement = export_or_abort(provider)
  entries[0] = @program.ManifestEntry::{
    local_port_id: entries[0].local_port_id,
    origin: @program.PortOrigin::Imported(
      provider_program=replacement.provider_program(),
      export_id=replacement.export_id(),
    ),
  }
  let passed = result == Ok(Ok(10)) &&
    preserved_entries.length() == 1 &&
    preserved_entries[0].origin is @program.PortOrigin::Local &&
    debug.manifest.length() == 1 &&
    debug.observations.length() == 1 &&
    debug.observations[0].origin is @program.PortOrigin::Local
  ignore(provider.close())
  passed
}

///|
fn same_export_two_consumers() -> Bool {
  let provider = provider_or_abort()
  let exported = export_or_abort(provider)
  let first_consumer = provider.consumer_program()
  let second_consumer = provider.consumer_program()
  let first = import_or_abort(first_consumer, exported)
  let second = import_or_abort(second_consumer, exported)
  let same_export = first.origin() is @program.PortOrigin::Imported(
    provider_program=_,
    export_id=first_export,
  ) && second.origin() is @program.PortOrigin::Imported(
    provider_program=_,
    export_id=second_export,
  ) && first_export == second_export
  let distinct_ports = first.port_id() != second.port_id() &&
    first.port_id().program() != second.port_id().program()
  ignore(provider.close())
  same_export && distinct_ports
}

///|
fn same_consumer_imports_twice() -> Bool {
  let provider = provider_or_abort()
  let exported = export_or_abort(provider)
  let consumer = provider.consumer_program()
  let first = import_or_abort(consumer, exported)
  let second = import_or_abort(consumer, exported)
  let same_export = match (first.origin(), second.origin()) {
    (
      @program.PortOrigin::Imported(export_id=first_export, ..),
      @program.PortOrigin::Imported(export_id=second_export, ..),
    ) => first_export == second_export
    _ => false
  }
  let passed = same_export &&
    first.port_id() != second.port_id() &&
    first.port_id().sequence() == 1 &&
    second.port_id().sequence() == 2
  ignore(provider.close())
  passed
}

///|
fn imported_formula_observations() -> Bool {
  let provider = provider_or_abort()
  let exported = export_or_abort(provider)
  let consumer = provider.local_consumer_program()
  let imported = import_or_abort(consumer, exported)
  let local_port = local_or_abort(provider, consumer)
  // The builder is single-use, so make both declarations in one builder.
  let builder = consumer.builder()
  let local_read = declare_or_abort(builder, local_port)
  let imported_read_again = declare_or_abort(builder, imported)
  let formula = formula_or_abort(builder, ctx => {
    match (ctx.read(local_read), ctx.read(imported_read_again)) {
      (Ok(left), Ok(right)) => Ok(left + right)
      (Err(error), _) => Err(error)
      (_, Err(error)) => Err(error)
    }
  })
  let result = consumer.read(formula)
  let debug = formula.debug()
  let entries = formula.manifest().entries()
  let passed = result == Ok(Ok(20)) &&
    entries.length() == 2 &&
    entries[0].origin is @program.PortOrigin::Local &&
    entries[1].origin is @program.PortOrigin::Imported(..) &&
    debug.observations.length() == 2 &&
    debug.observations[0].local_port_id == local_port.port_id() &&
    debug.observations[0].origin is @program.PortOrigin::Local &&
    debug.observations[1].local_port_id == imported.port_id() &&
    debug.observations[1].origin is @program.PortOrigin::Imported(..)
  ignore(provider.close())
  passed
}

///|
fn dynamic_imported_origins() -> Bool {
  let provider = provider_or_abort()
  let left_export = export_or_abort(provider)
  let right_export = export_or_abort(provider)
  let consumer = provider.consumer_program()
  let left = import_or_abort(consumer, left_export)
  let right = import_or_abort(consumer, right_export)
  let builder = consumer.builder()
  let left_read = declare_or_abort(builder, left)
  let right_read = declare_or_abort(builder, right)
  let formula = formula_or_abort(builder, ctx => {
    match ctx.read(left_read) {
      Ok(10) => ctx.read(right_read)
      Ok(_) => Ok(20)
      Err(error) => Err(error)
    }
  })
  let first = consumer.read(formula)
  let first_observed = formula.debug().observations
  let changed = provider.set(20)
  let second = consumer.read(formula)
  let second_observed = formula.debug().observations
  let entries = formula.manifest().entries()
  let passed = changed &&
    first == Ok(Ok(10)) &&
    second == Ok(Ok(20)) &&
    entries.length() == 2 &&
    first_observed.length() == 2 &&
    second_observed.length() == 1 &&
    first_observed[0].origin is @program.PortOrigin::Imported(..) &&
    first_observed[1].origin is @program.PortOrigin::Imported(..) &&
    second_observed[0].origin is @program.PortOrigin::Imported(..)
  ignore(provider.close())
  passed
}

///|
fn provider_close_is_outer_error() -> Bool {
  let provider = provider_or_abort()
  let exported = export_or_abort(provider)
  let consumer = provider.consumer_program()
  let imported = import_or_abort(consumer, exported)
  let builder = consumer.builder()
  let declared = declare_or_abort(builder, imported)
  let formula = formula_or_abort(builder, ctx => ctx.read(declared))
  let local_builder = consumer.builder()
  let consumer_region_formula = formula_or_abort(local_builder, _ctx => Ok(99))
  let closed = provider.close()
  let result = consumer.read(formula)
  let consumer_region_open = consumer.read(consumer_region_formula) == Ok(Ok(99))
  closed &&
  result is Err(@program.FormulaReadError::ClosedRegion) &&
  consumer_region_open
}

///|
fn different_store_rejects_without_allocation() -> Bool {
  let first_provider = provider_or_abort()
  let first_export = export_or_abort(first_provider)
  let second_provider = provider_or_abort()
  let second_export = export_or_abort(second_provider)
  let consumer = second_provider.consumer_program()
  let own = import_or_abort(consumer, second_export)
  let rejected = consumer.import_export(first_export)
  let next = import_or_abort(consumer, second_export)
  let passed = rejected is Err(@program.ImportError::DifferentStore) &&
    own.port_id().sequence() == 1 &&
    next.port_id().sequence() == 2 &&
    first_export.export_id() != second_export.export_id()
  ignore(first_provider.close())
  ignore(second_provider.close())
  passed
}

///|
fn foreign_local_port_rejected() -> Bool {
  let provider = provider_or_abort()
  let first_consumer = provider.local_consumer_program()
  let second_consumer = provider.local_consumer_program()
  let local_port = local_or_abort(provider, first_consumer)
  let builder = second_consumer.builder()
  let rejected = builder.declare_port(local_port)
  ignore(provider.close())
  rejected is Err(@program.BuilderError::ForeignPort(_))
}

///|
fn foreign_formula_rejected() -> Bool {
  let provider = provider_or_abort()
  let exported = export_or_abort(provider)
  let owner = provider.consumer_program()
  let foreign = provider.consumer_program()
  let imported = import_or_abort(owner, exported)
  let builder = owner.builder()
  let declared = declare_or_abort(builder, imported)
  let formula = formula_or_abort(builder, ctx => ctx.read(declared))
  let before = provider.read_attempts()
  let rejected = foreign.read(formula)
    is Err(@program.FormulaReadError::ForeignFormula) &&
    provider.read_attempts() == before
  let owner_reads = owner.read(formula) == Ok(Ok(10))
  ignore(provider.close())
  rejected && owner_reads
}

///|
fn reexport_forbidden() -> Bool {
  let provider = provider_or_abort()
  let exported = export_or_abort(provider)
  let consumer = provider.consumer_program()
  let imported = import_or_abort(consumer, exported)
  let rejected = consumer.export_port(imported)
  ignore(provider.close())
  rejected is Err(@program.ExportError::ReexportForbidden)
}

///|
fn unauthorized_foreign_declaration() -> Bool {
  let provider = provider_or_abort()
  let first_consumer = provider.local_consumer_program()
  let second_consumer = provider.local_consumer_program()
  let local_port = local_or_abort(provider, first_consumer)
  let first_builder = first_consumer.builder()
  let foreign_declared = declare_or_abort(first_builder, local_port)
  let second_builder = second_consumer.builder()
  let formula = formula_or_abort(second_builder, ctx => ctx.read(foreign_declared))
  let before = provider.read_attempts()
  let result = second_consumer.read(formula)
  let after = provider.read_attempts()
  let passed = result is Ok(Err(@program.ProgramError::UnauthorizedRead(_))) &&
    before == after &&
    formula.debug().observations.length() == 0
  ignore(provider.close())
  passed
}

///|
fn escaped_context_rejected() -> Bool {
  let provider = provider_or_abort()
  let consumer = provider.local_consumer_program()
  let local_port = local_or_abort(provider, consumer)
  let builder = consumer.builder()
  let declared = declare_or_abort(builder, local_port)
  let escaped : Ref[@program.ProgramEvalCtx?] = Ref(None)
  let formula = formula_or_abort(builder, ctx => {
    escaped.val = Some(ctx)
    ctx.read(declared)
  })
  let first = consumer.read(formula)
  let reads_before = provider.read_attempts()
  let observations_before = formula.debug().observations
  let expired = match escaped.val {
    Some(ctx) => ctx.read(declared)
    None => abort("escaped context")
  }
  let rejected = expired is Err(@program.ProgramError::ExpiredProgramEvaluation(_)) &&
    provider.read_attempts() == reads_before &&
    formula.debug().observations == observations_before
  let recovered = provider.set(12) && consumer.read(formula) == Ok(Ok(12))
  escaped.val = None
  ignore(provider.close())
  first == Ok(Ok(10)) && rejected && recovered
}

///|
fn first_structural_error_wins() -> Bool {
  let provider = provider_or_abort()
  let exported = export_or_abort(provider)
  let consumer = provider.consumer_program()
  let imported = import_or_abort(consumer, exported)
  let builder = consumer.builder()
  let declared = declare_or_abort(builder, imported)
  let formula = formula_or_abort(builder, ctx => {
    ignore(ctx.read(declared))
    ctx.read(declared)
  })
  ignore(provider.close())
  consumer.read(formula) is Err(@program.FormulaReadError::ClosedRegion)
}

///|
fn defensive_debug_copies() -> Bool {
  let provider = provider_or_abort()
  let exported = export_or_abort(provider)
  let consumer = provider.consumer_program()
  let imported = import_or_abort(consumer, exported)
  let builder = consumer.builder()
  let declared = declare_or_abort(builder, imported)
  let formula = formula_or_abort(builder, ctx => ctx.read(declared))
  ignore(consumer.read(formula))
  let manifest = formula.manifest().entries()
  let debug = formula.debug()
  let original_id = manifest[0].local_port_id
  manifest[0] = @program.ManifestEntry::{
    local_port_id: original_id,
    origin: @program.PortOrigin::Local,
  }
  debug.manifest[0] = @program.ManifestEntry::{
    local_port_id: original_id,
    origin: @program.PortOrigin::Local,
  }
  let preserved = formula.manifest().entries()[0].origin is @program.PortOrigin::Imported(..) &&
    formula.debug().manifest[0].origin is @program.PortOrigin::Imported(..)
  ignore(provider.close())
  preserved
}

///|
fn all_workloads() -> Bool {
  let a = local_origin_manifest()
  let b = same_export_two_consumers()
  let c = same_consumer_imports_twice()
  let d = imported_formula_observations()
  let e = dynamic_imported_origins()
  let f = provider_close_is_outer_error()
  let g = different_store_rejects_without_allocation()
  let h = foreign_local_port_rejected()
  let i = foreign_formula_rejected()
  let j = reexport_forbidden()
  let k = unauthorized_foreign_declaration()
  let l = escaped_context_rejected()
  let m = first_structural_error_wins()
  let n = defensive_debug_copies()
  a && b && c && d && e && f && g && h && i && j && k && l && m && n
}

///|
test "cross-program typed port workloads" {
  assert_true(all_workloads())
}
