///|
fn wb_raw(address : String, register : CellRegister?) -> RawRegisterEntry {
  RawRegisterEntry::RawRegisterEntry(address, register.map(encode_register))
}

///|
fn wb_assert_sheet_op(
  actual : @demo.SheetOp,
  expected : @demo.SheetOp,
) -> Unit raise {
  match (actual, expected) {
    (@demo.SheetOp::SetInput(a, av), @demo.SheetOp::SetInput(e, ev)) => {
      assert_eq(a, e)
      assert_eq(av, ev)
    }
    (
      @demo.SheetOp::SetFormulaAst(a, at, af),
      @demo.SheetOp::SetFormulaAst(e, et, ef),
    ) => {
      assert_eq(a, e)
      assert_eq(at, et)
      assert_true(af == ef)
    }
    (@demo.SheetOp::Delete(a), @demo.SheetOp::Delete(e)) => assert_eq(a, e)
    _ => fail("SheetOp variants differ")
  }
}

///|
fn wb_assert_decisions(
  actual : ReadOnlyArray[ProjectionDecision],
  expected : ReadOnlyArray[ProjectionDecision],
) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for i in 0..<expected.length() {
    match (actual[i], expected[i]) {
      (
        ProjectionDecision::ApplyWorksheet(a),
        ProjectionDecision::ApplyWorksheet(e),
      ) => wb_assert_sheet_op(a, e)
      (
        ProjectionDecision::SetCommitted(aa, av),
        ProjectionDecision::SetCommitted(ea, ev),
      ) => {
        assert_eq(aa, ea)
        assert_eq(av, ev)
      }
      (
        ProjectionDecision::SetDraft(aa, av),
        ProjectionDecision::SetDraft(ea, ev),
      ) => {
        assert_eq(aa, ea)
        assert_eq(av, ev)
      }
      (
        ProjectionDecision::SetDiagnostic(aa, av),
        ProjectionDecision::SetDiagnostic(ea, ev),
      ) => {
        assert_eq(aa, ea)
        assert_eq(av, ev)
      }
      _ => fail("ProjectionDecision variants differ")
    }
  }
}

///|
test "projection canonical order and initial decisions" {
  let sheet = @typed_spreadsheet.SheetId::SheetId(1)
  let snapshot = RawRegisterSnapshot::RawRegisterSnapshot(["B1", "A1", "B1"], [
    wb_raw("X1", Some(CellRegister::Source("99"))),
    wb_raw("A1", Some(CellRegister::Source("10"))),
    wb_raw("A1", Some(CellRegister::Source("20"))),
    wb_raw("B1", Some(CellRegister::Source("=A1"))),
  ])
  let result = compute_projection_transition(
    ProjectionState::empty(["A1", "B1"]),
    snapshot,
    sheet,
    [],
  )
  assert_eq(result.candidate_state().cells().map(c => c.address()), ["B1", "A1"])
  wb_assert_decisions(result.decisions(), [
    ProjectionDecision::ApplyWorksheet(
      @demo.SheetOp::SetFormulaAst(
        @typed_spreadsheet.CellId::of(sheet, "B1"),
        @typed_spreadsheet.CellType::t_int(),
        @typed_spreadsheet.Formula::cell_ref(
          @typed_spreadsheet.CellId::of(sheet, "A1"),
        ),
      ),
    ),
    ProjectionDecision::SetCommitted("B1", Some("=A1")),
    ProjectionDecision::SetDraft("B1", Some("=A1")),
    ProjectionDecision::ApplyWorksheet(
      @demo.SheetOp::SetInput(
        @typed_spreadsheet.CellId::of(sheet, "A1"),
        @typed_spreadsheet.CellValue::from_int(10),
      ),
    ),
    ProjectionDecision::SetCommitted("A1", Some("10")),
    ProjectionDecision::SetDraft("A1", Some("10")),
  ])
}

///|
test "projection initial deleted is semantically absent" {
  let result = compute_projection_transition(
    ProjectionState::empty(["A1"]),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      wb_raw("A1", Some(CellRegister::Deleted)),
    ]),
    @typed_spreadsheet.SheetId::SheetId(2),
    [],
  )
  assert_eq(result.decisions().length(), 0)
  let cell = result.candidate_state().cell("A1").unwrap()
  assert_eq(
    cell.last_seen_register(),
    RegisterObservation::Decoded(CellRegister::Deleted),
  )
  assert_eq(cell.last_good_source(), None)
  assert_eq(cell.diagnostic(), None)
}

