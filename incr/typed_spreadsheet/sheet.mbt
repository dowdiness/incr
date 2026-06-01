///|
/// A typed spreadsheet worksheet built on top of existing `@incr` cells.
///
/// `Worksheet` owns a local scope for all cells in the sheet so callers can
/// dispose an entire sheet by dropping the scope.
pub struct Worksheet {
  runtime : @incr.Runtime
  sheet_id : SheetId
  scope : @incr.Scope
  cells : @hashmap.HashMap[CellId, CellSlot]
  cell_presence : @hashmap.HashMap[CellId, @incr.InputField[Bool]]
}

///|
priv enum CellDefinition {
  Input(CellValue)
  Formula(Array[CellId], Array[CellId], CellType, (Worksheet) -> CellResult)
}

///|
struct CellSlot {
  presence : @incr.InputField[Bool]
  definition : @incr.InputField[CellDefinition]
  value : @incr.Derived[CellResult]
  metadata_root : @incr.Derived[Unit]
  watch : @incr.Watch[CellResult]
  metadata_watch : @incr.Watch[Unit]
}

///|
/// Whether a worksheet cell has a concrete value or formula definition.
pub enum CellKind {
  Input
  Formula
}

///|
/// A plain, read-only view of a single cell for UI and diagnostics.
pub struct CellSnapshot {
  id : CellId
  present : Bool
  kind : CellKind?
  result : CellResult
  installed_dependencies : Array[CellId]
  static_references : Array[CellId]
}

///|
/// Plain trace data for worksheet operations.
pub struct WorksheetTrace {
  recomputed : Array[CellId]
  changed : Array[CellId]
  unchanged : Array[CellId]
}

///|
/// Creates a worksheet bound to a runtime.
pub fn Worksheet::Worksheet(
  runtime : @incr.Runtime,
  sheet_id : SheetId,
) -> Worksheet {
  {
    runtime,
    sheet_id,
    scope: @incr.Scope::new(runtime),
    cells: @hashmap.HashMap([]),
    cell_presence: @hashmap.HashMap([]),
  }
}

///|
/// Returns the worksheet identifier.
pub fn Worksheet::sheet_id(self : Worksheet) -> SheetId {
  self.sheet_id
}

///|
/// Returns true when this worksheet has been disposed.
pub fn Worksheet::is_disposed(self : Worksheet) -> Bool {
  self.scope.is_disposed()
}

///|
/// Disposes all cells created through this worksheet.
pub fn Worksheet::dispose(self : Worksheet) -> Unit {
  self.scope.dispose()
}

///|
/// Reads the current cell result without aborting.
pub fn Worksheet::read(self : Worksheet, id : CellId) -> CellResult {
  self.read_slot(id)
}

///|
/// Returns a stable inspection snapshot for a single cell.
pub fn Worksheet::inspect_cell(self : Worksheet, id : CellId) -> CellSnapshot {
  if !self.owns_cell_id(id) {
    return missing_cell_snapshot(id, "foreign cell id")
  }

  match self.cell_presence.get(id) {
    Some(presence) if !presence.get() =>
      return missing_cell_snapshot(id, "no cell at the requested address")
    Some(_) => ()
    None => return missing_cell_snapshot(id, "no cell at the requested address")
  }

  match self.cells.get(id) {
    Some(slot) => {
      let (kind, installed_dependencies, static_references) = slot.definition
        .get()
        .kind_and_deps()
      {
        id,
        present: true,
        kind,
        result: slot.read(),
        installed_dependencies,
        static_references,
      }
    }
    None => missing_cell_snapshot(id, "no cell at the requested address")
  }
}

