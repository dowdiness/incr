// Drift-catch for README.md and docs/getting-started.mbt.md quickstart examples.

///|
test "quickstart: target constructors from README" {
  let rt = @incr.Runtime()
  let x = rt.input(10, label="x")
  let y = rt.input(20, label="y")
  let sum = x.derived2(y, (a, b) => a + b, label="sum")
  let doubled = sum.map(v => v * 2, label="doubled")
  inspect(sum.read_or_abort(), content="30")
  inspect(doubled.read_or_abort(), content="60")
  x.set(5)
  inspect(doubled.read_or_abort(), content="50")
}
