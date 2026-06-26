///|
priv struct Model {
  count : Int
  listening : Bool
}

///|
enum Msg {
  Pressed
  ToggleListening
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
  let state = Ref({ count: 0, listening: true })
  let version = scope.input_field(0, label="7guis.keyboard_shortcut.version")
  let listening = scope.input_field(
    true,
    label="7guis.keyboard_shortcut.listening",
  )
  let update : (Msg) -> @tea.Cmd[Msg] = msg => {
    state.val = update_model(msg, state.val)
    version.set(version.peek() + 1)
    listening.set(state.val.listening)
    @tea.Cmd::none()
  }
  let view : () -> @tea.Html[Msg] raise Failure = () => {
    ignore(version.get())
    view_model(state.val)
  }
  let subscriptions : () -> @tea.Subscriptions[Msg] raise Failure = () => {
    let subs = @hashmap.HashMap([])
    if listening.get() {
      subs.set(
        @tea.SubKey("7guis", "keyboard_shortcut"),
        @tea.SubSpec::WindowKeydown("k", Pressed),
      )
    }
    subs
  }
  let program = @tea.Program::with_subscriptions(
    runtime,
    scope,
    update,
    view,
    subscriptions,
    label="7guis.keyboard_shortcut.view",
  )
  { program, _state: state }
}

///|
fn update_model(msg : Msg, model : Model) -> Model {
  match msg {
    Pressed => { ..model, count: model.count + 1 }
    ToggleListening => { ..model, listening: !model.listening }
    Reset => { ..model, count: 0 }
  }
}

///|
fn view_model(model : Model) -> @tea.Html[Msg] {
  @tea.article(attrs=[@tea.class_attr("task-card")], [
    @tea.div(attrs=[@tea.class_attr("task-heading")], [
      @tea.h2([@tea.text("Keyboard Shortcut")]),
      @tea.p([
        @tea.text(
          "WindowKeydown subscription: press \u{201C}k\u{201D} to increment.",
        ),
      ]),
    ]),
    @tea.div(attrs=[@tea.class_attr("task-body")], [
      @tea.div(attrs=[@tea.class_attr("counter-readout")], [
        @tea.text("\{model.count}"),
      ]),
      @tea.p(attrs=[@tea.class_attr("status")], [
        @tea.text(
          if model.listening {
            "Listening — press k"
          } else {
            "Paused"
          },
        ),
      ]),
      @tea.div(attrs=[@tea.class_attr("button-row")], [
        @tea.button(
          attrs=button_attrs(),
          events=[@tea.on_click(ToggleListening)],
          if model.listening {
            "Pause"
          } else {
            "Resume"
          },
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
/// Mounts the Keyboard Shortcut task into `host` with its own runtime and
/// a `WindowKeydown` subscription for the "k" key.
pub fn mount(host : @tea.DomElement) -> Unit {
  let runtime = @incr.Runtime()
  let app = App(runtime)
  let renderer = @tea.BrowserRenderer::BrowserRenderer(runtime)
  ignore(renderer.mount(host, app.program))
}