///|
/// Runs an operation and returns a recompute/change trace for this worksheet.
///
/// The method returns `recomputed`, `changed`, and `unchanged` formula cell IDs,
/// with all formula cells re-read after the operation to capture final status.
///
/// - `recomputed`: formula cells whose verified revision advanced.
/// - `changed`: formula cells that changed value (`changed_at` advanced).
/// - `unchanged`: formula cells that reverified but did not change.
pub fn[T] Worksheet::trace(
  self : Worksheet,
  operation : () -> T,
) -> (T, WorksheetTrace) {
  let pre_formula_cells = self.formula_cells()
  pre_formula_cells.each(id => {
    let _ = self.read_slot(id)
  })

  let before = self.formula_revision_snapshot_with_ids(pre_formula_cells)
  let output = operation()
  let post_formula_cells = self.formula_cells()
  post_formula_cells.each(id => {
    let _ = self.read_slot(id)
  })
  let after = self.formula_revision_snapshot_with_ids(post_formula_cells)
  let (before_snapshot, after_snapshot) = (before, after)
  let recomputed : Array[CellId] = post_formula_cells.filter_map(id => {
    match (before_snapshot.get(id), after_snapshot.get(id)) {
      (Some(before_revision), Some(after_revision)) if after_revision.verified_at !=
        before_revision.verified_at => Some(id)
      (None, Some(_)) => Some(id)
      _ => None
    }
  })

  let changed : Array[CellId] = post_formula_cells.filter_map(id => {
    match (before_snapshot.get(id), after_snapshot.get(id)) {
      (Some(before_revision), Some(after_revision)) if after_revision.verified_at !=
        before_revision.verified_at &&
        after_revision.changed_at != before_revision.changed_at => Some(id)
      (None, Some(_)) => Some(id)
      _ => None
    }
  })

  let unchanged : Array[CellId] = post_formula_cells.filter_map(id => {
    match (before_snapshot.get(id), after_snapshot.get(id)) {
      (Some(before_revision), Some(after_revision)) if after_revision.verified_at !=
        before_revision.verified_at &&
        after_revision.changed_at == before_revision.changed_at => Some(id)
      _ => None
    }
  })

  (output, WorksheetTrace::{ recomputed, changed, unchanged })
}

///|
/// Sets a concrete value cell.
pub fn Worksheet::set_input(
  self : Worksheet,
  id : CellId,
  value : CellValue,
  declared? : CellType = CellType::TAny,
  label? : String,
) -> CellResult {
  if !self.owns_cell_id(id) {
    return CellResult::RefError("foreign cell id")
  }

  let cell_type = if declared == CellType::TAny {
    value.cell_type()
  } else {
    declared
  }

  if !cell_type.accepts(value) {
    return type_error(cell_type, value)
  }

  self.set_cell_definition(id, CellDefinition::Input(value), label?)
  CellResult::Ok(value)
}

///|
/// Sets a formula cell from typed dependencies.
///
/// The `compute` function receives the dependency values in `deps` order.
///
/// Returns `Result::Ok(())` when installation succeeds and `RefError` for
/// boundary mismatches. Read the cell through `read` to observe
/// evaluation results such as `TypeError`/`RefError`.
///
/// This keeps install success and evaluation success decoupled.
pub fn Worksheet::set_formula(
  self : Worksheet,
  id : CellId,
  declared : CellType,
  deps : Array[CellId],
  compute : (Array[CellValue]) -> CellResult,
  label? : String,
) -> Result[Unit, WorksheetError] {
  if !self.owns_cell_id(id) {
    return Err(WorksheetError::ref_error("foreign cell id"))
  }

  if !self.all_cell_ids_owned(deps) {
    return Err(WorksheetError::ref_error("foreign dependency id"))
  }

  let dep_ids = deps.copy()
  let definition = CellDefinition::Formula(dep_ids, dep_ids, declared, worksheet => {
    let values = []
    let mut first_error : CellResult? = None
    dep_ids.each(dep_id => {
      if first_error is None {
        let value_result = worksheet.get_slot(dep_id)
        match value_result {
          CellResult::Ok(value) => values.push(value)
          _ => first_error = Some(value_result)
        }
      }
    })
    match first_error {
      Some(error) => error
      None => compute(values)
    }
  })
  self.set_cell_definition(id, definition, label?)

  Ok(())
}

