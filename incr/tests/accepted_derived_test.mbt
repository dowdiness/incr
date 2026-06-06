// Black-box tests for the public `AcceptedDerived` facade: everything here uses
// only the re-exported `@incr` surface, so it doubles as a proof that the public
// API (constructors, accessors, `AcceptedSnapshot` field reads, `AcceptStatus`
// matching) is usable from a consumer package. Cases that require internal
// access (current/accepted wake-counting, simulating a Disposed candidate) live
// in incr/cells/accepted_derived_wbtest.mbt.

///|
/// Domain parse with hand-reasoned outcomes. `"v1"`/`"v1b"` both → `Ok(1)` (same
/// accepted value from different sources → candidate backdates); `"v2"` → `Ok(2)`;
/// `"e1a"`/`"e1b"` both → `Err("e1")`; `"e2"` → a distinct `Err("e2")`.
fn ad_parse(s : String) -> Result[Int, String] {
  match s {
    "v1" => Ok(1)
    "v1b" => Ok(1)
    "v2" => Ok(2)
    "e1a" => Err("e1")
    "e1b" => Err("e1")
    "e2" => Err("e2")
    _ => Err("other")
  }
}

// --- state machine rows -----------------------------------------------------

///|
test "public: no prior, Err → NoAccept" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "e1a")
  let ad = @incr.AcceptedDerived::AcceptedDerived(rt, () => {
    ad_parse(input.get())
  })
  inspect(ad.accepted_or_abort() is None, content="true")
  inspect(ad.snapshot_or_abort().status, content="NoAccept")
  inspect(ad.current_or_abort() is Err("e1"), content="true")
}

///|
test "public: no prior, Ok → AcceptedChanged" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "v1")
  let ad = @incr.AcceptedDerived::AcceptedDerived(rt, () => {
    ad_parse(input.get())
  })
  inspect(ad.accepted_or_abort() is Some(1), content="true")
  inspect(ad.snapshot_or_abort().status, content="AcceptedChanged")
  inspect(ad.current_or_abort() is Ok(1), content="true")
}

///|
test "public: prior Some, Err → RetainedDueToError" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "v1")
  let ad = @incr.AcceptedDerived::AcceptedDerived(rt, () => {
    ad_parse(input.get())
  })
  input.set("e1a")
  inspect(ad.accepted_or_abort() is Some(1), content="true")
  inspect(ad.snapshot_or_abort().status, content="RetainedDueToError")
  inspect(ad.current_or_abort() is Err("e1"), content="true")
}

///|
test "public: prior Some, equal Ok via Err → AcceptedUnchanged" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "v1")
  let ad = @incr.AcceptedDerived::AcceptedDerived(rt, () => {
    ad_parse(input.get())
  })
  input.set("e1a")
  input.set("v1b")
  inspect(ad.accepted_or_abort() is Some(1), content="true")
  inspect(ad.snapshot_or_abort().status, content="AcceptedUnchanged")
}

///|
test "public: backdated candidate still reports AcceptedUnchanged" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "v1")
  let ad = @incr.AcceptedDerived::AcceptedDerived(rt, () => {
    ad_parse(input.get())
  })
  input.set("v1b") // Ok(1) both times → candidate backdates; fold still runs
  inspect(ad.accepted_or_abort() is Some(1), content="true")
  inspect(ad.snapshot_or_abort().status, content="AcceptedUnchanged")
}

///|
test "public: prior Some, changed Ok → AcceptedChanged" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "v1")
  let ad = @incr.AcceptedDerived::AcceptedDerived(rt, () => {
    ad_parse(input.get())
  })
  input.set("v2")
  inspect(ad.accepted_or_abort() is Some(2), content="true")
  inspect(ad.snapshot_or_abort().status, content="AcceptedChanged")
  inspect(ad.current_or_abort() is Ok(2), content="true")
}

///|
test "public: transient success accepted without intervening read" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "e1a")
  let ad = @incr.AcceptedDerived::AcceptedDerived(rt, () => {
    ad_parse(input.get())
  })
  input.set("v1") // transient Ok(1): eager fold accepts it
  input.set("e1a") // Err: retained
  inspect(ad.accepted_or_abort() is Some(1), content="true")
  inspect(ad.snapshot_or_abort().status, content="RetainedDueToError")
}

// --- accepted_changed_at gating + accepted-only consumers -------------------

