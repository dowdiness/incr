///|
test "command validation keeps generation and local preconditions independent" {
  let sheet_id = @typed_spreadsheet.SheetId(1)
  let selected = @typed_spreadsheet.CellId::of(sheet_id, "B1")
  let editor = @typed_spreadsheet.CellId::of(sheet_id, "C1")
  let generation = @domain.DocumentGeneration::initial()
  let context = @domain.SheetExecutionContext::SheetExecutionContext(
    selected,
    Some(editor),
    generation,
  )
  let selected_command = @domain.SheetCommand::ApplyFromSelection(
    selected, "=A1 + 1", generation,
  )
  assert_true(
    @domain.validate_sheet_command(selected_command, context) ==
    @domain.CommandApplicability::Applicable,
  )
  let editor_command = @domain.SheetCommand::ApplyFromEditor(
    editor, "7", generation,
  )
  assert_true(
    @domain.validate_sheet_command(editor_command, context) ==
    @domain.CommandApplicability::Applicable,
  )
  let delete_command = @domain.SheetCommand::DeleteFromSelection(
    selected, generation,
  )
  assert_true(
    @domain.validate_sheet_command(delete_command, context) ==
    @domain.CommandApplicability::Applicable,
  )
  let reset_command = @domain.SheetCommand::ResetDocument(generation)
  assert_true(
    @domain.validate_sheet_command(reset_command, context) ==
    @domain.CommandApplicability::Applicable,
  )
  let stale_and_mismatched = @domain.SheetCommand::ApplyFromSelection(
    selected,
    "=A1 + 1",
    generation.next(),
  )
  let mismatched_context = @domain.SheetExecutionContext::SheetExecutionContext(
    @typed_spreadsheet.CellId::of(sheet_id, "A1"),
    Some(@typed_spreadsheet.CellId::of(sheet_id, "D1")),
    generation,
  )
  assert_true(
    @domain.validate_sheet_command(stale_and_mismatched, mismatched_context) ==
    @domain.CommandApplicability::StaleGeneration,
  )
  assert_true(
    @domain.validate_sheet_command(selected_command, mismatched_context) ==
    @domain.CommandApplicability::LocalPreconditionFailed,
  )
  let editor_mismatch = @domain.SheetCommand::ApplyFromEditor(
    editor, "7", generation,
  )
  assert_true(
    @domain.validate_sheet_command(editor_mismatch, mismatched_context) ==
    @domain.CommandApplicability::LocalPreconditionFailed,
  )
}
