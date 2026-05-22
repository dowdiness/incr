///|
#warnings("-deprecated")
test "runtime read legacy compatibility helpers still work" {
  let rt = @incr.Runtime()
  let input = @incr.Signal(rt, 2)
  let memo = @incr.Memo(rt, () => input.get() + 1)
  let hybrid = @incr.HybridMemo(rt, () => input.get() * 2)
  let reactive = @incr.Reactive::new(rt, () => input.get() * 3)

  inspect(rt.read(memo), content="3")
  inspect(rt.read_hybrid(hybrid), content="4")
  inspect(rt.read_reactive(reactive), content="6")
}
