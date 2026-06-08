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

///|
test "public: watch_accepted stays put across current-error churn, advances on accepted change" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "v1")
  let ad = @incr.AcceptedDerived::AcceptedDerived(rt, () => {
    ad_parse(input.get())
  })
  // The public watch facade reads the accepted projection; it backdates on the
  // accepted value, so current-error churn must not change what it reports.
  let watch = ad.watch_accepted()
  inspect(watch.read_or_abort() is Some(1), content="true")
  let r1 = ad.accepted_changed_at()
  input.set("e1a") // RetainedDueToError
  input.set("e2") // different error, still retained
  input.set("v1b") // equal success, no advance
  inspect(watch.read_or_abort() is Some(1), content="true")
  inspect(ad.accepted_changed_at() == r1, content="true")
  // A genuine accepted-value change advances both the watched value and revision.
  input.set("v2")
  inspect(watch.read_or_abort() is Some(2), content="true")
  inspect(ad.accepted_changed_at() == r1, content="false")
  watch.dispose()
}

///|
test "public: in-graph accepted consumer gates on accepted value, not candidate churn" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "v1")
  let ad = @incr.AcceptedDerived::AcceptedDerived(rt, () => {
    ad_parse(input.get())
  })
  // An accepted-only in-graph consumer: reads the accepted value through the
  // tracked accessor, so it depends on the accepted projection, not the candidate.
  let runs = [0]
  let consumer = @incr.Derived::Derived(rt, () => {
    runs[0] = runs[0] + 1
    ad.accepted_get_or_abort()
  })
  let watch = consumer.watch()
  ignore(watch.read_or_abort()) // prime
  let base = runs[0]
  // Current-error churn: candidate changes (e1 -> e2) but the accepted value is
  // retained, so the consumer must NOT re-run.
  input.set("e1a")
  ignore(watch.read_or_abort())
  input.set("e2")
  ignore(watch.read_or_abort())
  inspect(runs[0] == base, content="true")
  // A genuine accepted-value change DOES re-run the consumer.
  input.set("v2")
  ignore(watch.read_or_abort())
  inspect(runs[0] > base, content="true")
  watch.dispose()
}

///|
test "public: accepted_get reads the accepted value in-graph" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "v1")
  let ad = @incr.AcceptedDerived::AcceptedDerived(rt, () => {
    ad_parse(input.get())
  })
  // Unwrap inside the consumer so the cell's value type is `Int?` (ReadError is
  // not Eq, so a Result-valued Derived cannot backdate); the graceful in-graph
  // read is still exercised in a tracked frame.
  let consumer = @incr.Derived::Derived(rt, () => {
    match ad.accepted_get() {
      Ok(v) => v
      Err(_) => None
    }
  })
  let watch = consumer.watch()
  inspect(watch.read_or_abort() is Some(1), content="true")
  input.set("e1a") // retained: accepted unchanged
  inspect(watch.read_or_abort() is Some(1), content="true")
  input.set("v2") // accepted advances
  inspect(watch.read_or_abort() is Some(2), content="true")
  watch.dispose()
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
test "public: disposed wrapper reports Disposed on all channels, candidate spared" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "v1")
  let candidate = @incr.Derived::fallible(rt, () => ad_parse(input.get()))
  let ad = @incr.AcceptedDerived::from_candidate(candidate)
  inspect(ad.accepted_or_abort() is Some(1), content="true")
  ad.dispose()
  // The external candidate is spared (from_candidate contract), but the disposed
  // wrapper must not bypass its own lifecycle: every read channel surfaces
  // Disposed rather than an incoherent fresh-current / stale-accepted mix.
  inspect(
    match ad.current() {
      Err(e) => e.is_disposed()
      Ok(_) => false
    },
    content="true",
  )
  inspect(
    match ad.accepted() {
      Err(e) => e.is_disposed()
      Ok(_) => false
    },
    content="true",
  )
  inspect(
    match ad.snapshot() {
      Err(e) => e.is_disposed()
      Ok(_) => false
    },
    content="true",
  )
  // The externally-owned candidate remains readable by its owner after a later edit.
  input.set("v2")
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

// --- BackdateEq tier --------------------------------------------------------
//
// `AcceptedDerived::accepted_memo` / `Scope::accepted_memo` accept a candidate
// value that is NOT `Eq` but carries a `Revision` (so it is `BackdateEq`).
// Acceptance is gated by revision identity, not structural equality.

///|
/// Non-`Eq` candidate value: a `Revision` is the acceptance identity, `payload`
/// can differ even when the revision is equal (proving acceptance gates on the
/// revision, not the value). Deliberately does NOT derive `Eq`.
priv struct AdDoc {
  revision : @incr.Revision
  payload : Int
}

///|
impl @incr.HasChangedAt for AdDoc with fn changed_at(self) -> @incr.Revision {
  self.revision
}

///|
impl @incr.BackdateEq for AdDoc

///|
/// `Revision` at `steps` advances from the initial revision.
fn ad_rev(steps : Int) -> @incr.Revision {
  let mut r = @incr.Revision::initial()
  for _ in 0..<steps {
    r = r.next()
  }
  r
}

///|
/// `"r1a"`/`"r1b"` → same revision (1), DIFFERENT payload (10 vs 99); `"r2"` →
/// a new revision (2); `"e1a"`/`"e1b"` → equal `Err("e1")`; `"e2"` → distinct.
fn ad_bd_parse(s : String) -> Result[AdDoc, String] {
  match s {
    "r1a" => Ok(AdDoc::{ revision: ad_rev(1), payload: 10 })
    "r1b" => Ok(AdDoc::{ revision: ad_rev(1), payload: 99 })
    "r2" => Ok(AdDoc::{ revision: ad_rev(2), payload: 20 })
    "e1a" => Err("e1")
    "e1b" => Err("e1")
    "e2" => Err("e2")
    _ => Err("other")
  }
}

