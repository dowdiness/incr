# Nodeflow production-readiness stop gate

**Date:** 2026-08-29

**Reader:** new maintainers evaluating the optional Nodeflow layer or deciding whether to commission its next product integration.

**Decision:** retain the merged Nodeflow implementation as completed, adoptable evidence and add no permanent browser, packaging, memory, persistence, or Canvas integration machinery without an explicit product driver. Record the bounded host experiments in this note, recommend that maintainers close Issue #496 as an Adoptable prototype through a separately authorized GitHub action, and reopen implementation only through one of the driver-specific gates below.

**Keep until:** Nodeflow receives a production consumer or publication commission, or the evidence layer is deleted.

**Disposition:** retained production-readiness gate. This note records completed investigation and the conditions for future work. It does not authorize publication, a persistence-v1 contract, GitHub issue changes, or Canopy Canvas integration.

## Executive summary

Incr Query is an incremental computation kernel. It deliberately does not define Nodes, Ports, editable Graphs, Formulas, Actions, persistence documents, or UI presentation. The Nodeflow evidence module demonstrates that an optional application layer can own those concepts while using only Incr Query's public interface.

The prototype is complete enough to classify as **Adoptable optional layer**. It has a small opaque aggregate, typed edits and observations, deterministic application semantics, bounded web evaluation, restoration, cleanup, and compiler-enforced representation privacy. Its known algorithmic restoration bottleneck and post-publication lifecycle ambiguity have been resolved.

No application currently consumes Nodeflow as a production package. Nodeflow is not published, no browser deployment backend has been selected, no browser support policy exists, and no product has accepted persistence compatibility obligations. Permanent cross-browser and clean-room packaging infrastructure would therefore maintain hypothetical adapters rather than protect a real caller.

Exploratory execution established that the current depth policy works under Node and three Playwright browser engines for both JS and wasm-gc in a source workspace. A separate clean-room experiment composed Nodeflow source with an unpacked Incr Query candidate and ran the JS result under the same hosts. These results retire the immediate feasibility question; they do not create a support matrix.

The correct next step is to stop adding generic readiness machinery. Future tests should live with the first real consumer or publication adapter and cover only the hosts and contracts that product selects.

## Product context

### Incr Query

`dowdiness/incr_query` is a sibling product to current `dowdiness/incr`, not its compatibility successor. Its kernel lives under `incr_query/kernel` and provides:

- Stores and Regions;
- typed Sources, Views, Derived Values, and Queries;
- dynamic dependency tracking;
- atomic Transactions;
- typed cycle, lifetime, phase, and evaluation-limit failures.

The distribution candidate and standalone public consumer are maintained under:

- `incr_query/tools/check-incr-query-k2-3-distribution.sh`;
- `incr_query/consumer_probe`;
- the `Incr Query distribution candidate` job in `.github/workflows/ci.yml`.

That distribution harness packages an unpublished candidate twice, checks reproducibility and package contents, consumes the unpacked candidate in a fresh workspace, verifies no source fallback, and exercises default, native, JavaScript, and wasm-gc targets.

### Optional Nodeflow layer

The Nodeflow evidence module is:

```text
examples/spikes/incr_query_nodeflow_kernel/
├── application/
├── nodeflow/
├── consumer/
└── run.sh
```

The packages have distinct ownership:

- `application` owns the closed Node Descriptors, Formula Outcomes, Commands, decisions, and descriptor codec. It imports neither Nodeflow nor Incr Query.
- `nodeflow` owns the editable Semantic Graph, Semantic Identities, typed Connections, runtime capability lowering, Graph Documents, Actions, and Surface Snapshots. It imports the application model and public Incr Query interface.
- `consumer` proves that callers can use Nodeflow without importing Incr Query directly.

Nodeflow is an opaque aggregate. Callers use Graph Edits, observation demand, Action invocation, Graph Document export/restoration, and immutable Surface Snapshots. Incr Query handles, runtime Nodes, Sources, Regions, Transactions, caches, and mutable Maps remain private.

### Graph Surface and Canopy Canvas

A Graph Surface renders and edits presentation state around a Semantic Graph. Under the selected authority model:

- Nodeflow owns Semantic Graph structure and Semantic Identity;
- a Graph Surface owns selection, viewport, hover, drag preview, and layout profile;
- Graph Edits cross from the surface into Nodeflow;
- Surface Snapshots cross from Nodeflow into the surface.

