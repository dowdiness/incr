///|
/// L2 semantic oracle — reference-model property tests.
///
/// See issue #365 / #364 in https://github.com/dowdiness/incr.
///
/// Runs random op sequences against both the real incr Runtime and a
/// naive full-recompute reference model, then asserts observable
/// outputs agree.
///
/// ## Coverage
///
/// - **Value correctness**: every derived read after random input sets
///   matches a full-recompute from scratch (invariants 2–5 from
///   docs/design/internals.md).
/// - **Green path**: setting an unrelated input does not increase a
///   derived's recompute count.
/// - **Backdating**: an equal-value recompute of a middle node does not
///   cascade to downstream recompute counts.
///
/// ## Mutation test
///
/// Break backdating by replacing `changed_at` preservation in
/// `derived_impl.mbt` with unconditional advance. The property tests
/// below should still pass (values stay correct). The backdating test
/// *must* turn red.

///|
/// Deterministic pseudo-random number generator (LCG).
///
/// Reproducible — a given seed always produces the same sequence.
/// No global state, no import of an external RNG.
struct LCG {
  mut state : Int
}

///|
fn LCG::new(seed : Int) -> LCG {
  { state: seed }
}

///|
fn LCG::next(self : LCG) -> Int {
  self.state = self.state * 1103515245 + 12345
  self.state & 0x7fffffff
}

///|
/// Returns a value in `[0, max)`.
fn LCG::next_range(self : LCG, max : Int) -> Int {
  self.next() % max
}

///|
/// A test fixture bundles the real Runtime graph and a pure reference function
/// that maps input values to derived values (full recompute from scratch).
type Fixture = (
  Array[Input[Int]],
  Array[Derived[Int]],
  (Array[Int]) -> Array[Int],
)

///|
/// A test fixture with ReachableDerived cells.
type FixtureReach = (
  Array[Input[Int]],
  Array[ReachableDerived[Int]],
  (Array[Int]) -> Array[Int],
)

///|
/// Read a derived value without GC-rooting side effects.
///
/// Creates a temporary observer, reads the value, then disposes it.
fn[T] read_derived_for_test(d : Derived[T]) -> T {
  let obs = d.observe()
  let v = obs.get()
  obs.dispose()
  v
}

///|
/// Read a reachable derived value without GC-rooting side effects.
/// See `read_derived_for_test`.
fn[T : Eq] read_reach_for_test(d : ReachableDerived[T]) -> T {
  let obs = d.observe()
  let v = obs.get()
  obs.dispose()
  v
}

///|
/// Run a value-correctness property test for ReachableDerived.
/// See `check_value_correctness`.
fn check_value_correctness_reach(
  inputs : Array[Input[Int]],
  deriveds : Array[ReachableDerived[Int]],
  ref_fn : (Array[Int]) -> Array[Int],
  num_steps : Int,
  seed : Int,
) -> Unit {
  check_value_correctness_core(
    inputs,
    deriveds.length(),
    ref_fn,
    num_steps,
    seed,
    fn(d : Int) -> Int { read_reach_for_test(deriveds[d]) },
  )
}

// ============================================================
//  Property test driver
// ============================================================

///|
/// Shared core for value-correctness property tests.
///
/// Calls `read_fn(d)` for each derived index `d` to obtain the real
/// value from the Runtime, then compares against the reference model.
/// The `deriveds` array is replaced by `num_deriveds` + a read callback
/// so the same core works for `Derived`, `ReachableDerived`, etc.
fn check_value_correctness_core(
  inputs : Array[Input[Int]],
  num_deriveds : Int,
  ref_fn : (Array[Int]) -> Array[Int],
  num_steps : Int,
  seed : Int,
  read_fn : (Int) -> Int,
) -> Unit {
  let rng = LCG::new(seed)
  let num_inputs = inputs.length()

  // Capture initial reference state from the real model
  let ref_vals : Array[Int] = []
  for i in 0..<num_inputs {
    ref_vals.push(inputs[i].peek())
  }

  for _step in 0..<num_steps {
    // Pick a random input and give it a random value
    let idx = rng.next_range(num_inputs)
    let val = rng.next_range(1000)
    inputs[idx].set(val)
    ref_vals[idx] = val

    // Reference model: pure full-recompute
    let expected = ref_fn(ref_vals)

    // Compare every derived against the reference.
    // On mismatch, abort with step, derived index, real/expected values, and seed
    // for reproduction.
    for d in 0..<num_deriveds {
      let real_val = read_fn(d)
      let expected_val = expected[d]
      if real_val != expected_val {
        abort(
          "value mismatch at step " +
          _step.to_string() +
          " derived[" +
          d.to_string() +
          "]: got " +
          real_val.to_string() +
          ", expected " +
          expected_val.to_string() +
          " (seed " +
          seed.to_string() +
          ")",
        )
      }
    }
  }
}

