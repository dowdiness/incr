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
}

///|
enum CellSlot {
  Input(@incr.InputField[CellValue])
  Formula(@incr.Derived[CellResult])
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
  let cell_type = if declared == CellType::TAny {
    value.cell_type()
  } else {
    declared
  }

  match self.cells.get(id) {
    Some(slot) =>
      match slot {
        CellSlot::Input(input) => {
          if !cell_type.accepts(value) {
            return CellResult::TypeError(
              "value type mismatch: expected " +
              cell_type.to_string() +
              " and got " +
              value.cell_type().to_string(),
            )
          }
          input.set(value)
          self.cells.set(id, CellSlot::Input(input))
          CellResult::Ok(value)
        }
        CellSlot::Formula(formula) => {
          if !cell_type.accepts(value) {
            return CellResult::TypeError(
              "value type mismatch: expected " +
              cell_type.to_string() +
              " and got " +
              value.cell_type().to_string(),
            )
          }
          self.runtime.dispose_cell(formula.id())
          let input = self.scope.input_field(value, label?)
          self.cells.set(id, CellSlot::Input(input))
          CellResult::Ok(value)
        }
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
      let input = self.scope.input_field(value, label?)
      self.cells.set(id, CellSlot::Input(input))
      CellResult::Ok(value)
    }
  }
}

///|
/// Sets a formula cell from typed dependencies.
///
/// The `compute` function receives the dependency values in `deps` order.
///
/// Returns `Unit` when installation succeeds. Read the cell through
/// `read` to observe evaluation results such as `TypeError`/`RefError`.
///
/// This keeps install success and evaluation success decoupled.
pub fn Worksheet::set_formula(
  self : Worksheet,
  id : CellId,
  declared : CellType,
  deps : Array[CellId],
  compute : (Array[CellValue]) -> CellResult,
  label? : String,
) -> Unit {
  let existing = self.cells.get(id)

  let dep_ids = deps
  let expected = declared
  let evaluator = compute

  let derived = self.scope.derived(
    fn() {
      let values = []
      for dep_id in dep_ids {
        match self.read_slot(dep_id) {
          CellResult::Ok(value) => values.push(value)
          CellResult::ParseError(message) =>
            return CellResult::RefError(message)
          CellResult::TypeError(message) => return CellResult::RefError(message)
          CellResult::RefError(message) => return CellResult::RefError(message)
          CellResult::CycleError(message) =>
            return CellResult::CycleError(message)
        }
      }

      let result = evaluator(values)
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
    },
    label?,
  )

  match existing {
    Some(existing_cell) => self.runtime.dispose_cell(existing_cell.cell_id())
    None => ()
  }

  self.cells.set(id, CellSlot::Formula(derived))
}

///|
/// Sets a formula cell from a hand-built formula AST.
///
/// Returns `Unit` when installation succeeds. Read the cell through
/// `read` to observe evaluation results such as `TypeError`/`RefError`.
///
/// This keeps install success and evaluation success decoupled.
pub fn Worksheet::set_formula_ast(
  self : Worksheet,
  id : CellId,
  declared : CellType,
  formula : Formula,
  label? : String,
) -> Unit {
  let existing = self.cells.get(id)

  let computed = formula
  let expected = declared

  let derived = self.scope.derived(
    fn() {
      let result = computed.evaluate(fn(dep_id) { self.read_slot(dep_id) })
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
    },
    label?,
  )

  match existing {
    Some(existing_cell) => self.runtime.dispose_cell(existing_cell.cell_id())
    None => ()
  }

  self.cells.set(id, CellSlot::Formula(derived))
}

///|
/// Removes a cell definition and disposes its underlying `@incr` node.
pub fn Worksheet::delete(self : Worksheet, id : CellId) -> CellResult {
  match self.cells.get(id) {
    Some(slot) => {
      self.runtime.dispose_cell(slot.cell_id())
      self.cells.remove(id)
      CellResult::Ok(CellValue::Blank)
    }
    None => CellResult::RefError("no cell at the requested address")
  }
}

///|
fn Worksheet::read_slot(self : Worksheet, id : CellId) -> CellResult {
  match self.cells.get(id) {
    Some(slot) => slot.read()
    None => CellResult::RefError("cell not found")
  }
}

///|
fn CellSlot::read(self : CellSlot) -> CellResult {
  match self {
    Input(field) => CellResult::Ok(field.get())
    Formula(derived) =>
      match derived.read() {
        Ok(value) => value
        Err(err) => CellResult::CycleError(err.format_path())
      }
  }
}

///|
fn CellSlot::cell_id(self : CellSlot) -> @incr.CellId {
  match self {
    Input(field) => field.id()
    Formula(derived) => derived.id()
  }
}