Canopy Canvas is a possible future Graph Surface, not part of the evidence module. A separately inspected Canopy checkout at `f12feda56fde42b99fda8dc6d1737f0ad55bea90` currently gives its canvas model durable Node/Edge snapshots and stable Canvas identities (`modules/canvas-graph/README.md`) and does not include the Incr Query Nodeflow module in `apps/canvas/main/moon.pkg`. A production integration would therefore need an explicit authority-seam design rather than a dependency-only change.

## Completed capability baseline

The following behavior is merged on `main`.

### Semantic and runtime model

- Number and Boolean Port families;
- Number, Boolean, Add, Multiply, SafeDivide, Display, and OptionalOffset Nodes;
- single-provider Inputs and fan-out Outputs;
- atomic binding changes and Node removal;
- application-owned current Formula failures;
- explicit Action invocation and immutable Commands;
- active-cycle observation and recovery;
- demand-driven Surface Snapshots;
- same-lineage restoration into independent runtime authorities.

### Error and lifetime model

Expected domain outcomes remain values. Structural execution, publication, provenance, and lifetime failures use operation-specific typed raised errors.

A Store-configured maximum of 256 simultaneously active Queries protects Nodeflow web hosts from recursive host-stack exhaustion. Reaching the limit leaves the Semantic Graph valid and appears as typed Output or Action unavailability. The kernel default remains unbounded for other consumers.

After an accepted transition installs changed semantic and runtime state (called internal Graph publication), a true Structural Failure during the following snapshot assembly quarantines the Nodeflow before raising. This internal publication is unrelated to package or registry publication. Formula runtime paths use exhaustive matches rather than impossible-state aborts.

### Persistence evidence

Graph Document export and restoration preserve semantic identities, allocator frontier, descriptors, parameters, and Connections while excluding runtime handles, caches, outputs, observation demand, presentation state, and Command execution history.

This is an evidence contract, not a stable persistence promise. `GraphDocument::encode_json` and `decode_json` are public in the evidence package, but no product has committed to long-term v1 readability, migration ownership, or unknown-property behavior.

### Performance evidence

`docs/performance/2026-08-29-incr-query-nodeflow-boundaries.md` records broad/shallow edit and snapshot results and dedicated restoration measurements.

The restoration validator now builds one live-Node-sized identity Map and lazily derives schema metadata. It preserves document-order rejection precedence and sparse identities while removing the previous binding-dependent full-document scan. At 10,000 Nodes, the measured JS validation time changed from 110.71 ms to 6.11 ms for a linear document and from 209.80 ms to 6.73 ms for dense bindings.

No remaining performance result justifies another generic optimization.

### Validation evidence

`examples/spikes/incr_query_nodeflow_kernel/run.sh` checks:

- Nodeflow and consumer packages on default, native, JS, and wasm-gc;
- JS and wasm-gc release evaluation-limit behavior;
- generated-interface freshness;
- negative capability probes;
- application/Nodeflow/kernel dependency direction;
- absence of Incr Query representation in the Nodeflow interface;
- Incr Query layout and documentation boundaries.

## Production-readiness question

The investigation asks:

> What permanent work, if any, is necessary before a real product consumer or publication commitment exists?

A useful next step must do more than demonstrate another green configuration. It must retire a risk that affects a current caller or change a pending architectural decision.

The evaluation criteria are:

1. **Information gain** — can failure change the product design?
2. **Essential complexity** — does the work represent a real domain or host obligation?
3. **Deletion test** — would deleting the new module force complexity into existing callers?
4. **Adapter reality** — does an actual adapter vary at the proposed seam?
5. **Reversibility** — can the project change direction without compatibility debt?
6. **Locality** — does knowledge stay with the module that owns it?
7. **CI cost** — how much permanent setup, download, and failure surface is introduced?
8. **Claim discipline** — does the evidence support only the stated production claim?

## Investigation method

The study intentionally covered the following design space.

### Repository analysis

- audited Nodeflow public interfaces, release tests, package manifests, persistence code, and validation harness;
- audited the existing Incr Query distribution candidate and no-source-fallback controls;
- inspected existing Playwright and localhost-server patterns in `.github/workflows/ci.yml` and `examples/incr_tea`;
- inspected the intended Canopy Canvas consumer's current authority and package seams;
- located remaining production aborts and uncommitted persistence obligations.

### Host experiments

Temporary MoonBit executable packages exercised the Nodeflow active-Query policy. The semantic scenario built a chain below the configured policy and a chain above it, demanded the tail, and reported whether the result was current or typed unavailable. Temporary packages and scripts were removed after the experiment.

Two backend adapters were used:

- JS installed or printed a deterministic result consumed by Node or a browser page;
- wasm-gc exported `_start` and used its generated `spectest.print_char` import to emit the result.