///|
test "public: changed_at advances only on accepted-value change" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "v1")
  let ad = @incr.AcceptedDerived::AcceptedDerived(rt, () => {
    ad_parse(input.get())
  })
  let r1 = ad.accepted_changed_at()
  input.set("e1a") // RetainedDueToError: accepted unchanged
  inspect(ad.accepted_changed_at() == r1, content="true")
  input.set("e2") // different error, still no accepted change
  inspect(ad.accepted_changed_at() == r1, content="true")
  input.set("v1b") // equal success: accepted unchanged
  inspect(ad.accepted_changed_at() == r1, content="true")
  input.set("v2") // changed success: accepted advances
  inspect(ad.accepted_changed_at() == r1, content="false")
}

///|
test "public: accepted-only consumers ignore current-error churn" {
  // Accepted value stays Some(1) across e1 → e2 current churn, so the accepted
  // revision (what accepted-only downstream consumers gate on) does not advance.
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "v1")
  let ad = @incr.AcceptedDerived::AcceptedDerived(rt, () => {
    ad_parse(input.get())
  })
  let r1 = ad.accepted_changed_at()
  input.set("e1a")
  input.set("e2")
  inspect(ad.accepted_or_abort() is Some(1), content="true")
  inspect(ad.accepted_changed_at() == r1, content="true")
}

// --- snapshot coherence (validates AcceptedSnapshot field reads externally) --

///|
test "public: snapshot exposes coherent current/accepted/status fields" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "v1")
  let ad = @incr.AcceptedDerived::AcceptedDerived(rt, () => {
    ad_parse(input.get())
  })
  input.set("e1a")
  let snap = ad.snapshot_or_abort()
  inspect(snap.current is Err("e1"), content="true")
  inspect(snap.accepted is Some(1), content="true")
  inspect(snap.status, content="RetainedDueToError")
}

// --- gc survival + batch coherence -----------------------------------------

///|
test "public: chain survives Runtime::gc()" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "v1")
  let ad = @incr.AcceptedDerived::AcceptedDerived(rt, () => {
    ad_parse(input.get())
  })
  inspect(ad.accepted_or_abort() is Some(1), content="true")
  rt.gc()
  inspect(ad.accepted_or_abort() is Some(1), content="true")
  input.set("v2")
  inspect(ad.accepted_or_abort() is Some(2), content="true")
}

///|
test "public: batch coalesces to one committed transition" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "e1a")
  let ad = @incr.AcceptedDerived::AcceptedDerived(rt, () => {
    ad_parse(input.get())
  })
  inspect(ad.accepted_or_abort() is None, content="true")
  rt.batch(fn() {
    input.set("v1") // transient Ok(1) inside the batch
    input.set("e1a") // committed value: Err
  })
  // Coalesced → the transient Ok(1) is never separately accepted.
  inspect(ad.accepted_or_abort() is None, content="true")
  inspect(ad.snapshot_or_abort().status, content="NoAccept")
}

///|
test "public: batch with a single net accepted change" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "v1")
  let ad = @incr.AcceptedDerived::AcceptedDerived(rt, () => {
    ad_parse(input.get())
  })
  let r1 = ad.accepted_changed_at()
  rt.batch(fn() {
    input.set("v2")
    input.set("v1b") // committed Ok(1) == prior accepted
  })
  inspect(ad.accepted_or_abort() is Some(1), content="true")
  inspect(ad.snapshot_or_abort().status, content="AcceptedUnchanged")
  inspect(ad.accepted_changed_at() == r1, content="true")
}

// --- constructors -----------------------------------------------------------

///|
test "public: from_candidate wraps an external candidate; dispose spares it" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "v1")
  let candidate = @incr.Derived::fallible(rt, () => ad_parse(input.get()))
  let ad = @incr.AcceptedDerived::from_candidate(candidate)
  inspect(ad.accepted_or_abort() is Some(1), content="true")
  input.set("v2")
  inspect(ad.accepted_or_abort() is Some(2), content="true")
  ad.dispose()
  inspect(ad.is_disposed(), content="true")
  // The externally-owned candidate is NOT disposed by the AcceptedDerived.
  inspect(candidate.read_or_abort() is Ok(2), content="true")
}

///|
test "public: Scope::accepted_derived disposes with its parent scope" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "v1")
  let scope = @incr.Scope::new(rt)
  let ad = scope.accepted_derived(() => ad_parse(input.get()))
  inspect(ad.accepted_or_abort() is Some(1), content="true")
  input.set("v2")
  inspect(ad.accepted_or_abort() is Some(2), content="true")
  scope.dispose()
  inspect(ad.is_disposed(), content="true")
}
