///|
struct BindingCell {
  address : String
  text : String?
  diagnostic : @core.ProjectionDiagnostic?
} derive(Eq, Debug)

///|
struct BindingFixture {
  runtime : @incr.Runtime
  committed : @incr.InputField[Array[BindingCell]]
  drafts : @incr.InputField[Array[BindingCell]]
  diagnostics : @incr.InputField[Array[BindingCell]]
}

///|
fn replace_binding(
  cells : Array[BindingCell],
  address : String,
  text : String?,
) -> Array[BindingCell] {
  cells.map(cell => {
    if cell.address == address {
      { ..cell, text, }
    } else {
      cell
    }
  })
}

///|
fn replace_diagnostic(
  cells : Array[BindingCell],
  address : String,
  diagnostic : @core.ProjectionDiagnostic?,
) -> Array[BindingCell] {
  cells.map(cell => {
    if cell.address == address {
      { ..cell, diagnostic, }
    } else {
      cell
    }
  })
}

///|
fn BindingFixture::new(runtime : @incr.Runtime) -> BindingFixture {
  let blank = [
    BindingCell::{ address: "A1", text: None, diagnostic: None },
    BindingCell::{ address: "B1", text: None, diagnostic: None },
  ]
  {
    runtime,
    committed: @incr.InputField(runtime, blank.copy(), label="committed"),
    drafts: @incr.InputField(runtime, blank.copy(), label="drafts"),
    diagnostics: @incr.InputField(runtime, blank, label="diagnostics"),
  }
}

///|
fn BindingFixture::bindings(self : BindingFixture) -> ProjectionBindings {
  let drafts = self.drafts
  let committed = self.committed
  let diagnostics = self.diagnostics
  ProjectionBindings::ProjectionBindings(
    () => {
      ReadOnlyArray::from_array(
        drafts
        .peek()
        .filter_map(cell => {
          match cell.text {
            Some(text) =>
              Some(@core.DraftObservation::DraftObservation(cell.address, text))
            None => None
          }
        }),
      )
    },
    decision => {
      match decision {
        @core.ProjectionDecision::SetCommitted(address, text) =>
          committed.set(replace_binding(committed.peek(), address, text))
        @core.ProjectionDecision::SetDraft(address, text) =>
          drafts.set(replace_binding(drafts.peek(), address, text))
        @core.ProjectionDecision::SetDiagnostic(address, diagnostic) =>
          diagnostics.set(
            replace_diagnostic(diagnostics.peek(), address, diagnostic),
          )
        _ => ()
      }
    },
  )
}

///|
fn seeds() -> Array[Seed] {
  [
    Seed::Seed("A1", @core.CellRegister::Source("10")),
    Seed::Seed("B1", @core.CellRegister::Source("=A1 + 1")),
  ]
}

///|
fn reset_authority(
  _generation : @domain.DocumentGeneration,
) -> ResetAuthority raise @container.DocumentError {
  let document = @container.Document::new("reset-replica")
  let node = document.create_node(parent=@container.root_id)
  ResetAuthority::ResetAuthority(
    @core.CollaborativeSheetId::CollaborativeSheetId("reset-sheet"),
    document,
    node,
    @typed_spreadsheet.SheetId(9),
  )
}

///|
fn fixture_start(
  replica : String,
  sheet : Int,
) -> (EgwAdapter, BindingFixture) raise @container.DocumentError {
  let fixture = BindingFixture::new(@incr.Runtime())
  let started = try! EgwAdapter::bootstrap(
    fixture.runtime,
    replica,
    @core.CollaborativeSheetId::CollaborativeSheetId("sheet"),
    @typed_spreadsheet.SheetId(sheet),
    seeds(),
    fixture.bindings(),
    reset_authority,
  )
  let adapter = match started {
    AdapterStartResult::Ready(adapter, _) => adapter
    AdapterStartResult::Failed(_) =>
      raise @container.DocumentError::Internal(detail="bootstrap failed")
  }
  (adapter, fixture)
}

///|
fn id(adapter : EgwAdapter, address : String) -> @typed_spreadsheet.CellId {
  @typed_spreadsheet.CellId::of(adapter.sheet_id(), address)
}

///|
fn command(
  adapter : EgwAdapter,
  address : String,
  text : String,
) -> AdapterApplyResult raise @container.DocumentError {
  let target = id(adapter, address)
  let generation = adapter.generation()
  adapter.apply_command(
    @domain.SheetCommand::ApplyFromSelection(target, text, generation),
    @domain.SheetExecutionContext::SheetExecutionContext(
      target,
      None,
      generation,
    ),
  )
}

