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
/// Read a derived value without GC-rooting side effects.
///
/// Creates a temporary observer, reads the value, then disposes it.
fn[T] read_derived_for_test(d : Derived[T]) -> T {
  let obs = d.observe()
  let v = obs.get()
  obs.dispose()
  v
}

// ============================================================
//  Property test driver
// ============================================================

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
) -> Unit raise InspectError {
  let rng = LCG::new(seed)
  let num_inputs = inputs.length()
  let num_deriveds = deriveds.length()

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

    // Compare every derived against the reference
    for d in 0..<num_deriveds {
      let real_val = read_derived_for_test(deriveds[d])
      let matches = real_val == expected[d]
      inspect(matches, content="true")
    }
  }
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

// ============================================================
//  Value correctness property tests
// ============================================================

///|
test "l2 value: chain random ops" {
  let rt = Runtime()
  let (inputs, deriveds, ref_fn) = make_chain_fixture(rt)
  check_value_correctness(inputs, deriveds, ref_fn, 50, 42)
}

///|
test "l2 value: diamond random ops" {
  let rt = Runtime()
  let (inputs, deriveds, ref_fn) = make_diamond_fixture(rt)
  check_value_correctness(inputs, deriveds, ref_fn, 50, 43)
}

///|
test "l2 value: two chains random ops" {
  let rt = Runtime()
  let (inputs, deriveds, ref_fn) = make_two_chains_fixture(rt)
  check_value_correctness(inputs, deriveds, ref_fn, 50, 44)
}

///|
test "l2 value: conditional dynamic deps random ops" {
  let rt = Runtime()
  let (inputs, deriveds, ref_fn) = make_conditional_fixture(rt)
  check_value_correctness(inputs, deriveds, ref_fn, 50, 45)
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

  let b1 = Derived(rt, fn() {
    input_b.get() + 10
  })
  let b2 = Derived(rt, fn() {
    b1.get_or_abort() * 2
  })

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
