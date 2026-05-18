---
name: incr
description: Use when writing or reviewing MoonBit code against the `dowdiness/incr` reactive library — building Signals/Memos/HybridMemos, attaching long-lived derived cells, adding microbenchmarks, or wrapping a reactive pipeline in a struct. Catches recurring idiom misses (`.get()` vs `rt.read`, GC-anchor Observer, `Type::Type` constructor naming, defensive copies).
---

# incr

Reference for writing canonical `@incr` code. Adapt to context — these are
patterns the project consistently uses, not enforcement rules.

Project root for this skill's citations:
`/home/antisatori/ghq/github.com/dowdiness/canopy/loom/incr/` (the `incr`
submodule of the `loom` repo).

## When to Use

Trigger keywords: `Memo::new`, `Signal::new`, `HybridMemo::new`,
`@incr.Scope`, `@incr.Observer`, `Reactive`, `parser.runtime()`,
`scope.memo`, `add_observer`, `attach_*`, `bench_test.mbt`, ".bench(",
`rt.read`, `m.get()`. Also any time you are defining a new struct that
owns reactive cells and exposes a `get`/`dispose` surface.

Sister skill: **loom** (parser-side conventions). If the task involves
calling `Parser::new` or `new_parser`, read that one too.

## Quick Reference

| Situation | Use | Not |
|-----------|-----|-----|
| Read upstream cell from inside any incr compute closure (`Memo::new`, `Reactive::new`, `HybridMemo::new`, `scope.memo`, `scope.hybrid_memo`, `scope.reactive`) | `cell.get()` | `rt.read(cell)` — does one-shot observer lifecycle work that's wasted inside an already-tracked frame; on layered/tree shapes the user measured ~25–30% inflation (see `feedback_api_misuse_pattern.md`) |
| Read a `Memo` from outside the reactive graph (tests, top-level, non-tracked consumer methods) | `rt.read(memo)` or persistent `observer.get()` | `memo.get()` (would silently record a stray dep on whatever tracking frame is active) |
| Read a `HybridMemo` from outside the graph | `rt.read_hybrid(h)` or `observer.get()` | `rt.read(h)` — `read` is `Memo`-only |
| Read a `Reactive` from outside the graph | `rt.read_reactive(r)` or `observer.get()` | `rt.read(r)` — same reason |
| Read anything after `dispose()` | Don't — disposed cells/observers abort | — |
| Define a new struct's primary constructor | `fn MyStruct::MyStruct(...) -> MyStruct` | `fn MyStruct::new(...) -> MyStruct` (older idiom; `Type::Type` is project convention per `~/.claude/moonbit-base.md`) |
| Attach long-lived derived cells to a parser/runtime | `Scope` + persistent `Observer` (see template below) | Bare `Memo::new` with no GC root — `rt.gc()` will sweep the chain |
| Use a library-provided pre-existing constructor (`Memo::new`, `Signal::new`, `Runtime::new`, `HybridMemo::new`, `Scope::new`) | The name they ship with (`::new`) | Don't rename library APIs — the `Type::Type` convention is for *defining* new structs, not for *calling* upstream library constructors. Observers come from `*.observe()` (no `Observer::new`). |

## The `.get()` vs `rt.read` Rule (the big one)

`rt.read(memo)` opens and closes a one-shot observer to do the read.
That's the right shape for an external caller — it ensures pull
verification runs and downstream callers see a coherent value. **Inside
any incr compute closure** (`Memo::new`, `Reactive::new`,
`HybridMemo::new`, `scope.memo`, `scope.hybrid_memo`, `scope.reactive`),
you're already inside a tracked frame; calling `rt.read` from there pays
the observer lifecycle cost on every recompute for nothing. The user's
2026-05-18 measurement put the inflation at ~25–30% on layered/tree
shapes (see `feedback_api_misuse_pattern.md`).

Note: `rt.read` is `Memo`-only. For `HybridMemo` use `rt.read_hybrid(h)`;
for `Reactive` use `rt.read_reactive(r)`. A persistent `Observer::get()`
works for all three.