### Clean-room experiment

A temporary workspace combined an unpacked Incr Query candidate archive with copied Nodeflow/application source. The dependency tree was checked to ensure `dowdiness/incr_query@0.1.0-alpha.1` resolved to the unpacked workspace member instead of the repository checkout.

Nodeflow itself was not packaged or published.

## Host experiment results

### Source-workspace matrix

The JS scenario returned `pass` under:

| Host | Result |
|---|---|
| Node.js 24 | pass |
| Playwright Chromium 148 | pass |
| Playwright Firefox 150 | pass |
| Playwright WebKit 26.4 | pass |

The wasm-gc scenario returned `pass` under:

| Host | Result |
|---|---|
| Node.js 24 WebAssembly | pass |
| Playwright Chromium WebAssembly GC | pass |
| Playwright Firefox WebAssembly GC | pass |
| Playwright WebKit WebAssembly GC | pass |

Playwright WebKit is not Safari. These results establish engine-level feasibility for the tested Playwright build; they do not promise support for Safari releases or any other browser version.

### Clean-room JS result

Packaging the standalone Nodeflow module failed because `dowdiness/incr_query` is intentionally absent from the public registry. This is expected: neither Nodeflow nor Incr Query publication was commissioned by this work.

With an unpacked Incr Query candidate included as a workspace member, `moon tree` resolved:

```text
dowdiness/incr_query@0.1.0-alpha.1
  -> local unpacked candidate workspace member
```

The clean-room release JS artifact returned `pass` under the same tested versions listed in the source-workspace matrix: Node.js 24, Playwright Chromium 148, Playwright Firefox 150, and Playwright WebKit 26.4.

Clean-room wasm-gc was not run. The source-workspace wasm-gc matrix and clean-room JS experiment establish the individual mechanisms, not their complete cross-product.

## Essential complexity already represented

The following complexity belongs to the problem and is already implemented:

- dynamic Semantic References require validated identity lookup;
- heterogeneous Ports require closed typed runtime capability sums;
- accepted edits require atomic Source publication and ordered Region lifetime work;
- host-recursive Query evaluation requires a product-owned active-depth policy;
- expected evaluation limits require typed unavailable observations;
- post-publication Structural Failure requires quarantine;
- persistence restoration requires semantic validation before runtime allocation;
- a Graph Surface requires a UI-neutral immutable snapshot seam.

Removing any of these would move complexity into every Nodeflow caller or violate a demonstrated invariant. They pass the deletion test.

## Accidental complexity of a permanent host matrix

A maintained clean-room, dual-backend, multi-engine regression would add:

- an archive-export contract to distribution tooling;
- a temporary-workspace orchestrator;
- Nodeflow-specific npm metadata and lockfile;
- a localhost asset server;
- Node JS and wasm loaders;
- Chromium, Firefox, and WebKit launch adapters;
- browser and Node version pins;
- path-filtered workflow ownership;
- eight host/backend result cells;
- browser downloads and associated CI failure surface.

No production caller currently depends on this machinery. Deleting it would not force complexity into a caller because no caller, package, deployment adapter, or support policy exists. It therefore fails the deletion test at the current stage.

The proposed host seam also has no real adapter. Temporary research loaders do not count as product adapters. A generic conformance framework before the first production host would formalize hypothetical variation and violate the one-adapter rule.

The host matrix remains a useful diagnostic recipe. It does not yet earn permanent implementation status.

## Options evaluated

### Permanent clean-room JS/wasm-gc host matrix

**What it proves:** packaged-kernel composition, source-fallback exclusion, both web backends, and several JS/WebAssembly engines.

**Cost:** highest test-infrastructure and browser-download burden; no current caller benefits.

**Decision:** do not implement until a product selects a support matrix or a second real host adapter exists.

### Single Chromium JS regression

**What it proves:** compiled Nodeflow JS executes in a real browser and preserves the typed depth outcome.

**Cost:** small, but still owns a hypothetical browser adapter. Node and Chromium also share V8, limiting engine information.

**Decision:** acceptable only if a maintainer explicitly requires a browser regression before a real consumer exists; not currently necessary because the exploratory run is green.

### Direct Canopy Canvas vertical slice

**What it proves:** actual product value, semantic/presentation authority, identity mapping, edit lowering, and rendering cadence.

**Cost:** cross-repository submodule and workspace work plus a required decision about Canvas's current durable graph model versus Nodeflow semantic authority.

**Decision:** commission as a separate product prototype when Canopy explicitly chooses Nodeflow as a candidate Semantic Graph authority. Do not hide this decision inside readiness tooling.

