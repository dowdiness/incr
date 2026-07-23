///|
/// Benchmark-only hint model. `ChangedProperties` is a synthetic lower bound;
/// EGW 0.4 does not supply changed-property addresses.
enum EgwBenchProjectionHint {
  FullScan
  ChangedProperties(Array[String])
}

///|
struct EgwBenchSnapshot {
  snapshot : @core.RawRegisterSnapshot
  get_property_reads : Int
}

///|
fn egw_bench_seeds() -> Array[Seed] {
  [
    Seed::Seed("A1", @core.CellRegister::Source("10")),
    Seed::Seed("B1", @core.CellRegister::Source("=A1 + 1")),
  ]
}

///|
fn egw_bench_reset_authority(
  _generation : @domain.DocumentGeneration,
) -> ResetAuthority raise @container.DocumentError {
  let document = @container.Document::new("egw-bench-reset")
  let node = document.create_node(parent=@container.root_id)
  ResetAuthority::ResetAuthority(
    @core.CollaborativeSheetId::CollaborativeSheetId("egw-bench-reset"),
    document,
    node,
    @typed_spreadsheet.SheetId(1001),
  )
}

///|
fn egw_bench_adapter() -> EgwAdapter raise @container.DocumentError {
  let runtime = @incr.Runtime()
  let bindings = ProjectionBindings::ProjectionBindings(
    () => ReadOnlyArray::from_array([]),
    _ => (),
  )
  match
    EgwAdapter::bootstrap(
      runtime,
      "egw-bench",
      @core.CollaborativeSheetId::CollaborativeSheetId("egw-bench"),
      @typed_spreadsheet.SheetId(1000),
      egw_bench_seeds(),
      bindings,
      egw_bench_reset_authority,
    ) {
    AdapterStartResult::Ready(adapter, _) => adapter
    AdapterStartResult::Failed(_) =>
      raise @container.DocumentError::Internal(detail="bench bootstrap failed")
  }
}

///|
fn egw_bench_addresses(count : Int) -> Array[String] {
  @domain.grid_cells()[0:count].to_owned()
}

///|
fn egw_bench_snapshot(
  adapter : EgwAdapter,
  hint : EgwBenchProjectionHint,
) -> EgwBenchSnapshot {
  match hint {
    FullScan =>
      {
        snapshot: snapshot_addresses(adapter, adapter.addresses[:]),
        get_property_reads: adapter.addresses.length(),
      }
    ChangedProperties(addresses) =>
      {
        snapshot: snapshot_addresses(adapter, addresses[:]),
        get_property_reads: addresses.length(),
      }
  }
}

///|
fn egw_bench_set_registers(
  adapter : EgwAdapter,
  addresses : ArrayView[String],
  text : String,
) -> Unit {
  let payload = @core.encode_register(@core.CellRegister::Source(text))
  for address in addresses {
    adapter.document.set_property(adapter.node, property_key(address), payload)
  }
}

///|
fn egw_bench_transition(
  adapter : EgwAdapter,
  hint : EgwBenchProjectionHint,
) -> @core.ProjectionTransition {
  let observed = egw_bench_snapshot(adapter, hint)
  @core.compute_projection_transition(
    adapter.state,
    observed.snapshot,
    adapter.sheet_id,
    ReadOnlyArray::from_array([]),
  )
}

///|
fn egw_bench_apply_prepared(
  adapter : EgwAdapter,
  decisions : ReadOnlyArray[@core.ProjectionDecision],
) -> Unit {
  try! adapter.runtime.batch(() => {
    for decision in decisions {
      apply_decision(adapter, decision)
    }
  })
}

///|
/// Applies the synthetic changed-property frame but intentionally does not
/// retain its partial candidate state. This is a lower bound, not a production
/// projection path.
fn egw_bench_project_changed_lower_bound(
  adapter : EgwAdapter,
  addresses : Array[String],
) -> Int {
  let transition = egw_bench_transition(adapter, ChangedProperties(addresses))
  egw_bench_apply_prepared(adapter, transition.decisions())
  transition.decisions().length()
}

///|
fn egw_bench_scan(
  b : @bench.T,
  count : Int,
  hint : EgwBenchProjectionHint,
) -> Unit raise @container.DocumentError {
  let adapter = egw_bench_adapter()
  let addresses = egw_bench_addresses(count)
  egw_bench_set_registers(adapter, addresses, "20")
  b.bench(() => b.keep(egw_bench_snapshot(adapter, hint)))
  adapter.worksheet.dispose()
}

