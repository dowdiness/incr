// Stage-2 spike for `AcceptedDerived`.
//
// Validates the success-gated accept state machine and the eager-forcing
// requirement from docs/design/specs/2026-06-05-committed-derived.md BEFORE any
// public API exists. This is a test-local whitebox fixture, not a public facade:
// nothing here is exported and the `.mbti` interface is unchanged.
//
// Design choices proven here (deferred to the spike by the spec):
//   * The accept-advancing cell is an `EagerDerived` reading the candidate
//     `Derived[Result[V, E]]`. Push propagation traverses the pull candidate to
//     reach the eager cell, so the fold runs once per committed revision — even
//     when no consumer reads. This is the eager-forcing mechanism.
//   * The previous accepted value is held in a `Ref[V?]` captured by the eager
//     compute, OUTSIDE the reactive dependency graph. The fold reads and writes
//     it as retained state, so there is no derived self-dependency (no cycle).
//
// Out of spike scope (full surface, stage 3+): the `ReadError` channel, the
// `Watch`/gc-anchor ownership surface, and the equal-error current-channel
// backdate test. This spike pins the observable transition table + eager
// forcing only.

///|
/// Status of a single committed-revision transition through the accept gate.
/// Mirrors the spec's state-machine `Status` column.
enum AcceptStatus {
  NoAccept
  AcceptedChanged
  AcceptedUnchanged
  RetainedDueToError
} derive(Eq)

///|
impl Show for AcceptStatus with fn output(self, logger) {
  logger.write_string(
    match self {
      NoAccept => "NoAccept"
      AcceptedChanged => "AcceptedChanged"
      AcceptedUnchanged => "AcceptedUnchanged"
      RetainedDueToError => "RetainedDueToError"
    },
  )
}

///|
/// Test-local fixture for the `AcceptedDerived` state machine. Holds the
/// retained accepted value (`accepted_slot`) and the accept counter
/// (`accept_count`) OUTSIDE the reactive graph; `snapshot` is the eager
/// accept-advancing cell.
struct AcceptedSpike[V, E] {
  accepted_slot : Ref[V?]
  accept_count : Ref[Int]
  snapshot : EagerDerived[(Result[V, E], V?, AcceptStatus)]
}

///|
/// Builds the spike over an existing candidate stage. The fold runs eagerly:
/// `snapshot` is an `EagerDerived` whose only tracked dependency is `candidate`,
/// so push propagation re-runs it once per committed revision. The previous
/// accepted value lives in `accepted_slot` — a plain `Ref`, not a cell — so the
/// self-referencing fold does not form a derived cycle.
fn[V : Eq, E : Eq] AcceptedSpike::AcceptedSpike(
  rt : Runtime,
  candidate : Derived[Result[V, E]],
) -> AcceptedSpike[V, E] {
  let accepted_slot : Ref[V?] = { val: None }
  let accept_count : Ref[Int] = { val: 0 }
  let snapshot = EagerDerived::EagerDerived(rt, () => {
    let current = candidate.get_or_abort()
    let prev = accepted_slot.val
    let (new_accepted, status) = match (prev, current) {
      (None, Err(_)) => (None, NoAccept)
      (None, Ok(v)) => (Some(v), AcceptedChanged)
      (Some(old), Err(_)) => (Some(old), RetainedDueToError)
      (Some(old), Ok(v)) =>
        if v == old {
          (Some(old), AcceptedUnchanged)
        } else {
          (Some(v), AcceptedChanged)
        }
    }
    accepted_slot.val = new_accepted
    if status == AcceptedChanged {
      accept_count.val = accept_count.val + 1
    }
    (current, new_accepted, status)
  })
  { accepted_slot, accept_count, snapshot }
}

///|
/// Last accepted value, read straight from the retained slot. Because the eager
/// fold advances the slot per committed revision, this reflects the accepted
/// state with no read of the reactive graph.
fn[V, E] AcceptedSpike::accepted(self : AcceptedSpike[V, E]) -> V? {
  self.accepted_slot.val
}