```moonbit
// ✅ Inside a Memo body — `.get()` records the dep cheaply
let typed_memo = scope.memo(
  fn() { @typecheck.convert_from_cst(parser.syntax_tree().get()) },
  label="typed_term_bridge",
)

// ❌ Inside a Memo body — paid the observer lifecycle on every recompute
let typed_memo = scope.memo(
  fn() { @typecheck.convert_from_cst(rt.read(parser.syntax_tree())) },
)

// ✅ Outside the graph — `rt.read` is correct
let snapshot = rt.read(parser.syntax_tree())

// ✅ Outside the graph through a persistent observer
let result = attachment.observer.get()
```

Canonical reference: `loom/incr/tests/bench_test.mbt` consistently uses
`.get()` inside closures and `rt.read(...)` at bench scope.
`loom/examples/lambda/src/typed_parser.mbt:59` uses `.get()` inside
`scope.memo`. `loom/examples/lambda/src/callers/callers.mbt:133` does
the same.

## The Persistent-Observer GC Anchor

`Runtime::gc()` marks reachability via BFS from `gc_root_counts`, which
`Memo::observe()` increments. One-shot `rt.read()` creates and disposes
an observer immediately — so it does NOT keep the cell alive across a
later `gc()`. Interior Memos with no observer get swept; subsequent
reads abort.

**Rule:** if you build a downstream chain that should survive
`Runtime::gc()` (anything stored in a struct field with a public `get`),
hold a persistent `Observer` on the terminal Memo and register it with
a `Scope`.

### Template — attaching a derived pipeline to a parser

From `loom/examples/lambda/src/typed_parser.mbt` (and mirrored in
`loom/examples/lambda/src/callers/callers.mbt`):

```moonbit
pub(all) struct MyAttachment {
  scope : @incr.Scope
  observer : @incr.Observer[Result]
  // ... other cells you need to expose
}

pub fn attach_my_thing(
  parser : @loom.Parser[@ast.Term],
) -> MyAttachment {
  let rt = parser.runtime()
  let scope = @incr.Scope::new(rt)
  let derived = scope.memo(
    fn() { do_work(parser.syntax_tree().get()) },
    label="derived_bridge",
  )
  let result = scope.memo(
    fn() { finalize(derived.get()) },
    label="derived_result",
  )
  let observer = scope.add_observer(result.observe())
  { scope, observer }
}

pub fn MyAttachment::get(self : MyAttachment) -> Result {
  self.observer.get()
}

pub fn MyAttachment::dispose(self : MyAttachment) -> Unit {
  self.scope.dispose()   // children → observer → owned cells. Idempotent.
}
```

Why the observer protects upstream cells too: GC traversal follows
`gc_dependencies()` from observed roots, so the parser's interior
memos stay reachable as long as one downstream Memo is observed.

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
  syntax : @incr.Memo[@seam.SyntaxNode],
) -> CallersPipeline { ... }

