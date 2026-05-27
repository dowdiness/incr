---
name: incr
description: Use when writing or reviewing MoonBit code against the `dowdiness/incr` reactive library (v0.6.x+) — building Inputs/Deriveds/ReachableDeriveds (or the compatibility names Signal/Memo/HybridMemo), attaching long-lived derived cells with `Watch`/`Observer`, adding microbenchmarks, or wrapping a reactive pipeline in a struct. Catches recurring idiom misses (inside-vs-outside read semantics, GC-anchor `Watch`/`Observer`, `Type::Type` constructor naming, defensive copies).
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

Trigger keywords (target facade — preferred for new code):
`@incr.Input`, `@incr.Derived`, `@incr.ReachableDerived`,
`@incr.InputField`, `@incr.EagerDerived`, `@incr.DerivedMap`,
`@incr.Watch`, `@incr.MapRelation`, `Scope::new`, `scope.input`,
`scope.derived`, `scope.reachable_derived`, `scope.eager_derived`,
`.read()`, `.read_or_abort()`, `.get_or_abort()`, `.watch()`.

Trigger keywords (compatibility names — still valid, used by older
loom/canopy code): `Memo::new`, `Signal::new`, `HybridMemo::new`,
`@incr.Observer`, `Reactive`, `scope.memo`, `scope.signal`,
`add_observer`, `.observe()`, `rt.read`, `rt.read_hybrid`,
`rt.read_reactive`.

Also fires on: `parser.runtime()`, `attach_*`, `bench_test.mbt`,
`.bench(` — or any time you are defining a new struct that owns
reactive cells and exposes a `get`/`dispose` surface.

Sister skill: **loom** (parser-side conventions). If the task involves
calling `Parser::new` or `new_parser`, read that one too.

## Naming: Target Facade ↔ Compatibility

Per `~/.claude/CLAUDE.md` and `loom/incr/CLAUDE.md`, v0.6.0 introduced
target facade names as the preferred form for new docs and examples.
Compatibility names remain supported, but ordinary new code should use
the target facades. Keep compatibility handles only where the target
facade intentionally does not expose the behavior yet (accumulators,
low-level memo introspection recipes, or legacy downstream code).

| Compatibility | Target facade |
|---------------|---------------|
| `Signal[T]` | `Input[T]` |
| `Memo[T]` | `Derived[T]` |
| `HybridMemo[T]` | `ReachableDerived[T]` |
| `MemoMap[K, V]` | `DerivedMap[K, V]` |
| `TrackedCell[T]` | `InputField[T]` |
| `Reactive[T]` | `EagerDerived[T]` |
| `Observer[T]` | `Watch[T]` |
| `FunctionalRelation[T]` | `MapRelation[T]` |
| `scope.memo(...)` | `scope.derived(...)` |
| `scope.signal(...)` | `scope.input(...)` |
| `memo.observe()` | `derived.watch()` |
| `rt.read(memo)` | `derived.read()` / `derived.read_or_abort()` |
| `rt.read_hybrid(h)` | `reachable.read()` / `reachable.read_or_abort()` |
| `rt.read_reactive(r)` | `eager.read()` / `eager.read_or_abort()` |

`Runtime`, `Scope`, `Accumulator`, `Effect`, `MemoEvent`, `CycleError`
are the same name in both worlds. New code should pick one column and
stay there per cell chain — don't mix `Memo` and `Derived` for the same
graph unless a compatibility-only API forces that boundary.