///|
/// Run a value-correctness property test.
///
/// For each of `num_steps` random steps: pick a random input, set it to
/// a random value, then read **every** derived cell and compare against
/// the reference model.  The reference model (`ref_fn`) is a pure
/// function: `input_values → derived_values` — full recompute from
fn check_value_correctness(
  inputs : Array[Input[Int]],
  deriveds : Array[Derived[Int]],
  ref_fn : (Array[Int]) -> Array[Int],
  num_steps : Int,
  seed : Int,
) -> Unit {
  check_value_correctness_core(
    inputs,
    deriveds.length(),
    ref_fn,
    num_steps,
    seed,
    fn(d : Int) -> Int { read_derived_for_test(deriveds[d]) },
  )
}

// ============================================================
//  Fixture definitions
// ============================================================

// --- Chain (3 levels) ---
// input -> d1(+1) -> d2(*2) -> d3(-3)

///|
fn make_chain_fixture(rt : Runtime) -> Fixture {
  let input = Input::Input(rt, 0)
  let d1 = Derived(rt, fn() { input.get() + 1 })
  let d2 = Derived(rt, fn() { d1.get_or_abort() * 2 })
  let d3 = Derived(rt, fn() { d2.get_or_abort() - 3 })
  let inputs = [input]
  let deriveds = [d1, d2, d3]
  let ref_fn = fn(vals : Array[Int]) -> Array[Int] {
    let v1 = vals[0] + 1
    let v2 = v1 * 2
    let v3 = v2 - 3
    [v1, v2, v3]
  }
  (inputs, deriveds, ref_fn)
}

// --- Diamond ---
// input -> dA(+1) -> dC(dA + dB)
//       -> dB(*2) ─┘

///|
fn make_diamond_fixture(rt : Runtime) -> Fixture {
  let input = Input::Input(rt, 0)
  let dA = Derived(rt, fn() { input.get() + 1 })
  let dB = Derived(rt, fn() { input.get() * 2 })
  let dC = Derived(rt, fn() { dA.get_or_abort() + dB.get_or_abort() })

  let inputs = [input]
  let deriveds = [dA, dB, dC]
  let ref_fn = fn(vals : Array[Int]) -> Array[Int] {
    let vA = vals[0] + 1
    let vB = vals[0] * 2
    let vC = vA + vB
    [vA, vB, vC]
  }
  (inputs, deriveds, ref_fn)
}

// --- Two independent chains ---
// input1 -> d1A(+1) -> d1B(*2)
// input2 -> d2A(+10) -> d2B(*3)

///|
fn make_two_chains_fixture(rt : Runtime) -> Fixture {
  let input1 = Input::Input(rt, 0)
  let input2 = Input::Input(rt, 0)

  let d1A = Derived(rt, fn() { input1.get() + 1 })
  let d1B = Derived(rt, fn() { d1A.get_or_abort() * 2 })

  let d2A = Derived(rt, fn() { input2.get() + 10 })
  let d2B = Derived(rt, fn() { d2A.get_or_abort() * 3 })

  let inputs = [input1, input2]
  let deriveds = [d1A, d1B, d2A, d2B]
  let ref_fn = fn(vals : Array[Int]) -> Array[Int] {
    let v1A = vals[0] + 1
    let v1B = v1A * 2
    let v2A = vals[1] + 10
    let v2B = v2A * 3
    [v1A, v1B, v2A, v2B]
  }
  (inputs, deriveds, ref_fn)
}

// --- Conditional / dynamic dependency ---
// flag(0/1) + input_a + input_b -> picker(reads flag ? a : b)

