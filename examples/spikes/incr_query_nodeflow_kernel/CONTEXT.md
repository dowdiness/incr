# Nodeflow

Nodeflow is a provisional application context for testing typed, editable semantic graphs over Incr Query. It owns graph meaning and execution-facing identity while remaining independent of any visual graph surface.

## Language

**Semantic Graph**:
The authoritative collection of Nodes, Ports, connections, parameters, and Node lifetimes evaluated by Nodeflow.
_Avoid_: Canvas document, layout graph, render graph

**Semantic Identity**:
A stable, opaque Nodeflow-owned identity. Graph, Node, and Node-owned Port, Parameter, and Action identities form an ownership hierarchy rather than one global namespace.
_Avoid_: Canvas ID, mapped UI ID, cell ID, View ID, memo ID

**Graph Identity**:
The persisted identity of one Semantic Graph lineage. It is independent of Incr Query Store and Region identities and is a caller-owned semantic key, not runtime authority: the selected Nodeflow receiver determines the execution domain. Multiple restored aggregates may intentionally represent the same lineage without sharing runtime state.
_Avoid_: Store ID, document path, Canvas handle, runtime capability, process-global ownership claim

**Node Identity**:
A Semantic Identity unique within one Graph Identity. A Graph Surface carries it directly as a generic caller-owned key and cannot mint, replace, or persistently remap it.
_Avoid_: Global node ID, Canvas node ID, runtime cell ID

**Node Descriptor**:
An immutable application-owned declaration of one Node kind's Port, Parameter, Action, and Formula shape. A Graph Document stores stable descriptor data while an explicit application catalog supplies executable construction; the initial prototype lowers a closed application sum inside the Nodeflow package, accepts no arbitrary Formula closure, and establishes no production plugin model.
_Avoid_: Canvas NodeKind, serialized Formula closure, public user callback, process-global plugin registry, universal property bag

**Port Identity**:
A Semantic Identity unique within one Node Identity. A connection endpoint identifies its Graph, Node, and Port scopes explicitly.
_Avoid_: Global port ID, port label, array index

**Parameter Identity**:
A Semantic Identity unique within one Node Identity for an authored, non-connectable value declared by that Node. It remains distinct from Port and Action namespaces and is stable across Graph Surface projections and Graph Document round-trips.
_Avoid_: Parameter label, array index, Input Port ID, form control ID

**Action Identity**:
A Semantic Identity unique within one Node Identity for an explicitly invokable Action declared by that Node. It identifies the Action across Graph Surface observations and invocations but is not an invocation token, Command identity, or idempotency key.
_Avoid_: Action label, button ID, invocation ID, Command ID

**Node Reference**:
A Graph Identity and Node Identity pair used when a Node is referenced across Graph boundaries.
_Avoid_: Global node ID, Canvas node ID

**Port Reference**:
A Graph Identity, Node Identity, and Port Identity tuple used for connection endpoints and cross-boundary references.
_Avoid_: Port label, endpoint string, runtime key

**Parameter Reference**:
A Graph Identity, Node Identity, and Parameter Identity tuple used to address one parameter across authoring and persistence boundaries.
_Avoid_: Parameter label, dotted string path, form control ID

**Action Reference**:
A Graph Identity, Node Identity, and Action Identity tuple used to request Action Availability or start an Action Invocation. Removing the owning Node retires the reference without assigning it to another Action.
_Avoid_: Global Action ID, UI callback index, invocation token

**Parameter Value**:
A valid application-owned typed semantic value stored for one Parameter Reference. Parsing, partially entered text, and validation presentation remain outside the Semantic Graph; an invalid authoring request is rejected rather than persisted as a malformed Parameter Value.
_Avoid_: Raw form text, implicit default after parse failure, presentation draft

**Port Value Type**:
The application-owned semantic type of values carried by one Port. Nodeflow requires an Input and Output to have the same declared type before connecting them, uses explicit conversion Nodes instead of implicit coercion, and defines no universal `Any` type or framework-wide enum of application types.
_Avoid_: Display label, runtime cast, Canvas PortType, implicit coercion, universal Any

**Declared Input**:
A Formula-owned typed authority to read one of its Node's declared Input Ports or Parameters during one evaluation. The closed Node Descriptor lowering constructs only those readers inside the Nodeflow package; no public Formula callback, raw execution context, runtime authorization Map, or ambient graph access is offered as a substitute for confinement.
_Avoid_: String lookup, public Formula builder, ambient graph access, raw QueryContext, runtime authorization registry

**Identity Remap**:
A caller-owned result of copying semantic content into an existing Graph, pairing source references with freshly minted target references. It is operation-local and never a persistent registry.
_Avoid_: Identity registry, alias table, Canvas mapping