///|
/// Current candidate result for the latest committed revision.
fn[V, E] AcceptedSpike::current(self : AcceptedSpike[V, E]) -> Result[V, E] {
  let (current, _, _) = self.snapshot.read()
  current
}

///|
/// Status of the latest committed-revision transition.
fn[V, E] AcceptedSpike::status(self : AcceptedSpike[V, E]) -> AcceptStatus {
  let (_, _, status) = self.snapshot.read()
  status
}

///|
/// Number of times the accepted value actually changed.
fn[V, E] AcceptedSpike::accept_count(self : AcceptedSpike[V, E]) -> Int {
  self.accept_count.val
}

///|
/// Domain parse used by the spike. Distinct sources map to controlled
/// `Result[Int, String]` outcomes so accepted-value equality can be reasoned by
/// hand: `"v1"` and `"v1b"` both parse to `Ok(1)` (same accepted value from
/// different sources), `"v2"` parses to `Ok(2)`, `"e1"` to `Err("e1")`, and
/// anything else to `Err("other")`.
fn spike_parse(s : String) -> Result[Int, String] {
  match s {
    "v1" => Ok(1)
    "v1b" => Ok(1)
    "v2" => Ok(2)
    "e1" => Err("e1")
    _ => Err("other")
  }
}

///|
/// Row 1 of the state machine: no prior accepted value, candidate `Err` →
/// accepted stays `None`, status `NoAccept`, current carries the error.
test "accepted spike: no prior, Err → NoAccept" {
  let rt = Runtime::Runtime()
  let input = Input::Input(rt, "e1")
  let candidate = Derived::fallible(rt, () => spike_parse(input.get()))
  let spike = AcceptedSpike::AcceptedSpike(rt, candidate)
  @debug.assert_eq(spike.accepted(), None)
  inspect(spike.status(), content="NoAccept")
  @debug.assert_eq(spike.current(), Err("e1"))
  @debug.assert_eq(spike.accept_count(), 0)
}

///|
/// Row 2 of the state machine: no prior accepted value, candidate `Ok(v)` →
/// first success creates `Some(v)`, status `AcceptedChanged`, count advances.
test "accepted spike: no prior, Ok → AcceptedChanged (first success)" {
  let rt = Runtime::Runtime()
  let input = Input::Input(rt, "v1")
  let candidate = Derived::fallible(rt, () => spike_parse(input.get()))
  let spike = AcceptedSpike::AcceptedSpike(rt, candidate)
  @debug.assert_eq(spike.accepted(), Some(1))
  inspect(spike.status(), content="AcceptedChanged")
  @debug.assert_eq(spike.current(), Ok(1))
  @debug.assert_eq(spike.accept_count(), 1)
}

///|
/// Row 3 of the state machine: prior accepted value exists, candidate `Err` →
/// retained value is preserved, status `RetainedDueToError`, current carries the
/// error, accept count does NOT advance.
test "accepted spike: prior Some, Err → RetainedDueToError" {
  let rt = Runtime::Runtime()
  let input = Input::Input(rt, "v1")
  let candidate = Derived::fallible(rt, () => spike_parse(input.get()))
  let spike = AcceptedSpike::AcceptedSpike(rt, candidate)
  input.set("e1")
  @debug.assert_eq(spike.accepted(), Some(1))
  inspect(spike.status(), content="RetainedDueToError")
  @debug.assert_eq(spike.current(), Err("e1"))
  @debug.assert_eq(spike.accept_count(), 1)
}

