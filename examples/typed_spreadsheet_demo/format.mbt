///|
/// Formats a demo worksheet operation for text, JSON, and Web presentation.
pub fn format_op(operation : SheetOp) -> String {
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
/// Formats the operation-specific outcome returned by a demo step.
pub fn format_outcome(outcome : OpOutcome) -> String {
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
/// Formats one inspection snapshot for CLI text output.
pub fn format_snapshot(snapshot : @typed_spreadsheet.CellSnapshot) -> String {
  if snapshot.present {
    let kind_text = match snapshot.kind {
      Some(kind) => format_cell_kind(kind)
      None => "unknown"
    }
    let result_text = format_cell_result(snapshot.result)
    let shape = format_dependency_shape(snapshot.dependency_shape)
    let deps = format_cell_ids(snapshot.installed_dependencies)
    let refs = format_cell_ids(snapshot.static_references)
    let dynamic_deps = format_cell_ids(snapshot.last_dynamic_dependencies)
    "\{kind_text} \{result_text} shape=\{shape} deps=\{deps} refs=\{refs} dyn=\{dynamic_deps}"
  } else {
    let result_text = format_cell_result(snapshot.result)
    "missing \{result_text}"
  }
}

///|
/// Formats the static kind of a typed spreadsheet cell.
fn format_cell_kind(kind : @typed_spreadsheet.CellKind) -> String {
  match kind {
    Input => "input"
    Formula => "formula"
  }
}

///|
/// Formats a formula dependency-shape classification.
pub fn format_dependency_shape(
  shape : @typed_spreadsheet.FormulaDependencyShape?,
) -> String {
  match shape {
    None => "none"
    Some(Applicative) => "applicative"
    Some(Selective) => "selective"
    Some(Dynamic) => "dynamic"
  }
}

///|
/// Formats cell ids as a bracketed, comma-separated list.
pub fn format_cell_ids(ids : Array[@typed_spreadsheet.CellId]) -> String {
  if ids.length() == 0 {
    "[]"
  } else {
    let values = ids.map(id => cell_id_to_string(id)).join(", ")
    "[\{values}]"
  }
}

///|
/// Converts cell ids to address strings for JSON/ViewModel arrays.
pub fn cell_id_strings(ids : Array[@typed_spreadsheet.CellId]) -> Array[String] {
  ids.map(id => cell_id_to_string(id))
}

///|
/// Formats a cell id using its sheet-local address.
pub fn cell_id_to_string(id : @typed_spreadsheet.CellId) -> String {
  id.address
}

///|
/// Formats a demo formula AST.
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
/// Formats a typed spreadsheet cell value with its variant name.
fn format_cell_value(value : @typed_spreadsheet.CellValue) -> String {
  repr(value)
}

///|
/// Formats a typed spreadsheet cell result with its variant name.
pub fn format_cell_result(result : @typed_spreadsheet.CellResult) -> String {
  repr(result)
}

///|
/// Formats a worksheet operation error with its variant name.
fn format_worksheet_error(error : @typed_spreadsheet.WorksheetError) -> String {
  repr(error)
}

///|
/// Returns the JSON/ViewModel kind string for a snapshot.
pub fn snapshot_kind(snapshot : @typed_spreadsheet.CellSnapshot) -> String {
  if !snapshot.present {
    "missing"
  } else {
    match snapshot.kind {
      Some(kind) => format_cell_kind(kind)
      None => "unknown"
    }
  }
}