**Connection**:
A Semantic Graph binding from one Output Port Reference to one Input Port Reference. Each Input Port has zero or one current Connection, an Output Port may serve many Inputs, and the Connection has no separately minted identity beyond its endpoints; rebinding replaces the prior provider atomically.
_Avoid_: Edge entity, Canvas Edge ID, connection registry, multi-provider scalar input

**Binding Change Set**:
A Graph Edit payload assigning a final Bound Output or Unbound state to each of a finite set of distinct Input Port References. Nodeflow validates every target, endpoint, and Port Value Type before producing one Graph Transition; caller order is retained only for deterministic rejection reporting, duplicate targets are rejected, and no sequential intermediate binding is observable.
_Avoid_: Ordered connect/disconnect script, partial rebind, duplicate last-write-wins, generic Graph Edit batch

**Graph Edit**:
A requested atomic change to the Semantic Graph, such as binding or unbinding an Input Port, changing a parameter, adding a Node, or removing a Node.
_Avoid_: Canvas interaction, UI event, Action

**Graph Edit Rejection**:
An expected refusal of a Graph Edit based on the request and current Semantic Graph, such as a stale reference to a missing Node. It is returned as an ordinary `Result` value, leaves the graph unchanged, and does not use MoonBit's raised-error channel.
_Avoid_: Exception, structural failure, internal error

**Graph Transition**:
The private deterministic accepted result of applying one Graph Edit to the current Semantic Graph, containing the complete next Semantic Graph and private decisions needed to realize it. It is neither part of the caller interface nor a durable Event, receipt, or revision, and the next graph is not observable until Graph Transition Publication succeeds.
_Avoid_: Public transition type, mutated live graph, event log entry, commit receipt, public revision

**Graph Transition Publication**:
The private synchronous imperative-shell protocol that realizes an accepted Graph Transition against the execution domain and exposes its next Semantic Graph only after the required transaction and lifetime work completes. No intermediate graph is public; a Structural Failure exits through quarantine rather than converting the accepted transition into a late Graph Edit Rejection.
_Avoid_: Public publication plan, incremental public mutation, post-commit rejection, asynchronous partial publication

**Structural Failure**:
The category of operation-specific typed raised errors reporting that Nodeflow could not safely publish, observe, restore, or invoke an otherwise valid decision because an execution, transaction, provenance, or lifetime seam failed. Nodeflow defines no umbrella kernel-error enum, never converts these failures into expected domain rejection, and leaves an unknown raised error or `Failure` as an internal defect for quarantine.
_Avoid_: Global NodeflowStructuralError, Graph edit rejection, invalid user action, catch-all fallback

**Node Removal Publication**:
The synchronous shell protocol for an accepted Node-removal decision. Nodeflow first publishes all disconnections and survivor unbindings in one Incr Query Transaction; after that Transaction restores the Store to idle, it idempotently closes every removed Node Region without yielding control, then installs and exposes the next Semantic Graph. A rejected edit starts neither the Transaction nor Region cleanup; under the valid publication phase close succeeds, while any raised RegionError signals a violated shell protocol and enters Structural Failure quarantine rather than becoming a Graph Edit Rejection.
_Avoid_: Asynchronous cleanup, public Removing state, cleanup journal, expected close rejection, post-commit rejection

**Input Waiting**:
The evaluation condition of a Node with at least one unbound required Input Port. Nodeflow keeps the Node in the Semantic Graph but does not invoke its Formula or invent a default input value; an explicitly optional unbound Input Port instead supplies `None`, and Input Waiting may coexist with Blocked Evaluation on another Port.
_Avoid_: Evaluation error, implicit zero, automatic Node deletion, making every Formula handle missing required inputs

**Unavailable Output**:
An Output Port with no current semantic value because its Node cannot presently evaluate. When a Node enters Input Waiting, its previous output becomes unavailable immediately and is never supplied to downstream Formulas as if it were current. A Graph Surface may retain that previous value only as explicitly stale presentation, not as Semantic Graph state or a computable value.
_Avoid_: Last value wins, implicit cache value, current output, silent stale propagation

**Blocked Evaluation**:
The evaluation condition of a Node with any connected Input Port whose provider currently has an Unavailable Output. Nodeflow does not invoke the Formula until that connection supplies a current value; optionality applies only when the Port is unbound, so a connected optional Port can also block, and this condition may coexist with Input Waiting elsewhere on the Node.
_Avoid_: Upstream waiting, input waiting, treating unavailable as optional `None`, implicit stale value, structural failure

