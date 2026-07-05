///|
test "expr: InputField subtotal via operator and derived" {
  let rt = @incr.Runtime()
  let price = @incr.InputField(rt, 10, label="price")
  let quantity = @incr.InputField(rt, 2, label="quantity")
  let subtotal = (price.expr() * quantity.expr()).derived(label="subtotal")
  inspect(subtotal.read_or_abort(), content="20")
  quantity.set(3)
  inspect(subtotal.read_or_abort(), content="30")
}

///|
test "expr: add operator" {
  let rt = @incr.Runtime()
  let a = @incr.Input(rt, 10)
  let b = @incr.Input(rt, 3)
  let sum = (a.expr() + b.expr()).derived(label="sum")
  inspect(sum.read_or_abort(), content="13")
  a.set(20)
  inspect(sum.read_or_abort(), content="23")
}

///|
test "expr: sub operator" {
  let rt = @incr.Runtime()
  let a = @incr.Input(rt, 10)
  let b = @incr.Input(rt, 3)
  let diff = (a.expr() - b.expr()).derived(label="diff")
  inspect(diff.read_or_abort(), content="7")
  a.set(5)
  inspect(diff.read_or_abort(), content="2")
}

///|
test "expr: div operator" {
  let rt = @incr.Runtime()
  let a = @incr.Input(rt, 20)
  let b = @incr.Input(rt, 4)
  let quot = (a.expr() / b.expr()).derived(label="quot")
  inspect(quot.read_or_abort(), content="5")
}

///|
test "expr: mod operator" {
  let rt = @incr.Runtime()
  let a = @incr.Input(rt, 17)
  let b = @incr.Input(rt, 5)
  let rem = (a.expr() % b.expr()).derived(label="rem")
  inspect(rem.read_or_abort(), content="2")
}

///|
test "expr: neg operator" {
  let rt = @incr.Runtime()
  let a = @incr.Input(rt, 42)
  let neg = (-a.expr()).derived(label="neg")
  inspect(neg.read_or_abort(), content="-42")
  a.set(10)
  inspect(neg.read_or_abort(), content="-10")
}

///|
test "expr: multi-operator chain" {
  let rt = @incr.Runtime()
  let a = @incr.Input(rt, 10)
  let b = @incr.Input(rt, 3)
  let c = @incr.Input(rt, 2)
  // (10 + 3) * 2 = 26
  let result = ((a.expr() + b.expr()) * c.expr()).derived(label="result")
  inspect(result.read_or_abort(), content="26")
  a.set(5)
  // (5 + 3) * 2 = 16
  inspect(result.read_or_abort(), content="16")
}

///|
test "expr: Derived::expr lift" {
  let rt = @incr.Runtime()
  let a = @incr.Input(rt, 5)
  let d = @incr.Derived(rt, fn() { a.get() * 2 }, label="double")
  let double_expr = d.expr()
  let result = double_expr.derived(label="result")
  inspect(result.read_or_abort(), content="10")
  a.set(3)
  inspect(result.read_or_abort(), content="6")
}

///|
test "expr: Expr::constant composition" {
  let rt = @incr.Runtime()
  let a = @incr.Input(rt, 10)
  // a + 5
  let result = (a.expr() + @incr.Expr::constant(rt, 5)).derived(label="result")
  inspect(result.read_or_abort(), content="15")
  a.set(20)
  inspect(result.read_or_abort(), content="25")
}

///|
test "expr: Scope::derived_expr" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let a = scope.input(7)
  let b = scope.input(3)
  let expr = a.expr() + b.expr()
  let sum = scope.derived_expr(expr, label="sum")
  inspect(sum.read_or_abort(), content="10")
  scope.dispose()
}

///|
test "expr: ReachableDerived::expr lift" {
  let rt = @incr.Runtime()
  let a = @incr.Input(rt, 10)
  let rd = @incr.ReachableDerived(rt, fn() { a.get() * 3 }, label="triple")
  let result = rd.expr().derived(label="result")
  inspect(result.read_or_abort(), content="30")
  a.set(5)
  inspect(result.read_or_abort(), content="15")
}

///|
test "panic expr: cross-runtime composition aborts" {
  let rt_a = @incr.Runtime()
  let rt_b = @incr.Runtime()
  let a = @incr.Input(rt_a, 10)
  let b = @incr.Input(rt_b, 20)
  // map2 checks same runtime at composition time; + dispatches to map2
  let _sum = a.expr() + b.expr()
}

///|
test "panic expr: Scope::derived_expr with wrong runtime aborts" {
  let rt_a = @incr.Runtime()
  let rt_b = @incr.Runtime()
  let scope = @incr.Scope::new(rt_a)
  let a = @incr.Input(rt_b, 10)
  let _ = scope.derived_expr(a.expr(), label="wrong")
}

///|
test "expr: .e() alias for InputField" {
  let rt = @incr.Runtime()
  let price = @incr.InputField(rt, 10, label="price")
  let quantity = @incr.InputField(rt, 2, label="quantity")
  let subtotal = (price.e() * quantity.e()).derived(label="subtotal")
  inspect(subtotal.read_or_abort(), content="20")
  quantity.set(3)
  inspect(subtotal.read_or_abort(), content="30")
}
