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
  let program = @tea.Program::stateful(
    runtime,
    { count: 0 },
    update_model,
    view_model,
    label="7guis.counter.view",
  )
  let renderer = @tea.BrowserRenderer::BrowserRenderer(runtime)
  ignore(renderer.mount(host, program))
}
