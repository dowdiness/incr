///|
priv struct GraphId {
  ordinal : Int
} derive(Eq, Hash, Debug)

///|
priv struct NodeId {
  ordinal : Int
} derive(Eq, Hash, Debug)

///|
priv struct PortId {
  ordinal : Int
} derive(Eq, Hash, Debug)

///|
/// A reference to a node, including its owning graph.
pub struct NodeReference {
  priv graph : GraphId
  priv node : NodeId
} derive(Eq, Hash, Debug)

///|
/// A reference to a port, including its owning graph and node.
pub struct PortReference {
  priv graph : GraphId
  priv node : NodeId
  priv port : PortId
} derive(Eq, Hash, Debug)

///|
/// An atomic authoring request. The tracer slice supports adding one Number Node.
pub(all) enum GraphEdit {
  AddNumberNode(value~ : Int)
}

///|
/// An expected refusal decided before runtime publication begins.
pub(all) enum GraphEditRejection {
  InvalidEdit
} derive(Eq, Debug)

///|
/// Structural failures while publishing an accepted Graph Edit and its snapshot.
pub suberror GraphPublicationError {
  ClosedNodeflow
  RegionClosed
  RegionMutationDuringEvaluation
  RegionMutationDuringTransaction
  ReadCrossStore
  ReadClosedRegion
  ReadExpiredContext
  ReadReentrantRoot
  ReadDuringTransaction
} derive(Debug)

///|
/// Structural failures while producing a Surface Snapshot.
pub suberror SurfaceReadError {
  ClosedNodeflow
  CrossStore
  ClosedRegion
  ExpiredContext
  ReentrantRoot
  DuringTransaction
} derive(Debug)

///|
/// Structural failures while synchronously releasing the execution domain.
pub suberror GraphCloseError {
  RegionClosed
  RegionMutationDuringEvaluation
  RegionMutationDuringTransaction
} derive(Debug)

///|
/// Closed application-owned output data projected without a kernel View.
pub(all) enum OutputData {
  Number(Int)
} derive(Eq, Debug)

///|
/// The current result for one demanded Port Reference.
pub(all) enum OutputObservation {
  Missing
  Unavailable
  Current(OutputData)
} derive(Eq, Debug)

///|
/// An owned, ordered request for Output observations.
pub struct ObservationDemand {
  priv ports : Array[PortReference]
}

///|
/// Creates a demand that observes no Outputs.
pub fn ObservationDemand::empty() -> ObservationDemand {
  { ports: [] }
}

///|
/// Returns a fresh demand with one Port appended; snapshots deduplicate requests.
pub fn ObservationDemand::request(
  self : ObservationDemand,
  port : PortReference,
) -> ObservationDemand {
  let ports = self.ports.copy()
  ports.push(port)
  { ports, }
}

///|
/// An immutable UI-neutral projection from one committed graph state.
pub struct SurfaceSnapshot {
  priv observations : ReadOnlyArray[(PortReference, OutputObservation)]
}

///|
/// Returns immutable observations in first-request order.
pub fn SurfaceSnapshot::observations(
  self : SurfaceSnapshot,
) -> ReadOnlyArray[(PortReference, OutputObservation)] {
  self.observations
}

///|
/// Returns one observation, or Missing when the Port was not observed.
pub fn SurfaceSnapshot::observation(
  self : SurfaceSnapshot,
  port : PortReference,
) -> OutputObservation {
  for entry in self.observations {
    if entry.0 == port {
      return entry.1
    }
  }
  Missing
}

///|
/// The semantic identities and snapshot returned after successful publication.
pub struct GraphEditSuccess {
  priv node : NodeReference
  priv output : PortReference
  priv snapshot : SurfaceSnapshot
}

///|
/// Returns the added Node Reference.
pub fn GraphEditSuccess::node(self : GraphEditSuccess) -> NodeReference {
  self.node
}

///|
/// Returns the added Number Output Port Reference.
pub fn GraphEditSuccess::output(self : GraphEditSuccess) -> PortReference {
  self.output
}

///|
/// Returns the snapshot assembled after the edit was published.
pub fn GraphEditSuccess::snapshot(self : GraphEditSuccess) -> SurfaceSnapshot {
  self.snapshot
}

///|
priv struct NumberNode {
  parameter : Int
  output : PortReference
}

///|
priv struct GraphState {
  graph : GraphId
  next_node : Int
  nodes : Map[NodeId, NumberNode]
}

///|
priv struct GraphTransition {
  state : GraphState
  node : NodeReference
  output : PortReference
  value : Int
}

///|
priv enum RuntimeOutput {
  Number(@incr_query.View[Int])
}

