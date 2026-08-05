///|
priv type RcProbeToken

///|
extern "C" fn rc_probe_token_new(kind : Int) -> RcProbeToken = "incr_rc_probe_token_new"

///|
#borrow(token)
extern "C" fn rc_probe_token_touch(token : RcProbeToken) -> Unit = "incr_rc_probe_token_touch"

///|
extern "C" fn rc_probe_live_count(kind : Int) -> Int = "incr_rc_probe_live_count"

///|
extern "C" fn rc_probe_finalized_count(kind : Int) -> Int = "incr_rc_probe_finalized_count"

///|
let batch_size : Int = 32

///|
let passive_chain_kind : Int = 0

///|
let passive_diamond_kind : Int = 1

///|
let effect_stop_kind : Int = 2

///|
let effect_close_kind : Int = 3

///|
let listener_kind : Int = 4

///|
let deferred_flush_kind : Int = 5

///|
let deferred_close_kind : Int = 6

///|
let keyed_kind : Int = 7

///|
let compute_cycle_kind : Int = 8

///|
let cache_cycle_kind : Int = 9

///|
let two_view_cycle_kind : Int = 10

///|
priv struct Observation {
  label : String
  live_before_break : Int
  expected_before_break : Int
  live_after_break : Int
  expected_after_break : Int
  finalized : Int
  expected_finalized : Int
}

///|
priv struct CachedPayload {
  marker : Int
  token : RcProbeToken
  views : Array[@skeleton.View[CachedPayload]]
}

///|
fn CachedPayload::CachedPayload(
  marker : Int,
  token : RcProbeToken,
  views : Array[@skeleton.View[CachedPayload]],
) -> CachedPayload {
  { marker, token, views }
}

///|
impl Eq for CachedPayload with fn equal(self, other) -> Bool {
  self.marker == other.marker
}

///|
fn retain_token(token : RcProbeToken) -> () -> Unit {
  () => rc_probe_token_touch(token)
}

///|
fn allocate_passive_chain() -> Int {
  let store = @skeleton.Store()
  let retainers = Array::makei(batch_size, _ => {
    retain_token(rc_probe_token_new(passive_chain_kind))
  })
  let root = store.probe_passive_chain(retainers)
  let before_drop = rc_probe_live_count(passive_chain_kind)
  ignore(root())
  before_drop
}

///|
fn allocate_passive_diamonds() -> Int {
  let store = @skeleton.Store()
  let roots = Array::makei(batch_size, _ => {
    store.probe_passive_diamond(
      retain_token(rc_probe_token_new(passive_diamond_kind)),
      retain_token(rc_probe_token_new(passive_diamond_kind)),
      retain_token(rc_probe_token_new(passive_diamond_kind)),
      retain_token(rc_probe_token_new(passive_diamond_kind)),
    )
  })
  let before_drop = rc_probe_live_count(passive_diamond_kind)
  roots.each(root => ignore(root()))
  before_drop
}

///|
fn exercise_effect_breakers() -> (Int, Int) {
  let store = @skeleton.Store()
  let stops = Array::makei(batch_size, i => {
    let token = rc_probe_token_new(effect_stop_kind)
    let view = store.derived(() => {
      rc_probe_token_touch(token)
      i
    })
    store.mount(() => ignore(view()))
  })
  let before = rc_probe_live_count(effect_stop_kind)
  stops.each(stop => stop.stop())
  stops.clear()
  let after = rc_probe_live_count(effect_stop_kind)
  (before, after)
}

///|
fn exercise_effect_close() -> (Int, Int) {
  let store = @skeleton.Store()
  ignore(
    Array::makei(batch_size, i => {
      let token = rc_probe_token_new(effect_close_kind)
      let view = store.derived(() => {
        rc_probe_token_touch(token)
        i
      })
      ignore(store.mount(() => ignore(view())))
    }),
  )
  let before = rc_probe_live_count(effect_close_kind)
  store.close()
  let after = rc_probe_live_count(effect_close_kind)
  (before, after)
}

