///|
/// Monotonic generation for commands issued against a sheet document.
///
/// The representation is private; use `initial` and `next` to create values.
pub struct DocumentGeneration(Int) derive(Eq, Debug)

///|
/// Returns the initial document generation.
pub fn DocumentGeneration::initial() -> DocumentGeneration {
  DocumentGeneration(0)
}

///|
/// Returns the next document generation.
pub fn DocumentGeneration::next(
  self : DocumentGeneration,
) -> DocumentGeneration {
  DocumentGeneration(self.0 + 1)
}

///|
/// A command submitted by the sheet UI for later execution.
pub(all) enum SheetCommand {
  /// Apply submitted text to the currently selected cell.
  ApplyFromSelection(@typed_spreadsheet.CellId, String, DocumentGeneration)
  /// Apply submitted text to the cell being edited inline.
  ApplyFromEditor(@typed_spreadsheet.CellId, String, DocumentGeneration)
  /// Delete the currently selected cell.
  DeleteFromSelection(@typed_spreadsheet.CellId, DocumentGeneration)
  /// Reset the document at the captured generation.
  ResetDocument(DocumentGeneration)
} derive(Eq, Debug)

///|
/// Whether a sheet command may be executed in the current context.
pub(all) enum CommandApplicability {
  /// The command may be executed.
  Applicable
  /// The command was created for an older document generation.
  StaleGeneration
  /// The command's local selection or editing precondition failed.
  LocalPreconditionFailed
} derive(Eq, Debug)

///|
/// The sheet state needed to validate a command at execution time.
///
/// Construct this value with `SheetExecutionContext::SheetExecutionContext`.
pub struct SheetExecutionContext {
  selected_cell : @typed_spreadsheet.CellId
  editing_cell : @typed_spreadsheet.CellId?
  generation : DocumentGeneration
} derive(Eq, Debug)

///|
/// Creates an execution context for sheet command validation.
pub fn SheetExecutionContext::SheetExecutionContext(
  selected_cell : @typed_spreadsheet.CellId,
  editing_cell : @typed_spreadsheet.CellId?,
  generation : DocumentGeneration,
) -> SheetExecutionContext {
  { selected_cell, editing_cell, generation }
}

///|
/// Validates a command without changing the document or execution context.
///
/// Stale generation takes precedence over local selection or editor
/// preconditions.
pub fn validate_sheet_command(
  command : SheetCommand,
  context : SheetExecutionContext,
) -> CommandApplicability {
  match command {
    SheetCommand::ApplyFromSelection(target, _, generation)
    | SheetCommand::DeleteFromSelection(target, generation) =>
      if generation != context.generation {
        StaleGeneration
      } else if target != context.selected_cell {
        LocalPreconditionFailed
      } else {
        Applicable
      }
    SheetCommand::ApplyFromEditor(target, _, generation) =>
      if generation != context.generation {
        StaleGeneration
      } else if context.editing_cell != Some(target) {
        LocalPreconditionFailed
      } else {
        Applicable
      }
    SheetCommand::ResetDocument(generation) =>
      if generation != context.generation {
        StaleGeneration
      } else {
        Applicable
      }
  }
}
