///|
priv struct Model {
  elapsed : Int
  duration : Int
  running : Bool
}

///|
enum Msg {
  Tick
  Reset
  SetDuration(String)
  SetRunning(Bool)
} derive(Eq)

///|
priv struct App {
  program : @tea.Program[Msg, @tea.Html[Msg]]
  _state : Ref[Model]
}

///|
fn App::App(runtime : @incr.Runtime) -> App {
  let scope = @incr.Scope::new(runtime)
  let state = Ref({ elapsed: 0, duration: 10000, running: true })
  let version = scope.input_field(0, label="7guis.timer.version")
  let update : (Msg) -> @tea.Cmd[Msg] = msg => {
    state.val = update_model(msg, state.val)
    version.set(version.peek() + 1)
    @tea.Cmd::none()
  }
  let view : () -> @tea.Html[Msg] raise Failure = () => {
    ignore(version.get())
    view_model(state.val)
  }
  let subscriptions : () -> @tea.Subscriptions[Msg] raise Failure = () => {
    ignore(version.get())
    let subscriptions = @hashmap.HashMap([])
    if state.val.running {
      subscriptions.set(
        @tea.SubKey("7guis", "timer"),
        @tea.SubSpec::Timer(100, Tick),
      )
    }
    subscriptions
  }
  let program = @tea.Program::with_subscriptions(
    runtime,
    scope,
    update,
    view,
    subscriptions,
    label="7guis.timer.view",
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
fn update_model(msg : Msg, model : Model) -> Model {
  match msg {
    Tick =>
      if !model.running {
        model
      } else {
        let elapsed = (model.elapsed + 100).clamp(min=0, max=model.duration)
        { ..model, elapsed, running: elapsed < model.duration }
      }
    Reset => { ..model, elapsed: 0, running: true }
    SetDuration(value) =>
      match parse_int_or_none(value) {
        Some(duration) => {
          let duration = duration.clamp(min=1000, max=30000)
          let elapsed = model.elapsed.clamp(min=0, max=duration)
          { duration, elapsed, running: model.running && elapsed < duration }
        }
        None => model
      }
    SetRunning(value) =>
      { ..model, running: value && model.elapsed < model.duration }
  }
}

///|
fn view_model(model : Model) -> @tea.Html[Msg] {
  let percent = if model.duration == 0 {
    0
  } else {
    model.elapsed * 100 / model.duration
  }
  @tea.article(attrs=[@tea.class_attr("task-card")], [
    @tea.div(attrs=[@tea.class_attr("task-heading")], [
      @tea.h2([@tea.text("Timer")]),
      @tea.p([
        @tea.text("Program::with_subscriptions drives a ticking model field."),
      ]),
    ]),
    @tea.div(attrs=[@tea.class_attr("task-body")], [
      @tea.node(
        "progress",
        attrs=[
          @tea.attr("max", "\{model.duration}"),
          @tea.attr("value", "\{model.elapsed}"),
        ],
        [@tea.text("\{percent}%")],
      ),
      @tea.p(attrs=[@tea.class_attr("status")], [
        @tea.text(
          "Elapsed: \{model.elapsed / 1000}s / \{model.duration / 1000}s",
        ),
      ]),
      @tea.node("label", attrs=[@tea.class_attr("field")], [
        @tea.span([@tea.text("Duration")]),
        @tea.input(
          attrs=@tea.Attrs::build()
            .attr("type", "range")
            .attr("min", "1000")
            .attr("max", "30000")
            .attr("step", "1000")
            .value("\{model.duration}")
            .to_array(),
          events=[@tea.on_input(tag="duration")],
        ),
      ]),
      @tea.div(attrs=[@tea.class_attr("button-row")], [
        if model.running {
          @tea.button(
            attrs=button_attrs(),
            events=[@tea.on_click(SetRunning(false))],
            "Pause",
          )
        } else {
          @tea.button(
            attrs=button_attrs(),
            events=[@tea.on_click(SetRunning(true))],
            "Start",
          )
        },
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
fn resolve_text_input(
  id : @tea.TextInputId,
  payload : @tea.TextInputPayload,
) -> Msg? {
  match id.name {
    "duration" => Some(SetDuration(payload.value))
    _ => None
  }
}

///|
/// Mounts the Timer task into `host` with its own runtime, browser renderer, and timer subscription.
pub fn mount(host : @tea.DomElement) -> Unit {
  let runtime = @incr.Runtime()
  let app = App(runtime)
  let renderer = @tea.BrowserRenderer::BrowserRenderer(runtime)
  ignore(renderer.mount(host, app.program, on_input=resolve_text_input))
}
