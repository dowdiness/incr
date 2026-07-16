///|
priv struct CellEntry {
  id : String
  text : String
}

///|
priv struct Model {
  cells : Array[CellEntry]
}

///|
enum Msg {
  SetCell(String, String)
} derive(Eq)

///|
priv struct App {
  program : @tea.Program[Msg, @tea.Html[Msg]]
  _state : Ref[Model]
}

///|
fn App::App(runtime : @incr.Runtime) -> App {
  let scope = @incr.Scope::new(runtime)
  let state = Ref({ cells: init_cells() })
  let version = scope.input_field(0, label="7guis.cells.version")
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
    label="7guis.cells.view",
  )
  { program, _state: state }
}

///|
fn init_cells() -> Array[CellEntry] {
  [
    for row in 1..<=4 => {
      ["A", "B", "C", "D"].map(column => { id: "\{column}\{row}", text: "" })
    }
  ].flatten()
}

///|
fn update_model(msg : Msg, model : Model) -> Model {
  match msg {
    SetCell(id, text) => { cells: update_cell(model.cells, id, text) }
  }
}

///|
fn update_cell(
  cells : Array[CellEntry],
  id : String,
  text : String,
) -> Array[CellEntry] {
  cells.map(cell => if cell.id == id { { ..cell, text, } } else { cell })
}

///|
fn cell_text(model : Model, id : String) -> String {
  model.cells
  .search_by(cell => cell.id == id)
  .map(index => model.cells[index].text)
  .unwrap_or("")
}

///|
fn cell_value(model : Model, id : String) -> String {
  cell_value_visited(model, id, [])
}

///|
fn cell_value_visited(
  model : Model,
  id : String,
  visited : Array[String],
) -> String {
  if visited.iter().any(seen => seen == id) {
    "#cycle"
  } else {
    let text = cell_text(model, id)
    text
    .strip_prefix("=")
    .map_or(text, ref_id => {
      let next = ref_id.to_owned().trim().to_owned()
      if next.is_empty() {
        ""
      } else {
        cell_value_visited(model, next, [id, ..visited])
      }
    })
  }
}

///|
fn view_model(model : Model) -> @tea.Html[Msg] {
  let rows = [
    for row in 1..<=4 => {
      @tea.div(
        attrs=[@tea.class_attr("cells-row")],
        [
          for column in ["A", "B", "C", "D"] => {
            view_cell(model, "\{column}\{row}")
          }
        ],
      )
    }
  ]
  @tea.article(attrs=[@tea.class_attr("task-card")], [
    @tea.div(attrs=[@tea.class_attr("task-heading")], [
      @tea.h2([@tea.text("Cells")]),
      @tea.p([
        @tea.text(
          "A small spreadsheet-shaped dependency toy; =A1 mirrors another cell.",
        ),
      ]),
    ]),
    @tea.div(attrs=[@tea.class_attr("task-body")], rows),
  ])
}

///|
fn view_cell(model : Model, id : String) -> @tea.Html[Msg] {
  @tea.div(attrs=[@tea.class_attr("mini-cell")], [
    @tea.span(attrs=[@tea.class_attr("cell-id")], [@tea.text(id)]),
    @tea.input(
      attrs=@tea.Attrs::build().value(cell_text(model, id)).to_array(),
      events=[@tea.on_input(tag="cell:\{id}")],
    ),
    @tea.span(attrs=[@tea.class_attr("cell-value")], [
      @tea.text(cell_value(model, id)),
    ]),
  ])
}

///|
fn resolve_value(id : @tea.ValueEventId, payload : @tea.ValuePayload) -> Msg? {
  match id.name {
    [.. "cell:", .. cell] => Some(SetCell(cell.to_owned(), payload.value))
    _ => None
  }
}

///|
/// Mounts the Cells task into `host` with its own runtime and browser renderer.
pub fn mount(host : @tea.DomElement) -> Unit {
  let runtime = @incr.Runtime()
  let app = App(runtime)
  let renderer = @tea.BrowserRenderer::BrowserRenderer(runtime)
  ignore(renderer.mount(host, app.program, on_value=resolve_value))
}
