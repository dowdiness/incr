# Build-Oriented Boundary Design

**Status:** Proposed — ideal design, breaking changes allowed

**Date:** 2026-05-26

**Inspired by:** Build systems à la carte (`build` package / paper)

**Related:** [Internal Evaluation Boundaries](2026-05-26-internal-rebuild-boundaries.md), [Evaluation Strategy Refactor Plan](../../plans/2026-05-26-evaluation-strategy-refactor.md)

## Goal

Describe the ideal way to structure build-style application code on top of
`incr`. The design keeps the useful split from Build systems à la carte — task
meaning, dependency discovery, cache storage, execution policy, and effect
boundaries are separate — while fitting MoonBit's concrete, `Self`-based trait
system.

The ideal design is broader than "add small traits". Traits are one possible
seam. The preferred seam depends on what varies:

- use a **concrete facade** when one package owns the domain and lifecycle;
- use an **attachment struct** when a stage is rooted on a parser/runtime;
- use a **function record** when callers inject deterministic policy;
- use a **small trait** only when multiple implementors share the same concrete
  domain types and method signatures;
- use **operation/request data** for effectful work.

This document is about application architecture. It is not a request to make the
`incr` core language-aware.

## North star

`incr` owns **when** cached computations run. Application packages own **what**
those computations mean.

- `Runtime`, `Input`, `Derived`, `DerivedMap`, `Scope`, and `Watch` are the
  build scheduler/store substrate.
- Parser, checker, diagnostic, artifact, provider, and executor concepts are
  domain-owned.
- Effects happen at the edge. Network, filesystem writes, process execution,
  and LLM calls must not run inside `Derived` closures.
- Dynamic dependencies are ordinary tracked reads. A stage can read different
  keys after parsing imports, ranking context, or selecting request inputs.
- Public domain APIs expose stable domain data or terminal `Derived` cells;
  they do not expose broad "project" objects that silently own every stage.

## What changed after loom lambda and Canopy

The recent loom lambda and Canopy changes provide the first concrete evidence
for the ideal boundary:

- `@loom.Parser[Ast]` is a concrete parser facade, not a parser trait.
- `examples/lambda/src/analysis.mbt` owns `LambdaAnalysis`,
  `LambdaDiagnostic`, and `LambdaDiagnosticPhase` in the lambda package.
- `examples/lambda/src/typed_parser.mbt` exposes `TypecheckAttachment`, with a
  result `Derived`, terminal `Watch`, and explicit `dispose()`.
- Canopy removed an FFI-local lambda typecheck bundle and adopted the loom-owned
  `LambdaAnalysis` attachment through `LambdaCompanion::typecheck_output()`.
- Canopy exports selected terminal `Derived` cells as workspace
  `ProtectedCell`s, leaving lifetime and coordinator policy outside the lambda
  checker.
- Canopy cognition uses `CognitionProvider` and `ContextRanker` as deterministic
  function-record policies, while its provider-boundary plan keeps real async
  provider effects outside recomputation.

The lesson is not "promote Parser/Checker traits to `incr`". The lesson is
"move each seam to the package that owns its domain types and lifecycle".

## MoonBit encoding constraints

MoonBit traits have `Self`, but no trait parameters and no associated types.
Therefore a reusable trait cannot express "for any key type and value type".
Every non-`Self` type in a trait method must be concrete.

Use this rule:

1. Define domain types in the consuming package: keys, syntax, diagnostics,
   checked artifacts, provider request descriptors, operation plans, and errors.
2. Pick the seam form after the types are known.
3. Do not invent stringly shared traits just to avoid local code.
4. Promote only after two real consumers can share the same concrete vocabulary.

This makes domain boundaries explicit without pretending MoonBit has associated
types.

## Build Systems à la Carte mapping

The design borrows BSaC's separation of task meaning, store, scheduler, and
rebuilder, but adapts it to `incr`'s typed cell graph instead of recreating the
Haskell type-class API.