**Phase 3a decision (2026-05-26, PR #90):** do **not** add target-vocabulary
bridge methods to compatibility handles (`Memo::read`, `Memo::get_or_abort`,
`MemoMap::read`, etc.). The compatibility handles are eventual cleanup/removal
targets; migrating users to new methods on them would create churn. For ordinary
migration, move the handle type/constructor to `Derived`, `ReachableDerived`, or
`DerivedMap`. Use `scripts/migrate-to-target-facades.py` for a dry-run report
and conservative safe rewrites; it skips files with context-sensitive reads or
compatibility-only methods that need manual judgment.

## Quick Reference

Rows below show the target facade form first; compatibility-name equivalents in
parentheses.

| Situation | Use | Not |
|-----------|-----|-----|
| Read an `Input` from inside any compute closure | `input.get()` | wrapping in `rt.read(...)` — Inputs are non-fallible; `.get()` records the dep at zero observer cost |
| Read a `Derived` / `ReachableDerived` / `EagerDerived` from inside another compute closure | `derived.get_or_abort()` (strict) or `derived.get()` returning `Result` (graceful) | `rt.read(derived)` — does one-shot observer lifecycle work that's wasted inside an already-tracked frame; on layered/tree shapes the user measured ~25–30% inflation (see `feedback_api_misuse_pattern.md`) |
| Read a `Derived` (or `Memo`) from outside the reactive graph (tests, top-level, non-tracked consumer methods) | `derived.read_or_abort()` or `derived.read() -> Result` (or persistent `watch.read_or_abort()` / `observer.get()`) | calling `.get()` at top level — would silently record a stray dep on whatever tracking frame is active |
| Read a `ReachableDerived` (or `HybridMemo`) from outside the graph | `reachable.read_or_abort()` or `reachable.read()` (or `watch.read_or_abort()`) | mixing `rt.read(h)` — `Runtime::read` is `Memo[T]`-only; for the compat handle, `rt.read_hybrid(h)` works but is the legacy form |
| Read an `EagerDerived` (or `Reactive`) from outside the graph | `eager.read_or_abort()` or `eager.read()` (or `watch.read_or_abort()`) | mixing `rt.read(r)` — same as above; the compat form is `rt.read_reactive(r)` |
| Read anything after `dispose()` | Don't — disposed cells/observers/watches abort | — |
| Define a new struct's primary constructor | `fn MyStruct::MyStruct(...) -> MyStruct` | `fn MyStruct::new(...) -> MyStruct` (older idiom; `Type::Type` is project convention per `~/.claude/moonbit-base.md`) |
| Attach long-lived derived cells to a parser/runtime | `Scope` + persistent `Watch` (preferred) or `Observer` (compat) — see templates below | Bare `Derived(rt, ...)` / `Memo::new` with no GC root — `rt.gc()` will sweep the chain |
| Use a library-provided constructor | `Input(rt, v, label=...)`, `Derived(rt, f, label=...)`, `ReachableDerived(rt, f, label=...)`, `Runtime()`, `Scope::new(rt)`, `derived.watch()` (or compat: `Memo::new`, `Signal::new`, `memo.observe()`) | Don't rename library APIs — the `Type::Type` convention is for *defining* new structs, not for *calling* upstream library constructors. `Watch` comes from `*.watch()`; `Observer` from `*.observe()`. Neither has `::new`. |

## Inside vs Outside the Graph (the big rule)

The read API splits along one axis: **am I inside a tracked compute
closure or not?**

**Inside a compute closure** (`Derived(rt, f, ...)`, `ReachableDerived`,
`EagerDerived`, `scope.derived`, `scope.reachable_derived`,
`scope.eager_derived` — and the compat equivalents `Memo::new`,
`HybridMemo::new`, `Reactive::new`, `scope.memo`):

- `input.get()` — Inputs are non-fallible; just reads and records the dep.
- `derived.get_or_abort()` — strict read; aborts on cycle.
- `derived.get()` — graceful read; returns `Result[T, CycleError]`.

These record the dep on the surrounding tracking frame at zero observer
cost.

**Outside the graph** (top-level, tests, event handlers, non-tracked
consumer methods):

- `derived.read_or_abort()` — strict; aborts on cycle.
- `derived.read()` — returns `Result[T, CycleError]`.
- Through a long-lived anchor: `watch.read_or_abort()` / `watch.read()`
  (or compat: `observer.get()`).
- Legacy: `rt.read(memo)` / `rt.read_hybrid(h)` / `rt.read_reactive(r)`
  still work for the compat-named handles.

### Why mixing breaks

Calling `rt.read(memo)` from inside a compute closure (or
`derived.read_or_abort()` — same shape) opens and closes a one-shot
observer to do the read, on top of the tracking frame that's already
live. The 2026-05-18 measurement put the inflation at ~25–30% on
layered/tree shapes (see `feedback_api_misuse_pattern.md`). Correctness
is fine, so the bug is invisible without a microbench.

Calling `.get()` / `.get_or_abort()` at top level silently records a
stray dep on whatever tracking frame is active — typically none, but if
you're inside a test that ran a `scope.derived(...)` setup helper, the
dep will land on that closure's frame.

### Examples

```moonbit
// ✅ Target facade — inside a Derived body
let total = Derived(
  rt,
  () => subtotal.get_or_abort().to_double() + tax.get_or_abort(),
  label="total",
)

// ✅ Compatibility — inside a Memo body (still valid)
let typed_memo = scope.memo(
  fn() { @typecheck.convert_from_cst(parser.syntax_tree().get_or_abort()) },
  label="typed_term_bridge",
)

// ❌ Inside a compute closure — pays the observer lifecycle every recompute
let typed_memo = scope.memo(
  fn() { @typecheck.convert_from_cst(rt.read(parser.syntax_tree())) },
)

// ✅ Outside the graph — target facade
let snapshot = parser.syntax_tree().read_or_abort()
match total.read() {
  Ok(v) => println("Total: \{v}")
  Err(e) => println(e.format_path())
}

// ✅ Outside the graph — compat path (still works)
let snapshot = rt.read(parser.syntax_tree())

// ✅ Outside the graph through a persistent anchor
let result = attachment.watch.read_or_abort()    // target
let result = attachment.observer.get()           // compat
```

Canonical references:

- `docs/target_api_examples.mbt.md` — checked literate examples of the
  target facade form (`Input`, `Derived`, `Scope`, `Watch`,
  `read_or_abort`, `get_or_abort`).
- `docs/getting-started.mbt.md` — narrative version with the
  inside-vs-outside rule called out.
- `tests/bench_test.mbt` — bench template using the compat names; still
  the canonical bench surface.
- `dowdiness/loom: examples/lambda/src/typed_parser.mbt:59` — compat
  `scope.memo` + `.get_or_abort()` pattern in real downstream use.
- `dowdiness/loom: examples/lambda/src/callers/callers.mbt:133` — same.

## The Persistent-Anchor GC Rule

`Runtime::gc()` marks reachability via BFS from `gc_root_counts`, which
`derived.watch()` / `memo.observe()` increment. One-shot
`derived.read_or_abort()` (or legacy `rt.read(memo)`) creates and
disposes the anchor immediately — so it does NOT keep the cell alive
across a later `gc()`. Interior Deriveds with no anchor get swept;
subsequent reads abort.

**Rule:** if you build a downstream chain that should survive
`Runtime::gc()` (anything stored in a struct field with a public `get`),
hold a persistent `Watch` (target) or `Observer` (compat) on the
terminal Derived/Memo and register it with a `Scope`.

GC traversal follows `gc_dependencies()` from anchored roots, so the
parser's interior cells stay reachable as long as one downstream cell is
watched/observed.

### Template — target facade (preferred for new code)

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
  // `derived.watch()` allocates and registers the GC root. Scope owns
  // its disposal — no separate `scope.add_*` call required.
  { scope, watch: result.watch() }
}