///|
fn assert_int(
  sheet : @typed_spreadsheet.Worksheet,
  cell : @typed_spreadsheet.CellId,
  value : Int,
) -> Unit raise {
  match sheet.read(cell) {
    @typed_spreadsheet.CellResult::Ok(actual) =>
      assert_eq(actual, @typed_spreadsheet.CellValue::from_int(value))
    _ => fail("unexpected worksheet result")
  }
}

///|
fn install_text(
  sheet : @typed_spreadsheet.Worksheet,
  cell : @typed_spreadsheet.CellId,
  text : String,
) -> Unit raise {
  match @demo.parse_cell_text_op(cell, text) {
    Ok(@demo.SheetOp::SetInput(id, value)) =>
      assert_true(
        sheet.set_input(id, value) is @typed_spreadsheet.CellResult::Ok(_),
      )
    Ok(@demo.SheetOp::SetFormulaAst(id, cell_type, formula)) =>
      assert_true(sheet.set_formula_ast(id, cell_type, formula) is Ok(_))
    Ok(@demo.SheetOp::Delete(id)) =>
      assert_true(sheet.delete(id) is @typed_spreadsheet.CellResult::Ok(_))
    Err(_) => fail("test source must parse")
  }
}

///|
fn assert_semantic_decisions(
  actual : ReadOnlyArray[@core.ProjectionDecision],
  expected : ReadOnlyArray[@core.ProjectionDecision],
) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for i in 0..<actual.length() {
    match (actual[i], expected[i]) {
      (
        @core.ProjectionDecision::ApplyWorksheet(a),
        @core.ProjectionDecision::ApplyWorksheet(e),
      ) =>
        match (a, e) {
          (@demo.SheetOp::SetInput(ai, av), @demo.SheetOp::SetInput(ei, ev)) => {
            assert_eq(ai, ei)
            assert_eq(av, ev)
          }
          (
            @demo.SheetOp::SetFormulaAst(ai, at, af),
            @demo.SheetOp::SetFormulaAst(ei, et, ef),
          ) => {
            assert_eq(ai, ei)
            assert_eq(at, et)
            assert_true(af == ef)
          }
          (@demo.SheetOp::Delete(ai), @demo.SheetOp::Delete(ei)) =>
            assert_eq(ai, ei)
          _ => fail("worksheet decision variants differ")
        }
      (
        @core.ProjectionDecision::SetCommitted(aa, av),
        @core.ProjectionDecision::SetCommitted(ea, ev),
      ) => {
        assert_eq(aa, ea)
        assert_eq(av, ev)
      }
      (
        @core.ProjectionDecision::SetDraft(aa, av),
        @core.ProjectionDecision::SetDraft(ea, ev),
      ) => {
        assert_eq(aa, ea)
        assert_eq(av, ev)
      }
      (
        @core.ProjectionDecision::SetDiagnostic(aa, av),
        @core.ProjectionDecision::SetDiagnostic(ea, ev),
      ) => {
        assert_eq(aa, ea)
        assert_eq(av, ev)
      }
      _ => fail("projection decision variants differ")
    }
  }
}

///|
fn assert_converged(a : EgwAdapter, b : EgwAdapter) -> Unit raise {
  assert_eq(
    a.export_all().to_canonical_bytes(),
    b.export_all().to_canonical_bytes(),
  )
  assert_eq(a.projection_state(), b.projection_state())
  assert_int(a.worksheet, id(a, "A1"), 20)
  assert_int(b.worksheet, id(b, "A1"), 20)
}

///|
fn attach_peer(
  source : EgwAdapter,
  replica : String,
  sheet : Int,
) -> (EgwAdapter, BindingFixture) raise @container.DocumentError {
  let fixture = BindingFixture::new(@incr.Runtime())
  let document = @container.Document::new(replica)
  let message = source.export_all()
  ignore(document.sync().apply(message))
  let node = document.children(@container.root_id)[0]
  let adapter = match
    EgwAdapter::attach(
      fixture.runtime,
      @core.CollaborativeSheetId::CollaborativeSheetId("sheet"),
      @typed_spreadsheet.SheetId(sheet),
      source.generation(),
      document,
      node,
      seeds(),
      fixture.bindings(),
      reset_authority,
    ) {
    AdapterStartResult::Ready(adapter, _) => adapter
    AdapterStartResult::Failed(_) =>
      raise @container.DocumentError::Internal(detail="attach failed")
  }
  (adapter, fixture)
}

