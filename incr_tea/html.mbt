///|
/// Pure id for direct attribute patch descriptors.
#cfg(target="js")
priv struct DirectAttrId {
  name : String
} derive(Eq, Debug)

///|
/// Static attribute data for the minimal Incremental TEA HTML subset.
#cfg(target="js")
pub struct Attribute {
  priv name : String
  priv value : String
  priv direct : DirectAttrId?
  priv bool_value : Bool?
} derive(Eq, Debug)

///|
#cfg(target="js")
fn DirectAttrId::DirectAttrId(name : String) -> DirectAttrId {
  { name, }
}

///|
/// Pure id for direct text leaf patch descriptors.
#cfg(target="js")
priv struct DirectTextId {
  name : String
} derive(Eq, Debug)

///|
#cfg(target="js")
fn DirectTextId::DirectTextId(name : String) -> DirectTextId {
  { name, }
}

///|
/// Pure id for value payload events.
#cfg(target="js")
pub struct ValueEventId {
  name : String
} derive(Eq, Debug)

///|
/// Construct a value event identifier from a name. This constructor does not error.
#cfg(target="js")
pub fn ValueEventId::ValueEventId(name : String) -> ValueEventId {
  { name, }
}

///|
/// Browser-extracted value payload.
#cfg(target="js")
pub struct ValuePayload {
  value : String
}

///|
/// Construct a value payload from a string. This constructor does not error.
#cfg(target="js")
pub fn ValuePayload::ValuePayload(value : String) -> ValuePayload {
  { value, }
}

///|
/// Pure id for checkbox/radio checked-state payload events.
#cfg(target="js")
pub struct CheckedInputId {
  name : String
} derive(Eq, Debug)

///|
#cfg(target="js")
pub fn CheckedInputId::CheckedInputId(name : String) -> CheckedInputId {
  { name, }
}

///|
/// Browser-extracted checkbox/radio checked payload.
#cfg(target="js")
pub struct CheckedPayload {
  checked : Bool
}

///|
#cfg(target="js")
pub fn CheckedPayload::CheckedPayload(checked : Bool) -> CheckedPayload {
  { checked, }
}

///|
/// Pure id for keyboard payload events.
#cfg(target="js")
pub struct KeyEventId {
  name : String
} derive(Eq, Debug)

///|
#cfg(target="js")
pub fn KeyEventId::KeyEventId(name : String) -> KeyEventId {
  { name, }
}

///|
/// Browser-extracted keyboard payload.
#cfg(target="js")
pub struct KeyPayload {
  key : String
  code : String
  alt_key : Bool
  ctrl_key : Bool
  meta_key : Bool
  shift_key : Bool
  repeat : Bool
}

///|
#cfg(target="js")
pub fn KeyPayload::KeyPayload(
  key : String,
  code : String,
  alt_key : Bool,
  ctrl_key : Bool,
  meta_key : Bool,
  shift_key : Bool,
  repeat : Bool,
) -> KeyPayload {
  { key, code, alt_key, ctrl_key, meta_key, shift_key, repeat }
}

///|
/// Pure DOM event actions stored in descriptors or returned by keyboard
/// resolvers. The renderer applies them to the live event at the boundary.
#cfg(target="js")
priv struct EventActions {
  prevent_default : Bool
  stop_propagation : Bool
} derive(Eq, Debug)

///|
#cfg(target="js")
fn EventActions::EventActions(
  prevent_default? : Bool = false,
  stop_propagation? : Bool = false,
) -> EventActions {
  { prevent_default, stop_propagation }
}

///|
#cfg(target="js")
fn EventActions::action_mask(self : EventActions) -> Int {
  let prevent = if self.prevent_default { 1 } else { 0 }
  let stop = if self.stop_propagation { 2 } else { 0 }
  prevent + stop
}

///|
/// Keyboard resolver result produced at the browser boundary.
///
/// The optional message re-enters the TEA scheduler. The action flags are
/// applied to the live DOM event by the renderer, so cacheable `Html` values
/// still store only pure ids and static descriptor flags.
#cfg(target="js")
pub struct KeyEventDispatch[Msg] {
  priv message : Msg?
  priv actions : EventActions
}