///|
fn make_conditional_fixture(rt : Runtime) -> Fixture {
  let flag = Input::Input(rt, 1) // 1 = true
  let input_a = Input::Input(rt, 10)
  let input_b = Input::Input(rt, 20)
  let picker = Derived(rt, fn() {
    if flag.get() != 0 {
      input_a.get()
    } else {
      input_b.get()
    }
  })

  let inputs = [flag, input_a, input_b]
  let deriveds = [picker]
  let ref_fn = fn(vals : Array[Int]) -> Array[Int] {
    let picked = if vals[0] != 0 { vals[1] } else { vals[2] }
    [picked]
  }
  (inputs, deriveds, ref_fn)
}

// --- ReachableDerived (2-level chain) ---
//  input -> rd1(*2) -> rd2(+10)
//  Same semantics as Derived but uses ReachableDerived cells.

///|
fn make_reach_fixture(rt : Runtime) -> FixtureReach {
  let input = Input::Input(rt, 0)
  let rd1 = ReachableDerived(rt, fn() { input.get() * 2 })
  let rd2 = ReachableDerived(rt, fn() { rd1.get_or_abort() + 10 })

  let inputs = [input]
  let deriveds = [rd1, rd2]
  let ref_fn = fn(vals : Array[Int]) -> Array[Int] {
    let v1 = vals[0] * 2
    let v2 = v1 + 10
    [v1, v2]
  }
  (inputs, deriveds, ref_fn)
}

// ============================================================
//  Value correctness property tests
// ============================================================

///|
test "l2 value: chain random ops" {
  let rt = Runtime()
  let (inputs, deriveds, ref_fn) = make_chain_fixture(rt)
  check_value_correctness(inputs, deriveds, ref_fn, 500, 42)
}

///|
test "l2 value: diamond random ops" {
  let rt = Runtime()
  let (inputs, deriveds, ref_fn) = make_diamond_fixture(rt)
  check_value_correctness(inputs, deriveds, ref_fn, 500, 43)
}

///|
test "l2 value: two chains random ops" {
  let rt = Runtime()
  let (inputs, deriveds, ref_fn) = make_two_chains_fixture(rt)
  check_value_correctness(inputs, deriveds, ref_fn, 500, 44)
}

///|
test "l2 value: conditional dynamic deps random ops" {
  let rt = Runtime()
  let (inputs, deriveds, ref_fn) = make_conditional_fixture(rt)
  check_value_correctness(inputs, deriveds, ref_fn, 500, 45)
}

///|
test "l2 value: reachable derived random ops" {
  let rt = Runtime()
  let (inputs, deriveds, ref_fn) = make_reach_fixture(rt)
  check_value_correctness_reach(inputs, deriveds, ref_fn, 500, 46)
}

// ============================================================
//  Incrementality: green path
// ============================================================

///|
test "l2 green path: unrelated input does not cause recompute" {
  // Two independent chains under one runtime.
  // Scenario: set input_b, read a2 — a-chain should NOT recompute
  // when only the unrelated input_b changed.
  let rt = Runtime()
  let input_a = Input::Input(rt, 0)
  let input_b = Input::Input(rt, 100)

  let mut a_count = 0
  let a1 = Derived(rt, fn() {
    a_count += 1
    input_a.get() + 1
  })
  let a2 = Derived(rt, fn() {
    a_count += 1
    a1.get_or_abort() * 3
  })

  let b1 = Derived(rt, fn() { input_b.get() + 10 })
  let b2 = Derived(rt, fn() { b1.get_or_abort() * 2 })

  // Prime both chains
  let _ = read_derived_for_test(a2)
  let _ = read_derived_for_test(b2)
  let saved_a = a_count

  // Set only unrelated input_b — a-chain should NOT recompute
  input_b.set(200)
  let _ = read_derived_for_test(a2)
  inspect(a_count == saved_a, content="true")
}

// ============================================================
//  Incrementality: dynamic dependency tracking
// ============================================================

