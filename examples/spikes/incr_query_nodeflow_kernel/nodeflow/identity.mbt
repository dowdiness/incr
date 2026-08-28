///|
/// The closed set of executable Node declarations.
pub(all) enum NodeDescriptor {
  Number(value~ : Int)
  Boolean(value~ : Bool)
  Add
  Multiply
  SafeDivide
  Display
  OptionalOffset(value~ : Int)
}

///|
/// The closed semantic kind exposed by the graph surface.
pub(all) enum NodeKind {
  Number
  Boolean
  Add
  Multiply
  SafeDivide
  Display
  OptionalOffset
} derive(Eq, Debug)

///|
/// The direction of a graph port.
pub(all) enum PortDirection {
  Input
  Output
} derive(Eq, Debug)

///|
/// The closed port value type.
pub(all) enum PortValueType {
  Number
  Boolean
} derive(Eq, Debug)

///|
/// A graph-scoped opaque parameter identity.
pub struct ParameterReference {
  priv graph : Int
  priv node : Int
  priv parameter : Int
} derive(Eq, Hash, Debug)

///|
/// A typed authored parameter value.
pub(all) enum ParameterValue {
  Number(Int)
  Boolean(Bool)
} derive(Eq, Debug)

///|
/// An immutable structural node projection.
pub struct NodeView {
  priv node : NodeReference
  priv kind : NodeKind
} derive(Eq, Debug)

///|
/// Returns this projection's Semantic Node Reference.
pub fn NodeView::node(self : NodeView) -> NodeReference {
  self.node
}

///|
/// Returns the closed presentation-safe Node kind.
pub fn NodeView::kind(self : NodeView) -> NodeKind {
  self.kind
}

///|
/// An immutable structural port projection.
pub struct PortView {
  priv port : PortReference
  priv direction : PortDirection
  priv value_type : PortValueType
  priv required : Bool
} derive(Eq, Debug)

///|
/// Returns this projection's Semantic Port Reference.
pub fn PortView::port(self : PortView) -> PortReference {
  self.port
}

///|
/// Returns whether the Port is an Input or Output.
pub fn PortView::direction(self : PortView) -> PortDirection {
  self.direction
}

///|
/// Returns the closed semantic value type carried by the Port.
pub fn PortView::value_type(self : PortView) -> PortValueType {
  self.value_type
}

///|
/// Reports whether an unbound Input causes Input Waiting.
pub fn PortView::required(self : PortView) -> Bool {
  self.required
}

///|
/// An immutable structural parameter projection.
pub struct ParameterView {
  priv parameter : ParameterReference
  priv value : ParameterValue
} derive(Eq, Debug)

///|
/// Returns this projection's Semantic Parameter Reference.
pub fn ParameterView::parameter(self : ParameterView) -> ParameterReference {
  self.parameter
}

///|
/// Returns the current typed authored Parameter Value.
pub fn ParameterView::value(self : ParameterView) -> ParameterValue {
  self.value
}

///|
/// An immutable structural action projection.
pub struct ActionView {
  priv action : ActionReference
} derive(Eq, Debug)

///|
/// Returns this projection's Semantic Action Reference.
pub fn ActionView::action(self : ActionView) -> ActionReference {
  self.action
}

///|
/// An immutable connection projection.
pub struct ConnectionView {
  priv input : PortReference
  priv output : PortReference
} derive(Eq, Debug)

///|
/// Returns the Input endpoint owned by this Connection.
pub fn ConnectionView::input(self : ConnectionView) -> PortReference {
  self.input
}

///|
/// Returns the Output provider bound to the Input endpoint.
pub fn ConnectionView::output(self : ConnectionView) -> PortReference {
  self.output
}

///|
/// A graph-scoped opaque Node identity.
pub struct NodeReference {
  priv graph : Int
  priv node : Int
} derive(Eq, Hash, Debug)

///|
fn parameter_reference(
  node : NodeReference,
  parameter : Int,
) -> ParameterReference {
  { graph: node.graph, node: node.node, parameter }
}

///|
/// A graph-scoped opaque Port identity.
pub struct PortReference {
  priv graph : Int
  priv node : Int
  priv port : Int
} derive(Eq, Hash, Debug)

///|
/// A graph- and Node-scoped Action identity.
pub struct ActionReference {
  priv graph : Int
  priv node : Int
  priv action : Int
} derive(Eq, Hash, Debug)

///|
/// A single final binding for an Input Port. `Bound` providers must be Outputs.
pub(all) enum BindingTarget {
  Bound(PortReference)
  Unbound
}

