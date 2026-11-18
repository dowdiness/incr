///|
/// Monotonic generation for commands issued against a sheet document.
///
/// The representation is private; use `initial` and `next` to create values.
#derive(Eq, Debug)
pub struct DocumentGeneration(Int32)

///|
pub extend DocumentGeneration with Eq::{not_equal, equal}

///|
pub extend DocumentGeneration with Debug::{to_repr}

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
#derive(Eq, Debug)
pub(all) enum SheetCommand {
  /// Apply submitted text to the currently selected cell.
  ApplyFromSelection(@typed_spreadsheet.CellId, String, DocumentGeneration)
  /// Apply submitted text to the cell being edited inline.
  ApplyFromEditor(@typed_spreadsheet.CellId, String, DocumentGeneration)
  /// Delete the currently selected cell.
  DeleteFromSelection(@typed_spreadsheet.CellId, DocumentGeneration)
  /// Reset the document at the captured generation.
  ResetDocument(DocumentGeneration)
}

///|
pub extend SheetCommand with Eq::{not_equal, equal}

///|
pub extend SheetCommand with Debug::{to_repr}

///|
/// Whether a sheet command may be executed in the current context.
#derive(Eq, Debug)
pub(all) enum CommandApplicability {
  /// The command may be executed.
  Applicable
  /// The command was created for an older document generation.
  StaleGeneration
  /// The command's local selection or editing precondition failed.
  LocalPreconditionFailed
}

///|
pub extend CommandApplicability with Eq::{not_equal, equal}

///|
pub extend CommandApplicability with Debug::{to_repr}

///|
/// The sheet state needed to validate a command at execution time.
///
/// Construct this value with `SheetExecutionContext::SheetExecutionContext`.
#derive(Eq, Debug)
pub struct SheetExecutionContext {
  selected_cell : @typed_spreadsheet.CellId
  editing_cell : @typed_spreadsheet.CellId?
  generation : DocumentGeneration
}

///|
pub extend SheetExecutionContext with Eq::{not_equal, equal}

///|
pub extend SheetExecutionContext with Debug::{to_repr}

///|
/// Creates an execution context for sheet command validation.
pub fn SheetExecutionContext::SheetExecutionContext(
  selected_cell : @typed_spreadsheet.CellId,
  editing_cell : @typed_spreadsheet.CellId?,
  generation : DocumentGeneration,
) -> SheetExecutionContext {
  { selected_cell, editing_cell, generation, }
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