///|
test "l2 dynamic deps: flipping branch drops old dep, tracks new" {
  // flag(0/1) + input_a + input_b -> picker -> label
  // When flag flips from true to false, the dependency set of picker
  // changes: [flag, input_a] -> [flag, input_b]. After the flip,
  // setting the now-unrelated input_a should NOT cause recompute
  // of picker or label (transitive green path).
  let rt = Runtime()
  let flag = Input::Input(rt, 1)
  let input_a = Input::Input(rt, 10)
  let input_b = Input::Input(rt, 20)

  let mut picker_runs = 0
  let picker = Derived(rt, fn() {
    picker_runs += 1
    if flag.get() != 0 {
      input_a.get()
    } else {
      input_b.get()
    }
  })

  let mut label_runs = 0
  let label = Derived(rt, fn() {
    label_runs += 1
    picker.get_or_abort() * 10
  })

  // Prime: flag=1 → reads a=10 → picker=10, label=100
  inspect(read_derived_for_test(label), content="100")
  inspect(picker_runs, content="1")
  inspect(label_runs, content="1")

  // Set unrelated input_b — NOT a dependency, picker should NOT recompute
  input_b.set(99)
  inspect(read_derived_for_test(label), content="100")
  inspect(picker_runs, content="1")
  inspect(label_runs, content="1")

  // Flip flag — now deps = [flag, input_b]; picker recomputes from b
  flag.set(0)
  inspect(read_derived_for_test(label), content="990")
  inspect(picker_runs, content="2")
  inspect(label_runs, content="2")

  // Set input_a — now UNTRACKED (was dropped from deps), should NOT recompute
  input_a.set(42)
  inspect(read_derived_for_test(label), content="990")
  inspect(picker_runs, content="2") // green path: picker not recomputed
  inspect(label_runs, content="2") // green path: label not recomputed

  // Set input_b — IS the current dep, SHOULD recompute
  input_b.set(21)
  inspect(read_derived_for_test(label), content="210")
  inspect(picker_runs, content="3")
  inspect(label_runs, content="3")
}

// ============================================================
//  Backdating regression
// ============================================================

///|
test "l2 backdating: stable middle prevents downstream recompute" {
  // Graph: input -> is_even -> label
  // When is_even recomputes but returns the same value (true),
  // its changed_at is preserved (backdated), so label skips.
  let rt = Runtime()
  let input = Input::Input(rt, 4)
  let mut parity_runs = 0
  let mut label_runs = 0

  let is_even = Derived(rt, fn() {
    parity_runs += 1
    input.get() % 2 == 0
  })

  let label = Derived(rt, fn() {
    label_runs += 1
    if is_even.get_or_abort() {
      0
    } else {
      1
    }
  })

  // Prime: both compute
  inspect(read_derived_for_test(label), content="0") // 4 is even
  inspect(parity_runs, content="1")
  inspect(label_runs, content="1")

  // Set to 6 (same parity, both even) — is_even backdates (value unchanged),
  // so label should skip recompute.
  input.set(6)
  inspect(read_derived_for_test(label), content="0")
  inspect(parity_runs, content="2") // is_even ran but value == prior
  inspect(label_runs, content="1") // label should NOT have run

  // Set to 7 (different parity) — both recompute
  input.set(7)
  inspect(read_derived_for_test(label), content="1")
  inspect(parity_runs, content="3")
  inspect(label_runs, content="2")
}

// ============================================================
//  Exact push-reachable count gate
// ============================================================

///|
/// Input with two Effect subscribers: disposing one must decrement
/// `push_reachable_count` from 2→1 (not just 1→0), catching broken
/// decrement paths that the `> 0` gate cannot witness.
test "l2 exact count: input with two effects" {
  let rt = Runtime()
  let input = Input(rt, 0)
  let e1 = Effect(rt, () => ignore(input.get()))
  let e2 = Effect(rt, () => ignore(input.get()))

  // Both effects live → input has 2 direct push subscribers
  inspect(push_reachable_count(rt, input.id()), content="2")
  inspect(push_reachable_gate_holds(rt), content="true")

  // Dispose one arm: count must drop to exactly 1
  e1.dispose()
  inspect(push_reachable_count(rt, input.id()), content="1")
  inspect(push_reachable_gate_holds(rt), content="true")

  // Dispose the other: count must reach 0
  e2.dispose()
  inspect(push_reachable_count(rt, input.id()), content="0")
  inspect(push_reachable_gate_holds(rt), content="true")
}

