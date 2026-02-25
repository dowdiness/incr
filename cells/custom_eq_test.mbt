// =============================================================================
// Tests for Memo with custom Eq types
// =============================================================================
// These tests verify that backdating correctly uses the Eq trait for
// value comparison, not reference identity. This is important for types
// where structural equality differs from identity.

///|
/// A point type where equality is based on coordinates, not identity.
/// Two Point instances at the same coordinates are equal even if they
/// are different allocations.
struct Point {
  x : Int
  y : Int

  fn new(x : Int, y : Int) -> Point
} derive(Eq)

///|
fn Point::new(x : Int, y : Int) -> Point {
  { x, y }
}

///|
test "custom_eq: backdating with Point struct" {
  // Test that backdating uses Eq, not identity.
  // A memo that produces Point with coordinates based on input mod 10.
  // Different inputs can produce equal Points (e.g., 5 and 15 both -> Point(5, 0))
  let rt = Runtime::new()
  let input = Signal::new(rt, 5)

  let mut point_count = 0
  let point_memo = Memo::new(rt, () => {
    point_count = point_count + 1
    // x is input mod 10, y is always 0
    // So 5, 15, 25, etc. all produce Point(5, 0)
    Point(input.get() % 10, 0)
  })

  let mut downstream_count = 0
  let downstream = Memo::new(rt, () => {
    downstream_count = downstream_count + 1
    let p = point_memo.get()
    p.x * 100 + p.y
  })

  // Initial: input=5 -> Point(5, 0) -> 500
  inspect(downstream.get(), content="500")
  inspect(point_count, content="1")
  inspect(downstream_count, content="1")

  // Change to 15: Point(5, 0) -> same coordinates!
  // A new Point object is allocated but equals the old value via Eq
  // -> backdating should apply
  input.set(15)
  inspect(downstream.get(), content="500")
  inspect(point_count, content="2") // point_memo recomputed
  inspect(downstream_count, content="1") // downstream did NOT recompute (backdated!)

  // Change to 7: Point(7, 0) -> different coordinates
  input.set(7)
  inspect(downstream.get(), content="700")
  inspect(point_count, content="3")
  inspect(downstream_count, content="2") // downstream DID recompute
}

///|
/// A wrapper type where equality ignores a "generation" field.
/// Two Versioned values are equal if their inner value is equal,
/// regardless of their generation counter.
priv struct Versioned {
  value : Int
  generation : Int // Ignored in equality check

  fn new(value : Int, generation : Int) -> Versioned
}

///|
impl Eq for Versioned with equal(self, other) -> Bool {
  self.value == other.value
}

///|
fn Versioned::new(value : Int, generation : Int) -> Versioned {
  { value, generation }
}

///|
test "custom_eq: backdating ignores generation field" {
  let rt = Runtime::new()
  let input = Signal::new(rt, 100)

  let mut gen = 0
  let mut versioned_count = 0
  let versioned_memo : Memo[Versioned] = Memo::new(rt, () => {
    versioned_count = versioned_count + 1
    gen = gen + 1
    // Each computation creates new generation but value based on input
    Versioned(input.get() / 10, gen)
  })

  let mut downstream_count = 0
  let downstream = Memo::new(rt, () => {
    downstream_count = downstream_count + 1
    versioned_memo.get().value * 2
  })

  // Initial: input=100 -> Versioned(10, gen=1) -> 20
  inspect(downstream.get(), content="20")
  inspect(versioned_count, content="1")
  inspect(downstream_count, content="1")

  // Change to 105: value=10 (same), gen=2 (different)
  // But Eq only compares value, so backdating should apply
  input.set(105)
  inspect(downstream.get(), content="20")
  inspect(versioned_count, content="2") // versioned_memo recomputed
  inspect(downstream_count, content="1") // downstream did NOT recompute (backdated!)

  // Verify generation did increment
  inspect(gen, content="2")
  inspect(versioned_memo.get().generation, content="2")

  // Change to 200: value=20 (different), gen=3
  input.set(200)
  inspect(downstream.get(), content="40")
  inspect(versioned_count, content="3")
  inspect(downstream_count, content="2") // Now downstream recomputed
}

