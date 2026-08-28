# Nodeflow kernel spike

**Reader:** maintainers evaluating an optional semantic graph layer over `dowdiness/incr_query`.

**Decision:** keep Nodeflow opaque with generic graph-scoped node/port references and a separate consumer seam; prove the smallest Number Node workload before adding graph features.

**Keep until:** Issue #496's finite evidence prototype reaches a documented verdict.

**Disposition:** active spike; this slice is evidence, not a production API commitment.

The tracer slice creates an empty Nodeflow, applies one Number Node edit, and returns both its `NodeReference` and output `PortReference`. A generic `ObservationDemand` requests ports, and `SurfaceSnapshot` reports `Missing`, `Unavailable`, or typed `Current` output data. The Number formula is backed by one private Incr Query Region, a `Source[Int]` parameter, and a derived numeric View.

`GraphState` validation is pure and private; publication and surface reads translate only concrete kernel errors at their respective operation seams. `Nodeflow::close` idempotently releases every Node Region, and later apply or snapshot calls raise their operation-specific closed variant. Rebinding, removal, actions, persistence, cycles, and presentation state remain deferred.
