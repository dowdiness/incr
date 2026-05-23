# Checked Target API Examples

These literate tests mirror the high-value target API examples in
[`README.md`](../README.md) and [`getting-started.md`](getting-started.md).
They exist to catch docs/API drift for the recommended facade names and read
semantics.

```mbt check
///|
test "docs target api: direct constructor quick start" {
  let rt = @incr.Runtime()
  let x = @incr.Input(rt, 10, label="x")
  let y = @incr.Input(rt, 20, label="y")
  let sum = @incr.Derived(rt, () => x.get() + y.get(), label="sum")

  inspect(sum.read_or_abort(), content="30")
  x.set(5)
  inspect(sum.read_or_abort(), content="25")
}

///|
test "docs target api: direct runtime read and update" {
  let rt = @incr.Runtime()
  let price = @incr.Input(rt, 100, label="price")
  let quantity = @incr.Input(rt, 5, label="quantity")
  let total = @incr.Derived(
    rt,
    () => price.get() * quantity.get(),
    label="total",
  )

  inspect(total.read_or_abort(), content="500")
  quantity.set(10)
  inspect(total.read_or_abort(), content="1000")
}

///|
test "docs target api: scope constructors own lifecycle" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let x = scope.input(10, label="x")
  let y = scope.input(20, label="y")
  let sum = scope.derived(() => x.get() + y.get(), label="sum")

  inspect(sum.read_or_abort(), content="30")
  scope.dispose()
  inspect(scope.is_disposed(), content="true")
}

///|
test "docs target api: read result and strict get inside derived" {
  let rt = @incr.Runtime()
  let base_price = @incr.Input(rt, 100, label="base_price")
  let quantity = @incr.Input(rt, 2, label="quantity")
  let tax_rate = @incr.Input(rt, 0.1, label="tax_rate")
  let subtotal = @incr.Derived(
    rt,
    () => base_price.get() * quantity.get(),
    label="subtotal",
  )
  let tax = @incr.Derived(
    rt,
    () => subtotal.get_or_abort().to_double() * tax_rate.get(),
    label="tax",
  )
  let total = @incr.Derived(
    rt,
    () => subtotal.get_or_abort().to_double() + tax.get_or_abort(),
    label="total",
  )

  match total.read() {
    Ok(value) => inspect(value, content="220")
    Err(err) => abort(err.format_path())
  }

  quantity.set(3)
  inspect(total.read_or_abort(), content="330")
}

///|
test "docs target api: watch keeps derived live across gc" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 1, label="input")
  let watch = {
    let derived = @incr.Derived(rt, () => input.get() + 1, label="derived")
    derived.watch()
  }

  inspect(watch.read_or_abort(), content="2")
  rt.gc()
  input.set(2)
  inspect(watch.read_or_abort(), content="3")
  watch.dispose()
}
```
