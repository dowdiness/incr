///|
/// Errors returned by the tiny demo formula text parser.
pub(all) enum FormulaTextParseError {
  /// The edit text was empty after trimming whitespace.
  EmptyInput
  /// A non-formula input or integer literal operand was not an `Int`.
  InvalidInteger(String)
  /// A formula operand that should name a cell was empty or malformed.
  InvalidCellReference(String)
  /// The formula shape is outside the demo grammar.
  UnsupportedFormula(String)
} derive(Eq, Debug)

///|
/// Parses one demo cell edit into a worksheet operation.
///
/// Supported text is deliberately small:
///
/// - `10` installs an integer input.
/// - `=A1` installs an integer cell-reference formula.
/// - `=A1 + 1` installs an integer addition formula.
/// - `=A1 * 2` installs an integer multiplication formula.
/// - `=if(A1 > 10, 1, 0)` installs an integer conditional formula.
pub fn parse_cell_text_op(
  target : @typed_spreadsheet.CellId,
  text : String,
) -> Result[SheetOp, FormulaTextParseError] {
  let input = text.trim()
  if input.is_empty() {
    Err(FormulaTextParseError::EmptyInput)
  } else {
    match input.strip_prefix("=") {
      Some(formula_text) => parse_formula_op(target, formula_text.trim())
      None => parse_input_op(target, input)
    }
  }
}

///|
fn parse_input_op(
  target : @typed_spreadsheet.CellId,
  input : StringView,
) -> Result[SheetOp, FormulaTextParseError] {
  match parse_int(input) {
    Ok(value) =>
      Ok(
        SheetOp::SetInput(target, @typed_spreadsheet.CellValue::from_int(value)),
      )
    Err(error) => Err(error)
  }
}

///|
fn parse_formula_op(
  target : @typed_spreadsheet.CellId,
  formula_text : StringView,
) -> Result[SheetOp, FormulaTextParseError] {
  if formula_text.is_empty() {
    Err(FormulaTextParseError::UnsupportedFormula(formula_text.to_owned()))
  } else {
    match parse_formula_expr(target, formula_text) {
      Ok(formula) =>
        Ok(
          SheetOp::SetFormulaAst(
            target,
            @typed_spreadsheet.CellType::t_int(),
            formula,
          ),
        )
      Err(error) => Err(error)
    }
  }
}

///|
fn parse_formula_expr(
  target : @typed_spreadsheet.CellId,
  formula_text : StringView,
) -> Result[@typed_spreadsheet.Formula, FormulaTextParseError] {
  match formula_text.strip_prefix("if(") {
    Some(after_if) => parse_if_formula(target, formula_text, after_if)
    None => parse_arithmetic_formula(target, formula_text)
  }
}

///|
fn parse_arithmetic_formula(
  target : @typed_spreadsheet.CellId,
  formula_text : StringView,
) -> Result[@typed_spreadsheet.Formula, FormulaTextParseError] {
  match formula_text.split_once("+") {
    Some((lhs, rhs)) =>
      parse_binary_int_formula(
        target,
        lhs,
        rhs,
        @typed_spreadsheet.Formula::add,
      )
    None =>
      match formula_text.split_once("*") {
        Some((lhs, rhs)) =>
          parse_binary_int_formula(
            target,
            lhs,
            rhs,
            @typed_spreadsheet.Formula::mul,
          )
        None =>
          parse_cell_ref_formula(target, formula_text).map_err(_ => {
            FormulaTextParseError::UnsupportedFormula(formula_text.to_owned())
          })
      }
  }
}

