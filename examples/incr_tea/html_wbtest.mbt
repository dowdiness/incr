///|
#cfg(target="js")
test "#248: Attrs builder composes Eq-safe attributes without aliasing" {
  let base = Attrs::build().class("editor-row")
  let first = base.data("semantic-id", "sem-a").aria_bool("selected", true)
  let second = base.data("semantic-id", "sem-b").aria_bool("selected", false)

  inspect(
    first.to_array() ==
    [
      class_attr("editor-row"),
      attr("data-semantic-id", "sem-a"),
      aria_attr("selected", "true"),
    ],
    content="true",
  )
  inspect(
    second.to_array() ==
    [
      class_attr("editor-row"),
      attr("data-semantic-id", "sem-b"),
      aria_attr("selected", "false"),
    ],
    content="true",
  )
}

///|
#cfg(target="js")
test "#248: keyed list wrappers are equivalent to keyed_node" {
  let children : Array[(String, Html[Unit])] = [("a", text("Alpha"))]
  let attrs = Attrs::build().class("keyed-list").role("listbox").to_array()
  let wrapped = keyed_ul(attrs~, children)
  let raw = keyed_node("ul", attrs~, children)

  inspect(wrapped == raw, content="true")
}

///|
#cfg(target="js")
test "#254: direct patch descriptors are pure Eq data" {
  let text_id = DirectTextId("hot.text")
  let attr_id = DirectAttrId("hot.class")
  let first : Html[Unit] = div(attrs=[direct_class_attr(id=attr_id, "hot")], [
    direct_text(id=text_id, "fallback"),
  ])
  let same : Html[Unit] = div(attrs=[direct_class_attr(id=attr_id, "hot")], [
    direct_text(id=text_id, "fallback"),
  ])
  let changed_id : Html[Unit] = div(
    attrs=[direct_class_attr(id=DirectAttrId("other.class"), "hot")],
    [direct_text(id=text_id, "fallback")],
  )

  inspect(first == same, content="true")
  inspect(first == changed_id, content="false")
}
