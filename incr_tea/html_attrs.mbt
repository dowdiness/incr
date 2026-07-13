///|
/// Eq-safe attribute builder for common editor/demo HTML needs.
///
/// Builder methods return a fresh builder and keep the eventual attribute order
/// explicit. Finish with `to_array()` before passing attributes to an element
/// constructor.
#cfg(target="js")
pub struct Attrs {
  priv values : Array[Attribute]
}

///|
#cfg(target="js")
pub fn Attrs::build() -> Attrs {
  { values: [] }
}

///|
#cfg(target="js")
pub fn Attrs::append(self : Attrs, attribute : Attribute) -> Attrs {
  let values = self.values.copy()
  values.push(attribute)
  { values, }
}

///|
#cfg(target="js")
pub fn Attrs::attr(self : Attrs, name : String, value : String) -> Attrs {
  self.append(attr(name, value))
}

///|
#cfg(target="js")
pub fn Attrs::class(self : Attrs, value : String) -> Attrs {
  self.append(class_attr(value))
}

///|
#cfg(target="js")
pub fn Attrs::role(self : Attrs, value : String) -> Attrs {
  self.attr("role", value)
}

///|
#cfg(target="js")
pub fn Attrs::value(self : Attrs, value : String) -> Attrs {
  self.attr("value", value)
}

///|
#cfg(target="js")
pub fn Attrs::placeholder(self : Attrs, value : String) -> Attrs {
  self.attr("placeholder", value)
}

///|
#cfg(target="js")
pub fn Attrs::data(self : Attrs, name : String, value : String) -> Attrs {
  self.attr("data-" + name, value)
}

///|
#cfg(target="js")
pub fn Attrs::aria(self : Attrs, name : String, value : String) -> Attrs {
  self.append(aria_attr(name, value))
}

///|
#cfg(target="js")
pub fn Attrs::aria_bool(self : Attrs, name : String, value : Bool) -> Attrs {
  self.aria(name, if value { "true" } else { "false" })
}

///|
#cfg(target="js")
pub fn Attrs::to_array(self : Attrs) -> Array[Attribute] {
  self.values.copy()
}

///|
/// Sets the DOM `checked` property on checkbox/radio inputs. Both `true` and
/// `false` are explicit controlled intents; omit the helper for uncontrolled
/// browser-owned state.
#cfg(target="js")
pub fn Attrs::checked(self : Attrs, value : Bool) -> Attrs {
  self.append(prop_bool_value("checked", value))
}

///|
/// Sets the DOM `disabled` property on form controls. Both `true` and `false`
/// are explicit controlled intents; omit the helper for uncontrolled
/// browser-owned state.
#cfg(target="js")
pub fn Attrs::disabled(self : Attrs, value : Bool) -> Attrs {
  self.append(prop_bool_value("disabled", value))
}

///|
/// Sets the DOM `selected` property on `<option>` elements. Both `true` and
/// `false` are explicit controlled intents; omit the helper for uncontrolled
/// browser-owned state.
#cfg(target="js")
pub fn Attrs::selected(self : Attrs, value : Bool) -> Attrs {
  self.append(prop_bool_value("selected", value))
}