///|
priv struct RuntimeNode {
  region : @incr_query.Region
  parameter : @incr_query.Source[Int]
  output : RuntimeOutput
}

///|
fn RuntimeNode::anchor(self : RuntimeNode) -> Unit {
  ignore(self.region)
  ignore(self.parameter)
}

///|
priv struct NodeflowRuntime {
  store : @incr_query.Store
  nodes : Map[NodeId, RuntimeNode]
  outputs : Map[PortReference, RuntimeOutput]
  closed : Ref[Bool]
}

///|
/// An opaque aggregate owning one Semantic Graph and its execution domain.
pub struct Nodeflow {
  priv mut state : GraphState
  priv runtime : NodeflowRuntime
}

///|
let next_graph_ordinal : Ref[Int] = Ref(1)

///|
fn next_graph_id() -> GraphId {
  let ordinal = next_graph_ordinal.val
  next_graph_ordinal.val = ordinal + 1
  { ordinal, }
}

///|
fn GraphState::apply(
  self : GraphState,
  edit : GraphEdit,
) -> Result[GraphTransition, GraphEditRejection] {
  match edit {
    GraphEdit::AddNumberNode(_) => {
      let node : NodeId = { ordinal: self.next_node }
      let port : PortId = { ordinal: 0 }
      let node_reference = { graph: self.graph, node }
      let output = { graph: self.graph, node, port }
      let value = match edit {
        GraphEdit::AddNumberNode(value~) => value
      }
      let nodes = self.nodes.copy()
      nodes[node] = { parameter: value, output }
      Ok({
        state: { graph: self.graph, next_node: self.next_node + 1, nodes },
        node: node_reference,
        output,
        value,
      })
    }
  }
}

///|
fn Nodeflow::create_runtime_node(
  self : Nodeflow,
  value : Int,
) -> RuntimeNode raise GraphPublicationError {
  let region = self.runtime.store.region() catch {
    @incr_query.RegionError::ClosedRegion(_) =>
      raise GraphPublicationError::RegionClosed
    @incr_query.RegionError::MutationDuringEvaluation(_) =>
      raise GraphPublicationError::RegionMutationDuringEvaluation
    @incr_query.RegionError::MutationDuringTransaction(_) =>
      raise GraphPublicationError::RegionMutationDuringTransaction
  }
  let parameter = region.source(value) catch {
    @incr_query.RegionError::ClosedRegion(_) =>
      raise GraphPublicationError::RegionClosed
    @incr_query.RegionError::MutationDuringEvaluation(_) =>
      raise GraphPublicationError::RegionMutationDuringEvaluation
    @incr_query.RegionError::MutationDuringTransaction(_) =>
      raise GraphPublicationError::RegionMutationDuringTransaction
  }
  let view = region.derived(ctx => ctx.get(parameter.view())) catch {
    @incr_query.RegionError::ClosedRegion(_) =>
      raise GraphPublicationError::RegionClosed
    @incr_query.RegionError::MutationDuringEvaluation(_) =>
      raise GraphPublicationError::RegionMutationDuringEvaluation
    @incr_query.RegionError::MutationDuringTransaction(_) =>
      raise GraphPublicationError::RegionMutationDuringTransaction
  }
  { region, parameter, output: RuntimeOutput::Number(view) }
}

