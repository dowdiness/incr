# Nodeflow production-readiness options

**Date:** 2026-08-29

**Reader:** maintainers deciding how to harden the Incr Query Nodeflow layer without adding speculative machinery.

**Decision:** recommend a bounded root-read mechanism enforced by Incr Query and selected privately by Nodeflow, plus indexed restoration validation, exhaustive runtime state matching, and an explicit version-1 persistence contract. Do not add a Nodeflow scheduler, static graph-depth validator, async evaluator, or general Formula framework. Keep a Skyframe-style restartable Query as the strongest long-term experiment only if a real product must exceed the bounded depth.

**Keep until:** these recommendations are either implemented and compressed into durable ADRs, rejected by new evidence, or superseded by a newer production-readiness investigation.

**Disposition:** active research recommendation; not an implementation authorization or publication decision.

## Executive finding

A better near-term design exists than either “accept the host stack” or “build an iterative Nodeflow evaluator.” The kernel already knows the actual dynamic Query nesting through `EvalSession.active_stack`. A new bounded root read can stop before entering an unsafe nested Query, return a typed kernel error, and let Nodeflow project that product limit as an expected unavailable observation. This is smaller and more accurate than static graph-depth analysis and does not duplicate Incr Query.

A second better idea exists for the long term. Bazel Skyframe avoids suspending arbitrary direct-style callbacks: a function asks for a dependency, returns incomplete when it is unavailable, and is invoked again after the dependency completes. An opt-in restartable Incr Query constructor could use the same model with pure, replayable callbacks. It is more implementable in MoonBit than a hidden trampoline or heterogeneous continuation stack, but it is not justified until a consumer needs dependency depth beyond the bounded production envelope.

## Corrected evidence

### Deterministic cold-depth reproduction

The production-shaped test must be run by file path:

```bash
NEW_MOON_MOD=0 moon test --release --target js \
  examples/spikes/incr_query_nodeflow_kernel/nodeflow/deep_probe_wbtest.mbt
```

Using `-f deep_probe_wbtest.mbt` after a package path reports `no test entry found`; treating exit zero from that command as a pass is false evidence.

A cold test constructs one linear chain, performs one demanded `SetParameter`, and asserts the exact tail value. Results on the pinned toolchain:

| Target | Last passing depth | First observed failing depth |
|---|---:|---:|
| JavaScript | 500 | 600 |
| wasm-gc | 600 | 700 |
| native | at least 10,000 | not reached |

The JS failure is `RangeError: Maximum call stack size exceeded` through `QueryContext::get → eval_query → compute_query`. Running the same generated JS test under Node with `--stack_size=4096` makes depth 1,000 pass. This verifies that host stack capacity, rather than Graph validation or Surface projection, controls the failure.

The earlier `@bench.T` rows remain valid timing measurements for their own warmed benchmark process, but they are not a safe-depth acceptance test. MoonBit’s official benchmark documentation says `T::bench` automatically chooses a suitable iteration count and `T::keep` affects optimization; it does not claim that the benchmark runner reproduces cold production stack behavior. Production depth therefore needs a separate release test, not inference from a timing row.

Sources:

