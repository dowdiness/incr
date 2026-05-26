# Build-Oriented Trait Boundaries

**Status:** Proposed

**Date:** 2026-05-26

**Inspired by:** Build systems à la carte (`build` package / paper)

## Goal

Describe how to structure build-style application code on top of `incr` using
small MoonBit traits. The design should preserve the useful split from Build
systems à la carte — separate task meaning, dependency discovery, cache storage,
and execution policy — without requiring Haskell-style higher-rank type classes
or higher-kinded types.

This is a proposal for application-level architecture, not a request to make the
core runtime language-aware.

## Motivation

Build-style applications repeatedly face the same failure mode: a single
"project" object starts by reading source, then grows parsing, import lookup,
checking, diagnostics, artifact emission, progress reporting, and cache policy
behind one broad interface. That makes it hard to test stages independently and
hard to tell which reads should become incremental dependencies.

The purpose of these traits is to make the seams explicit:

- `Source` owns acquisition of raw facts.
- `Parser` owns syntax only.
- `ImportResolver` owns name-to-key policy and workspace configuration.
- `Checker` owns semantic validation over parsed modules and resolved imports.
- `Transformer` / `Executor` owns final artifact production or planned effects.

`incr` should remain the cache/scheduler underneath those seams. The application
traits explain what is being computed; `Derived` and `DerivedMap` explain when it
needs recomputation.

The design principle is: reserve names for responsibilities that are already
visible in real pipelines, but defer shared abstraction until the value type and
failure mode are concrete. A named seam is useful when it prevents a broad
"project object" from absorbing unrelated work. A shared trait is useful only
when two consumers can use the same concrete signature.

## Existing `incr` responsibilities

The current API already covers most build-system infrastructure. New traits
should name application responsibilities, not duplicate scheduler or cache work.

| Existing type / trait | Responsibility in build-system terms |
|---|---|
| `Runtime` | The scheduler and store coordinator: owns revisions, dependency edges, batching, GC roots, cycle detection, push propagation, and memo-event hooks. |
| `RuntimeContext` / `Database` | A context capability that exposes the `Runtime` to helper constructors. It is not a source database or language database by itself. |
| `Input[T]` / `Signal[T]` | External mutable facts: editor buffers, file contents, compiler options, environment snapshots. `set` records changes and advances revisions. |
| `InputField[T]` / `TrackedCell[T]` | Field-level external facts for larger structs. Useful when a project model has independently mutable fields. |
| `Derived[T]` / `Memo[T]` | A cached task with one value. The compute closure is the MoonBit analogue of a task interpretation: it reads dependencies, returns a value, and the runtime records the edges. |
| `DerivedMap[K, V]` / `MemoMap[K, V]` | A keyed family of cached tasks. Each key gets a lazily created per-key derived cell. This is the natural representation for module/file/package tasks. |
| `ReachableDerived[T]` / `HybridMemo[T]` | A lazy task that can be kept alive by push-mode downstream subscribers. Use at boundaries where a UI or effect needs stable reachability. |
| `EagerDerived[T]` / `Reactive[T]` and `Effect` | Push-maintained values and side-effect sinks. Useful for UI/status surfaces, not for ordinary pull build steps. |
| `Scope` | Lifetime owner for cells created as part of a build graph or attachment. |
| `Watch[T]` / `Observer[T]` | Persistent read handle and GC root for terminal values that must survive `Runtime::gc()`. |
| `Freshness` / `Readable` | Generic freshness inspection. These traits do not describe build stages. |
| `Relation` / `MapRelation` | Bottom-up Datalog-style relations. Useful for declarative facts, but not required for a staged build pipeline. |
| `Accumulator[T]` | Side-channel collection from memo computes. Useful for diagnostics when the producer/consumer invalidation path is intentional. |

The deprecated `pipeline/` package currently contains `Sourceable`,
`Parseable`, `Checkable`, and `Executable`. Those traits return mostly
`String`-based values and are documented as an early sketch with no production
consumers. They should not be expanded into the core abstraction.

## MoonBit encoding constraints

The Haskell paper can quantify over a task algebra. MoonBit traits are
`Self`-based: they have no trait type parameters and no associated types. That
means a reusable trait cannot say "for any key type `k` and value type `v`."

Use this rule instead:

- Define the domain types in the application package: `ModuleKey`, `SourceText`,
  `ParsedModule`, `ImportGraph`, `CheckedModule`, `Diagnostic`, `Artifact`, and
  domain error enums.
- Define small traits whose method signatures mention those concrete domain
  types.
- Use generic functions over the context type, for example
  `Ctx : Source + ImportResolver + Parser`, while the key/value types remain
  fixed by the package.