///|
/// An enum type with custom equality semantics.
priv enum Status {
  Loading(progress~ : Int)
  Ready(data~ : Int)
  Error(code~ : Int, message~ : String)
}

///|
impl Eq for Status with equal(self, other) -> Bool {
  match (self, other) {
    (Loading(progress=p1), Loading(progress=p2)) => p1 == p2
    (Ready(data=d1), Ready(data=d2)) => d1 == d2
    (Error(code=c1, ..), Error(code=c2, ..)) =>
      // Only compare error codes, ignore message
      c1 == c2
    _ => false
  }
}

///|
test "custom_eq: enum with selective field comparison" {
  let rt = Runtime::new()
  let error_code = Signal::new(rt, 404)
  let error_msg = Signal::new(rt, "Not Found")

  let mut status_count = 0
  let status_memo : Memo[Status] = Memo::new(rt, () => {
    status_count = status_count + 1
    Error(code=error_code.get(), message=error_msg.get())
  })

  let mut handler_count = 0
  let handler = Memo::new(rt, () => {
    handler_count = handler_count + 1
    match status_memo.get() {
      Error(code=c, ..) => "Error: " + c.to_string()
      Ready(data=d) => "Data: " + d.to_string()
      Loading(progress=p) => "Loading: " + p.to_string() + "%"
    }
  })

  // Initial
  inspect(handler.get(), content="Error: 404")
  inspect(status_count, content="1")
  inspect(handler_count, content="1")

  // Change message but keep same code: Error eq ignores message
  error_msg.set("Page Not Found")
  inspect(handler.get(), content="Error: 404")
  inspect(status_count, content="2") // recomputed
  inspect(handler_count, content="1") // backdated! Same error code

  // Change error code: now handler should recompute
  error_code.set(500)
  inspect(handler.get(), content="Error: 500")
  inspect(status_count, content="3")
  inspect(handler_count, content="2")
}

///|
test "custom_eq: status variants and fields are used" {
  let loading = Loading(progress=42)
  let ready = Ready(data=7)
  let error = Error(code=500, message="boom")

  match loading {
    Loading(progress=p) => inspect(p, content="42")
    _ => abort("expected loading")
  }

  match ready {
    Ready(data=d) => inspect(d, content="7")
    _ => abort("expected ready")
  }

  match error {
    Error(message=m, ..) => inspect(m, content="boom")
    _ => abort("expected error")
  }
}

///|
/// Test with Array where content equality matters
test "custom_eq: array content equality" {
  let rt = Runtime::new()
  let size = Signal::new(rt, 3)

  let mut array_count = 0
  let array_memo : Memo[Array[Int]] = Memo::new(rt, () => {
    array_count = array_count + 1
    let arr : Array[Int] = []
    for i = 0; i < size.get(); i = i + 1 {
      arr.push(i * 2)
    }
    arr
  })

  let mut sum_count = 0
  let sum_memo = Memo::new(rt, () => {
    sum_count = sum_count + 1
    let arr = array_memo.get()
    let mut total = 0
    for i = 0; i < arr.length(); i = i + 1 {
      total = total + arr[i]
    }
    total
  })

  // Initial: [0, 2, 4] -> sum = 6
  inspect(sum_memo.get(), content="6")
  inspect(array_count, content="1")
  inspect(sum_count, content="1")

  // Same size -> creates new array with same content
  // Array equality is by content, so backdating should apply
  size.set(3)
  // Note: Signal same-value optimization means no revision bump
  inspect(sum_memo.get(), content="6")
  inspect(array_count, content="1") // No recompute due to signal optimization
  inspect(sum_count, content="1")

  // Force recomputation by changing then reverting
  size.set(4) // [0, 2, 4, 6] -> sum = 12
  inspect(sum_memo.get(), content="12")
  inspect(array_count, content="2")
  inspect(sum_count, content="2")

  size.set(3) // Back to [0, 2, 4] -> new array, but same content as initial
  inspect(sum_memo.get(), content="6")
  inspect(array_count, content="3") // Array memo recomputed
  inspect(sum_count, content="3") // Sum also recomputed since array changed (different object)
}
