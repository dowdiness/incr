///|
priv enum NumberEvaluation {
  Unavailable(ReadOnlyArray[EvaluationIssue])
  Current(@application.NumberFormulaOutcome)
}

///|
priv enum NumberBinding {
  Unbound
  Bound(@incr_query.View[NumberEvaluation])
}

///|
priv enum DisplayActionPreparation {
  Unavailable(ReadOnlyArray[ActionInputIssue])
  Prepared(@application.NumberFormulaOutcome)
}

///|
priv enum RuntimeOutput {
  Number(@incr_query.View[NumberEvaluation])
  Boolean(@incr_query.View[Bool])
}

///|
priv enum RuntimeNode {
  Number(
    @incr_query.Region,
    @incr_query.Source[Int],
    @incr_query.View[NumberEvaluation]
  )
  Boolean(@incr_query.Region, @incr_query.Source[Bool], @incr_query.View[Bool])
  Add(
    @incr_query.Region,
    @incr_query.Source[NumberBinding],
    @incr_query.Source[NumberBinding],
    Ref[Int],
    @incr_query.View[NumberEvaluation]
  )
  Multiply(
    @incr_query.Region,
    @incr_query.Source[NumberBinding],
    @incr_query.Source[NumberBinding],
    Ref[Int],
    @incr_query.View[NumberEvaluation]
  )
  SafeDivide(
    @incr_query.Region,
    @incr_query.Source[NumberBinding],
    @incr_query.Source[NumberBinding],
    Ref[Int],
    @incr_query.View[NumberEvaluation]
  )
  Display(
    @incr_query.Region,
    @incr_query.Source[NumberBinding],
    @incr_query.View[NumberEvaluation],
    @incr_query.View[DisplayActionPreparation],
    Ref[Int]
  )
  OptionalOffset(
    @incr_query.Region,
    @incr_query.Source[Int],
    @incr_query.Source[NumberBinding],
    @incr_query.Source[NumberBinding],
    Ref[Int],
    @incr_query.View[NumberEvaluation]
  )
}

///|
priv enum RuntimeLifecycle {
  Open
  Quarantined
  Closed
} derive(Eq)

///|
priv struct NodeflowRuntime {
  store : @incr_query.Store
  nodes : Map[Int, RuntimeNode]
  outputs : Map[PortReference, RuntimeOutput]
  lifecycle : Ref[RuntimeLifecycle]
}

///|
fn map_region_error(error : @incr_query.RegionError) -> GraphPublicationError {
  match error {
    @incr_query.RegionError::ClosedRegion(_) =>
      GraphPublicationError::RegionClosed
    @incr_query.RegionError::MutationDuringEvaluation(_) =>
      GraphPublicationError::RegionMutationDuringEvaluation
    @incr_query.RegionError::MutationDuringTransaction(_) =>
      GraphPublicationError::RegionMutationDuringTransaction
  }
}

///|
fn map_transaction_error(
  error : @incr_query.TransactionError,
) -> GraphPublicationError {
  match error {
    @incr_query.TransactionError::CrossStore(_) =>
      GraphPublicationError::ReadCrossStore
    @incr_query.TransactionError::ClosedRegion(_) =>
      GraphPublicationError::RegionClosed
    @incr_query.TransactionError::ExpiredTransaction(_) =>
      GraphPublicationError::ReadExpiredContext
    @incr_query.TransactionError::TransactionDuringEvaluation(_) =>
      GraphPublicationError::RegionMutationDuringEvaluation
    @incr_query.TransactionError::NestedTransaction(_) =>
      GraphPublicationError::RegionMutationDuringTransaction
  }
}

///|
fn[T] fail_runtime_setup(
  region : @incr_query.Region,
  error : @incr_query.RegionError,
) -> T raise GraphPublicationError {
  region.close() catch {
    close_error => raise map_region_error(close_error)
  }
  raise map_region_error(error)
}