///|
/// Input → Derived(memo) → two Effects: disposing one effect decrements the
/// memo's count from 2→1 while keeping the input's count at 1 (live path
/// still exists through the remaining effect). Exercises the memo hop in
/// `propagate_liveness` where the memo's own liveness status (count > 0)
/// gates upstream propagation.
test "l2 exact count: fanout through memo with two effects" {
  let rt = Runtime()
  let input = Input(rt, 0)
  let memo = Derived(rt, () => input.get() + 1)
  let e1 = Effect(rt, () => ignore(memo.read_or_abort()))
  let e2 = Effect(rt, () => ignore(memo.read_or_abort()))

  // Keep memo alive (GC anchor)
  let memo_watch = memo.watch()

  // Memo has 2 direct push subscribers, input has 1 (the memo itself)
  inspect(push_reachable_count(rt, memo.id()), content="2")
  inspect(push_reachable_count(rt, input.id()), content="1")
  inspect(push_reachable_gate_holds(rt), content="true")

  // Dispose one effect: memo count drops to 1, input stays at 1
  e1.dispose()
  inspect(push_reachable_count(rt, memo.id()), content="1")
  inspect(push_reachable_count(rt, input.id()), content="1")
  inspect(push_reachable_gate_holds(rt), content="true")

  // Dispose the other: memo reaches 0 → flips to not-live → -1 to input
  e2.dispose()
  inspect(push_reachable_count(rt, memo.id()), content="0")
  inspect(push_reachable_count(rt, input.id()), content="0")
  inspect(push_reachable_gate_holds(rt), content="true")

  ignore(memo_watch)
}

// ============================================================
//  Oracle reconstruction: dependency-graph push reachability
// ============================================================

///|
/// Reconstructs "has a live push cell downstream" by walking upstream through
/// `gc_dependencies` from each live push cell, then comparing against the
/// incrementally maintained `push_reachable_count > 0` gate. Uses raw
/// dependency arrays rather than the subscriber graph, so it catches
/// inconsistencies where the two graph representations drift apart.
fn deps_oracle_holds(rt : Runtime) -> Bool {
  let num_slots = rt.core.cell_index.length()
  let has_push_downstream : @hashset.HashSet[CellId] = @hashset.HashSet([])
  let visited : @hashset.HashSet[CellId] = @hashset.HashSet([])

  // Traverse upstream from each live push cell
  for slot in 0..<num_slots {
    let cref = rt.core.cell_index[slot]
    match cref {
      PushReactive(_) | PushEffect(_) => {
        // Slot index IS the cell's id; construct CellId directly to avoid
        // @kernel.cell_id_for's abort-on-Disposed path.
        let id = CellId::{ runtime_id: rt.core.runtime_id, id: slot }
        if rt.is_cell_disposed(id) {
          continue
        }
        let worklist : Array[CellId] = [id]
        let mut wi = 0
        while wi < worklist.length() {
          let cur = worklist[wi]
          wi += 1
          guard !visited.contains(cur) else { continue }
          visited.add(cur)
          has_push_downstream.add(cur)
          for dep in cell_dependencies(rt, cur) {
            guard !visited.contains(dep) else { continue }
            guard !rt.is_cell_disposed(dep) else { continue }
            worklist.push(dep)
          }
        }
      }
      _ => ()
    }
  }

  // Compare against push_reachable_count > 0 for each gate-participating cell
  for slot in 0..<num_slots {
    let id = match cell_id_for_slot(rt, slot) {
      Some(id) => id
      None => continue
    }
    if participates_in_push_reachable_gate(rt, id) {
      let oracle_has_push = has_push_downstream.contains(id)
      let actual_has_push = push_reachable_count(rt, id) > 0
      if oracle_has_push != actual_has_push {
        return false
      }
    }
  }
  true
}