- If a library truly needs to be generic over key/value choices, use a generic
  struct or function record, not a MoonBit trait pretending to have associated
  types.

This keeps trait bounds useful while staying inside MoonBit's type system.

## Proposed application-level traits

These names describe responsibilities. They should live in user code or in a
language/build adapter package, not in the `incr` root facade. Snippets in this
section are illustrative signatures over application-defined types, not checked
API examples.

### `Source`

Provides raw source for a key.

Responsibilities:

- Read external data such as file contents, editor buffers, database rows, or
  generated virtual files.
- Hide how data is acquired: in-memory `Input`s, filesystem snapshots, or a
  project database.
- Return domain failures as data when possible, so diagnostics can be cached and
  combined.

Example shape, using application-defined concrete types:

```moonbit
pub(open) trait Source {
  fn source_text(Self, ModuleKey) -> SourceResult
}
```

An implementation may call `Input::get()` or another `DerivedMap::get_or_abort`
inside `source_text`; when called from a `Derived` / `DerivedMap` compute body,
that read records the dependency.

### `ImportResolver`

Resolves dependency names to keys.

Responsibilities:

- Convert imports found in parsed source into canonical `ModuleKey`s.
- Apply search paths, package aliases, generated-module rules, or workspace
  overlays.
- Report unresolved or ambiguous imports as diagnostics.

```moonbit
pub(open) trait ImportResolver {
  fn resolve_imports(Self, ModuleKey, ParsedModule) -> ImportResolution
}
```

Keep this separate from parsing. Parsing discovers syntactic import clauses;
resolution turns them into build keys. The separation matters because import
policy changes more often than syntax: search paths, package aliases, generated
module overlays, and virtual workspaces can all change while the parser remains
unchanged. It also lets tools reuse the parser for syntax highlighting or outline
views without forcing workspace resolution to run.

### `Parser`

Parses raw source text into a structured representation.

Responsibilities:

- Convert `SourceText` into `ParsedModule` or a parse-error payload.
- Preserve syntax errors as data so downstream diagnostics can be incremental.
- Avoid knowing how source text was acquired.

```moonbit
pub(open) trait Parser {
  fn parse_module(Self, ModuleKey, SourceText) -> ParseResult
}
```

### `Checker`

Checks a parsed module and its resolved dependencies.

Responsibilities:

- Type-check, lint, validate names, or produce semantic diagnostics.
- Consume dependency outputs from other keyed tasks.
- Return diagnostics and any checked representation needed by later stages.

```moonbit
pub(open) trait Checker {
  fn check_module(Self, ModuleKey, ParsedModule, Array[CheckedImport]) -> CheckResult
}
```

This method should receive already-read dependency values rather than reaching
into the runtime directly when possible. The `DerivedMap` compute closure can
choose whether dependencies are read statically or dynamically.

### `Transformer` / `Executor`

Transforms checked intermediate values into final artifacts or executes planned
work.

Responsibilities:

- Lower, optimize, emit, interpret, run tests, or produce editor projections.
- Keep side effects explicit. Prefer returning an operation plan when the stage
  can be separated from execution.

```moonbit
pub(open) trait Transformer {
  fn transform_module(Self, ModuleKey, CheckedModule) -> TransformResult
}
```

Use `Transformer` for pure or mostly pure cached stages: lowering, indexing,
formatting, code generation to an in-memory artifact, or producing an operation
plan. Use `Executor` only at an effect boundary: writing files, launching a
process, running tests, or sending work to a remote service. A `Transformer`
result can be safely stored in `DerivedMap`; an `Executor` should usually consume
a `BuildPlan` outside the compute closure or from a clearly owned `Effect`.

Diagnostics and artifacts should remain application-defined data. Prefer a
single diagnostic envelope for a package, such as `Diagnostic` with fields for
source range, severity, message, and stage. Prefer typed artifact wrappers such
as `CheckedModule`, `EmitPlan`, or `ArtifactPath` over generic `String` results.
If these types cannot be named yet, keep the trait local instead of widening it
to `Array[String]`.

## Composing traits into incremental tasks

A build graph should be an ordinary struct that owns a `Scope`, stage maps, and
terminal `Watch` handles. Each stage is represented by an `Input`, `Derived`, or
`DerivedMap` depending on cardinality and mutability.

Typical module pipeline:

| Stage | `incr` representation | Dependencies read inside compute |
|---|---|---|
| Source facts | `Input[SourceText]` per open buffer, or a `DerivedMap[ModuleKey, SourceResult]` over a `Source` provider | External source inputs or snapshot maps |
| Parse | `DerivedMap[ModuleKey, ParseResult]` | Source stage for the same key |
| Import resolution | `DerivedMap[ModuleKey, ImportResolution]` | Parse stage for the same key, plus resolver configuration inputs |
| Check | `DerivedMap[ModuleKey, CheckResult]` | Parse stage, import-resolution stage, and checked outputs for imported keys |
| Transform | `DerivedMap[ModuleKey, TransformResult]` | Check stage for the same key and, if needed, checked dependencies |
| UI/status surface | `ReachableDerived`, `EagerDerived`, or `Watch` over terminal maps | The terminal tasks the UI observes |

The build graph can then expose methods such as `check(key)` or
`artifact(key)` that perform outside-graph reads via `read()` /
`read_or_abort()` or through a persistent `Watch`.

### Static and dynamic dependencies are both supported

Build systems à la carte distinguishes applicative tasks with statically known
dependencies from monadic tasks that discover dependencies while executing.
`incr` does not need separate task classes for that split:

- Static dependencies are just reads made unconditionally by the compute
  closure.
- Dynamic dependencies are reads made after inspecting earlier results, such as
  parsing imports before calling `checked.get_or_abort(import_key)`.
- `DerivedMap` records the actual keys read during the current run and updates
  the dependency set on recompute.

That gives the useful applicative/monadic distinction without encoding higher
kinded task interpreters in MoonBit.

A mixed example is a module diagnostics task:

1. It always reads the source and parser configuration for `key`. Those are
   static dependencies for this task shape.
2. It parses the source. If parsing fails, it returns parse diagnostics and does
   not read imports.
3. If parsing succeeds, it resolves imports. The set of imported module keys is
   discovered from the parsed syntax and workspace policy.
4. It reads `checked.get_or_abort(dep_key)` for each resolved import. Those are
   dynamic dependencies; changing the import list changes the dependency set on
   the next recompute.

`DerivedMap` handles both cases because the runtime records the reads actually
performed by the compute closure, then diffs the dependency set when the key is
recomputed.

### Module-diagnostics sketch

This illustrative compute body shows how a real stage should keep errors as
values while using `DerivedMap` reads to register dependencies:

```moonbit
let source = graph.sources.get_or_abort(key)
match source {
  Err(diag) => CheckResult::errors([diag])
  Ok(text) =>
    match ctx.parse_module(key, text) {
      Err(parse_diags) => CheckResult::errors(parse_diags)
      Ok(parsed) =>
        match ctx.resolve_imports(key, parsed) {
          Err(resolve_diags) => CheckResult::errors(resolve_diags)
          Ok(imports) => {
            let checked_imports : Array[CheckedImport] = []
            for dep in imports.keys() {
              match graph.checked.get_or_abort(dep) {
                Ok(dep_result) => checked_imports.push(dep_result.as_import())
                Err(cycle) => return CheckResult::cycle(cycle)
              }
            }
            ctx.check_module(key, parsed, checked_imports)
          }
        }
    }
}
```

This is still pseudocode: `SourceResult`, `ParseResult`, `CheckResult`, and
cycle-handling policy belong to the application. The structural point is that
source, parser configuration, import resolution, and imported modules become
ordinary tracked reads rather than a separate build scheduler protocol.

A dependency-resolution failure should normally be cached as a value, not raised
as a runtime failure. For example, `resolve_imports` can return
`Err(resolve_diags)` when an import is missing or ambiguous. The check stage then
returns those diagnostics and deliberately does not read the unresolved module's
`graph.checked` entry. That means the current module depends on the source,
parser config, and resolver config, but not on a nonexistent module key. When the
workspace mapping changes and resolver config is updated through an `Input`, the
resolution stage recomputes and may add the now-resolved module as a new dynamic
dependency.

Reserve `raise Failure` for broken invariants or unrecoverable host errors. User
facing build failures — missing files, parse errors, type errors, unresolved
imports, emit conflicts — should be represented in domain result values so the
incremental graph can cache and combine them.

## Represent operations as data

When a stage means "compile this module", avoid performing all side effects in a
compute closure. Prefer a data representation that later code can interpret:

```moonbit
pub(all) enum BuildOperation {
  Resolve(ModuleKey)
  Parse(ModuleKey)
  Check(ModuleKey)
  Emit(ModuleKey, ArtifactPath)
  Run(ModuleKey)
}

pub(all) struct BuildPlan {
  operations : Array[BuildOperation]
  diagnostics : Array[Diagnostic]
}
```

Returning plans from `DerivedMap` stages enables undo logs, progress reporting,
deferred execution, dry runs, and deterministic tests. Effects should live at
edges: event handlers, CLI drivers, or `Effect` nodes whose lifecycle is clear.