///|
test "projection valid source repeated unchanged preserves state" {
  let sheet = @typed_spreadsheet.SheetId::SheetId(2)
  let snapshot = RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
    wb_raw("A1", Some(CellRegister::Source("10"))),
  ])
  let first = compute_projection_transition(
    ProjectionState::empty(["A1"]),
    snapshot,
    sheet,
    [],
  )
  let second = compute_projection_transition(
    first.candidate_state(),
    snapshot,
    sheet,
    [],
  )
  assert_eq(second.decisions().length(), 0)
  assert_eq(second.candidate_state(), first.candidate_state())
}

///|
test "projection source to unset deletes and clears clean draft" {
  let sheet = @typed_spreadsheet.SheetId::SheetId(2)
  let source = compute_projection_transition(
    ProjectionState::empty(["A1"]),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      wb_raw("A1", Some(CellRegister::Source("10"))),
    ]),
    sheet,
    [],
  )
  let unset = compute_projection_transition(
    source.candidate_state(),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [wb_raw("A1", None)]),
    sheet,
    [DraftObservation::DraftObservation("A1", "10")],
  )
  wb_assert_decisions(unset.decisions(), [
    ProjectionDecision::ApplyWorksheet(
      @demo.SheetOp::Delete(@typed_spreadsheet.CellId::of(sheet, "A1")),
    ),
    ProjectionDecision::SetCommitted("A1", None),
    ProjectionDecision::SetDraft("A1", None),
  ])
}

///|
test "projection absence deletes only an existing semantic cell" {
  let sheet = @typed_spreadsheet.SheetId::SheetId(2)
  let initial = compute_projection_transition(
    ProjectionState::empty(["A1"]),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      wb_raw("A1", Some(CellRegister::Source("10"))),
    ]),
    sheet,
    [],
  )
  let deleted = compute_projection_transition(
    initial.candidate_state(),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      wb_raw("A1", Some(CellRegister::Deleted)),
    ]),
    sheet,
    [],
  )
  wb_assert_decisions(deleted.decisions(), [
    ProjectionDecision::ApplyWorksheet(
      @demo.SheetOp::Delete(@typed_spreadsheet.CellId::of(sheet, "A1")),
    ),
    ProjectionDecision::SetCommitted("A1", None),
    ProjectionDecision::SetDraft("A1", None),
  ])
  let absent = compute_projection_transition(
    ProjectionState::empty(["A1"]),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [wb_raw("A1", None)]),
    sheet,
    [],
  )
  assert_eq(absent.decisions().length(), 0)
}

///|
test "projection malformed state separates observation good and diagnostic" {
  let sheet = @typed_spreadsheet.SheetId::SheetId(3)
  let good = compute_projection_transition(
    ProjectionState::empty(["A1"]),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      wb_raw("A1", Some(CellRegister::Source("10"))),
    ]),
    sheet,
    [],
  )
  let empty_source = compute_projection_transition(
    good.candidate_state(),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      wb_raw("A1", Some(CellRegister::Source(""))),
    ]),
    sheet,
    [],
  )
  assert_eq(empty_source.decisions().length(), 1)
  match empty_source.decisions()[0] {
    ProjectionDecision::SetDiagnostic(
      "A1",
      Some(
        ProjectionDiagnostic::InvalidSource(
          "A1",
          "",
          @demo.FormulaTextParseError::EmptyInput
        )
      )
    ) => ()
    _ => fail("empty source should only diagnose")
  }
  let invalid = compute_projection_transition(
    good.candidate_state(),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      wb_raw("A1", Some(CellRegister::Source("nope"))),
    ]),
    sheet,
    [],
  )
  assert_eq(
    invalid.candidate_state().cell("A1").unwrap().last_good_source(),
    Some("10"),
  )
  assert_eq(invalid.decisions().length(), 1)
  let again = compute_projection_transition(
    invalid.candidate_state(),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      wb_raw("A1", Some(CellRegister::Source("nope"))),
    ]),
    sheet,
    [],
  )
  assert_eq(again.decisions().length(), 0)
  let malformed = compute_projection_transition(
    invalid.candidate_state(),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      RawRegisterEntry::RawRegisterEntry("A1", Some("{")),
    ]),
    sheet,
    [],
  )
  assert_eq(
    malformed.candidate_state().cell("A1").unwrap().last_good_source(),
    Some("10"),
  )
  assert_eq(malformed.diagnostics(), [ProjectionDiagnostic::MalformedJson("A1")])
}