///|
test "host export JSON roundtrip attaches the supplied node" {
  let host_fixture = BindingFixture::new(@incr.Runtime())
  let host_document = @container.Document::new("preflight-host")
  let unrelated_host_node = host_document.create_node(parent=@container.root_id)
  let host_node = host_document.create_node(parent=@container.root_id)
  host_document.set_property(
    host_node,
    property_key("A1"),
    @core.encode_register(@core.CellRegister::Source("10")),
  )
  host_document.set_property(
    host_node,
    property_key("B1"),
    @core.encode_register(@core.CellRegister::Source("=A1 + 1")),
  )
  let host = match
    EgwAdapter::attach(
      host_fixture.runtime,
      @core.CollaborativeSheetId::CollaborativeSheetId("sheet"),
      @typed_spreadsheet.SheetId(7),
      @domain.DocumentGeneration::initial(),
      host_document,
      host_node,
      seeds(),
      host_fixture.bindings(),
      reset_authority,
    ) {
    AdapterStartResult::Ready(adapter, _) => adapter
    AdapterStartResult::Failed(_) => fail("host attach failed")
  }
  let wire = host.export_all().to_json_string()
  let message = @container.SyncMessage::from_json_string(wire) catch {
    error => raise error
  }
  let joiner_document = @container.Document::new("preflight-joiner")
  ignore(joiner_document.sync().apply(message))
  assert_true(joiner_document.is_alive(host_node))
  assert_eq(
    joiner_document.get_property(host_node, "cell/A1"),
    host.document.get_property(host.node, "cell/A1"),
  )
  assert_eq(
    joiner_document.get_property(host_node, "cell/B1"),
    host.document.get_property(host.node, "cell/B1"),
  )
  assert_true(joiner_document.version() != @container.Version::empty())
  assert_true(unrelated_host_node != host.node)
  assert_true(joiner_document.children(@container.root_id)[0] != host_node)
  let fixture = BindingFixture::new(@incr.Runtime())
  let attached = match
    EgwAdapter::attach(
      fixture.runtime,
      host.identity(),
      host.sheet_id(),
      host.generation(),
      joiner_document,
      host_node,
      seeds(),
      fixture.bindings(),
      reset_authority,
    ) {
    AdapterStartResult::Ready(adapter, _) => adapter
    AdapterStartResult::Failed(_) => fail("attach failed")
  }
  assert_int(attached.worksheet, id(attached, "A1"), 10)
  assert_int(attached.worksheet, id(attached, "B1"), 11)
}

///|
test "bootstrap writes seeds and projects computed cells" {
  let (adapter, fixture) = fixture_start("bootstrap", 7)
  assert_true(adapter.version() != @container.Version::empty())
  assert_int(adapter.worksheet, id(adapter, "A1"), 10)
  assert_int(adapter.worksheet, id(adapter, "B1"), 11)
  assert_eq(fixture.committed.peek()[1].text, Some("=A1 + 1"))
  assert_eq(fixture.drafts.peek()[1].text, Some("=A1 + 1"))
}

///|
test "rejected stale and foreign commands preserve all state" {
  let (adapter, fixture) = fixture_start("reject", 7)
  let before = adapter.export_all().to_canonical_bytes()
  let before_version = adapter.version()
  let state = adapter.projection_state()
  let committed = fixture.committed.peek()
  let drafts = fixture.drafts.peek()
  let target = id(adapter, "A1")
  let stale = adapter.apply_command(
    @domain.SheetCommand::ApplyFromSelection(
      target,
      "20",
      @domain.DocumentGeneration::initial().next(),
    ),
    @domain.SheetExecutionContext::SheetExecutionContext(
      target,
      None,
      @domain.DocumentGeneration::initial(),
    ),
  )
  assert_true(stale is AdapterApplyResult::Rejected(_))
  let invalid = adapter.apply_command(
    @domain.SheetCommand::ApplyFromSelection(
      target,
      "not a cell",
      adapter.generation(),
    ),
    @domain.SheetExecutionContext::SheetExecutionContext(
      target,
      None,
      adapter.generation(),
    ),
  )
  assert_true(invalid is AdapterApplyResult::SourceRejected(_))
  let foreign_target = @typed_spreadsheet.CellId::of(
    @typed_spreadsheet.SheetId(99),
    "A1",
  )
  let foreign = adapter.apply_command(
    @domain.SheetCommand::ApplyFromSelection(
      foreign_target,
      "20",
      adapter.generation(),
    ),
    @domain.SheetExecutionContext::SheetExecutionContext(
      foreign_target,
      None,
      adapter.generation(),
    ),
  )
  assert_true(foreign is AdapterApplyResult::Rejected(_))
  assert_eq(adapter.version(), before_version)
  assert_eq(adapter.export_all().to_canonical_bytes(), before)
  assert_eq(adapter.projection_state(), state)
  assert_eq(fixture.committed.peek(), committed)
  assert_eq(fixture.drafts.peek(), drafts)
  assert_int(adapter.worksheet, target, 10)
}

