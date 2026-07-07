///|
fn prop_revision_next_strictly_increases(steps : Int) -> Bool {
  let mut r = Revision::initial()
  for _ in 0..<steps {
    let next = r.next()
    if !(r < next) {
      return false
    }
    if r == next {
      return false
    }
    r = next
  }
  true
}

///|
fn prop_revision_value_tracks_steps(steps : Int) -> Bool {
  let mut r = Revision::initial()
  for _ in 0..<steps {
    r = r.next()
  }
  r.value == steps
}

///|
test "revision quickcheck: next strictly increases" {
  let steps_gen = @gen.int_range(0, 32)
  let prop = @qc.forall(steps_gen, prop_revision_next_strictly_increases)
  @qc.quick_check(prop, max_success=100)
}

///|
test "revision quickcheck: value tracks step count from initial" {
  let steps_gen = @gen.int_range(0, 32)
  let prop = @qc.forall(steps_gen, prop_revision_value_tracks_steps)
  @qc.quick_check(prop, max_success=100)
}