pub fn MyAttachment::get(self : MyAttachment) -> Result {
  self.watch.read_or_abort()
}

pub fn MyAttachment::dispose(self : MyAttachment) -> Unit {
  self.scope.dispose()   // children → watch → owned cells. Idempotent.
}
```

### Template — compatibility names (still canonical in loom/canopy as of 2026-05-24)

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
  let derived = scope.memo(
    fn() { do_work(parser.syntax_tree().get_or_abort()) },
    label="derived_bridge",
  )
  let result = scope.memo(
    fn() { finalize(derived.get_or_abort()) },
    label="derived_result",
  )
  let observer = scope.add_observer(result.observe())
  { scope, observer }
}

pub fn MyAttachment::get(self : MyAttachment) -> Result {
  self.observer.get()
}

pub fn MyAttachment::dispose(self : MyAttachment) -> Unit {
  self.scope.dispose()
}
```

Both templates produce the same reachability behavior. Pick a column
per chain and stay there — don't half-migrate one struct.

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
  syntax : @incr.Derived[@seam.SyntaxNode],   // or @incr.Memo if matching surrounding compat code
) -> CallersPipeline { ... }

let p = CallersPipeline::CallersPipeline(rt, syntax)
```

### What v0.6.x facade names look like at the call site

The target facade ships its constructors using exactly this convention,
so `Input(rt, v)` / `Derived(rt, f)` / `ReachableDerived(rt, f)` /
`InputField(rt, v)` / `Runtime()` are the canonical call forms — no
`::new` and no explicit `Type::Type` qualifier needed at the call site.

```moonbit
let rt = Runtime()
let x = Input(rt, 10, label="x")
let total = Derived(rt, () => x.get() * 2, label="total")
```

The compatibility names still use `::new` because they are aliases for
the older shape:

```moonbit
let rt = Runtime::new()
let x = Signal::new(rt, 10)
let m = Memo::new(rt, () => x.get() * 2)
```

`Scope::new(rt)` is the same in both worlds.

### Don't rename upstream library constructors

`Memo::new`, `Signal::new`, `HybridMemo::new`, `Runtime::new`,
`Scope::new`, `Parser::new` are the names those APIs ship with — call
them as-is. **`Watch` and `Observer` are never constructed**; they
come from `derived.watch()` / `memo.observe()` / `hybrid.observe()` /
`reactive.observe()`. The `Type::Type` rule is for new struct
definitions, not retroactive migration of upstream APIs.

Canonical reference for the convention in use:
`dowdiness/loom: examples/lambda/src/callers/callers.mbt:127` defines
`CallersPipeline::CallersPipeline`.

## Bench Patterns

Canonical reference: `tests/bench_test.mbt`. Copy its surface when
adding new benches. As of 2026-05-24 the bench file uses compatibility
names — that's fine; either column works. Match whatever the file you're
editing already uses.

```moonbit
// Compatibility-name form — matches existing bench_test.mbt
test "memo: get warm (up-to-date, no recompute)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let m = Memo::new(rt, () => sig.get() * 2)
  ignore(rt.read(m))           // ← prime BEFORE measuring
  b.bench(fn() { b.keep(rt.read(m)) })
}

