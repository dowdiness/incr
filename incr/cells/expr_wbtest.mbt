///|
test "expr: InputField subtotal materializes one derived cell" {
  let rt = Runtime::Runtime()
  let price = InputField(rt, 10, label="price")
  let quantity = InputField(rt, 2, label="quantity")
  let cell_count_before_derived = rt.core.cell_ops.length()
  let subtotal = (price.expr() * quantity.expr()).derived(label="subtotal")
  inspect(subtotal.read_or_abort(), content="20")
  inspect(
    rt.core.cell_ops.length(),
    content=(cell_count_before_derived + 1).to_string(),
  )
  quantity.set(3)
  inspect(subtotal.read_or_abort(), content="30")
}

///|
test "expr: chain of three operators materializes +1 cell" {
  let rt = Runtime::Runtime()
  let a = Input(rt, 10)
  let b = Input(rt, 3)
  let c = Input(rt, 2)
  let before = rt.core.cell_ops.length()
  let expr = (a.expr() + b.expr()) * c.expr()
  let _ = expr.derived(label="result")
  inspect(rt.core.cell_ops.length(), content=(before + 1).to_string())
}

///|
test "expr: cell count via derived_expr also +1" {
  let rt = Runtime::Runtime()
  let a = Input(rt, 5)
  let scope = Scope::new(rt)
  let before = rt.core.cell_ops.length()
  let _ = scope.derived_expr(a.expr(), label="via_scope")
  inspect(rt.core.cell_ops.length(), content=(before + 1).to_string())
}