///|
test "dead node and mismatched readback retain state" {
  let (adapter, fixture) = fixture_start("faults", 7)
  let before = adapter.projection_state()
  let committed = fixture.committed.peek()
  adapter.document.delete_node(adapter.node)
  assert_true(
    command(adapter, "A1", "20") is AdapterApplyResult::MutationNotLanded,
  )
  assert_eq(adapter.projection_state(), before)
  assert_eq(fixture.committed.peek(), committed)
  assert_int(adapter.worksheet, id(adapter, "A1"), 10)
  let (adapter2, fixture2) = fixture_start("readback", 7)
  let before2 = adapter2.projection_state()
  let committed2 = fixture2.committed.peek()
  adapter2.set_readback_override_for_test(Some("wrong"))
  assert_true(
    command(adapter2, "A1", "20") is AdapterApplyResult::MutationNotLanded,
  )
  assert_eq(adapter2.projection_state(), before2)
  assert_eq(fixture2.committed.peek(), committed2)
  assert_int(adapter2.worksheet, id(adapter2, "A1"), 10)
}

///|
test "identical local write is no semantic change after authority readback" {
  let (adapter, _) = fixture_start("noop", 7)
  match command(adapter, "A1", "10") {
    AdapterApplyResult::NoSemanticChange(report) =>
      assert_eq(report.decisions(), 0)
    _ => fail("expected no semantic change")
  }
}

///|
test "failed prepared frame rolls back bindings and retries" {
  let (adapter, fixture) = fixture_start("rollback", 7)
  let before = adapter.projection_state()
  let committed_before = fixture.committed.peek()
  let a = id(adapter, "A1")
  let b = id(adapter, "B1")
  assert_true(
    adapter.worksheet.delete(b) is @typed_spreadsheet.CellResult::Ok(_),
  )
  adapter.document.set_property(
    adapter.node,
    "cell/A1",
    @core.encode_register(@core.CellRegister::Deleted),
  )
  adapter.document.set_property(
    adapter.node,
    "cell/B1",
    @core.encode_register(@core.CellRegister::Deleted),
  )
  let message = adapter.export_all()
  match adapter.apply_sync(message).adapter_result() {
    AdapterApplyResult::ProjectionFailed(
      ProjectionApplyError::UnexpectedDelete(failed, _)
    ) => assert_eq(failed, b)
    _ => fail("unexpected rollback result")
  }
  assert_eq(adapter.projection_state(), before)
  assert_eq(fixture.committed.peek(), committed_before)
  assert_int(adapter.worksheet, a, 10)
  install_text(adapter.worksheet, b, "=A1 + 1")
  match adapter.apply_sync(message).adapter_result() {
    AdapterApplyResult::Applied(_) => ()
    _ => fail("retry failed")
  }
  assert_true(!adapter.worksheet.inspect_cell(a).present)
  assert_true(!adapter.worksheet.inspect_cell(b).present)
}

