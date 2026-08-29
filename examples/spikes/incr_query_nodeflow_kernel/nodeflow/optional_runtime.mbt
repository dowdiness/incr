///|
priv enum OptionalInputEvaluation {
  Absent
  Unavailable
  Current(@application.NumberFormulaOutcome)
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
    match (required_evaluation, optional_evaluation) {
      (
        Some(NumberEvaluation::Current(required_outcome)),
        OptionalInputEvaluation::Absent,
      ) => {
        count.val = count.val + 1
        NumberEvaluation::Current(
          @application.evaluate_optional_offset(
            required_outcome,
            None,
            ctx.get(parameter.view()),
          ),
        )
      }
      (
        Some(NumberEvaluation::Current(required_outcome)),
        OptionalInputEvaluation::Current(optional_outcome),
      ) => {
        count.val = count.val + 1
        NumberEvaluation::Current(
          @application.evaluate_optional_offset(
            required_outcome,
            Some(optional_outcome),
            ctx.get(parameter.view()),
          ),
        )
      }
      (required_evaluation, optional_evaluation) => {
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
        NumberEvaluation::Unavailable(ReadOnlyArray::from_array(issues))
      }
    }
  }) catch {
    error => fail_runtime_setup(region, error)
  }
  RuntimeNode::OptionalOffset(
    region, parameter, required, optional, count, output,
  )
}