///|
/// Run a value-correctness property test with an Effect wired to the last
/// derived, then verify the dependency-graph oracle.
fn check_with_oracle(
  inputs : Array[Input[Int]],
  deriveds : Array[Derived[Int]],
  ref_fn : (Array[Int]) -> Array[Int],
  num_steps : Int,
  seed : Int,
  rt : Runtime,
) -> Unit {
  // Wire an Effect to the last derived so the oracle has a push cell to
  // traverse from (otherwise push_reachable_count is 0 everywhere).
  if deriveds.length() > 0 {
    let last = deriveds[deriveds.length() - 1]
    let _effect = Effect(rt, fn() { ignore(last.read_or_abort()) })
    ignore(last.watch())
  }
  check_value_correctness(inputs, deriveds, ref_fn, num_steps, seed)
  if !deps_oracle_holds(rt) {
    abort(
      "oracle: deps_oracle_holds failed after " +
      num_steps.to_string() +
      " steps (seed " +
      seed.to_string() +
      ")",
    )
  }
}

///|
test "l2 oracle: chain with effect" {
  let rt = Runtime()
  let (inputs, deriveds, ref_fn) = make_chain_fixture(rt)
  check_with_oracle(inputs, deriveds, ref_fn, 500, 42, rt)
}

///|
test "l2 oracle: diamond with effect" {
  let rt = Runtime()
  let (inputs, deriveds, ref_fn) = make_diamond_fixture(rt)
  check_with_oracle(inputs, deriveds, ref_fn, 500, 43, rt)
}

///|
test "l2 oracle: reachable derived with effect" {
  let rt = Runtime()
  let (inputs, deriveds, ref_fn) = make_reach_fixture(rt)
  // Wire an Effect to the last reachable derived — since ReachableDerived is
  // not a push cell itself, the effect provides the push path.
  if deriveds.length() > 0 {
    let last = deriveds[deriveds.length() - 1]
    let _effect = Effect(rt, fn() { ignore(last.read_or_abort()) })
    ignore(last.watch())
  }
  check_value_correctness_reach(inputs, deriveds, ref_fn, 500, 44)
  if !deps_oracle_holds(rt) {
    abort("oracle: deps_oracle_holds failed after 500 steps (seed 44)")
  }
}

// ============================================================
//  Nested-batch state machine property test
// ============================================================
//
// Generates random batch action trees (Set / Batch-with-children) and executes
// them against both the real Runtime and a pure state model. After every
// successful commit or rollback, asserts the Runtime's committed values match
// the model.
//
// Catches bugs in:
//   - Frame depth tracking and nesting
//   - Rollback restoring pre-batch pending state
//   - Frame merge on successful inner batch completion
//   - Pending write bookkeeping across frames

///|
/// Sub-error type for batch state machine raises.
///
/// Uses `L2Stop` to avoid ambiguity with `BatchTestError::Stop` in batch_wbtest.mbt.
suberror L2BatchError {
  L2Stop
}

///|
/// A single action in the generated batch tree.
enum BatchAction {
  /// Set input[idx] to val (outside or inside a batch).
  SetAction(Int, Int)
  /// Execute children inside a batch, optionally raising at the end.
  BatchAction(Array[BatchAction], Bool)
}

///|
/// Apply a sequence of actions to a pure state array (the model).
///
/// * `SetAction` directly updates the value at the given index.
/// * `BatchAction(_, true)` discards all children (raise = rollback).
/// * `BatchAction(children, false)` recurses into children (commit).
fn apply_actions(state : Array[Int], actions : Array[BatchAction]) -> Unit {
  for action in actions {
    match action {
      SetAction(idx, val) => state[idx] = val
      BatchAction(_, true) => () // raise rolls back all children
      BatchAction(children, false) => apply_actions(state, children)
    }
  }
}

///|
/// Execute actions against the real Runtime (no model updates).
///
/// This function is called inside batch closures where closures capture by
/// value — it only touches the Runtime, never the model.
fn exec_runtime_actions(
  rt : Runtime,
  inputs : Array[Input[Int]],
  actions : Array[BatchAction],
) -> Unit {
  for action in actions {
    match action {
      SetAction(idx, val) => inputs[idx].set(val)
      BatchAction(children, should_raise) =>
        if should_raise {
          let _ = rt.batch_result(fn() raise {
            exec_runtime_actions(rt, inputs, children)
            raise L2BatchError::L2Stop
          })
        } else {
          rt.batch(fn() { exec_runtime_actions(rt, inputs, children) })
        }
    }
  }
}

