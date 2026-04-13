///|
test "scope: create and dispose via public API" {
  let rt = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt)
  let sig = scope.signal(42)
  let m = scope.memo(fn() { sig.get() * 2 })
  inspect(rt.read(m), content="84")
  scope.dispose()
  inspect(sig.is_disposed(), content="true")
  inspect(m.is_disposed(), content="true")
}

///|
test "scope: nested scopes via public API" {
  let rt = @incr.Runtime::new()
  let parent = @incr.Scope::new(rt)
  let child = parent.child()
  let sig = child.signal(10)
  parent.dispose()
  inspect(sig.is_disposed(), content="true")
}

///|
test "scope: manual dispose before scope dispose is safe" {
  let rt = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt)
  let sig = scope.signal(1)
  let m = scope.memo(fn() { sig.get() })
  // Manually dispose the memo before the scope
  m.dispose()
  inspect(m.is_disposed(), content="true")
  // Scope dispose should not abort — idempotent
  scope.dispose()
  inspect(sig.is_disposed(), content="true")
}

///|
test "scope: scope does not interfere with unscoped cells" {
  let rt = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt)
  let scoped_sig = scope.signal(1)
  let unscoped_sig = @incr.Signal::new(rt, 2)
  scope.dispose()
  inspect(scoped_sig.is_disposed(), content="true")
  inspect(unscoped_sig.is_disposed(), content="false")
  // Unscoped signal still works
  inspect(unscoped_sig.get(), content="2")
}

///|
test "scope: child scope cells disposed before parent cells" {
  let rt = @incr.Runtime::new()
  let parent = @incr.Scope::new(rt)
  let parent_sig = parent.signal(100)
  let child = parent.child()
  let child_sig = child.signal(200)
  // Child reads parent — this is the typical pattern
  let child_memo = child.memo(fn() { parent_sig.get() + child_sig.get() })
  inspect(rt.read(child_memo), content="300")
  parent.dispose()
  inspect(child_sig.is_disposed(), content="true")
  inspect(child_memo.is_disposed(), content="true")
  inspect(parent_sig.is_disposed(), content="true")
}

///|
test "scope: dispose during batch — pending signal writes discarded" {
  let rt = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt)
  let sig = scope.signal(1)
  rt.batch(fn() {
    sig.set(99)
    // Dispose the scope mid-batch — pending write should be discarded
    scope.dispose()
  })
  inspect(sig.is_disposed(), content="true")
}

///|
test "scope: cell manually disposed before scope dispose is safe" {
  let rt = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt)
  let sig1 = scope.signal(1)
  let sig2 = scope.signal(2)
  // Manually dispose one cell
  sig1.dispose()
  inspect(sig1.is_disposed(), content="true")
  inspect(sig2.is_disposed(), content="false")
  // Scope dispose should handle already-disposed cell gracefully
  scope.dispose()
  inspect(sig2.is_disposed(), content="true")
}

///|
test "scope: dispose after push propagation completes" {
  let rt = @incr.Runtime::new()
  let scope = @incr.Scope::new(rt)
  let sig = scope.signal(1)
  let count : Ref[Int] = { val: 0 }
  let eff = scope.effect(fn() { count.val = count.val + sig.get() })
  inspect(count.val, content="1")
  // Trigger push propagation
  sig.set(10)
  inspect(count.val, content="11")
  // Dispose after propagation completes — should be safe
  scope.dispose()
  inspect(sig.is_disposed(), content="true")
  inspect(eff.is_disposed(), content="true")
}
