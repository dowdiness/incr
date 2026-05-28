///|
/// A typed formula AST for spreadsheet expressions.
pub enum Formula {
  /// A literal value in the formula.
  Literal(CellValue)
  /// A reference to another worksheet cell.
  Ref(CellId)
  /// Integer addition of two formulas.
  Add(Formula, Formula)
  /// Integer multiplication of two formulas.
  Mul(Formula, Formula)
  /// Equality comparison of two formulas.
  Eq(Formula, Formula)
  /// Integer greater-than comparison of two formulas.
  Gt(Formula, Formula)
  /// Conditional formula execution.
  If(Formula, Formula, Formula)
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
/// Creates an integer-multiplication formula node.
pub fn Formula::mul(lhs : Formula, rhs : Formula) -> Formula {
  Formula::Mul(lhs, rhs)
}

///|
/// Creates an equality comparison formula node.
pub fn Formula::eq(lhs : Formula, rhs : Formula) -> Formula {
  Formula::Eq(lhs, rhs)
}

///|
/// Creates an integer-greater-than comparison formula node.
pub fn Formula::gt(lhs : Formula, rhs : Formula) -> Formula {
  Formula::Gt(lhs, rhs)
}

///|
/// Creates a conditional formula node.
pub fn Formula::if_(
  condition : Formula,
  then_formula : Formula,
  else_formula : Formula,
) -> Formula {
  Formula::If(condition, then_formula, else_formula)
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
    Formula::Mul(lhs, rhs) => {
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
                      CellResult::ok(CellValue::from_int(lhs_value * rhs_value))
                    _ =>
                      CellResult::type_error(
                        "Mul requires Int on the right side",
                      )
                  }
                _ => CellResult::type_error("Mul requires Int on the left side")
              }
            _ => right
          }
        }
        _ => left
      }
    }
    Formula::Eq(lhs, rhs) => {
      let left = lhs.evaluate(read)
      match left {
        CellResult::Ok(left_value) => {
          let right = rhs.evaluate(read)
          match right {
            CellResult::Ok(right_value) =>
              CellResult::ok(CellValue::Bool(left_value == right_value))
            _ => right
          }
        }
        _ => left
      }
    }
    Formula::Gt(lhs, rhs) => {
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
                      CellResult::ok(
                        CellValue::from_bool(lhs_value > rhs_value),
                      )
                    _ =>
                      CellResult::type_error(
                        "Gt requires Int on the right side",
                      )
                  }
                _ => CellResult::type_error("Gt requires Int on the left side")
              }
            _ => right
          }
        }
        _ => left
      }
    }
    Formula::If(condition, then_formula, else_formula) =>
      match condition.evaluate(read) {
        CellResult::Ok(value) =>
          match value {
            CellValue::Bool(flag) =>
              if flag {
                then_formula.evaluate(read)
              } else {
                else_formula.evaluate(read)
              }
            _ => CellResult::type_error("If requires Bool condition")
          }
        result => result
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
    Formula::Mul(lhs, rhs) => {
      lhs.collect_refs(refs)
      rhs.collect_refs(refs)
    }
    Formula::Eq(lhs, rhs) => {
      lhs.collect_refs(refs)
      rhs.collect_refs(refs)
    }
    Formula::Gt(lhs, rhs) => {
      lhs.collect_refs(refs)
      rhs.collect_refs(refs)
    }
    Formula::If(condition, then_formula, else_formula) => {
      condition.collect_refs(refs)
      then_formula.collect_refs(refs)
      else_formula.collect_refs(refs)
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
