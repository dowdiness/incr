///|
/// An opaque aggregate owning one Semantic Graph and its execution domain.
pub struct Nodeflow {
  priv mut state : GraphState
  priv runtime : NodeflowRuntime
}

///|
let next_graph_ordinal : Ref[Int] = Ref(1)

///|
fn next_graph_id() -> Int {
  let result = next_graph_ordinal.val
  next_graph_ordinal.val = result + 1
  result
}

///|
/// Creates an empty graph with a fresh process-local Graph identity.
pub fn Nodeflow::empty() -> Nodeflow {
  let store = @incr_query.Store::Store()
  let graph = next_graph_id()
  {
    state: { graph, next_node: 0, nodes: Map([]) },
    runtime: { store, nodes: Map([]), outputs: Map([]), closed: Ref(false) },
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
  Number(Int)
  Boolean(Bool)
  Unavailable
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
        @incr_query.ReadError::Cycle(_) => return Ok(ReadResult::Unavailable)
        @incr_query.ReadError::ExpiredQueryContext(_) =>
          return Err(ReadFailure::ExpiredContext)
        @incr_query.ReadError::ReentrantRootGet(_) =>
          return Err(ReadFailure::ReentrantRoot)
        @incr_query.ReadError::GetDuringTransaction(_) =>
          return Err(ReadFailure::DuringTransaction)
      }
      match evaluation {
        NumberEvaluation::Unavailable => Ok(ReadResult::Unavailable)
        NumberEvaluation::Current(value) => Ok(ReadResult::Number(value))
      }
    }
    RuntimeOutput::Boolean(view) =>
      Ok(ReadResult::Boolean(self.runtime.store.get(view))) catch {
        @incr_query.ReadError::CrossStore(_) => Err(ReadFailure::CrossStore)
        @incr_query.ReadError::ClosedRegion(_) => Err(ReadFailure::ClosedRegion)
        @incr_query.ReadError::Cycle(_) => Ok(ReadResult::Unavailable)
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
  let seen : Set[PortReference] = Set([])
  let observations : Array[(PortReference, OutputObservation)] = []
  for port in demand.ports {
    if !seen.contains(port) {
      seen.add(port)
      match self.runtime.outputs.get(port) {
        None => observations.push((port, Missing))
        Some(output) =>
          match self.read_output(output) {
            Err(error) => return Err(error)
            Ok(ReadResult::Number(value)) =>
              observations.push((port, Current(OutputData::Number(value))))
            Ok(ReadResult::Boolean(value)) =>
              observations.push((port, Current(OutputData::Boolean(value))))
            Ok(ReadResult::Unavailable) =>
              observations.push((port, Unavailable))
          }
      }
    }
  }
  Ok({ observations: ReadOnlyArray::from_array(observations) })
}

///|
/// Observes requested Outputs once from the committed graph.
pub fn Nodeflow::snapshot(
  self : Nodeflow,
  demand : ObservationDemand,
) -> SurfaceSnapshot raise SurfaceReadError {
  if self.runtime.closed.val {
    raise SurfaceReadError::ClosedNodeflow
  }
  match self.snapshot_core(demand) {
    Ok(snapshot) => snapshot
    Err(error) => raise map_read_failure(error)
  }
}

///|
fn Nodeflow::stage_edit(
  self : Nodeflow,
  edit : GraphEdit,
) -> Unit raise GraphPublicationError {
  match edit {
    GraphEdit::SetNumberParameter(node~, value~) =>
      match self.runtime.nodes.get(node.node) {
        Some(RuntimeNode::Number(_, parameter, _)) => {
          let result : Result[Unit, Unit] = self.runtime.store.transaction(tx => {
            tx.set(parameter, value)
            Ok(())
          }) catch {
            error => raise map_transaction_error(error)
          }
          ignore(result)
        }
        _ => ()
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
            | RuntimeNode::Multiply(_, left, right, _, _) =>
              tx.set(
                if change.target.port == 0 {
                  left
                } else {
                  right
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
  }
}

///|
/// Validates and publishes one edit; domain rejection changes nothing.
pub fn Nodeflow::apply(
  self : Nodeflow,
  edit : GraphEdit,
  demand : ObservationDemand,
) -> Result[GraphEditResult, GraphEditRejection] raise GraphPublicationError {
  if self.runtime.closed.val {
    raise GraphPublicationError::ClosedNodeflow
  }
  match self.state.apply(edit) {
    Err(rejection) => Err(rejection)
    Ok(transition) =>
      match transition.added {
        Some((node, inputs, outputs)) => {
          let runtime_node = make_runtime_node(
            self.runtime.store,
            transition.state.nodes.get(node.node).unwrap().descriptor,
          )
          let output = runtime_output(runtime_node)
          self.runtime.nodes[node.node] = runtime_node
          for port in outputs {
            self.runtime.outputs[port] = output
          }
          self.state = transition.state
          let snapshot = match self.snapshot_core(demand) {
            Ok(value) => value
            Err(error) => raise map_publication_read_failure(error)
          }
          Ok(
            GraphEditResult::Added({
              node,
              inputs: ReadOnlyArray::from_array(inputs),
              outputs: ReadOnlyArray::from_array(outputs),
              snapshot,
            }),
          )
        }
        None => {
          self.stage_edit(edit)
          self.state = transition.state
          let snapshot = match self.snapshot_core(demand) {
            Ok(value) => value
            Err(error) => raise map_publication_read_failure(error)
          }
          Ok(GraphEditResult::Changed(snapshot))
        }
      }
  }
}

///|
/// Idempotently closes every Node Region.
pub fn Nodeflow::close(self : Nodeflow) -> Unit raise GraphCloseError {
  if self.runtime.closed.val {
    return
  }
  let nodes = self.runtime.nodes.to_array()
  for _, entry in nodes {
    entry.1.close_runtime()
  }
  self.runtime.nodes.clear()
  self.runtime.outputs.clear()
  self.runtime.closed.val = true
}