///|
fn egw_bench_decode(b : @bench.T, count : Int) -> Unit {
  let entries = egw_bench_addresses(count).mapi((index, address) => {
    (address, @core.encode_register(@core.CellRegister::Source("\{index}")))
  })
  b.bench(() => {
    for entry in entries {
      let (address, payload) = entry
      b.keep(@core.decode_register(address, Some(payload)))
    }
  })
}

///|
fn egw_bench_decode_diff(
  b : @bench.T,
  count : Int,
  hint : EgwBenchProjectionHint,
) -> Unit raise @container.DocumentError {
  let adapter = egw_bench_adapter()
  let addresses = egw_bench_addresses(count)
  egw_bench_set_registers(adapter, addresses, "20")
  let observed = egw_bench_snapshot(adapter, hint)
  b.bench(() => {
    b.keep(
      @core.compute_projection_transition(
        adapter.state,
        observed.snapshot,
        adapter.sheet_id,
        ReadOnlyArray::from_array([]),
      ),
    )
  })
  adapter.worksheet.dispose()
}

///|
fn egw_bench_projection(
  b : @bench.T,
  count : Int,
) -> Unit raise @container.DocumentError {
  let adapter = egw_bench_adapter()
  let addresses = egw_bench_addresses(count)
  egw_bench_set_registers(adapter, addresses, "20")
  let first = egw_bench_transition(adapter, FullScan).decisions()
  egw_bench_set_registers(adapter, addresses, "21")
  let second = egw_bench_transition(adapter, FullScan).decisions()
  egw_bench_apply_prepared(adapter, first)
  let mut use_first = false
  b.bench(() => {
    let decisions = if use_first { first } else { second }
    use_first = !use_first
    egw_bench_apply_prepared(adapter, decisions)
    b.keep(decisions.length())
  })
  adapter.worksheet.dispose()
}

///|
fn egw_bench_end_to_end_full_scan(
  b : @bench.T,
  count : Int,
) -> Unit raise @container.DocumentError {
  let adapter = egw_bench_adapter()
  let addresses = egw_bench_addresses(count)
  egw_bench_set_registers(adapter, addresses, "19")
  ignore(project_authority_with_drafts(adapter, ReadOnlyArray::from_array([])))
  let mut value = 20
  b.bench(() => {
    value = if value == 20 { 21 } else { 20 }
    egw_bench_set_registers(adapter, addresses, "\{value}")
    b.keep(
      project_authority_with_drafts(adapter, ReadOnlyArray::from_array([])),
    )
  })
  adapter.worksheet.dispose()
}

///|
fn egw_bench_end_to_end_changed_properties(
  b : @bench.T,
  count : Int,
) -> Unit raise @container.DocumentError {
  let adapter = egw_bench_adapter()
  let addresses = egw_bench_addresses(count)
  egw_bench_set_registers(adapter, addresses, "19")
  ignore(egw_bench_project_changed_lower_bound(adapter, addresses))
  let mut value = 20
  b.bench(() => {
    value = if value == 20 { 21 } else { 20 }
    egw_bench_set_registers(adapter, addresses, "\{value}")
    b.keep(egw_bench_project_changed_lower_bound(adapter, addresses))
  })
  adapter.worksheet.dispose()
}

///|
test "egw bench seam: read counts and decisions agree" {
  let adapter = try! egw_bench_adapter()
  let addresses = egw_bench_addresses(10)
  egw_bench_set_registers(adapter, addresses, "20")
  let full = egw_bench_snapshot(adapter, FullScan)
  let changed = egw_bench_snapshot(adapter, ChangedProperties(addresses))
  assert_eq(full.get_property_reads, 2500)
  assert_eq(changed.get_property_reads, 10)
  let full_transition = @core.compute_projection_transition(
    adapter.state,
    full.snapshot,
    adapter.sheet_id,
    ReadOnlyArray::from_array([]),
  )
  let changed_transition = @core.compute_projection_transition(
    adapter.state,
    changed.snapshot,
    adapter.sheet_id,
    ReadOnlyArray::from_array([]),
  )
  assert_semantic_decisions(
    full_transition.decisions(),
    changed_transition.decisions(),
  )
  assert_eq(changed_transition.candidate_state().cells().length(), 10)
  adapter.worksheet.dispose()
}

///|
test "egw scan full_scan changed=1" (b : @bench.T) {
  try! egw_bench_scan(b, 1, FullScan)
}

///|
test "egw scan full_scan changed=10" (b : @bench.T) {
  try! egw_bench_scan(b, 10, FullScan)
}

