// White-box tests for `AcceptedDerived` cases that require internal access. The
// public-API behavior (state-machine rows, changed_at gating, gc/batch,
// constructors) is covered black-box in incr/tests/accepted_derived_test.mbt;
// only the two cases below need to reach internals:
//   * wake-counting the CURRENT channel (`ad.candidate`) to prove an equal error
//     backdates it (no in-graph current handle is exposed publicly);
//   * simulating a Disposed candidate read (`ad.candidate.dispose()`) and
//     asserting the retained slot/status (`ad.accepted_slot`/`ad.last_status`)
//     are untouched.

///|
fn ad_parse(s : String) -> Result[Int, String] {
  match s {
    "v1" => Ok(1)
    "v2" => Ok(2)
    "e1a" => Err("e1")
    "e1b" => Err("e1")
    "e2" => Err("e2")
    _ => Err("other")
  }
}

///|
/// Entry criterion #1: an equal error from a distinct source backdates the
/// current channel, so current observers are not woken and the accept revision
/// does not advance. Wake-counted via a pull probe on the internal candidate.
test "accepted: equal error backdates current channel (observers not woken)" {
  let rt = Runtime::Runtime()
  let input = Input::Input(rt, "e1a")
  let ad = AcceptedDerived::AcceptedDerived(rt, () => ad_parse(input.get()))
  let cur_runs : Ref[Int] = { val: 0 }
  let cur_probe = Derived::Derived(rt, () => {
    cur_runs.val = cur_runs.val + 1
    ignore(ad.candidate.get_or_abort())
    0
  })
  let cur_watch = cur_probe.watch()
  ignore(cur_watch.read_or_abort())
  let base_runs = cur_runs.val
  let base_rev = ad.accepted_changed_at()
  // Equal error, distinct source: candidate value Err("e1") unchanged → backdates.
  input.set("e1b")
  ignore(cur_watch.read_or_abort())
  inspect(cur_runs.val == base_runs, content="true")
  inspect(ad.accepted_changed_at() == base_rev, content="true")
  // Positive control: a genuinely different error DOES wake the current channel.
  input.set("e2")
  ignore(cur_watch.read_or_abort())
  inspect(cur_runs.val > base_runs, content="true")
  cur_watch.dispose()
}

///|
/// Entry criterion #2: a candidate ReadError (Disposed) must NOT drive the state
/// machine — accessors surface the error honestly while the retained accepted
/// value and status are left untouched. (Transient `Err(Cycle)` resume is
/// structurally unreachable in this engine; see the module header note.)
test "accepted: disposed candidate surfaces ReadError, retains accepted state" {
  let rt = Runtime::Runtime()
  let input = Input::Input(rt, "v1")
  let ad = AcceptedDerived::AcceptedDerived(rt, () => ad_parse(input.get()))
  @debug.assert_eq(ad.accepted_or_abort(), Some(1))
  ad.candidate.dispose()
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
  // Retained acceptance state is untouched by the read error.
  @debug.assert_eq(ad.accepted_slot.val, Some(1))
  inspect(ad.last_status.val, content="AcceptedChanged")
}
