///|
/// An opaque aggregate owning one Semantic Graph and its execution domain.
pub struct Nodeflow {
  priv mut state : GraphState
  priv runtime : NodeflowRuntime
}

///|
let next_graph_ordinal : Ref[Int] = Ref(1)

///|
const NODEFLOW_MAX_ACTIVE_QUERIES : UInt = 256U

///|
fn next_graph_id() -> Int {
  let result = next_graph_ordinal.val
  next_graph_ordinal.val = result + 1
  result
}

///|
fn reserve_graph_id(id : Int) -> Unit {
  if next_graph_ordinal.val <= id {
    next_graph_ordinal.val = id + 1
  }
}

///|
/// Creates an empty graph with a fresh process-local Graph identity.
pub fn Nodeflow::empty() -> Nodeflow {
  let store = @incr_query.Store::Store(
    max_active_queries=NODEFLOW_MAX_ACTIVE_QUERIES,
  )
  let graph = next_graph_id()
  {
    state: { graph, next_node: 0, nodes: Map([]) },
    runtime: {
      store,
      nodes: Map([]),
      outputs: Map([]),
      lifecycle: Ref(RuntimeLifecycle::Open),
    },
  }
}

///|
priv enum ReadFailure {
  CrossStore
  ClosedRegion
  ExpiredContext
  ReentrantRoot
  DuringTransaction
}

///|
priv enum ReadResult {
  Number(@application.NumberFormulaOutcome)
  Boolean(Bool)
  Unavailable(ReadOnlyArray[EvaluationIssue])
}

///|
fn Nodeflow::read_output(
  self : Nodeflow,
  output : RuntimeOutput,
) -> Result[ReadResult, ReadFailure] {
  match output {
    RuntimeOutput::Number(view) => {
      let evaluation = self.runtime.store.get(view) catch {
        @incr_query.ReadError::CrossStore(_) =>
          return Err(ReadFailure::CrossStore)
        @incr_query.ReadError::ClosedRegion(_) =>
          return Err(ReadFailure::ClosedRegion)
        @incr_query.ReadError::Cycle(_) =>
          return Ok(
            ReadResult::Unavailable(
              ReadOnlyArray::from_array([EvaluationIssue::CyclicEvaluation]),
            ),
          )
        @incr_query.ReadError::EvaluationLimitExceeded(_) =>
          return Ok(
            ReadResult::Unavailable(
              ReadOnlyArray::from_array([
                EvaluationIssue::EvaluationLimitExceeded,
              ]),
            ),
          )
        @incr_query.ReadError::ExpiredQueryContext(_) =>
          return Err(ReadFailure::ExpiredContext)
        @incr_query.ReadError::ReentrantRootGet(_) =>
          return Err(ReadFailure::ReentrantRoot)
        @incr_query.ReadError::GetDuringTransaction(_) =>
          return Err(ReadFailure::DuringTransaction)
      }
      match evaluation {
        NumberEvaluation::Unavailable(issues) =>
          Ok(ReadResult::Unavailable(issues))
        NumberEvaluation::Current(value) => Ok(ReadResult::Number(value))
      }
    }
    RuntimeOutput::Boolean(view) =>
      Ok(ReadResult::Boolean(self.runtime.store.get(view))) catch {
        @incr_query.ReadError::CrossStore(_) => Err(ReadFailure::CrossStore)
        @incr_query.ReadError::ClosedRegion(_) => Err(ReadFailure::ClosedRegion)
        @incr_query.ReadError::Cycle(_) =>
          Ok(
            ReadResult::Unavailable(
              ReadOnlyArray::from_array([EvaluationIssue::CyclicEvaluation]),
            ),
          )
        @incr_query.ReadError::EvaluationLimitExceeded(_) =>
          Ok(
            ReadResult::Unavailable(
              ReadOnlyArray::from_array([
                EvaluationIssue::EvaluationLimitExceeded,
              ]),
            ),
          )
        @incr_query.ReadError::ExpiredQueryContext(_) =>
          Err(ReadFailure::ExpiredContext)
        @incr_query.ReadError::ReentrantRootGet(_) =>
          Err(ReadFailure::ReentrantRoot)
        @incr_query.ReadError::GetDuringTransaction(_) =>
          Err(ReadFailure::DuringTransaction)
      }
  }
}