///|
test "reset uses fresh authority and rejects stale command" {
  let calls = Ref(0)
  let factory = (generation : @domain.DocumentGeneration) => {
    calls.val += 1
    reset_authority(generation)
  }
  let fixture = BindingFixture::new(@incr.Runtime())
  let adapter = match
    EgwAdapter::bootstrap(
      fixture.runtime,
      "reset",
      @core.CollaborativeSheetId::CollaborativeSheetId("sheet"),
      @typed_spreadsheet.SheetId(7),
      seeds(),
      fixture.bindings(),
      factory,
    ) {
    AdapterStartResult::Ready(adapter, _) => adapter
    AdapterStartResult::Failed(_) => fail("bootstrap failed")
  }
  let old_generation = adapter.generation()
  let old_node = adapter.node
  let old_worksheet = adapter.worksheet
  let stale_reset = adapter.apply_command(
    @domain.SheetCommand::ResetDocument(old_generation.next()),
    @domain.SheetExecutionContext::SheetExecutionContext(
      id(adapter, "A1"),
      None,
      old_generation,
    ),
  )
  assert_true(stale_reset is AdapterApplyResult::Rejected(_))
  assert_eq(calls.val, 0)
  match
    adapter.apply_command(
      @domain.SheetCommand::ResetDocument(old_generation),
      @domain.SheetExecutionContext::SheetExecutionContext(
        id(adapter, "A1"),
        None,
        old_generation,
      ),
    ) {
    AdapterApplyResult::Applied(_) | AdapterApplyResult::NoSemanticChange(_) =>
      ()
    _ => fail("reset failed")
  }
  assert_eq(calls.val, 1)
  assert_true(old_worksheet.is_disposed())
  assert_eq(adapter.generation(), old_generation.next())
  assert_true(adapter.node != old_node)
  assert_eq(adapter.sheet_id(), @typed_spreadsheet.SheetId(9))
  assert_int(adapter.worksheet, id(adapter, "A1"), 10)
  let stale = adapter.apply_command(
    @domain.SheetCommand::ApplyFromSelection(
      id(adapter, "A1"),
      "20",
      old_generation,
    ),
    @domain.SheetExecutionContext::SheetExecutionContext(
      id(adapter, "A1"),
      None,
      old_generation,
    ),
  )
  assert_true(
    stale
    is AdapterApplyResult::Rejected(
      @domain.CommandApplicability::StaleGeneration
    ),
  )
}

///|
test "dead replacement leaves current authority unchanged" {
  let dead_factory = (_ : @domain.DocumentGeneration) => {
    let document = @container.Document::new("dead")
    let node = document.create_node(parent=@container.root_id)
    document.delete_node(node)
    ResetAuthority::ResetAuthority(
      @core.CollaborativeSheetId::CollaborativeSheetId("dead"),
      document,
      node,
      @typed_spreadsheet.SheetId(10),
    )
  }
  let fixture = BindingFixture::new(@incr.Runtime())
  let started = try! EgwAdapter::bootstrap(
    fixture.runtime,
    "reset-dead",
    @core.CollaborativeSheetId::CollaborativeSheetId("sheet"),
    @typed_spreadsheet.SheetId(7),
    seeds(),
    fixture.bindings(),
    dead_factory,
  )
  let adapter = match started {
    AdapterStartResult::Ready(adapter, _) => adapter
    AdapterStartResult::Failed(_) => fail("bootstrap failed")
  }
  let before = adapter.export_all().to_canonical_bytes()
  let before_generation = adapter.generation()
  let before_identity = adapter.identity().value()
  let before_state = adapter.projection_state()
  let before_sheet_id = adapter.sheet_id()
  let before_worksheet = adapter.worksheet
  assert_true(
    adapter.apply_command(
      @domain.SheetCommand::ResetDocument(before_generation),
      @domain.SheetExecutionContext::SheetExecutionContext(
        id(adapter, "A1"),
        None,
        before_generation,
      ),
    )
    is AdapterApplyResult::MutationNotLanded,
  )
  assert_eq(adapter.generation(), before_generation)
  assert_eq(adapter.identity().value(), before_identity)
  assert_eq(adapter.projection_state(), before_state)
  assert_eq(adapter.sheet_id(), before_sheet_id)
  assert_true(!before_worksheet.is_disposed())
  assert_eq(adapter.export_all().to_canonical_bytes(), before)
}