### Descriptor codec totality

One production abort remains in `examples/spikes/incr_query_nodeflow_kernel/nodeflow/document.mbt`: Nodeflow parses trusted application descriptor JSON and aborts if the application encoder returns invalid JSON.

Removing it cleanly requires choosing an application-owned `Json` conversion, a `ToJson` interface, a fallible public encoder, or another persistence adapter seam. Those choices affect the evidence package's public persistence interface.

**Decision:** resolve with an explicit persistence/publication direction. Do not create an accidental compatibility commitment solely to remove an unreachable trusted-encoder assertion.

### Browser memory and GC profiling

A retained-heap experiment could exercise repeated restore, edit, removal, snapshot, and close. No current evidence shows unbounded retained growth, and portable heap instrumentation differs by engine.

**Decision:** investigate only after a real long-lived host reproduces retention growth or establishes a memory budget.

### Persistence v1

Production persistence requires version dispatch, strict unknown-property policy, frozen descriptor codecs, golden fixtures, migration ownership, and compatibility documentation.

**Decision:** defer until a product commissions persistence or package publication. This is the least reversible option in the design space.

### No additional implementation

The prototype verdict is recorded, the known correctness and performance blockers have been addressed, and the host feasibility experiments are green.

**Decision:** selected.

## Final decision

Do not add a permanent host-conformance package or workflow now.

The repository should retain the current Nodeflow source, tests, performance snapshot, and this bounded host evidence. Issue #496 has fulfilled its stated purpose: build a finite headless prototype and conclude Adoptable, Promising with blockers, or Reject. Its recorded conclusion is **Adoptable optional layer**.

Closing Issue #496 is the appropriate bookkeeping action, but this document does not authorize that GitHub mutation. No broad production backlog should remain attached to the completed prototype issue.

No ADR is required. The decision preserves an evidence-only implementation and avoids a hard-to-reverse product commitment.

## Reopen gates

New Nodeflow implementation begins only when one of these gates has an owner and acceptance criteria.

### Gate A — real Graph Surface consumer

Trigger: Canopy Canvas or another Node UI explicitly selects Nodeflow for a prototype.

Then:

- design the Semantic Graph versus presentation/layout authority seam;
- build the smallest vertical slice in the actual host;
- keep browser acceptance in that host's CI;
- test only the backend and browser engines selected by the consumer;
- avoid a generic host framework until a second adapter exists.

### Gate B — Nodeflow package publication

Trigger: a maintainer commissions a distributable Nodeflow package.

Then:

- define package contents and public-consumer fixtures;
- select supported MoonBit targets and host versions;
- reuse the Incr Query candidate distribution seam;
- add clean-room package consumption and only the selected host matrix;
- verify registry name availability before publication.

### Gate C — production persistence

Trigger: a product commits to storing Graph Documents across releases.

Then:

- create the persistence-v1 ADR;
- define version dispatch and migration ownership;
- reject unknown fields that cannot be preserved;
- freeze descriptor codecs per wire version;
- add golden fixtures and migration tests;
- remove the descriptor codec abort within the selected adapter.

### Gate D — browser deployment without package publication

Trigger: a product chooses Nodeflow JS or wasm-gc for a deployed browser host.

Then:

- promote the relevant exploratory host recipe into that deployment adapter's tests;
- pin the actual browser support policy;
- test below-limit current and above-limit typed unavailable behavior;
- add no engines or backends outside the support policy.

### Gate E — retained-memory signal

Trigger: a long-lived host reproduces retained growth after restore/edit/remove/close, or adopts an explicit memory budget.

Then:

- isolate a repeatable workload;
- attribute retained objects before designing eviction;
- measure after explicit close and host GC where available;
- add memory policy only after identifying the owning lifetime.

### Gate F — depth beyond 256

Trigger: a real consumer requires a cold demanded path deeper than the configured active-Query policy.

Then:

- preserve the current typed limit as the baseline;
- prototype restartable/replayable Query semantics separately;
- do not add a Nodeflow scheduler or static graph-depth rejection;
- require the deeper consumer workload to justify the kernel change.

## Immediate disposition checklist

The evidence phase is complete when maintainers explicitly confirm:

- the merged Nodeflow verdict remains Adoptable optional layer;
- no publication or persistence compatibility is implied;
- the host experiment results are retained as bounded evidence, not a support matrix;
- Issue #496 is closed rather than expanded with unrelated production work;
- future implementation names one reopen gate and its product owner.

Until then, the correct engineering action is to preserve the current implementation and add no new Nodeflow mechanism.