///|
priv enum ActionResolution {
  Missing
  Resolved(DisplayActionPreparation)
}

///|
fn Nodeflow::resolve_action(
  self : Nodeflow,
  action : ActionReference,
) -> Result[ActionResolution, ReadFailure] {
  if action.graph != self.state.graph || action.action != 0 {
    return Ok(ActionResolution::Missing)
  }
  match self.state.nodes.get(action.node) {
    Some({ descriptor: @application.NodeDescriptor::Display, .. }) =>
      match self.runtime.nodes.get(action.node) {
        Some(RuntimeNode::Display(_, _, _, preparation, _)) => {
          let resolved = self.runtime.store.get(preparation) catch {
            @incr_query.ReadError::CrossStore(_) =>
              return Err(ReadFailure::CrossStore)
            @incr_query.ReadError::ClosedRegion(_) =>
              return Err(ReadFailure::ClosedRegion)
            @incr_query.ReadError::Cycle(_) =>
              return Ok(
                ActionResolution::Resolved(
                  DisplayActionPreparation::Unavailable(
                    ReadOnlyArray::from_array([
                      ActionInputIssue::ValueUnavailable({
                        graph: action.graph,
                        node: action.node,
                        port: 0,
                      }),
                    ]),
                  ),
                ),
              )
            @incr_query.ReadError::EvaluationLimitExceeded(_) =>
              return Ok(
                ActionResolution::Resolved(
                  DisplayActionPreparation::Unavailable(
                    ReadOnlyArray::from_array([
                      ActionInputIssue::EvaluationLimitExceeded,
                    ]),
                  ),
                ),
              )
            @incr_query.ReadError::ExpiredQueryContext(_) =>
              return Err(ReadFailure::ExpiredContext)
            @incr_query.ReadError::ReentrantRootGet(_) =>
              return Err(ReadFailure::ReentrantRoot)
            @incr_query.ReadError::GetDuringTransaction(_) =>
              return Err(ReadFailure::DuringTransaction)
          }
          Ok(ActionResolution::Resolved(resolved))
        }
        _ => Ok(ActionResolution::Missing)
      }
    _ => Ok(ActionResolution::Missing)
  }
}

///|
fn action_observation(resolution : ActionResolution) -> ActionObservation {
  match resolution {
    ActionResolution::Missing => ActionObservation::Missing
    Resolved(DisplayActionPreparation::Prepared(_)) =>
      ActionObservation::Present(ActionAvailability::Available)
    Resolved(DisplayActionPreparation::Unavailable(issues)) =>
      ActionObservation::Present(ActionAvailability::Unavailable(issues))
  }
}

///|
fn map_read_failure(error : ReadFailure) -> SurfaceReadError {
  match error {
    CrossStore => SurfaceReadError::CrossStore
    ClosedRegion => SurfaceReadError::ClosedRegion
    ExpiredContext => SurfaceReadError::ExpiredContext
    ReentrantRoot => SurfaceReadError::ReentrantRoot
    DuringTransaction => SurfaceReadError::DuringTransaction
  }
}

///|
fn map_invocation_read_failure(error : ReadFailure) -> ActionInvocationError {
  match error {
    CrossStore => ActionInvocationError::CrossStore
    ClosedRegion => ActionInvocationError::ClosedRegion
    ExpiredContext => ActionInvocationError::ExpiredContext
    ReentrantRoot => ActionInvocationError::ReentrantRoot
    DuringTransaction => ActionInvocationError::DuringTransaction
  }
}

///|
fn map_publication_read_failure(error : ReadFailure) -> GraphPublicationError {
  match error {
    CrossStore => GraphPublicationError::ReadCrossStore
    ClosedRegion => GraphPublicationError::ReadClosedRegion
    ExpiredContext => GraphPublicationError::ReadExpiredContext
    ReentrantRoot => GraphPublicationError::ReadReentrantRoot
    DuringTransaction => GraphPublicationError::ReadDuringTransaction
  }
}