**Cyclic Evaluation**:
The unavailable evaluation state observed when the currently active Formula dependency path forms a cycle. Nodeflow keeps the accepted Semantic Graph editable and reports the kernel's typed Cycle category and opaque diagnostic at the demanded-root quarantine seam without turning it into a Formula failure, parsing its private path, or exposing an old output as current.
_Avoid_: Static connection-cycle rejection, Formula failure, stale output, parsed kernel cycle path

**Formula Outcome**:
The immutable application-owned semantic result of one closed prototype Formula: either a successful value or a typed Formula failure, equivalent to `Result[V, E]`, composed fail-fast in declared input order. Both variants are current memoizable values; this evidence defines no generalized Formula-language effect syntax or cross-language composition policy, while Structural Failures remain on operation-specific raised channels.
_Avoid_: Unavailable Output, raw host exception, catch-all conversion, Nodeflow-wide Formula error, speculative Formula-language framework

**Failure Presentation**:
An application-owned pure projection from a typed Formula failure and explicit presentation context into consumer-owned view data. The application adapter owns localization, privacy filtering, semantic-reference attachment, and the shape required by its Graph Surface, CLI, or other consumer. Nodeflow defines no common Formula diagnostic record before multiple consumers establish a shared need, and presentation data is neither persisted nor used for evaluation or memo equality.
_Avoid_: Nodeflow-wide diagnostic schema, `Debug` or `repr` fallback, persisted message, Formula evaluation depending on locale

**Action Invocation**:
An explicit request to evaluate one Action exactly once against its declared inputs in one committed snapshot. Input publication alone never creates an Action Invocation. The pure decision captures only the application values needed to state the caller's intent; invocation identity or retry metadata, when needed, is supplied by the imperative shell rather than minted from a clock, random source, or counter inside the Action.
_Avoid_: Automatic effect, Formula evaluation, independent incoherent reads, ambient kernel Revision

**Command**:
An immutable application-owned description of intent returned by an Action decision for interpretation by the imperative shell. A Command contains the minimum owned values that fix its meaning and never silently rereads the Semantic Graph during execution. External authorization, resource versions, idempotency, retry, and delivery remain application or external-authority concerns and are added only by Commands that need them.
_Avoid_: Entire graph snapshot, executable closure over a View, automatic exactly-once promise, stale authorization snapshot

**Command Execution**:
An imperative-shell-owned attempt to interpret a Command whose lifetime and durability are application policy rather than Node or Region lifetime. Node removal does not cancel it automatically, Semantic Graph restore does not replay it automatically, and explicit cancellation is best-effort rather than an external rollback promise; disposal of its application input boundary prevents later feedback delivery where the shell controls that boundary.
_Avoid_: Node-owned task, automatic removal cancellation, restore-time replay, external rollback promise, Nodeflow in-flight registry

**Command Feedback**:
An immutable application-owned input that the imperative shell may emit zero or more times while or after a Command Execution. It re-enters an application-owned pure transition before any later Graph Edit; Nodeflow defines no universal Event schema, completion cardinality, delivery guarantee, or stale, duplicate, ordering, and cancellation policy.
_Avoid_: Completion Event, direct callback mutation, Nodeflow request ticket, exactly-once completion

**Action Availability**:
The consumer-safe derived observation of whether one existing Action can prepare its declared inputs in the current committed snapshot: Available without prepared values, or Unavailable with ordered Action Input Issues. Input preparation remains an unnamed private step repeated by a fresh Action Invocation; becoming Available never invokes the Action, and the observation carries neither values nor authority forward.
_Avoid_: Public ActionPreparation type, `can_invoke` boolean without reasons, prepared Command inputs in UI data, queued invocation, cached invocation permission

**Action Observation**:
The ordinary Surface Snapshot result for one requested Action Reference: Missing when the Action is absent from the current Semantic Graph, or Present with its current Action Availability. It creates no invocation and carries no authority into a later one.
_Avoid_: Cached invocation permission, automatic Action, missing-Action exception

**Action Input Issue**:
A reason that Action input preparation is currently Unavailable: either a required Input Port is unbound or its connected Output Port has no current value. A compatible failed Formula Outcome is a current value and is not an Action Input Issue.
_Avoid_: Formula failure, Structural Failure, upstream waiting, implicit stale value

**Action Invocation Rejection**:
An expected refusal before Action input resolution because the requested Action Reference is absent from the current Semantic Graph. It changes no state, invokes no Action, creates no Command, and is distinct from an existing Action whose inputs are currently Unavailable.
_Avoid_: Action Input Issue, Structural Failure, application authorization refusal, missing-Node exception