///|
/// Creates an empty graph with a fresh process-local Graph Identity.
pub fn Nodeflow::empty() -> Nodeflow {
  let store = @incr_query.Store::Store()
  let graph : GraphId = next_graph_id()
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
priv enum OutputRead {
  Value(Int)
  Cycle
  Failure(ReadFailure)
}

///|
fn Nodeflow::read_output(self : Nodeflow, output : RuntimeOutput) -> OutputRead {
  match output {
    RuntimeOutput::Number(view) =>
      OutputRead::Value(self.runtime.store.get(view)) catch {
        @incr_query.ReadError::CrossStore(_) =>
          OutputRead::Failure(ReadFailure::CrossStore)
        @incr_query.ReadError::ClosedRegion(_) =>
          OutputRead::Failure(ReadFailure::ClosedRegion)
        @incr_query.ReadError::Cycle(_) => OutputRead::Cycle
        @incr_query.ReadError::ExpiredQueryContext(_) =>
          OutputRead::Failure(ReadFailure::ExpiredContext)
        @incr_query.ReadError::ReentrantRootGet(_) =>
          OutputRead::Failure(ReadFailure::ReentrantRoot)
        @incr_query.ReadError::GetDuringTransaction(_) =>
          OutputRead::Failure(ReadFailure::DuringTransaction)
      }
  }
}

///|
fn map_surface_read_error(error : ReadFailure) -> SurfaceReadError {
  match error {
    ReadFailure::CrossStore => SurfaceReadError::CrossStore
    ReadFailure::ClosedRegion => SurfaceReadError::ClosedRegion
    ReadFailure::ExpiredContext => SurfaceReadError::ExpiredContext
    ReadFailure::ReentrantRoot => SurfaceReadError::ReentrantRoot
    ReadFailure::DuringTransaction => SurfaceReadError::DuringTransaction
  }
}

///|
fn map_publication_read_error(error : ReadFailure) -> GraphPublicationError {
  match error {
    ReadFailure::CrossStore => GraphPublicationError::ReadCrossStore
    ReadFailure::ClosedRegion => GraphPublicationError::ReadClosedRegion
    ReadFailure::ExpiredContext => GraphPublicationError::ReadExpiredContext
    ReadFailure::ReentrantRoot => GraphPublicationError::ReadReentrantRoot
    ReadFailure::DuringTransaction =>
      GraphPublicationError::ReadDuringTransaction
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
        None => observations.push((port, OutputObservation::Missing))
        Some(output) =>
          match self.read_output(output) {
            OutputRead::Value(value) =>
              observations.push(
                (port, OutputObservation::Current(OutputData::Number(value))),
              )
            OutputRead::Cycle =>
              observations.push((port, OutputObservation::Unavailable))
            OutputRead::Failure(error) => return Err(error)
          }
      }
    }
  }
  Ok({ observations: ReadOnlyArray::from_array(observations) })
}

///|
/// Observes requested Outputs once from the current committed graph.
///
/// Raises ClosedNodeflow after close; a Cycle becomes Unavailable instead.
pub fn Nodeflow::snapshot(
  self : Nodeflow,
  demand : ObservationDemand,
) -> SurfaceSnapshot raise SurfaceReadError {
  if self.runtime.closed.val {
    raise SurfaceReadError::ClosedNodeflow
  }
  match self.snapshot_core(demand) {
    Ok(snapshot) => snapshot
    Err(error) => raise map_surface_read_error(error)
  }
}

///|
/// Validates and publishes one Graph Edit, then assembles its requested snapshot.
///
/// Rejection is a value and changes nothing. A raised post-publication read error
/// enters quarantine; it is never converted into a late rejection.
pub fn Nodeflow::apply(
  self : Nodeflow,
  edit : GraphEdit,
  demand : ObservationDemand,
) -> Result[GraphEditSuccess, GraphEditRejection] raise GraphPublicationError {
  if self.runtime.closed.val {
    raise GraphPublicationError::ClosedNodeflow
  }
  match self.state.apply(edit) {
    Err(rejection) => Err(rejection)
    Ok(transition) => {
      let runtime_node = self.create_runtime_node(transition.value)
      let node_id = transition.node.node
      let runtime_output = runtime_node.output
      runtime_node.anchor()
      match transition.state.nodes.get(node_id) {
        Some(node) => {
          ignore(node.parameter)
          ignore(node.output)
        }
        None => ()
      }
      self.runtime.nodes[node_id] = runtime_node
      self.runtime.outputs[transition.output] = runtime_output
      self.state = transition.state
      let snapshot = match self.snapshot_core(demand) {
        Ok(snapshot) => snapshot
        Err(error) => raise map_publication_read_error(error)
      }
      Ok({ node: transition.node, output: transition.output, snapshot })
    }
  }
}

///|
fn RuntimeNode::close(self : RuntimeNode) -> Unit raise GraphCloseError {
  self.region.close() catch {
    @incr_query.RegionError::ClosedRegion(_) =>
      raise GraphCloseError::RegionClosed
    @incr_query.RegionError::MutationDuringEvaluation(_) =>
      raise GraphCloseError::RegionMutationDuringEvaluation
    @incr_query.RegionError::MutationDuringTransaction(_) =>
      raise GraphCloseError::RegionMutationDuringTransaction
  }
}

///|
/// Idempotently closes every Node Region and releases private runtime indexes.
///
/// Later apply and snapshot calls raise their operation-specific ClosedNodeflow
/// variant. A structural close failure leaves the aggregate in quarantine and a
/// later close may safely retry because Region close is idempotent.
pub fn Nodeflow::close(self : Nodeflow) -> Unit raise GraphCloseError {
  if self.runtime.closed.val {
    return
  }
  let nodes = self.runtime.nodes.to_array()
  nodes.sort_by((left, right) => left.0.ordinal.compare(right.0.ordinal))
  for _, entry in nodes {
    entry.1.close()
  }
  self.runtime.nodes.clear()
  self.runtime.outputs.clear()
  self.runtime.closed.val = true
}