///|
test "local and remote equivalent authority changes have equal results" {
  let (a, fa) = fixture_start("local", 7)
  let (b, fb) = attach_peer(a, "remote", 7)
  let baseline = a.version()
  let prior = a.state
  let remote_prior = b.state
  let local_drafts = (a.bindings.drafts)()
  let remote_drafts = (b.bindings.drafts)()
  let local_result = command(a, "A1", "20")
  let local_decisions = @core.compute_projection_transition(
    prior,
    snapshot(a),
    a.sheet_id,
    local_drafts,
  ).decisions()
  let message = a.export_since(baseline)
  let remote = b.apply_sync(message).adapter_result()
  let remote_decisions = @core.compute_projection_transition(
    remote_prior,
    snapshot(b),
    b.sheet_id,
    remote_drafts,
  ).decisions()
  assert_semantic_decisions(local_decisions, remote_decisions)
  assert_true(local_result is AdapterApplyResult::Applied(_))
  assert_true(remote is AdapterApplyResult::Applied(_))
  assert_eq(a.projection_state(), b.projection_state())
  assert_eq(fa.committed.peek(), fb.committed.peek())
  assert_eq(fa.drafts.peek(), fb.drafts.peek())
  assert_int(a.worksheet, id(a, "A1"), 20)
  assert_int(b.worksheet, id(b, "A1"), 20)
}

///|
test "concurrent valid writes converge" {
  let (a, fa) = fixture_start("concurrent-a", 7)
  let (b, fb) = attach_peer(a, "concurrent-b", 7)
  let av = a.version()
  let bv = b.version()
  ignore(command(a, "A1", "20"))
  ignore(command(b, "A1", "30"))
  ignore(b.apply_sync(a.export_since(av)))
  ignore(a.apply_sync(b.export_since(bv)))
  ignore(b.apply_sync(a.export_all()))
  ignore(a.apply_sync(b.export_all()))
  assert_eq(
    a.export_all().to_canonical_bytes(),
    b.export_all().to_canonical_bytes(),
  )
  assert_eq(a.projection_state(), b.projection_state())
  assert_eq(fa.committed.peek(), fb.committed.peek())
  assert_eq(fa.diagnostics.peek(), fb.diagnostics.peek())
  assert_eq(a.worksheet.read(id(a, "A1")), b.worksheet.read(id(b, "A1")))
}

///|
test "apply delete race converges presence" {
  let (a, fa) = fixture_start("race-a", 7)
  let (b, fb) = attach_peer(a, "race-b", 7)
  let av = a.version()
  let bv = b.version()
  ignore(command(a, "A1", "20"))
  let target = id(b, "A1")
  ignore(
    b.apply_command(
      @domain.SheetCommand::DeleteFromSelection(target, b.generation()),
      @domain.SheetExecutionContext::SheetExecutionContext(
        target,
        None,
        b.generation(),
      ),
    ),
  )
  ignore(b.apply_sync(a.export_since(av)))
  ignore(a.apply_sync(b.export_since(bv)))
  ignore(a.apply_sync(b.export_all()))
  ignore(b.apply_sync(a.export_all()))
  assert_eq(
    a.export_all().to_canonical_bytes(),
    b.export_all().to_canonical_bytes(),
  )
  assert_eq(a.projection_state(), b.projection_state())
  assert_eq(fa.committed.peek(), fb.committed.peek())
  assert_eq(fa.diagnostics.peek(), fb.diagnostics.peek())
  assert_eq(
    a.worksheet.inspect_cell(id(a, "A1")).present,
    b.worksheet.inspect_cell(id(b, "A1")).present,
  )
}

///|
test "duplicate and pending out of order delivery is deterministic" {
  let (a, _) = fixture_start("order-a", 7)
  let create = a.export_all()
  let after_create = a.version()
  ignore(command(a, "A1", "20"))
  let property = a.export_since(after_create)
  let probe = @container.Document::new("order-b")
  let pending = probe.sync().apply(property)
  assert_true(pending.pending_operations() > 0)
  let resolved_report = probe.sync().apply(create)
  assert_true(resolved_report.pending_operations() == 0)
  let duplicate_report = probe.sync().apply(create)
  assert_true(duplicate_report.duplicate_operations() > 0)
  let fixture = BindingFixture::new(@incr.Runtime())
  let node = probe.children(@container.root_id)[0]
  let b = match
    EgwAdapter::attach(
      fixture.runtime,
      @core.CollaborativeSheetId::CollaborativeSheetId("sheet"),
      @typed_spreadsheet.SheetId(7),
      a.generation(),
      probe,
      node,
      seeds(),
      fixture.bindings(),
      reset_authority,
    ) {
    AdapterStartResult::Ready(adapter, _) => adapter
    AdapterStartResult::Failed(_) => fail("attach failed")
  }
  assert_eq(a.projection_state(), b.projection_state())
  assert_int(b.worksheet, id(b, "A1"), 20)
  let duplicate = b.apply_sync(create)
  assert_true(duplicate.sync_report().duplicate_operations() > 0)
  assert_true(
    duplicate.adapter_result() is AdapterApplyResult::NoSemanticChange(_),
  )
  assert_eq(a.projection_state(), b.projection_state())
}

