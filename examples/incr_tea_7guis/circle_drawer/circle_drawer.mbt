///|
priv struct Circle {
  id : Int
  x : Int
  y : Int
  radius : Int
}

///|
priv struct Model {
  circles : Array[Circle]
  selected : Int?
  next_id : Int
  undo : Array[Array[Circle]]
  redo : Array[Array[Circle]]
}

///|
enum Msg {
  Add(Int, Int)
  Select(Int)
  SetRadius(String)
  Undo
  Redo
} derive(Eq)

///|
priv struct App {
  program : @tea.Program[Msg, @tea.Html[Msg]]
  _state : Ref[Model]
}

///|
fn App::App(runtime : @incr.Runtime) -> App {
  let scope = @incr.Scope::new(runtime)
  let state = Ref({
    circles: [],
    selected: None,
    next_id: 1,
    undo: [],
    redo: [],
  })
  let version = scope.input_field(0, label="7guis.circle.version")
  let update : (Msg) -> @tea.Cmd[Msg] = msg => {
    state.val = update_model(msg, state.val)
    version.set(version.peek() + 1)
    @tea.Cmd::none()
  }
  let view : () -> @tea.Html[Msg] raise Failure = () => {
    ignore(version.get())
    view_model(state.val)
  }
  let program = @tea.Program::Program(
    runtime,
    scope,
    update,
    view,
    label="7guis.circle.view",
  )
  { program, _state: state }
}

///|
fn parse_int_or_none(value : String) -> Int? {
  let trimmed = value.trim()
  try @string.parse_int(trimmed) catch {
    _ => None
  } noraise {
    number => Some(number)
  }
}

///|
fn push_history(model : Model) -> Array[Array[Circle]] {
  [..model.undo, model.circles]
}

///|
fn history_without_last(history : Array[Array[Circle]]) -> Array[Array[Circle]] {
  history
  .mapi((index, circles) => (index, circles))
  .filter(pair => pair.0 < history.length() - 1)
  .map(pair => pair.1)
}

///|
fn update_model(msg : Msg, model : Model) -> Model {
  match msg {
    Add(x, y) => {
      let id = model.next_id
      {
        circles: [..model.circles, { id, x, y, radius: 24 }],
        selected: Some(id),
        next_id: id + 1,
        undo: push_history(model),
        redo: [],
      }
    }
    Select(id) => { ..model, selected: Some(id) }
    SetRadius(value) =>
      model.selected
      .bind(id => parse_int_or_none(value).map(radius => (id, radius)))
      .map_or(model, pair => {
        let bounded = pair.1.clamp(min=8, max=80)
        let circles = model.circles.map(circle => {
          if circle.id == pair.0 {
            { ..circle, radius: bounded }
          } else {
            circle
          }
        })
        { ..model, circles, undo: push_history(model), redo: [] }
      })
    Undo =>
      model.undo
      .last()
      .map_or(model, previous => {
        ..model,
        circles: previous,
        selected: None,
        undo: history_without_last(model.undo),
        redo: [..model.redo, model.circles],
      })
    Redo =>
      model.redo
      .last()
      .map_or(model, next => {
        ..model,
        circles: next,
        selected: None,
        undo: [..model.undo, model.circles],
        redo: history_without_last(model.redo),
      })
  }
}

///|
fn view_model(model : Model) -> @tea.Html[Msg] {
  let selected_radius = selected_radius(model)
  @tea.article(attrs=[@tea.class_attr("task-card")], [
    @tea.div(attrs=[@tea.class_attr("task-heading")], [
      @tea.h2([@tea.text("Circle Drawer")]),
      @tea.p([@tea.text("Pointer payloads stay at the mount boundary.")]),
    ]),
    @tea.div(attrs=[@tea.class_attr("task-body")], [
      @tea.div(
        attrs=[@tea.class_attr("circle-board")],
        events=[@tea.on_pointer_down(id=@tea.PointerEventId("circle-board"))],
        model.circles.map(circle => circle_view(model, circle)),
      ),
      @tea.node("label", attrs=[@tea.class_attr("field")], [
        @tea.span([@tea.text("Selected radius")]),
        @tea.input(
          attrs=@tea.Attrs::build()
            .attr("type", "range")
            .attr("min", "8")
            .attr("max", "80")
            .value("\{selected_radius}")
            .to_array(),
          events=[@tea.on_input(tag="radius")],
        ),
      ]),
      @tea.div(attrs=[@tea.class_attr("button-row")], [
        @tea.button(
          attrs=if model.undo.is_empty() {
            disabled_button_attrs()
          } else {
            button_attrs()
          },
          events=if model.undo.is_empty() { [] } else { [@tea.on_click(Undo)] },
          "Undo",
        ),
        @tea.button(
          attrs=if model.redo.is_empty() {
            disabled_button_attrs()
          } else {
            button_attrs()
          },
          events=if model.redo.is_empty() { [] } else { [@tea.on_click(Redo)] },
          "Redo",
        ),
      ]),
    ]),
  ])
}

///|
fn circle_view(model : Model, circle : Circle) -> @tea.Html[Msg] {
  let selected = model.selected == Some(circle.id)
  let diameter = circle.radius * 2
  let class_name = if selected { "circle is-selected" } else { "circle" }
  @tea.div(
    attrs=@tea.Attrs::build()
      .class(class_name)
      .attr(
        "style",
        "left: \{circle.x}px; top: \{circle.y}px; width: \{diameter}px; height: \{diameter}px;",
      )
      .to_array(),
    events=[
      @tea.on_pointer_down(
        id=@tea.PointerEventId("circle:\{circle.id}"),
        stop_propagation=true,
      ),
    ],
    [],
  )
}

///|
fn selected_radius(model : Model) -> Int {
  model.selected
  .bind(id => model.circles.search_by(circle => circle.id == id))
  .map(index => model.circles[index].radius)
  .unwrap_or(24)
}

///|
fn button_attrs() -> Array[@tea.Attribute] {
  @tea.Attrs::build().attr("type", "button").to_array()
}

///|
fn disabled_button_attrs() -> Array[@tea.Attribute] {
  @tea.Attrs::build()
  .attr("type", "button")
  .attr("disabled", "disabled")
  .to_array()
}

///|
extern "js" fn round_client_coordinate(value : Double) -> Int =
  #| (value) => Math.round(Number(value) || 0)

///|
fn resolve_text_input(
  id : @tea.TextInputId,
  payload : @tea.TextInputPayload,
) -> Msg? {
  match id.name {
    "radius" => Some(SetRadius(payload.value))
    _ => None
  }
}

///|
fn resolve_pointer(
  id : @tea.PointerEventId,
  payload : @tea.PointerPayload,
) -> Msg? {
  match id.name {
    "circle-board" =>
      Some(
        Add(
          round_client_coordinate(payload.offset_x),
          round_client_coordinate(payload.offset_y),
        ),
      )
    [.. "circle:", .. circle_id] =>
      parse_int_or_none(circle_id.to_owned()).map(id => Select(id))
    _ => None
  }
}

///|
/// Mounts the Circle Drawer task into `host` with its own runtime and browser renderer.
pub fn mount(host : @tea.DomElement) -> Unit {
  let runtime = @incr.Runtime()
  let app = App(runtime)
  let renderer = @tea.BrowserRenderer::BrowserRenderer(runtime)
  ignore(
    renderer.mount(
      host,
      app.program,
      on_input=resolve_text_input,
      on_pointer=resolve_pointer,
    ),
  )
}
