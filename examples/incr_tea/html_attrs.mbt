///|
/// Eq-safe attribute builder for common editor/demo HTML needs.
///
/// Builder methods return a fresh builder and keep the eventual attribute order
/// explicit. Finish with `to_array()` before passing attributes to an element
/// constructor.
#cfg(target="js")
priv struct Attrs {
  values : Array[Attribute]
}

///|
#cfg(target="js")
fn Attrs::build() -> Attrs {
  { values: [] }
}

///|
#cfg(target="js")
fn Attrs::append(self : Attrs, attribute : Attribute) -> Attrs {
  let values = self.values.copy()
  values.push(attribute)
  { values, }
}

///|
#cfg(target="js")
fn Attrs::attr(self : Attrs, name : String, value : String) -> Attrs {
  self.append(attr(name, value))
}

///|
#cfg(target="js")
fn Attrs::class(self : Attrs, value : String) -> Attrs {
  self.append(class_attr(value))
}

///|
#cfg(target="js")
fn Attrs::role(self : Attrs, value : String) -> Attrs {
  self.attr("role", value)
}

///|
#cfg(target="js")
fn Attrs::value(self : Attrs, value : String) -> Attrs {
  self.attr("value", value)
}

///|
#cfg(target="js")
fn Attrs::placeholder(self : Attrs, value : String) -> Attrs {
  self.attr("placeholder", value)
}

///|
#cfg(target="js")
fn Attrs::data(self : Attrs, name : String, value : String) -> Attrs {
  self.attr("data-" + name, value)
}

///|
#cfg(target="js")
fn Attrs::aria(self : Attrs, name : String, value : String) -> Attrs {
  self.append(aria_attr(name, value))
}

///|
#cfg(target="js")
fn Attrs::aria_bool(self : Attrs, name : String, value : Bool) -> Attrs {
  self.aria(name, if value { "true" } else { "false" })
}

///|
#cfg(target="js")
fn Attrs::to_array(self : Attrs) -> Array[Attribute] {
  self.values.copy()
}