// Target-facade form — same shape, new vocabulary
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
  (`rt.read(m)` or `d.read_or_abort()`) before `b.bench(...)` to settle
  dependencies and avoid measuring first-touch overhead.
- **Use `b.keep(...)` on the result** so the compiler doesn't dead-code
  the read.
- **`b.bench(fn() { ... })`** is the canonical signature; the closure
  body should be the smallest realistic measurement.
- **Library-API names ship with the column you pick** — `Signal::new` /
  `Memo::new` / `Runtime::new` (compat) or `Input(rt, ...)` /
  `Derived(rt, ...)` / `Runtime()` (target). Don't invent
  `Input::new` — the target facade uses direct-constructor sugar.
- **Inside compute closures use `.get()` / `.get_or_abort()`; outside
  use `rt.read(...)` (compat) or `.read_or_abort()` / `.read()` (target).**
  The bench file is the template for both rules at once.
- **Label derived cells** in attached pipelines (`label="..."`) — labels
  show up in introspection, which is the whole point of having them.

## When You're About to Write New Reactive Code — Checklist

Before any non-trivial `Derived(rt, ...)` / `ReachableDerived` /
`EagerDerived` (or compat `Memo::new` / `HybridMemo::new` /
`Reactive::new`) call, ask:

1. **Which column am I in?** Pick target facade
   (`Input`/`Derived`/`Watch`) or compatibility
   (`Signal`/`Memo`/`Observer`) and match the file you're editing.
   Don't half-migrate one chain.
