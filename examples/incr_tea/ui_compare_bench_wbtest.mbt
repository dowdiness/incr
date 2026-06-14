///|
/// `incr_tea` side of the shared UI-shaped pure-view benchmark slice for #257.
///
/// Adjacent-framework dependencies live in the JS-only
/// `examples/incr_tea/ui_compare_bench` subpackage so the root package stays
/// benchable on wasm-gc for the existing gate benchmarks.

///|
#cfg(target="js")
fn ui_compare_incr_counter_view(count : Int) -> Html[String] {
  div(attrs=[class_attr("counter")], [
    h2([text("Count: \{count}")]),
    button(events=[on_click("increment")], "+"),
  ])
}

///|
#cfg(target="js")
test "ui compare counter: incr_tea pure view build" (b : @bench.T) {
  let mut count = 0
  b.bench(() => {
    count = count + 1
    b.keep(ui_compare_incr_counter_view(count))
  })
}

///|
#cfg(target="js")
test "ui compare list N=16: incr_tea keyed pure view build" (b : @bench.T) {
  let items = dom_bench_make_items(16)
  b.bench(() => {
    let view : Html[String] = dom_bench_keyed_list(items)
    b.keep(view)
  })
}

///|
#cfg(target="js")
test "ui compare list N=64: incr_tea keyed pure view build" (b : @bench.T) {
  let items = dom_bench_make_items(64)
  b.bench(() => {
    let view : Html[String] = dom_bench_keyed_list(items)
    b.keep(view)
  })
}

///|
#cfg(target="js")
test "ui compare list N=256: incr_tea keyed pure view build" (b : @bench.T) {
  let items = dom_bench_make_items(256)
  b.bench(() => {
    let view : Html[String] = dom_bench_keyed_list(items)
    b.keep(view)
  })
}