| Build Systems à la Carte concept | `incr` / MoonBit adaptation |
| --- | --- |
| `Task` | A `Derived` / `DerivedMap` compute closure. The closure describes what one key computes. |
| `fetch` | `.get()` / `.get_or_abort()` inside a compute closure. These reads discover dependencies. |
| `Tasks` | A package-owned family of stage cells, usually several typed `DerivedMap`s rather than one generic map. |
| `Store` | `Runtime` + typed wrapper caches + internal SoA storage. Application code should not own scheduler state. |
| Trace / `Info` | Dependency lists, source revisions, `changed_at`, `verified_at`, durability, and domain provenance such as context items. |
| `Rebuilder` | Internal pull verification: freshness, dependency scan, synthetic dependency checks, recompute, and backdating. |
| `Scheduler` | Runtime evaluation order: demand-driven pull reads, eager push propagation, batch commit, and fixpoint loops. |
| Applicative tasks | Compute closures whose dependency set is structurally fixed. |
| Monadic tasks | Compute closures that choose later reads after inspecting earlier results, such as imports or ranked context. |

The key adaptation is **typed multi-store**. BSaC examples often present one
`k -> v` store. MoonBit users should prefer multiple typed stores:

```moonbit
// Illustrative shape, not a root `incr` API.
parse_results : @incr.DerivedMap[ModuleKey, ParseResult]
resolved_imports : @incr.DerivedMap[ModuleKey, ImportResolution]
checked_modules : @incr.DerivedMap[ModuleKey, CheckResult]
artifacts : @incr.DerivedMap[ModuleKey, TransformResult]
```

This avoids forcing every stage into one large sum type or a stringly artifact
map. Cross-stage dependencies are ordinary reads between the typed maps.

The second adaptation is that scheduler/rebuilder selection belongs to `incr`,
not to application stage traits. An application may expose domain tasks and
plans, but it should not own freshness, verification, dependency storage, or GC
root semantics.

## Boundary taxonomy

### Concrete engine facade

Use this when one package owns stateful engine lifetime.

`@loom.Parser[Ast]` is the reference pattern: it owns one imperative parser
engine and publishes source, syntax, AST, diagnostics, and snapshot views as
`Derived` cells on one runtime.

Do not wrap this in a generic `Parser` trait unless two independent parser
facades need the same concrete method signatures. The name `Parser` in this
document is a role, not a recommendation to define `trait Parser`.

### Attachment facade

Use this when a domain analysis is attached to an existing parser/runtime.

Reference shape:

```moonbit
pub(all) struct LanguageAnalysis {
  parser : @loom.Parser[Ast]
  scope : @incr.Scope
  result : @incr.Derived[AnalysisResult]
  watch : @incr.Watch[AnalysisResult]
}

pub fn attach_language_analysis(parser : @loom.Parser[Ast]) -> LanguageAnalysis
pub fn LanguageAnalysis::result(self : LanguageAnalysis) -> AnalysisResult
pub fn LanguageAnalysis::result_cell(self : LanguageAnalysis) -> @incr.Derived[AnalysisResult]
pub fn LanguageAnalysis::dispose(self : LanguageAnalysis) -> Unit
```

`LambdaAnalysis` and `TypecheckAttachment` are the current concrete examples.
The attachment owns only its scopes and watches; the parser remains owned by the
caller.

### Reactive read and lifetime discipline

Every domain facade should make the inside/outside graph boundary obvious:

- inside `Derived`, `DerivedMap`, `ReachableDerived`, `EagerDerived`, or
  attachment compute closures, read inputs with `.get()` and upstream derived
  cells with `.get_or_abort()` or `.get()` when cycle results are handled as
  data;
- outside the graph, read through `.read()` / `.read_or_abort()` or through a
  persistent `Watch`;
- an attachment with public `result()` / `diagnostics()` methods should hold a
  terminal `Watch` so the chain survives `Runtime::gc()`;
- a downstream subscriber that should react to changes should receive a narrow
  `Derived` accessor such as `typecheck_output()`, not the whole attachment's
  mutable/lifetime internals;
- `dispose()` releases only the scopes and watches owned by that facade.

This rule is part of the boundary, not just an implementation idiom. It is what
lets Canopy protect lambda cells through a coordinator without owning the lambda
analysis pipeline.

