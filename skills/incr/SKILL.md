---
name: incr
description: Use when writing or reviewing MoonBit code against the `dowdiness/incr` reactive library (v0.14.x+) — building Inputs/Deriveds/ReachableDeriveds, attaching long-lived derived cells with `Watch`/`Observer`, adding microbenchmarks, or wrapping a reactive pipeline in a struct. Catches recurring idiom misses (inside-vs-outside read semantics, GC-anchor `Watch`/`Observer`, `Type::Type` constructor naming, defensive copies).
---

# incr

Reference for writing canonical `@incr` code. Adapt to context — these are
patterns the project consistently uses, not enforcement rules.

Citation paths in this skill are repo-relative to **this repo**
(`dowdiness/incr`) unless explicitly qualified with a sister repo
(`dowdiness/loom: …`). The `incr` library is also vendored as a
submodule of the `dowdiness/loom` monorepo; both views host the same
source tree.

## When to Use

Trigger keywords:
`@incr.Input`, `@incr.Derived`, `@incr.ReachableDerived`,
`@incr.InputField`, `@incr.EagerDerived`, `@incr.DerivedMap`,
`@incr.Watch`, `@incr.Observer`, `@incr.MapRelation`, `Scope::new`,
`scope.input`, `scope.derived`, `scope.reachable_derived`,
`scope.eager_derived`, `.read()`, `.read_or_abort()`,
`.get_or_abort()`, `.watch()`, `.observe()`, `add_observer`.

Also fires on: `parser.runtime()`, `attach_*`, `bench_test.mbt`,
`.bench(` — or any time you are defining a new struct that owns reactive cells
and exposes a `get`/`dispose` surface.

Sister skill: **loom** (parser-side conventions). If the task involves
calling `Parser::new` or `new_parser`, read that one too.

## Historical Mapping (names removed in v0.12.0 / v0.13.0 / v0.14.0)

`incr` 0.13.0 is a breaking release that removed the entire compatibility
API surface introduced during the v0.6.x target-facade migration; 0.14.0
followed with a boundary cleanup (ghost handle ids deleted,
invariant-bearing types closed, `Result`-channel retype). The names below
no longer exist — do not use them in new code, and if you encounter them
in older loom/canopy code, treat it as pre-0.14.0 code that needs
migrating to the current names.

| Removed (compat name) | Current API |
|------------------------|--------------|
| `Signal[T]` / `Signal::new` | `Input[T]` |
| `Memo[T]` / `Memo::new` | `Derived[T]` |
| `HybridMemo[T]` / `HybridMemo::new` | `ReachableDerived[T]` |
| `MemoMap[K, V]` | `DerivedMap[K, V]` |
| `TrackedCell[T]` / `create_tracked_cell` | `InputField[T]` / `create_input_field` |
| `Reactive[T]` / `Reactive::new` | `EagerDerived[T]` |
| `FunctionalRelation[T]` | `MapRelation[T]` |
| `Database` | `RuntimeContext` |
| `Readable` | `Freshness` |
| `Trackable` | `InputFieldOwner` |
| `scope.memo(...)` | `scope.derived(...)` |
| `scope.signal(...)` | `scope.input(...)` |
| `Scope::reactive(...)` | `Scope::eager_derived(...)` |
| `add_tracked(...)` | `add_input_fields(...)` or `scope.adopt(...)` |
| `InputField::as_tracked_cell` / `TrackedCell::as_input` | removed — use `InputField` directly |
| `memo.observe()` | `derived.watch()` |
| `rt.read(memo)` | `derived.read()` / `derived.read_or_abort()` |
| `rt.read_hybrid(h)` | `reachable.read()` / `reachable.read_or_abort()` |
| `rt.read_reactive(r)` | `eager.read()` |
| root re-exports `ReactiveId` / `FunctionalRelationId` | removed |
| `Accumulator::new(rt~, ...)` (removed 0.14.0) | `Accumulator(rt, label?)` — positional constructor |
| `InputId[T]` / `MemoId[T]` / `RelationId[T]` / `FunctionalRelationId[K, V]` (removed 0.14.0) | deleted ghost types — nothing produced or consumed them; use `CellId` if you need a raw id |
| `Input::get_result` / `InputField::get_result` returning `Result[T, CycleError]` (retyped 0.14.0) | now `Result[T, ReadError]`; a disposed input returns `Err(ReadError::Disposed(id))` instead of aborting |

