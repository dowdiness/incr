///|
fn region_or_abort(store : @kernel.Store) -> @kernel.Region {
  match store.region() {
    Ok(region) => region
    Err(_) => abort("region")
  }
}

///|
fn[T] source_or_abort(region : @kernel.Region, value : T) -> @kernel.Source[T] {
  match region.source(value) {
    Ok(source) => source
    Err(_) => abort("source")
  }
}

///|
fn[T] port_or_abort(program : @program.Program, view : @kernel.View[T]) -> @program.ReadPort[T] {
  match program.port(view) {
    Ok(port) => port
    Err(_) => abort("port")
  }
}

///|
fn[T] declared_or_abort(
  builder : @program.FormulaBuilder,
  port : @program.ReadPort[T],
) -> @program.DeclaredRead[T] {
  match builder.declare_port(port) {
    Ok(declared) => declared
    Err(_) => abort("declare")
  }
}

///|
fn[V] formula_or_abort(
  builder : @program.FormulaBuilder,
  compute : (@program.ProgramEvalCtx) -> Result[V, @program.ProgramError],
) -> @program.Formula[V] {
  match builder.build(compute) {
    Ok(formula) => formula
    Err(_) => abort("build")
  }
}

///|
fn initial_two_ports() -> Bool {
  let store = @kernel.Store()
  let region = region_or_abort(store)
  let program = @program.Program(region)
  let left = source_or_abort(region, 10)
  let right = source_or_abort(region, 32)
  let left_port = port_or_abort(program, left.view())
  let right_port = port_or_abort(program, right.view())
  let builder = program.builder()
  let left_read = declared_or_abort(builder, left_port)
  let right_read = declared_or_abort(builder, right_port)
  let formula = formula_or_abort(builder, ctx => {
    match (ctx.read(left_read), ctx.read(right_read)) {
      (Ok(a), Ok(b)) => Ok(a + b)
      (Err(error), _) => Err(error)
      (_, Err(error)) => Err(error)
    }
  })
  let result = store.read(formula.view())
  let debug = formula.debug()
  let manifest = formula.manifest().port_ids()
  manifest[0] = manifest[1]
  let preserved_manifest = formula.manifest().port_ids()
  let passed = result == Ok(Ok(42)) &&
    manifest.length() == 2 &&
    preserved_manifest[0] != preserved_manifest[1] &&
    debug.observations.length() == 2 &&
    debug.observations[0].port_id == preserved_manifest[0] &&
    debug.observations[1].port_id == preserved_manifest[1]
  ignore(region.close())
  passed
}

///|
fn same_view_distinct_ports() -> Bool {
  let store = @kernel.Store()
  let region = region_or_abort(store)
  let program = @program.Program(region)
  let source = source_or_abort(region, 9)
  let a = port_or_abort(program, source.view())
  let b = port_or_abort(program, source.view())
  let builder = program.builder()
  let da = declared_or_abort(builder, a)
  let db = declared_or_abort(builder, b)
  let formula = formula_or_abort(builder, ctx => {
    match (ctx.read(da), ctx.read(db)) {
      (Ok(x), Ok(y)) => Ok(x + y)
      (Err(error), _) => Err(error)
      (_, Err(error)) => Err(error)
    }
  })
  let result = store.read(formula.view())
  let observed = formula.debug().observations
  let manifest = formula.manifest().port_ids()
  let passed = result == Ok(Ok(18)) &&
    manifest.length() == 2 &&
    manifest[0] != manifest[1] &&
    observed.length() == 2 &&
    observed[0].port_id == manifest[0] &&
    observed[1].port_id == manifest[1] &&
    observed[0].port_id != observed[1].port_id &&
    observed[0].ordinal == 0 &&
    observed[1].ordinal == 1 &&
    source.debug().read_count == 2
  ignore(region.close())
  passed
}