///|
/// Dispatches a message and optionally applies DOM event actions.
#cfg(target="js")
pub fn[Msg] KeyEventDispatch::message(
  message : Msg,
  prevent_default? : Bool = false,
  stop_propagation? : Bool = false,
) -> KeyEventDispatch[Msg] {
  {
    message: Some(message),
    actions: EventActions(prevent_default~, stop_propagation~),
  }
}

///|
/// Applies DOM event actions without dispatching a message.
#cfg(target="js")
pub fn[Msg] KeyEventDispatch::actions(
  prevent_default? : Bool = false,
  stop_propagation? : Bool = false,
) -> KeyEventDispatch[Msg] {
  { message: None, actions: EventActions(prevent_default~, stop_propagation~) }
}

///|
#cfg(target="js")
fn[Msg] KeyEventDispatch::action_mask(self : KeyEventDispatch[Msg]) -> Int {
  self.actions.action_mask()
}

///|
/// Pure id for pointer payload events.
#cfg(target="js")
pub struct PointerEventId {
  name : String
} derive(Eq, Debug)

///|
#cfg(target="js")
pub fn PointerEventId::PointerEventId(name : String) -> PointerEventId {
  { name, }
}

///|
/// Browser-extracted pointer payload.
#cfg(target="js")
pub struct PointerPayload {
  pointer_id : Int
  pointer_type : String
  client_x : Double
  client_y : Double
  offset_x : Double
  offset_y : Double
  button : Int
  buttons : Int
  alt_key : Bool
  ctrl_key : Bool
  meta_key : Bool
  shift_key : Bool
}

///|
#cfg(target="js")
pub fn PointerPayload::PointerPayload(
  pointer_id : Int,
  pointer_type : String,
  client_x : Double,
  client_y : Double,
  offset_x : Double,
  offset_y : Double,
  button : Int,
  buttons : Int,
  alt_key : Bool,
  ctrl_key : Bool,
  meta_key : Bool,
  shift_key : Bool,
) -> PointerPayload {
  {
    pointer_id,
    pointer_type,
    client_x,
    client_y,
    offset_x,
    offset_y,
    button,
    buttons,
    alt_key,
    ctrl_key,
    meta_key,
    shift_key,
  }
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
  Value(id~ : ValueEventId)
  CheckedInput(id~ : CheckedInputId)
  Key(id~ : KeyEventId)
  Pointer(id~ : PointerEventId)
} derive(Eq, Debug)

///|
/// Pure event descriptor stored in `Html` view data.
///
/// The renderer turns descriptors into DOM listeners at the boundary; tracked
/// view computations do not allocate or cache browser callback closures.
#cfg(target="js")
pub struct EventBinding[Msg] {
  priv name : String
  priv spec : EventSpec[Msg]
  priv actions : EventActions
} derive(Eq, Debug)

///|
#cfg(target="js")
fn[Msg] event_binding(
  name : String,
  spec : EventSpec[Msg],
  prevent_default? : Bool = false,
  stop_propagation? : Bool = false,
) -> EventBinding[Msg] {
  { name, spec, actions: EventActions(prevent_default~, stop_propagation~) }
}

