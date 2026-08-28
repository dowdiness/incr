# Nodeflow kernel spike

**Reader:** maintainers evaluating a typed editable semantic graph over Incr Query.

**Decision:** keep Nodeflow opaque and closed while proving typed graph edits and atomic publication.

**Keep until:** Issue #496's finite evidence prototype reaches a documented verdict.

**Disposition:** active spike; this slice is evidence, not a production API commitment.

## Scope matrix

| Capability | Status |
|---|---|
| Opaque graph/node/port identities | Implemented |
| Closed descriptors: Number, Boolean, Add, Multiply, SafeDivide, Display, OptionalOffset | Implemented |
| Pure validation and ordinary edit rejection | Implemented |
| Atomic binding change sets and typed parameters | Implemented |
| Missing/unavailable/current demand projection | Implemented |
| Typed Formula Failure and ordered evaluation issues | Implemented |
| Display Action availability and explicit invocation | Implemented |
| GraphDocument JSON codec and atomic restoration | Implemented |
| Atomic Node removal and Region lifetime publication | Implemented |
| External persistence storage engine | Deferred |
| General cycles beyond the existing kernel catch shape | Deferred |
| Negative probes and `run.sh` | Deferred |

Each Node owns one private Incr Query Region. Number, Boolean, and OptionalOffset parameters are typed Sources; Add, Multiply, SafeDivide, and OptionalOffset own typed binding Sources and derived outputs. OptionalOffset distinguishes an absent optional Input from a connected unavailable provider. Publication creates runtime definitions before installing graph state, and stages binding writes in one transaction. Every Surface Snapshot projects deterministic Node, Port, Parameter, Action, and Connection views independently of Output demand. Surface output and Action demand is deduplicated in first-occurrence order; unavailable outputs and Action inputs carry immutable ordered issues, while formula failures remain current values. Display exposes a pass-through Number output and an explicit RecordNumber Action; availability never invokes it.