///|
/// Sets a formula cell from a hand-built formula AST.
///
/// Returns `Result::Ok(())` when installation succeeds and `RefError` for
/// boundary mismatches. Read the cell through `read` to observe
/// evaluation results such as `TypeError`/`RefError`.
///
/// This keeps install success and evaluation success decoupled.
pub fn Worksheet::set_formula_ast(
  self : Worksheet,
  id : CellId,
  declared : CellType,
  formula : Formula,
  label? : String,
) -> Result[Unit, WorksheetError] {
  if !self.owns_cell_id(id) {
    return Err(WorksheetError::ref_error("foreign cell id"))
  }

  let dep_ids = formula.refs()
  if !self.all_cell_ids_owned(dep_ids) {
    return Err(WorksheetError::ref_error("foreign dependency id"))
  }

  let definition = CellDefinition::Formula(
    dep_ids,
    ([] : Array[CellId]),
    declared,
    worksheet => formula.evaluate(dep_id => worksheet.get_slot(dep_id)),
  )
  self.set_cell_definition(id, definition, label?)

  Ok(())
}

///|
/// Marks a cell as deleted and wires batch rollback restoration.
pub fn Worksheet::delete(self : Worksheet, id : CellId) -> CellResult {
  if !self.owns_cell_id(id) {
    return CellResult::RefError("foreign cell id")
  }

  match self.cells.get(id) {
    Some(_) => {
      let presence = self.cell_presence_for(id)
      let previous_present = presence.get()
      if !previous_present {
        return CellResult::RefError("no cell at the requested address")
      }
      presence.set(false)
      CellResult::Ok(CellValue::Blank)
    }
    None => CellResult::RefError("no cell at the requested address")
  }
}

///|
fn Worksheet::read_slot(self : Worksheet, id : CellId) -> CellResult {
  self.with_live_slot(id, slot => slot.read())
}

///|
fn Worksheet::get_slot(self : Worksheet, id : CellId) -> CellResult {
  self.with_live_slot(id, slot => slot.get())
}

///|
fn Worksheet::with_live_slot(
  self : Worksheet,
  id : CellId,
  consume_slot : (CellSlot) -> CellResult,
) -> CellResult {
  if !self.owns_cell_id(id) {
    return CellResult::RefError("foreign cell id")
  }

  if !self.cell_presence_for(id).get() {
    return CellResult::RefError("no cell at the requested address")
  }
  match self.cells.get(id) {
    Some(slot) => consume_slot(slot)
    None => CellResult::RefError("no cell at the requested address")
  }
}

///|
fn Worksheet::formula_cells(self : Worksheet) -> Array[CellId] {
  [
    for id in self.cells.keys().to_array() if self.is_formula_cell(id) => id
  ]
}

///|
fn Worksheet::is_formula_cell(self : Worksheet, id : CellId) -> Bool {
  match self.cell_presence.get(id) {
    Some(presence) if !presence.get() => false
    Some(_) =>
      match self.cells.get(id) {
        Some(slot) =>
          match slot.definition.get() {
            CellDefinition::Formula(_, _, _, _) => true
            _ => false
          }
        None => false
      }
    None => false
  }
}

///|
fn Worksheet::formula_revision_snapshot_with_ids(
  self : Worksheet,
  formula_cells : Array[CellId],
) -> @hashmap.HashMap[CellId, FormulaRevisionSnapshot] {
  let snapshot = @hashmap.HashMap([])
  formula_cells.each(id => {
    match self.cells.get(id) {
      Some(slot) =>
        match self.runtime.cell_info(slot.value.id()) {
          Some(info) =>
            snapshot.set(id, FormulaRevisionSnapshot::{
              changed_at: info.changed_at,
              verified_at: info.verified_at,
            })
          None => ()
        }
      None => ()
    }
  })
  snapshot
}

///|
priv struct FormulaRevisionSnapshot {
  changed_at : @incr.Revision
  verified_at : @incr.Revision
}

///|
fn Worksheet::owns_cell_id(self : Worksheet, id : CellId) -> Bool {
  self.sheet_id == id.sheet_id
}

///|
fn Worksheet::new_slot(
  self : Worksheet,
  id : CellId,
  definition : CellDefinition,
  label? : String,
) -> CellSlot {
  let presence = self.cell_presence_for(id)
  let definition = self.scope.input_field(definition, label?)
  let value = self.scope.derived(
    () => {
      if presence.get() {
        definition.get().evaluate(self)
      } else {
        CellResult::RefError("no cell at the requested address")
      }
    },
    label?,
  )
  let metadata_root = self.scope.derived(
    () => {
      let _ = presence.get()
      let _ = definition.get()
      ()
    },
    label?,
  )
  let watch = self.scope.add_watch(value.watch())
  let metadata_watch = self.scope.add_watch(metadata_root.watch())
  CellSlot::{
    presence,
    definition,
    value,
    metadata_root,
    watch,
    metadata_watch,
  }
}