///|
/// Private representation for cacheable HTML/VDOM values.
#cfg(target="js")
priv enum HtmlRepr[Msg] {
  Text(String)
  DirectText(id~ : DirectTextId, fallback~ : String)
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
/// Minimal cacheable HTML/VDOM representation used by the renderer prototype.
///
/// The representation is opaque so callers construct values through helpers
/// that defensively copy arrays, preserving stable `Html : Eq` cache behavior.
#cfg(target="js")
pub struct Html[Msg] {
  priv repr : HtmlRepr[Msg]
} derive(Eq, Debug)

///|
#cfg(target="js")
pub fn attr(name : String, value : String) -> Attribute {
  { name, value, direct: None, bool_value: None }
}

///|
#cfg(target="js")
fn direct_attr(
  id~ : DirectAttrId,
  name : String,
  fallback : String,
) -> Attribute {
  { name, value: fallback, direct: Some(id), bool_value: None }
}

///|
/// Creates a boolean property attribute whose presence means `true`.
///
/// Common controlled helpers use a private explicit constructor so `false`
/// remains distinguishable from an omitted uncontrolled property.
#cfg(target="js")
pub fn prop_bool(name : String) -> Attribute {
  { name, value: "", direct: None, bool_value: Some(true) }
}

///|
#cfg(target="js")
fn prop_bool_value(name : String, value : Bool) -> Attribute {
  { name, value: "", direct: None, bool_value: Some(value) }
}

///|
#cfg(target="js")
pub fn class_attr(value : String) -> Attribute {
  attr("class", value)
}

///|
#cfg(target="js")
fn direct_class_attr(id~ : DirectAttrId, fallback : String) -> Attribute {
  direct_attr(id~, "class", fallback)
}

///|
#cfg(target="js")
pub fn aria_attr(name : String, value : String) -> Attribute {
  attr("aria-" + name, value)
}

///|
#cfg(target="js")
pub fn[Msg] text(value : String) -> Html[Msg] {
  { repr: Text(value) }
}

///|
#cfg(target="js")
fn[Msg] direct_text(id~ : DirectTextId, fallback : String) -> Html[Msg] {
  { repr: DirectText(id~, fallback~) }
}

///|
#cfg(target="js")
pub fn[Msg] on_click(
  message : Msg,
  prevent_default? : Bool = false,
  stop_propagation? : Bool = false,
) -> EventBinding[Msg] {
  event_binding("click", Const(message), prevent_default~, stop_propagation~)
}

///|
/// Pure double-click descriptor for interactions such as spreadsheet inline edit.
#cfg(target="js")
pub fn[Msg] on_dblclick(
  message : Msg,
  prevent_default? : Bool = false,
  stop_propagation? : Bool = false,
) -> EventBinding[Msg] {
  event_binding("dblclick", Const(message), prevent_default~, stop_propagation~)
}

///|
/// Pure form-submit descriptor. The helper prevents the browser's native form
/// submission by default; override `prevent_default=false` only when navigation
/// is intentional.
#cfg(target="js")
pub fn[Msg] on_submit(
  message : Msg,
  prevent_default? : Bool = true,
  stop_propagation? : Bool = false,
) -> EventBinding[Msg] {
  event_binding("submit", Const(message), prevent_default~, stop_propagation~)
}

///|
/// Pure focus descriptor.
#cfg(target="js")
pub fn[Msg] on_focus(
  message : Msg,
  prevent_default? : Bool = false,
  stop_propagation? : Bool = false,
) -> EventBinding[Msg] {
  event_binding("focus", Const(message), prevent_default~, stop_propagation~)
}

///|
/// Pure blur descriptor.
#cfg(target="js")
pub fn[Msg] on_blur(
  message : Msg,
  prevent_default? : Bool = false,
  stop_propagation? : Bool = false,
) -> EventBinding[Msg] {
  event_binding("blur", Const(message), prevent_default~, stop_propagation~)
}

///|
/// Pure value descriptor. `tag` is wrapped as a typed `ValueEventId`; the
/// renderer reads the target's `value` at the browser boundary and resolves
/// `(id, payload) -> Msg` through the mount-time value resolver.
#cfg(target="js")
pub fn[Msg] on_input(
  tag~ : String,
  prevent_default? : Bool = false,
  stop_propagation? : Bool = false,
) -> EventBinding[Msg] {
  event_binding(
    "input",
    Value(id=ValueEventId(tag)),
    prevent_default~,
    stop_propagation~,
  )
}

///|
/// Pure value-change descriptor for controls whose committed value changes on
/// `change` rather than every text edit, such as selects and range sliders.
/// The renderer reads the target's `value` at the browser boundary and resolves
/// `(id, payload) -> Msg` through the mount-time value resolver.
#cfg(target="js")
pub fn[Msg] on_change(
  tag~ : String,
  prevent_default? : Bool = false,
  stop_propagation? : Bool = false,
) -> EventBinding[Msg] {
  event_binding(
    "change",
    Value(id=ValueEventId(tag)),
    prevent_default~,
    stop_propagation~,
  )
}

///|
/// Pure checked-state descriptor for checkbox/radio controls. The renderer
/// reads `event.target.checked` at the browser boundary and resolves
/// `(id, payload) -> Msg` through the mount-time checked resolver.
#cfg(target="js")
pub fn[Msg] on_checked_change(
  tag~ : String,
  prevent_default? : Bool = false,
  stop_propagation? : Bool = false,
) -> EventBinding[Msg] {
  event_binding(
    "change",
    CheckedInput(id=CheckedInputId(tag)),
    prevent_default~,
    stop_propagation~,
  )
}

///|
/// Pure keyboard descriptor. The browser boundary extracts key/code/modifier
/// payload fields and resolves them through the mount-time keyboard resolver.
#cfg(target="js")
pub fn[Msg] on_keydown(
  id~ : KeyEventId,
  prevent_default? : Bool = false,
  stop_propagation? : Bool = false,
) -> EventBinding[Msg] {
  event_binding("keydown", Key(id~), prevent_default~, stop_propagation~)
}

///|
/// Pure pointer descriptor. The browser boundary extracts pointer coordinates,
/// ids, buttons, type, and modifiers before resolving at the mount boundary.
#cfg(target="js")
pub fn[Msg] on_pointer_down(
  id~ : PointerEventId,
  prevent_default? : Bool = false,
  stop_propagation? : Bool = false,
) -> EventBinding[Msg] {
  event_binding(
    "pointerdown",
    Pointer(id~),
    prevent_default~,
    stop_propagation~,
  )
}

///|
#cfg(target="js")
pub fn[Msg] node(
  tag : String,
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[Html[Msg]],
) -> Html[Msg] {
  {
    repr: Elem(
      tag~,
      attrs=attrs.copy(),
      events=events.copy(),
      children=children.copy(),
    ),
  }
}

///|
#cfg(target="js")
pub fn[Msg] div(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[Html[Msg]],
) -> Html[Msg] {
  node("div", attrs~, events~, children)
}

///|
#cfg(target="js")
pub fn[Msg] article(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[Html[Msg]],
) -> Html[Msg] {
  node("article", attrs~, events~, children)
}

///|
#cfg(target="js")
pub fn[Msg] p(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[Html[Msg]],
) -> Html[Msg] {
  node("p", attrs~, events~, children)
}

///|
#cfg(target="js")
pub fn[Msg] span(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[Html[Msg]],
) -> Html[Msg] {
  node("span", attrs~, events~, children)
}

///|
#cfg(target="js")
pub fn[Msg] h2(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[Html[Msg]],
) -> Html[Msg] {
  node("h2", attrs~, events~, children)
}

///|
#cfg(target="js")
pub fn[Msg] h3(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[Html[Msg]],
) -> Html[Msg] {
  node("h3", attrs~, events~, children)
}

///|
#cfg(target="js")
pub fn[Msg] button(
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
pub fn[Msg] input(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
) -> Html[Msg] {
  node("input", attrs~, events~, [])
}

///|
#cfg(target="js")
pub fn[Msg] ul(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[Html[Msg]],
) -> Html[Msg] {
  node("ul", attrs~, events~, children)
}

///|
#cfg(target="js")
pub fn[Msg] li(
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
pub fn[Msg] keyed_node(
  tag : String,
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[(String, Html[Msg])],
) -> Html[Msg] {
  {
    repr: KeyedElem(
      tag~,
      attrs=attrs.copy(),
      events=events.copy(),
      children=children.copy(),
    ),
  }
}

///|
#cfg(target="js")
pub fn[Msg] keyed_ul(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[(String, Html[Msg])],
) -> Html[Msg] {
  keyed_node("ul", attrs~, events~, children)
}

///|
#cfg(target="js")
pub fn[Msg] keyed_ol(
  attrs? : Array[Attribute] = [],
  events? : Array[EventBinding[Msg]] = [],
  children : Array[(String, Html[Msg])],
) -> Html[Msg] {
  keyed_node("ol", attrs~, events~, children)
}