///|
test "egw scan full_scan changed=100" (b : @bench.T) {
  try! egw_bench_scan(b, 100, FullScan)
}

///|
test "egw scan full_scan changed=2500" (b : @bench.T) {
  try! egw_bench_scan(b, 2500, FullScan)
}

///|
test "egw scan changed_properties changed=1" (b : @bench.T) {
  try! egw_bench_scan(b, 1, ChangedProperties(egw_bench_addresses(1)))
}

///|
test "egw scan changed_properties changed=10" (b : @bench.T) {
  try! egw_bench_scan(b, 10, ChangedProperties(egw_bench_addresses(10)))
}

///|
test "egw scan changed_properties changed=100" (b : @bench.T) {
  try! egw_bench_scan(b, 100, ChangedProperties(egw_bench_addresses(100)))
}

///|
test "egw scan changed_properties changed=2500" (b : @bench.T) {
  try! egw_bench_scan(b, 2500, ChangedProperties(egw_bench_addresses(2500)))
}

///|
test "egw decode changed=1" (b : @bench.T) {
  egw_bench_decode(b, 1)
}

///|
test "egw decode changed=10" (b : @bench.T) {
  egw_bench_decode(b, 10)
}

///|
test "egw decode changed=100" (b : @bench.T) {
  egw_bench_decode(b, 100)
}

///|
test "egw decode changed=2500" (b : @bench.T) {
  egw_bench_decode(b, 2500)
}

///|
test "egw decode_diff full_scan changed=1" (b : @bench.T) {
  try! egw_bench_decode_diff(b, 1, FullScan)
}

///|
test "egw decode_diff full_scan changed=10" (b : @bench.T) {
  try! egw_bench_decode_diff(b, 10, FullScan)
}

///|
test "egw decode_diff full_scan changed=100" (b : @bench.T) {
  try! egw_bench_decode_diff(b, 100, FullScan)
}

///|
test "egw decode_diff full_scan changed=2500" (b : @bench.T) {
  try! egw_bench_decode_diff(b, 2500, FullScan)
}

///|
test "egw decode_diff changed_properties changed=1" (b : @bench.T) {
  try! egw_bench_decode_diff(b, 1, ChangedProperties(egw_bench_addresses(1)))
}

///|
test "egw decode_diff changed_properties changed=10" (b : @bench.T) {
  try! egw_bench_decode_diff(b, 10, ChangedProperties(egw_bench_addresses(10)))
}

///|
test "egw decode_diff changed_properties changed=100" (b : @bench.T) {
  try! egw_bench_decode_diff(
    b,
    100,
    ChangedProperties(egw_bench_addresses(100)),
  )
}

///|
test "egw decode_diff changed_properties changed=2500" (b : @bench.T) {
  try! egw_bench_decode_diff(
    b,
    2500,
    ChangedProperties(egw_bench_addresses(2500)),
  )
}

///|
test "egw projection prepared changed=1" (b : @bench.T) {
  try! egw_bench_projection(b, 1)
}

///|
test "egw projection prepared changed=10" (b : @bench.T) {
  try! egw_bench_projection(b, 10)
}

///|
test "egw projection prepared changed=100" (b : @bench.T) {
  try! egw_bench_projection(b, 100)
}

///|
test "egw projection prepared changed=2500" (b : @bench.T) {
  try! egw_bench_projection(b, 2500)
}

///|
test "egw end_to_end full_scan changed=1" (b : @bench.T) {
  try! egw_bench_end_to_end_full_scan(b, 1)
}

///|
test "egw end_to_end full_scan changed=10" (b : @bench.T) {
  try! egw_bench_end_to_end_full_scan(b, 10)
}

///|
test "egw end_to_end full_scan changed=100" (b : @bench.T) {
  try! egw_bench_end_to_end_full_scan(b, 100)
}

///|
test "egw end_to_end full_scan changed=2500" (b : @bench.T) {
  try! egw_bench_end_to_end_full_scan(b, 2500)
}

///|
test "egw end_to_end changed_properties changed=1" (b : @bench.T) {
  try! egw_bench_end_to_end_changed_properties(b, 1)
}

///|
test "egw end_to_end changed_properties changed=10" (b : @bench.T) {
  try! egw_bench_end_to_end_changed_properties(b, 10)
}

///|
test "egw end_to_end changed_properties changed=100" (b : @bench.T) {
  try! egw_bench_end_to_end_changed_properties(b, 100)
}

///|
test "egw end_to_end changed_properties changed=2500" (b : @bench.T) {
  try! egw_bench_end_to_end_changed_properties(b, 2500)
}