///|
fn dynamic_branch() -> Bool {
  let store = @kernel.Store()
  let region = region_or_abort(store)
  let program = @program.Program(region)
  let mode = source_or_abort(region, true)
  let left = source_or_abort(region, 3)
  let right = source_or_abort(region, 8)
  let mode_port = port_or_abort(program, mode.view())
  let left_port = port_or_abort(program, left.view())
  let right_port = port_or_abort(program, right.view())
  let builder = program.builder()
  let mode_read = declared_or_abort(builder, mode_port)
  let left_read = declared_or_abort(builder, left_port)
  let right_read = declared_or_abort(builder, right_port)
  let formula = formula_or_abort(builder, ctx => {
    match ctx.read(mode_read) {
      Err(error) => Err(error)
      Ok(true) => ctx.read(left_read)
      Ok(false) => ctx.read(right_read)
    }
  })
  let first = store.read(formula.view())
  let first_observed = formula.debug().observations
  let right_commit = store.transaction(tx => tx.set(mode, false))
  let second = store.read(formula.view())
  let second_observed = formula.debug().observations
  let stable_manifest = formula.manifest().port_ids()
  let passed = first == Ok(Ok(3)) &&
    right_commit is Ok(_) &&
    second == Ok(Ok(8)) &&
    first_observed.length() == 2 &&
    first_observed[0].port_id == stable_manifest[0] &&
    first_observed[1].port_id == stable_manifest[1] &&
    second_observed.length() == 2 &&
    second_observed[0].port_id == stable_manifest[0] &&
    second_observed[1].port_id == stable_manifest[2] &&
    stable_manifest.length() == 3
  ignore(region.close())
  passed
}

///|
fn duplicate_declaration() -> Bool {
  let store = @kernel.Store()
  let region = region_or_abort(store)
  let program = @program.Program(region)
  let source = source_or_abort(region, 6)
  let port = port_or_abort(program, source.view())
  let builder = program.builder()
  let first = declared_or_abort(builder, port)
  let second = declared_or_abort(builder, port)
  let formula = formula_or_abort(builder, ctx => {
    match (ctx.read(first), ctx.read(second)) {
      (Ok(a), Ok(b)) => Ok(a + b)
      (Err(error), _) => Err(error)
      (_, Err(error)) => Err(error)
    }
  })
  let result = store.read(formula.view())
  let debug = formula.debug()
  let passed = result == Ok(Ok(12)) &&
    formula.manifest().port_ids().length() == 1 &&
    debug.observations.length() == 2 &&
    debug.observations[0].port_id == debug.observations[1].port_id &&
    debug.observations[0].ordinal == 0 &&
    debug.observations[1].ordinal == 1
  ignore(region.close())
  passed
}

///|
fn foreign_declared_read() -> Bool {
  let store = @kernel.Store()
  let region = region_or_abort(store)
  let program = @program.Program(region)
  let source = source_or_abort(region, 11)
  let port = port_or_abort(program, source.view())
  let builder_a = program.builder()
  let declared_a = declared_or_abort(builder_a, port)
  let builder_b = program.builder()
  let formula = formula_or_abort(builder_b, ctx => ctx.read(declared_a))
  let before = source.debug().read_count
  let result = store.read(formula.view())
  let after = source.debug().read_count
  let unauthorized = result is Ok(Err(@program.ProgramError::UnauthorizedRead(_)))
  let passed = unauthorized && before == after && formula.debug().observations.length() == 0
  ignore(region.close())
  passed
}

///|
fn cross_program_and_lifecycle() -> Bool {
  let store = @kernel.Store()
  let region = region_or_abort(store)
  let first_program = @program.Program(region)
  let second_program = @program.Program(region)
  let source = source_or_abort(region, 5)
  let first_port = port_or_abort(first_program, source.view())
  let second_builder = second_program.builder()
  let cross_program = second_builder.declare_port(first_port)
  let own_builder = first_program.builder()
  let own_read = declared_or_abort(own_builder, first_port)
  let formula = formula_or_abort(own_builder, ctx => ctx.read(own_read))
  let after_build_declare = own_builder.declare_port(first_port)
  let duplicate_build = own_builder.build(ctx => ctx.read(own_read))
  let passed = cross_program is Err(@program.BuilderError::ForeignPort(_)) &&
    after_build_declare is Err(@program.BuilderError::BuilderExpired) &&
    duplicate_build is Err(@program.BuilderError::BuilderExpired) &&
    store.read(formula.view()) == Ok(Ok(5))
  ignore(region.close())
  passed
}

