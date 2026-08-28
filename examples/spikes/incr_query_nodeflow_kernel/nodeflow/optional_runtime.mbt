///|
priv enum OptionalInputEvaluation {
  Absent
  Unavailable
  Current(NumberFormulaOutcome)
}

///|
/// Creates the optional-offset formula runtime.
fn make_optional_offset_runtime(
  region : @incr_query.Region,
  node : NodeReference,
  value : Int,
) -> RuntimeNode raise GraphPublicationError {
  let parameter = region.source(value) catch {
    error => fail_runtime_setup(region, error)
  }
  let required = region.source(NumberBinding::Unbound) catch {
    error => fail_runtime_setup(region, error)
  }
  let optional = region.source(NumberBinding::Unbound) catch {
    error => fail_runtime_setup(region, error)
  }
  let count = Ref(0)
  let required_ref : PortReference = {
    graph: node.graph,
    node: node.node,
    port: 0,
  }
  let optional_ref : PortReference = {
    graph: node.graph,
    node: node.node,
    port: 1,
  }
  let output = region.derived(ctx => {
    let required_evaluation = match ctx.get(required.view()) {
      NumberBinding::Unbound => None
      NumberBinding::Bound(view) => Some(ctx.get(view))
    }
    let optional_evaluation = match ctx.get(optional.view()) {
      NumberBinding::Unbound => OptionalInputEvaluation::Absent
      NumberBinding::Bound(view) =>
        match ctx.get(view) {
          NumberEvaluation::Unavailable(_) =>
            OptionalInputEvaluation::Unavailable
          NumberEvaluation::Current(value) =>
            OptionalInputEvaluation::Current(value)
        }
    }
    let issues : Array[EvaluationIssue] = []
    match required_evaluation {
      None => issues.push(EvaluationIssue::InputWaiting(required_ref))
      Some(NumberEvaluation::Unavailable(_)) =>
        issues.push(EvaluationIssue::BlockedEvaluation(required_ref))
      Some(NumberEvaluation::Current(_)) => ()
    }
    if optional_evaluation is OptionalInputEvaluation::Unavailable {
      issues.push(EvaluationIssue::BlockedEvaluation(optional_ref))
    }
    if !issues.is_empty() {
      NumberEvaluation::Unavailable(ReadOnlyArray::from_array(issues))
    } else {
      let required_outcome = match required_evaluation {
        Some(NumberEvaluation::Current(outcome)) => outcome
        _ => abort("required input unexpectedly unavailable")
      }
      let optional_outcome = match optional_evaluation {
        OptionalInputEvaluation::Absent => NumberFormulaOutcome::Success(0)
        OptionalInputEvaluation::Current(outcome) => outcome
        Unavailable => abort("optional input unexpectedly unavailable")
      }
      match (required_outcome, optional_outcome) {
        (NumberFormulaOutcome::Failure(error), _) =>
          NumberEvaluation::Current(NumberFormulaOutcome::Failure(error))
        (_, NumberFormulaOutcome::Failure(error)) =>
          NumberEvaluation::Current(NumberFormulaOutcome::Failure(error))
        (NumberFormulaOutcome::Success(value), Success(offset)) => {
          count.val = count.val + 1
          NumberEvaluation::Current(
            NumberFormulaOutcome::Success(
              value + offset + ctx.get(parameter.view()),
            ),
          )
        }
      }
    }
  }) catch {
    error => fail_runtime_setup(region, error)
  }
  RuntimeNode::OptionalOffset(
    region, parameter, required, optional, count, output,
  )
}
