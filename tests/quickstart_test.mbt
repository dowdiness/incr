// Drift-catch for README.md and docs/getting-started.mbt.md quickstart examples.

///|
test "quickstart: target constructors from README" {
  let rt = @incr.Runtime()
  let x = @incr.Input(rt, 10, label="x")
  let y = @incr.Input(rt, 20, label="y")
  let sum = @incr.Derived(rt, () => x.get() + y.get(), label="sum")
  inspect(sum.read_or_abort(), content="30")
  x.set(5)
  inspect(sum.read_or_abort(), content="25")
}