///|
fn make_runtime_node(
  store : @incr_query.Store,
  node : NodeReference,
  descriptor : @application.NodeDescriptor,
) -> RuntimeNode raise GraphPublicationError {
  let region = store.region() catch { error => raise map_region_error(error) }
  match descriptor {
    @application.NodeDescriptor::Number(value~) => {
      let parameter = region.source(value) catch {
        error => fail_runtime_setup(region, error)
      }
      let output = region.derived(ctx => {
        NumberEvaluation::Current(
          @application.NumberFormulaOutcome::Success(ctx.get(parameter.view())),
        )
      }) catch {
        error => fail_runtime_setup(region, error)
      }
      RuntimeNode::Number(region, parameter, output)
    }
    @application.NodeDescriptor::Boolean(value~) => {
      let parameter = region.source(value) catch {
        error => fail_runtime_setup(region, error)
      }
      let output = region.derived(ctx => ctx.get(parameter.view())) catch {
        error => fail_runtime_setup(region, error)
      }
      RuntimeNode::Boolean(region, parameter, output)
    }
    @application.NodeDescriptor::Add => make_math_runtime(region, node, 0)
    @application.NodeDescriptor::Multiply => make_math_runtime(region, node, 1)
    @application.NodeDescriptor::SafeDivide =>
      make_math_runtime(region, node, 2)
    @application.NodeDescriptor::Display => make_display_runtime(region, node)
    @application.NodeDescriptor::OptionalOffset(value~) =>
      make_optional_offset_runtime(region, node, value)
  }
}

///|
fn make_display_runtime(
  region : @incr_query.Region,
  node : NodeReference,
) -> RuntimeNode raise GraphPublicationError {
  let input = region.source(NumberBinding::Unbound) catch {
    error => fail_runtime_setup(region, error)
  }
  let compute_count = Ref(0)
  let input_reference : PortReference = {
    graph: node.graph,
    node: node.node,
    port: 0,
  }
  let output = region.derived(ctx => {
    match ctx.get(input.view()) {
      NumberBinding::Unbound =>
        NumberEvaluation::Unavailable(
          ReadOnlyArray::from_array([
            EvaluationIssue::InputWaiting(input_reference),
          ]),
        )
      NumberBinding::Bound(view) =>
        match ctx.get(view) {
          NumberEvaluation::Unavailable(_) =>
            NumberEvaluation::Unavailable(
              ReadOnlyArray::from_array([
                EvaluationIssue::BlockedEvaluation(input_reference),
              ]),
            )
          NumberEvaluation::Current(outcome) =>
            NumberEvaluation::Current(outcome)
        }
    }
  }) catch {
    error => fail_runtime_setup(region, error)
  }
  let action_preparation = region.derived(ctx => {
    match ctx.get(input.view()) {
      NumberBinding::Unbound =>
        DisplayActionPreparation::Unavailable(
          ReadOnlyArray::from_array([ActionInputIssue::Unbound(input_reference)]),
        )
      NumberBinding::Bound(view) =>
        match ctx.get(view) {
          NumberEvaluation::Unavailable(_) =>
            DisplayActionPreparation::Unavailable(
              ReadOnlyArray::from_array([
                ActionInputIssue::ValueUnavailable(input_reference),
              ]),
            )
          NumberEvaluation::Current(outcome) =>
            DisplayActionPreparation::Prepared(outcome)
        }
    }
  }) catch {
    error => fail_runtime_setup(region, error)
  }
  RuntimeNode::Display(region, input, output, action_preparation, compute_count)
}

///|
fn make_math_runtime(
  region : @incr_query.Region,
  node : NodeReference,
  operation : Int,
) -> RuntimeNode raise GraphPublicationError {
  let left = region.source(NumberBinding::Unbound) catch {
    error => fail_runtime_setup(region, error)
  }
  let right = region.source(NumberBinding::Unbound) catch {
    error => fail_runtime_setup(region, error)
  }
  let compute_count = Ref(0)
  let output = region.derived(ctx => {
    let left_evaluation = match ctx.get(left.view()) {
      NumberBinding::Unbound => None
      NumberBinding::Bound(view) => Some(ctx.get(view))
    }
    let right_evaluation = match ctx.get(right.view()) {
      NumberBinding::Unbound => None
      NumberBinding::Bound(view) => Some(ctx.get(view))
    }
    match (left_evaluation, right_evaluation) {
      (
        Some(NumberEvaluation::Current(left)),
        Some(NumberEvaluation::Current(right)),
      ) => {
        compute_count.val = compute_count.val + 1
        let result = if operation == 0 {
          @application.evaluate_add(left, right)
        } else if operation == 1 {
          @application.evaluate_multiply(left, right)
        } else {
          @application.evaluate_safe_divide(left, right)
        }
        NumberEvaluation::Current(result)
      }
      (left_evaluation, right_evaluation) => {
        let issues : Array[EvaluationIssue] = []
        match left_evaluation {
          None =>
            issues.push(
              EvaluationIssue::InputWaiting({
                graph: node.graph,
                node: node.node,
                port: 0,
              }),
            )
          Some(NumberEvaluation::Unavailable(_)) =>
            issues.push(
              EvaluationIssue::BlockedEvaluation({
                graph: node.graph,
                node: node.node,
                port: 0,
              }),
            )
          Some(NumberEvaluation::Current(_)) => ()
        }
        match right_evaluation {
          None =>
            issues.push(
              EvaluationIssue::InputWaiting({
                graph: node.graph,
                node: node.node,
                port: 1,
              }),
            )
          Some(NumberEvaluation::Unavailable(_)) =>
            issues.push(
              EvaluationIssue::BlockedEvaluation({
                graph: node.graph,
                node: node.node,
                port: 1,
              }),
            )
          Some(NumberEvaluation::Current(_)) => ()
        }
        NumberEvaluation::Unavailable(ReadOnlyArray::from_array(issues))
      }
    }
  }) catch {
    error => fail_runtime_setup(region, error)
  }
  if operation == 0 {
    RuntimeNode::Add(region, left, right, compute_count, output)
  } else if operation == 1 {
    RuntimeNode::Multiply(region, left, right, compute_count, output)
  } else {
    RuntimeNode::SafeDivide(region, left, right, compute_count, output)
  }
}