///|
fn failed_build_consumes_builder() -> Bool {
  let store = @kernel.Store()
  let region = region_or_abort(store)
  let program = @program.Program(region)
  let source = source_or_abort(region, 4)
  let port = port_or_abort(program, source.view())
  let builder = program.builder()
  let declared = declared_or_abort(builder, port)
  let attempted : Ref[
    Result[@program.Formula[Int], @program.BuilderError]?,
  ] = Ref(None)
  let trigger = match region.query_always_changed((_ctx, _ : Unit) => {
    attempted.val = Some(builder.build(ctx => ctx.read(declared)))
    Ok(())
  }) {
    Ok(query) => query
    Err(_) => abort("trigger query")
  }
  ignore(store.read(trigger.at(())))
  let rejected = attempted.val
    is Some(Err(@program.BuilderError::Region(_)))
  let declare_expired = builder.declare_port(port)
    is Err(@program.BuilderError::BuilderExpired)
  let build_expired = builder.build(ctx => ctx.read(declared))
    is Err(@program.BuilderError::BuilderExpired)
  ignore(region.close())
  rejected && declare_expired && build_expired
}

///|
fn escaped_eval_ctx_expires() -> Bool {
  let store = @kernel.Store()
  let region = region_or_abort(store)
  let program = @program.Program(region)
  let source = source_or_abort(region, 12)
  let port = port_or_abort(program, source.view())
  let builder = program.builder()
  let declared = declared_or_abort(builder, port)
  let escaped : Ref[@program.ProgramEvalCtx?] = Ref(None)
  let formula = formula_or_abort(builder, ctx => {
    escaped.val = Some(ctx)
    ctx.read(declared)
  })
  let first = store.read(formula.view())
  let reads_before = source.debug().read_count
  let observations_before = formula.debug().observations
  let expired = match escaped.val {
    Some(ctx) => ctx.read(declared)
    None => abort("escaped context")
  }
  let rejected = expired
    is Err(@program.ProgramError::ExpiredProgramEvaluation(_)) &&
    source.debug().read_count == reads_before &&
    formula.debug().observations == observations_before
  ignore(store.transaction(tx => tx.set(source, 13)))
  let recovered = store.read(formula.view()) == Ok(Ok(13)) &&
    formula.debug().observations.length() == 1 &&
    source.debug().read_count == reads_before + 1
  escaped.val = None
  ignore(region.close())
  first == Ok(Ok(12)) && rejected && recovered
}

///|
fn structural_transparency() -> Bool {
  let store = @kernel.Store()
  let closed_region = region_or_abort(store)
  let closed_program = @program.Program(closed_region)
  let closed_source = source_or_abort(closed_region, 1)
  let closed_port = port_or_abort(closed_program, closed_source.view())
  let closed_builder = closed_program.builder()
  let closed_read = declared_or_abort(closed_builder, closed_port)
  let closed_formula = formula_or_abort(closed_builder, ctx => ctx.read(closed_read))
  ignore(closed_region.close())
  let closed_result = store.read(closed_formula.view())

  let cycle_region = region_or_abort(store)
  let cycle_program = @program.Program(cycle_region)
  let cycle_ref : Ref[(@kernel.View[Int])?] = Ref(None)
  let cycle_query = match cycle_region.query_always_changed((ctx, _ : Unit) => {
    match cycle_ref.val {
      Some(view) => ctx.read(view)
      None => Ok(0)
    }
  }) {
    Ok(query) => query
    Err(_) => abort("cycle query")
  }
  cycle_ref.val = Some(cycle_query.at(()))
  let cycle_port = port_or_abort(cycle_program, cycle_query.at(()))
  let cycle_builder = cycle_program.builder()
  let cycle_read = declared_or_abort(cycle_builder, cycle_port)
  let cycle_formula = formula_or_abort(cycle_builder, ctx => ctx.read(cycle_read))
  let cycle_result = store.read(cycle_formula.view())
  let passed = closed_result is Err(@kernel.ReadError::ClosedRegion(_)) &&
    cycle_result is Err(@kernel.ReadError::Cycle(_))
  ignore(cycle_region.close())
  passed
}

///|
fn all_workloads() -> Bool {
  initial_two_ports() &&
    same_view_distinct_ports() &&
    dynamic_branch() &&
    duplicate_declaration() &&
    foreign_declared_read() &&
    cross_program_and_lifecycle() &&
    failed_build_consumes_builder() &&
    escaped_eval_ctx_expires() &&
    structural_transparency()
}

///|
test "program read-port workloads" {
  assert_true(all_workloads())
}