///|
test "projection draft clean absent source deletion and dirty retention" {
  let sheet = @typed_spreadsheet.SheetId::SheetId(4)
  let source = compute_projection_transition(
    ProjectionState::empty(["A1"]),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      wb_raw("A1", Some(CellRegister::Source("10"))),
    ]),
    sheet,
    [],
  )
  wb_assert_decisions(source.decisions(), [
    ProjectionDecision::ApplyWorksheet(
      @demo.SheetOp::SetInput(
        @typed_spreadsheet.CellId::of(sheet, "A1"),
        @typed_spreadsheet.CellValue::from_int(10),
      ),
    ),
    ProjectionDecision::SetCommitted("A1", Some("10")),
    ProjectionDecision::SetDraft("A1", Some("10")),
  ])
  let deleted = compute_projection_transition(
    source.candidate_state(),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      wb_raw("A1", Some(CellRegister::Deleted)),
    ]),
    sheet,
    [DraftObservation::DraftObservation("A1", "10")],
  )
  wb_assert_decisions(deleted.decisions(), [
    ProjectionDecision::ApplyWorksheet(
      @demo.SheetOp::Delete(@typed_spreadsheet.CellId::of(sheet, "A1")),
    ),
    ProjectionDecision::SetCommitted("A1", None),
    ProjectionDecision::SetDraft("A1", None),
  ])
  let dirty = compute_projection_transition(
    source.candidate_state(),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      wb_raw("A1", Some(CellRegister::Source("20"))),
    ]),
    sheet,
    [DraftObservation::DraftObservation("A1", "local")],
  )
  wb_assert_decisions(dirty.decisions(), [
    ProjectionDecision::ApplyWorksheet(
      @demo.SheetOp::SetInput(
        @typed_spreadsheet.CellId::of(sheet, "A1"),
        @typed_spreadsheet.CellValue::from_int(20),
      ),
    ),
    ProjectionDecision::SetCommitted("A1", Some("20")),
  ])
}

///|
test "projection malformed repeated preserves last good and diagnoses once" {
  let sheet = @typed_spreadsheet.SheetId::SheetId(5)
  let good = compute_projection_transition(
    ProjectionState::empty(["A1"]),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      wb_raw("A1", Some(CellRegister::Source("10"))),
    ]),
    sheet,
    [],
  )
  let malformed_snapshot = RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
    RawRegisterEntry::RawRegisterEntry("A1", Some("{")),
  ])
  let malformed = compute_projection_transition(
    good.candidate_state(),
    malformed_snapshot,
    sheet,
    [],
  )
  let cell = malformed.candidate_state().cell("A1").unwrap()
  assert_eq(
    cell.last_seen_register(),
    RegisterObservation::Invalid(ProjectionDiagnostic::MalformedJson("A1")),
  )
  assert_eq(cell.last_good_source(), Some("10"))
  assert_eq(cell.diagnostic(), Some(ProjectionDiagnostic::MalformedJson("A1")))
  assert_eq(malformed.diagnostics(), [ProjectionDiagnostic::MalformedJson("A1")])
  let repeated = compute_projection_transition(
    malformed.candidate_state(),
    malformed_snapshot,
    sheet,
    [],
  )
  assert_eq(repeated.decisions().length(), 0)
}