**Action Invocation Outcome**:
The ordinary value returned for one explicit invocation after freshly resolving its declared inputs: Rejected with an Action Invocation Rejection, Unavailable with the current ordered Action Input Issues, or Decided with the application-owned decision. Neither Rejected nor Unavailable calls the Action decision; application refusal remains inside the application decision, while runtime Structural Failure remains on the typed raised-error channel.
_Avoid_: Nested rejection `Result`, exception for unavailability, conflated application refusal

**Action Re-invocation**:
A new explicit Action Invocation used when delayed work needs values from a later committed snapshot. A pending Command may request scheduling or produce Command Feedback that requests a later invocation, but it does not change its own meaning by rereading the graph. The later invocation may be rejected normally if its target identity no longer exists.
_Avoid_: Hidden graph reread, mutable Command meaning, kernel scheduler policy

**Graph Document**:
The application-owned persistent representation of one Semantic Graph, containing its Semantic Identities, monotonic identity-allocation frontier, Node descriptors and parameters, and connections. It is a save, restore, import, and copy boundary rather than the interactive mutation interface, and excludes execution-engine identities and caches, computed outputs, Command Executions and Feedback, mounted demand, Presentation State, and the separate Layout Profile.
_Avoid_: Interactive whole-document replacement, runtime snapshot, output cache, in-flight command log, Canvas document

**Graph Restoration**:
The atomic validation and reconstruction of a Graph Document into a fresh execution domain while preserving its Semantic Identities and allocation frontier. Restoration may coexist with another aggregate of the same semantic lineage because operations resolve against their explicit Nodeflow receiver; it exposes no partial graph, replays no Command, restores no cached output, and recomputes demanded values from persisted semantic inputs.
_Avoid_: Implicit runtime authority, Store deserialization, partial load, runtime identity reuse, restore-time effect replay

**Output Demand**:
An ephemeral application request to include a selected Output Port in a consumer observation. It controls observation rather than Semantic Graph meaning, never enters a Graph Document, and neither promises cache eviction when removed nor makes an unavailable output current.
_Avoid_: Graph Edit, semantic connection, persisted mount, cache-lifetime authority, implicit evaluation of every output

**Output Observation**:
The ordinary Surface Snapshot result for one demanded Port Reference: Missing when it is not a current Output Port, Unavailable when it has no current semantic value, or Current with application-owned consumer data. Nodeflow resolves the reference before reading any execution capability, so stale demand cannot touch a retired Region; a failed Formula Outcome is Current, while stale presentation retained by a Graph Surface is outside this result.
_Avoid_: Raw View read, ClosedRegion as stale-demand control flow, last-good semantic value, Formula failure as unavailable

**Reactive Turn**:
The private synchronous shell interval started by every Surface Snapshot request, optionally immediately after a successful apply or restore publication, in which each demanded output root is observed at most once against one committed state before another external input or callback may interleave. Transaction staging never refreshes a root; a Cycle may be quarantined for its demanded root, while any other Structural Failure aborts the turn rather than becoming application data.
_Avoid_: Public scheduler interface, per-write refresh, re-entrant projection callback, asynchronous graph evaluation, ambient Revision, catch-all structural recovery

**Surface Snapshot**:
The immutable, UI-neutral result of Nodeflow's sole surface-read operation, assembled by one Reactive Turn from the Semantic Graph and explicitly requested output and Action observations. Apply and restore return this same snapshot shape after successful publication; it carries Semantic Identities and consumer view data without exposing execution-engine handles or joining Presentation State into semantic authority.
_Avoid_: Independent output or Action read methods, implicit observation of every value, kernel View bundle, Canvas state, ambient revision

**Graph Surface**:
A presentation and interaction surface that projects a Semantic Graph without owning its meaning. It uses Semantic Identities directly as generic keys; Canopy Canvas is one possible Graph Surface.
_Avoid_: Semantic graph, Nodeflow runtime, canonical graph, identity registry

**Surface Attachment**:
A rebuildable association from a Semantic Identity to a current DOM node, SVG path, view path, or other renderer-local object. It is never durable authoring identity.
_Avoid_: Semantic identity, Canvas identity, persistent identity mapping

**Presentation State**:
Graph Surface state that does not change Nodeflow meaning, including viewport, selection, hover, drag preview, connection gesture state, and context menus.
_Avoid_: Semantic state, graph parameters, connections

**Layout Profile**:
A persistent Graph Surface artifact for one Graph Identity that maps Node Identities to presentation metadata such as position, size, collapsed state, grouping, and viewport preference. It is separate from the Semantic Graph and cannot affect Nodeflow evaluation.
_Avoid_: Semantic graph, Nodeflow document, session state