### Function-record policy

Use this when callers inject deterministic pure policy and there is no need for
method dispatch over an object hierarchy.

Examples:

```moonbit
pub(all) struct CognitionProvider {
  file_summary : (String, String) -> String
  repo_summary : (Array[String]) -> String
}

pub(all) struct ContextRanker {
  score_summary : (String, CognitionKey) -> Int
  reason_summary : (String, CognitionKey) -> String
}
```

These are intentionally synchronous and deterministic. They produce values or
scores only; the store keeps graph ownership.

### Small trait

Use a trait only when all of the following are true:

- the method signatures mention concrete domain types;
- at least two implementors are expected;
- the trait replaces real duplication rather than thin forwarding;
- implementors should be swappable without taking ownership of unrelated stages.

Good traits are narrow capabilities. Bad traits are broad project objects.

### Operation/request data

Use data when work crosses an effect boundary.

```moonbit
pub(all) enum BuildOperation {
  Parse(ModuleKey)
  Check(ModuleKey)
  Emit(ModuleKey, ArtifactPath)
  Run(ModuleKey)
}

pub(all) struct ProviderRequest {
  id : ProviderRequestId
  target : BuildKey
  model_id : String
  options_fingerprint : String
  dependencies : Array[BuildKey]
}
```

A `Derived` can build a plan or request descriptor. A driver outside the graph
executes it and reports completion through an explicit API.

## Existing `incr` responsibilities

`incr` already covers the build-system substrate. Do not duplicate these with
application traits.

| Existing type | Build-system responsibility |
| --- | --- |
| `Runtime` | Scheduler/store coordinator: revisions, dependency edges, batching, GC, cycle detection, push propagation, observation hooks. |
| `Input[T]` | External mutable facts: buffers, file snapshots, options, cancellation flags, fake time. |
| `InputField[T]` | Field-level mutable facts inside larger structs. |
| `Derived[T]` | One cached task. Reads inside the closure become dependencies. |
| `DerivedMap[K, V]` | Keyed cached task family. Natural for module/file/request keyed stages. |
| `ReachableDerived[T]` | Lazy task kept reachable by push downstream consumers. |
| `EagerDerived[T]` / `Effect` | Push-maintained surfaces and owned side-effect sinks. Use carefully at effect edges. |
| `Scope` | Lifetime owner for cells created by a graph or attachment. |
| `Watch[T]` | Persistent outside-graph read handle and GC root. |
| `Accumulator[T]` | Intentional side-channel collection from compute bodies. Useful for diagnostics when invalidation semantics are understood. |

The deprecated `pipeline/` package's `Sourceable`, `Parseable`, `Checkable`, and
`Executable` traits are string-oriented sketches. In an ideal breaking design,
remove that package or move it to an archive/example. Do not evolve it into the
shared model.

## Task graph first, stages second

Treat source, parse, resolution, checking, transformation, and provider planning
as examples of keyed tasks. The primary design question is not "which trait name
should this stage implement?" but:

1. What is the key?
2. What typed value is cached for that key?
3. Which reads discover the dependency trace?
4. Which errors are domain values rather than runtime failures?
5. Which terminal cells need `Watch` roots or downstream `Derived` accessors?
6. Which effects must be represented as operation/request data instead of run in
   the compute closure?

Once those answers are concrete, choose a facade, attachment, function record,
small trait, or operation data type. Stage names are useful vocabulary, but the
`Derived` / `DerivedMap` task graph is the actual build-system structure.

## Ideal stage boundaries

The following names describe common task roles. They should live in a consumer
or domain adapter package, not in `incr` root.

### Source facts

Source acquisition is either external input state or a deterministic provider
method. It should not know parser/checker internals.

Representations:

- `Input[SourceText]` for editor buffers or file snapshots;
- `DerivedMap[ModuleKey, SourceResult]` for virtual source lookup;
- a function-record policy when tests inject deterministic text.

A trait is optional and only useful once concrete domain types are stable.

### Parse stage

Prefer a concrete parser facade when stateful incremental parsing matters. For
loom languages, use `@loom.Parser[Ast]` directly and expose its `Derived` views.

