///|
/// Shared UI-shaped pure-view benchmark slice for #257.
///
/// This file intentionally measures only view-value construction for the same
/// counter and keyed-list shapes in `incr_tea`, Rabbita, and Luna. It does not
/// measure browser DOM patching, Rabbita's dirty-cell flush loop, or Luna's
/// direct DOM effects. Those need separate browser harnesses called out in the
/// dated comparison plan.

///|
#cfg(target="js")
fn ui_compare_rabbita_emit(_msg : String) -> @rabbita.Cmd {
  @rabbita.none
}

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
fn ui_compare_rabbita_counter_view(
  emit : @rabbita.Emit[String],
  count : Int,
) -> @rabbita.Html {
  @rabbita_html.div(class="counter", [
    @rabbita_html.h2("Count: \{count}"),
    @rabbita_html.button(on_click=emit("increment"), "+"),
  ])
}

///|
#cfg(target="js")
fn ui_compare_luna_counter_view(count : Int) -> @luna.Node[Unit, String] {
  @luna.h("div", [("class", @luna.attr_static("counter"))], [
    @luna.h("h2", [], [@luna.text("Count: \{count}")]),
    @luna.h(
      "button",
      [("onclick", @luna.attr_handler(@luna.event_handler()))],
      [@luna.text("+")],
    ),
  ])
}

///|
#cfg(target="js")
fn ui_compare_rabbita_row(
  emit : @rabbita.Emit[String],
  id : String,
  label : String,
) -> @rabbita.Html {
  @rabbita_html.li(class="list-item", [
    @rabbita_html.span(class="list-label", "\{label} (\{id})"),
    @rabbita_html.input(
      class="list-note",
      placeholder="notes — survive reorder",
      on_input=value => emit("\{id}:\{value}"),
      @rabbita_html.nothing,
    ),
  ])
}

///|
#cfg(target="js")
fn ui_compare_rabbita_keyed_list(
  emit : @rabbita.Emit[String],
  items : Array[(String, String)],
) -> @rabbita.Html {
  let children : Map[String, @rabbita.Html] = Map(
    items.map(pair => {
      let (id, label) = pair
      (id, ui_compare_rabbita_row(emit, id, label))
    }),
  )
  @rabbita_html.ul(class="keyed-list", children)
}

///|
#cfg(target="js")
fn ui_compare_luna_row(id : String, label : String) -> @luna.Node[Unit, String] {
  @luna.h(
    "li",
    [
      ("class", @luna.attr_static("list-item")),
      ("data-key", @luna.attr_static(id)),
    ],
    [
      @luna.h("span", [("class", @luna.attr_static("list-label"))], [
        @luna.text("\{label} (\{id})"),
      ]),
      @luna.h(
        "input",
        [
          ("class", @luna.attr_static("list-note")),
          ("placeholder", @luna.attr_static("notes — survive reorder")),
          ("oninput", @luna.attr_handler(@luna.event_handler())),
        ],
        [],
      ),
    ],
  )
}

///|
#cfg(target="js")
fn ui_compare_luna_list(
  items : Array[(String, String)],
) -> @luna.Node[Unit, String] {
  @luna.h(
    "ul",
    [("class", @luna.attr_static("keyed-list"))],
    items.map(pair => {
      let (id, label) = pair
      ui_compare_luna_row(id, label)
    }),
  )
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
test "ui compare counter: Rabbita pure view build" (b : @bench.T) {
  let emit = ui_compare_rabbita_emit
  let mut count = 0
  b.bench(() => {
    count = count + 1
    b.keep(ui_compare_rabbita_counter_view(emit, count))
  })
}

///|
#cfg(target="js")
test "ui compare counter: Luna pure VNode build" (b : @bench.T) {
  let mut count = 0
  b.bench(() => {
    count = count + 1
    b.keep(ui_compare_luna_counter_view(count))
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
test "ui compare list N=16: Rabbita keyed pure view build" (b : @bench.T) {
  let emit = ui_compare_rabbita_emit
  let items = dom_bench_make_items(16)
  b.bench(() => b.keep(ui_compare_rabbita_keyed_list(emit, items)))
}

///|
#cfg(target="js")
test "ui compare list N=16: Luna list-shaped pure VNode build" (b : @bench.T) {
  let items = dom_bench_make_items(16)
  b.bench(() => b.keep(ui_compare_luna_list(items)))
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
test "ui compare list N=64: Rabbita keyed pure view build" (b : @bench.T) {
  let emit = ui_compare_rabbita_emit
  let items = dom_bench_make_items(64)
  b.bench(() => b.keep(ui_compare_rabbita_keyed_list(emit, items)))
}

///|
#cfg(target="js")
test "ui compare list N=64: Luna list-shaped pure VNode build" (b : @bench.T) {
  let items = dom_bench_make_items(64)
  b.bench(() => b.keep(ui_compare_luna_list(items)))
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

///|
#cfg(target="js")
test "ui compare list N=256: Rabbita keyed pure view build" (b : @bench.T) {
  let emit = ui_compare_rabbita_emit
  let items = dom_bench_make_items(256)
  b.bench(() => b.keep(ui_compare_rabbita_keyed_list(emit, items)))
}

///|
#cfg(target="js")
test "ui compare list N=256: Luna list-shaped pure VNode build" (b : @bench.T) {
  let items = dom_bench_make_items(256)
  b.bench(() => b.keep(ui_compare_luna_list(items)))
}