Deprecated in 0.14.0 but still functional (positional `Type::Type` forms
are canonical): `Input::new` → `Input(rt, v)`, `Runtime::new` →
`Runtime()`, `Relation::new` → `Relation(rt)`, `Effect::new` →
`Effect(rt, f)`. Removal is planned for a post-`Expr[T]` breaking
release.

Also closed in 0.14.0: `Revision`, `InternId`, and `InternTable[T]` can
no longer be constructed via struct literals (use `Revision::initial()` /
`.next()`, `InternTable::new()` / `.intern(value)`); `DerivedMap`
constructors now require `V : Eq` (`::fallible` also `E : Eq`).

`Scope`, `DerivedEvent`, `CycleError`, `Observer`/`Watch` are unaffected.
See the CHANGELOG for the full removal list and any remaining edge cases.

## Quick Reference

| Situation | Use | Not |
|-----------|-----|-----|
| Read an `Input` from inside any compute closure | `input.get()` | wrapping in an outside-read API — Inputs are non-fallible; `.get()` records the dep at zero observer cost |
| Read a `Derived` / `ReachableDerived` from inside another compute closure | `derived.get_or_abort()` / `reachable.get_or_abort()` (strict) or `.get()` returning `Result` (graceful) | `.read_or_abort()` or `.read()` — outside-read APIs do one-shot observer work or obscure the tracked boundary |
| Read an `EagerDerived` from inside another compute closure | `eager.get()` | `eager.read()` — it is permissive and should be reserved for outside-graph reads unless a boundary wrapper deliberately needs that behavior |
| Read a `Derived` from outside the reactive graph (tests, top-level, non-tracked consumer methods) | `derived.read_or_abort()` or `derived.read() -> Result` (or persistent `watch.read_or_abort()` / `observer.get()`) | calling strict graph reads (`.get()` / `.get_or_abort()`) outside a tracked context aborts, or records a dependency if a compute frame is unexpectedly active |
| Read a `ReachableDerived` from outside the graph | `reachable.read_or_abort()` or `reachable.read()` (or `watch.read_or_abort()`) | — |
| Read an `EagerDerived` from outside the graph | `eager.read()` (or `watch.read_or_abort()` / `observer.get()`) | calling `eager.get()` outside a tracked context aborts |
| Read anything after `dispose()` | Don't — disposed cells/observers/watches abort | — |
| Define a new struct's primary constructor | `fn MyStruct::MyStruct(...) -> MyStruct` | `fn MyStruct::new(...) -> MyStruct` (older idiom; `Type::Type` is project convention per `~/.claude/moonbit-base.md`) |
| Attach long-lived derived cells to a parser/runtime | `Scope` + persistent `Watch` (preferred) or `Observer` — see templates below | Bare `Derived(rt, ...)` with no GC root — `rt.gc()` will sweep the chain |
| Use a library-provided constructor | `Input(rt, v, label=...)`, `Derived(rt, f, label=...)`, `ReachableDerived(rt, f, label=...)`, `Runtime()`, `Scope::new(rt)`, `derived.watch()` | Don't rename library APIs — the `Type::Type` convention is for *defining* new structs, not for *calling* upstream library constructors. `Watch` comes from `*.watch()`; `Observer` from `*.observe()`. Neither has `::new`. |

## Inside vs Outside the Graph (the big rule)

The read API splits along one axis: **am I inside a tracked compute
closure or not?**

**Inside a compute closure** (`Derived(rt, f, ...)`, `ReachableDerived`,
`EagerDerived`, `scope.derived`, `scope.reachable_derived`,
`scope.eager_derived`):

- `input.get()` — Inputs are non-fallible; just reads and records the dep.
- `derived.get_or_abort()` / `reachable.get_or_abort()` — strict read; aborts on cycle.
- `derived.get()` / `reachable.get()` — graceful read; returns `Result[T, CycleError]`.
- `eager.get()` — strict tracked read of an eager/push value. `EagerDerived` has no `Result` or `_or_abort` read channel.

These record the dep on the surrounding tracking frame at zero observer
cost.