If a pure parse helper exists, keep it local:

```moonbit
pub fn parse_module(ModuleKey, SourceText) -> ParseResult
```

Only introduce a parse trait when multiple concrete parsers share the same
`ModuleKey`, `SourceText`, and `ParseResult` types.

### Import/dependency resolution

Keep syntactic import discovery separate from workspace policy. Resolution owns
search paths, package aliases, overlays, generated modules, and unresolved or
ambiguous import diagnostics.

A resolution stage is usually a `DerivedMap[ModuleKey, ImportResolution]` that
reads parsed syntax and resolver configuration inputs.

### Check/analysis stage

For language analysis, prefer an attachment facade rooted on the parser runtime.
It owns the analysis scope, terminal watch, and domain diagnostics.

`LambdaAnalysis` is the model:

- parser diagnostics and typecheck diagnostics are wrapped in a lambda-owned
  diagnostic envelope;
- the combined diagnostic `Derived` reads parser diagnostics and typecheck
  result inside its compute body;
- a terminal `Watch` keeps parser and analysis internals reachable through GC;
- `dispose()` tears down only analysis-owned scopes.

### Transform/artifact stage

Use `Derived` or `DerivedMap` for pure transformations: lowering, formatting,
indexing, projection, in-memory code generation, or plan construction.

Expose terminal cells through narrow accessors when another package needs to
subscribe:

```moonbit
pub fn Companion::artifact_cell(self : Companion) -> @incr.Derived[Artifact]
```

This is the shape Canopy uses for projection, eval escalation, and typecheck
output.

### Execute/effect stage

Executors run outside ordinary `Derived` recomputation. They consume plans or
request descriptors and call explicit completion APIs.

Use `Effect` only when the lifecycle is clearly owned and the side effect is a
reactive terminal surface. Do not hide network I/O, filesystem writes, or
process launches in a reusable "checker" or "transformer" interface.

## Dynamic dependencies

Build systems à la carte distinguishes static and dynamic dependencies. `incr`
already supports both:

- static dependencies are unconditional reads in a compute closure;
- dynamic dependencies are reads selected after inspecting earlier results;
- `DerivedMap` records the keys actually read during the current run and diffs
  them on recompute.

A module diagnostics task can parse a file, discover imports, resolve them, and
then read `checked.get_or_abort(dep_key)` for each resolved dependency. A query
context task can rank candidate summaries and depend only on selected items. A
provider-request planning task can snapshot the dependency set selected for one
request.

The application should treat missing files, parse errors, type errors,
unresolved imports, provider rejection, and budget overflow as domain result
values when possible. Reserve runtime failure for broken invariants.

## Effect boundary discipline

Effectful providers and executors need request/completion data, not broad
callbacks that mutate graph state.

A future LLM/provider boundary should follow these rules:

1. Planning is synchronous and deterministic. It may use `Derived` cells to build
   request descriptors, dependency fingerprints, retry classifications, and
   visible status.
2. The request descriptor records target key, provider/model/options
   fingerprint, selected context, source revisions, dependency keys, and a stable
   idempotency key.
3. A driver outside the graph performs async transport, cancellation, retry,
   credential lookup, and redaction.
4. Completion is an explicit store/domain operation. It validates request id,
   option fingerprint, source revisions, dependency fingerprint, liveness, and
   budget limits before accepting output.
5. Stale completion never overwrites a newer artifact.

This keeps `incr` useful for planning/status while preserving the hard rule: no
real network or provider call runs inside a `Derived` closure.

## Breaking recommendations

If the project is optimizing for the ideal design rather than compatibility:

1. **Remove or quarantine `incr/pipeline`.** Its stringly traits are not the
   future shared API.
2. **Stop presenting `Parser`, `Checker`, `Transformer`, and `Executor` as
   default trait names.** Present them as roles. Pick concrete facade, record,
   trait, or data per role.
3. **Design typed task maps before stage traits.** Prefer typed multi-store
   layouts over one untyped artifact map.
4. **Use target facade names in new APIs.** Prefer `Input`, `Derived`,
   `DerivedMap`, `Watch`, and `read_or_abort` / `get_or_abort` over compatibility
   names.