///|
fn parse_if_formula(
  target : @typed_spreadsheet.CellId,
  source : StringView,
  after_if : StringView,
) -> Result[@typed_spreadsheet.Formula, FormulaTextParseError] {
  guard after_if.strip_suffix(")") is Some(args_text) else {
    return Err(FormulaTextParseError::UnsupportedFormula(source.to_owned()))
  }
  match args_text.split(",").to_array() {
    [condition_text, then_text, else_text] => {
      let condition = parse_gt_condition_formula(target, condition_text)
      let then_formula = parse_int_formula(then_text)
      let else_formula = parse_int_formula(else_text)
      match (condition, then_formula, else_formula) {
        (Ok(condition), Ok(then_formula), Ok(else_formula)) =>
          Ok(
            @typed_spreadsheet.Formula::if_(
              condition, then_formula, else_formula,
            ),
          )
        (Err(error), _, _) => Err(error)
        (_, Err(error), _) => Err(error)
        (_, _, Err(error)) => Err(error)
      }
    }
    _ => Err(FormulaTextParseError::UnsupportedFormula(source.to_owned()))
  }
}

///|
fn parse_gt_condition_formula(
  target : @typed_spreadsheet.CellId,
  condition_text : StringView,
) -> Result[@typed_spreadsheet.Formula, FormulaTextParseError] {
  match condition_text.split_once(">") {
    Some((lhs, rhs)) =>
      parse_binary_int_formula(target, lhs, rhs, @typed_spreadsheet.Formula::gt)
    None =>
      Err(FormulaTextParseError::UnsupportedFormula(condition_text.to_owned()))
  }
}

///|
fn parse_binary_int_formula(
  target : @typed_spreadsheet.CellId,
  lhs : StringView,
  rhs : StringView,
  combine : (@typed_spreadsheet.Formula, @typed_spreadsheet.Formula) -> @typed_spreadsheet.Formula,
) -> Result[@typed_spreadsheet.Formula, FormulaTextParseError] {
  match (parse_cell_ref_formula(target, lhs), parse_int_formula(rhs)) {
    (Ok(left), Ok(right)) => Ok(combine(left, right))
    (Err(error), _) => Err(error)
    (_, Err(error)) => Err(error)
  }
}

///|
fn parse_cell_ref_formula(
  target : @typed_spreadsheet.CellId,
  text : StringView,
) -> Result[@typed_spreadsheet.Formula, FormulaTextParseError] {
  let address = text.trim()
  if is_a1_address(address) {
    Ok(
      @typed_spreadsheet.Formula::cell_ref(
        @typed_spreadsheet.CellId::of(target.sheet_id, address.to_owned()),
      ),
    )
  } else {
    Err(FormulaTextParseError::InvalidCellReference(address.to_owned()))
  }
}

///|
/// Returns true when `address` has the A1 shape: one or more uppercase column
/// letters followed by a positive row number with no leading zero (`A1`, `ZZ9`).
/// This rejects bare words and numbers (`hello`, `123`, `A1B`) so they surface
/// as parse errors instead of silently installing references to phantom cells.
fn is_a1_address(address : StringView) -> Bool {
  let mut letters = 0
  let mut digits = 0
  for ch in address {
    if ch is ('A'..='Z') && digits == 0 {
      letters += 1
    } else if ch is ('0'..='9') && letters > 0 {
      if digits == 0 && ch == '0' {
        return false
      }
      digits += 1
    } else {
      return false
    }
  }
  letters > 0 && digits > 0
}

///|
fn parse_int_formula(
  text : StringView,
) -> Result[@typed_spreadsheet.Formula, FormulaTextParseError] {
  match parse_int(text) {
    Ok(value) =>
      Ok(
        @typed_spreadsheet.Formula::literal(
          @typed_spreadsheet.CellValue::from_int(value),
        ),
      )
    Err(error) => Err(error)
  }
}

///|
fn parse_int(text : StringView) -> Result[Int, FormulaTextParseError] {
  let input = text.trim()
  let parsed : Result[Int, Error] = try? @string.parse_int(input)
  match parsed {
    Ok(value) => Ok(value)
    Err(_) => Err(FormulaTextParseError::InvalidInteger(input.to_owned()))
  }
}
