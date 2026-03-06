///|
test "pull_verify: signal always returns Ok" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  match rt.pull_verify(sig.id()) {
    Ok(_) => ()
    Err(_) => abort("expected Ok")
  }
}

///|
test "pull_verify: up-to-date memo returns Ok without recompute" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let mut count = 0
  let m = Memo::new(rt, () => {
    count += 1
    sig.get()
  })
  let _ = m.get()
  inspect(count, content="1")
  let _ = rt.pull_verify(m.id())
  inspect(count, content="1")
}

///|
test "pull_verify: stale memo recomputes on next get" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let m = Memo::new(rt, () => sig.get() + 10)
  let _ = m.get()
  sig.set(5)
  let _ = rt.pull_verify(m.id())
  inspect(m.get(), content="15")
}

///|
test "panic pull_verify: disposed dependency aborts verification" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 1)
  let unrelated = Signal::new(rt, 0)
  let r = Reactive::new(rt, () => sig.get() * 2)
  let m = Memo::new(rt, () => r.get() + 1)
  inspect(m.get(), content="3")
  r.dispose()
  unrelated.set(1) // bump revision so memo must re-verify deps
  let _ = m.get()
}
