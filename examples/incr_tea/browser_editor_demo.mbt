///|
#cfg(target="js")
priv struct EditorNode {
  id : String
  label : String
  role : String
  text : @incr.InputField[String]
  diagnostic : @incr.InputField[String]
}

///|
#cfg(target="js")
fn EditorNode::EditorNode(
  scope : @incr.Scope,
  id : String,
  label : String,
  role : String,
  initial_text : String,
  initial_diagnostic : String,
) -> EditorNode {
  {
    id,
    label,
    role,
    text: scope.input_field(initial_text, label="demo.editor.\{id}.text"),
    diagnostic: scope.input_field(
      initial_diagnostic,
      label="demo.editor.\{id}.diagnostic",
    ),
  }
}

///|
#cfg(target="js")
priv struct EditorDemoModel {
  scope : @incr.Scope
  nodes_by_id : @hashmap.HashMap[String, EditorNode]
  order : @incr.InputField[Array[String]]
  selected_id : @incr.InputField[String]
  viewport_revision : @incr.InputField[Int]
  diagnostic_revision : @incr.InputField[Int]
}

///|
#cfg(target="js")
fn EditorDemoModel::EditorDemoModel(runtime : @incr.Runtime) -> EditorDemoModel {
  let scope = @incr.Scope::new(runtime)
  let nodes = [
    EditorNode(
      scope, "sem-module", "module header", "module", "module Canvas", "ok: root projection is stable",
    ),
    EditorNode(
      scope, "sem-binding", "binding name", "binding", "map", "warning: rename propagates to call sites",
    ),
    EditorNode(
      scope, "sem-call", "call site", "expression", "map(points)", "ok: call site is linked to the binding",
    ),
  ]
  let nodes_by_id : @hashmap.HashMap[String, EditorNode] = @hashmap.HashMap([])
  nodes.each(node => nodes_by_id.set(node.id, node))
  {
    scope,
    nodes_by_id,
    order: scope.input_field(
      nodes.map(node => node.id),
      label="demo.editor.order",
    ),
    selected_id: scope.input_field(
      "sem-binding",
      label="demo.editor.selected_id",
    ),
    viewport_revision: scope.input_field(
      0,
      label="demo.editor.viewport_revision",
    ),
    diagnostic_revision: scope.input_field(
      0,
      label="demo.editor.diagnostic_revision",
    ),
  }
}

///|
#cfg(target="js")
fn EditorDemoModel::require_node(
  self : EditorDemoModel,
  id : String,
) -> EditorNode {
  match self.nodes_by_id.get(id) {
    Some(node) => node
    None => abort("unknown editor semantic id: \{id}")
  }
}

///|
#cfg(target="js")
fn EditorDemoModel::edit_node(
  self : EditorDemoModel,
  id : String,
  value : String,
) -> Unit {
  match self.nodes_by_id.get(id) {
    Some(node) => {
      self.selected_id.set(id)
      node.text.set(value)
    }
    None => ()
  }
}

///|
#cfg(target="js")
fn EditorDemoModel::rename_selected(self : EditorDemoModel) -> Unit {
  let node = self.require_node(self.selected_id.peek())
  let current = node.text.peek()
  let next = match current {
    "map" => "fold"
    "fold" => "map"
    _ => current + "'"
  }
  node.text.set(next)
}

///|
#cfg(target="js")
fn EditorDemoModel::move_selected_down(self : EditorDemoModel) -> Unit {
  let selected = self.selected_id.peek()
  let next_order = self.order.peek().copy()
  let selected_index : Int? = for index, id in next_order {
    if id == selected {
      break Some(index)
    }
  } nobreak {
    None
  }
  match selected_index {
    Some(index) =>
      if index + 1 < next_order.length() {
        next_order.swap(index, index + 1)
        self.order.set(next_order)
      }
    None => ()
  }
}

///|
#cfg(target="js")
fn EditorDemoModel::bump_selected_diagnostic(self : EditorDemoModel) -> Unit {
  let node = self.require_node(self.selected_id.peek())
  let next = self.diagnostic_revision.peek() + 1
  self.diagnostic_revision.set(next)
  node.diagnostic.set("warning rev \{next}: inspector-only diagnostic changed")
}

