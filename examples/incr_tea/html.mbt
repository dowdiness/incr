///|
/// Static attribute data for the minimal Incremental TEA HTML subset.
#cfg(target="js")
priv struct Attribute {
  name : String
  value : String
} derive(Eq, Debug)

///|
/// Pure id for text-input payload events.
#cfg(target="js")
priv struct TextInputId {
  name : String
} derive(Eq, Debug)

///|
#cfg(target="js")
fn TextInputId::TextInputId(name : String) -> TextInputId {
  { name, }
}

///|
/// Browser-extracted text input payload.
#cfg(target="js")
priv struct TextInputPayload {
  value : String
}

///|
/// Pure id for keyboard payload events.
#cfg(target="js")
priv struct KeyEventId {
  name : String
} derive(Eq, Debug)

///|
#cfg(target="js")
fn KeyEventId::KeyEventId(name : String) -> KeyEventId {
  { name, }
}

///|
/// Browser-extracted keyboard payload.
#cfg(target="js")
priv struct KeyPayload {
  key : String
  code : String
  alt_key : Bool
  ctrl_key : Bool
  meta_key : Bool
  shift_key : Bool
  repeat : Bool
}

///|
/// Pure id for pointer payload events.
#cfg(target="js")
priv struct PointerEventId {
  name : String
} derive(Eq, Debug)

///|
#cfg(target="js")
fn PointerEventId::PointerEventId(name : String) -> PointerEventId {
  { name, }
}

///|
/// Browser-extracted pointer payload.
#cfg(target="js")
priv struct PointerPayload {
  pointer_id : Int
  pointer_type : String
  client_x : Double
  client_y : Double
  button : Int
  buttons : Int
  alt_key : Bool
  ctrl_key : Bool
  meta_key : Bool
  shift_key : Bool
}

///|
/// Pure description of the message an event produces.
///
/// `Const` ignores the DOM payload and emits a fixed message (e.g. a click).
/// Payload variants carry only typed pure ids; the renderer extracts browser
/// payload data and resolves `(id, payload) -> Msg` at the mount boundary. No
/// closure or DOM event object is stored in cacheable `Html` view data.
#cfg(target="js")
priv enum EventSpec[Msg] {
  Const(Msg)
  TextInput(id~ : TextInputId)
  Key(id~ : KeyEventId)
  Pointer(id~ : PointerEventId)
} derive(Eq, Debug)

///|
/// Pure event descriptor stored in `Html` view data.
///
/// The renderer turns descriptors into DOM listeners at the boundary; tracked
/// view computations do not allocate or cache browser callback closures.
#cfg(target="js")
priv struct EventBinding[Msg] {
  name : String
  spec : EventSpec[Msg]
  prevent_default : Bool
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
  // Keyed element: children carry a stable business key so the renderer can
  // reuse DOM nodes across insert/remove/reorder. Ordered (not a Map) so the
  // child order is part of the cacheable view value.
  KeyedElem(
    tag~ : String,
    attrs~ : Array[Attribute],
    events~ : Array[EventBinding[Msg]],
    children~ : Array[(String, Html[Msg])]
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
fn[Msg] on_click(
  message : Msg,
  prevent_default? : Bool = false,
) -> EventBinding[Msg] {
  { name: "click", spec: Const(message), prevent_default }
}

///|
/// Pure text-input descriptor. `tag` is wrapped as a typed `TextInputId`; the
/// renderer reads the input element's `value` at the browser boundary and
/// resolves `(id, payload) -> Msg` through the mount-time resolver.
#cfg(target="js")
fn[Msg] on_input(
  tag~ : String,
  prevent_default? : Bool = false,
) -> EventBinding[Msg] {
  { name: "input", spec: TextInput(id=TextInputId(tag)), prevent_default }
}

///|
/// Pure keyboard descriptor. The browser boundary extracts key/code/modifier
/// payload fields and resolves them through the mount-time keyboard resolver.
#cfg(target="js")
fn[Msg] on_keydown(
  id~ : KeyEventId,
  prevent_default? : Bool = false,
) -> EventBinding[Msg] {
  { name: "keydown", spec: Key(id~), prevent_default }
}

///|
/// Pure pointer descriptor. The browser boundary extracts pointer coordinates,
/// ids, buttons, type, and modifiers before resolving at the mount boundary.
#cfg(target="js")
fn[Msg] on_pointer_down(
  id~ : PointerEventId,
  prevent_default? : Bool = false,
) -> EventBinding[Msg] {
  { name: "pointerdown", spec: Pointer(id~), prevent_default }
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

///|
/// Void input element (no children). Pair with pure payload descriptors such as
/// `on_input`, `on_keydown`, or `on_pointer_down`.
#cfg(target="js")
fn[Msg] input(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
) -> Html[Msg] {
  node("input", attrs~, events~, [])
}

///|
#cfg(target="js")
fn[Msg] ul(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[Html[Msg]],
) -> Html[Msg] {
  node("ul", attrs~, events~, children)
}

///|
#cfg(target="js")
fn[Msg] li(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[Html[Msg]],
) -> Html[Msg] {
  node("li", attrs~, events~, children)
}

///|
/// Keyed element constructor. Each child is paired with a stable, unique key
/// (use a business id, not the array index). Reordering keys preserves the DOM
/// node for each key; changing a key drops the old node and creates a new one.
#cfg(target="js")
fn[Msg] keyed_node(
  tag : String,
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[(String, Html[Msg])],
) -> Html[Msg] {
  KeyedElem(
    tag~,
    attrs=attrs.copy(),
    events=events.copy(),
    children=children.copy(),
  )
}

///|
#cfg(target="js")
fn[Msg] keyed_ul(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[(String, Html[Msg])],
) -> Html[Msg] {
  keyed_node("ul", attrs~, events~, children)
}

///|
#cfg(target="js")
fn[Msg] keyed_ol(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[(String, Html[Msg])],
) -> Html[Msg] {
  keyed_node("ol", attrs~, events~, children)
}