let p = CallersPipeline::CallersPipeline(rt, syntax)
```

**Do not rename library constructors.** `Memo::new`, `Signal::new`,
`HybridMemo::new`, `Runtime::new`, `Scope::new`, `Parser::new` are the
names those APIs ship with — call them as-is. **Observers are not
constructed**; they come from `memo.observe()` / `hybrid.observe()` /
`reactive.observe()`. The `Type::Type` rule is for new struct
definitions, not retroactive migration of upstream APIs.

Canonical reference for the convention in use:
`loom/examples/lambda/src/callers/callers.mbt:127` defines
`CallersPipeline::CallersPipeline`.

## Bench Patterns

Canonical reference: `loom/incr/tests/bench_test.mbt`. Copy its surface
when adding new benches.

```moonbit
test "memo: get warm (up-to-date, no recompute)" (b : @bench.T) {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42)
  let m = Memo::new(rt, () => sig.get() * 2)
  ignore(rt.read(m))           // ← prime BEFORE measuring
  b.bench(fn() { b.keep(rt.read(m)) })
}
```

Conventions to match verbatim:

- **Prime, then bench.** Call `rt.read(...)` once outside `b.bench(...)`
  to settle dependencies and avoid measuring first-touch overhead.
- **Use `b.keep(...)` on the result** so the compiler doesn't dead-code
  the read.
- **`b.bench(fn() { ... })`** is the canonical signature; the closure
  body should be the smallest realistic measurement.
- **Use `Signal::new`, `Memo::new`, `Runtime::new`** — library-API
  names. Inside closures use `.get()`; at bench scope use
  `rt.read(...)`. The bench file is the template for both rules at once.
- **Label memos** in attached pipelines (`label="..."`) — labels show
  up in introspection, which is the whole point of having them.

## When You're About to Write New Reactive Code — Checklist

Before any non-trivial `Memo::new` / `Reactive::new` / `HybridMemo::new`
call, ask:

1. **Am I inside a tracked closure?** If yes, use `.get()`. If outside
   (top-level, test setup, a public method that's not a Memo body), use
   `rt.read(...)` or a persistent `Observer::get()`.
2. **Will this cell survive `rt.gc()`?** If it's owned by a struct with
   a public `get`/`dispose` surface, it needs a `Scope` + persistent
   `Observer` GC anchor. If it's transient (one-shot read, immediately
   discarded), `rt.read` alone is fine.
3. **Am I defining a new struct constructor?** Name it `Type::Type`,
   not `Type::new`.
4. **Is this a bench?** Prime once outside `b.bench`. Use
   `Signal::new`/`Memo::new` (library names). Add a `label=`.

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `rt.read(cell)` inside `Memo::new` closure | Bench numbers inflated 25-30% on layered shapes; correctness OK so easy to miss | Replace with `cell.get()`. Audit the bench file in the same package as the canonical template. |
| Forgot the `Observer` GC anchor on an `attach_*` helper | Tests pass until `rt.gc()` runs; then `attachment.get()` aborts | Add `scope.add_observer(result_memo.observe())` and store the observer in the struct. |
| Defined `MyType::new(...)` for a new struct | Inconsistent with project convention; Codex/code review will flag | Rename to `MyType::MyType(...)`. |
| Forgot to prime in a bench | First-touch cost shows up in the warm baseline | Add `ignore(rt.read(m))` before `b.bench(...)`. |

## Red Flags — Pause and Verify

- About to type `rt.read(` inside a closure passed to `Memo::new` /
  `Reactive::new` / `HybridMemo::new` / `scope.memo` /
  `scope.hybrid_memo` / `scope.reactive` → switch to `.get()`.
- About to type `rt.read(h)` on a `HybridMemo` or `rt.read(r)` on a
  `Reactive` (outside the graph) → use `rt.read_hybrid` /
  `rt.read_reactive` respectively, or a persistent `Observer::get()`.
- About to define `fn MyType::new(` for a brand-new struct → switch to
  `fn MyType::MyType(`.
- A struct field is `priv memo : @incr.Memo[T]` with a public `get` /
  `dispose` and no `observer : @incr.Observer[T]` field → missing GC
  anchor.
- A bench body that calls `Signal::set` then `rt.read(m)` with no prime
  above it → first iteration measures cold path.

## Canonical Files to Cite (Verify Before Asserting)

Reading these is the fastest way to ground a change. Cite paths, don't
paraphrase.

- `loom/incr/tests/bench_test.mbt` — bench template; `.get()` vs
  `rt.read` rule visible at a glance.
- `loom/examples/lambda/src/typed_parser.mbt` — canonical
  `Scope` + persistent `Observer` + `dispose` lifecycle on a parser
  attachment.
- `loom/examples/lambda/src/callers/callers.mbt` — second example of
  the same pattern, plus defensive `.copy()` on cached buckets and the
  `Type::Type` constructor convention.
- `loom/incr/CLAUDE.md` — package map (where each cell type lives), and
  the rule that the `cells/internal/*` engines are not user-facing.
- `~/.claude/moonbit-base.md` — quick-reference table for `Type::Type`
  and the general MoonBit conventions this skill assumes.

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
  (`loom/incr/docs/decisions/2026-05-17-memo-event-observation.md`) and
  the visualization-tap follow-up. Substantive incr-internal work, not
  workflow guidance.
- Migrating existing library constructors (`Memo::new` etc.) to
  `::Type` form. The convention is for new user code.