- [`query_context.mbt`](../../incr_query/kernel/query_context.mbt), `QueryContext::get_result`
- [`query.mbt`](../../incr_query/kernel/query.mbt), `eval_query`, `eval_query_slow`, and `compute_query`
- [MoonBit: Writing Benchmarks](https://docs.moonbitlang.com/en/latest/language/benchmarks.html)

### Restoration validation reproduction

A release JS microbenchmark times `validate_document` with a prebuilt document, excluding JSON decode and runtime allocation:

| Shape | N=1,000 | N=10,000 |
|---|---:|---:|
| Independent nodes | 292.54 µs | 3.50 ms |
| Linear bound chain | 2.99 ms | 188.97 ms |

The cause is concrete: restoration scans `wire.nodes` for each bound provider. The existing first pass already checks identity uniqueness; extending it to build `Map[Int, DocumentNode]` makes provider resolution expected O(1) and removes the measured quadratic shape. This optimization is now evidence-backed.

Source: [`restoration.mbt`](../../examples/spikes/incr_query_nodeflow_kernel/nodeflow/restoration.mbt), `validate_document`.

## Root cause

Current Query callbacks are direct-style MoonBit closures:

```text
compute(ctx)
  → ctx.get(child)
    → child recipe(ctx)
      → child compute(ctx)
        → ctx.get(grandchild)
```

`ctx.get` must synchronously return a typed value to the still-running caller. An internal `Array` worklist cannot suspend and later resume an arbitrary MoonBit closure at that call site. Iterativizing only memo verification is insufficient because cold and red computation still recurse through callback frames.

The current kernel correctly records dynamic dependencies only after successful nested reads, keeps temporary tracking frames outside committed memo state, gives cycle detection precedence through `core.active`, and preserves last-successful memo authority on failure. Any replacement must preserve all four properties.

## Design It Twice comparison

### A. Kernel-owned bounded root read — recommended now

**Interface sketch**

```text
Store::get_with_query_limit(view, max_active_queries)
  -> V
  raise ReadError including EvaluationLimitExceeded
```

`Store::get` remains unchanged for compatibility. The bounded operation installs `max_active_queries` in the private root `EvalSession`. `eval_query_slow` checks the current `active_stack.length()` before `core.active.set` and `active_stack.push`. Cycle lookup still occurs first, so a real Cycle keeps its current witness and precedence.

Nodeflow privately selects a conservative initial limit of 256 for its fixed, small-frame Formula closures. It catches only `EvaluationLimitExceeded` and maps it to explicit product outcomes:

- `EvaluationIssue::EvaluationLimitExceeded`
- `ActionInputIssue::EvaluationLimitExceeded`
- `OutputObservation::Unavailable`
- `ActionInvocationOutcome::Unavailable`

Other `ReadError` variants retain operation-specific typed `raise`. A budget breach is an expected product limit, not a malformed Graph Edit, so it must not become `GraphEditRejection`. Mapping it to an unavailable observation also lets `apply` publish a valid edit and return a coherent snapshot rather than raise after semantic state has already been installed.

**Why it is better**

- measures actual dynamic Query nesting, including dynamic dependencies;
- rejects no dormant or undemanded graph path;
- needs no SCC or longest-path maintenance;
- keeps the public Nodeflow interface shape;
- makes failure deterministic across JS, wasm-gc, and native;
- adds no scheduler, semantic graph, clock, or persistent policy.

**Limitations**

- bounds Query nesting, not arbitrary recursion inside user callbacks;
- the value 256 is a Nodeflow policy and must be validated in browser release builds;
- the kernel receives one narrow new root-read operation and one typed error variant.

### B. Static Nodeflow graph-depth validation — reject

This would calculate longest paths during binding edits and restoration, then reject graphs above a fixed depth.

It is weaker than A because it rejects undemanded paths, must define depth through cycles/SCCs, adds incremental graph-analysis machinery, and cannot protect direct Incr Query consumers or runtime dynamic dependencies. It also turns an observation resource policy into semantic Graph validity.

### C. Nodeflow calculation chain — reject

Excel constructs a dependency tree and a calculation chain, recalculates dirty cells in chain order, and adjusts the chain when an unmet dependency is encountered. This proves that an iterative graph evaluator is viable in a spreadsheet product.

For Nodeflow, however, implementing the same mechanism would create a second evaluator beside Incr Query: duplicate cache authority, cycle handling, invalidation, cutoff, lifetime, and transaction semantics. Closed descriptors make it technically possible but do not make the duplication desirable. It would weaken the evidence that Incr Query is the kernel.

Source: [Microsoft: Excel Recalculation](https://learn.microsoft.com/en-us/office/client-developer/excel/excel-recalculation).

### D. Hidden trampoline under existing callbacks — impossible as a full solution

A worklist can make verification iterative, but it cannot resume an arbitrary direct-style callback after `ctx.get` without compiler support, CPS, a resumable program representation, or replay. Claiming a no-interface-change trampoline would hide this unsolved continuation problem.

### E. MoonBit async/coroutines — reject

Compiler-supported async could theoretically supply resumable state machines, but it would turn a synchronous deterministic read into async execution. The official runtime currently supports native best, has limited JavaScript support, experimental Wasm1 support, and an unstable interface. It is the wrong dependency for the primary JS/wasm-gc Nodeflow seam.

Source: [MoonBit: Async programming support](https://docs.moonbitlang.com/en/latest/language/async-experimental.html).

### F. Restartable Query — strongest long-term experiment

Skyframe’s `SkyFunction` calls `env.getValue`; when a dependency is unavailable it returns incomplete, the dependency is evaluated, and the original function is invoked again. This avoids preserving an arbitrary continuation.

An opt-in Incr Query interface could follow that shape:

```text
RestartableContext::get(view) -> V?
RestartableStep[V] = Ready(V) | Await
Region::restartable(compute : (RestartableContext, K) -> RestartableStep[V])
```

A private scheduler keeps an explicit stack of type-erased `ensure` closures. A missing child returns `None`; the pure callback returns `Await`; the child is evaluated; then the parent callback restarts. Only the final successful invocation installs its dynamic trace and memo. Existing direct `Region::query` remains unchanged.

This requires deterministic, replay-safe callbacks. That matches Nodeflow’s pure application Formula contract and Salsa’s documented model of query functions as pure transformations. It does not match arbitrary effectful callbacks, so it must be opt-in and separately named.

Why it beats CPS/Formula DSL:

- no heterogeneous continuation value needs to cross the public interface;
- ordinary pattern matching and `Option` express dependency availability;
- source order and dynamic dependencies remain visible;
- the scheduler owns retry and cleanup without exposing runtime handles.

Why not implement it now:

- verification and computation both need restartable frames;
- callback replay semantics are a new interface commitment;
- current products have no demonstrated requirement beyond the recommended bound;
- it changes Incr Query’s public surface and needs differential tests against Fresh.

Sources:

- [Bazel Skyframe](https://bazel.build/reference/skyframe)
- [Salsa README](https://github.com/salsa-rs/salsa)

### G. Increase host stack or chunk the graph — reject

Node stack flags are unavailable as a portable browser/wasm contract. Artificial materialization nodes or chunk boundaries alter graph semantics and introduce shell-managed propagation. Neither is a production interface.

## Other production-readiness findings

### Remove production `abort`s

Four non-test aborts remain:

- math inputs “unexpectedly unavailable”;
- required OptionalOffset input “unexpectedly unavailable”;
- optional input “unexpectedly unavailable”;
- application descriptor JSON encode-then-parse.

The Formula aborts are artifacts of a two-pass state analysis. One exhaustive match can produce issues or evaluate only the all-current case, making impossible branches structurally absent. The codec abort disappears if the application package owns direct `Json` conversion instead of serializing to String and reparsing.

Concrete core candidates checked: `Option`, `Result`, pattern matching, `Json`, `ToJson`, and `FromJson`. Prefer direct `Json` functions or explicit v1 codec methods over a parse round-trip.

### Make post-publication structural failure state explicit

`Nodeflow::apply` installs runtime and semantic state before its demanded snapshot. If a true structural `ReadError` occurs afterward, it raises while leaving the edit installed. For production, those non-budget failures should quarantine the aggregate before raising, so the caller never continues with an ambiguously published graph. Budget exhaustion is different: it is projected as expected Unavailable and returns a normal snapshot.

### Own persistence v1 or do not publish it

The current interface publicly exposes `GraphDocument::encode_json` and `decode_json`, while prose calls the schema evidence-only. Production cannot promise both. The preferred choice is to rename the unpublished methods explicitly around v1, add golden fixtures, and commit to semantic v1 readability:

- newer readers continue to decode v1;
- unknown major versions reject before descriptor interpretation;
- v2, if needed, migrates purely into the current semantic document;
- canonical byte equality is a test aid, not the compatibility definition.

This is hard to reverse and should become an ADR only when publication is commissioned.

## Recommended implementation sequence

### P0 — deterministic safety

1. Add cold release depth probes for JS and wasm-gc using direct file-path execution.
2. Add kernel bounded root read and guard cleanup tests at `limit-1`, `limit`, and `limit+1`.
3. Set Nodeflow’s private limit to 256 and map only budget exhaustion to expected output/action unavailability.
4. Quarantine only on non-budget structural failures after publication.

### P1 — remove measured and explicit debt

5. Build a document-node Map during restoration validation; rerun the independent/chain restoration benchmarks.
6. Replace all four production aborts with exhaustive state matching and direct application-owned Json conversion.
7. Name and test the persistence v1 contract; defer publication until the compatibility decision is explicit.

### P2 — conditional research

8. Prototype restartable Query only if a real Nodeflow document requires depth above 256 or another Incr Query consumer needs stackless evaluation.
9. Differentially compare restartable and direct Query semantics for cold, green, red, cutoff, failure cleanup, dynamic dependency changes, and Cycle witnesses before considering adoption.

## Existing API First result

Reused or recommended:

- project: `EvalSession.active_stack`, `core.active`, `TrackingFrame`, `ReadError`, operation-specific Nodeflow outcomes, GraphDocument validation passes;
- core: `Map`, `Set`, `ReadOnlyArray`, `Option`, `Result`, `Json`, `ToJson`, `FromJson`, `@bench` clocks and benchmark harness.

Checked but rejected:

- static longest-path/SCC machinery — wrong seam;
- MoonBit async — unstable and target-misaligned;
- a Nodeflow topological cache — duplicate authority;
- hidden direct-style trampoline — cannot suspend arbitrary closures;
- host stack configuration — not portable;
- generic Formula/CPS framework — more caller burden than restartable replay.

## Verdict

The immediate recommendation is **bounded direct evaluation**, not an iterative rewrite. It raises production readiness with a small deep interface and converts a backend crash into deterministic product behavior. The genuinely better unbounded design is **restartable Query**, inspired by Skyframe, but it should remain a gated prototype until depth above 256 has a real driver.