///|
#cfg(target="js")
fn editor_projection_program(
  runtime : @incr.Runtime,
  model : EditorDemoModel,
) -> Program[DemoMsg, Html[DemoMsg]] {
  let update : (DemoMsg) -> Cmd[DemoMsg] = msg => {
    match msg {
      EditorSelect(id) =>
        match model.nodes_by_id.get(id) {
          Some(_) => model.selected_id.set(id)
          None => ()
        }
      EditorNodeInput(id, value) => model.edit_node(id, value)
      EditorRenameSelected => model.rename_selected()
      EditorMoveSelectedDown => model.move_selected_down()
      EditorTouchViewport =>
        model.viewport_revision.set(model.viewport_revision.peek() + 1)
      EditorBumpDiagnostics => model.bump_selected_diagnostic()
      _ => ()
    }
    Cmd::none()
  }
  let view : () -> Html[DemoMsg] raise Failure = () => {
    let selected = model.selected_id.get()
    let viewport_revision = model.viewport_revision.get()
    let rows = model.order
      .get()
      .mapi((position, id) => {
        let node = model.require_node(id)
        let is_selected = id == selected
        let row_class = if is_selected {
          "editor-row is-selected"
        } else {
          "editor-row"
        }
        (
          id,
          li(
            attrs=[
              class_attr(row_class),
              attr("data-semantic-id", id),
              attr("data-position", "\{position}"),
              attr("role", "option"),
              aria_attr("selected", if is_selected { "true" } else { "false" }),
            ],
            events=[on_pointer_down(id=PointerEventId("editor.select.\{id}"))],
            [
              span(attrs=[class_attr("editor-position")], [
                text("#\{position + 1}"),
              ]),
              div(attrs=[class_attr("editor-node-meta")], [
                span(attrs=[class_attr("editor-node-role")], [text(node.role)]),
                span(attrs=[class_attr("editor-node-id")], [text(id)]),
              ]),
              input(
                attrs=[
                  class_attr("editor-token-input"),
                  attr("value", node.text.get()),
                  attr("data-semantic-id", id),
                  aria_attr("label", "Edit \{node.label}"),
                ],
                events=[on_input(tag="editor.text.\{id}")],
              ),
              span(attrs=[class_attr("editor-node-label")], [text(node.label)]),
            ],
          ),
        )
      })
    article(attrs=[class_attr("demo-card editor-projection-card")], [
      h2([text("Semantic-keyed editor")]),
      p(attrs=[class_attr("demo-note")], [
        text(
          "Rows are keyed by semantic ids, not by their current positions. Type in a token, move the selection, or change diagnostics and watch the renderer counters.",
        ),
      ]),
      div(attrs=[class_attr("button-row")], [
        demo_button(EditorRenameSelected, "rename selected"),
        demo_button(EditorMoveSelectedDown, "move selected down"),
        demo_button(EditorTouchViewport, "touch viewport"),
        demo_button(EditorBumpDiagnostics, "bump selected diagnostic"),
      ]),
      p(attrs=[class_attr("editor-viewport")], [
        text("viewport revision: \{viewport_revision}"),
      ]),
      keyed_node(
        "ol",
        attrs=[class_attr("editor-projection"), attr("role", "listbox")],
        rows,
      ),
    ])
  }
  Program::Program(
    runtime,
    model.scope,
    update,
    view,
    label="demo.editor.projection.view",
  )
}

///|
#cfg(target="js")
fn editor_inspector_program(
  runtime : @incr.Runtime,
  model : EditorDemoModel,
) -> Program[DemoMsg, Html[DemoMsg]] {
  let scope = @incr.Scope::new(runtime)
  let update : (DemoMsg) -> Cmd[DemoMsg] = _ => Cmd::none()
  let view : () -> Html[DemoMsg] raise Failure = () => {
    let selected = model.selected_id.get()
    let node = model.require_node(selected)
    article(attrs=[class_attr("demo-card editor-inspector-card")], [
      h3([text("Derived inspector")]),
      p(attrs=[class_attr("metric-line")], [
        span(attrs=[class_attr("metric-label")], [text("selected")]),
        span(attrs=[class_attr("editor-node-id")], [text(selected)]),
      ]),
      p([text("role: \{node.role}")]),
      p([text("text: \{node.text.get()}")]),
      p(attrs=[class_attr("editor-diagnostic")], [
        text("diagnostic: \{node.diagnostic.get()}"),
      ]),
      p(attrs=[class_attr("demo-note")], [
        text(
          "This side panel is a separate watched view root: it reads selection, selected text, and diagnostics, but not row order or viewport state.",
        ),
      ]),
    ])
  }
  Program::Program(
    runtime,
    scope,
    update,
    view,
    label="demo.editor.inspector.view",
  )
}

///|
#cfg(target="js")
fn editor_on_input(id : TextInputId, payload : TextInputPayload) -> DemoMsg? {
  match id.name.strip_prefix("editor.text.") {
    Some(semantic_id) =>
      Some(EditorNodeInput(semantic_id.to_owned(), payload.value))
    None => None
  }
}

///|
#cfg(target="js")
fn editor_on_pointer(
  id : PointerEventId,
  _payload : PointerPayload,
) -> DemoMsg? {
  match id.name.strip_prefix("editor.select.") {
    Some(semantic_id) => Some(EditorSelect(semantic_id.to_owned()))
    None => None
  }
}