///|
test "projection malformed recovery only clears diagnostic for same last good source" {
  let sheet = @typed_spreadsheet.SheetId::SheetId(5)
  let good = compute_projection_transition(
    ProjectionState::empty(["A1"]),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      wb_raw("A1", Some(CellRegister::Source("10"))),
    ]),
    sheet,
    [],
  )
  let malformed = compute_projection_transition(
    good.candidate_state(),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      RawRegisterEntry::RawRegisterEntry("A1", Some("{")),
    ]),
    sheet,
    [],
  )
  let recovered = compute_projection_transition(
    malformed.candidate_state(),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      wb_raw("A1", Some(CellRegister::Source("10"))),
    ]),
    sheet,
    [],
  )
  wb_assert_decisions(recovered.decisions(), [
    ProjectionDecision::SetDiagnostic("A1", None),
  ])
  assert_eq(
    recovered.candidate_state().cell("A1").unwrap().last_good_source(),
    Some("10"),
  )
  assert_eq(recovered.candidate_state().cell("A1").unwrap().diagnostic(), None)
}

///|
test "projection invalid source recovery updates semantic state" {
  let sheet = @typed_spreadsheet.SheetId::SheetId(6)
  let invalid = compute_projection_transition(
    ProjectionState::empty(["A1"]),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      wb_raw("A1", Some(CellRegister::Source("nope"))),
    ]),
    sheet,
    [],
  )
  let invalid_cell = invalid.candidate_state().cell("A1").unwrap()
  assert_eq(
    invalid_cell.last_seen_register(),
    RegisterObservation::Decoded(CellRegister::Source("nope")),
  )
  assert_eq(invalid_cell.last_good_source(), None)
  assert_true(
    invalid_cell.diagnostic()
    is Some(ProjectionDiagnostic::InvalidSource(_, _, _)),
  )
  let valid = compute_projection_transition(
    invalid.candidate_state(),
    RawRegisterSnapshot::RawRegisterSnapshot(["A1"], [
      wb_raw("A1", Some(CellRegister::Source("10"))),
    ]),
    sheet,
    [],
  )
  wb_assert_decisions(valid.decisions(), [
    ProjectionDecision::ApplyWorksheet(
      @demo.SheetOp::SetInput(
        @typed_spreadsheet.CellId::of(sheet, "A1"),
        @typed_spreadsheet.CellValue::from_int(10),
      ),
    ),
    ProjectionDecision::SetCommitted("A1", Some("10")),
    ProjectionDecision::SetDraft("A1", Some("10")),
    ProjectionDecision::SetDiagnostic("A1", None),
  ])
  assert_eq(
    valid.candidate_state().cell("A1").unwrap().last_good_source(),
    Some("10"),
  )
}

///|
test "projection diagnostics follow canonical snapshot order" {
  let snapshot = RawRegisterSnapshot::RawRegisterSnapshot(["B1", "A1"], [
    RawRegisterEntry::RawRegisterEntry("A1", Some("{")),
    RawRegisterEntry::RawRegisterEntry("B1", Some("{")),
  ])
  assert_eq(
    compute_projection_transition(
      ProjectionState::empty(["B1", "A1"]),
      snapshot,
      @typed_spreadsheet.SheetId::SheetId(7),
      [],
    ).diagnostics(),
    [
      ProjectionDiagnostic::MalformedJson("B1"),
      ProjectionDiagnostic::MalformedJson("A1"),
    ],
  )
}

///|
test "projection retry is pure and candidates are equal" {
  let sheet = @typed_spreadsheet.SheetId::SheetId(8)
  let previous = ProjectionState::empty(["B1", "A1"])
  let snapshot = RawRegisterSnapshot::RawRegisterSnapshot(["B1", "A1"], [
    wb_raw("A1", Some(CellRegister::Source("nope"))),
    wb_raw("B1", Some(CellRegister::Source("10"))),
  ])
  let drafts = ReadOnlyArray::from_array([
    DraftObservation::DraftObservation("A1", ""),
    DraftObservation::DraftObservation("B1", ""),
  ])
  let first = compute_projection_transition(previous, snapshot, sheet, drafts)
  let second = compute_projection_transition(previous, snapshot, sheet, drafts)
  assert_eq(first.candidate_state(), second.candidate_state())
  assert_eq(first.diagnostics(), second.diagnostics())
  wb_assert_decisions(first.decisions(), second.decisions())
}

///|
test "projection state empty deduplicates addresses" {
  let state = ProjectionState::empty(["B1", "A1", "B1", "A1"])
  assert_eq(state.cells().map(c => c.address()), ["B1", "A1"])
}
