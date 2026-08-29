# Context Map

## Contexts

- [Incr Query](./incr_query/kernel/CONTEXT.md) — an independent typed incremental query kernel
- [Nodeflow](./examples/spikes/incr_query_nodeflow_kernel/CONTEXT.md) — a provisional application context for the Nodeflow evidence spike

## Relationships

- **Incr Query ↔ current Incr**: Independent sibling products in one repository. They do not share a public runtime or interchangeable handles.
- **Nodeflow → Incr Query**: Nodeflow may use the public Incr Query interface as an optional application layer. Incr Query does not know Nodeflow concepts.
- **Nodeflow → Graph Surface**: Nodeflow owns the Semantic Graph and Semantic Identities. A Graph Surface references them and owns only Presentation State.