**Outside the graph** (top-level, tests, event handlers, non-tracked
consumer methods):

- `derived.read_or_abort()` / `reachable.read_or_abort()` — strict; aborts on cycle.
- `derived.read()` / `reachable.read()` — returns `Result[T, CycleError]`.
- `eager.read()` — reads the current eager/push value outside the graph.
- Through a long-lived anchor: `watch.read_or_abort()` / `watch.read()`
  (or `observer.get()`).

The read channel — `Derived` / `ReachableDerived` `.get()` / `.read()`,
`DerivedMap` `.get(key)` / `.read(key)`, and `Watch::read()` — currently
returns `Result[..., CycleError]`. `DerivedMap::read_or(...)` and
`DerivedMap::read_or_else(...)` return the value `V` directly after
applying their fallback. Disposed cells still abort on strict reads. Keep
generated code matching on `CycleError` until a broader read-error API
appears in `cells/pkg.generated.mbti`.

### Why mixing breaks

Calling `derived.read_or_abort()` / `reachable.read_or_abort()` from
inside a compute closure opens and closes a one-shot observer to do the
read, on top of the tracking frame that's already live. The 2026-05-18
measurement put the inflation at ~25–30% on layered/tree shapes (see
`feedback_api_misuse_pattern.md`). Correctness is fine, so the bug is
invisible without a microbench.

Calling strict graph reads (`derived.get()`, `derived.get_or_abort()`,
`reachable.get()`, `reachable.get_or_abort()`, `eager.get()`) at top
level aborts outside a tracked context; inside a helper that happens to
run during another compute, it records a dependency on that active
frame. Outside code should use read/watch APIs instead.

### Examples

```moonbit
// ✅ Inside a Derived body
let total = Derived(
  rt,
  () => subtotal.get_or_abort().to_double() + tax.get_or_abort(),
  label="total",
)

// ❌ Inside a compute closure — pays the observer lifecycle every recompute
let typed_derived = scope.derived(
  fn() { @typecheck.convert_from_cst(parser.syntax_tree().read_or_abort()) },
)

// ✅ Outside the graph
let snapshot = parser.syntax_tree().read_or_abort()
match total.read() {
  Ok(v) => println("Total: \{v}")
  Err(e) => println(e.format_path())
}

// ✅ Outside the graph through a persistent anchor
let result = attachment.watch.read_or_abort()    // Watch
let result = attachment.observer.get()           // Observer
```

Canonical references:

- `docs/target_api_examples.mbt.md` — checked literate examples
  (`Input`, `Derived`, `Scope`, `Watch`, `read_or_abort`, `get_or_abort`).
- `docs/getting-started.md` — narrative version with the
  inside-vs-outside rule called out.
- `tests/bench_test.mbt` — bench template; canonical bench surface.
- `dowdiness/loom: examples/lambda/src/typed_parser.mbt:59` —
  `scope.derived` + `.get_or_abort()` pattern in real downstream use.
- `dowdiness/loom: examples/lambda/src/callers/callers.mbt:133` — same.

## The Persistent-Anchor GC Rule

`Runtime::gc()` marks reachability via BFS from `gc_root_counts`, which
`derived.watch()` / `derived.observe()` increment. One-shot
`derived.read_or_abort()` creates and disposes the anchor immediately —
so it does NOT keep the cell alive across a later `gc()`. Interior
Deriveds with no anchor get swept; subsequent reads abort.

**Rule:** if you build a downstream chain that should survive
`Runtime::gc()` (anything stored in a struct field with a public `get`),
hold a persistent `Watch` or `Observer` on the terminal Derived. The
recommended anchor form is **`scope.watch(derived)`** (0.14.0): it folds
watch creation, scope registration, and one priming read into a single
call, so scope disposal releases the watch and a `Runtime::gc()` that
runs before the first consumer read cannot sweep the upstream graph. The
lower-level pieces still exist — `scope.add_watch(derived.watch())`
registers without priming (an uncomputed watched cell is rooted but has
no recorded upstream `gc_dependencies()` yet, so prime it yourself), and
`Observer` values register with `Scope::add_observer`. If the facade
keeps a last-good cache, seed it from the priming read.