///|
/// Row 4 of the state machine: prior accepted value exists, candidate `Ok(v)`
/// with `v == old` → retained value unchanged, status `AcceptedUnchanged`,
/// accept count does NOT advance. Driven through `Err` so the candidate value
/// genuinely changes (`Err → Ok`) and the eager fold re-runs.
test "accepted spike: prior Some, equal Ok → AcceptedUnchanged" {
  let rt = Runtime::Runtime()
  let input = Input::Input(rt, "v1")
  let candidate = Derived::fallible(rt, () => spike_parse(input.get()))
  let spike = AcceptedSpike::AcceptedSpike(rt, candidate)
  input.set("e1") // RetainedDueToError, accepted stays Some(1)
  input.set("v1b") // Ok(1): equal to retained 1 → AcceptedUnchanged
  @debug.assert_eq(spike.accepted(), Some(1))
  inspect(spike.status(), content="AcceptedUnchanged")
  @debug.assert_eq(spike.current(), Ok(1))
  @debug.assert_eq(spike.accept_count(), 1)
}

///|
/// Backdated-candidate variant of Row 4. Two distinct sources (`"v1"`, `"v1b"`)
/// map to the SAME candidate value `Ok(1)`, so the intermediate pull candidate
/// memo BACKDATES (value unchanged, `changed_at` not advanced) — no `Err` step
/// forces a real candidate change. The eager fold must still run on this
/// committed revision and report `AcceptedUnchanged`; if push propagation skipped
/// the eager cell on a backdated pull dep, `status` would read the stale
/// `AcceptedChanged`. Confirms push enqueue is reachability-driven, not
/// `changed_at`-driven (`incr/cells/internal/kernel/push_propagate.mbt`).
test "accepted spike: backdated candidate still reports AcceptedUnchanged" {
  let rt = Runtime::Runtime()
  let input = Input::Input(rt, "v1")
  let candidate = Derived::fallible(rt, () => spike_parse(input.get()))
  let spike = AcceptedSpike::AcceptedSpike(rt, candidate)
  // v1 → v1b directly: candidate value is Ok(1) both times → candidate backdates.
  input.set("v1b")
  @debug.assert_eq(spike.accepted(), Some(1))
  inspect(spike.status(), content="AcceptedUnchanged")
  @debug.assert_eq(spike.current(), Ok(1))
  @debug.assert_eq(spike.accept_count(), 1)
}

///|
/// Row 5 of the state machine: prior accepted value exists, candidate `Ok(v)`
/// with `v != old` → retained value replaced with `v`, status
/// `AcceptedChanged`, accept count advances.
test "accepted spike: prior Some, changed Ok → AcceptedChanged" {
  let rt = Runtime::Runtime()
  let input = Input::Input(rt, "v1")
  let candidate = Derived::fallible(rt, () => spike_parse(input.get()))
  let spike = AcceptedSpike::AcceptedSpike(rt, candidate)
  input.set("v2") // Ok(2): differs from retained 1 → AcceptedChanged
  @debug.assert_eq(spike.accepted(), Some(2))
  inspect(spike.status(), content="AcceptedChanged")
  @debug.assert_eq(spike.current(), Ok(2))
  @debug.assert_eq(spike.accept_count(), 2)
}

///|
/// The load-bearing eager-forcing case. A transient successful candidate is
/// accepted even though NO consumer reads any channel between that success and a
/// later failure. With lazy pull-only evaluation the fold would never observe
/// the `Ok(1)` edit and `accepted` would wrongly remain `None`; the eager cell
/// runs per committed revision, so the slot advances to `Some(1)` with zero
/// intervening reads, and the later `Err` retains it.
test "accepted spike: transient success accepted without intervening read" {
  let rt = Runtime::Runtime()
  let input = Input::Input(rt, "e1")
  let candidate = Derived::fallible(rt, () => spike_parse(input.get()))
  let spike = AcceptedSpike::AcceptedSpike(rt, candidate)
  // No reads below until the final assertions.
  input.set("v1") // transient Ok(1): eager fold accepts Some(1)
  input.set("e1") // Err: RetainedDueToError keeps Some(1)
  @debug.assert_eq(spike.accepted(), Some(1))
  inspect(spike.status(), content="RetainedDueToError")
  @debug.assert_eq(spike.current(), Err("e1"))
  @debug.assert_eq(spike.accept_count(), 1)
}
