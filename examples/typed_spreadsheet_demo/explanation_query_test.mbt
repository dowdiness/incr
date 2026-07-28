///|
test "explain cell returns the formula and active observed inputs" {
  let answer = match explain_cell(explanation_test_context(), "B1") {
    Ok(answer) => answer
    Err(_) => abort("expected B1 to be inside the observed region")
  }

  inspect(answer.subject, content="B1")
  inspect(answer.result.repr, content="Int(11)")
  match answer.formula {
    Some(formula) => inspect(formula.text, content="=A1 + 1")
    None => abort("expected formula metadata")
  }
  let active = answer.active_inputs
  inspect(active.length(), content="1")
  inspect(active[0].id, content="A1")
  inspect(active[0].observed, content="true")
  match active[0].result {
    Some(result) => inspect(result.repr, content="Int(10)")
    None => abort("expected observed input result")
  }
  inspect(answer.inactive_inputs.length(), content="0")
}

///|
test "explain last change keeps engine trace secondary to selected evidence" {
  let base = explanation_test_context()
  let context = {
    ..base,
    latest_trace: Some({
      edit: "B1 ← =A1 + 2",
      outcome: "Ok(())",
      recomputed: ["B1"],
      changed: ["B1"],
      unchanged: [],
    }),
    latest_evidence: Some({
      edit: "B1 ← =A1 + 2",
      outcome: "Ok(())",
      cells: [
        {
          id: "B1",
          classification: "changed",
          before_kind: "formula",
          before_result_status: "ok",
          before_result: "Ok(Int(11))",
          after_kind: "formula",
          after_result_status: "ok",
          after_result: "Ok(Int(12))",
        },
      ],
    }),
  }
  let answer = match explain_last_change(context, "B1") {
    Some(answer) => answer
    None => abort("expected latest change facts")
  }

  inspect(answer.subject, content="B1")
  inspect(answer.edit, content="B1 ← =A1 + 2")
  match answer.evidence {
    Some(evidence) => {
      inspect(evidence.classification, content="changed")
      inspect(evidence.before_result, content="Int(11)")
      inspect(evidence.after_result, content="Int(12)")
    }
    None => abort("expected selected-cell evidence")
  }
  inspect(answer.trace.recomputed.length(), content="1")
  inspect(answer.trace.recomputed[0], content="B1")
  inspect(answer.trace.changed.length(), content="1")
  inspect(answer.trace.changed[0], content="B1")
}

///|
test "explain cell separates active and inactive conditional references" {
  let base = explanation_test_context()
  let focus = {
    ..base.cells[0],
    static_references: ["A1", "C1"],
    last_dynamic_dependencies: ["A1"],
  }
  let context = {
    ..base,
    cells: [
      focus,
      base.cells[1],
      explanation_test_cell("C1", "20", "input", "Int(20)", [], [], None),
    ],
  }
  let first = explain_cell(context, "B1").unwrap()
  inspect(first.active_inputs[0].id, content="A1")
  inspect(first.inactive_inputs[0].id, content="C1")

  let switched = {
    ..context,
    cells: [{ ..focus, last_dynamic_dependencies: ["C1"] }, ..context.cells[1:]],
  }
  let second = explain_cell(switched, "B1").unwrap()
  inspect(second.active_inputs[0].id, content="C1")
  inspect(second.inactive_inputs[0].id, content="A1")
}

///|
test "explain cell covers inputs, errors, and references outside the region" {
  let base = explanation_test_context()
  let input = explain_cell(base, "A1").unwrap()
  inspect(input.kind, content="input")
  inspect(input.active_inputs.length(), content="0")
  inspect(input.formula is None, content="true")

  let error_context = {
    ..base,
    cells: [
      {
        ..base.cells[0],
        result: {
          status: "type_error",
          value: None,
          error: Some("Add requires Int on the left side"),
          repr: "TypeError(Add requires Int on the left side)",
        },
        static_references: ["Z9"],
        last_dynamic_dependencies: ["Z9"],
      },
      base.cells[1],
    ],
  }
  let error = explain_cell(error_context, "B1").unwrap()
  inspect(error.result.status, content="type_error")
  inspect(error.active_inputs[0].id, content="Z9")
  inspect(error.active_inputs[0].observed, content="false")
  inspect(error.active_inputs[0].result is None, content="true")
}

///|
test "explanation queries report bounded absence without inventing facts" {
  let context = explanation_test_context()
  match explain_cell(context, "Z9") {
    Err(CellOutsideObservedRegion(cell)) => inspect(cell, content="Z9")
    Ok(_) => abort("expected an out-of-region error")
  }
  inspect(explain_last_change(context, "B1") is None, content="true")

  let outside_history = {
    ..context,
    latest_trace: Some({
      edit: "Z9 ← 1",
      outcome: "Ok(Int(1))",
      recomputed: [],
      changed: [],
      unchanged: [],
    }),
    latest_evidence: Some({
      edit: "Z9 ← 1",
      outcome: "Ok(Int(1))",
      cells: [
        {
          id: "Z9",
          classification: "changed",
          before_kind: "missing",
          before_result_status: "missing",
          before_result: "Ok(Blank)",
          after_kind: "input",
          after_result_status: "ok",
          after_result: "Ok(Int(1))",
        },
      ],
    }),
  }
  inspect(explain_last_change(outside_history, "Z9") is None, content="true")
}

///|
test "explain cell is deterministic and owns its bounded scope" {
  let context = explanation_test_context()
  let first = explain_cell(context, "B1").unwrap()
  let second = explain_cell(context, "B1").unwrap()
  inspect(
    first.to_json().stringify() == second.to_json().stringify(),
    content="true",
  )

  context.region[0] = "mutated-by-caller"
  inspect(first.scope.region[0], content="B1")
}

///|
fn explanation_test_context() -> AiContextSnapshot {
  {
    schema_version: 1,
    selected_cell: "B1",
    max_cells: 8,
    truncated: false,
    region: ["B1", "A1"],
    cells: [
      explanation_test_cell(
        "B1",
        "=A1 + 1",
        "formula",
        "Int(11)",
        ["A1"],
        ["A1"],
        Some({
          text: "=A1 + 1",
          ast_status: "ok",
          shape: Some("Add(Ref(A1), Literal(Int(1)))"),
          error: None,
        }),
      ),
      explanation_test_cell("A1", "10", "input", "Int(10)", [], [], None),
    ],
    latest_trace: None,
    latest_evidence: None,
  }
}

///|
fn explanation_test_cell(
  id : String,
  committed_text : String,
  kind : String,
  repr : String,
  static_references : Array[String],
  last_dynamic_dependencies : Array[String],
  formula : AiContextFormula?,
) -> AiContextCell {
  {
    id,
    committed_text,
    draft_text: committed_text,
    draft_dirty: false,
    present: true,
    kind,
    result: { status: "ok", value: None, error: None, repr },
    dependency_shape: "applicative",
    installed_dependencies: [],
    static_references,
    last_dynamic_dependencies,
    formula,
  }
}
