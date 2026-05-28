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
  Formula(Array[CellId], CellType, (Array[CellValue]) -> CellResult)
}

///|
struct CellSlot {
  definition : @incr.InputField[CellDefinition]
  value : @incr.Derived[CellResult]
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

  match self.cells.get(id) {
    Some(slot) => {
      if !cell_type.accepts(value) {
        return CellResult::TypeError(
          "value type mismatch: expected " +
          cell_type.to_string() +
          " and got " +
          value.cell_type().to_string(),
        )
      }
      slot.definition.force_set(CellDefinition::Input(value))
      CellResult::Ok(value)
    }
    None => {
      if !cell_type.accepts(value) {
        return CellResult::TypeError(
          "value type mismatch: expected " +
          cell_type.to_string() +
          " and got " +
          value.cell_type().to_string(),
        )
      }
      let slot = self.new_slot(CellDefinition::Input(value), label?)
      self.store_new_slot(id, slot)
      CellResult::Ok(value)
    }
  }
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

  for dep_id in deps {
    if !self.owns_cell_id(dep_id) {
      return Err(WorksheetError::ref_error("foreign dependency id"))
    }
  }

  let definition = CellDefinition::Formula(deps.copy(), declared, compute)
  match self.cells.get(id) {
    Some(slot) => slot.definition.force_set(definition)
    None => {
      let slot = self.new_slot(definition, label?)
      self.store_new_slot(id, slot)
    }
  }

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
  for dep_id in dep_ids {
    if !self.owns_cell_id(dep_id) {
      return Err(WorksheetError::ref_error("foreign dependency id"))
    }
  }

  let computed = formula
  let definition = CellDefinition::Formula(dep_ids, declared, fn(_deps) {
    computed.evaluate(fn(dep_id) { self.read_slot(dep_id) })
  })
  match self.cells.get(id) {
    Some(slot) => slot.definition.force_set(definition)
    None => {
      let slot = self.new_slot(definition, label?)
      self.store_new_slot(id, slot)
    }
  }

  Ok(())
}

///|
/// Removes a cell definition and disposes its underlying `@incr` node.
pub fn Worksheet::delete(self : Worksheet, id : CellId) -> CellResult {
  if !self.owns_cell_id(id) {
    return CellResult::RefError("foreign cell id")
  }

  match self.cells.get(id) {
    Some(slot) => {
      let definition = slot.definition.get()
      self.cells.remove(id)
      let presence = self.cell_presence_for(id)
      let previous_present = presence.get()
      presence.force_set(false)
      self.runtime.record_batch_rollback(slot.definition.id(), fn() {
        let slot = self.new_slot(definition)
        self.cells.set(id, slot)
        presence.force_set(previous_present)
      })
      self.runtime.dispose_cell(slot.definition.id())
      self.runtime.dispose_cell(slot.value.id())
      CellResult::Ok(CellValue::Blank)
    }
    None => CellResult::RefError("no cell at the requested address")
  }
}

///|
fn Worksheet::read_slot(self : Worksheet, id : CellId) -> CellResult {
  if !self.owns_cell_id(id) {
    return CellResult::RefError("foreign cell id")
  }

  match self.cells.get(id) {
    Some(slot) => slot.read()
    None => {
      ignore(self.cell_presence_for(id).get())
      CellResult::RefError("cell not found")
    }
  }
}

///|
fn Worksheet::owns_cell_id(self : Worksheet, id : CellId) -> Bool {
  self.sheet_id == id.sheet_id
}

///|
fn Worksheet::new_slot(
  self : Worksheet,
  definition : CellDefinition,
  label? : String,
) -> CellSlot {
  let definition = self.scope.input_field(definition, label?)
  let value = self.scope.derived(
    fn() { definition.get().evaluate(self) },
    label?,
  )
  CellSlot::{ definition, value }
}

///|
fn Worksheet::store_new_slot(
  self : Worksheet,
  id : CellId,
  slot : CellSlot,
) -> Unit {
  let presence = self.cell_presence_for(id)
  let previous_present = presence.get()
  presence.force_set(true)

  let definition_id = slot.definition.id()
  let value_id = slot.value.id()
  self.cells.set(id, slot)
  self.runtime.record_batch_rollback(definition_id, fn() {
    self.cells.remove(id)
    presence.force_set(previous_present)
    self.runtime.dispose_cell(definition_id)
    self.runtime.dispose_cell(value_id)
  })
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
fn CellDefinition::evaluate(
  self : CellDefinition,
  worksheet : Worksheet,
) -> CellResult {
  match self {
    CellDefinition::Input(value) => CellResult::Ok(value)
    CellDefinition::Formula(dep_ids, expected, evaluate) => {
      let values = []
      for dep_id in dep_ids {
        match worksheet.read_slot(dep_id) {
          CellResult::Ok(value) => values.push(value)
          CellResult::ParseError(message) =>
            return CellResult::ParseError(message)
          CellResult::TypeError(message) =>
            return CellResult::TypeError(message)
          CellResult::RefError(message) => return CellResult::RefError(message)
          CellResult::CycleError(message) =>
            return CellResult::CycleError(message)
        }
      }

      let result = evaluate(values)
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
fn CellSlot::read(self : CellSlot) -> CellResult {
  match self.value.read() {
    Ok(value) => value
    Err(err) => CellResult::CycleError(err.format_path())
  }
}