///|
fn runtime_output(node : RuntimeNode) -> RuntimeOutput {
  match node {
    RuntimeNode::Number(_, _, view) => RuntimeOutput::Number(view)
    RuntimeNode::Boolean(_, _, view) => RuntimeOutput::Boolean(view)
    RuntimeNode::Add(_, _, _, _, view)
    | RuntimeNode::Multiply(_, _, _, _, view)
    | RuntimeNode::SafeDivide(_, _, _, _, view)
    | RuntimeNode::Display(_, _, view, _, _)
    | RuntimeNode::OptionalOffset(_, _, _, _, _, view) =>
      RuntimeOutput::Number(view)
  }
}

///|
fn RuntimeNode::runtime_binding(
  self : RuntimeNode,
  port : Int,
  target : BindingTarget,
  outputs : Map[PortReference, RuntimeOutput],
) -> (Int, NumberBinding)? {
  match self {
    RuntimeNode::Add(_, _, _, _, _)
    | RuntimeNode::Multiply(_, _, _, _, _)
    | RuntimeNode::SafeDivide(_, _, _, _, _)
    | RuntimeNode::Display(_, _, _, _, _)
    | RuntimeNode::OptionalOffset(_, _, _, _, _, _) =>
      match target {
        BindingTarget::Unbound => Some((port, NumberBinding::Unbound))
        BindingTarget::Bound(provider) =>
          match outputs.get(provider) {
            Some(RuntimeOutput::Number(view)) =>
              Some((port, NumberBinding::Bound(view)))
            _ => None
          }
      }
    _ => None
  }
}

///|
#warnings("-unused_value")
fn RuntimeNode::record_invocation(self : RuntimeNode) -> Unit {
  match self {
    RuntimeNode::Display(_, _, _, _, count) => count.val = count.val + 1
    _ => ()
  }
}

///|
#warnings("-unused_value")
fn RuntimeNode::formula_compute_count(self : RuntimeNode) -> Int {
  match self {
    RuntimeNode::Add(_, _, _, count, _)
    | RuntimeNode::Multiply(_, _, _, count, _)
    | RuntimeNode::SafeDivide(_, _, _, count, _) => count.val
    RuntimeNode::OptionalOffset(_, _, required, optional, count, _) => {
      ignore(required)
      ignore(optional)
      count.val
    }
    RuntimeNode::Display(_, _, _, _, _)
    | RuntimeNode::Number(_, _, _)
    | RuntimeNode::Boolean(_, _, _) => 0
  }
}

///|
#warnings("-unused_value")
fn RuntimeNode::action_invocation_count(self : RuntimeNode) -> Int {
  match self {
    RuntimeNode::Display(_, _, _, _, count) => count.val
    _ => 0
  }
}

///|
fn RuntimeNode::close_runtime(self : RuntimeNode) -> Unit raise GraphCloseError {
  let region = match self {
    RuntimeNode::Number(region, _, _)
    | RuntimeNode::Boolean(region, _, _)
    | RuntimeNode::Add(region, _, _, _, _)
    | RuntimeNode::Multiply(region, _, _, _, _)
    | RuntimeNode::SafeDivide(region, _, _, _, _)
    | RuntimeNode::Display(region, _, _, _, _)
    | RuntimeNode::OptionalOffset(region, _, _, _, _, _) => region
  }
  region.close() catch {
    @incr_query.RegionError::ClosedRegion(_) =>
      raise GraphCloseError::RegionClosed
    @incr_query.RegionError::MutationDuringEvaluation(_) =>
      raise GraphCloseError::RegionMutationDuringEvaluation
    @incr_query.RegionError::MutationDuringTransaction(_) =>
      raise GraphCloseError::RegionMutationDuringTransaction
  }
}