///|
fn exercise_combined_breakers() -> (Int, Int, Int, Int) {
  let store = @skeleton.Store()
  let listener_tokens = Array::makei(batch_size, i => {
    let token = rc_probe_token_new(listener_kind)
    let view = store.derived(() => {
      rc_probe_token_touch(token)
      i
    })
    store.listen(() => ignore(view()))
  })
  ignore(
    Array::makei(batch_size, i => {
      let token = rc_probe_token_new(deferred_flush_kind)
      let (_, write) = store.input(i)
      store.enqueue_deferred(() => {
        rc_probe_token_touch(token)
        write.set(i + 1)
      })
    }),
  )
  let listener_before = rc_probe_live_count(listener_kind)
  let deferred_before = rc_probe_live_count(deferred_flush_kind)
  listener_tokens.each(token => token.remove())
  listener_tokens.clear()
  let listener_after = rc_probe_live_count(listener_kind)
  store.flush()
  let deferred_after = rc_probe_live_count(deferred_flush_kind)
  store.close()
  (listener_before, listener_after, deferred_before, deferred_after)
}

///|
fn exercise_deferred_close() -> (Int, Int) {
  let store = @skeleton.Store()
  ignore(
    Array::makei(batch_size, i => {
      let token = rc_probe_token_new(deferred_close_kind)
      let (_, write) = store.input(i)
      store.enqueue_deferred(() => {
        rc_probe_token_touch(token)
        write.set(i + 1)
      })
    }),
  )
  let before = rc_probe_live_count(deferred_close_kind)
  store.close()
  let after = rc_probe_live_count(deferred_close_kind)
  (before, after)
}

///|
fn exercise_keyed_survivors() -> (Int, Int) {
  let store = @skeleton.Store()
  let surviving_getters = Array::makei(batch_size, i => {
    let token = rc_probe_token_new(keyed_kind)
    let view = store.derived(() => {
      rc_probe_token_touch(token)
      i
    })
    let getter = @skeleton.retire_keyed_for_probe(view)
    ignore(getter())
    getter
  })
  let while_getters_survive = rc_probe_live_count(keyed_kind)
  surviving_getters.clear()
  let after_getters_drop = rc_probe_live_count(keyed_kind)
  (while_getters_survive, after_getters_drop)
}

///|
fn leak_compute_cycles() -> Int {
  ignore(
    Array::makei(batch_size, i => {
      let store = @skeleton.Store()
      let holder : Ref[@skeleton.View[Int]?] = Ref(None)
      let token = rc_probe_token_new(compute_cycle_kind)
      let view = store.derived(() => {
        rc_probe_token_touch(token)
        ignore(holder.val)
        i
      })
      holder.val = Some(view)
    }),
  )
  rc_probe_live_count(compute_cycle_kind)
}

///|
fn leak_cached_value_cycles() -> Int {
  ignore(
    Array::makei(batch_size, i => {
      let store = @skeleton.Store()
      let view = store.derived(() => {
        CachedPayload(i, rc_probe_token_new(cache_cycle_kind), [])
      })
      let payload = view()
      rc_probe_token_touch(payload.token)
      payload.views.push(view)
    }),
  )
  rc_probe_live_count(cache_cycle_kind)
}

///|
fn leak_two_view_cycles() -> Int {
  ignore(
    Array::makei(batch_size, i => {
      let store = @skeleton.Store()
      let a_holder : Ref[@skeleton.View[Int]?] = Ref(None)
      let b_holder : Ref[@skeleton.View[Int]?] = Ref(None)
      let a_token = rc_probe_token_new(two_view_cycle_kind)
      let b_token = rc_probe_token_new(two_view_cycle_kind)
      let a = store.derived(() => {
        rc_probe_token_touch(a_token)
        ignore(b_holder.val)
        i
      })
      let b = store.derived(() => {
        rc_probe_token_touch(b_token)
        ignore(a_holder.val)
        i + 1
      })
      a_holder.val = Some(a)
      b_holder.val = Some(b)
    }),
  )
  rc_probe_live_count(two_view_cycle_kind)
}

///|
fn Observation::passed(self : Observation) -> Bool {
  self.live_before_break == self.expected_before_break &&
  self.live_after_break == self.expected_after_break &&
  self.finalized == self.expected_finalized
}

///|
fn Observation::print(self : Observation) -> Unit {
  println(self.label)
  println("  live before break/drop: \{self.live_before_break}")
  println("  expected before:        \{self.expected_before_break}")
  println("  live after break/drop:  \{self.live_after_break}")
  println("  expected after:         \{self.expected_after_break}")
  println("  finalized:              \{self.finalized}")
  println("  expected finalized:     \{self.expected_finalized}")
  println("  pass:                   \{self.passed()}")
}