///|
test "clean draft follows remote while dirty draft remains local" {
  let (a, fa) = fixture_start("draft-a", 7)
  let (b, fb) = attach_peer(a, "draft-b", 7)
  let first_version = a.version()
  ignore(command(a, "A1", "20"))
  ignore(b.apply_sync(a.export_since(first_version)))
  assert_eq(fb.committed.peek()[0].text, Some("20"))
  assert_eq(fb.drafts.peek()[0].text, Some("20"))
  fb.drafts.set(replace_binding(fb.drafts.peek(), "A1", Some("local")))
  let second_version = a.version()
  ignore(command(a, "A1", "30"))
  ignore(b.apply_sync(a.export_since(second_version)))
  assert_eq(fa.committed.peek()[0].text, Some("30"))
  assert_eq(fb.committed.peek()[0].text, Some("30"))
  assert_eq(fb.drafts.peek()[0].text, Some("local"))
}

///|
test "malformed and unknown remote payloads retain distinct last good values" {
  let (a, fa) = fixture_start("bad-a", 7)
  let (b, fb) = attach_peer(a, "bad-z", 7)
  let av = a.version()
  let bv = b.version()
  ignore(command(a, "A1", "20"))
  b.document.set_property(b.node, "cell/A1", "{")
  let malformed = b.export_since(bv)
  ignore(b.apply_sync(malformed))
  ignore(a.apply_sync(malformed))
  ignore(b.apply_sync(a.export_since(av)))
  let a_diagnostic = a.projection_state().cell("A1").unwrap().diagnostic()
  let b_diagnostic = b.projection_state().cell("A1").unwrap().diagnostic()
  assert_true(a_diagnostic is Some(_))
  assert_eq(a_diagnostic, b_diagnostic)
  assert_eq(fa.diagnostics.peek(), fb.diagnostics.peek())
  assert_int(a.worksheet, id(a, "A1"), 20)
  assert_int(b.worksheet, id(b, "A1"), 10)
  let before_unknown = b.version()
  b.document.set_property(b.node, "cell/A1", "{\"v\":2,\"kind\":\"deleted\"}")
  let unknown = b.export_since(before_unknown)
  ignore(b.apply_sync(unknown))
  ignore(a.apply_sync(unknown))
  let next_a = a.projection_state().cell("A1").unwrap().diagnostic()
  let next_b = b.projection_state().cell("A1").unwrap().diagnostic()
  assert_true(
    next_a is Some(@core.ProjectionDiagnostic::UnsupportedNumericVersion(_, _)),
  )
  assert_eq(next_a, next_b)
  assert_int(a.worksheet, id(a, "A1"), 20)
  assert_int(b.worksheet, id(b, "A1"), 10)
}

///|
test "valid replacement clears malformed diagnostics and reconverges" {
  let (a, fa) = fixture_start("recover-a", 7)
  let (b, fb) = attach_peer(a, "recover-b", 7)
  let version = a.version()
  a.document.set_property(a.node, "cell/A1", "{")
  ignore(b.apply_sync(a.export_since(version)))
  let version2 = a.version()
  a.document.set_property(
    a.node,
    "cell/A1",
    @core.encode_register(@core.CellRegister::Source("20")),
  )
  ignore(b.apply_sync(a.export_since(version2)))
  ignore(a.apply_sync(b.export_all()))
  assert_eq(a.projection_state(), b.projection_state())
  assert_eq(a.projection_state().cell("A1").unwrap().diagnostic(), None)
  assert_eq(fa.committed.peek(), fb.committed.peek())
  assert_eq(fa.diagnostics.peek(), fb.diagnostics.peek())
  assert_int(a.worksheet, id(a, "A1"), 20)
  assert_int(b.worksheet, id(b, "A1"), 20)
  assert_eq(
    a.export_all().to_canonical_bytes(),
    b.export_all().to_canonical_bytes(),
  )
}

///|
test "convergence helper checks EGW state projection state and worksheet separately" {
  let (a, _) = fixture_start("converge-a", 7)
  let (b, _) = attach_peer(a, "converge-b", 7)
  ignore(command(a, "A1", "20"))
  ignore(b.apply_sync(a.export_all()))
  assert_converged(a, b)
}