///|
/// One member of an atomic binding change set.
pub(all) struct BindingChange {
  target : PortReference
  binding : BindingTarget
}

///|
/// The immutable result of adding a Node.
pub struct AddedNode {
  priv node : NodeReference
  priv inputs : ReadOnlyArray[PortReference]
  priv outputs : ReadOnlyArray[PortReference]
  priv actions : ReadOnlyArray[ActionReference]
  priv parameters : ReadOnlyArray[ParameterReference]
  priv snapshot : SurfaceSnapshot
}

///|
/// Returns the added Node identity.
pub fn AddedNode::node(self : AddedNode) -> NodeReference {
  self.node
}

///|
/// Returns the Node's ordered Input Ports.
pub fn AddedNode::inputs(self : AddedNode) -> ReadOnlyArray[PortReference] {
  self.inputs
}

///|
/// Returns the Node's ordered Output Ports.
pub fn AddedNode::outputs(self : AddedNode) -> ReadOnlyArray[PortReference] {
  self.outputs
}

///|
/// Returns the Node's ordered Actions.
pub fn AddedNode::actions(self : AddedNode) -> ReadOnlyArray[ActionReference] {
  self.actions
}

///|
/// Returns the Node's ordered Parameter References.
pub fn AddedNode::parameters(
  self : AddedNode,
) -> ReadOnlyArray[ParameterReference] {
  self.parameters
}

///|
/// Returns the snapshot produced by publication.
pub fn AddedNode::snapshot(self : AddedNode) -> SurfaceSnapshot {
  self.snapshot
}

///|
/// The ordinary result of applying an edit.
pub(all) enum GraphEditResult {
  Added(AddedNode)
  Changed(SurfaceSnapshot)
}

///|
/// An atomic authoring request.
pub(all) enum GraphEdit {
  AddNode(descriptor~ : NodeDescriptor)
  SetParameter(parameter~ : ParameterReference, value~ : ParameterValue)
  BindingChangeSet(changes~ : Array[BindingChange])
  RemoveNodes(nodes~ : Array[NodeReference])
}

///|
/// An expected refusal decided by the pure graph core.
pub(all) enum GraphEditRejection {
  InvalidEdit
  MissingNode
  MissingParameter
  WrongParameterType
  MissingPort
  WrongDirection
  WrongType
  DuplicateBindingTarget
  DuplicateNodeTarget
} derive(Eq, Debug)

///|
/// A reason an Action cannot prepare its inputs.
pub(all) enum ActionInputIssue {
  Unbound(PortReference)
  ValueUnavailable(PortReference)
} derive(Eq, Debug)

///|
/// The consumer-safe availability of an Action.
pub(all) enum ActionAvailability {
  Available
  Unavailable(ReadOnlyArray[ActionInputIssue])
} derive(Eq, Debug)

///|
/// The observation of one requested Action.
pub(all) enum ActionObservation {
  Missing
  Present(ActionAvailability)
} derive(Eq, Debug)

///|
/// A minimal immutable command produced by the Display Action.
pub(all) enum Command {
  RecordNumber(Int)
} derive(Eq, Debug)

///|
/// The closed Display application decision.
pub(all) enum ApplicationDecision {
  Success(Command)
  ApplicationRefusal(FormulaFailure)
} derive(Eq, Debug)

///|
/// The expected refusal of an Action invocation.
pub(all) enum ActionInvocationRejection {
  MissingAction
} derive(Eq, Debug)

///|
/// The result of explicitly invoking an Action.
pub(all) enum ActionInvocationOutcome {
  Rejected(ActionInvocationRejection)
  Unavailable(ReadOnlyArray[ActionInputIssue])
  Decided(ApplicationDecision)
} derive(Eq, Debug)

///|
/// Closed semantic output data.
pub(all) enum FormulaFailure {
  DivisionByZero
} derive(Eq, Debug)

///|
/// The current result of a Number formula.
pub(all) enum NumberFormulaOutcome {
  Success(Int)
  Failure(FormulaFailure)
} derive(Eq, Debug)

///|
/// Why a Node currently has no available output.
pub(all) enum EvaluationIssue {
  InputWaiting(PortReference)
  BlockedEvaluation(PortReference)
  CyclicEvaluation
} derive(Eq, Debug)

///|
/// Closed semantic output data.
pub(all) enum OutputData {
  Number(NumberFormulaOutcome)
  Boolean(Bool)
} derive(Eq, Debug)

