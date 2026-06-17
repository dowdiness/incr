///|
priv struct Model {
  flight_kind : String
  start_date : String
  return_date : String
  status : String
}

///|
enum Msg {
  SetFlightKind(String)
  SetStartDate(String)
  SetReturnDate(String)
  BookFlight
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
    flight_kind: "one-way",
    start_date: "2026-06-17",
    return_date: "2026-06-18",
    status: "Choose a trip and book it.",
  })
  let version = scope.input_field(0, label="7guis.flight.version")
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
    label="7guis.flight.view",
  )
  { program, _state: state }
}

///|
fn dates_valid(model : Model) -> Bool {
  if model.flight_kind == "one-way" {
    !model.start_date.is_empty()
  } else {
    !model.start_date.is_empty() &&
    !model.return_date.is_empty() &&
    model.start_date <= model.return_date
  }
}

///|
fn update_model(msg : Msg, model : Model) -> Model {
  match msg {
    SetFlightKind(value) => { ..model, flight_kind: value }
    SetStartDate(value) => { ..model, start_date: value }
    SetReturnDate(value) => { ..model, return_date: value }
    BookFlight =>
      if dates_valid(model) {
        let status = if model.flight_kind == "one-way" {
          "Booked one-way flight on \{model.start_date}."
        } else {
          "Booked return flight from \{model.start_date} to \{model.return_date}."
        }
        { ..model, status, }
      } else {
        { ..model, status: "Choose valid flight dates." }
      }
  }
}

///|
fn view_model(model : Model) -> @tea.Html[Msg] {
  let return_disabled = model.flight_kind == "one-way"
  let can_book = dates_valid(model)
  @tea.article(attrs=[@tea.class_attr("task-card")], [
    @tea.div(attrs=[@tea.class_attr("task-heading")], [
      @tea.h2([@tea.text("Flight Booker")]),
      @tea.p([@tea.text("Select and date changes use pure change descriptors.")]),
    ]),
    @tea.div(attrs=[@tea.class_attr("task-body")], [
      labeled_select("Trip", "flight-kind", "kind", model.flight_kind, [
        ("one-way", "one-way flight"),
        ("return", "return flight"),
      ]),
      date_field("Start", "flight-start", model.start_date, "start", false),
      date_field(
        "Return",
        "flight-return",
        model.return_date,
        "return",
        return_disabled,
      ),
      @tea.div(attrs=[@tea.class_attr("button-row")], [
        @tea.button(
          attrs=if can_book { button_attrs() } else { disabled_button_attrs() },
          events=if can_book { [@tea.on_click(BookFlight)] } else { [] },
          "Book",
        ),
      ]),
      @tea.p(
        attrs=[
          @tea.class_attr(if can_book { "status" } else { "status is-error" }),
        ],
        [@tea.text(model.status)],
      ),
    ]),
  ])
}

///|
fn labeled_select(
  label : String,
  id : String,
  tag : String,
  selected : String,
  options : Array[(String, String)],
) -> @tea.Html[Msg] {
  @tea.node("label", attrs=[@tea.class_attr("field"), @tea.attr("for", id)], [
    @tea.span([@tea.text(label)]),
    @tea.node(
      "select",
      attrs=@tea.Attrs::build().attr("id", id).to_array(),
      events=[@tea.on_change(tag~)],
      options.map(pair => {
        @tea.node("option", attrs=option_attrs(pair.0, pair.0 == selected), [
          @tea.text(pair.1),
        ])
      }),
    ),
  ])
}

///|
fn date_field(
  label : String,
  id : String,
  value : String,
  tag : String,
  disabled : Bool,
) -> @tea.Html[Msg] {
  let attrs = @tea.Attrs::build()
    .attr("id", id)
    .attr("type", "date")
    .value(value)
  let attrs = if disabled { attrs.attr("disabled", "disabled") } else { attrs }
  @tea.node("label", attrs=[@tea.class_attr("field"), @tea.attr("for", id)], [
    @tea.span([@tea.text(label)]),
    @tea.input(
      attrs=attrs.to_array(),
      events=if disabled { [] } else { [@tea.on_change(tag~)] },
    ),
  ])
}

///|
fn option_attrs(value : String, selected : Bool) -> Array[@tea.Attribute] {
  let attrs = @tea.Attrs::build().attr("value", value)
  if selected {
    attrs.attr("selected", "selected").to_array()
  } else {
    attrs.to_array()
  }
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
fn resolve_text_input(
  id : @tea.TextInputId,
  payload : @tea.TextInputPayload,
) -> Msg? {
  match id.name {
    "kind" => Some(SetFlightKind(payload.value))
    "start" => Some(SetStartDate(payload.value))
    "return" => Some(SetReturnDate(payload.value))
    _ => None
  }
}

///|
/// Mounts the Flight Booker task into `host` with its own runtime and browser renderer.
pub fn mount(host : @tea.DomElement) -> Unit {
  let runtime = @incr.Runtime()
  let app = App(runtime)
  let renderer = @tea.BrowserRenderer::BrowserRenderer(runtime)
  ignore(renderer.mount(host, app.program, on_input=resolve_text_input))
}