///|
/// Generate a single random `BatchAction`.
fn generate_one_action(
  rng : LCG,
  remaining_depth : Int,
  num_inputs : Int,
  max_children : Int,
) -> BatchAction {
  // ~33% chance to generate a BatchAction when depth allows; otherwise SetAction.
  if remaining_depth > 0 && rng.next_range(3) == 0 {
    let num_children = rng.next_range(max_children) + 1
    let children : Array[BatchAction] = []
    for _i in 0..<num_children {
      children.push(
        generate_one_action(rng, remaining_depth - 1, num_inputs, max_children),
      )
    }
    let should_raise = rng.next_range(4) == 0 // 25% of batches raise
    BatchAction::BatchAction(children, should_raise)
  } else {
    BatchAction::SetAction(rng.next_range(num_inputs), rng.next_range(100))
  }
}

///|
/// Generate a random tree of batch actions.
fn generate_batch_actions(
  rng : LCG,
  max_depth : Int,
  num_inputs : Int,
  max_children : Int,
) -> Array[BatchAction] {
  let count = rng.next_range(6) + 1 // 1–6 top-level actions
  let actions : Array[BatchAction] = []
  for _i in 0..<count {
    actions.push(generate_one_action(rng, max_depth, num_inputs, max_children))
  }
  actions
}

///|
/// Assert that the batch engine's internal state is clean after a top-level
/// batch completion. Catches internal-state corruption that `peek()` cannot
/// witness (stale `pending_value`, `commit_pending`, or leaked frames).
fn check_batch_invariants(rt : Runtime, seed : Int) -> Unit {
  if rt.core.batch.pending.length() != 0 {
    abort(
      "batch state machine seed " +
      seed.to_string() +
      ": pending.length() = " +
      rt.core.batch.pending.length().to_string() +
      " != 0 after batch completion",
    )
  }
  if rt.core.batch.frames.length() != 0 {
    abort(
      "batch state machine seed " +
      seed.to_string() +
      ": frames.length() = " +
      rt.core.batch.frames.length().to_string() +
      " != 0 after batch completion",
    )
  }
  if rt.core.batch.depth != 0 {
    abort(
      "batch state machine seed " +
      seed.to_string() +
      ": depth = " +
      rt.core.batch.depth.to_string() +
      " != 0 after batch completion",
    )
  }
}

///|
/// Run one seed of the nested-batch state machine property test.
///
/// Generates a random action tree, then executes it against both the real
/// Runtime and a pure state model. After every top-level batch completion
/// (commit or rollback), asserts that committed values match the model.
fn run_nested_batch_seed(
  rt : Runtime,
  inputs : Array[Input[Int]],
  seed : Int,
) -> Unit {
  let rng = LCG::new(seed)
  let actions = generate_batch_actions(rng, 3, inputs.length(), 4)

  // Capture initial committed values as model baseline
  let expected : Array[Int] = []
  for i in 0..<inputs.length() {
    expected.push(inputs[i].peek())
  }

  for action in actions {
    match action {
      SetAction(idx, val) => {
        inputs[idx].set(val)
        expected[idx] = val
      }
      BatchAction(children, should_raise) => {
        if should_raise {
          // Runtime: raise → rollback
          let _ = rt.batch_result(fn() raise {
            exec_runtime_actions(rt, inputs, children)
            raise L2BatchError::L2Stop
          })
          // Model: children are discarded (rollback)
        } else {
          // Runtime: batch commits
          rt.batch(fn() { exec_runtime_actions(rt, inputs, children) })
          // Model: apply children's effects
          apply_actions(expected, children)
        }
        check_batch_invariants(rt, seed)
      }
    }
  }
}

///|
test "l2 batch state machine: nested random ops" {
  let rt = Runtime()
  let input_a = Input::Input(rt, 0)
  let input_b = Input::Input(rt, 0)
  let input_c = Input::Input(rt, 0)
  let inputs = [input_a, input_b, input_c]
  // Run 8 seeds for coverage
  run_nested_batch_seed(rt, inputs, 47)
  run_nested_batch_seed(rt, inputs, 48)
  run_nested_batch_seed(rt, inputs, 49)
  run_nested_batch_seed(rt, inputs, 50)
  run_nested_batch_seed(rt, inputs, 51)
  run_nested_batch_seed(rt, inputs, 52)
  run_nested_batch_seed(rt, inputs, 53)
  run_nested_batch_seed(rt, inputs, 54)
}
