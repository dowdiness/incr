///|
priv struct Model {
  count : Int
}

///|
enum Msg {
  Increment
  Reset
} derive(Eq)

///|
priv struct App {
  program : @tea.Program[Msg, @tea.Html[Msg]]
  _state : Ref[Model]
}

///|
fn App::App(runtime : @incr.Runtime) -> App {
  let scope = @incr.Scope::new(runtime)
  let state = Ref({ count: 0 })
  let version = scope.input_field(0, label="7guis.counter.version")
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
    label="7guis.counter.view",
  )
  { program, _state: state }
}

///|
fn update_model(msg : Msg, model : Model) -> Model {
  match msg {
    Increment => { count: model.count + 1 }
    Reset => { count: 0 }
  }
}

///|
fn view_model(model : Model) -> @tea.Html[Msg] {
  @tea.article(attrs=[@tea.class_attr("task-card")], [
    @tea.div(attrs=[@tea.class_attr("task-heading")], [
      @tea.h2([@tea.text("Counter")]),
      @tea.p([@tea.text("Smallest possible model/update/view loop.")]),
    ]),
    @tea.div(attrs=[@tea.class_attr("task-body")], [
      @tea.div(attrs=[@tea.class_attr("counter-readout")], [
        @tea.text("\{model.count}"),
      ]),
      @tea.div(attrs=[@tea.class_attr("button-row")], [
        @tea.button(
          attrs=button_attrs(),
          events=[@tea.on_click(Increment)],
          "Count",
        ),
        @tea.button(
          attrs=button_attrs(),
          events=[@tea.on_click(Reset)],
          "Reset",
        ),
      ]),
    ]),
  ])
}

///|
fn button_attrs() -> Array[@tea.Attribute] {
  @tea.Attrs::build().attr("type", "button").to_array()
}

///|
/// Mounts the Counter task into `host` with its own runtime and browser renderer.
pub fn mount(host : @tea.DomElement) -> Unit {
  let runtime = @incr.Runtime()
  let app = App(runtime)
  let renderer = @tea.BrowserRenderer::BrowserRenderer(runtime)
  ignore(renderer.mount(host, app.program))
}