A tagless plan algebra can sit on top of this data if a consumer has at least
two real interpretations, such as execution planning plus progress rendering.
Do not introduce this layer only because it is theoretically elegant:

```moonbit
pub(open) trait BuildPlanSym {
  fn empty() -> Self
  fn op(BuildOperation) -> Self
  fn sequence(Self, Self) -> Self
  fn depends_on(Self, Self) -> Self
}

pub(open) trait ModuleBuildSym : BuildPlanSym {
  fn parse(ModuleKey) -> Self
  fn check(ModuleKey) -> Self
  fn transform(ModuleKey) -> Self
}
```

Concrete `ModuleBuildSym` implementations can lower these methods to
`Self::op(...)`. This trait is a plan builder, not the typed execution
interface; execution still happens through `Source`, `Parser`, `Checker`,
`Transformer`, and `DerivedMap` stages. Keep it out of the first prototype
unless a second interpretation is actually used.

## Adoption path

Use this proposal in this order:

1. Pick one real consumer pipeline, preferably a small module/file diagnostics
   path rather than a full compiler.
2. Define `ModuleKey`, diagnostic, parsed, checked, and artifact types in that
   consumer package.
3. Define only the traits needed by that pipeline. If the first prototype does
   not emit artifacts, skip `Transformer`; if it does not execute effects, skip
   `Executor`.
4. Wire stages with `Scope`-owned `DerivedMap`s and expose reads through methods
   or terminal `Watch` handles.
5. Add a checked example or integration test that changes source/import config
   and demonstrates dependency-set changes.
6. Only after that, decide whether plan data or `BuildPlanSym` adds value.

This keeps the first validation grounded in `incr` behavior rather than in an
abstract build DSL.

## Current `pipeline/` package policy

The existing `dowdiness/incr/pipeline` package is deprecated. Do not grow
`Sourceable`, `Parseable`, `Checkable`, or `Executable` into this proposal's
API. They are string-oriented compatibility traits, not a proven shared build
model.

A future migration should either:

- remove the package once downstream code has a better local replacement; or
- replace it with a separate optional package after the promotion criteria below
  are met.

Until then, documentation should describe `pipeline/` as a sketch and new
examples should use local traits in the consuming package.

## Promotion criteria for shared traits

Keep these traits local until there is evidence that a shared package would
remove real duplication rather than freeze a speculative API. Promotion is
reasonable only when all of the following are true:

1. Two independent consumers use the same concrete domain types or can agree on
   a small shared vocabulary without stringly-typed fallbacks.
2. The traits have checked examples or integration tests showing incremental
   behavior, not just direct method calls.
3. The split improves replacement of one stage without forcing unrelated stages
   to implement no-op methods.
4. Error and diagnostic types are stable enough that the trait signatures do not
   need associated types to stay useful.
5. The package can remain optional; importing `incr` alone should not imply a
   compiler/build pipeline dependency.

If these conditions are not met, prefer local traits plus `DerivedMap` wiring.

## What belongs in `incr` core

Keep core `incr` generic:

- Continue exposing runtime/cell capabilities: `RuntimeContext`, `Freshness`,
  `InputFieldOwner`, `Scope`, `Watch`, and construction helpers.
- Do not add `Parser`, `Checker`, `ImportResolver`, or `Transformer` to the root
  package; their method signatures need application-specific concrete types.
- Treat the current `pipeline/` package as deprecated. A future replacement
  should be driven by a real consumer and should either live with that consumer
  or be a separate optional package with concrete domain types.

## Benefits retained from Build systems à la carte

- **Clear separation of concerns:** source acquisition, dependency resolution,
  parsing, checking, transformation, scheduling, and caching have separate
  owners.
- **Composable tasks:** each stage is a `Derived` or `DerivedMap` and can be
  replaced independently when the trait boundary is stable.
- **Dynamic dependency support:** imports discovered during parsing can drive
  keyed reads during checking or transformation.
- **Reusable runtime:** `incr` remains a general incremental computation
  framework rather than becoming a compiler pipeline framework.
- **MoonBit fit:** genericity is expressed with context trait bounds and concrete
  domain types, avoiding unrepresentable associated-type or HKT designs.

## Suggested next steps

1. Prototype these traits in the first real consumer package, using that
   package's concrete key, source, syntax, diagnostic, and artifact types.
2. Build the pipeline as a struct with `Scope`-owned `DerivedMap` stages and a
   terminal `Watch` for long-lived reads.
3. Add checked examples for the real pipeline before promoting any trait to a
   shared package.
4. Once two consumers share the same concrete abstractions, decide whether a
   small optional package is warranted. Until then, keep the traits local.
