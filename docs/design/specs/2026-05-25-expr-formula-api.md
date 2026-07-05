# `Expr[T]` Formula API

**Status:** Accepted

**Date:** 2026-07-05 (Status updated from Proposed to Accepted upon E2 implementation)

**Parent TODO:** [`docs/todo.md`](../../todo.md#api-improvements)

## Goal

Add a high-level formula layer for target facade handles so users can write
small derived computations declaratively without hiding mutation or allocating
intermediate cells:

```moonbit
// Proposed API; checked examples must be added when the API ships.
let subtotal = (cart.price.expr() * cart.quantity.expr()).derived(
  label="subtotal",
)
```

The formula should stay lazy until materialization. The expression chain above
must allocate exactly one incremental cell: the final `Derived[Int]` returned by
`.derived(...)`.

## Non-goals

- Do not overload operators directly on `Input[T]` or `InputField[T]`. MoonBit
  operator traits are self-closed (`Self -> Self`), so `Input + Input` would
  have to return `Input`, which is the wrong semantic shape.
- Do not introduce implicit `T -> Expr[T]` conversion for literals. MoonBit does
  not provide a safe implicit conversion hook here, and runtime-less constants
  would make same-runtime validation ambiguous.
- Do not make expression evaluation a new public read API. Expressions are a
  construction DSL for derived cells, not standalone reactive nodes.
- Do not add indexing syntax in v1. Reserve `_[_]`, `_[_]=_`, and `_[_:_]` for
  future indexed reactive collections unless a later design proves scalar
  expression indexing is worth spending that syntax.

## Chosen surface

Use the name `Expr[T]` for v1. `Formula[T]` can be revisited later as a public
alias if user feedback says the domain language is clearer, but the first API
should have one canonical type name.

```moonbit
// Sketch; exact syntax may adjust during implementation.
pub(all) struct Expr[T] {
  priv rt : Runtime
  priv eval : () -> T raise Failure
  priv debug : ExprDebug
}
```

`Expr[T]` lives in the `cells` package, next to the target facades. That lets it
read package-private runtime handles from `Input`, `InputField`, `Derived`, and
`ReachableDerived` without exposing compatibility internals in the root facade.

### Source lifts

| Source | Method | Expression evaluation inside a materialized formula |
|---|---|---|
| `Input[T]` | `input.expr()` | `input.get()` |
| `InputField[T]` | `field.expr()` | `field.get()` |
| `Derived[T]` | `derived.expr()` | `derived.get_or_abort()` |
| `ReachableDerived[T]` | `reachable.expr()` | `reachable.get_or_abort()` |
| `EagerDerived[T]` | `eager.expr()` | `eager.get()` |
| constant | `Expr::constant(rt, value, label?)` | captured value |

Use strict reads for derived sources. A materialized formula computes inside a
tracked context, so strict reads are the correct dependency edge. If a formula
source has a cycle, the expression API should behave like the aborting
convenience methods (`get_or_abort`) rather than force every operator closure to
carry `Result[T, CycleError]`.

The source-lift signatures should make existing facade bounds explicit:

```moonbit
pub fn[T] Input::expr(self : Input[T]) -> Expr[T]
pub fn[T] InputField::expr(self : InputField[T]) -> Expr[T]
pub fn[T] Derived::expr(self : Derived[T]) -> Expr[T]
pub fn[T : Eq] ReachableDerived::expr(self : ReachableDerived[T]) -> Expr[T]
pub fn[T] EagerDerived::expr(self : EagerDerived[T]) -> Expr[T]
```

`ReachableDerived` carries `T : Eq` because its current facade read path carries
that bound. `EagerDerived` reads are currently unbounded, so its source lift
should remain unbounded too. Do not promise unbounded source lifts for facades
whose underlying read paths are bounded.

Compatibility handles (`Signal`, `TrackedCell`, `Memo`, `HybridMemo`) should not
get v1 `expr()` methods. The formula API is part of the target facade surface;
old names remain supported for existing code but should not gain every new
convenience by default.

### Constants

Constants are explicit about their runtime:

```moonbit
let fee = Expr::constant(rt, 100, label="fee")
let total = subtotal.expr() + fee
```

Do not add `Expr::pure(value)` in v1. A runtime-less expression would either
make `expr + pure(1)` delay validation until materialization or require special
composition rules. Requiring `rt` keeps the invariant simple: every `Expr[T]`
has exactly one owning runtime.

The captured value is returned as-is on each evaluation. There is no defensive
copy; this matches ordinary MoonBit closure capture semantics.

## Runtime invariant

Every `Expr[T]` stores a `Runtime`. Composition validates that all operands
belong to the same runtime immediately:

```moonbit
fn[A, B] Expr::assert_same_runtime(left : Expr[A], right : Expr[B], op : String) -> Unit
```

The implementation can compare `left.rt.core.runtime_id` and
`right.rt.core.runtime_id` because `Expr` is in the `cells` package. On mismatch,
abort with a message shaped like:

```text
Cross-runtime expression: operator + composed Runtime 1 with Runtime 2
```

This is API misuse, not a recoverable `CycleError`. Early validation is better
than waiting for the final `Derived` to compute because it points at the bad
composition site.

The early check covers expression operands only. It cannot inspect arbitrary
closures passed to `map` / `map2`: a user closure can still capture a cell from
another runtime. Treat that as closure misuse. Existing tracked read-path
cross-runtime guards catch captured `get()` / `read()` calls when the
materialized expression evaluates, but not at expression composition time.
Untracked `peek()` calls intentionally do not record dependencies or run the
cross-runtime guard, so public documentation should tell users not to call
`peek()` from formula closures.

`Scope::derived_expr(scope, expr, label?)` must also validate that
`expr.rt.core.runtime_id == scope.runtime.core.runtime_id` before registering the
owned derived cell. `Expr::derived(label?)` needs no extra runtime argument and
materializes against `expr.rt`.

## Core combinators

Operators should be thin wrappers over explicit combinators:

```moonbit
pub fn[A, B] Expr::map(self : Expr[A], f : (A) -> B raise Failure) -> Expr[B]

pub fn[A, B, C] Expr::map2(
  left : Expr[A],
  right : Expr[B],
  f : (A, B) -> C raise Failure,
) -> Expr[C]
```

`map2` performs the same-runtime check once for its explicit expression operands
at composition time, then returns a new expression whose `eval` closure evaluates
both operands and applies `f`. `map` preserves the receiver runtime.

Public `map` / `map2` closures should be documented as pure transformations over
their arguments. They may raise `Failure`, but should not read unrelated
reactive handles. If they do capture a handle from another runtime and call a
tracked read (`get()` / `read()`), the current runtime guards catch it when the
materialized expression is evaluated, not when `map` / `map2` is called.
Untracked `peek()` calls remain outside this guard by design and are misuse in a
formula closure.

These combinators make the formula layer useful beyond arithmetic and provide a
single implementation path for operator methods.

## Operators

Implement arithmetic operators on `Expr[T]`, not on source handles:

| Operator trait | `Expr` result | Bound on `T` |
|---|---|---|
| `Add` | `Expr[T] + Expr[T] -> Expr[T]` | `T : Add` |
| `Sub` | `Expr[T] - Expr[T] -> Expr[T]` | `T : Sub` |
| `Mul` | `Expr[T] * Expr[T] -> Expr[T]` | `T : Mul` |
| `Div` | `Expr[T] / Expr[T] -> Expr[T]` | `T : Div` |
| `Mod` | `Expr[T] % Expr[T] -> Expr[T]` | `T : Mod` |
| `Neg` | `-Expr[T] -> Expr[T]` | `T : Neg` |

Defer bitwise operators until implementation verifies the current MoonBit trait
names and signatures. Defer comparisons and boolean operators as well:
comparison traits produce `Bool`, not `Self`, and expression structural equality
would be a poor meaning for `==` on formulas. If users need comparison formulas,
add named combinators later, such as `Expr::lt(left, right) -> Expr[Bool]`.

## Materialization

`Expr` materializes to a normal target `Derived`:

```moonbit
pub fn[T : Eq] Expr::derived(self : Expr[T], label? : String) -> Derived[T]

pub fn[T : Eq] Scope::derived_expr(
  self : Scope,
  expr : Expr[T],
  label? : String,
) -> Derived[T]
```

`Expr::derived` constructs `Derived(self.rt, () => self.eval(), label?)`.
`Scope::derived_expr` mirrors `Scope::derived`, but validates same-runtime and
registers the resulting cell for disposal.

Do not add `Expr::reachable_derived` in v1. Source expressions may read from
`ReachableDerived`, but the first materialization target should be the ordinary
lazy `Derived` because it is the target facade users already use for formulas.
A reachable materialization variant can be added later if a concrete UI or
long-lived graph case needs it.

Expression composition creates closures and small expression values, but no
incremental cells. Reusing an unmaterialized expression duplicates work:

```moonbit
let sum = a.expr() + b.expr()
let squared = sum * sum // evaluates `sum` twice when materialized
```

That is intentional. Users who need sharing should materialize the subformula:

```moonbit
let sum = (a.expr() + b.expr()).derived(label="sum")
let squared = (sum.expr() * sum.expr()).derived(label="squared")
```

## Indexing

Do not implement `_[_]` for `Expr` or `DerivedMap` in v1.

For keyed derived values, prefer named methods if and when expression support is
needed:

```moonbit
// Later design, not v1.
by_key.expr_at(key)       // constant key
by_key.expr_at_expr(kx)   // reactive key expression
```

Named methods avoid spending MoonBit indexing syntax on scalar cells before the
reactive collection design (`InputMap`, `InputArray`, text/line views) is known.

## Labels and debug output

The materialized cell label remains explicit:

```moonbit
(price.expr() * quantity.expr()).derived(label="subtotal")
```

Do not automatically use the formula text as the `Derived` label in v1. Automatic
labels can become long, unstable, and would require `Show`/`Debug` constraints
for constants. The expression may carry a small private `ExprDebug` tree for
future diagnostics, but `Runtime::cell_info()` should report only the label
provided at materialization.

Recommended debug policy for v1:

- source lifts record known cell labels internally when available;
- constants record their optional label or `const` without formatting the value;
- operators record the operator token;
- no public `Expr::to_string` until there is a concrete diagnostic consumer.

## Motivating recipe: immutable domain structs with input fields

The primary target is domain structs whose fields are mutable cells but whose
shape is stable:

```moonbit
// Proposed API; checked after implementation.
pub(all) struct CartLine {
  price : @incr.InputField[Int]
  quantity : @incr.InputField[Int]
}

pub fn CartLine::CartLine(rt : @incr.Runtime, price : Int, quantity : Int) -> CartLine {
  {
    price: @incr.InputField(rt, price, label="CartLine.price"),
    quantity: @incr.InputField(rt, quantity, label="CartLine.quantity"),
  }
}

pub fn CartLine::subtotal_expr(self : CartLine) -> @incr.Expr[Int] {
  self.price.expr() * self.quantity.expr()
}

let subtotal = line.subtotal_expr().derived(label="subtotal")
```

Mutation remains explicit at the field boundary (`line.price.set(...)`), while
the formula stays declarative.

## Checked examples required with implementation

When this API is implemented, add checked literate examples rather than only
unchecked prose. Suggested file: `docs/expr_examples.mbt.md`, linked from
`docs/README.md`.

Minimum checked cases:

1. `InputField` cart subtotal: expression computes once materialized and updates
   after `set`.
2. No hidden intermediate cells: use `Runtime::cell_info` or cell-id counts from
   tests to prove only source cells plus one `Derived` are installed.
3. Constants require explicit runtime and compose with fields.
4. `Derived::expr()` uses strict tracked reads. The update behavior should still
   be tested, but that alone does not prove strictness because permissive reads
   also record dependencies while tracking. Use implementation review or a
   white-box hook to pin that this lift calls `get_or_abort()`, not
   `read_or_abort()`.
5. Cross-runtime composition aborts at operator composition time for explicit
   `Expr` operands.
6. A `map` / `map2` closure that captures a cell from another runtime and uses a
   tracked read (`get()` / `read()`) aborts when the materialized expression
   evaluates. Document this as closure misuse, not as early composition
   validation. Explicitly exclude `peek()` from this guarantee because it is
   untracked by design.
7. `Scope::derived_expr` owns the materialized derived and rejects expressions
   from another runtime.
8. Operator methods are absent on `Input` / `InputField`; keep this as compile
   discipline in review because it cannot be asserted in a runtime test.

## Implementation outline

1. Add `cells/expr.mbt` with `Expr[T]`, source lift methods, constants,
   `map`/`map2`, arithmetic operator impls, and `Expr::derived`.
2. Add `Scope::derived_expr` in `cells/scope.mbt`.
3. Re-export `Expr` from the root package via `incr.mbt`.
4. Add black-box tests for public behavior and white-box tests only if needed to
   assert cell allocation counts.
5. Add checked literate examples and update `docs/README.md`.
6. Update `docs/api-reference.mbt.md` only after the API exists; keep examples
   in checked companion files.

## Open follow-ups

- Whether `Formula[T]` should become a public alias after users try `Expr[T]`.
- Whether reachable materialization (`Expr::reachable_derived`) is needed.
- Whether comparison formulas deserve named combinators.
- Whether a future reactive collection design wants indexing syntax and how that
  interacts with `DerivedMap` expression reads.
