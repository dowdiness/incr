///|
fn main {
  @rabbita.new(app()).mount("app")
}

///|
fn app() -> @rabbita.Cell {
  @rabbita.simple_cell(model=init_model(), update~, view~)
}
