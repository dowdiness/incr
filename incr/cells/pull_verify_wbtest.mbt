///|
test "pull_verify: input always returns Ok" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  match rt.pull_verify(sig.id()) {
    Ok(_) => ()
    Err(_) => abort("expected Ok")
  }
}

///|
test "pull_verify: up-to-date memo returns Ok without recompute" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let mut count = 0
  let m = Derived(rt, () => {
    count += 1
    sig.get()
  })
  let _ = m.read_or_abort()
  inspect(count, content="1")
  let _ = rt.pull_verify(m.id())
  inspect(count, content="1")
}

///|
test "pull_verify: stale memo recomputes on next get" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let m = Derived(rt, () => sig.get() + 10)
  let _ = m.read_or_abort()
  sig.set(5)
  let _ = rt.pull_verify(m.id())
  inspect(m.read_or_abort(), content="15")
}

///|
test "panic pull_verify: disposed dependency aborts verification" {
  let rt = Runtime::Runtime()
  let sig = Input::Input(rt, 1)
  let unrelated = Input::Input(rt, 0)
  let r = Reactive::new(rt, () => sig.get() * 2)
  let m = Derived(rt, () => r.get() + 1)
  inspect(m.read_or_abort(), content="3")
  r.dispose()
  unrelated.set(1) // bump revision so memo must re-verify deps
  let _ = m.read_or_abort()
}
