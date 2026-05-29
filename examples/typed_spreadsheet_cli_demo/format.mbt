///|
fn format_op(operation : @demo.SheetOp) -> String {
  match operation {
    SetInput(id, value) => {
      let id_text = cell_id_to_string(id)
      let value_text = format_cell_value(value)
      "SetInput \{id_text} = \{value_text}"
    }
    SetFormulaAst(id, declared, formula) => {
      let id_text = cell_id_to_string(id)
      let type_text = declared.to_string()
      let formula_text = format_formula(formula)
      "SetFormulaAst \{id_text} : \{type_text} = \{formula_text}"
    }
    Delete(id) => {
      let id_text = cell_id_to_string(id)
      "Delete \{id_text}"
    }
  }
}

///|
fn format_outcome(outcome : @demo.OpOutcome) -> String {
  match outcome {
    SetInput(result) => format_cell_result(result)
    SetFormulaAst(result) =>
      match result {
        Ok(_) => "Ok(())"
        Err(error) => {
          let error_text = format_worksheet_error(error)
          "Err(\{error_text})"
        }
      }
    Delete(result) => format_cell_result(result)
  }
}

///|
fn format_snapshot(snapshot : @typed_spreadsheet.CellSnapshot) -> String {
  if snapshot.present {
    let kind_text = match snapshot.kind {
      Some(kind) => format_cell_kind(kind)
      None => "unknown"
    }
    let result_text = format_cell_result(snapshot.result)
    let deps = format_cell_ids(snapshot.installed_dependencies)
    let refs = format_cell_ids(snapshot.static_references)
    "\{kind_text} \{result_text} deps=\{deps} refs=\{refs}"
  } else {
    let result_text = format_cell_result(snapshot.result)
    "missing \{result_text}"
  }
}

///|
fn format_cell_kind(kind : @typed_spreadsheet.CellKind) -> String {
  match kind {
    Input => "input"
    Formula => "formula"
  }
}

///|
fn format_cell_ids(ids : Array[@typed_spreadsheet.CellId]) -> String {
  if ids.length() == 0 {
    "[]"
  } else {
    let values = ids.map(id => cell_id_to_string(id)).join(", ")
    "[\{values}]"
  }
}

///|
fn cell_id_to_string(id : @typed_spreadsheet.CellId) -> String {
  id.address
}

///|
fn format_formula(formula : @typed_spreadsheet.Formula) -> String {
  match formula {
    Literal(value) => format_cell_value(value)
    Ref(id) => cell_id_to_string(id)
    Add(lhs, rhs) => {
      let left = format_formula(lhs)
      let right = format_formula(rhs)
      "(\{left} + \{right})"
    }
    Mul(lhs, rhs) => {
      let left = format_formula(lhs)
      let right = format_formula(rhs)
      "(\{left} * \{right})"
    }
    Eq(lhs, rhs) => {
      let left = format_formula(lhs)
      let right = format_formula(rhs)
      "(\{left} == \{right})"
    }
    Gt(lhs, rhs) => {
      let left = format_formula(lhs)
      let right = format_formula(rhs)
      "(\{left} > \{right})"
    }
    If(condition, then_formula, else_formula) => {
      let condition_text = format_formula(condition)
      let then_text = format_formula(then_formula)
      let else_text = format_formula(else_formula)
      "if \{condition_text} then \{then_text} else \{else_text}"
    }
  }
}

///|
fn format_cell_value(value : @typed_spreadsheet.CellValue) -> String {
  repr(value)
}

///|
fn format_cell_result(result : @typed_spreadsheet.CellResult) -> String {
  repr(result)
}

///|
fn format_worksheet_error(error : @typed_spreadsheet.WorksheetError) -> String {
  repr(error)
}