2. **Am I inside a tracked closure?** If yes, use `.get()` (Input) or
   `.get_or_abort()` / `.get()` (Derived/ReachableDerived/EagerDerived
   — the latter returns `Result`). If outside (top-level, test setup, a
   public method that's not a compute body), use `.read_or_abort()` /
   `.read()` (target) or `rt.read(...)` / `rt.read_hybrid(...)` /
   `rt.read_reactive(...)` (compat), or a persistent
   `watch.read_or_abort()` / `observer.get()`.
3. **Will this cell survive `rt.gc()`?** If it's owned by a struct with
   a public `get`/`dispose` surface, it needs a `Scope` + persistent
   `Watch` (target) or `Observer` (compat) GC anchor. If it's transient
   (one-shot read, immediately discarded), a bare outside-graph read is
   fine.
4. **Am I defining a new struct constructor?** Name it `Type::Type`,
   not `Type::new`.
5. **Is this a bench?** Prime once outside `b.bench`. Use library names
   from whichever column the bench file already uses. Add a `label=`.

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `rt.read(cell)` or `derived.read_or_abort()` inside a compute closure | Bench numbers inflated 25-30% on layered shapes; correctness OK so easy to miss | Replace with `cell.get()` / `derived.get_or_abort()`. Audit the bench file in the same package as the canonical template. |
| Calling `.get()` / `.get_or_abort()` from top-level test or handler | Silent stray dep recorded on whatever frame happens to be active; flaky or surprising recomputes later | Use `.read_or_abort()` / `.read()` (target) or `rt.read(...)` (compat). |
| Forgot the GC anchor on an `attach_*` helper | Tests pass until `rt.gc()` runs; then `attachment.get()` aborts | Target: store `result.watch()` in the struct (Scope owns disposal). Compat: store `scope.add_observer(result.observe())`. |
| Mixed `Memo`/`Derived` for the same chain | Reviewers/Codex flag the inconsistency; types still align because of aliasing so it compiles | Pick one column per chain. |
| Defined `MyType::new(...)` for a new struct | Inconsistent with project convention; Codex/code review will flag | Rename to `MyType::MyType(...)`. |
| Wrote `Input::new(...)` / `Derived::new(...)` | Target facade ships direct constructors, not `::new` | Use `Input(rt, v, label=...)` / `Derived(rt, f, label=...)` directly. |
| Forgot to prime in a bench | First-touch cost shows up in the warm baseline | Add `ignore(rt.read(m))` (compat) or `ignore(d.read_or_abort())` (target) before `b.bench(...)`. |

## Red Flags — Pause and Verify

- About to type `rt.read(` or `.read_or_abort()` inside a closure
  passed to `Derived` / `ReachableDerived` / `EagerDerived` /
  `Memo::new` / `HybridMemo::new` / `Reactive::new` / `scope.derived` /
  `scope.memo` / `scope.reachable_derived` / `scope.eager_derived` /
  `scope.hybrid_memo` / `scope.reactive` → switch to `.get()` (Input)
  or `.get_or_abort()` (Derived family).
- About to type `rt.read(h)` on a `HybridMemo` or `rt.read(r)` on a
  `Reactive` (outside the graph) → use `rt.read_hybrid` /
  `rt.read_reactive`, or a persistent `observer.get()`. For target
  names, just call `reachable.read_or_abort()` / `eager.read_or_abort()`.
- About to define `fn MyType::new(` for a brand-new struct → switch to
  `fn MyType::MyType(`.
- About to call `Input::new(...)` or `Derived::new(...)` → the target
  facade ships direct constructors; drop the `::new`.
- A struct field is `priv derived : @incr.Derived[T]` (or
  `priv memo : @incr.Memo[T]`) with a public `get` / `dispose` and no
  `watch : @incr.Watch[T]` / `observer : @incr.Observer[T]` field →
  missing GC anchor.
- A bench body that calls `Signal::set` / `input.set` then a read with
  no prime above it → first iteration measures cold path.
- Mixing names within one cell chain (`Memo` upstream, `Derived`
  downstream, or `.observe()` plus `.watch()`) → pick one column.

## Canonical Files to Cite (Verify Before Asserting)

Reading these is the fastest way to ground a change. Cite paths, don't
paraphrase.

In this repo (`dowdiness/incr`):

- `docs/target_api_examples.mbt.md` — checked literate target facade
  examples (`Input`, `Derived`, `Scope`, `Watch`, `read_or_abort`,
  `get_or_abort`). Verified by `moon check` — never out of date.
- `docs/getting-started.mbt.md` — narrative walk-through with the
  inside-vs-outside read rule called out (steps 4 and 4.5).
- `docs/api-reference.mbt.md` — compatibility ↔ target mapping tables for
  each handle; authoritative shape of `read` / `read_or_abort` /
  `get` / `get_or_abort` / `watch` / `observe`, plus current guidance to
  migrate old handles directly to target facades rather than adding bridge
  methods to compatibility handles.
- `scripts/migrate-to-target-facades.py` — dry-run-by-default helper for
  compatibility-to-facade migrations; reports context-sensitive read sites
  and skips files with manual findings under `--apply`.
- `tests/bench_test.mbt` — bench template (currently in compatibility
  names; either column is fine — match what's there).
- `CLAUDE.md` — package map (where each cell type lives), the
  `cells/internal/*` isolation rule, and the target-facade preference
  for new docs/examples.

In sister repo `dowdiness/loom` (where the incr library is consumed by
real parser pipelines — these are the canonical user-facing examples
and still use compatibility names as of 2026-05-24):

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
- Migrating existing library constructors (`Memo::new` etc.) to
  `::Type` form. The convention is for new user code.
- Adding same-receiver target-vocabulary bridge methods to compatibility
  handles (`Memo::read`, `Memo::get_or_abort`, `MemoMap::read`, etc.).
  Phase 3a shipped as docs/tooling in PR #90: migrate ordinary consumers
  directly to `Derived` / `ReachableDerived` / `DerivedMap` instead.
- Removing compatibility-handle guidance entirely. Compatibility names are
  still present and remain necessary for accumulator and low-level
  introspection recipes until a future breaking cleanup explicitly removes
  or isolates them.
