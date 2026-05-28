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
    Formula::Add(lhs, rhs) =>
      evaluate_int_binary(
        lhs,
        rhs,
        read,
        "Add requires Int on the left side",
        "Add requires Int on the right side",
        fn(lhs_value, rhs_value) { CellValue::from_int(lhs_value + rhs_value) },
      )
    Formula::Mul(lhs, rhs) =>
      evaluate_int_binary(
        lhs,
        rhs,
        read,
        "Mul requires Int on the left side",
        "Mul requires Int on the right side",
        fn(lhs_value, rhs_value) { CellValue::from_int(lhs_value * rhs_value) },
      )
    Formula::Eq(lhs, rhs) => evaluate_eq(lhs, rhs, read)
    Formula::Gt(lhs, rhs) =>
      evaluate_int_binary(
        lhs,
        rhs,
        read,
        "Gt requires Int on the left side",
        "Gt requires Int on the right side",
        fn(lhs_value, rhs_value) { CellValue::from_bool(lhs_value > rhs_value) },
      )
    Formula::If(condition, then_formula, else_formula) => {
      let condition_result = condition.evaluate(read)
      guard condition_result is CellResult::Ok(condition_value) else {
        return condition_result
      }

      guard condition_value is CellValue::Bool(flag) else {
        return CellResult::type_error("If requires Bool condition")
      }

      if flag {
        then_formula.evaluate(read)
      } else {
        else_formula.evaluate(read)
      }
    }
  }
}

///|
fn evaluate_int_binary(
  lhs : Formula,
  rhs : Formula,
  read : (CellId) -> CellResult,
  left_type_error : String,
  right_type_error : String,
  combine : (Int, Int) -> CellValue,
) -> CellResult {
  let left_result = lhs.evaluate(read)
  guard left_result is CellResult::Ok(left_value) else { return left_result }
  let lhs_value = match left_value {
    Int(value) => value
    _ => return CellResult::type_error(left_type_error)
  }

  let right_result = rhs.evaluate(read)
  guard right_result is CellResult::Ok(right_value) else { return right_result }
  let rhs_value = match right_value {
    Int(value) => value
    _ => return CellResult::type_error(right_type_error)
  }

  CellResult::ok(combine(lhs_value, rhs_value))
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
    Formula::Ref(cell_id) => if !refs.contains(cell_id) { refs.push(cell_id) }
    Formula::Add(lhs, rhs) => collect_binary_refs(lhs, rhs, refs)
    Formula::Mul(lhs, rhs) => collect_binary_refs(lhs, rhs, refs)
    Formula::Eq(lhs, rhs) => collect_binary_refs(lhs, rhs, refs)
    Formula::Gt(lhs, rhs) => collect_binary_refs(lhs, rhs, refs)
    Formula::If(condition, then_formula, else_formula) => {
      condition.collect_refs(refs)
      then_formula.collect_refs(refs)
      else_formula.collect_refs(refs)
    }
  }
}

///|
fn collect_binary_refs(
  lhs : Formula,
  rhs : Formula,
  refs : Array[CellId],
) -> Unit {
  lhs.collect_refs(refs)
  rhs.collect_refs(refs)
}

///|
fn evaluate_eq(
  lhs : Formula,
  rhs : Formula,
  read : (CellId) -> CellResult,
) -> CellResult {
  let left = lhs.evaluate(read)
  guard left is CellResult::Ok(left_value) else { return left }

  let right = rhs.evaluate(read)
  guard right is CellResult::Ok(right_value) else { return right }

  CellResult::ok(CellValue::Bool(left_value == right_value))
}
