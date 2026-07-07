///|
/// Validates `@incr.Expr[T]` in spreadsheet-like formula scenarios via raw incr facades.
///
/// These tests exercise Expr in patterns mirroring real worksheet formulas:
/// cross-cell references, chained arithmetic, reactive updates, constant reuse.
/// They use raw incr facades to validate Expr independently of the Worksheet API layer.
///
/// See also: `typed_spreadsheet_formula_test.mbt` for Worksheet-native Formula AST tests.

///|
test "typed spreadsheet expr: subtotal = unit_price * quantity" {
  let rt = @incr.Runtime()
  let unit_price = @incr.Input(rt, 5, label="unit_price")
  let quantity = @incr.Input(rt, 3, label="quantity")
  // C1 = A1 * B1 (spreadsheet pattern)
  let subtotal = (unit_price.expr() * quantity.expr()).derived(label="subtotal")
  inspect(subtotal.read_or_abort(), content="15")
  quantity.set(10)
  inspect(subtotal.read_or_abort(), content="50")
}

///|
test "typed spreadsheet expr: tax = subtotal * 0.1 with constant" {
  let rt = @incr.Runtime()
  let unit_price = @incr.Input(rt, 100, label="unit_price")
  let quantity = @incr.Input(rt, 2, label="quantity")
  let subtotal = (unit_price.expr() * quantity.expr()).derived(label="subtotal")
  // tax = subtotal * 10 / 100
  let tax = (subtotal.expr() *
  @incr.Expr::constant(rt, 10) /
  @incr.Expr::constant(rt, 100)).derived(label="tax")
  inspect(subtotal.read_or_abort(), content="200")
  inspect(tax.read_or_abort(), content="20")
  unit_price.set(50)
  inspect(subtotal.read_or_abort(), content="100")
  inspect(tax.read_or_abort(), content="10")
}

///|
test "typed spreadsheet expr: chained formula with intermediate" {
  let rt = @incr.Runtime()
  let base = @incr.Input(rt, 10, label="base")
  let adjustment = @incr.Input(rt, 5, label="adjustment")
  let stepped = (base.expr() + adjustment.expr()).derived(label="stepped")
  let doubled = (stepped.expr() * @incr.Expr::constant(rt, 2)).derived(
    label="doubled",
  )
  inspect(stepped.read_or_abort(), content="15")
  inspect(doubled.read_or_abort(), content="30")
  base.set(20)
  inspect(stepped.read_or_abort(), content="25")
  inspect(doubled.read_or_abort(), content="50")
}

///|
test "typed spreadsheet expr: cell refs via Derived::expr lift" {
  let rt = @incr.Runtime()
  let a1 = @incr.Input(rt, 10, label="A1")
  let a2 = @incr.Input(rt, 20, label="A2")
  let b1 = @incr.Derived(rt, fn() { a1.get() + a2.get() }, label="B1")
  let b2 = @incr.Derived(rt, fn() { a1.get() * a2.get() }, label="B2")
  // C1 reads B1 and B2 via Derived::expr lift
  let c1 = (b1.expr() + b2.expr()).derived(label="C1")
  inspect(c1.read_or_abort(), content="230") // (10+20) + (10*20) = 30 + 200
  a1.set(5)
  inspect(c1.read_or_abort(), content="125") // (5+20) + (5*20) = 25 + 100
}

///|
test "typed spreadsheet expr: ReachableDerived as formula cell" {
  let rt = @incr.Runtime()
  let a1 = @incr.Input(rt, 7, label="A1")
  let formula = @incr.ReachableDerived(
    rt,
    fn() { a1.get() * 3 },
    label="formula",
  )
  inspect(formula.read_or_abort(), content="21")
  let chained = (formula.expr() + @incr.Expr::constant(rt, 1)).derived(
    label="chained",
  )
  inspect(chained.read_or_abort(), content="22")
  a1.set(10)
  inspect(chained.read_or_abort(), content="31") // (10*3) + 1
}