///|
fn Nodeflow::snapshot_core(
  self : Nodeflow,
  demand : ObservationDemand,
) -> Result[SurfaceSnapshot, ReadFailure] {
  let node_views : Array[NodeView] = []
  let port_views : Array[PortView] = []
  let parameter_views : Array[ParameterView] = []
  let action_views : Array[ActionView] = []
  let connections : Array[ConnectionView] = []
  let node_entries = self.state.nodes.to_array()
  node_entries.sort_by((a, b) => a.0.compare(b.0))
  for node_entry in node_entries {
    let node_id = node_entry.0
    let node_state = node_entry.1
    let reference : NodeReference = { graph: self.state.graph, node: node_id }
    let schema = descriptor_schema(node_state.descriptor)
    node_views.push({ node: reference, kind: schema.kind })
    for ordinal, port in schema.ports {
      let port_ref : PortReference = {
        graph: self.state.graph,
        node: node_id,
        port: ordinal,
      }
      port_views.push({
        port: port_ref,
        direction: port.direction,
        value_type: port.value_type,
        required: port.required,
      })
      if port.direction is PortDirection::Input {
        match node_state.bindings.get(port_ref) {
          Some(BindingTarget::Bound(output)) =>
            connections.push({ input: port_ref, output })
          _ => ()
        }
      }
    }
    let parameter_value = node_state.descriptor.parameter_values()
    for parameter, value in parameter_value {
      parameter_views.push({
        parameter: parameter_reference(reference, parameter),
        value,
      })
    }
    for action in 0..<schema.actions {
      action_views.push({
        action: { graph: self.state.graph, node: node_id, action },
      })
    }
  }
  let seen : Set[PortReference] = Set([])
  let observations : Array[(PortReference, OutputObservation)] = []
  let action_observations : Array[(ActionReference, ActionObservation)] = []
  let seen_actions : Set[ActionReference] = Set([])
  for request in demand.requests {
    match request {
      DemandRequest::OutputDemand(port) =>
        if !seen.contains(port) {
          seen.add(port)
          match self.runtime.outputs.get(port) {
            None => observations.push((port, Missing))
            Some(output) =>
              match self.read_output(output) {
                Err(error) => return Err(error)
                Ok(ReadResult::Number(value)) =>
                  observations.push(
                    (port, Current(@application.OutputData::Number(value))),
                  )
                Ok(ReadResult::Boolean(value)) =>
                  observations.push(
                    (port, Current(@application.OutputData::Boolean(value))),
                  )
                Ok(ReadResult::Unavailable(issues)) =>
                  observations.push((port, Unavailable(issues)))
              }
          }
        }
      DemandRequest::ActionDemand(action) =>
        if !seen_actions.contains(action) {
          seen_actions.add(action)
          match self.resolve_action(action) {
            Err(error) => return Err(error)
            Ok(resolution) =>
              action_observations.push((action, action_observation(resolution)))
          }
        }
    }
  }
  Ok({
    nodes: ReadOnlyArray::from_array(node_views),
    ports: ReadOnlyArray::from_array(port_views),
    parameters: ReadOnlyArray::from_array(parameter_views),
    actions: ReadOnlyArray::from_array(action_views),
    connections: ReadOnlyArray::from_array(connections),
    observations: ReadOnlyArray::from_array(observations),
    action_observations: ReadOnlyArray::from_array(action_observations),
  })
}

///|
/// Observes requested Outputs once from the committed graph.

///|
/// Invokes an existing Action against freshly committed inputs.
pub fn Nodeflow::invoke(
  self : Nodeflow,
  action : ActionReference,
) -> ActionInvocationOutcome raise ActionInvocationError {
  if self.runtime.lifecycle.val != RuntimeLifecycle::Open {
    raise ActionInvocationError::ClosedNodeflow
  }
  if action.graph != self.state.graph ||
    action.action != 0 ||
    self.state.nodes.get(action.node) is None {
    return ActionInvocationOutcome::Rejected(
      ActionInvocationRejection::MissingAction,
    )
  }
  match self.resolve_action(action) {
    Err(error) => raise map_invocation_read_failure(error)
    Ok(ActionResolution::Missing) =>
      ActionInvocationOutcome::Rejected(
        ActionInvocationRejection::MissingAction,
      )
    Ok(Resolved(DisplayActionPreparation::Unavailable(issues))) =>
      ActionInvocationOutcome::Unavailable(issues)
    Ok(Resolved(DisplayActionPreparation::Prepared(outcome))) => {
      self.runtime.nodes.get(action.node).unwrap().record_invocation()
      ActionInvocationOutcome::Decided(@application.display_decision(outcome))
    }
  }
}