///|
/// The retained accepted payload, or `-1` when nothing is accepted.
fn ad_accepted_payload(ad : @incr.AcceptedDerived[AdDoc, String]) -> Int {
  match ad.accepted_or_abort() {
    Some(d) => d.payload
    None => -1
  }
}

///|
test "bd: no prior, Ok → AcceptedChanged" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "r1a")
  let ad = @incr.AcceptedDerived::accepted_memo(rt, () => {
    ad_bd_parse(input.get())
  })
  inspect(ad_accepted_payload(ad), content="10")
  inspect(ad.snapshot_or_abort().status, content="AcceptedChanged")
}

///|
test "bd: same revision, different payload → AcceptedUnchanged, retains first doc" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "r1a")
  let ad = @incr.AcceptedDerived::accepted_memo(rt, () => {
    ad_bd_parse(input.get())
  })
  input.set("r1b") // same revision (1), payload 99 — but revision is the identity
  inspect(ad.snapshot_or_abort().status, content="AcceptedUnchanged")
  // The retained accepted value is the FIRST doc (payload 10), not 99: an equal
  // revision does not advance the accepted value.
  inspect(ad_accepted_payload(ad), content="10")
}

///|
test "bd: new revision → AcceptedChanged" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "r1a")
  let ad = @incr.AcceptedDerived::accepted_memo(rt, () => {
    ad_bd_parse(input.get())
  })
  input.set("r2")
  inspect(ad.snapshot_or_abort().status, content="AcceptedChanged")
  inspect(ad_accepted_payload(ad), content="20")
}

///|
test "bd: prior Some, Err → RetainedDueToError" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "r1a")
  let ad = @incr.AcceptedDerived::accepted_memo(rt, () => {
    ad_bd_parse(input.get())
  })
  input.set("e1a")
  inspect(ad.snapshot_or_abort().status, content="RetainedDueToError")
  inspect(ad_accepted_payload(ad), content="10")
  inspect(ad.current_or_abort() is Err("e1"), content="true")
}

///|
test "bd: transient success accepted without intervening read" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "e1a")
  let ad = @incr.AcceptedDerived::accepted_memo(rt, () => {
    ad_bd_parse(input.get())
  })
  input.set("r1a") // transient Ok: eager fold accepts it
  input.set("e1a") // Err: retained, with no accepted read in between
  inspect(ad.snapshot_or_abort().status, content="RetainedDueToError")
  inspect(ad_accepted_payload(ad), content="10")
}

///|
test "bd: changed_at advances only on revision change, not current-error churn" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "r1a")
  let ad = @incr.AcceptedDerived::accepted_memo(rt, () => {
    ad_bd_parse(input.get())
  })
  let r1 = ad.accepted_changed_at()
  input.set("e1a") // RetainedDueToError
  inspect(ad.accepted_changed_at() == r1, content="true")
  input.set("e2") // different error — still no accepted change
  inspect(ad.accepted_changed_at() == r1, content="true")
  input.set("r1b") // same revision success — no accepted change
  inspect(ad.accepted_changed_at() == r1, content="true")
  input.set("r2") // new revision — accepted advances
  inspect(ad.accepted_changed_at() == r1, content="false")
}

///|
test "bd: in-graph accepted consumer ignores current-error churn, re-runs on revision change" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "r1a")
  let ad = @incr.AcceptedDerived::accepted_memo(rt, () => {
    ad_bd_parse(input.get())
  })
  let runs = [0]
  let consumer = @incr.Derived::Derived(rt, () => {
    runs[0] = runs[0] + 1
    match ad.accepted_get() {
      Ok(Some(d)) => d.payload
      _ => -1
    }
  })
  let watch = consumer.watch()
  ignore(watch.read_or_abort())
  let base = runs[0]
  input.set("e1a") // current error: accepted retained → consumer must NOT re-run
  ignore(watch.read_or_abort())
  input.set("e2")
  ignore(watch.read_or_abort())
  input.set("r1b") // same revision: accepted retained → still no re-run
  ignore(watch.read_or_abort())
  inspect(runs[0] == base, content="true")
  input.set("r2") // new revision: accepted advances → consumer re-runs
  ignore(watch.read_or_abort())
  inspect(runs[0] > base, content="true")
  watch.dispose()
}

///|
test "bd: chain survives Runtime::gc()" {
  // The BackdateEq tier builds `accepted_cell` by hand (via `with_backdate` +
  // `add_cell_ids`), not `scope.derived`. This pins that the gc anchor still
  // keeps the chain (accepted_cell -> fold -> candidate) rooted across a gc.
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "r1a")
  let ad = @incr.AcceptedDerived::accepted_memo(rt, () => {
    ad_bd_parse(input.get())
  })
  inspect(ad_accepted_payload(ad), content="10")
  rt.gc()
  inspect(ad_accepted_payload(ad), content="10")
  input.set("r2")
  inspect(ad_accepted_payload(ad), content="20")
}

///|
test "bd: Scope::accepted_memo disposes with its parent scope" {
  let rt = @incr.Runtime::Runtime()
  let input = @incr.Input::Input(rt, "r1a")
  let scope = @incr.Scope::new(rt)
  let ad = scope.accepted_memo(() => ad_bd_parse(input.get()))
  inspect(ad_accepted_payload(ad), content="10")
  input.set("r2")
  inspect(ad_accepted_payload(ad), content="20")
  scope.dispose()
  inspect(ad.is_disposed(), content="true")
}