GC traversal follows `gc_dependencies()` from anchored roots, so the
parser's interior cells stay reachable as long as one downstream cell is
watched/observed and has been computed at least once.

### Template — `Watch` (preferred for new code)

```moonbit
pub(all) struct MyAttachment {
  scope : @incr.Scope
  watch : @incr.Watch[Result]
  // ... other cells you need to expose
}

pub fn MyAttachment::attach(
  parser : @loom.Parser[@ast.Term],
) -> MyAttachment {
  let rt = parser.runtime()
  let scope = @incr.Scope::new(rt)
  let stage_one = scope.derived(
    () => do_work(parser.syntax_tree().get_or_abort()),
    label="stage_one",
  )
  let result = scope.derived(
    () => finalize(stage_one.get_or_abort()),
    label="result",
  )
  // scope.watch folds creation + scope registration + a priming read,
  // so a pre-read Runtime::gc() sees the upstream dependencies.
  let watch = scope.watch(result)
  { scope, watch }
}

pub fn MyAttachment::get(self : MyAttachment) -> Result {
  self.watch.read_or_abort()
}

pub fn MyAttachment::dispose(self : MyAttachment) -> Unit {
  self.scope.dispose() // releases the scope-registered watch too
}
```

### Template — `Observer`

From `dowdiness/loom: examples/lambda/src/typed_parser.mbt` (and
mirrored in `dowdiness/loom: examples/lambda/src/callers/callers.mbt`):

```moonbit
pub(all) struct MyAttachment {
  scope : @incr.Scope
  observer : @incr.Observer[Result]
}

pub fn attach_my_thing(
  parser : @loom.Parser[@ast.Term],
) -> MyAttachment {
  let rt = parser.runtime()
  let scope = @incr.Scope::new(rt)
  let derived = scope.derived(
    fn() { do_work(parser.syntax_tree().get_or_abort()) },
    label="derived_bridge",
  )
  let result = scope.derived(
    fn() { finalize(derived.get_or_abort()) },
    label="derived_result",
  )
  let observer = scope.add_observer(result.observe())
  ignore(observer.get())
  { scope, observer }
}

pub fn MyAttachment::get(self : MyAttachment) -> Result {
  self.observer.get()
}

pub fn MyAttachment::dispose(self : MyAttachment) -> Unit {
  self.scope.dispose()
}
```

Both templates produce the same reachability behavior. Pick one per
chain and stay there — don't half-migrate one struct between `Watch`
and `Observer` mid-flight.

## Constructor Naming for *New* Structs

Project convention (per `~/.claude/moonbit-base.md` Quick Reference):
**define** new struct types' primary constructor as
`fn Type::Type(...) -> Type`, not `fn Type::new(...) -> Type`. The
miss this rule prevents is definition naming, not call syntax — at the
call site, match nearby code (`Type::Type(args)` or the short-form
`Type(args)` sugar, both work).

```moonbit
// ✅ New struct in user code
pub fn CallersPipeline::CallersPipeline(
  rt : @incr.Runtime,
  syntax : @incr.Derived[@seam.SyntaxNode],
) -> CallersPipeline { ... }

let p = CallersPipeline::CallersPipeline(rt, syntax)
```

### What API names look like at the call site

The library ships its constructors using exactly this convention, so
`Input(rt, v)` / `Derived(rt, f)` / `ReachableDerived(rt, f)` /
`InputField(rt, v)` / `Runtime()` are the canonical call forms — no
`::new` and no explicit `Type::Type` qualifier needed at the call site.

```moonbit
let rt = Runtime()
let x = Input(rt, 10, label="x")
let total = Derived(rt, () => x.get() * 2, label="total")
```

`Scope::new(rt)` follows the `::new` form because `Scope` predates the
direct-constructor sugar.

### Don't rename upstream library constructors

`Scope::new` and `Parser::new` are the names those APIs ship with — call
them as-is. (`Runtime::new` is deprecated since 0.14.0; use `Runtime()`.)
**`Watch` and `Observer` are never constructed**; they come from
`scope.watch(derived)` (preferred) / `derived.watch()` /
`derived.observe()` / `reachable.observe()` / `eager.observe()`. The
`Type::Type` rule is for new struct definitions, not retroactive
migration of upstream APIs.

