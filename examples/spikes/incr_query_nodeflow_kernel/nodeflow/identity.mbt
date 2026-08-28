///|
/// The closed set of executable Node declarations.
pub(all) enum NodeDescriptor {
  Number(value~ : Int)
  Boolean(value~ : Bool)
  Add
  Multiply
  SafeDivide
  Display
}

///|
/// A graph-scoped opaque Node identity.
pub struct NodeReference {
  priv graph : Int
  priv node : Int
} derive(Eq, Hash, Debug)

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
  SetNumberParameter(node~ : NodeReference, value~ : Int)
  BindingChangeSet(changes~ : Array[BindingChange])
}

///|
/// An expected refusal decided by the pure graph core.
pub(all) enum GraphEditRejection {
  InvalidEdit
  MissingNode
  MissingPort
  WrongDirection
  WrongType
  DuplicateBindingTarget
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
  priv observations : ReadOnlyArray[(PortReference, OutputObservation)]
  priv action_observations : ReadOnlyArray[(ActionReference, ActionObservation)]
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