///|
/// The current result for one demanded Output.
pub(all) enum OutputObservation {
  Missing
  Unavailable(ReadOnlyArray[EvaluationIssue])
  Current(OutputData)
} derive(Eq, Debug)

///|
/// An owned ordered output demand.
priv enum DemandRequest {
  OutputDemand(PortReference)
  ActionDemand(ActionReference)
}

///|
pub struct ObservationDemand {
  priv requests : Array[DemandRequest]
}

///|
/// Creates an empty demand.
pub fn ObservationDemand::empty() -> ObservationDemand {
  { requests: [] }
}

///|
/// Appends a Port; snapshots retain only the first occurrence.
pub fn ObservationDemand::request(
  self : ObservationDemand,
  port : PortReference,
) -> ObservationDemand {
  let requests = self.requests.copy()
  requests.push(DemandRequest::OutputDemand(port))
  { requests, }
}

///|
/// Requests an Action observation; snapshots retain first occurrence.
pub fn ObservationDemand::request_action(
  self : ObservationDemand,
  action : ActionReference,
) -> ObservationDemand {
  let requests = self.requests.copy()
  requests.push(DemandRequest::ActionDemand(action))
  { requests, }
}

///|
/// An immutable UI-neutral surface projection.
pub struct SurfaceSnapshot {
  priv nodes : ReadOnlyArray[NodeView]
  priv ports : ReadOnlyArray[PortView]
  priv parameters : ReadOnlyArray[ParameterView]
  priv actions : ReadOnlyArray[ActionView]
  priv connections : ReadOnlyArray[ConnectionView]
  priv observations : ReadOnlyArray[(PortReference, OutputObservation)]
  priv action_observations : ReadOnlyArray[(ActionReference, ActionObservation)]
}

///|
/// Returns all current Nodes in Semantic Identity order.
pub fn SurfaceSnapshot::nodes(
  self : SurfaceSnapshot,
) -> ReadOnlyArray[NodeView] {
  self.nodes
}

///|
/// Returns all current Ports in Node and declared Port order.
pub fn SurfaceSnapshot::ports(
  self : SurfaceSnapshot,
) -> ReadOnlyArray[PortView] {
  self.ports
}

///|
/// Returns all current Parameters in Node and declaration order.
pub fn SurfaceSnapshot::parameters(
  self : SurfaceSnapshot,
) -> ReadOnlyArray[ParameterView] {
  self.parameters
}

///|
/// Returns all current Actions in Node and declaration order.
pub fn SurfaceSnapshot::actions(
  self : SurfaceSnapshot,
) -> ReadOnlyArray[ActionView] {
  self.actions
}

///|
/// Returns all bound Inputs in deterministic semantic order.
pub fn SurfaceSnapshot::connections(
  self : SurfaceSnapshot,
) -> ReadOnlyArray[ConnectionView] {
  self.connections
}

///|
/// Returns observations in first-request order.
pub fn SurfaceSnapshot::observations(
  self : SurfaceSnapshot,
) -> ReadOnlyArray[(PortReference, OutputObservation)] {
  self.observations
}

///|
/// Returns Action observations in first-request order.
pub fn SurfaceSnapshot::action_observations(
  self : SurfaceSnapshot,
) -> ReadOnlyArray[(ActionReference, ActionObservation)] {
  self.action_observations
}

///|
/// Looks up one observation, returning Missing for an unrequested Port.
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
/// Returns an Action observation, or Missing when it was not requested.
pub fn SurfaceSnapshot::action_observation(
  self : SurfaceSnapshot,
  action : ActionReference,
) -> ActionObservation {
  for entry in self.action_observations {
    if entry.0 == action {
      return entry.1
    }
  }
  Missing
}

///|
/// Structural failures while publishing an accepted edit.
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
/// Structural failures while producing an Action decision.
pub suberror ActionInvocationError {
  ClosedNodeflow
  CrossStore
  ClosedRegion
  ExpiredContext
  ReentrantRoot
  DuringTransaction
} derive(Debug)

///|
/// Structural failures while producing a surface snapshot.
pub suberror SurfaceReadError {
  ClosedNodeflow
  CrossStore
  ClosedRegion
  ExpiredContext
  ReentrantRoot
  DuringTransaction
} derive(Debug)

///|
/// Structural failures while closing the execution domain.
pub suberror GraphCloseError {
  RegionClosed
  RegionMutationDuringEvaluation
  RegionMutationDuringTransaction
} derive(Debug)