Canonical reference for the convention in use:
`dowdiness/loom: examples/lambda/src/callers/callers.mbt:127` defines
`CallersPipeline::CallersPipeline`.

## Bench Patterns

Canonical reference: `tests/bench_test.mbt`. Copy its surface when
adding new benches.

```moonbit
test "derived: get warm (up-to-date, no recompute)" (b : @bench.T) {
  let rt = Runtime()
  let x = Input(rt, 42)
  let d = Derived(rt, () => x.get() * 2)
  ignore(d.read_or_abort())    // ← prime BEFORE measuring
  b.bench(fn() { b.keep(d.read_or_abort()) })
}
```

Conventions to match verbatim:

- **Prime, then bench.** Call the outside-graph read once
  (`d.read_or_abort()`) before `b.bench(...)` to settle dependencies and
  avoid measuring first-touch overhead.
- **Use `b.keep(...)` on the result** so the compiler doesn't dead-code
  the read.
- **`b.bench(fn() { ... })`** is the canonical signature; the closure
  body should be the smallest realistic measurement.
- **Library-API names use direct-constructor sugar** — `Input(rt, ...)`
  / `Derived(rt, ...)` / `Runtime()`. Don't invent `Input::new`.
- **Inside compute closures use `.get()` (Input/EagerDerived) or
  `.get_or_abort()` / `.get()` (Derived/ReachableDerived); outside use
  `.read_or_abort()` / `.read()` (Derived/ReachableDerived), or `.read()`
  (EagerDerived).** The bench file is the template for both rules at once.
- **Label derived cells** in attached pipelines (`label="..."`) — labels
  show up in introspection, which is the whole point of having them.

## When You're About to Write New Reactive Code — Checklist

Before any non-trivial `Derived(rt, ...)` / `ReachableDerived` /
`EagerDerived` call, ask:

1. **Am I inside a tracked closure?** If yes, use `.get()` for
   `Input` / `EagerDerived`, or `.get_or_abort()` / `.get()` for
   `Derived` / `ReachableDerived` (the latter returns `Result`). If
   outside (top-level, test setup, a public method that's not a compute
   body), use `.read_or_abort()` / `.read()` for `Derived` /
   `ReachableDerived`, `.read()` for `EagerDerived`, or a persistent
   `watch.read_or_abort()` / `observer.get()`.
2. **Will this cell survive `rt.gc()`?** If it's owned by a struct with
   a public `get`/`dispose` surface, it needs a `Scope` + persistent
   `Watch` or `Observer` GC anchor. If it's transient (one-shot read,
   immediately discarded), a bare outside-graph read is fine.
3. **Am I defining a new struct constructor?** Name it `Type::Type`,
   not `Type::new`.
4. **Is this a bench?** Prime once outside `b.bench`. Add a `label=`.

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `derived.read_or_abort()` / `reachable.read_or_abort()` inside a compute closure | Bench numbers inflated 25-30% on layered shapes; correctness OK so easy to miss | Replace with `input.get()` / `eager.get()` or `derived.get_or_abort()` / `reachable.get_or_abort()`. Audit the bench file in the same package as the canonical template. |
| Calling strict graph reads (`.get()` / `.get_or_abort()`) from top-level test or handler | Aborts outside a tracked context, or records a surprising dependency if a compute frame is active | Use `.read_or_abort()` / `.read()` for `Derived` / `ReachableDerived`, `.read()` for `EagerDerived`. |
| Forgot the GC anchor or priming read on an `attach_*` helper | Tests pass until `rt.gc()` runs before the first read; then `attachment.get()` aborts | Store `result.watch()` (or `scope.add_observer(result.observe())`), prime with `watch.read_or_abort()` (or `observer.get()`), and dispose the watch explicitly. |
| Defined `MyType::new(...)` for a new struct | Inconsistent with project convention; Codex/code review will flag | Rename to `MyType::MyType(...)`. |
| Wrote `Input::new(...)` / `Derived::new(...)` | Library ships direct constructors, not `::new` | Use `Input(rt, v, label=...)` / `Derived(rt, f, label=...)` directly. |
| Forgot to prime in a bench | First-touch cost shows up in the warm baseline | Add `ignore(d.read_or_abort())` before `b.bench(...)`. |
| Used a name from the historical mapping table (`Signal`, `Memo`, `HybridMemo`, `TrackedCell`, `Reactive`, `FunctionalRelation`, `Database`, `Readable`, `Trackable`, `rt.read`, etc.) | Compile error — removed in v0.12.0/v0.13.0 | Look up the current name in the Historical Mapping table above. |

