///|
/// A typed formula AST for spreadsheet expressions.
pub enum Formula {
  /// A literal value in the formula.
  Literal(CellValue)
  /// A reference to another worksheet cell.
  Ref(CellId)
  /// Integer addition of two formulas.
  Add(Formula, Formula)
}

///|
/// Creates a literal formula node.
pub fn Formula::literal(value : CellValue) -> Formula {
  Formula::Literal(value)
}

///|
/// Creates a formula reference node.
pub fn Formula::cell_ref(cell_id : CellId) -> Formula {
  Formula::Ref(cell_id)
}

///|
/// Creates an integer-addition formula node.
pub fn Formula::add(lhs : Formula, rhs : Formula) -> Formula {
  Formula::Add(lhs, rhs)
}

///|
/// Evaluates the formula through a cell reader.
///
/// Reader failures are surfaced directly as `CellResult`.
fn Formula::evaluate(
  self : Formula,
  read : (CellId) -> CellResult,
) -> CellResult {
  match self {
    Formula::Literal(value) => CellResult::ok(value)
    Formula::Ref(cell_id) => read(cell_id)
    Formula::Add(lhs, rhs) => {
      let left = lhs.evaluate(read)
      match left {
        CellResult::Ok(left_value) => {
          let right = rhs.evaluate(read)
          match right {
            CellResult::Ok(right_value) =>
              match left_value {
                CellValue::Int(lhs_value) =>
                  match right_value {
                    CellValue::Int(rhs_value) =>
                      CellResult::ok(CellValue::from_int(lhs_value + rhs_value))
                    _ =>
                      CellResult::type_error(
                        "Add requires Int on the right side",
                      )
                  }
                _ => CellResult::type_error("Add requires Int on the left side")
              }
            _ => right
          }
        }
        _ => left
      }
    }
  }
}

///|
/// Collects direct and nested referenced cell ids used by this formula.
pub fn Formula::refs(self : Formula) -> Array[CellId] {
  let refs = []
  self.collect_refs(refs)
  refs
}

///|
fn Formula::collect_refs(self : Formula, refs : Array[CellId]) -> Unit {
  match self {
    Formula::Literal(_) => ()
    Formula::Ref(cell_id) =>
      if !formula_refs_contains(refs, cell_id) {
        refs.push(cell_id)
      }
    Formula::Add(lhs, rhs) => {
      lhs.collect_refs(refs)
      rhs.collect_refs(refs)
    }
  }
}

///|
fn formula_refs_contains(refs : Array[CellId], target : CellId) -> Bool {
  for value in refs {
    if value == target {
      return true
    }
  }
  false
}