5. **Promote domain facades, not generic traits.** Canopy's move from an
   FFI-local lambda typecheck bundle to loom's `LambdaAnalysis` is the right kind
   of promotion.
6. **Expose terminal `Derived` cells only through narrow accessors.** This lets
   coordinators subscribe without owning the analysis internals.
7. **Represent effects as data.** Execution drivers consume plans/requests and
   report completion explicitly.
8. **Keep scheduler/rebuilder choice in `incr`.** Application packages may choose
   runtime profiles once they exist, but they should not implement freshness or
   dependency storage.

## Promotion criteria

Promote a local seam only when it has proven the right owner.

### Promote to a domain package when

- another package needs the exact same language/domain analysis;
- the domain package already owns the syntax, diagnostic, or artifact types;
- the facade can expose narrow `Derived`/value accessors without leaking
  lifecycle internals.

`LambdaAnalysis` moving into the lambda package and being reused by Canopy is the
reference case.

### Promote to a shared optional package when

- two independent domains share the same concrete vocabulary;
- checked examples demonstrate incremental behavior, not just method calls;
- replacing one stage does not force unrelated no-op methods;
- diagnostic/error types are stable enough without associated types;
- importing `incr` alone does not pull in a compiler/build pipeline dependency.

If these are not true, keep the seam local.

## Adoption path

1. Pick one real pipeline. Prefer a small diagnostics or request-planning path
   over a full compiler.
2. Define domain key, source, syntax, diagnostic, result, artifact, request, and
   error types in the owning package.
3. Choose the seam form for each role: concrete facade, attachment, function
   record, trait, or operation data.
4. Build stages with `Scope`-owned `Derived` / `DerivedMap` cells and terminal
   `Watch` handles where lifetime matters.
5. Expose narrow accessors for downstream subscribers.
6. Add tests that edit inputs, change dynamic dependencies, run `Runtime::gc()`,
   and dispose attachments.
7. Only then decide whether any seam deserves promotion.

## What belongs in `incr` core

Keep core `incr` generic:

- runtime/cell capabilities;
- target facades;
- dependency tracking;
- GC and lifetime primitives;
- observation hooks over runtime events;
- checked examples for reactive read/lifetime behavior.

Do not add language/build concepts to the root package:

- no root `Parser` trait;
- no root `Checker` trait;
- no root `ImportResolver` trait;
- no root `Transformer` or `Executor` trait;
- no provider/client HTTP surface;
- no generic build DSL that depends on stringly artifacts.

## Benefits retained from Build systems à la carte

- **Separate concerns:** source facts, parse, resolution, checking, transform,
  planning, scheduling, caching, and execution have distinct owners.
- **Composable tasks:** each pure stage is a `Derived` or `DerivedMap` and can be
  replaced where its domain seam is stable.
- **Dynamic dependencies:** imports, selected context items, or request inputs
  can drive keyed reads during a run.
- **Effect safety:** effectful work is planned as data and executed by drivers.
- **MoonBit fit:** genericity is achieved through concrete domain types,
  function records, and narrow traits only where the language can express them.

## Validation for implementation PRs

For changes inside `incr`:

```bash
moon fmt
moon info
moon check
moon test
```

For downstream migrations that update loom/Canopy consumers, also run the
relevant consumer tests, for example:

```bash
# from the dowdiness/loom repository root
cd examples/lambda && moon test

# from the dowdiness/canopy repository root
moon test ffi/lambda
```

Use the parent repositories' CI fan-out as source of truth when paths differ.

## Done criteria

- New build-style examples use domain-owned facades/records/data rather than
  root `incr` build traits.
- `incr/pipeline` is removed, archived, or clearly quarantined as legacy.
- Parser-attached analysis uses the parser runtime, correct inside/outside graph
  reads, terminal `Watch` roots, narrow `Derived` accessors, and explicit
  `dispose()`.
- Effectful provider/executor work is represented by request/operation data and
  executed outside `Derived` closures.
- Any public API break is intentional, documented, and reflected in generated
  `.mbti` diffs.
