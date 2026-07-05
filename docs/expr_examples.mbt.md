# Checked `Expr[T]` Formula Examples

These literate tests are companions to the
[`Expr[T]` Formula API spec](design/specs/2026-05-25-expr-formula-api.md).
They cover the minimum checked cases required by the spec.

```mbt check
///|
test "expr docs: InputField cart subtotal" {
  let rt = @incr.Runtime()
  let price = @incr.InputField(rt, 10, label="price")
  let quantity = @incr.InputField(rt, 2, label="quantity")
  let subtotal = (price.expr() * quantity.expr()).derived(label="subtotal")
  inspect(subtotal.read_or_abort(), content="20")
  quantity.set(3)
  inspect(subtotal.read_or_abort(), content="30")
}

///|
test "expr docs: Expr::constant composes with fields" {
  let rt = @incr.Runtime()
  let a = @incr.Input(rt, 10)
  let result = (a.expr() + @incr.Expr::constant(rt, 5)).derived(label="result")
  inspect(result.read_or_abort(), content="15")
  a.set(20)
  inspect(result.read_or_abort(), content="25")
}

///|
test "expr docs: multi-operator chain materializes correctly" {
  let rt = @incr.Runtime()
  let a = @incr.Input(rt, 10)
  let b = @incr.Input(rt, 3)
  let c = @incr.Input(rt, 2)
  let result = ((a.expr() + b.expr()) * c.expr()).derived(label="result")
  inspect(result.read_or_abort(), content="26")
  a.set(5)
  inspect(result.read_or_abort(), content="16")
}

///|
test "expr docs: neg operator" {
  let rt = @incr.Runtime()
  let a = @incr.Input(rt, 42)
  let neg = (-a.expr()).derived(label="neg")
  inspect(neg.read_or_abort(), content="-42")
  a.set(10)
  inspect(neg.read_or_abort(), content="-10")
}

///|
test "expr docs: Derived::expr lift" {
  let rt = @incr.Runtime()
  let a = @incr.Input(rt, 5)
  let d = @incr.Derived(rt, fn() { a.get() * 2 }, label="double")
  let result = d.expr().derived(label="result")
  inspect(result.read_or_abort(), content="10")
  a.set(3)
  inspect(result.read_or_abort(), content="6")
}

///|
test "expr docs: Scope::derived_expr" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let a = scope.input(7)
  let b = scope.input(3)
  let sum = scope.derived_expr(a.expr() + b.expr(), label="sum")
  inspect(sum.read_or_abort(), content="10")
  scope.dispose()
  inspect(scope.is_disposed(), content="true")
}

///|
test "panic expr docs: cross-runtime composition aborts" {
  let rt_a = @incr.Runtime()
  let rt_b = @incr.Runtime()
  let a = @incr.Input(rt_a, 10)
  let b = @incr.Input(rt_b, 20)
  let _sum = a.expr() + b.expr()
}
```