## Red Flags — Pause and Verify

- About to type `.read_or_abort()` / `reachable.read_or_abort()` inside a
  closure passed to `Derived` / `ReachableDerived` / `EagerDerived` /
  `scope.derived` / `scope.reachable_derived` / `scope.eager_derived` →
  switch to `.get()` (Input / EagerDerived) or `.get_or_abort()` (Derived
  / ReachableDerived).
- About to type `eager.read()` inside a tracked closure → prefer
  `eager.get()` so the code documents that it requires a compute frame.
- About to define `fn MyType::new(` for a brand-new struct → switch to
  `fn MyType::MyType(`.
- About to call `Input::new(...)` or `Derived::new(...)` → the library
  ships direct constructors; drop the `::new`.
- A struct field is `priv derived : @incr.Derived[T]` with a public
  `get` / `dispose` and no `watch : @incr.Watch[T]` /
  `observer : @incr.Observer[T]` field → missing GC anchor.
- A bench body that calls `input.set` then a read with no prime above
  it → first iteration measures cold path.
- About to type any name from the Historical Mapping table
  (`Signal`, `Memo`, `HybridMemo`, `MemoMap`, `TrackedCell`, `Reactive`,
  `FunctionalRelation`, `Database`, `Readable`, `Trackable`, `rt.read`,
  `rt.read_hybrid`, `rt.read_reactive`, `scope.memo`, `scope.signal`) →
  it was removed in v0.12.0/v0.13.0; use the current-API column instead.

## Canonical Files to Cite (Verify Before Asserting)

Reading these is the fastest way to ground a change. Cite paths, don't
paraphrase.

In this repo (`dowdiness/incr`):

- `docs/target_api_examples.mbt.md` — checked literate examples
  (`Input`, `Derived`, `Scope`, `Watch`, `read_or_abort`,
  `get_or_abort`). Verified by `moon check` — never out of date.
- `docs/getting-started.md` — narrative walk-through with the
  inside-vs-outside read rule called out.
- `docs/api-reference.md` — authoritative shape of `read` /
  `read_or_abort` / `get` / `get_or_abort` / `watch` / `observe` for
  each handle.
- `tests/bench_test.mbt` — bench template.
- `CLAUDE.md` — package map (where each cell type lives) and the
  `cells/internal/*` isolation rule.
- `CHANGELOG.md` — authoritative record of the v0.12.0/v0.13.0 removals
  and their replacements.

In sister repo `dowdiness/loom` (where the incr library is consumed by
real parser pipelines — these are the canonical user-facing examples):

- `examples/lambda/src/typed_parser.mbt` — canonical `Scope` +
  persistent `Observer` + `dispose` lifecycle on a parser attachment.
- `examples/lambda/src/callers/callers.mbt` — second example of the
  same pattern, plus defensive `.copy()` on cached buckets and the
  `Type::Type` constructor convention.

Developer-side (referenced from `CLAUDE.md` via `@~/.claude/moonbit-base.md`):

- `~/.claude/moonbit-base.md` — quick-reference table for `Type::Type`
  and the general MoonBit conventions this skill assumes. Not present
  in this repo's tree; lives in each developer's `~/.claude/` profile.

If any file above has moved or been renamed since this skill was
written, update the skill — don't trust the path.

## Related Memories

- `feedback_api_misuse_pattern.md` — the four-miss session that
  motivated this skill.
- `feedback_persistent_observer_for_gc.md` — long-form rationale for
  the GC-anchor pattern.
- `project_callers_prototype.md` — Tier 0 example using every pattern
  in this skill correctly post-Codex review.

## Out of Scope

- The Memo Event Observation ADR
  (`docs/decisions/2026-05-17-memo-event-observation.md`) and the
  visualization-tap follow-up. Substantive incr-internal work, not
  workflow guidance.
- Adding same-receiver bridge methods across handle types
  (`Derived::observe`, etc.) beyond what the current API already ships.