///|
fn main {
  let chain_before_drop = allocate_passive_chain()
  let chain_after_drop = rc_probe_live_count(passive_chain_kind)
  let diamond_before_drop = allocate_passive_diamonds()
  let diamond_after_drop = rc_probe_live_count(passive_diamond_kind)
  let (effect_stop_before, effect_stop_after) = exercise_effect_breakers()
  let (effect_close_before, effect_close_after) = exercise_effect_close()
  let (listener_before, listener_after, deferred_before, deferred_after) = exercise_combined_breakers()
  let (deferred_close_before, deferred_close_after) = exercise_deferred_close()
  let (keyed_before, keyed_after) = exercise_keyed_survivors()
  let compute_cycles = leak_compute_cycles()
  let cache_cycles = leak_cached_value_cycles()
  let two_view_cycles = leak_two_view_cycles()

  let observations : Array[Observation] = [
    {
      label: "passive acyclic chain",
      live_before_break: chain_before_drop,
      expected_before_break: batch_size,
      live_after_break: chain_after_drop,
      expected_after_break: 0,
      finalized: rc_probe_finalized_count(passive_chain_kind),
      expected_finalized: batch_size,
    },
    {
      label: "passive acyclic diamonds",
      live_before_break: diamond_before_drop,
      expected_before_break: batch_size * 4,
      live_after_break: diamond_after_drop,
      expected_after_break: 0,
      finalized: rc_probe_finalized_count(passive_diamond_kind),
      expected_finalized: batch_size * 4,
    },
    {
      label: "mounted Effect SCC after Stop",
      live_before_break: effect_stop_before,
      expected_before_break: batch_size,
      live_after_break: effect_stop_after,
      expected_after_break: 0,
      finalized: rc_probe_finalized_count(effect_stop_kind),
      expected_finalized: batch_size,
    },
    {
      label: "mounted Effect SCC after Store.close",
      live_before_break: effect_close_before,
      expected_before_break: batch_size,
      live_after_break: effect_close_after,
      expected_after_break: 0,
      finalized: rc_probe_finalized_count(effect_close_kind),
      expected_finalized: batch_size,
    },
    {
      label: "listener SCC after token removal",
      live_before_break: listener_before,
      expected_before_break: batch_size,
      live_after_break: listener_after,
      expected_after_break: 0,
      finalized: rc_probe_finalized_count(listener_kind),
      expected_finalized: batch_size,
    },
    {
      label: "deferred-write SCC after flush",
      live_before_break: deferred_before,
      expected_before_break: batch_size,
      live_after_break: deferred_after,
      expected_after_break: 0,
      finalized: rc_probe_finalized_count(deferred_flush_kind),
      expected_finalized: batch_size,
    },
    {
      label: "pending deferred writes after Store.close",
      live_before_break: deferred_close_before,
      expected_before_break: batch_size,
      live_after_break: deferred_close_after,
      expected_after_break: 0,
      finalized: rc_probe_finalized_count(deferred_close_kind),
      expected_finalized: batch_size,
    },
    {
      label: "keyed entry after surviving getter drop",
      live_before_break: keyed_before,
      expected_before_break: batch_size,
      live_after_break: keyed_after,
      expected_after_break: 0,
      finalized: rc_probe_finalized_count(keyed_kind),
      expected_finalized: batch_size,
    },
    {
      label: "opaque late-bound compute cycles",
      live_before_break: compute_cycles,
      expected_before_break: batch_size,
      live_after_break: compute_cycles,
      expected_after_break: batch_size,
      finalized: rc_probe_finalized_count(compute_cycle_kind),
      expected_finalized: 0,
    },
    {
      label: "opaque cached owning-collection cycles",
      live_before_break: cache_cycles,
      expected_before_break: batch_size,
      live_after_break: cache_cycles,
      expected_after_break: batch_size,
      finalized: rc_probe_finalized_count(cache_cycle_kind),
      expected_finalized: 0,
    },
    {
      label: "opaque two-View cycles",
      live_before_break: two_view_cycles,
      expected_before_break: batch_size * 2,
      live_after_break: two_view_cycles,
      expected_after_break: batch_size * 2,
      finalized: rc_probe_finalized_count(two_view_cycle_kind),
      expected_finalized: 0,
    },
  ]

  println("OWNERSHIP NATIVE RC — THROWAWAY PROBE")
  println("batch size: \{batch_size}")
  observations.each(observation => observation.print())
  let passed = observations.all(observation => observation.passed())
  println("overall verdict: \{if passed { "PASS" } else { "FAIL" }}")
  if !passed {
    abort("native RC observations did not match the ownership argument")
  }
}
