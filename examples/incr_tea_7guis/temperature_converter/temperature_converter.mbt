///|
priv struct Model {
  celsius : String
  fahrenheit : String
}

///|
enum Msg {
  SetCelsius(String)
  SetFahrenheit(String)
} derive(Eq)

///|
priv struct App {
  program : @tea.Program[Msg, @tea.Html[Msg]]
  _state : Ref[Model]
}

///|
fn App::App(runtime : @incr.Runtime) -> App {
  let scope = @incr.Scope::new(runtime)
  let state = Ref({ celsius: "0", fahrenheit: "32" })
  let version = scope.input_field(0, label="7guis.temperature.version")
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
    label="7guis.temperature.view",
  )
  { program, _state: state }
}

///|
fn parse_double_or_none(value : String) -> Double? {
  let trimmed = value.trim()
  try @string.parse_double(trimmed) catch {
    _ => None
  } noraise {
    number => Some(number)
  }
}

///|
fn update_model(msg : Msg, model : Model) -> Model {
  match msg {
    SetCelsius(value) =>
      match parse_double_or_none(value) {
        Some(celsius) =>
          {
            celsius: value,
            fahrenheit: (celsius * 9.0 / 5.0 + 32.0).to_string(),
          }
        None => { ..model, celsius: value }
      }
    SetFahrenheit(value) =>
      match parse_double_or_none(value) {
        Some(fahrenheit) =>
          {
            celsius: ((fahrenheit - 32.0) * 5.0 / 9.0).to_string(),
            fahrenheit: value,
          }
        None => { ..model, fahrenheit: value }
      }
  }
}

///|
fn view_model(model : Model) -> @tea.Html[Msg] {
  @tea.article(attrs=[@tea.class_attr("task-card")], [
    @tea.div(attrs=[@tea.class_attr("task-heading")], [
      @tea.h2([@tea.text("Temperature Converter")]),
      @tea.p([@tea.text("Paired text inputs round-trip through payload ids.")]),
    ]),
    @tea.div(attrs=[@tea.class_attr("task-body")], [
      field("Celsius", "temp-celsius", model.celsius, "celsius"),
      field("Fahrenheit", "temp-fahrenheit", model.fahrenheit, "fahrenheit"),
    ]),
  ])
}

///|
fn field(
  label : String,
  id : String,
  value : String,
  tag : String,
) -> @tea.Html[Msg] {
  @tea.node("label", attrs=[@tea.class_attr("field"), @tea.attr("for", id)], [
    @tea.span([@tea.text(label)]),
    @tea.input(
      attrs=@tea.Attrs::build().attr("id", id).value(value).to_array(),
      events=[@tea.on_input(tag~)],
    ),
  ])
}

///|
fn resolve_text_input(
  id : @tea.TextInputId,
  payload : @tea.TextInputPayload,
) -> Msg? {
  match id.name {
    "celsius" => Some(SetCelsius(payload.value))
    "fahrenheit" => Some(SetFahrenheit(payload.value))
    _ => None
  }
}

///|
/// Mounts the Temperature Converter task into `host` with its own runtime and browser renderer.
pub fn mount(host : @tea.DomElement) -> Unit {
  let runtime = @incr.Runtime()
  let app = App(runtime)
  let renderer = @tea.BrowserRenderer::BrowserRenderer(runtime)
  ignore(renderer.mount(host, app.program, on_input=resolve_text_input))
}
