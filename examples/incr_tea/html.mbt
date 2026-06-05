///|
/// Static attribute data for the minimal Incremental TEA HTML subset.
#cfg(target="js")
priv struct Attribute {
  name : String
  value : String
} derive(Eq, Debug)

///|
/// Pure event descriptor stored in `Html` view data.
///
/// The renderer turns descriptors into DOM listeners at the boundary; tracked
/// view computations do not allocate or cache browser callback closures.
#cfg(target="js")
priv struct EventBinding[Msg] {
  name : String
  message : Msg
} derive(Eq, Debug)

///|
/// Minimal cacheable HTML/VDOM representation used by the renderer prototype.
#cfg(target="js")
priv enum Html[Msg] {
  Text(String)
  Elem(
    tag~ : String,
    attrs~ : Array[Attribute],
    events~ : Array[EventBinding[Msg]],
    children~ : Array[Html[Msg]]
  )
} derive(Eq, Debug)

///|
#cfg(target="js")
fn attr(name : String, value : String) -> Attribute {
  { name, value }
}

///|
#cfg(target="js")
fn class_attr(value : String) -> Attribute {
  attr("class", value)
}

///|
#cfg(target="js")
fn aria_attr(name : String, value : String) -> Attribute {
  attr("aria-" + name, value)
}

///|
#cfg(target="js")
fn[Msg] text(value : String) -> Html[Msg] {
  Text(value)
}

///|
#cfg(target="js")
fn[Msg] on_click(message : Msg) -> EventBinding[Msg] {
  { name: "click", message }
}

///|
#cfg(target="js")
fn[Msg] node(
  tag : String,
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[Html[Msg]],
) -> Html[Msg] {
  Elem(tag~, attrs=attrs.copy(), events=events.copy(), children=children.copy())
}

///|
#cfg(target="js")
fn[Msg] div(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[Html[Msg]],
) -> Html[Msg] {
  node("div", attrs~, events~, children)
}

///|
#cfg(target="js")
fn[Msg] article(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[Html[Msg]],
) -> Html[Msg] {
  node("article", attrs~, events~, children)
}

///|
#cfg(target="js")
fn[Msg] p(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[Html[Msg]],
) -> Html[Msg] {
  node("p", attrs~, events~, children)
}

///|
#cfg(target="js")
fn[Msg] span(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[Html[Msg]],
) -> Html[Msg] {
  node("span", attrs~, events~, children)
}

///|
#cfg(target="js")
fn[Msg] h2(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[Html[Msg]],
) -> Html[Msg] {
  node("h2", attrs~, events~, children)
}

///|
#cfg(target="js")
fn[Msg] h3(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[Html[Msg]],
) -> Html[Msg] {
  node("h3", attrs~, events~, children)
}

///|
#cfg(target="js")
fn[Msg] button(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  label : String,
) -> Html[Msg] {
  node("button", attrs~, events~, [text(label)])
}
