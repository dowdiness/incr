///|
struct Model {
  scenario : @demo.FixedScenarioViewModel
  current : Int
  selected_cell : String?
  status : String
  error : String?
}

///|
enum Msg {
  NextStep
  PrevStep
  SelectStep(Int)
  SelectCell(String)
}

///|
fn init_model() -> Model {
  let scenario = @demo.fixed_scenario_view_model()
  {
    scenario,
    current: 0,
    selected_cell: Some("A1"),
    status: step_status(0, scenario.steps.length()),
    error: None,
  }
}

///|
fn update(msg : Msg, model : Model) -> Model {
  let total = model.scenario.steps.length()
  match msg {
    NextStep => move_to_step(model, model.current + 1, total)
    PrevStep => move_to_step(model, model.current - 1, total)
    SelectStep(index) => move_to_step(model, index, total)
    SelectCell(cell) =>
      {
        ..model,
        selected_cell: Some(cell),
        status: "Selected cell \{cell}.",
        error: None,
      }
  }
}

///|
fn move_to_step(model : Model, index : Int, total : Int) -> Model {
  if index >= 0 && index < total {
    { ..model, current: index, status: step_status(index, total), error: None }
  } else {
    { ..model, error: Some("The fixed scenario has no step at that position.") }
  }
}

///|
fn current_step(model : Model) -> @demo.WorksheetStepViewModel {
  model.scenario.steps[model.current]
}

///|
fn step_status(index : Int, total : Int) -> String {
  let number = index + 1
  "Showing step \{number} of \{total}."
}