///|
/// Returns one immutable structural and explicitly demanded value snapshot.
///
/// Empty demand still projects Semantic Graph structure without evaluating an
/// Output or Action. Closed or quarantined aggregates raise ClosedNodeflow.
pub fn Nodeflow::snapshot(
  self : Nodeflow,
  demand : ObservationDemand,
) -> SurfaceSnapshot raise SurfaceReadError {
  if self.runtime.lifecycle.val != RuntimeLifecycle::Open {
    raise SurfaceReadError::ClosedNodeflow
  }
  match self.snapshot_core(demand) {
    Ok(snapshot) => snapshot
    Err(error) => raise map_read_failure(error)
  }
}

///|
fn Nodeflow::snapshot_after_publication(
  self : Nodeflow,
  demand : ObservationDemand,
) -> SurfaceSnapshot raise GraphPublicationError {
  match self.snapshot_core(demand) {
    Ok(value) => value
    Err(error) => {
      self.runtime.lifecycle.val = RuntimeLifecycle::Quarantined
      raise map_publication_read_failure(error)
    }
  }
}

///|
fn Nodeflow::stage_removal(
  self : Nodeflow,
  unbound : Array[PortReference],
) -> Unit raise GraphPublicationError {
  let result : Result[Unit, Unit] = self.runtime.store.transaction(tx => {
    for target in unbound {
      let runtime = self.runtime.nodes.get(target.node).unwrap()
      match runtime {
        RuntimeNode::Add(_, left, right, _, _)
        | RuntimeNode::Multiply(_, left, right, _, _)
        | RuntimeNode::SafeDivide(_, left, right, _, _) =>
          tx.set(
            if target.port == 0 {
              left
            } else {
              right
            },
            NumberBinding::Unbound,
          )
        RuntimeNode::Display(_, input, _, _, _) =>
          tx.set(input, NumberBinding::Unbound)
        RuntimeNode::OptionalOffset(_, _, required, optional, _, _) =>
          tx.set(
            if target.port == 0 {
              required
            } else {
              optional
            },
            NumberBinding::Unbound,
          )
        _ => ()
      }
    }
    Ok(())
  }) catch {
    error => raise map_transaction_error(error)
  }
  ignore(result)
}

///|
fn Nodeflow::stage_edit(
  self : Nodeflow,
  edit : GraphEdit,
) -> Unit raise GraphPublicationError {
  match edit {
    GraphEdit::SetParameter(parameter~, value~) => {
      let result : Result[Unit, Unit] = self.runtime.store.transaction(tx => {
        match self.runtime.nodes.get(parameter.node) {
          Some(RuntimeNode::Number(_, source, _)) =>
            match value {
              @application.ParameterValue::Number(v) => tx.set(source, v)
              _ => ()
            }
          Some(RuntimeNode::Boolean(_, source, _)) =>
            match value {
              @application.ParameterValue::Boolean(v) => tx.set(source, v)
              _ => ()
            }
          Some(RuntimeNode::OptionalOffset(_, source, _, _, _, _)) =>
            match value {
              @application.ParameterValue::Number(v) => tx.set(source, v)
              _ => ()
            }
          _ => ()
        }
        Ok(())
      }) catch {
        error => raise map_transaction_error(error)
      }
      ignore(result)
    }
    GraphEdit::BindingChangeSet(changes~) => {
      let result : Result[Unit, Unit] = self.runtime.store.transaction(tx => {
        for change in changes {
          let runtime = self.runtime.nodes.get(change.target.node).unwrap()
          let (_, binding) = runtime
            .runtime_binding(
              change.target.port,
              change.binding,
              self.runtime.outputs,
            )
            .unwrap()
          match runtime {
            RuntimeNode::Add(_, left, right, _, _)
            | RuntimeNode::Multiply(_, left, right, _, _)
            | RuntimeNode::SafeDivide(_, left, right, _, _) =>
              tx.set(
                if change.target.port == 0 {
                  left
                } else {
                  right
                },
                binding,
              )
            RuntimeNode::Display(_, input, _, _, _) => tx.set(input, binding)
            RuntimeNode::OptionalOffset(_, _, required, optional, _, _) =>
              tx.set(
                if change.target.port == 0 {
                  required
                } else {
                  optional
                },
                binding,
              )
            _ => ()
          }
        }
        Ok(())
      }) catch {
        error => raise map_transaction_error(error)
      }
      ignore(result)
    }
    GraphEdit::AddNode(..) => ()
    GraphEdit::RemoveNodes(..) => ()
  }
}