///|
fn Worksheet::store_new_slot(
  self : Worksheet,
  id : CellId,
  slot : CellSlot,
) -> Unit {
  slot.presence.set(true)

  let definition_id = slot.definition.id()
  let value_id = slot.value.id()
  let metadata_root_id = slot.metadata_root.id()
  self.cells.set(id, slot)
  self.runtime.record_batch_rollback(definition_id, () => {
    self.cells.remove(id)
    slot.watch.dispose()
    slot.metadata_watch.dispose()
    self.runtime.dispose_cell(definition_id)
    self.runtime.dispose_cell(value_id)
    self.runtime.dispose_cell(metadata_root_id)
  })
  let _ = slot.metadata_watch.read()
}

///|
fn Worksheet::cell_presence_for(
  self : Worksheet,
  id : CellId,
) -> @incr.InputField[Bool] {
  match self.cell_presence.get(id) {
    Some(field) => field
    None => {
      let field = self.scope.input_field(false)
      self.cell_presence.set(id, field)
      field
    }
  }
}

///|
fn missing_cell_snapshot(id : CellId, message : String) -> CellSnapshot {
  {
    id,
    present: false,
    kind: None,
    result: CellResult::RefError(message),
    installed_dependencies: [],
    static_references: [],
  }
}

///|
fn Worksheet::set_cell_definition(
  self : Worksheet,
  id : CellId,
  definition : CellDefinition,
  label? : String,
) -> Unit {
  match self.cells.get(id) {
    Some(slot) => {
      if !slot.presence.get() {
        slot.presence.set(true)
      }
      slot.definition.force_set(definition)
    }
    None => {
      let slot = self.new_slot(id, definition, label?)
      self.store_new_slot(id, slot)
    }
  }
}

///|
fn Worksheet::all_cell_ids_owned(self : Worksheet, ids : Array[CellId]) -> Bool {
  ids.all(id => self.owns_cell_id(id))
}

///|
fn CellDefinition::kind_and_deps(
  self : CellDefinition,
) -> (CellKind?, Array[CellId], Array[CellId]) {
  match self {
    CellDefinition::Input(_) =>
      (Some(CellKind::Input), ([] : Array[CellId]), ([] : Array[CellId]))
    CellDefinition::Formula(static_references, installed_dependencies, _, _) =>
      (
        Some(CellKind::Formula),
        installed_dependencies.copy(),
        static_references.copy(),
      )
  }
}

///|
fn CellDefinition::evaluate(
  self : CellDefinition,
  worksheet : Worksheet,
) -> CellResult {
  match self {
    CellDefinition::Input(value) => CellResult::Ok(value)
    CellDefinition::Formula(_, _, expected, evaluate) => {
      let result = evaluate(worksheet)
      match result {
        CellResult::Ok(value) =>
          if expected == CellType::TAny || expected.accepts(value) {
            CellResult::Ok(value)
          } else {
            CellResult::TypeError(
              "formula result mismatch: expected " +
              expected.to_string() +
              " and got " +
              value.cell_type().to_string(),
            )
          }
        _ => result
      }
    }
  }
}

///|
fn type_error(cell_type : CellType, value : CellValue) -> CellResult {
  CellResult::TypeError(
    "value type mismatch: expected " +
    cell_type.to_string() +
    " and got " +
    value.cell_type().to_string(),
  )
}

///|
fn CellSlot::read(self : CellSlot) -> CellResult {
  match self.watch.read() {
    Ok(value) => value
    Err(err) => CellResult::CycleError(err.format_path())
  }
}

///|
fn CellSlot::get(self : CellSlot) -> CellResult {
  match self.value.get() {
    Ok(value) => value
    Err(err) => CellResult::CycleError(err.format_path())
  }
}
