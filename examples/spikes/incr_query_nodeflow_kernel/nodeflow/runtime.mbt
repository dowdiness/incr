///|
priv enum NumberEvaluation {
  Unavailable
  Current(Int)
}

///|
priv enum NumberBinding {
  Unbound
  Bound(@incr_query.View[NumberEvaluation])
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
  Boolean(@incr_query.Region, @incr_query.View[Bool])
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
}

///|
priv struct NodeflowRuntime {
  store : @incr_query.Store
  nodes : Map[Int, RuntimeNode]
  outputs : Map[PortReference, RuntimeOutput]
  closed : Ref[Bool]
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
  descriptor : NodeDescriptor,
) -> RuntimeNode raise GraphPublicationError {
  let region = store.region() catch { error => raise map_region_error(error) }
  match descriptor {
    NodeDescriptor::Number(value~) => {
      let parameter = region.source(value) catch {
        error => fail_runtime_setup(region, error)
      }
      let output = region.derived(ctx => {
        NumberEvaluation::Current(ctx.get(parameter.view()))
      }) catch {
        error => fail_runtime_setup(region, error)
      }
      RuntimeNode::Number(region, parameter, output)
    }
    NodeDescriptor::Boolean(value~) => {
      let parameter = region.source(value) catch {
        error => fail_runtime_setup(region, error)
      }
      let output = region.derived(ctx => ctx.get(parameter.view())) catch {
        error => fail_runtime_setup(region, error)
      }
      RuntimeNode::Boolean(region, output)
    }
    NodeDescriptor::Add => make_math_runtime(region, false)
    NodeDescriptor::Multiply => make_math_runtime(region, true)
  }
}

///|
fn make_math_runtime(
  region : @incr_query.Region,
  multiply : Bool,
) -> RuntimeNode raise GraphPublicationError {
  let left = region.source(NumberBinding::Unbound) catch {
    error => fail_runtime_setup(region, error)
  }
  let right = region.source(NumberBinding::Unbound) catch {
    error => fail_runtime_setup(region, error)
  }
  let compute_count = Ref(0)
  let output = region.derived(ctx => {
    match ctx.get(left.view()) {
      NumberBinding::Unbound => NumberEvaluation::Unavailable
      NumberBinding::Bound(left_view) =>
        match ctx.get(left_view) {
          NumberEvaluation::Unavailable => NumberEvaluation::Unavailable
          NumberEvaluation::Current(a) =>
            match ctx.get(right.view()) {
              NumberBinding::Unbound => NumberEvaluation::Unavailable
              NumberBinding::Bound(right_view) =>
                match ctx.get(right_view) {
                  NumberEvaluation::Unavailable => NumberEvaluation::Unavailable
                  NumberEvaluation::Current(b) => {
                    compute_count.val = compute_count.val + 1
                    NumberEvaluation::Current(
                      if multiply {
                        a * b
                      } else {
                        a + b
                      },
                    )
                  }
                }
            }
        }
    }
  }) catch {
    error => fail_runtime_setup(region, error)
  }
  if multiply {
    RuntimeNode::Multiply(region, left, right, compute_count, output)
  } else {
    RuntimeNode::Add(region, left, right, compute_count, output)
  }
}

///|
fn runtime_output(node : RuntimeNode) -> RuntimeOutput {
  match node {
    RuntimeNode::Number(_, _, view) => RuntimeOutput::Number(view)
    RuntimeNode::Boolean(_, view) => RuntimeOutput::Boolean(view)
    RuntimeNode::Add(_, _, _, _, view)
    | RuntimeNode::Multiply(_, _, _, _, view) => RuntimeOutput::Number(view)
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
    RuntimeNode::Add(_, _, _, _, _) | RuntimeNode::Multiply(_, _, _, _, _) =>
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
fn RuntimeNode::formula_compute_count(self : RuntimeNode) -> Int {
  match self {
    RuntimeNode::Add(_, _, _, count, _)
    | RuntimeNode::Multiply(_, _, _, count, _) => count.val
    RuntimeNode::Number(_, _, _) | RuntimeNode::Boolean(_, _) => 0
  }
}

///|
fn RuntimeNode::close_runtime(self : RuntimeNode) -> Unit raise GraphCloseError {
  let region = match self {
    RuntimeNode::Number(region, _, _)
    | RuntimeNode::Boolean(region, _)
    | RuntimeNode::Add(region, _, _, _, _)
    | RuntimeNode::Multiply(region, _, _, _, _) => region
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