///|
/// Validates and publishes one edit; domain rejection changes nothing.
pub fn Nodeflow::apply(
  self : Nodeflow,
  edit : GraphEdit,
  demand : ObservationDemand,
) -> Result[GraphEditResult, GraphEditRejection] raise GraphPublicationError {
  if self.runtime.lifecycle.val != RuntimeLifecycle::Open {
    raise GraphPublicationError::ClosedNodeflow
  }
  match self.state.apply(edit) {
    Err(rejection) => Err(rejection)
    Ok(transition) =>
      match transition.added {
        Some((node, inputs, outputs)) => {
          let runtime_node = make_runtime_node(
            self.runtime.store,
            node,
            transition.state.nodes.get(node.node).unwrap().descriptor,
          )
          let output = runtime_output(runtime_node)
          self.runtime.nodes[node.node] = runtime_node
          for port in outputs {
            self.runtime.outputs[port] = output
          }
          self.state = transition.state
          let snapshot = self.snapshot_after_publication(demand)
          let descriptor = transition.state.nodes.get(node.node).unwrap().descriptor
          let parameters = descriptor
            .parameter_values()
            .mapi((ordinal, _) => parameter_reference(node, ordinal))
          let actions = Array::makei(descriptor_schema(descriptor).actions, action => {
            graph: node.graph,
            node: node.node,
            action,
          })
          Ok(
            GraphEditResult::Added({
              node,
              inputs: ReadOnlyArray::from_array(inputs),
              outputs: ReadOnlyArray::from_array(outputs),
              parameters: ReadOnlyArray::from_array(parameters),
              actions: ReadOnlyArray::from_array(actions),
              snapshot,
            }),
          )
        }
        None =>
          match transition.removed {
            None => {
              self.stage_edit(edit)
              self.state = transition.state
              let snapshot = self.snapshot_after_publication(demand)
              Ok(GraphEditResult::Changed(snapshot))
            }
            Some((removed, unbound)) => {
              self.stage_removal(unbound)
              for node_id in removed {
                let runtime = self.runtime.nodes.get(node_id).unwrap()
                runtime.close_runtime() catch {
                  error => {
                    self.runtime.lifecycle.val = RuntimeLifecycle::Quarantined
                    raise match error {
                      GraphCloseError::RegionClosed =>
                        GraphPublicationError::RegionClosed
                      GraphCloseError::RegionMutationDuringEvaluation =>
                        GraphPublicationError::RegionMutationDuringEvaluation
                      GraphCloseError::RegionMutationDuringTransaction =>
                        GraphPublicationError::RegionMutationDuringTransaction
                    }
                  }
                }
              }
              for node_id in removed {
                self.runtime.nodes.remove(node_id)
              }
              let output_entries = self.runtime.outputs.to_array()
              for _, entry in output_entries {
                let (port, _) = entry
                if removed.contains(port.node) {
                  self.runtime.outputs.remove(port)
                }
              }
              self.state = transition.state
              let snapshot = self.snapshot_after_publication(demand)
              Ok(GraphEditResult::Changed(snapshot))
            }
          }
      }
  }
}

///|
/// Idempotently closes every Node Region.
pub fn Nodeflow::close(self : Nodeflow) -> Unit raise GraphCloseError {
  if self.runtime.lifecycle.val == RuntimeLifecycle::Closed {
    return
  }
  let nodes = self.state.nodes.to_array()
  nodes.sort_by((left, right) => left.0.compare(right.0))
  for _, entry in nodes {
    let (node_id, _) = entry
    errdefer {
      self.runtime.lifecycle.val = RuntimeLifecycle::Quarantined
    }
    self.runtime.nodes.get(node_id).unwrap().close_runtime()
  }
  self.runtime.nodes.clear()
  self.runtime.outputs.clear()
  self.runtime.lifecycle.val = RuntimeLifecycle::Closed
}
